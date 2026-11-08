import 'package:flutter/material.dart';

import '../../core/model/elements.dart';
import '../../core/settings.dart';
import 'editor_controller.dart';

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
      final left = pos.dx.clamp(8.0, size.width - 328);
      final below = pos.dy + box.size.height + 8;
      final top = below + 360 > size.height ? (pos.dy - 368).clamp(8.0, size.height - 368) : below;
      final right = pos.dx > size.width - 120;
      return Stack(children: [
        Positioned(
          left: right ? null : left.toDouble(),
          right: right ? size.width - pos.dx + 8 : null,
          top: right ? pos.dy.clamp(8.0, size.height - 368) : top.toDouble(),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(20),
            color: Theme.of(ctx).colorScheme.surfaceContainerLow,
            child: Padding(padding: const EdgeInsets.all(16), child: SizedBox(width: 288, child: child)),
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
  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final t = Theme.of(context);
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Pen', style: t.textTheme.titleSmall),
      const SizedBox(height: 8),
      SegmentedButton<ToolKind>(
        segments: const [
          ButtonSegment(value: ToolKind.pen, label: Text('Pen'), icon: Icon(Icons.edit_rounded)),
          ButtonSegment(value: ToolKind.fineliner, label: Text('Fine'), icon: Icon(Icons.edit_outlined)),
          ButtonSegment(value: ToolKind.pencil, label: Text('Pencil'), icon: Icon(Icons.create_rounded)),
        ],
        selected: {c.penKind},
        showSelectedIcon: false,
        onSelectionChanged: (s) => setState(() => c.update(() => c.penKind = s.first)),
      ),
      const SizedBox(height: 12),
      Text('Size ${c.penWidth.toStringAsFixed(1)}', style: t.textTheme.labelMedium),
      Slider(value: c.penWidth, min: 0.6, max: 12, onChanged: (v) => setState(() => c.update(() => c.penWidth = v))),
      Text('Colors', style: t.textTheme.labelMedium),
      const SizedBox(height: 6),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final col in {...widget.settings.penColors, ...extraColors})
          _Swatch(col, c.penColor == col, () {
            setState(() => c.update(() => c.penColor = col));
            widget.onColorsChanged(col);
          }),
      ]),
    ]);
  }
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
          ButtonSegment(value: SelectMode.lasso, label: Text('Lasso'), icon: Icon(Icons.gesture_rounded)),
          ButtonSegment(value: SelectMode.box, label: Text('Box'), icon: Icon(Icons.highlight_alt_rounded)),
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
