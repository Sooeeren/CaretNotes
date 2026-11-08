import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart' as win;

/// Stores small secrets (refresh tokens, passwords) on disk.
/// Windows: encrypted with DPAPI, so only this Windows user can read them.
class SecretStore {
  final String dir;
  SecretStore(this.dir);

  File _file(String key) => File(p.join(dir, '${key.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}.secret'));

  Future<void> write(String key, String value) async {
    await Directory(dir).create(recursive: true);
    final data = utf8.encode(value);
    await _file(key).writeAsBytes(Platform.isWindows ? _protect(Uint8List.fromList(data), true) : data, flush: true);
  }

  Future<String?> read(String key) async {
    final f = _file(key);
    if (!await f.exists()) return null;
    try {
      final raw = await f.readAsBytes();
      return utf8.decode(Platform.isWindows ? _protect(raw, false) : raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> delete(String key) async {
    final f = _file(key);
    if (await f.exists()) await f.delete();
  }

  static Uint8List _protect(Uint8List data, bool encrypt) {
    return using((arena) {
      final input = arena<win.CRYPT_INTEGER_BLOB>();
      final buf = arena<Uint8>(data.isEmpty ? 1 : data.length);
      buf.asTypedList(data.length).setAll(0, data);
      input.ref
        ..cbData = data.length
        ..pbData = buf;
      final output = arena<win.CRYPT_INTEGER_BLOB>();
      final ok = encrypt
          ? win.CryptProtectData(input, nullptr, nullptr, nullptr, nullptr, 0, output)
          : win.CryptUnprotectData(input, nullptr, nullptr, nullptr, nullptr, 0, output);
      if (ok == 0) throw StateError('DPAPI failed');
      final out = Uint8List.fromList(output.ref.pbData.asTypedList(output.ref.cbData));
      win.LocalFree(output.ref.pbData);
      return out;
    });
  }
}
