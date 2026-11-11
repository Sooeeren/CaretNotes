import 'package:caret_notes/core/model/elements.dart';
import 'package:caret_notes/core/model/note.dart';
import 'package:caret_notes/core/settings.dart';
import 'package:caret_notes/ui/editor/color_wheel.dart';
import 'package:caret_notes/ui/editor/editor_controller.dart';
import 'package:caret_notes/ui/editor/tool_options.dart';
import 'package:caret_notes/ui/editor/toolbar.dart';
import 'package:caret_notes/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

EditorController make() => EditorController(
  note: Note.create(title: 'x', layout: NoteLayout.paged, deviceName: 't'),
  relPath: 't.cnote',
  store: null,
  deviceName: 't',
);

Widget host(EditorController c, AppSettings s, {ValueChanged<int>? onColor, ValueChanged<Offset>? onDragStart}) => MaterialApp(
  theme: buildTheme(const Color(0xFFD9772B), Brightness.light),
  home: Scaffold(
    body: ListenableBuilder(
      listenable: c,
      builder: (_, _) => Center(
        child: ToolPill(
          c: c,
          settings: s,
          axis: Axis.horizontal,
          onDragStart: onDragStart ?? (_) {},
          onDragUpdate: (_) {},
          onDragEnd: (_) {},
          onPenColorsChanged: onColor ?? (_) {},
        ),
      ),
    ),
  ),
);

void main() {
  const area = Size(1200, 800);
  test('dropping near an edge docks the toolbar there, elsewhere it floats', () {
    expect(dockFor(const Offset(500, 30), area), ToolbarDock.top);
    expect(dockFor(const Offset(500, 780), area), ToolbarDock.bottom);
    expect(dockFor(const Offset(30, 400), area), ToolbarDock.left);
    expect(dockFor(const Offset(1170, 400), area), ToolbarDock.right);
    expect(dockFor(const Offset(600, 400), area), ToolbarDock.floating);
  });

  test('box select is the default selection mode', () {
    expect(make().selectMode, SelectMode.box);
  });

  testWidgets('the pill shows the chosen number of quick colors and they set the pen color', (tester) async {
    final c = make();
    const s = AppSettings(penColors: [0xFF111111, 0xFF3B6FE0, 0xFFD23B3B, 0xFF1A8F3C]);
    await tester.pumpWidget(host(c, s));
    expect(find.byType(QuickColor), findsNWidgets(3));
    expect(find.byTooltip('Any color…'), findsOneWidget);

    c.setTool(EditorTool.eraser);
    await tester.pump();
    await tester.tap(find.byType(QuickColor).at(1));
    await tester.pump();
    expect(c.penColor, 0xFF3B6FE0);
    expect(c.tool, EditorTool.pen, reason: 'picking a color while erasing goes back to the pen');

    await tester.pumpWidget(host(c, s.copyWith(quickColors: 0)));
    expect(find.byType(QuickColor), findsNothing);
  });

  testWidgets('a quick color recolors the highlighter while it is the active tool', (tester) async {
    final c = make()..setTool(EditorTool.highlighter);
    await tester.pumpWidget(host(c, const AppSettings(penColors: [0xFF111111, 0xFF3B6FE0, 0xFFD23B3B])));
    await tester.tap(find.byType(QuickColor).at(2));
    await tester.pump();
    expect(c.hlColor, 0xFFD23B3B);
    expect(c.tool, EditorTool.highlighter);
  });

  testWidgets('the color wheel picks any color and reports it', (tester) async {
    final c = make();
    final picked = <int>[];
    await tester.pumpWidget(host(c, const AppSettings(), onColor: picked.add));
    await tester.tap(find.byTooltip('Any color…'));
    await tester.pumpAndSettle();
    expect(find.byType(ColorWheel), findsOneWidget);
    await tester.enterText(find.byType(TextField), '#12AB34');
    await tester.pump();
    await tester.tap(find.text('Use color'));
    await tester.pumpAndSettle();
    expect(c.penColor, 0xFF12AB34);
    expect(picked, [0xFF12AB34]);
  });

  testWidgets('the pen panel previews the stroke and pages through colors with arrows', (tester) async {
    final c = make()..setTool(EditorTool.pen);
    await tester.pumpWidget(host(c, const AppSettings()));
    await tester.tap(find.byTooltip('Pen (tap again for type, size and color)'));
    await tester.pumpAndSettle();
    expect(find.byType(PenPreview), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);
    await tester.tap(find.byTooltip('Next colors'));
    await tester.pump();
    expect(find.text('2 / 2'), findsOneWidget);
    await tester.tap(find.byTooltip('Previous colors'));
    await tester.pump();
    expect(find.text('1 / 2'), findsOneWidget);

    await tester.tap(find.text('Pencil'));
    await tester.pump();
    expect(tester.widget<PenPreview>(find.byType(PenPreview)).kind, ToolKind.pencil);
  });

  testWidgets('the pill has a grip to drag it right away', (tester) async {
    final starts = <Offset>[];
    await tester.pumpWidget(host(make(), const AppSettings(), onDragStart: starts.add));
    await tester.drag(find.byTooltip('Drag to move the toolbar'), const Offset(0, 300));
    expect(starts, hasLength(1));
  });
}
