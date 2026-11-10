import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The app logo, shared with CaretFlow: a plum tile with two orbits, a white core and a
/// peach dot. Drawn from docs/brand/icon.svg (a 440 unit tile in a 512 unit box).
class AppLogo extends StatelessWidget {
  final double size;
  const AppLogo({super.key, this.size = 24});

  @override
  Widget build(BuildContext context) =>
      SizedBox.square(dimension: size, child: const CustomPaint(painter: AppLogoPainter()));
}

class AppLogoPainter extends CustomPainter {
  const AppLogoPainter();

  static const _plumTop = Color(0xFF735296), _plumBottom = Color(0xFF4B2F6E);
  static const _peachA = Color(0xFFFFA894), _peachB = Color(0xFFFF705A);
  static const _white = Color(0xFFFAF7FF);

  @override
  void paint(Canvas canvas, Size s) {
    final k = s.shortestSide / 440; // one SVG unit
    canvas.save();
    canvas.scale(k);
    const tile = Rect.fromLTWH(0, 0, 440, 440);
    final rrect = RRect.fromRectAndRadius(tile, const Radius.circular(104));
    canvas.drawRRect(
      rrect,
      Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_plumTop, _plumBottom]).createShader(tile),
    );

    const c = Offset(220, 220);
    void orbit(double degrees, double opacity) {
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(degrees * math.pi / 180);
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: 292, height: 128),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 24
          ..color = _white.withValues(alpha: opacity),
      );
      canvas.restore();
    }

    orbit(32, 0.35);
    orbit(-32, 0.95);
    canvas.drawCircle(c, 38, Paint()..color = _white);
    const dot = Offset(334, 146);
    canvas.drawCircle(
      dot,
      15,
      Paint()..shader = const LinearGradient(colors: [_peachA, _peachB]).createShader(Rect.fromCircle(center: dot, radius: 15)),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(AppLogoPainter old) => false;
}
