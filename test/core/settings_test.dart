import 'dart:io';

import 'package:caret_notes/core/settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('defaults match the spec', () {
    const s = AppSettings();
    expect(s.toolbarDock, ToolbarDock.top);
    expect(s.accent, AppSettings.defaultAccent);
    expect(s.theme, ThemePref.system);
    expect(s.fingerDrawing, isFalse);
    expect(s.sideButton, SideButtonAction.eraser);
  });

  test('save and load round-trip, missing file gives defaults', () async {
    final dir = await Directory.systemTemp.createTemp('cn_set_');
    final path = '${dir.path}/settings.json';
    expect((await AppSettings.load(path)).toolbarDock, ToolbarDock.top);
    await const AppSettings(toolbarDock: ToolbarDock.left, syncProvider: SyncProvider.folder, syncConfig: {'path': 'C:/x'})
        .save(path);
    final back = await AppSettings.load(path);
    expect(back.toolbarDock, ToolbarDock.left);
    expect(back.syncConfig['path'], 'C:/x');
    await dir.delete(recursive: true);
  });

  test('corrupt settings file falls back to defaults', () async {
    final dir = await Directory.systemTemp.createTemp('cn_set_');
    final path = '${dir.path}/settings.json';
    await File(path).writeAsString('{oops');
    expect((await AppSettings.load(path)).accent, AppSettings.defaultAccent);
    await dir.delete(recursive: true);
  });
}
