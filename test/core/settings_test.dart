import 'dart:io';

import 'package:caret_notes/core/model/elements.dart';
import 'package:caret_notes/core/settings.dart';
import 'package:caret_notes/core/tool_prefs.dart';
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

  test('three quick colors by default; the count and a bottom dock are saved', () async {
    expect(const AppSettings().quickColors, 3);
    final dir = await Directory.systemTemp.createTemp('cn_set_');
    final path = '${dir.path}/settings.json';
    await const AppSettings().copyWith(quickColors: 5, toolbarDock: ToolbarDock.bottom).save(path);
    final back = await AppSettings.load(path);
    expect(back.quickColors, 5);
    expect(back.toolbarDock, ToolbarDock.bottom);
    await dir.delete(recursive: true);
  });

  test('the app draws its own title bar unless the system one is chosen', () async {
    expect(const AppSettings().nativeTitleBar, isFalse);
    final dir = await Directory.systemTemp.createTemp('cn_set_');
    final path = '${dir.path}/settings.json';
    await const AppSettings().copyWith(nativeTitleBar: true).save(path);
    expect((await AppSettings.load(path)).nativeTitleBar, isTrue);
    await dir.delete(recursive: true);
  });

  test('update checks are on by default and a skipped version is remembered', () async {
    expect(const AppSettings().checkUpdates, isTrue);
    expect(const AppSettings().skippedVersion, '');
    final dir = await Directory.systemTemp.createTemp('cn_set_');
    final path = '${dir.path}/settings.json';
    await const AppSettings().copyWith(checkUpdates: false, skippedVersion: '1.4.0').save(path);
    final back = await AppSettings.load(path);
    expect(back.checkUpdates, isFalse);
    expect(back.skippedVersion, '1.4.0');
    await dir.delete(recursive: true);
  });

  test('the eraser is partial by default', () {
    expect(const AppSettings().tools.eraserPartial, isTrue);
    expect(AppSettings.fromJson(const {}).tools.eraserPartial, isTrue);
  });

  test('tool options are saved and loaded', () async {
    final dir = await Directory.systemTemp.createTemp('cn_set_');
    final path = '${dir.path}/settings.json';
    const tools = ToolPrefs(
      penKind: ToolKind.pencil,
      penColor: 0xFFD23B3B,
      penWidth: 5.5,
      hlColor: 0xFF00FF00,
      hlWidth: 20,
      eraserPartial: false,
      eraserSize: 22,
      selectMode: SelectMode.lasso,
      textMode: TextMode.box,
    );
    await const AppSettings().copyWith(tools: tools).save(path);
    final back = (await AppSettings.load(path)).tools;
    expect(back, tools);
    await dir.delete(recursive: true);
  });

  test('bad tool values fall back to defaults', () {
    final t = ToolPrefs.fromJson(const {'penKind': 'crayon', 'penWidth': 'x', 'eraserSize': 999});
    expect(t.penKind, const ToolPrefs().penKind);
    expect(t.penWidth, const ToolPrefs().penWidth);
    expect(t.eraserSize, 40);
  });

  test('corrupt settings file falls back to defaults', () async {
    final dir = await Directory.systemTemp.createTemp('cn_set_');
    final path = '${dir.path}/settings.json';
    await File(path).writeAsString('{oops');
    expect((await AppSettings.load(path)).accent, AppSettings.defaultAccent);
    await dir.delete(recursive: true);
  });
}
