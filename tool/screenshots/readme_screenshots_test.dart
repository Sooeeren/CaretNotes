// Renders the README screenshots from the real app widgets, with the real Windows fonts.
//
//   flutter test tool/screenshots/readme_screenshots_test.dart
//
// Writes docs/screenshots/*.png. Windows only (it loads fonts from C:\Windows\Fonts).
// Not part of the normal test suite (it lives outside test/).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:caret_notes/core/geometry.dart';
import 'package:caret_notes/core/library/library_store.dart';
import 'package:caret_notes/core/model/folder_meta.dart';
import 'package:caret_notes/core/model/note.dart';
import 'package:caret_notes/core/model/page.dart';
import 'package:caret_notes/core/settings.dart';
import 'package:caret_notes/ui/app.dart';
import 'package:caret_notes/ui/controllers.dart';
import 'package:caret_notes/core/model/elements.dart';
import 'package:caret_notes/ui/editor/canvas_view.dart';
import 'package:caret_notes/ui/editor/editor_screen.dart';
import 'package:caret_notes/ui/editor/painters.dart';
import 'package:caret_notes/ui/editor/template_dialog.dart';
import 'package:caret_notes/ui/editor/tool_options.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'demo_library.dart';

const _logical = Size(1360, 850);
const _dpr = 1.5;
final _root = GlobalKey();

Future<void> _font(String family, List<String> files) async {
  final l = FontLoader(family);
  for (final f in files) {
    final bytes = File(f).readAsBytesSync();
    l.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await l.load();
}

Future<void> _loadFonts() async {
  const w = r'C:\Windows\Fonts';
  final ui = ['$w\\segoeui.ttf', '$w\\seguisb.ttf', '$w\\segoeuib.ttf', '$w\\segoeuii.ttf', '$w\\segoeuiz.ttf'];
  for (final fam in ['Segoe UI Variable Text', 'Segoe UI Variable Display', 'Segoe UI', 'Roboto']) {
    await _font(fam, ui);
  }
  await _font('Consolas', ['$w\\consola.ttf', '$w\\consolab.ttf']);
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? r'C:\src\flutter';
  await _font('MaterialIcons', [p.join(flutterRoot, 'bin', 'cache', 'artifacts', 'material_fonts', 'materialicons-regular.otf')]);
}

class _Env {
  final Directory dir;
  final LibraryStore store;
  final LibraryController lib;
  final SettingsController settings;
  final Map<String, String> notes;
  _Env(this.dir, this.store, this.lib, this.settings, this.notes);

  Widget app() => RepaintBoundary(
        key: _root,
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: settings),
            ChangeNotifierProvider.value(value: lib),
            Provider<LibraryStore>.value(value: store),
          ],
          child: const CaretNotesApp(),
        ),
      );
}

Future<Uint8List?> _thumb(Note n) => renderThumbnail(n, const RenderAssets());

Future<_Env> _library({ThemePref theme = ThemePref.light}) async {
  debugDisableShadows = false; // tests draw shadows as black outlines by default; _shot restores it
  final dir = await Directory.systemTemp.createTemp('cn_shots_');
  final store = LibraryStore(p.join(dir.path, 'library'));
  await store.ensureRoot();
  final sem = await store.createFolder('', 'Semester 3', const FolderMeta(color: 0xFF3B6FE0, icon: 'school'));
  final la = await store.createFolder(sem, 'Linear Algebra', const FolderMeta(color: 0xFFFF8A1F, icon: 'functions'));
  await store.createFolder(sem, 'Physics', const FolderMeta(color: 0xFF1A8F3C, icon: 'science'));
  await store.createFolder(sem, 'Computer Networks', const FolderMeta(color: 0xFF9B3FD1, icon: 'lan'));
  await store.createFolder('', 'Personal', const FolderMeta(color: 0xFFD23B3B, icon: 'heart'));

  final notes = <String, String>{};
  Future<void> add(String key, String dir, Note n) async {
    final e = await store.createNote(dir, n, thumb: await _thumb(n));
    notes[key] = e.relPath;
  }

  await add('lecture', la, lectureNote());
  await add('cornell', la, cornellNote());
  await add('cornellDark', '', cornellNote(dark: true).copyWith(title: 'Exercise sheet 4 (dark)'));
  await add('grid', la, simpleNote('Lecture 3 · Determinants', const Template(kind: TemplateKind.grid, spacing: 14.17), els: [
    lines(28, '# Determinants\n**2 × 2:** ad − bc', left: 28, nLines: 2),
    ...arrow(const Vec2(60, 200), const Vec2(220, 120), seed: 50),
    loop(const RectD(40, 60, 180, 90), seed: 51),
  ]));
  await add('dots', la, simpleNote('Formula sheet', const Template(kind: TemplateKind.dots, spacing: 14.17), els: [
    lines(28, '# Formulas\n- det(AB) = det(A) det(B)\n- (AB)ᵀ = BᵀAᵀ\n- A⁻¹ = adj(A) / det(A)', left: 28, nLines: 4),
  ]));
  await add('staff', '', simpleNote('Choir · Bass part', const Template(kind: TemplateKind.staff)));

  final settings = SettingsController(AppSettings(deviceName: 'demo', theme: theme), null);
  final lib = LibraryController(store);
  await lib.refresh();
  return _Env(dir, store, lib, settings, notes);
}

