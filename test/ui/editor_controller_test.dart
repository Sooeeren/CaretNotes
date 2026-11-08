import 'package:caret_notes/core/geometry.dart';
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
}
