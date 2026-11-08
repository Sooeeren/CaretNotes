import 'dart:typed_data';

/// One file in the remote library. [token] changes whenever the content changes
/// (ETag, md5, or mtime+size), so sync can tell what changed since last time.
class RemoteEntry {
  final String path;
  final String token;
  final int size;
  const RemoteEntry(this.path, this.token, this.size);
}

/// A cloud location holding a copy of the library. Paths are relative, '/'-separated.
abstract class RemoteStore {
  String get displayName;
  Future<List<RemoteEntry>> listAll();
  Future<Uint8List> read(String path);

  /// Writes (creating parent folders) and returns the new token.
  Future<String> write(String path, Uint8List data);
  Future<void> delete(String path);
}

class RemoteException implements Exception {
  final String message;
  final bool offline;
  RemoteException(this.message, {this.offline = false});
  @override
  String toString() => message;
}
