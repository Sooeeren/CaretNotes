import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/color_math.dart';
import '../theme.dart';

/// Opens the color wheel and returns the chosen color, or null when cancelled.
/// The swatch shows the color it started from ("Before") next to the new one.
Future<int?> showColorWheel(BuildContext context, int initial, {String title = 'Pick a color'}) => showDialog<int>(
  context: context,
  builder: (ctx) => _ColorWheelDialog(initial: initial, title: title),
);

/// A hue/saturation wheel: the angle is the hue, the distance from the middle the
/// saturation. Brightness is set separately (see the dialog's slider).
class ColorWheel extends StatelessWidget {
  final double hue, saturation, value;
  final void Function(double hue, double saturation) onChanged;
  final double size;
  const ColorWheel({
    super.key,
    required this.hue,
    required this.saturation,
    required this.value,
    required this.onChanged,
    this.size = 220,
  });

  void _pick(Offset p) {
    final r = size / 2;
    final d = p - Offset(r, r);
    var h = math.atan2(d.dy, d.dx) * 180 / math.pi;
    if (h < 0) h += 360;
    onChanged(h, (d.distance / r).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanDown: (d) => _pick(d.localPosition),
      onPanUpdate: (d) => _pick(d.localPosition),
      child: CustomPaint(size: Size.square(size), painter: _WheelPainter(hue, saturation, value, AppTokens.of(context).hairline)),
    );
  }
}

class _WheelPainter extends CustomPainter {
  final double hue, saturation, value;
  final Color rim;
  _WheelPainter(this.hue, this.saturation, this.value, this.rim);

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final c = Offset(r, r);
    final circle = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = SweepGradient(colors: [for (var h = 0; h <= 360; h += 30) Color(hsvToArgb(h.toDouble(), 1, 1))])
            .createShader(circle),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()..shader = const RadialGradient(colors: [Colors.white, Color(0x00FFFFFF)]).createShader(circle),
    );
    // Darken the whole wheel to the chosen brightness.
    canvas.drawCircle(c, r, Paint()..color = Colors.black.withValues(alpha: 1 - value));
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = rim,
    );
    final a = hue * math.pi / 180;
    final knob = c + Offset(math.cos(a), math.sin(a)) * saturation * r;
    canvas.drawCircle(knob, 9, Paint()..color = Color(hsvToArgb(hue, saturation, value)));
    canvas.drawCircle(
      knob,
      9,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white,
    );
    canvas.drawCircle(
      knob,
      10.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = Colors.black26,
    );
  }

  @override
  bool shouldRepaint(_WheelPainter old) => old.hue != hue || old.saturation != saturation || old.value != value;
}

class _ColorWheelDialog extends StatefulWidget {
  final int initial;
  final String title;
  const _ColorWheelDialog({required this.initial, required this.title});
  @override
  State<_ColorWheelDialog> createState() => _ColorWheelDialogState();
}

class _ColorWheelDialogState extends State<_ColorWheelDialog> {
  late double _h, _s, _v;

  void _hsv((double, double, double) c) {
    _h = c.$1;
    _s = c.$2;
    _v = c.$3;
  }

  late final TextEditingController _hex;

  int get _color => hsvToArgb(_h, _s, _v);

  @override
  void initState() {
    super.initState();
    _hsv(argbToHsv(widget.initial));
    _hex = TextEditingController(text: hexOf(widget.initial));
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _set(double h, double s, double v) => setState(() {
    _hsv((h, s, v));
    _hex.text = hexOf(_color);
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final rgb = _color;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 260,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ColorWheel(hue: _h, saturation: _s, value: _v, onChanged: (h, s) => _set(h, s, _v)),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.brightness_6_outlined, size: 18),
                Expanded(
                  child: Slider(value: _v, onChanged: (v) => _set(_h, _s, v)),
                ),
              ],
            ),
            Row(
              children: [
                _BeforeAfter(before: widget.initial, after: rgb),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _hex,
                    decoration: const InputDecoration(isDense: true, labelText: 'Hex'),
                    onChanged: (s) {
                      final c = parseHexColor(s);
                      if (c != null) setState(() => _hsv(argbToHsv(c)));
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('R ${rgb >> 16 & 0xFF}   G ${rgb >> 8 & 0xFF}   B ${rgb & 0xFF}', style: t.textTheme.bodySmall),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, parseHexColor(_hex.text) ?? rgb), child: const Text('Use color')),
      ],
    );
  }
}

/// The starting color and the new one side by side, labelled, so a change is easy to judge.
class _BeforeAfter extends StatelessWidget {
  final int before, after;
  const _BeforeAfter({required this.before, required this.after});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final line = AppTokens.of(context).hairline;
    Widget half(Key key, int color, BorderRadius r) => Container(
          key: key,
          width: 30,
          height: 36,
          decoration: BoxDecoration(color: Color(color), borderRadius: r, border: Border.all(color: line)),
        );
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        half(const ValueKey('color-before'), before, const BorderRadius.horizontal(left: Radius.circular(8))),
        half(const ValueKey('color-after'), after, const BorderRadius.horizontal(right: Radius.circular(8))),
      ]),
      const SizedBox(height: 2),
      Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(width: 30, child: Text('Before', textAlign: TextAlign.center, style: t.textTheme.labelSmall?.copyWith(fontSize: 9))),
        SizedBox(width: 30, child: Text('Now', textAlign: TextAlign.center, style: t.textTheme.labelSmall?.copyWith(fontSize: 9))),
      ]),
    ]);
  }
}
