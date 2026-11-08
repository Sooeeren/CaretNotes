import 'dart:math' as math;

import 'package:caret_notes/core/geometry.dart';
import 'package:caret_notes/ui/editor/ruler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ruler is 20 cm long', () {
    expect(RulerGeom.lengthPt, closeTo(20 * 28.3465, 0.01));
  });

  test('a point near the edge snaps; projected points lie on the edge line', () {
    const r = RulerGeom(center: Vec2(300, 300), angle: 0);
    final top = 300 - RulerGeom.thicknessPt / 2;
    final side = r.edgeNear(Vec2(310, top - 10), 18);
    expect(side, -1);
    for (final p in const [Vec2(250, 260), Vec2(400, 290), Vec2(330, 240)]) {
      final q = r.project(p, side!);
      expect(q.y, closeTo(top, 1e-9));
      expect(q.x, closeTo(p.x, 1e-9));
    }
    expect(r.edgeNear(const Vec2(310, 100), 18), isNull);
  });

  test('projection works on a rotated ruler', () {
    final r = RulerGeom(center: const Vec2(0, 0), angle: math.pi / 4);
    final q = r.project(const Vec2(50, 0), 1);
    // distance from center line equals half thickness
    final n = Vec2(-math.sin(math.pi / 4), math.cos(math.pi / 4));
    expect(q.dot(n), closeTo(RulerGeom.thicknessPt / 2, 1e-9));
  });

  test('angles within 3 degrees of 0/45/90 snap', () {
    double deg(double d) => d * math.pi / 180;
    expect(snapRulerAngle(deg(44)), closeTo(deg(45), 1e-9));
    expect(snapRulerAngle(deg(91.5)), closeTo(deg(90), 1e-9));
    expect(snapRulerAngle(deg(-2)), closeTo(0, 1e-9));
    expect(snapRulerAngle(deg(30)), closeTo(deg(30), 1e-9));
  });

  test('two-finger drag moves and rotates the ruler', () {
    const r = RulerGeom(center: Vec2(100, 100), angle: 0);
    final m = r.twoFinger(const Vec2(50, 100), const Vec2(150, 100), const Vec2(60, 110), Vec2(60 + 100 * math.cos(0.5), 110 + 100 * math.sin(0.5)));
    expect(m.angle, closeTo(0.5, 1e-9));
    expect(m.center.x, greaterThan(100));
  });
}
