import 'package:caret_notes/core/geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rdp reduces a straight 100-point line to its two end points', () {
    final pts = List.generate(100, (i) => Vec2(i.toDouble(), i * 0.5));
    final out = rdp(pts, 0.5);
    expect(out.length, 2);
    expect(out.first, pts.first);
    expect(out.last, pts.last);
  });

  test('rdp keeps the corner of an L shape', () {
    final pts = [
      for (var i = 0; i <= 10; i++) Vec2(i.toDouble(), 0),
      for (var i = 1; i <= 10; i++) Vec2(10, i.toDouble()),
    ];
    expect(rdp(pts, 0.5), [const Vec2(0, 0), const Vec2(10, 0), const Vec2(10, 10)]);
  });

  test('pointInPolygon on a square', () {
    const sq = [Vec2(0, 0), Vec2(10, 0), Vec2(10, 10), Vec2(0, 10)];
    expect(pointInPolygon(const Vec2(5, 5), sq), isTrue);
    expect(pointInPolygon(const Vec2(15, 5), sq), isFalse);
    expect(pointInPolygon(const Vec2(-1, -1), sq), isFalse);
  });

  test('Affine rotate 90 degrees about origin then translate', () {
    final a = Affine.translate(5, 0) * Affine.rotate(1.5707963267948966);
    final p = a.apply(const Vec2(1, 0));
    expect(p.x, closeTo(5, 1e-9));
    expect(p.y, closeTo(1, 1e-9));
  });

  test('RectD union and contains', () {
    const a = RectD(0, 0, 10, 10);
    const b = RectD(5, 5, 20, 15);
    final u = a.union(b);
    expect(u, const RectD(0, 0, 20, 15));
    expect(u.contains(const Vec2(19, 14)), isTrue);
    expect(a.contains(const Vec2(11, 1)), isFalse);
  });
}
