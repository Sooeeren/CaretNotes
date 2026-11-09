import 'package:caret_notes/core/find.dart';
import 'package:caret_notes/core/geometry.dart';
import 'package:caret_notes/core/model/note.dart';
import 'package:caret_notes/ui/editor/editor_controller.dart';
import 'package:caret_notes/ui/editor/find_bar.dart';
import 'package:caret_notes/ui/editor/toolbar.dart';
import 'package:caret_notes/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

EditorController make() => EditorController(
      note: Note.create(title: 'Lecture', layout: NoteLayout.paged, deviceName: 'test'),
      relPath: 't.cnote',
      store: null,
      deviceName: 'test',
    );

void addText(EditorController c, String md, double y) {
  final pid = c.note.pages.first.id;
  final t = c.addText(pid, Vec2(80, y), mode: TextMode.box);
  c.typeText(pid, t.id, md, 30);
  c.finishTextEdit();
}

Widget wrap(Widget child) => MaterialApp(
      theme: buildTheme(const Color(0xFFD9772B), Brightness.light),
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('find bar steps through matching text and outlines the current one', (tester) async {
    final c = make();
    addText(c, 'Eigenvalues first', 100);
    addText(c, 'unrelated', 200);
    addText(c, 'more **eigenvalues**', 300);
    final revealed = <FindHit>[];
    var closed = false;
    await tester.pumpWidget(wrap(FindBar(c: c, onReveal: revealed.add, onClose: () => closed = true)));

    await tester.enterText(find.byType(TextField), 'eigen');
    await tester.pump();
    expect(find.text('1 of 2'), findsOneWidget);
    expect(revealed.last.rect.top, 100);
    expect(c.findHit?.elementId, revealed.last.elementId);

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.text('2 of 2'), findsOneWidget);
    expect(revealed.last.rect.top, 300);

    await tester.enterText(find.byType(TextField), 'nothing like this');
    await tester.pump();
    expect(find.text('No matches'), findsOneWidget);
    expect(c.findHit, isNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(closed, isTrue);
  });

  testWidgets('note bar read-mode button toggles read mode and disables undo', (tester) async {
    final c = make();
    addText(c, 'x', 100);
    await tester.pumpWidget(wrap(ListenableBuilder(
      listenable: c,
      builder: (_, _) => NoteBar(
        c: c,
        onBack: () {},
        onRename: () {},
        onFind: () {},
        finding: false,
        insertMenu: const SizedBox(),
        pagesButton: null,
        moreMenu: const SizedBox(),
      ),
    )));
    IconButton undo() => tester.widget<IconButton>(find.ancestor(of: find.byIcon(Icons.undo), matching: find.byType(IconButton)));
    expect(undo().onPressed, isNotNull);

    await tester.tap(find.byTooltip('Read mode (only scroll, no accidental marks)'));
    await tester.pump();
    expect(c.readOnly, isTrue);
    expect(find.text('1 page · Read mode'), findsOneWidget);
    expect(undo().onPressed, isNull);
  });
}
