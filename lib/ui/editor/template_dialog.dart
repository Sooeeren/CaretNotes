import 'package:flutter/material.dart';

import '../../core/model/page.dart';

/// Returns (template, applyToWholeNote) or null. A null template with whole=false means "use the note's template".
Future<(Template?, bool)?> showTemplateDialog(BuildContext context, Template current, {bool allowPageOnly = false, bool hasOverride = false}) =>
    showDialog<(Template?, bool)>(
      context: context,
      builder: (_) => _TemplateDialog(current: current, allowPageOnly: allowPageOnly, hasOverride: hasOverride),
    );

class _TemplateDialog extends StatefulWidget {
  final Template current;
  final bool allowPageOnly;
  final bool hasOverride;
  const _TemplateDialog({required this.current, required this.allowPageOnly, required this.hasOverride});
  @override
  State<_TemplateDialog> createState() => _TemplateDialogState();
}

class _TemplateDialogState extends State<_TemplateDialog> {
  late Template _t = widget.current;

  static const papers = [
    (0xFFFFFFFF, 0xFFD6E0F0, 'White'),
    (0xFFFBF7EC, 0xFFE3D9C0, 'Cream'),
    (0xFFEAF4EC, 0xFFC5DCC9, 'Mint'),
    (Template.darkPaper, Template.darkLine, 'Dark'),
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return AlertDialog(
      title: Text(widget.allowPageOnly ? 'Page template' : 'Paper template'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 10, children: [
            for (final k in TemplateKind.values)
              ChoiceChip(
                label: Text(switch (k) {
                  TemplateKind.blank => 'Blank',
                  TemplateKind.lined => 'Lined',
                  TemplateKind.grid => 'Grid',
                  TemplateKind.dots => 'Dots',
                }),
                selected: _t.kind == k,
                onSelected: (_) => setState(() => _t = _t.copyWith(kind: k)),
              ),
          ]),
          const SizedBox(height: 16),
          Text('Spacing ${(_t.spacing / 28.3465 * 10).toStringAsFixed(1)} mm', style: t.textTheme.labelLarge),
          Slider(value: _t.spacing, min: 10, max: 48, onChanged: (v) => setState(() => _t = _t.copyWith(spacing: v))),
          Text('Paper', style: t.textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(spacing: 10, children: [
            for (final p in papers)
              ChoiceChip(
                avatar: CircleAvatar(backgroundColor: Color(p.$1)),
                label: Text(p.$3),
                selected: _t.paperColor == p.$1,
                onSelected: (_) => setState(() => _t = _t.copyWith(paperColor: p.$1, lineColor: p.$2)),
              ),
          ]),
        ]),
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
