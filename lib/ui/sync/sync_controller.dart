import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../../core/format/note_codec.dart';
import '../../core/library/library_store.dart';
import '../../core/settings.dart';
import '../../core/sync/folder_remote.dart';
import '../../core/sync/gdrive_remote.dart';
import '../../core/sync/remote_store.dart';
import '../../core/sync/secret_store.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/sync/webdav_remote.dart';
import '../controllers.dart';

enum SyncStatus { disabled, idle, syncing, offline, error }

class ConflictSide {
  final String title;
  final String device;
  final DateTime modified;
  final Uint8List? thumb;
  const ConflictSide(this.title, this.device, this.modified, this.thumb);
}

class SyncController extends ChangeNotifier {
  final LibraryStore store;
  final SettingsController settings;
  final LibraryController library;
  final SecretStore secrets;
  late final GoogleAuth google = GoogleAuth(secrets);

  SyncController({required this.store, required this.settings, required this.library, required this.secrets}) {
    settings.addListener(_onSettings);
    _key = _configKey(settings.value);
    _timer = Timer.periodic(const Duration(minutes: 3), (_) => syncNow(quiet: true));
  }

  SyncStatus status = SyncStatus.disabled;
  DateTime? lastSync;
  String? lastError;
  List<PendingConflict> conflicts = const [];
  String? openNote;

  SyncEngine? _engine;
  String _key = '';
  Timer? _timer;
  Future<void>? _running;
  bool _again = false;

  bool get enabled => settings.value.syncProvider != SyncProvider.none;

  static String _configKey(AppSettings s) =>
      '${s.syncProvider.name}|${s.syncConfig['path'] ?? ''}|${s.syncConfig['url'] ?? ''}|${s.syncConfig['user'] ?? ''}';

  void _onSettings() {
    final k = _configKey(settings.value);
    if (k == _key) return;
    _key = k;
    _engine = null;
    status = enabled ? SyncStatus.idle : SyncStatus.disabled;
    notifyListeners();
    _switchedProvider().then((_) => syncNow());
  }

  /// Switching provider starts fresh: the library is uploaded to the new place
  /// (and merged with anything already there).
  Future<void> _switchedProvider() async {
    final marker = File(p.join(store.root, '.sync', 'provider.txt'));
    final old = await marker.exists() ? await marker.readAsString() : null;
    if (old != _key) {
      await SyncEngine(store, FolderRemote(store.root)).reset();
      await marker.parent.create(recursive: true);
      await marker.writeAsString(_key);
    }
  }

  Future<RemoteStore?> _remote() async {
    final s = settings.value;
    switch (s.syncProvider) {
      case SyncProvider.none:
        return null;
      case SyncProvider.folder:
        final path = s.syncConfig['path'];
        if (path == null || path.isEmpty) throw RemoteException('Choose a sync folder in Settings → Sync.');
        if (p.isWithin(path, store.root) || p.isWithin(store.root, path) || p.equals(path, store.root)) {
          throw RemoteException('The sync folder can\'t be inside the app\'s own library folder.');
        }
        return FolderRemote(path);
      case SyncProvider.webdav:
        final url = s.syncConfig['url'];
        if (url == null || url.isEmpty) throw RemoteException('Enter the WebDAV address in Settings → Sync.');
        return WebDavRemote(url, s.syncConfig['user'] ?? '', await secrets.read('webdav-password') ?? '');
      case SyncProvider.gdrive:
        final id = s.syncConfig['clientId'] ?? '';
        if (id.isEmpty) throw RemoteException('Add your Google client ID in Settings → Sync.');
        final client = await google.client(id, s.syncConfig['clientSecret'] ?? '');
        if (client == null) throw RemoteException('Sign in to Google Drive in Settings → Sync.');
        return GDriveRemote(drive.DriveApi(client));
    }
  }

  Future<SyncEngine?> _getEngine() async {
    if (_engine != null) return _engine;
    final r = await _remote();
    if (r == null) return null;
    await _switchedProvider();
    final e = SyncEngine(store, r);
    await e.load();
    return _engine = e;
  }

  void noteOpened(String relPath) => openNote = relPath;

  void noteClosed(String relPath) {
    if (openNote == relPath) openNote = null;
    syncNow(quiet: true);
  }

  Future<void> start() async {
    status = enabled ? SyncStatus.idle : SyncStatus.disabled;
    notifyListeners();
    await syncNow(quiet: true);
  }

  Future<void> syncNow({bool quiet = false}) {
    if (!enabled) {
      status = SyncStatus.disabled;
      notifyListeners();
      return Future.value();
    }
    if (_running != null) {
      _again = true;
      return _running!;
    }
    return _running = _run().whenComplete(() {
      _running = null;
      if (_again) {
        _again = false;
        syncNow(quiet: true);
      }
    });
  }

  Future<void> _run() async {
    status = SyncStatus.syncing;
    notifyListeners();
    try {
      final e = await _getEngine();
      if (e == null) {
        status = SyncStatus.disabled;
        return;
      }
      final r = await e.run(exclude: {if (openNote != null) openNote!});
      conflicts = e.pendingConflicts;
      lastSync = DateTime.now();
      lastError = null;
      status = SyncStatus.idle;
      if (r.changedLocal || r.conflicts.isNotEmpty) await library.refresh();
    } on RemoteException catch (e) {
      lastError = e.message;
      status = e.offline ? SyncStatus.offline : SyncStatus.error;
      if (!e.offline) _engine = null;
    } catch (e) {
      lastError = '$e';
      status = SyncStatus.error;
      _engine = null;
    } finally {
      notifyListeners();
    }
  }

  Future<(ConflictSide, ConflictSide)> preview(PendingConflict c) async {
    final e = await _getEngine();
    final lb = await File(store.abs(c.path)).readAsBytes();
    final rb = await e!.remote.read(c.remotePath);
    ConflictSide side(Uint8List b, String fallback) {
      final m = readNoteMeta(b);
      final dev = m?['modifiedBy'] as String?;
      return ConflictSide(
        m?['title'] as String? ?? fallback,
        dev != null && dev.isNotEmpty ? dev : fallback,
        DateTime.tryParse(m?['modified'] as String? ?? '') ?? DateTime.now(),
        readThumb(b),
      );
    }

    return (side(lb, 'This device'), side(rb, 'Other device'));
  }

  Future<void> resolve(PendingConflict c, Resolution how) async {
    final e = await _getEngine();
    if (e == null) return;
    await e.resolve(c, how);
    conflicts = e.pendingConflicts;
    notifyListeners();
    await library.refresh();
  }

  Future<void> signInGoogle() async {
    final s = settings.value;
    await google.signIn(s.syncConfig['clientId'] ?? '', s.syncConfig['clientSecret'] ?? '',
        (url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication));
    _engine = null;
    notifyListeners();
    await syncNow();
  }

  Future<void> signOutGoogle() async {
    await google.signOut();
    _engine = null;
    notifyListeners();
  }

  Future<void> setWebDavPassword(String pw) async {
    await secrets.write('webdav-password', pw);
    _engine = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    settings.removeListener(_onSettings);
    super.dispose();
  }
}
