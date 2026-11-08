import 'dart:typed_data';

import 'remote_store.dart';

/// In-memory remote, used by tests.
class MemoryRemote implements RemoteStore {
  final Map<String, (Uint8List, int)> files = {};
  int _v = 0;

  @override
  String get displayName => 'Memory';

  @override
  Future<List<RemoteEntry>> listAll() async =>
      [for (final e in files.entries) RemoteEntry(e.key, 'v${e.value.$2}', e.value.$1.length)];

  @override
  Future<Uint8List> read(String path) async {
    final f = files[path];
    if (f == null) throw RemoteException('not found: $path');
    return f.$1;
  }

  @override
  Future<String> write(String path, Uint8List data) async {
    _v++;
    files[path] = (Uint8List.fromList(data), _v);
    return 'v$_v';
  }

  @override
  Future<void> delete(String path) async => files.remove(path);
}
