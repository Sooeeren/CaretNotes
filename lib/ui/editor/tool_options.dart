import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/color_math.dart';
import '../../core/ink/stroke_geometry.dart';
import '../../core/model/elements.dart';
import '../../core/settings.dart';
import 'color_wheel.dart';
import 'editor_controller.dart';
import 'painters.dart';

const highlighterColors = [0xFFFFE14D, 0xFF8BE36B, 0xFFFF8BC2, 0xFF6EC8FF, 0xFFFFB054];

const extraColors = [
  0xFF000000, 0xFF424242, 0xFF757575, 0xFFFFFFFF, 0xFF1B2A6B, 0xFF3B6FE0, 0xFF2BA6C8, 0xFF00897B,
  0xFF1A8F3C, 0xFF7CB342, 0xFFF2B705, 0xFFFF8A1F, 0xFFD23B3B, 0xFFE0457B, 0xFF9B3FD1, 0xFF6D4C41,
];

/// Shows a small panel anchored below/next to the widget of [context].
Future<void> showToolOptions(BuildContext context, Widget child) {
  final box = context.findRenderObject() as RenderBox;
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final pos = box.localToGlobal(Offset.zero, ancestor: overlay);
  final size = overlay.size;
  return showDialog(
    context: context,
    barrierColor: Colors.transparent,
    builder: (ctx) {
      final left = pos.dx.clamp(8.0, math.max(8.0, size.width - 328));
      final below = pos.dy + box.size.height + 8;
      final top = below + 470 > size.height ? (pos.dy - 478).clamp(8.0, math.max(8.0, size.height - 478)) : below;
      final right = pos.dx > size.width - 120;
      return Stack(children: [
        Positioned(
          left: right ? null : left.toDouble(),
          right: right ? size.width - pos.dx + 8 : null,
          top: right ? pos.dy.clamp(8.0, math.max(8.0, size.height - 478)) : top.toDouble(),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(20),
            color: Theme.of(ctx).colorScheme.surfaceContainerLow,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: math.max(120.0, size.height - 16)),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: SizedBox(width: 288, child: child),
              ),
            ),
          ),
        ),
      ]);
    },
  );
}

class _Swatch extends StatelessWidget {
  final int color;
  final bool selected;
  final VoidCallback onTap;
  const _Swatch(this.color, this.selected, this.onTap);
  @override
  Widget build(BuildContext context) => InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: Color(color),
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? Theme.of(context).colorScheme.primary : Colors.black12,
              width: selected ? 3 : 1,
            ),
          ),
        ),
      );
}

class PenOptions extends StatefulWidget {
  final EditorController c;
  final AppSettings settings;
  final ValueChanged<int> onColorsChanged;
  const PenOptions({super.key, required this.c, required this.settings, required this.onColorsChanged});
  @override
  State<PenOptions> createState() => _PenOptionsState();
}

class _PenOptionsState extends State<PenOptions> {
  static const _perPage = 10;
  late int _page;

  List<List<int>> get _pages => colorPages(widget.settings.penColors, extraColors, perPage: _perPage);

  @override
  void initState() {
    super.initState();
    // Start on the page that holds the current color.
    _page = _pages.indexWhere((p) => p.contains(widget.c.penColor)).clamp(0, _pages.length - 1);
  }

  void _pick(int col) {
    setState(() => widget.c.update(() => widget.c.penColor = col));
    widget.onColorsChanged(col);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final t = Theme.of(context);
    final pages = _pages;
    final page = _page.clamp(0, pages.length - 1);
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Pen', style: t.textTheme.titleSmall),
      const SizedBox(height: 8),
      PenPreview(kind: c.penKind, width: c.penWidth, color: c.penColor),
      const SizedBox(height: 10),
      SegmentedButton<ToolKind>(
        segments: const [
          ButtonSegment(value: ToolKind.pen, label: Text('Pen'), icon: Icon(Icons.edit_outlined)),
          ButtonSegment(value: ToolKind.fineliner, label: Text('Fine'), icon: Icon(Icons.drive_file_rename_outline)),
          ButtonSegment(value: ToolKind.pencil, label: Text('Pencil'), icon: Icon(Icons.create_outlined)),
        ],
        selected: {c.penKind},
        showSelectedIcon: false,
        onSelectionChanged: (s) => setState(() => c.update(() => c.penKind = s.first)),
      ),
      const SizedBox(height: 12),
      Text('Size ${c.penWidth.toStringAsFixed(1)}', style: t.textTheme.labelMedium),
      Slider(value: c.penWidth, min: 0.6, max: 12, onChanged: (v) => setState(() => c.update(() => c.penWidth = v))),
      Row(children: [
        Text('Colors', style: t.textTheme.labelMedium),
        const Spacer(),
        Text('${page + 1} / ${pages.length}', style: t.textTheme.labelSmall),
      ]),
      const SizedBox(height: 6),
      Row(children: [
        IconButton(
          tooltip: 'Previous colors',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.chevron_left),
          onPressed: page > 0 ? () => setState(() => _page = page - 1) : null,
        ),
        Expanded(
          child: SizedBox(
            height: 68,
            child: Center(
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final col in pages[page]) _Swatch(col, c.penColor == col, () => _pick(col)),
              ]),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Next colors',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.chevron_right),
          onPressed: page < pages.length - 1 ? () => setState(() => _page = page + 1) : null,
        ),
      ]),
      const SizedBox(height: 4),
      Center(
        child: TextButton.icon(
          icon: const Icon(Icons.palette_outlined, size: 18),
          label: const Text('Custom color…'),
          onPressed: () async {
            final col = await showColorWheel(context, c.penColor);
            if (col != null && mounted) _pick(col);
          },
        ),
      ),
    ]);
  }
}

