import '../geometry.dart';
import '../ids.dart';
import '../model/elements.dart';

/// Whole-stroke eraser hit test: any segment within [radius] (+ half stroke width).
bool strokeHit(StrokeEl s, Vec2 p, double radius) {
  final r = radius + s.width / 2;
  if (!s.bounds().inflate(radius).contains(p)) return false;
  if (s.points.length == 1) return s.points.first.v.dist(p) <= r;
  for (var i = 1; i < s.points.length; i++) {
    if (distToSegment(p, s.points[i - 1].v, s.points[i].v) <= r) return true;
  }
  return false;
}

/// Partial eraser: removes the parts of [s] inside the eraser circle.
/// Returns `[s]` (same instance) if untouched, `[]` if fully erased,
/// otherwise the remaining pieces with new ids.
List<StrokeEl> eraseStroke(StrokeEl s, Vec2 center, double radius) {
  if (!strokeHit(s, center, radius)) return [s];
  final r = radius + s.width / 2;
  final runs = <List<InkPoint>>[];
  var cur = <InkPoint>[];
  for (var i = 0; i < s.points.length; i++) {
    final p = s.points[i];
    final inside = p.v.dist(center) <= r;
    final segCut = i > 0 && !inside && cur.isNotEmpty && distToSegment(center, s.points[i - 1].v, p.v) <= r;
    if (inside || segCut) {
      if (cur.length >= 2) runs.add(cur);
      cur = inside ? <InkPoint>[] : <InkPoint>[p];
    } else {
      cur.add(p);
    }
  }
  if (cur.length >= 2) runs.add(cur);
  return [for (final run in runs) s.copyWith(id: newId(), points: run)];
}
