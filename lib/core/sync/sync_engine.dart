import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../format/note_codec.dart';
import '../ids.dart';
import '../library/library_store.dart';
import '../merge/note_merge.dart';
import '../model/folder_meta.dart';
import '../model/note.dart';
import 'conflict_copies.dart';
import 'remote_store.dart';

enum Resolution { combine, keepLocal, keepRemote, keepBoth }

/// A note changed on both sides; waits for the user's choice. Blocks only that file.
class PendingConflict {
  final String path;

  /// Where the other version lives remotely: same path, or a sync client's conflict copy.
  final String remotePath;
  final String remoteToken;
  final DateTime detected;
  const PendingConflict(this.path, this.remotePath, this.remoteToken, this.detected);

  Map<String, dynamic> toJson() => {'path': path, 'remote': remotePath, 'token': remoteToken, 'at': detected.toIso8601String()};
  factory PendingConflict.fromJson(Map<String, dynamic> j) =>
      PendingConflict(j['path'] as String, j['remote'] as String, j['token'] as String, DateTime.parse(j['at'] as String));
}

class SyncReport {
  final List<String> uploaded = [], downloaded = [], deletedLocal = [], deletedRemote = [], skipped = [];
  final List<PendingConflict> conflicts = [];
  bool get changedLocal => downloaded.isNotEmpty || deletedLocal.isNotEmpty;
}

class _FileState {
  String hash;
  String token;
  int mtime;
  int size;
  _FileState(this.hash, this.token, this.mtime, this.size);
  Map<String, dynamic> toJson() => {'h': hash, 't': token, 'm': mtime, 's': size};
  factory _FileState.fromJson(Map<String, dynamic> j) => _FileState(j['h'] as String, j['t'] as String, j['m'] as int? ?? 0, j['s'] as int? ?? 0);
}

class _Local {
  final String hash;
  final int mtime, size;
  const _Local(this.hash, this.mtime, this.size);
}

bool isSyncablePath(String path) {
  final parts = path.split('/');
  final name = parts.last;
  if (parts.take(parts.length - 1).any((s) => s.startsWith('.'))) return false;
  return name == FolderMeta.fileName || LibraryStore.isNoteFile(name);
}

/// Reconciles the local library with one remote, using stored base copies for 3-way merges.
/// Nothing is ever hard-deleted: replaced or remotely-deleted notes go to Recently deleted.
class SyncEngine {
  final LibraryStore lib;
  final RemoteStore remote;
  SyncEngine(this.lib, this.remote);

  String get _syncDir => p.join(lib.root, '.sync');
  String get _statePath => p.join(_syncDir, 'state.json');
  String _basePath(String rel) => p.joinAll([_syncDir, 'base', ...rel.split('/')]);

  Map<String, _FileState> _files = {};
  List<PendingConflict> _conflicts = [];
  bool _loaded = false;

  List<PendingConflict> get pendingConflicts => List.unmodifiable(_conflicts);

  bool _cancelled = false;

