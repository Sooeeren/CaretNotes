import 'dart:math' as math;

import 'package:caret_notes/core/geometry.dart';
import 'package:caret_notes/core/ink/eraser.dart';
import 'package:caret_notes/core/ink/selection.dart';
import 'package:caret_notes/core/ink/shape_recognizer.dart';
import 'package:caret_notes/core/ink/stroke_geometry.dart';
import 'package:caret_notes/core/model/elements.dart';
import 'package:flutter_test/flutter_test.dart';

final _rnd = math.Random(42);
double _j(double a) => (_rnd.nextDouble() - 0.5) * 2 * a;

List<Vec2> _poly(List<Vec2> corners, {int perSide = 20, double jitter = 2}) => [
      for (var c = 0; c < corners.length; c++)
        for (var i = 0; i < perSide; i++)
          () {
            final a = corners[c], b = corners[(c + 1) % corners.length];
            final t = i / perSide;
            return Vec2(a.x + (b.x - a.x) * t + _j(jitter), a.y + (b.y - a.y) * t + _j(jitter));
          }(),
      corners.first + const Vec2(1, 1),
    ];

StrokeEl _stroke(String id, List<Vec2> pts, {double width = 2}) =>
    StrokeEl(id: id, points: [for (final p in pts) InkPoint(p.x, p.y, 0.5)], tool: ToolKind.pen, color: 0xFF000000, width: width);

void main() {
  group('recognizeShape', () {
    test('wobbly near-straight line becomes a line', () {
      final pts = [for (var i = 0; i <= 50; i++) Vec2(i * 4.0, 100 + _j(1.5))];
      final s = recognizeShape(pts)!;
      expect(s.kind, ShapeKind.line);
      expect(s.points.length, 2);
    });

    test('jittered square becomes a rectangle with 4 corners', () {
      final s = recognizeShape(_poly(const [Vec2(0, 0), Vec2(100, 0), Vec2(100, 100), Vec2(0, 100)]))!;
      expect(s.kind, ShapeKind.rect);
      expect(s.points.length, 5); // closed: first point repeated
      final b = RectD.fromPoints(s.points);
      expect(b.width, closeTo(100, 6));
      expect(b.height, closeTo(100, 6));
    });

    test('jittered square starting mid-side is still a rectangle', () {
      final pts = _poly(const [Vec2(50, 0), Vec2(100, 0), Vec2(100, 100), Vec2(0, 100), Vec2(0, 0)]);
      expect(recognizeShape(pts)!.kind, ShapeKind.rect);
    });

    test('jittered circle becomes an ellipse', () {
      final pts = [for (var i = 0; i <= 80; i++) Vec2(200 + 60 * math.cos(i / 80 * 2 * math.pi) + _j(2), 200 + 60 * math.sin(i / 80 * 2 * math.pi) + _j(2))];
      expect(recognizeShape(pts)!.kind, ShapeKind.ellipse);
    });

    test('triangle becomes a triangle', () {
      final s = recognizeShape(_poly(const [Vec2(0, 100), Vec2(60, 0), Vec2(120, 100)]))!;
      expect(s.kind, ShapeKind.triangle);
      expect(s.points.length, 4);
    });

    test('arrow: shaft then V head', () {
      final pts = <Vec2>[
        for (var i = 0; i <= 40; i++) Vec2(i * 5.0, 0 + _j(0.8)),
        for (var i = 1; i <= 8; i++) Vec2(200 - i * 3.0, -i * 3.0),
        for (var i = 1; i <= 8; i++) Vec2(176 + i * 3.0, -24 + i * 3.0),
        for (var i = 1; i <= 8; i++) Vec2(200 - i * 3.0, i * 3.0),
      ];
      expect(recognizeShape(pts)!.kind, ShapeKind.arrow);
    });

    test('open scribble is not recognized', () {
      final pts = [for (var i = 0; i <= 60; i++) Vec2(i * 3.0, 40 * math.sin(i / 3))];
      expect(recognizeShape(pts), isNull);
    });
  });

  group('eraser', () {
    final line = _stroke('a', [for (var i = 0; i <= 100; i++) Vec2(i.toDouble(), 0)]);

    test('erasing the middle splits a stroke into two', () {
      final out = eraseStroke(line, const Vec2(50, 0), 5);
      expect(out.length, 2);
      expect(out.every((s) => s.id != 'a'), isTrue);
      expect(out[0].points.last.x, lessThan(46));
      expect(out[1].points.first.x, greaterThan(54));
    });

    test('erasing far away leaves the stroke untouched', () {
      final out = eraseStroke(line, const Vec2(50, 50), 5);
      expect(out, [same(line)]);
    });

    test('erasing everything returns nothing', () {
      final tiny = _stroke('t', const [Vec2(0, 0), Vec2(1, 0)]);
      expect(eraseStroke(tiny, const Vec2(0.5, 0), 5), isEmpty);
    });

    test('strokeHit detects a sparse segment passing through the eraser', () {
      final sparse = _stroke('s', const [Vec2(0, 0), Vec2(100, 0)]);
      expect(strokeHit(sparse, const Vec2(50, 2), 3), isTrue);
      expect(strokeHit(sparse, const Vec2(50, 20), 3), isFalse);
    });
  });

  group('selection', () {
    final a = _stroke('a', [for (var i = 0; i <= 10; i++) Vec2(10 + i.toDouble(), 10)]);
    final b = _stroke('b', [for (var i = 0; i <= 10; i++) Vec2(100 + i.toDouble(), 100)]);
    const t = TextEl(id: 't', rect: RectD(200, 200, 260, 230), markdown: 'x');

    test('lasso picks only the enclosed stroke', () {
      const lasso = [Vec2(0, 0), Vec2(40, 0), Vec2(40, 40), Vec2(0, 40)];
      expect(lassoHits([a, b, t], lasso), {'a'});
    });

    test('box select picks stroke and text box whose centers are inside', () {
      expect(boxHits([a, b, t], const RectD(90, 90, 300, 300)), {'b', 't'});
    });
  });

  test('strokeOutline returns a closed polygon wider for more pressure', () {
    final light = strokeOutline(const [InkPoint(0, 0, 0.1), InkPoint(50, 0, 0.1)], 4, ToolKind.pen);
    final heavy = strokeOutline(const [InkPoint(0, 0, 1), InkPoint(50, 0, 1)], 4, ToolKind.pen);
    expect(RectD.fromPoints(heavy).height, greaterThan(RectD.fromPoints(light).height));
  });
}
