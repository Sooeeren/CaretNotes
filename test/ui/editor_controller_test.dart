import 'dart:io';

import 'package:caret_notes/core/geometry.dart';
import 'package:caret_notes/core/library/library_store.dart';
import 'package:caret_notes/core/ink/paint_order.dart';
import 'package:caret_notes/core/model/elements.dart';
import 'package:caret_notes/core/model/note.dart';
import 'package:caret_notes/ui/editor/editor_controller.dart';
import 'package:caret_notes/ui/editor/input_router.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

EditorController make() => EditorController(
      note: Note.create(title: 't', layout: NoteLayout.paged, deviceName: 'test'),
      relPath: 't.cnote',
      store: null,
      deviceName: 'test',
    );

void draw(EditorController c, List<Vec2> pts, {ToolKind tool = ToolKind.pen}) {
  final pid = c.note.pages.first.id;
  c.beginStroke(pid, InkPoint(pts.first.x, pts.first.y, 0.5), tool);
  for (final p in pts.skip(1)) {
    c.extendStroke(InkPoint(p.x, p.y, 0.5));
  }
  c.endStroke();
}

void main() {
  test('tool options come from and go back to ToolPrefs', () {
    final c = make();
    expect(c.eraserPartial, isTrue);
    const prefs = ToolPrefs(penWidth: 6, eraserPartial: false, eraserSize: 30, selectMode: SelectMode.lasso);
    c.applyToolPrefs(prefs);
    expect(c.penWidth, 6);
    expect(c.eraserPartial, isFalse);
    expect(c.selectMode, SelectMode.lasso);
    expect(c.toolPrefs, prefs);
    c.update(() => c.eraserSize = 12);
    expect(c.toolPrefs.eraserSize, 12);
  });

  group('strokes and undo', () {
    test('a pen stroke is added to the page', () {
      final c = make();
      draw(c, const [Vec2(10, 10), Vec2(20, 20), Vec2(30, 25)]);
      final els = c.note.pages.first.elements;
      expect(els.length, 1);
      expect((els.single as StrokeEl).tool, ToolKind.pen);
      expect(c.dirty, isTrue);
    });

    test('undo removes the stroke and redo restores it', () {
      final c = make();
      draw(c, const [Vec2(10, 10), Vec2(20, 20)]);
      c.undo();
      expect(c.note.pages.first.elements, isEmpty);
      expect(c.canRedo, isTrue);
      c.redo();
      expect(c.note.pages.first.elements.length, 1);
    });

    test('partial eraser drag is one undo step', () {
      final c = make();
      draw(c, [for (var i = 0; i <= 100; i++) Vec2(i.toDouble(), 50)]);
      final pid = c.note.pages.first.id;
      c.eraserPartial = true;
      c.beginErase();
      c.eraseAt(pid, const Vec2(30, 50));
      c.eraseAt(pid, const Vec2(70, 50));
      c.endErase();
      expect(c.note.pages.first.elements.length, 3);
      c.undo();
      expect(c.note.pages.first.elements.length, 1);
    });

    test('endless note grows when writing near the bottom', () {
      final c = EditorController(
        note: Note.create(title: 't', layout: NoteLayout.endless, deviceName: 'test'),
        relPath: 't.cnote',
        store: null,
        deviceName: 'test',
      );
      final h0 = c.note.pages.first.height;
      draw(c, [Vec2(10, h0 - 20), Vec2(20, h0 - 10)]);
      expect(c.note.pages.first.height, greaterThan(h0));
    });
  });

  group('palm rejection', () {
    test('touch while the stylus is down never draws, even with finger drawing on', () {
      final r = InputRouter(fingerDrawing: true);
      expect(r.down(1, PointerDeviceKind.stylus, kPrimaryButton, 0), InputRole.draw);
      expect(r.down(2, PointerDeviceKind.touch, kPrimaryButton, 10), InputRole.ignore);
    });

    test('touch shortly after the stylus lifted is ignored', () {
      final r = InputRouter(fingerDrawing: false);
      r.down(1, PointerDeviceKind.stylus, kPrimaryButton, 0);
      r.up(1, 100);
      expect(r.down(2, PointerDeviceKind.touch, kPrimaryButton, 300), InputRole.ignore);
      expect(r.down(3, PointerDeviceKind.touch, kPrimaryButton, 1000), InputRole.navigate);
    });

    test('touch while stylus hovers is ignored', () {
      final r = InputRouter(fingerDrawing: true);
      r.hover(PointerDeviceKind.stylus, 0);
      expect(r.down(2, PointerDeviceKind.touch, kPrimaryButton, 100), InputRole.ignore);
    });

    test('finger draws only when finger drawing is enabled', () {
      expect(InputRouter(fingerDrawing: true).down(1, PointerDeviceKind.touch, kPrimaryButton, 0), InputRole.draw);
      expect(InputRouter(fingerDrawing: false).down(1, PointerDeviceKind.touch, kPrimaryButton, 0), InputRole.navigate);
    });

    test('stylus eraser end and side button are recognized', () {
      final r = InputRouter(fingerDrawing: false);
      expect(r.down(1, PointerDeviceKind.invertedStylus, kPrimaryButton, 0), InputRole.erase);
      expect(r.down(2, PointerDeviceKind.stylus, kPrimaryButton | kSecondaryStylusButton, 0), InputRole.sideButton);
      expect(r.down(3, PointerDeviceKind.mouse, kMiddleMouseButton, 0), InputRole.navigate);
    });
  });

  test('highlighters are painted before pen strokes', () {
    const pen = StrokeEl(id: 'p', points: [InkPoint(0, 0, 1)], tool: ToolKind.pen, color: 0, width: 1);
    const hl = StrokeEl(id: 'h', points: [InkPoint(0, 0, 1)], tool: ToolKind.highlighter, color: 0, width: 1);
    expect(paintOrder([pen, hl]).map((e) => e.id), ['h', 'p']);
  });

  group('selection and shapes', () {
    test('lasso then move translates the selection bounds by the delta', () {
      final c = make();
      draw(c, const [Vec2(10, 10), Vec2(30, 10)]);
      final pid = c.note.pages.first.id;
      c.selectLasso(pid, const [Vec2(0, 0), Vec2(50, 0), Vec2(50, 30), Vec2(0, 30)]);
      expect(c.hasSelection, isTrue);
      final before = c.selectionRect!;
      c.moveSelection(100, 50);
      final after = c.selectionRect!;
      expect(after.left - before.left, closeTo(100, 1e-9));
      expect(after.top - before.top, closeTo(50, 1e-9));
    });

    test('deleting a selection is undoable', () {
      final c = make();
      draw(c, const [Vec2(10, 10), Vec2(30, 10)]);
      final pid = c.note.pages.first.id;
      c.selectBox(pid, const RectD(0, 0, 50, 50));
      c.deleteSelection();
      expect(c.note.pages.first.elements, isEmpty);
      c.undo();
      expect(c.note.pages.first.elements.length, 1);
    });

    test('holding after a rough line snaps it to a straight 2-point line', () {
      final c = make();
      final pid = c.note.pages.first.id;
      c.beginStroke(pid, const InkPoint(0, 100, .5), ToolKind.pen);
      for (var i = 1; i <= 40; i++) {
        c.extendStroke(InkPoint(i * 5.0, 100 + (i.isEven ? 1.2 : -1.2), .5));
      }
      expect(c.snapLiveToShape(), isTrue);
      c.extendStroke(const InkPoint(260, 140, .5)); // still down: end point follows the pen
      c.endStroke();
      final s = c.note.pages.first.elements.single as StrokeEl;
      expect(s.points.first.x, closeTo(0, 1e-9));
      expect(s.points.last.x, closeTo(260, 1e-9));
      expect(s.points.last.y, closeTo(140, 1e-9));
    });

    test('paste puts copies with new ids', () {
      final c = make();
      draw(c, const [Vec2(10, 10), Vec2(30, 10)]);
      final pid = c.note.pages.first.id;
      c.selectBox(pid, const RectD(0, 0, 50, 50));
      c.copySelection();
      c.paste(pid);
      final ids = c.note.pages.first.elements.map((e) => e.id).toSet();
      expect(ids.length, 2);
    });

    test('switching paged -> endless -> paged keeps every element', () {
      final c = make();
      c.addPage();
      draw(c, const [Vec2(10, 10), Vec2(30, 10)]);
      final p2 = c.note.pages[1].id;
      c.beginStroke(p2, const InkPoint(10, 10, .5), ToolKind.pen);
      c.extendStroke(const InkPoint(40, 40, .5));
      c.endStroke();
      c.switchLayout();
      expect(c.note.layout, NoteLayout.endless);
      expect(c.note.pages.single.elements.length, 2);
      c.switchLayout();
      expect(c.note.layout, NoteLayout.paged);
      expect(c.note.pages.length, 2);
      expect(c.note.pages[1].elements.length, 1);
    });
  });

  group('review fixes', () {
    test('saving over a file that changed on disk keeps the other version in Recently deleted', () async {
      final tmp = await Directory.systemTemp.createTemp('cn_ed_');
      final store = LibraryStore(tmp.path);
      final e = await store.createNote('', Note.create(title: 'N', layout: NoteLayout.paged, deviceName: 'a'));
      final c = EditorController(note: await store.loadNote(e.relPath), relPath: e.relPath, store: store, deviceName: 'a', autosave: false);
      await c.markLoaded();
      // sync downloads another device's version while the note is open
      final other = (await store.loadNote(e.relPath)).copyWith(title: 'other device');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await store.saveNote(e.relPath, other);
      draw(c, const [Vec2(1, 1), Vec2(5, 5)]);
      await c.save();
      expect((await store.loadNote(e.relPath)).pages.first.elements.length, 1);
      final trash = await store.listTrash();
      expect(trash.length, 1);
      expect(trash.single.originalPath, e.relPath);
      await tmp.delete(recursive: true);
    });

    test('undoing a layout switch restores the layout too, so no pages are lost', () {
      final c = make();
      c.addPage();
      c.addPage();
      c.switchLayout(); // -> endless
      c.undo(); // back to 3 pages, must also be paged again
      expect(c.note.layout, NoteLayout.paged);
      expect(c.note.pages.length, 3);
      c.switchLayout();
      c.switchLayout();
      expect(c.note.pages.length, greaterThanOrEqualTo(1));
      expect(c.note.layout, NoteLayout.paged);
    });
  });

  group('palm landing before the pen', () {
    test('touches already down are cancelled when the pen arrives', () {
      final r = InputRouter(fingerDrawing: true);
      expect(r.down(5, PointerDeviceKind.touch, kPrimaryButton, 0), InputRole.draw);
      expect(r.down(1, PointerDeviceKind.stylus, kPrimaryButton, 50), InputRole.draw);
      expect(r.takeCancelledTouches(), {5});
      expect(r.isCancelled(5), isTrue);
      r.up(5, 60);
      expect(r.isCancelled(5), isFalse);
    });

    test('hovering pen also cancels touches', () {
      final r = InputRouter(fingerDrawing: false);
      r.down(7, PointerDeviceKind.touch, kPrimaryButton, 0);
      r.hover(PointerDeviceKind.stylus, 10);
      expect(r.takeCancelledTouches(), {7});
    });
  });

  group('read mode', () {
    test('turning it on drops the selection; picking a tool turns it off', () {
      final c = make();
      draw(c, const [Vec2(10, 10), Vec2(40, 40)]);
      final pid = c.note.pages.first.id;
      c.setTool(EditorTool.select);
      c.selectOnly(pid, c.note.pages.first.elements.single.id);
      c.toggleReadOnly();
      expect(c.readOnly, isTrue);
      expect(c.hasSelection, isFalse);
      c.setTool(EditorTool.pen);
      expect(c.readOnly, isFalse);
    });
  });
}
