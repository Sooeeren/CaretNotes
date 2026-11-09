import 'dart:math' as math;

/// 2D vector / point in document space (PDF points).
class Vec2 {
  final double x, y;
  const Vec2(this.x, this.y);
  static const zero = Vec2(0, 0);

  Vec2 operator +(Vec2 o) => Vec2(x + o.x, y + o.y);
  Vec2 operator -(Vec2 o) => Vec2(x - o.x, y - o.y);
  Vec2 operator *(double s) => Vec2(x * s, y * s);
  double dot(Vec2 o) => x * o.x + y * o.y;
  double cross(Vec2 o) => x * o.y - y * o.x;
  double get length => math.sqrt(x * x + y * y);
  double dist(Vec2 o) => (this - o).length;
  Vec2 normalized() {
    final l = length;
    return l == 0 ? Vec2.zero : Vec2(x / l, y / l);
  }

  Vec2 get perp => Vec2(-y, x);

  @override
  bool operator ==(Object other) => other is Vec2 && other.x == x && other.y == y;
  @override
  int get hashCode => Object.hash(x, y);
  @override
  String toString() => 'Vec2($x, $y)';
}

/// Axis-aligned rectangle.
class RectD {
  final double left, top, right, bottom;
  const RectD(this.left, this.top, this.right, this.bottom);

  factory RectD.fromPoints(Iterable<Vec2> pts) {
    var l = double.infinity, t = double.infinity, r = -double.infinity, b = -double.infinity;
    for (final p in pts) {
      if (p.x < l) l = p.x;
      if (p.y < t) t = p.y;
      if (p.x > r) r = p.x;
      if (p.y > b) b = p.y;
    }
    if (l == double.infinity) return const RectD(0, 0, 0, 0);
    return RectD(l, t, r, b);
  }

  double get width => right - left;
  double get height => bottom - top;
  Vec2 get center => Vec2((left + right) / 2, (top + bottom) / 2);
  Vec2 get topLeft => Vec2(left, top);
  Vec2 get bottomRight => Vec2(right, bottom);
  bool get isEmpty => width <= 0 || height <= 0;

  bool contains(Vec2 p) => p.x >= left && p.x <= right && p.y >= top && p.y <= bottom;
  bool overlaps(RectD o) => left <= o.right && o.left <= right && top <= o.bottom && o.top <= bottom;
  RectD union(RectD o) => RectD(math.min(left, o.left), math.min(top, o.top), math.max(right, o.right), math.max(bottom, o.bottom));
  RectD inflate(double d) => RectD(left - d, top - d, right + d, bottom + d);
  RectD translate(double dx, double dy) => RectD(left + dx, top + dy, right + dx, bottom + dy);
  List<Vec2> get corners => [Vec2(left, top), Vec2(right, top), Vec2(right, bottom), Vec2(left, bottom)];

  List<double> toJson() => [left, top, right, bottom];
  factory RectD.fromJson(List<dynamic> j) =>
      RectD((j[0] as num).toDouble(), (j[1] as num).toDouble(), (j[2] as num).toDouble(), (j[3] as num).toDouble());

  @override
  bool operator ==(Object other) =>
      other is RectD && other.left == left && other.top == top && other.right == right && other.bottom == bottom;
  @override
  int get hashCode => Object.hash(left, top, right, bottom);
  @override
  String toString() => 'RectD($left, $top, $right, $bottom)';
}

/// 2D affine transform: [a c e; b d f].
class Affine {
  final double a, b, c, d, e, f;
  const Affine(this.a, this.b, this.c, this.d, this.e, this.f);
  static const identity = Affine(1, 0, 0, 1, 0, 0);

  factory Affine.translate(double dx, double dy) => Affine(1, 0, 0, 1, dx, dy);
  factory Affine.scale(double sx, [double? sy]) => Affine(sx, 0, 0, sy ?? sx, 0, 0);
  factory Affine.rotate(double rad) {
    final cs = math.cos(rad), sn = math.sin(rad);
    return Affine(cs, sn, -sn, cs, 0, 0);
  }

  /// Transform applied about [pivot].
  factory Affine.about(Vec2 pivot, Affine t) =>
      Affine.translate(pivot.x, pivot.y) * t * Affine.translate(-pivot.x, -pivot.y);

  /// Composition: (this * o).apply(p) == this.apply(o.apply(p)).
  Affine operator *(Affine o) => Affine(
        a * o.a + c * o.b,
        b * o.a + d * o.b,
        a * o.c + c * o.d,
        b * o.c + d * o.d,
        a * o.e + c * o.f + e,
        b * o.e + d * o.f + f,
      );

  Vec2 apply(Vec2 p) => Vec2(a * p.x + c * p.y + e, b * p.x + d * p.y + f);

  /// Uniform-ish scale factor (geometric mean of axis scales).
  double get scaleFactor => math.sqrt((a * d - b * c).abs());
  double get rotation => math.atan2(b, a);
}

double _segDist(Vec2 p, Vec2 a, Vec2 b) {
  final ab = b - a;
  final len2 = ab.dot(ab);
  if (len2 == 0) return p.dist(a);
  var t = (p - a).dot(ab) / len2;
  t = t.clamp(0.0, 1.0);
  return p.dist(a + ab * t);
}

/// Distance from [p] to segment [a]-[b].
double distToSegment(Vec2 p, Vec2 a, Vec2 b) => _segDist(p, a, b);

/// Closest point to [p] on the infinite line through [a] with direction [dir].
Vec2 projectOnLine(Vec2 p, Vec2 a, Vec2 dir) {
  final n = dir.normalized();
  return a + n * (p - a).dot(n);
}

/// Ramer–Douglas–Peucker polyline simplification.
List<Vec2> rdp(List<Vec2> pts, double eps) {
  if (pts.length < 3) return List.of(pts);
  final keep = List<bool>.filled(pts.length, false);
  keep[0] = true;
  keep[pts.length - 1] = true;
  final stack = <(int, int)>[(0, pts.length - 1)];
  while (stack.isNotEmpty) {
    final (s, e) = stack.removeLast();
    var maxD = 0.0;
    var idx = -1;
    for (var i = s + 1; i < e; i++) {
      final dd = _segDist(pts[i], pts[s], pts[e]);
      if (dd > maxD) {
        maxD = dd;
        idx = i;
      }
    }
    if (idx != -1 && maxD > eps) {
      keep[idx] = true;
      stack.add((s, idx));
      stack.add((idx, e));
    }
  }
  return [for (var i = 0; i < pts.length; i++) if (keep[i]) pts[i]];
}

/// Even-odd rule point-in-polygon test.
bool pointInPolygon(Vec2 p, List<Vec2> poly) {
  var inside = false;
  for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    final pi = poly[i], pj = poly[j];
    if ((pi.y > p.y) != (pj.y > p.y) && p.x < (pj.x - pi.x) * (p.y - pi.y) / (pj.y - pi.y) + pi.x) {
      inside = !inside;
    }
  }
  return inside;
}

double polylineLength(List<Vec2> pts) {
  var l = 0.0;
  for (var i = 1; i < pts.length; i++) {
    l += pts[i].dist(pts[i - 1]);
  }
  return l;
}

/// Snaps [y] to the nearest multiple of [step] (ruled text after a move).
double snapToLines(double y, double step) => step <= 0 ? y : (y / step).round() * step;
