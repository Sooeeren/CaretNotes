import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// The app logo: an orange tile with a white handwritten loop on a faded ruled line,
/// ending in a plum pen-tip dot. A sibling of CaretFlow's logo (plum
/// tile, peach dot). Same drawing as docs/brand/icon.svg: a 440 unit tile; the PNG/ICO
/// icons are rendered from this painter by tool/icons/render_icons_test.dart.
class AppLogo extends StatelessWidget {
  final double size;
  const AppLogo({super.key, this.size = 24});

  @override
  Widget build(BuildContext context) =>
      SizedBox.square(dimension: size, child: const CustomPaint(painter: AppLogoPainter()));
}

class AppLogoPainter extends CustomPainter {
  /// [margin] is the empty border around the tile, as a fraction of the size
  /// (app icons on Windows and Linux leave a little room, like CaretFlow's).
  const AppLogoPainter({this.margin = 0});
  final double margin;

  static const _orangeTop = Color(0xFFF4A04E), _orangeBottom = Color(0xFFD06A24);
  static const _plumA = Color(0xFF8C66B8), _plumB = Color(0xFF5A3A80);
  static const _white = Color(0xFFFFFBF6);

  @override
  void paint(Canvas canvas, Size s) {
    final side = s.shortestSide * (1 - 2 * margin);
    final k = side / 440; // one SVG unit
    canvas.save();
    canvas.translate((s.width - side) / 2, (s.height - side) / 2);
    canvas.scale(k);
    const tile = Rect.fromLTWH(0, 0, 440, 440);
    final rrect = RRect.fromRectAndRadius(tile, const Radius.circular(104));
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_orangeTop, _orangeBottom],
        ).createShader(tile),
    );
    // soft rim: lighter at the top, darker at the bottom
    canvas.drawRRect(
      rrect.deflate(1.25),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..shader = ui.Gradient.linear(Offset.zero, const Offset(0, 440), [
          Colors.white.withValues(alpha: 0.3),
          Colors.black.withValues(alpha: 0.2),
        ]),
    );

    Paint stroke(double width, double opacity) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = _white.withValues(alpha: opacity);

    // a handwritten loop on a faded ruled line; the plum dot is the pen tip
    canvas.translate(-10, 12);
    canvas.drawLine(const Offset(100, 330), const Offset(340, 330), stroke(22, 0.4));
    canvas.drawPath(
      Path()
        ..moveTo(96, 270)
        ..cubicTo(160, 270, 236, 210, 236, 150)
        ..cubicTo(236, 104, 184, 104, 184, 152)
        ..cubicTo(184, 222, 214, 272, 268, 272)
        ..cubicTo(300, 272, 318, 252, 330, 232),
      stroke(32, 1),
    );
    const dot = Offset(346, 206);
    canvas.drawCircle(
      dot,
      22,
      Paint()..shader = const LinearGradient(colors: [_plumA, _plumB]).createShader(Rect.fromCircle(center: dot, radius: 22)),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(AppLogoPainter old) => old.margin != margin;
}
