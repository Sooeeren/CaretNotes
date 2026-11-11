import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/geometry.dart';

const _cm = 28.3465;

/// Snaps to 0/45/90/… degrees when within 3°.
double snapRulerAngle(double a) {
  const step = math.pi / 4;
  const tol = 3 * math.pi / 180;
  final k = (a / step).roundToDouble();
  return (a - k * step).abs() <= tol ? k * step : a;
}

/// On-screen ruler in document coordinates (points).
class RulerGeom {
  /// Default length; pinching with two fingers makes it longer or shorter.
  static const lengthPt = 20 * _cm;
  static const minLengthPt = 5 * _cm;
  static const maxLengthPt = 60 * _cm;
  static const thicknessPt = 2.2 * _cm;

  final Vec2 center;
  final double angle;
  final double length;
  const RulerGeom({required this.center, required this.angle, this.length = lengthPt});

  Vec2 get dir => Vec2(math.cos(angle), math.sin(angle));
  Vec2 get normal => Vec2(-math.sin(angle), math.cos(angle));

  /// (along, across) coordinates relative to the center line.
  (double, double) local(Vec2 p) {
    final d = p - center;
    return (d.dot(dir), d.dot(normal));
  }

  bool contains(Vec2 p, {double margin = 0}) {
    final (u, v) = local(p);
    return u.abs() <= length / 2 + margin && v.abs() <= thicknessPt / 2 + margin;
  }

  /// Which edge (-1 = top/left side, +1 = other side) [p] is near, within [threshold] points.
  int? edgeNear(Vec2 p, double threshold) {
    final (u, v) = local(p);
    if (u.abs() > length / 2 + threshold) return null;
    final dist = v.abs() - thicknessPt / 2;
    if (dist > threshold) return null;
    return v < 0 ? -1 : 1;
  }

  /// Projects [p] onto the given edge line.
  Vec2 project(Vec2 p, int side) {
    final (u, _) = local(p);
    return center + dir * u + normal * (side * thicknessPt / 2);
  }

  RulerGeom copyWith({Vec2? center, double? angle, double? length}) =>
      RulerGeom(center: center ?? this.center, angle: angle ?? this.angle, length: length ?? this.length);

  /// New ruler pose after two fingers moved from (a0, b0) to (a1, b1): moved, turned, and
  /// longer or shorter as the fingers spread or pinch.
  RulerGeom twoFinger(Vec2 a0, Vec2 b0, Vec2 a1, Vec2 b1) {
    final m0 = (a0 + b0) * 0.5, m1 = (a1 + b1) * 0.5;
    final d0 = b0 - a0, d1 = b1 - a1;
    final rot = math.atan2(d1.y, d1.x) - math.atan2(d0.y, d0.x);
    // rotate center about the old midpoint, then translate with the midpoint
    final c = center - m0;
    final rc = Vec2(c.x * math.cos(rot) - c.y * math.sin(rot), c.x * math.sin(rot) + c.y * math.cos(rot));
    final s0 = d0.length;
    final newLength = s0 < 1e-6 ? length : (length * d1.length / s0).clamp(minLengthPt, maxLengthPt);
    return RulerGeom(center: m1 + rc, angle: snapRulerAngle(angle + rot), length: newLength);
  }

  double get degrees {
    var d = angle * 180 / math.pi % 180;
    if (d < 0) d += 180;
    return d;
  }
}

/// Paints the ruler; [toScreen] maps document points to screen.
class RulerPainter extends CustomPainter {
  final RulerGeom ruler;
  final double scale;
  final Offset Function(Vec2) toScreen;
  final bool dark;
  RulerPainter(this.ruler, this.scale, this.toScreen, this.dark);

  @override
  void paint(Canvas canvas, Size size) {
    final c = toScreen(ruler.center);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(ruler.angle);
    canvas.scale(scale);
    final len = ruler.length, th = RulerGeom.thicknessPt;
    final body = Rect.fromCenter(center: Offset.zero, width: len, height: th);
    final rr = RRect.fromRectAndRadius(body, const Radius.circular(6));
    canvas.drawRRect(rr, Paint()..color = (dark ? const Color(0xFF3A3F48) : const Color(0xFFF7F3E8)).withValues(alpha: 0.88));
    canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1 / scale
          ..color = dark ? Colors.white54 : Colors.black45);
    final tick = Paint()
      ..color = dark ? Colors.white70 : Colors.black87
      ..strokeWidth = 0.7 / scale;
    final top = -th / 2;
    final mm = _cm / 10;
    final count = (len / mm).floor();
    for (var i = 0; i <= count; i++) {
      final x = -len / 2 + i * mm;
      final l = i % 10 == 0 ? 12.0 : (i % 5 == 0 ? 8.0 : 4.5);
      canvas.drawLine(Offset(x, top), Offset(x, top + l), tick);
      canvas.drawLine(Offset(x, -top), Offset(x, -top - l), tick);
      if (i % 10 == 0 && i > 0 && i < count) {
        final tp = TextPainter(
          text: TextSpan(text: '${i ~/ 10}', style: TextStyle(fontSize: 8, color: dark ? Colors.white70 : Colors.black87)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x - tp.width / 2, top + 13));
      }
    }
    final label = TextPainter(
      text: TextSpan(
        text: '${ruler.degrees.round()}°',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: dark ? Colors.white : Colors.black87),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(canvas, Offset(-label.width / 2, -label.height / 2 + 6));
    canvas.restore();
  }

  @override
  // Always: [toScreen] also moves with panning, which none of the fields show.
  bool shouldRepaint(RulerPainter old) => true;
}
