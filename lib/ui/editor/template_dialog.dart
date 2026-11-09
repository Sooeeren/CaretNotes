import 'package:flutter/material.dart';

import '../../core/model/page.dart';
import '../../core/paper.dart';
import 'painters.dart';

/// Returns (template, applyToWholeNote) or null. A null template with whole=false means "use the note's template".
Future<(Template?, bool)?> showTemplateDialog(
  BuildContext context,
  Template current, {
  bool allowPageOnly = false,
  bool hasOverride = false,
  Size pageSize = const Size(595.28, 841.89),
}) =>
    showDialog<(Template?, bool)>(
      context: context,
      builder: (_) => _TemplateDialog(current: current, allowPageOnly: allowPageOnly, hasOverride: hasOverride, pageSize: pageSize),
    );

/// Paper colors: (paper, line, name).
const paperColors = [
  (0xFFFFFFFF, 0xFFD6E0F0, 'White'),
  (0xFFFBF7EC, 0xFFE3D9C0, 'Cream'),
  (0xFFEAF4EC, 0xFFC5DCC9, 'Mint'),
  (Template.darkPaper, Template.darkLine, 'Dark'),
];

/// The preset that [t] corresponds to, if any.
PaperPreset? presetOf(Template t) {
  for (final p in paperPresets) {
    if (p.kind == t.kind && (p.kind == TemplateKind.blank || (p.spacing - t.spacing).abs() < 0.5)) return p;
  }
  return null;
}

class _TemplateDialog extends StatefulWidget {
  final Template current;
  final bool allowPageOnly;
  final bool hasOverride;
  final Size pageSize;
  const _TemplateDialog({required this.current, required this.allowPageOnly, required this.hasOverride, required this.pageSize});
  @override
  State<_TemplateDialog> createState() => _TemplateDialogState();
}

class _TemplateDialogState extends State<_TemplateDialog> {
  late Template _t = widget.current;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final preset = presetOf(_t);
    final usesSpacing = _t.kind != TemplateKind.blank;
    return AlertDialog(
      title: Text(widget.allowPageOnly ? 'Page template' : 'Paper template'),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      content: SizedBox(
        width: 640,
        child: LayoutBuilder(builder: (context, box) {
          final narrow = box.maxWidth < 560;
          final presets = Wrap(
            spacing: 10,
            runSpacing: 12,
            children: [
              for (final p in paperPresets)
                _PresetCard(
                  preset: p,
                  template: _t.copyWith(kind: p.kind, spacing: p.spacing),
                  pageSize: widget.pageSize,
                  selected: identical(p, preset),
                  onTap: () => setState(() => _t = _t.copyWith(kind: p.kind, spacing: p.spacing)),
                ),
            ],
          );
          final side = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: PaperPreview(template: _t, pageSize: widget.pageSize, width: narrow ? 120 : 176)),
            const SizedBox(height: 14),
            Text('Paper', style: t.textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 6, children: [
              for (final p in paperColors)
                Tooltip(
                  message: p.$3,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => setState(() => _t = _t.copyWith(paperColor: p.$1, lineColor: p.$2)),
                    child: Container(
                      width: 30,
                      height: 30,
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: _t.paperColor == p.$1 ? t.colorScheme.primary : Colors.transparent, width: 2),
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Color(p.$1),
                          shape: BoxShape.circle,
                          border: Border.all(color: t.dividerColor),
                        ),
                      ),
                    ),
                  ),
                ),
            ]),
            if (usesSpacing) ...[
              const SizedBox(height: 12),
              Text('Spacing ${(_t.spacing / 2.83465).toStringAsFixed(1)} mm', style: t.textTheme.labelLarge),
              Slider(value: _t.spacing.clamp(10.0, 48.0), min: 10, max: 48, onChanged: (v) => setState(() => _t = _t.copyWith(spacing: v))),
            ],
          ]);
          return SingleChildScrollView(
            child: narrow
                ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [side, const SizedBox(height: 16), presets])
                : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: presets),
                    const SizedBox(width: 20),
                    SizedBox(width: 200, child: side),
                  ]),
          );
        }),
      ),
      actions: [
        if (widget.allowPageOnly && widget.hasOverride)
          TextButton(onPressed: () => Navigator.pop(context, (null, false)), child: const Text('Use note template')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        if (widget.allowPageOnly) TextButton(onPressed: () => Navigator.pop(context, (_t, true)), child: const Text('Whole note')),
        FilledButton(onPressed: () => Navigator.pop(context, (_t, !widget.allowPageOnly)), child: Text(widget.allowPageOnly ? 'This page' : 'Apply')),
      ],
    );
  }
}

class _PresetCard extends StatelessWidget {
  final PaperPreset preset;
  final Template template;
  final Size pageSize;
  final bool selected;
  final VoidCallback onTap;
  const _PresetCard({required this.preset, required this.template, required this.pageSize, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: preset.name,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 112,
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? t.colorScheme.primary : Colors.transparent, width: 1.6),
            color: selected ? t.colorScheme.primary.withValues(alpha: 0.06) : null,
          ),
          child: Column(children: [
            PaperPreview(template: template, pageSize: pageSize, width: 76),
            const SizedBox(height: 6),
            Text(
              preset.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.textTheme.bodySmall?.copyWith(fontWeight: selected ? FontWeight.w600 : null),
            ),
          ]),
        ),
      ),
    );
  }
}

/// A small page drawn with [template], scaled down from a full page of [pageSize].
class PaperPreview extends StatelessWidget {
  final Template template;
  final Size pageSize;
  final double width;
  const PaperPreview({super.key, required this.template, required this.pageSize, required this.width});

  @override
  Widget build(BuildContext context) {
    final h = width * pageSize.height / pageSize.width;
    return Container(
      width: width,
      height: h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: Theme.of(context).dividerColor),
        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 4, offset: Offset(0, 1))],
      ),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(painter: _PreviewPainter(template, pageSize)),
    );
  }
}

class _PreviewPainter extends CustomPainter {
  final Template t;
  final Size page;
  _PreviewPainter(this.t, this.page);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / page.width;
    canvas.scale(s);
    final r = Offset.zero & page;
    // About one pixel wide at preview size, so the lines stay visible.
    paintTemplate(canvas, t, r, page: r, lineScale: (1 / s / 0.7).clamp(1.0, 12.0));
  }

  @override
  bool shouldRepaint(_PreviewPainter old) =>
      old.t.kind != t.kind || old.t.spacing != t.spacing || old.t.paperColor != t.paperColor || old.t.lineColor != t.lineColor || old.page != page;
}
