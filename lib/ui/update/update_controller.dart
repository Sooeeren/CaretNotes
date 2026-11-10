import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../../core/update/install_kind.dart';
import '../../core/update/update_check.dart';
import '../../core/version.dart';
import '../controllers.dart';
import '../window_chrome.dart';

/// Checks GitHub for a newer CaretNotes and installs it: the Windows installer runs
/// silently and the AppImage replaces itself; other copies open the right download.
class UpdateController extends ChangeNotifier {
  final SettingsController settings;
  final http.Client client;
  final InstallKind kind;

  UpdateController({required this.settings, http.Client? client, InstallKind? kind})
      : client = client ?? http.Client(),
        kind = kind ?? detectInstallKind();

  static final current = AppVersion.parse(appVersion);

  bool checking = false;
  ReleaseInfo? available;
  String? error;

  /// 0..1 while a download runs, null otherwise.
  double? progress;

  Future<ReleaseInfo?> check() async {
    if (checking) return available;
    checking = true;
    error = null;
    notifyListeners();
    try {
      available = await UpdateChecker(client: client, current: current).check();
    } on UpdateException catch (e) {
      error = e.message;
    } finally {
      checking = false;
      notifyListeners();
    }
    return available;
  }

  /// The quiet check on start: only reports a release the user hasn't skipped.
  Future<ReleaseInfo?> startupCheck() async {
    if (!settings.value.checkUpdates) return null;
    final r = await check();
    if (r == null || settings.value.skippedVersion == r.version.toString()) return null;
    return r;
  }

  Future<void> skip(ReleaseInfo r) => settings.update((s) => s.copyWith(skippedVersion: r.version.toString()));

  /// What the primary button does for this kind of install.
  bool get selfUpdates => kind.selfUpdates;

  /// Updates in place (then the app closes and the new one starts), or opens the right
  /// download. Throws [UpdateException] with a plain message when something fails.
  Future<void> install(ReleaseInfo r) async {
    final asset = r.assetFor(kind);
    if (!kind.selfUpdates || asset == null) {
      await launchUrl(Uri.parse(asset?.url ?? r.pageUrl), mode: LaunchMode.externalApplication);
      return;
    }
    final bytes = await _download(asset);
    switch (kind) {
      case InstallKind.windowsInstaller:
        final dir = await Directory.systemTemp.createTemp('caretnotes-update-');
        final file = File(p.join(dir.path, asset.name));
        await file.writeAsBytes(bytes, flush: true);
        // The installer closes CaretNotes if it's still running and starts the new version.
        await Process.start(file.path, ['/SILENT', '/SUPPRESSMSGBOXES', '/NORESTART'], mode: ProcessStartMode.detached);
      case InstallKind.appImage:
        final target = Platform.environment['APPIMAGE']!;
        final tmp = File('$target.new');
        await tmp.writeAsBytes(bytes, flush: true);
        await Process.run('chmod', ['755', tmp.path]);
        await tmp.rename(target);
        await Process.start(target, const [], mode: ProcessStartMode.detached);
      default:
        return;
    }
    // Close like the window's close button, so open notes are saved first.
    await WindowChrome.requestClose();
  }

  Future<List<int>> _download(ReleaseAsset asset) async {
    progress = 0;
    notifyListeners();
    try {
      final res = await client.send(http.Request('GET', Uri.parse(asset.url)));
      if (res.statusCode != 200) throw UpdateException('Download failed (${res.statusCode})');
      final bytes = <int>[];
      await for (final chunk in res.stream) {
        bytes.addAll(chunk);
        if (asset.size > 0) {
          progress = bytes.length / asset.size;
          notifyListeners();
        }
      }
      if (!asset.matches(bytes)) throw UpdateException('The download was damaged (checksum does not match). Nothing was changed.');
      return bytes;
    } on UpdateException {
      rethrow;
    } catch (e) {
      throw UpdateException('Download failed ($e)');
    } finally {
      progress = null;
      notifyListeners();
    }
  }

  /// A short hint for copies that can't replace themselves.
  String? get manualHint => switch (kind) {
        InstallKind.windowsPortable =>
          'This is the portable CaretNotes, so it can\'t update itself. Download the new version, or use the installer to get automatic updates.',
        InstallKind.deb || InstallKind.rpm => 'Open the downloaded package to install it, or install it with your package manager.',
        InstallKind.arch => 'Install the downloaded package with: sudo pacman -U <file>',
        InstallKind.android => 'Open the downloaded APK to install it.',
        InstallKind.other => 'Download the version for your system from the release page.',
        _ => null,
      };

  @override
  void dispose() {
    client.close();
    super.dispose();
  }
}
