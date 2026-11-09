import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart' as win;

/// Moves [from] over [to], replacing it in one step. On Windows Dart's File.rename
/// removes the target first, which a sync client can see as a delete; MoveFileEx
/// with MOVEFILE_REPLACE_EXISTING swaps the file atomically instead.
Future<void> replaceFile(File from, String to) async {
  if (Platform.isWindows) {
    final ok = using((arena) {
      final a = arena.pcwstr(from.absolute.path);
      final b = arena.pcwstr(File(to).absolute.path);
      return win.MoveFileEx(a, b, win.MOVEFILE_REPLACE_EXISTING | win.MOVEFILE_WRITE_THROUGH).value;
    });
    if (ok) return;
    throw FileSystemException('Could not replace file', to);
  }
  await from.rename(to);
}