/// A sample stroke drawn with the pen's type, size and color, like the real ink.
class PenPreview extends StatelessWidget {
  final ToolKind kind;
  final double width;
  final int color;
  const PenPreview({super.key, required this.kind, required this.width, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      width: double.infinity,
      decoration: BoxDecoration(
        // Paper, so dark and light inks both show.
        color: const Color(0xFFFCFBF8),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: CustomPaint(painter: _PreviewPainter(kind, width, color)),
    );
  }
}

class _PreviewPainter extends CustomPainter {
  final ToolKind kind;
  final double width;
  final int color;
  _PreviewPainter(this.kind, this.width, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    const n = 48;
    final pts = <InkPoint>[];
    for (var i = 0; i <= n; i++) {
      final f = i / n;
      final x = 18 + f * (size.width - 36);
      final y = size.height / 2 + math.sin(f * math.pi * 2.2) * size.height * 0.22;
      // Light at the ends, firm in the middle, as when writing.
      final p = 0.35 + 0.65 * math.sin(f * math.pi);
      pts.add(InkPoint(x, y, p));
    }
    canvas.drawPath(pathFromOutline(strokeOutline(pts, width, kind)), strokePaint(kind, color));
  }

  @override
  bool shouldRepaint(_PreviewPainter old) => old.kind != kind || old.width != width || old.color != color;
}

class HighlighterOptions extends StatefulWidget {
  final EditorController c;
  const HighlighterOptions({super.key, required this.c});
  @override
  State<HighlighterOptions> createState() => _HighlighterOptionsState();
}

class _HighlighterOptionsState extends State<HighlighterOptions> {
  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final t = Theme.of(context);
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Highlighter', style: t.textTheme.titleSmall),
      const SizedBox(height: 4),
      Text('Drawn behind your writing, so it stays readable.', style: t.textTheme.bodySmall),
      const SizedBox(height: 8),
      Text('Width ${c.hlWidth.round()}', style: t.textTheme.labelMedium),
      Slider(value: c.hlWidth, min: 4, max: 32, onChanged: (v) => setState(() => c.update(() => c.hlWidth = v))),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final col in highlighterColors) _Swatch(col, c.hlColor == col, () => setState(() => c.update(() => c.hlColor = col))),
      ]),
    ]);
  }
}

class EraserOptions extends StatefulWidget {
  final EditorController c;
  const EraserOptions({super.key, required this.c});
  @override
  State<EraserOptions> createState() => _EraserOptionsState();
}

class _EraserOptionsState extends State<EraserOptions> {
  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final t = Theme.of(context);
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Eraser', style: t.textTheme.titleSmall),
      const SizedBox(height: 8),
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: false, label: Text('Whole stroke')),
          ButtonSegment(value: true, label: Text('Partial')),
        ],
        selected: {c.eraserPartial},
        showSelectedIcon: false,
        onSelectionChanged: (s) => setState(() => c.update(() => c.eraserPartial = s.first)),
      ),
      const SizedBox(height: 12),
      Text('Size ${c.eraserSize.round()}', style: t.textTheme.labelMedium),
      Slider(value: c.eraserSize, min: 2, max: 40, onChanged: (v) => setState(() => c.update(() => c.eraserSize = v))),
    ]);
  }
}

class SelectOptions extends StatefulWidget {
  final EditorController c;
  const SelectOptions({super.key, required this.c});
  @override
  State<SelectOptions> createState() => _SelectOptionsState();
}

class _SelectOptionsState extends State<SelectOptions> {
  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Selection', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      SegmentedButton<SelectMode>(
        segments: const [
          ButtonSegment(value: SelectMode.box, label: Text('Box'), icon: Icon(Icons.highlight_alt)),
          ButtonSegment(value: SelectMode.lasso, label: Text('Lasso'), icon: Icon(Icons.gesture)),
        ],
        selected: {c.selectMode},
        showSelectedIcon: false,
        onSelectionChanged: (s) => setState(() => c.update(() => c.selectMode = s.first)),
      ),
      const SizedBox(height: 8),
      Text('Drag inside the frame to move, corners to resize, the top circle to rotate.',
          style: Theme.of(context).textTheme.bodySmall),
    ]);
  }
}

class TextOptions extends StatefulWidget {
  final EditorController c;
  const TextOptions({super.key, required this.c});
  @override
  State<TextOptions> createState() => _TextOptionsState();
}

class _TextOptionsState extends State<TextOptions> {
  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final t = Theme.of(context);
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Text', style: t.textTheme.titleSmall),
      const SizedBox(height: 8),
      SegmentedButton<TextMode>(
        segments: const [
          ButtonSegment(value: TextMode.lines, label: Text('On lines'), icon: Icon(Icons.notes)),
          ButtonSegment(value: TextMode.box, label: Text('Text box'), icon: Icon(Icons.text_fields)),
        ],
        selected: {c.textMode},
        showSelectedIcon: false,
        onSelectionChanged: (s) => setState(() => c.update(() => c.textMode = s.first)),
      ),
      const SizedBox(height: 8),
      Text(
        c.textMode == TextMode.lines
            ? 'Click a line and type. Text follows the paper\'s lines like in a notebook. Markdown works.'
            : 'Click anywhere for a free text box you can move and resize. Markdown, tables and math work.',
        style: t.textTheme.bodySmall,
      ),
    ]);
  }
}
