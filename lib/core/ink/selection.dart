import '../geometry.dart';
import '../model/elements.dart';

bool _strokeInside(StrokeEl s, bool Function(Vec2) inside) {
  if (s.points.isEmpty) return false;
  var n = 0;
  for (final p in s.points) {
    if (inside(p.v)) n++;
  }
  return n * 2 >= s.points.length;
}

bool _hit(Element e, bool Function(Vec2) inside) => switch (e) {
      StrokeEl s => _strokeInside(s, inside),
      _ => inside(e.bounds().center),
    };

/// Freehand lasso: strokes with ≥ 50 % of points inside, other elements by center.
Set<String> lassoHits(List<Element> elements, List<Vec2> polygon) {
  if (polygon.length < 3) return {};
  final b = RectD.fromPoints(polygon);
  bool inside(Vec2 p) => b.contains(p) && pointInPolygon(p, polygon);
  return {for (final e in elements) if (_hit(e, inside)) e.id};
}

/// Rectangle select, same rule as [lassoHits].
Set<String> boxHits(List<Element> elements, RectD rect) =>
    {for (final e in elements) if (_hit(e, rect.contains)) e.id};

RectD selectionBounds(Iterable<Element> elements) {
  RectD? r;
  for (final e in elements) {
    r = r == null ? e.bounds() : r.union(e.bounds());
  }
  return r ?? const RectD(0, 0, 0, 0);
}
