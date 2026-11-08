import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../atomic_file.dart';
import '../ids.dart';
import 'remote_store.dart';

/// A folder kept in sync by a desktop client (Proton Drive, OneDrive, Dropbox…).
/// Writes go through a hidden temp file + rename so the client never uploads half a note.
class FolderRemote implements RemoteStore {
  final String root;
  FolderRemote(this.root);

  @override
  String get displayName => 'Synced folder';

  String _abs(String rel) => p.joinAll([root, ...rel.split('/')]);

  /// Temp/lock/partial files that sync clients and editors leave around.
  static bool isJunk(String name) {
    final n = name.toLowerCase();
    if (n.startsWith('.') && n != '.folder.json') return true;
    return n.startsWith('~') ||
        n.endsWith('.tmp') ||
        n.endsWith('.partial') ||
        n.endsWith('.crdownload') ||
        n.endsWith('.part') ||
        n.contains('.~cn-') ||
        n == 'desktop.ini' ||
        n == 'thumbs.db';
  }

  @override
  Future<List<RemoteEntry>> listAll() async {
    final dir = Directory(root);
    if (!await dir.exists()) {
      try {
        await dir.create(recursive: true);
      } catch (e) {
        throw RemoteException('The sync folder "$root" is not available.', offline: true);
      }
      return [];
    }
    final out = <RemoteEntry>[];
    await for (final e in dir.list(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      final rel = p.relative(e.path, from: root).replaceAll('\\', '/');
      final parts = rel.split('/');
      if (parts.take(parts.length - 1).any((s) => s.startsWith('.'))) continue;
      if (isJunk(parts.last)) continue;
      try {
        final st = await e.stat();
        out.add(RemoteEntry(rel, '${st.modified.millisecondsSinceEpoch}:${st.size}', st.size));
      } catch (_) {
        // file vanished while listing
      }
    }
    return out;
  }

  @override
  Future<Uint8List> read(String path) async {
    try {
      return await File(_abs(path)).readAsBytes();
    } on FileSystemException catch (e) {
      throw RemoteException('Could not read $path: ${e.message}');
    }
  }

  @override
  Future<String> write(String path, Uint8List data) async {
    final target = File(_abs(path));
    await target.parent.create(recursive: true);
    final tmp = File(p.join(target.parent.path, '.~cn-${newId().substring(0, 8)}.tmp'));
    await tmp.writeAsBytes(data, flush: true);
    // Rename replaces the target atomically; never delete first (a sync client could
    // propagate the delete, and a failure after it would lose the note).
    try {
      await replaceFile(tmp, target.path);
    } on FileSystemException {
      await tmp.copy(target.path);
      await tmp.delete();
    }
    final st = await target.stat();
    return '${st.modified.millisecondsSinceEpoch}:${st.size}';
  }

  @override
  Future<void> delete(String path) async {
    final f = File(_abs(path));
    if (await f.exists()) await f.delete();
    // remove now-empty parent folders (but never the root)
    var d = f.parent;
    while (p.isWithin(root, d.path)) {
      try {
        if (await d.list().isEmpty) {
          await d.delete();
          d = d.parent;
        } else {
          break;
        }
      } catch (_) {
        break;
      }
    }
  }
}
