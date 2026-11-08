import 'dart:math' as math;

import '../geometry.dart';
import '../model/elements.dart';

/// Stroke half-width at a point, from base width, pressure and tool.
double halfWidthAt(double width, double pressure, ToolKind tool) {
  final p = pressure.clamp(0.0, 1.0);
  switch (tool) {
    case ToolKind.pen:
      return width * (0.3 + 0.7 * p) / 2;
    case ToolKind.pencil:
      return width * (0.6 + 0.4 * p) / 2;
    case ToolKind.fineliner:
    case ToolKind.highlighter:
      return width / 2;
  }
}

/// Closed outline polygon of a variable-width stroke, with round caps.
/// Used for both screen rendering and vector PDF export.
List<Vec2> strokeOutline(List<InkPoint> pts, double width, ToolKind tool) {
  if (pts.isEmpty) return const [];
  if (pts.length == 1) {
    final r = halfWidthAt(width, pts[0].p, tool);
    return _circle(pts[0].v, r);
  }
  final left = <Vec2>[], right = <Vec2>[];
  for (var i = 0; i < pts.length; i++) {
    final prev = pts[math.max(0, i - 1)].v, next = pts[math.min(pts.length - 1, i + 1)].v;
    var dir = (next - prev).normalized();
    if (dir == Vec2.zero) dir = const Vec2(1, 0);
    final n = dir.perp;
    final hw = halfWidthAt(width, pts[i].p, tool);
    left.add(pts[i].v + n * hw);
    right.add(pts[i].v - n * hw);
  }
  final out = <Vec2>[...left];
  _cap(out, pts.last.v, left.last, halfWidthAt(width, pts.last.p, tool));
  out.addAll(right.reversed);
  _cap(out, pts.first.v, right.first, halfWidthAt(width, pts.first.p, tool));
  return out;
}

/// Semicircle from [from] around [c], going clockwise (screen coords) to the opposite side.
void _cap(List<Vec2> out, Vec2 c, Vec2 from, double r) {
  final a0 = math.atan2(from.y - c.y, from.x - c.x);
  const steps = 6;
  for (var i = 1; i < steps; i++) {
    final a = a0 - math.pi * i / steps;
    out.add(Vec2(c.x + r * math.cos(a), c.y + r * math.sin(a)));
  }
}

List<Vec2> _circle(Vec2 c, double r) => [
      for (var i = 0; i < 12; i++) Vec2(c.x + r * math.cos(i * math.pi / 6), c.y + r * math.sin(i * math.pi / 6)),
    ];

/// Light input smoothing: exponential moving average, used while capturing.
InkPoint smoothPoint(InkPoint prev, InkPoint raw, double alpha) => InkPoint(
      prev.x + (raw.x - prev.x) * alpha,
      prev.y + (raw.y - prev.y) * alpha,
      prev.p + (raw.p - prev.p) * alpha,
    );