  /// Stops this engine: a run in progress makes no further changes and saves no state.
  void cancel() => _cancelled = true;
  bool get cancelled => _cancelled;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final j = jsonDecode(await File(_statePath).readAsString()) as Map<String, dynamic>;
      _files = {for (final e in (j['files'] as Map).entries) e.key as String: _FileState.fromJson((e.value as Map).cast<String, dynamic>())};
      _conflicts = [for (final c in j['conflicts'] as List) PendingConflict.fromJson((c as Map).cast<String, dynamic>())];
    } catch (_) {
      _files = {};
      _conflicts = [];
    }
  }

  Future<void> _save() async {
    if (_cancelled) return;
    await Directory(_syncDir).create(recursive: true);
    final tmp = File('$_statePath.tmp');
    await tmp.writeAsString(jsonEncode({
      'files': {for (final e in _files.entries) e.key: e.value.toJson()},
      'conflicts': [for (final c in _conflicts) c.toJson()],
    }));
    await tmp.rename(_statePath);
  }

  /// Forgets all sync history (used when switching provider).
  Future<void> reset() async {
    _files = {};
    _conflicts = [];
    _loaded = true;
    final d = Directory(_syncDir);
    if (await d.exists()) await d.delete(recursive: true);
  }

  static String hashBytes(List<int> b) => sha1.convert(b).toString();

  Future<Map<String, _Local>> _scanLocal() async {
    final out = <String, _Local>{};
    final root = Directory(lib.root);
    if (!await root.exists()) return out;
    await for (final e in root.list(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      final rel = lib.rel(e.path);
      if (!isSyncablePath(rel)) continue;
      final st = await e.stat();
      final mt = st.modified.millisecondsSinceEpoch;
      final prev = _files[rel];
      if (prev != null && prev.mtime == mt && prev.size == st.size) {
        out[rel] = _Local(prev.hash, mt, st.size);
      } else {
        final path = e.path;
        out[rel] = _Local(await Isolate.run(() => hashBytes(File(path).readAsBytesSync())), mt, st.size);
      }
    }
    return out;
  }

  Future<void> _saveBase(String rel, List<int> bytes) async {
    final f = File(_basePath(rel));
    await f.parent.create(recursive: true);
    await f.writeAsBytes(bytes, flush: true);
  }

  Future<Uint8List?> _readBase(String rel) async {
    final f = File(_basePath(rel));
    return await f.exists() ? f.readAsBytes() : null;
  }

  Future<void> _dropBase(String rel) async {
    final f = File(_basePath(rel));
    if (await f.exists()) await f.delete();
  }

  Future<void> _record(String rel, List<int> bytes, String token) async {
    final st = await File(lib.abs(rel)).stat();
    _files[rel] = _FileState(hashBytes(bytes), token, st.modified.millisecondsSinceEpoch, st.size);
    await _saveBase(rel, bytes);
  }

  bool _validRemote(String rel, Uint8List bytes) {
    if (rel.endsWith(FolderMeta.fileName)) {
      try {
        jsonDecode(utf8.decode(bytes));
        return true;
      } catch (_) {
        return false;
      }
    }
    return isValidNoteFile(bytes);
  }

  /// [isOpen] is asked per file, right before touching it, so a note opened in the editor
  /// while sync runs is left alone.
  Future<SyncReport> run({Set<String> exclude = const {}, bool Function(String path)? isOpen}) async {
    bool skip(String path) => exclude.contains(path) || (isOpen?.call(path) ?? false);
    await load();
    if (_cancelled) return SyncReport();
    final report = SyncReport();
    final local = await _scanLocal();
    final listing = await remote.listAll();

    final remoteFiles = <String, RemoteEntry>{};
    final copies = <String, (String, RemoteEntry)>{}; // copyPath -> (original, entry)
    final names = {for (final e in listing) e.path};
    for (final e in listing) {
      if (!isSyncablePath(e.path)) continue;
      final orig = conflictOriginal(e.path);
      if (orig != null && (names.contains(orig) || local.containsKey(orig)) && await _sameNote(e.path, orig, local.containsKey(orig))) {
        copies[e.path] = (orig, e);
      } else {
        remoteFiles[e.path] = e;
      }
    }
    // OneDrive-style "Name-HOST.cnote": only a copy if it holds the same note.
    for (final e in remoteFiles.values.toList()) {
      if (_files.containsKey(e.path) || local.containsKey(e.path) || !e.path.endsWith(noteExtension)) continue;
      final orig = maybeHostSuffixCopy(e.path);
      if (orig == null || !local.containsKey(orig)) continue;
      try {
        final theirs = readNoteMeta(await remote.read(e.path))?['id'];
        final ours = readNoteMeta(await File(lib.abs(orig)).readAsBytes())?['id'];
        if (theirs != null && theirs == ours) {
          remoteFiles.remove(e.path);
          copies[e.path] = (orig, e);
        }
      } catch (_) {}
    }

    final blocked = {for (final c in _conflicts) c.path, for (final c in _conflicts) c.remotePath};
    // Notes first, folder settings last: a folder that still holds notes keeps its settings.
    final all = {...local.keys, ...remoteFiles.keys, ..._files.keys}.toList()
      ..sort((a, b) => (a.endsWith(FolderMeta.fileName) ? 1 : 0).compareTo(b.endsWith(FolderMeta.fileName) ? 1 : 0));
    for (final path in all) {
      if (_cancelled) return report;
      if (skip(path) || blocked.contains(path)) continue;
      try {
        await _syncOne(path, local[path], remoteFiles[path], report, () => skip(path) || _cancelled);
      } on RemoteException {
        rethrow;
      } catch (e) {
        report.skipped.add(path);
      }
    }

    for (final e in copies.entries) {
      final (orig, entry) = e.value;
      if (_cancelled) return report;
      if (blocked.contains(e.key) || skip(orig)) continue;
      if (!await File(lib.abs(orig)).exists()) continue;
      final bytes = await remote.read(e.key);
      if (!_validRemote(e.key, bytes)) {
        report.skipped.add(e.key);
        continue;
      }
      if (hashBytes(bytes) == local[orig]?.hash) {
        await remote.delete(e.key); // identical copy: just clean it up
        continue;
      }
      final c = PendingConflict(orig, e.key, entry.token, DateTime.now().toUtc());
      _conflicts.add(c);
      report.conflicts.add(c);
    }

    await _pruneEmptyDirs(Directory(lib.root));
    await _save();
    return report;
  }

  /// True when [copyPath] holds the same note (same note id) as [orig]. Folder settings
  /// files have no id; a "conflict" copy of one is trusted by name.
  Future<bool> _sameNote(String copyPath, String orig, bool origIsLocal) async {
    if (!copyPath.endsWith(noteExtension)) return true;
    try {
      final theirs = readNoteMeta(await remote.read(copyPath))?['id'];
      final ours = readNoteMeta(origIsLocal ? await File(lib.abs(orig)).readAsBytes() : await remote.read(orig))?['id'];
      return theirs != null && theirs == ours;
    } catch (_) {
      return false;
    }
  }

  Future<void> _syncOne(String path, _Local? l, RemoteEntry? r, SyncReport report, bool Function() handsOff) async {
    final s = _files[path];
    final isMeta = path.endsWith(FolderMeta.fileName);

    Future<void> upload() async {
      final bytes = await File(lib.abs(path)).readAsBytes();
      final token = await remote.write(path, bytes);
      await _record(path, bytes, token);
      report.uploaded.add(path);
    }

    Future<bool> download() async {
      final bytes = await remote.read(path);
      if (handsOff()) return false; // opened in the editor meanwhile
      if (!_validRemote(path, bytes)) {
        report.skipped.add(path);
        return false;
      }
      await lib.writeBytesAtomic(path, bytes);
      await _record(path, bytes, r!.token);
      report.downloaded.add(path);
      return true;
    }

    Future<void> deleteLocal() async {
      if (handsOff()) return;
      if (isMeta) {
        if (await _folderHasNotes(dirOfRel(path))) return upload(); // folder restored with its settings
        final f = File(lib.abs(path));
        if (await f.exists()) await f.delete();
      } else {
        await lib.trashItem(path, reason: 'Deleted on another device');
      }
      _files.remove(path);
      await _dropBase(path);
      report.deletedLocal.add(path);
    }

    Future<void> deleteRemote() async {
      await remote.delete(path);
      _files.remove(path);
      await _dropBase(path);
      report.deletedRemote.add(path);
    }

    Future<void> bothPresent() async {
      final rb = await remote.read(path);
      final lb = await File(lib.abs(path)).readAsBytes();
      if (hashBytes(rb) == hashBytes(lb)) {
        await _record(path, lb, r!.token);
        return;
      }
      if (!_validRemote(path, rb)) {
        report.skipped.add(path);
        return;
      }
      if (isMeta) {
        // folder settings: the newer one wins automatically
        DateTime mod(Uint8List b) {
          try {
            return FolderMeta.fromJson(jsonDecode(utf8.decode(b)) as Map<String, dynamic>).modified ?? DateTime(2000);
          } catch (_) {
            return DateTime(2000);
          }
        }

        if (mod(rb).isAfter(mod(lb))) {
          await lib.writeBytesAtomic(path, rb);
          await _record(path, rb, r!.token);
          report.downloaded.add(path);
        } else {
          final t = await remote.write(path, lb);
          await _record(path, lb, t);
          report.uploaded.add(path);
        }
        return;
      }
      final c = PendingConflict(path, path, r!.token, DateTime.now().toUtc());
      _conflicts.add(c);
      report.conflicts.add(c);
    }

    if (s == null) {
      if (l != null && r != null) return bothPresent();
      if (l != null) return upload();
      if (r != null) {
        await download();
        return;
      }
      return;
    }
    final lChanged = l?.hash != s.hash;
    final rChanged = r?.token != s.token;
    if (!lChanged && !rChanged) {
      if (l == null && r == null) _files.remove(path);
      return;
    }
    if (lChanged && !rChanged) {
      if (l == null) return r == null ? _dropState(path) : deleteRemote();
      return upload();
    }
    if (!lChanged && rChanged) {
      if (r == null) return l == null ? _dropState(path) : deleteLocal();
      await download();
      return;
    }
    // both changed
    if (l == null && r == null) return _dropState(path);
    if (l == null) {
      await download(); // deleted here, edited there: the edit survives
      return;
    }
    if (r == null) return upload(); // edited here, deleted there: the edit survives
    return bothPresent();
  }

  Future<bool> _folderHasNotes(String relDir) async {
    final d = Directory(lib.abs(relDir));
    if (!await d.exists()) return false;
    await for (final e in d.list(recursive: true)) {
      if (e is File && LibraryStore.isNoteFile(p.basename(e.path))) return true;
    }
    return false;
  }

  Future<void> _dropState(String path) async {
    _files.remove(path);
    await _dropBase(path);
  }

  Future<void> _pruneEmptyDirs(Directory d) async {
    await for (final e in d.list()) {
      if (e is Directory && !p.basename(e.path).startsWith('.')) {
        await _pruneEmptyDirs(e);
        try {
          if (await e.list().isEmpty) await e.delete();
        } catch (_) {}
      }
    }
  }

  /// Applies the user's choice for a conflict.
  Future<void> resolve(PendingConflict c, Resolution how) async {
    await load();
    final localFile = File(lib.abs(c.path));
    final localBytes = await localFile.exists() ? await localFile.readAsBytes() : null;
    final remoteBytes = await remote.read(c.remotePath);
    late Uint8List finalBytes;
    late String token;

    switch (how) {
      case Resolution.combine:
        if (localBytes == null) {
          finalBytes = remoteBytes;
        } else {
          final baseBytes = await _readBase(c.path);
          Note? base;
          try {
            base = baseBytes == null ? null : decodeNote(baseBytes);
          } catch (_) {}
          final merged = mergeNotes(base: base, local: decodeNote(localBytes), remote: decodeNote(remoteBytes));
          finalBytes = encodeNote(merged.copyWith(modified: DateTime.now().toUtc()), thumb: readThumb(localBytes));
        }
        await lib.writeBytesAtomic(c.path, finalBytes);
        token = await remote.write(c.path, finalBytes);
      case Resolution.keepLocal:
        await lib.trashBytes(c.path, remoteBytes, reason: 'Other version from a sync conflict');
        finalBytes = localBytes ?? remoteBytes;
        if (localBytes == null) await lib.writeBytesAtomic(c.path, finalBytes);
        token = await remote.write(c.path, finalBytes);
      case Resolution.keepRemote:
        if (localBytes != null) await lib.trashItem(c.path, reason: 'Replaced in a sync conflict');
        finalBytes = remoteBytes;
        await lib.writeBytesAtomic(c.path, finalBytes);
        token = c.remotePath == c.path ? c.remoteToken : await remote.write(c.path, finalBytes);
      case Resolution.keepBoth:
        final other = decodeNote(remoteBytes);
        final now = DateTime.now().toUtc();
        final copy = Note(
          id: newId(),
          title: '${other.title} (${other.modifiedBy.isEmpty ? 'other device' : other.modifiedBy} copy)',
          layout: other.layout,
          paper: other.paper,
          landscape: other.landscape,
          template: other.template,
          pages: other.pages,
          created: now,
          modified: now,
          modifiedBy: other.modifiedBy,
          favorite: other.favorite,
          assets: other.assets,
        );
        await lib.createNote(dirOfRel(c.path), copy, thumb: readThumb(remoteBytes));
        finalBytes = localBytes ?? remoteBytes;
        if (localBytes == null) await lib.writeBytesAtomic(c.path, finalBytes);
        token = await remote.write(c.path, finalBytes);
    }

    if (c.remotePath != c.path) await remote.delete(c.remotePath);
    await _record(c.path, finalBytes, token);
    _conflicts.removeWhere((x) => x.path == c.path && x.remotePath == c.remotePath);
    await _save();
  }
}
