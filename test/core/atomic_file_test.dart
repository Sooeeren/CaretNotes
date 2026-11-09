import 'dart:io';

import 'package:caret_notes/core/atomic_file.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('replaceFile swaps the temp file over an existing target', () async {
    final dir = await Directory.systemTemp.createTemp('cn_atomic_');
    final target = File('${dir.path}/note.cnote')..writeAsStringSync('old');
    final temp = File('${dir.path}/note.cnote.tmp')..writeAsStringSync('new');
    await replaceFile(temp, target.path);
    expect(target.readAsStringSync(), 'new');
    expect(temp.existsSync(), isFalse);
    await dir.delete(recursive: true);
  });

  test('replaceFile also works when the target does not exist yet', () async {
    final dir = await Directory.systemTemp.createTemp('cn_atomic_');
    final temp = File('${dir.path}/a.tmp')..writeAsStringSync('x');
    await replaceFile(temp, '${dir.path}/a.cnote');
    expect(File('${dir.path}/a.cnote').readAsStringSync(), 'x');
    await dir.delete(recursive: true);
  });
}