Future<void> _settle(WidgetTester tester, {int ms = 300}) async {
  await tester.runAsync(() async {
    for (var i = 0; i < 6; i++) {
      await Future<void>.delayed(Duration(milliseconds: ms ~/ 6));
      await tester.pump();
    }
  });
  await tester.pump(const Duration(milliseconds: 300));
}

/// Opens a note. Pushing happens inside runAsync: the editor reads the file in initState,
/// and IO started on the fake test clock never completes.
Future<void> _openEditor(WidgetTester tester, String rel) async {
  await tester.runAsync(() async {
    appNavigatorKey.currentState!.pushNamed('/editor', arguments: rel);
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    }
  });
  await tester.pump(const Duration(milliseconds: 500));
}

/// Captures the whole window, dialogs and panels included, at [_dpr] and writes `docs/screenshots/<name>.png`.
Future<void> _shot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary = _root.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final img = await boundary.toImage(pixelRatio: _dpr);
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    final f = File(p.join('docs', 'screenshots', '$name.png'));
    await f.parent.create(recursive: true);
    await f.writeAsBytes(png!.buffer.asUint8List());
  });
  debugDisableShadows = true;
}

void main() {
  late _Env env;

  setUpAll(() async {
    await _loadFonts();
    appRoutes['/editor'] = (args) => EditorScreen(relPath: args as String);
  });

  setUp(() {
    final v = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    v.physicalSize = _logical * _dpr;
    v.devicePixelRatio = _dpr;
  });

  tearDown(() async {
    final v = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    v.resetPhysicalSize();
    v.resetDevicePixelRatio();
  });

  testWidgets('hero: lecture note with text on lines, sketches and a text box', (tester) async {
    env = (await tester.runAsync(_library))!;
    await tester.pumpWidget(env.app());
    await _settle(tester);
    await _openEditor(tester, env.notes['lecture']!);
    await _shot(tester, 'hero');
  });

  testWidgets('library', (tester) async {
    env = (await tester.runAsync(_library))!;
    await tester.pumpWidget(env.app());
    final la = env.notes['lecture']!.split('/').take(2).join('/');
    await tester.runAsync(() async => env.lib.openFolder(la));
    await _settle(tester, ms: 800);
    await _shot(tester, 'library');
  });

  testWidgets('paper templates', (tester) async {
    env = (await tester.runAsync(_library))!;
    await tester.pumpWidget(env.app());
    await _settle(tester);
    await _openEditor(tester, env.notes['cornell']!);
    final ctx = tester.element(find.byType(EditorScreen));
    showTemplateDialog(ctx, const Template(kind: TemplateKind.cornell));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await _shot(tester, 'templates');
  });

  testWidgets('text tool: typing on lines', (tester) async {
    env = (await tester.runAsync(_library))!;
    await tester.pumpWidget(env.app());
    await _settle(tester);
    await _openEditor(tester, env.notes['lecture']!);
    // Pick the text tool and open its options panel...
    await tester.tap(find.byTooltip('Type on lines (tap again for text box)'));
    await tester.pump();
    await tester.tap(find.byTooltip('Type on lines (tap again for text box)'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(TextOptions), findsOneWidget);
    // ...and show the "Useful facts" block being edited, with its formatting bar.
    final c = tester.widget<CanvasView>(find.byType(CanvasView)).controller;
    final pg = c.note.pages.first;
    final facts = pg.elements.whereType<TextEl>().firstWhere((e) => e.markdown.startsWith('## Useful'));
    c.startTextEdit(pg.id, facts.id);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await _shot(tester, 'text');
  });

  testWidgets('dark mode with Cornell paper', (tester) async {
    env = (await tester.runAsync(() => _library(theme: ThemePref.dark)))!;
    await tester.pumpWidget(env.app());
    await _settle(tester);
    await _openEditor(tester, env.notes['cornellDark']!);
    await _shot(tester, 'dark');
  });
}
