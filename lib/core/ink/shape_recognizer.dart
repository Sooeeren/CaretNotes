import 'dart:math' as math;

import '../geometry.dart';

enum ShapeKind { line, rect, ellipse, triangle, arrow }

class RecognizedShape {
  final ShapeKind kind;

  /// Polyline of the clean shape. Closed shapes repeat the first point at the end.
  final List<Vec2> points;
  const RecognizedShape(this.kind, this.points);
}

/// Turns a rough hand-drawn stroke into a clean shape, or null if it doesn't
/// look like one of the supported shapes.
RecognizedShape? recognizeShape(List<Vec2> pts) {
  if (pts.length < 2) return null;
  final len = polylineLength(pts);
  final bounds = RectD.fromPoints(pts);
  final diag = math.sqrt(bounds.width * bounds.width + bounds.height * bounds.height);
  if (len < 12 || diag < 8) return null;

  final closed = pts.first.dist(pts.last) < math.max(0.18 * len, 6) && len > 3 * pts.first.dist(pts.last);

  if (!closed) {
    final simple = rdp(pts, math.max(3, 0.05 * diag));
    if (simple.length == 2) return RecognizedShape(ShapeKind.line, [pts.first, pts.last]);
    return _arrow(pts, simple);
  }

  // Closed: ellipse fit first (rects/triangles fit badly).
  final ell = _ellipseFit(pts, bounds);
  if (ell != null) return ell;

  final verts = _closedVertices(pts, diag);
  if (verts.length == 3) return RecognizedShape(ShapeKind.triangle, [...verts, verts.first]);
  if (verts.length == 4) return RecognizedShape(ShapeKind.rect, _rect(verts));
  return null;
}

RecognizedShape? _ellipseFit(List<Vec2> pts, RectD b) {
  final cx = b.center.x, cy = b.center.y, rx = b.width / 2, ry = b.height / 2;
  if (rx < 3 || ry < 3) return null;
  var err = 0.0;
  for (final p in pts) {
    final dx = (p.x - cx) / rx, dy = (p.y - cy) / ry;
    err += (math.sqrt(dx * dx + dy * dy) - 1).abs();
  }
  err /= pts.length;
  if (err > 0.085) return null;
  const n = 64;
  return RecognizedShape(ShapeKind.ellipse, [
    for (var i = 0; i <= n; i++) Vec2(cx + rx * math.cos(i / n * 2 * math.pi), cy + ry * math.sin(i / n * 2 * math.pi)),
  ]);
}

/// Corner vertices of a closed polyline, dropping near-collinear ones.
List<Vec2> _closedVertices(List<Vec2> pts, double diag) {
  var v = rdp(pts, 0.07 * diag);
  if (v.length > 2 && v.first.dist(v.last) < 0.15 * diag) v = v.sublist(0, v.length - 1);
  var changed = true;
  while (changed && v.length > 3) {
    changed = false;
    for (var i = 0; i < v.length; i++) {
      final a = v[(i - 1 + v.length) % v.length], b = v[i], c = v[(i + 1) % v.length];
      final d1 = (b - a).normalized(), d2 = (c - b).normalized();
      final turn = math.acos(d1.dot(d2).clamp(-1.0, 1.0));
      if (turn < 0.45 || b.dist(a) < 0.08 * diag) {
        v = [...v]..removeAt(i);
        changed = true;
        break;
      }
    }
  }
  return v;
}

List<Vec2> _rect(List<Vec2> v) {
  // Near axis-aligned: snap to bounding box; otherwise keep a rotated rectangle.
  final e = v[1] - v[0];
  final ang = math.atan2(e.y, e.x);
  final mod = (ang % (math.pi / 2) + math.pi / 2) % (math.pi / 2);
  final off = math.min(mod, math.pi / 2 - mod);
  if (off < 0.18) {
    final b = RectD.fromPoints(v);
    final c = b.corners;
    return [...c, c.first];
  }
  // rotated: build from first edge direction and average extents
  final center = Vec2(v.map((p) => p.x).reduce((a, b) => a + b) / 4, v.map((p) => p.y).reduce((a, b) => a + b) / 4);
  final ux = e.normalized(), uy = ux.perp;
  var hx = 0.0, hy = 0.0;
  for (final p in v) {
    hx += ((p - center).dot(ux)).abs();
    hy += ((p - center).dot(uy)).abs();
  }
  hx /= 4;
  hy /= 4;
  final c = [
    center - ux * hx - uy * hy,
    center + ux * hx - uy * hy,
    center + ux * hx + uy * hy,
    center - ux * hx + uy * hy,
  ];
  return [...c, c.first];
}

RecognizedShape? _arrow(List<Vec2> pts, List<Vec2> simple) {
  if (simple.length < 4) return null;
  final tail = simple[0], tip = simple[1];
  final shaft = tail.dist(tip);
  if (shaft < 20) return null;
  // Everything after the tip must stay close to it (the head).
  for (var i = 2; i < simple.length; i++) {
    if (simple[i].dist(tip) > 0.45 * shaft) return null;
  }
  final dir = (tip - tail).normalized();
  final headLen = math.max(0.18 * shaft, 8.0);
  const spread = 0.45;
  Vec2 rot(Vec2 d, double a) => Vec2(d.x * math.cos(a) - d.y * math.sin(a), d.x * math.sin(a) + d.y * math.cos(a));
  final back = dir * -1;
  final h1 = tip + rot(back, spread) * headLen;
  final h2 = tip + rot(back, -spread) * headLen;
  return RecognizedShape(ShapeKind.arrow, [tail, tip, h1, tip, h2]);
}
