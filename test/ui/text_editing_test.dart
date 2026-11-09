import 'package:caret_notes/core/geometry.dart';
import 'package:caret_notes/core/model/elements.dart';
import 'package:caret_notes/core/model/note.dart';
import 'package:caret_notes/core/paper.dart';
import 'package:caret_notes/ui/editor/editor_controller.dart';
import 'package:caret_notes/ui/editor/editor_shortcuts.dart';
import 'package:caret_notes/ui/editor/text_box.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

EditorController make() => EditorController(
      note: Note.create(title: 't', layout: NoteLayout.paged, deviceName: 'test'),
      relPath: 't.cnote',
      store: null,
      deviceName: 'test',
    );

/// The editor's shortcut layer around a text box editor, like in the real editor screen.
Widget host(EditorController c, String pageId, TextEl el) => MaterialApp(
      home: Scaffold(
        body: EditorShortcuts(
          c: c,
          bindings: {const SingleActivator(LogicalKeyboardKey.backspace): c.deleteSelection},
          child: ListenableBuilder(
            listenable: c,
            builder: (_, _) => c.editingTextId == null
                ? const SizedBox()
                : TextBoxEditor(
                    el: el,
                    onChanged: (md, h) => c.typeText(pageId, el.id, md, h),
                    onDone: () {},
                  ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('Backspace deletes a character in a text box instead of being eaten by the editor', (tester) async {
    final c = make();
    final pid = c.note.pages.first.id;
    // The editor is already on screen when the user starts typing in a new box.
    final el = c.addText(pid, const Vec2(100, 100));
    c.typeText(pid, el.id, 'x', 30);
    c.finishTextEdit();
    await tester.pumpWidget(host(c, pid, el));
    await tester.pump();
    c.startTextEdit(pid, el.id);
    await tester.pump();
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'ab');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect((c.note.pages.first.find(el.id) as TextEl).markdown, 'a');
  });

  testWidgets('Backspace still deletes the selection when no text box is being edited', (tester) async {
    final c = make();
    final pid = c.note.pages.first.id;
    final el = c.addText(pid, const Vec2(100, 100));
    c.typeText(pid, el.id, 'keep me?', 30);
    c.finishTextEdit();
    c.selectOnly(pid, el.id);
    await tester.pumpWidget(host(c, pid, el));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(c.note.pages.first.find(el.id), isNull);
  });

  group('text tool modes', () {
    test('typing on lines: the new text sits on the ruled lines, right of the margin', () {
      final c = make();
      final pid = c.note.pages.first.id;
      expect(c.textMode, TextMode.lines);
      final t = c.addText(pid, const Vec2(300, 100));
      final s = c.note.template.spacing;
      expect(t.lineHeight, s);
      expect(t.rect.left, greaterThan(notebookMargin(s)));
      expect(t.rect.top % s, 0);
      expect(t.rect.height, s);
    });

    test('text box mode makes a free box where you tap', () {
      final c = make();
      final pid = c.note.pages.first.id;
      c.update(() => c.textMode = TextMode.box);
      final t = c.addText(pid, const Vec2(300, 100));
      expect(t.lineHeight, isNull);
      expect(t.rect.left, 300);
      expect(t.rect.top, 100);
    });

    test('changing the paper spacing keeps text on its lines', () {
      final c = make();
      final pid = c.note.pages.first.id;
      final t = c.addText(pid, const Vec2(300, 100));
      c.typeText(pid, t.id, 'hello', t.lineHeight!);
      c.finishTextEdit();
      c.setNoteTemplate(c.note.template.copyWith(spacing: 30));
      final moved = c.note.pages.first.find(t.id) as TextEl;
      expect(moved.lineHeight, 30);
      expect(moved.rect.top % 30, 0);
    });
  });
}
