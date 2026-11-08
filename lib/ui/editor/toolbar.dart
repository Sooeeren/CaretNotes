import 'package:flutter/material.dart';

import '../../core/model/elements.dart';
import '../../core/settings.dart';
import 'editor_controller.dart';
import 'tool_options.dart';

/// Where a toolbar dropped at [pos] (in the editor area) should dock.
ToolbarDock dockFor(Offset pos, Size area, {double edge = 90}) {
  if (pos.dy < edge) return ToolbarDock.top;
  if (pos.dx < edge) return ToolbarDock.left;
  if (pos.dx > area.width - edge) return ToolbarDock.right;
  return ToolbarDock.floating;
}

class EditorToolbar extends StatelessWidget {
  final EditorController c;
  final AppSettings settings;
  final Axis axis;
  final bool compact;
  final VoidCallback onBack;
  final VoidCallback onInsertImage;
  final VoidCallback onRename;
  final Widget moreMenu;
  final void Function(Offset global) onDragStart;
  final void Function(Offset global) onDragUpdate;
  final void Function(Offset global) onDragEnd;
  final ValueChanged<int> onPenColorsChanged;

  const EditorToolbar({
    super.key,
    required this.c,
    required this.settings,
    required this.axis,
    this.compact = false,
    required this.onBack,
    required this.onInsertImage,
    required this.onRename,
    required this.moreMenu,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onPenColorsChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final horizontal = axis == Axis.horizontal;

    Widget tool(EditorTool tl, IconData icon, String tip, {Color? accent, Widget Function()? options}) {
      final selected = c.tool == tl;
      return Builder(
        builder: (ctx) => _ToolButton(
          icon: icon,
          tooltip: tip,
          selected: selected,
          accent: accent,
          onTap: () {
            if (selected && options != null) {
              showToolOptions(ctx, options());
            } else {
              c.setTool(tl);
            }
          },
        ),
      );
    }

    final penIcon = switch (c.penKind) {
      ToolKind.fineliner => Icons.edit_outlined,
      ToolKind.pencil => Icons.create_rounded,
      _ => Icons.edit_rounded,
    };

    final items = <Widget>[
      IconButton(tooltip: 'Back', icon: const Icon(Icons.arrow_back_rounded), onPressed: onBack),
      if (horizontal && !compact)
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onRename,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text(c.note.title, overflow: TextOverflow.ellipsis, style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            ),
          ),
        ),
      _sep(horizontal),
      tool(EditorTool.pen, penIcon, 'Pen (tap again for options)',
          accent: Color(c.penColor), options: () => PenOptions(c: c, settings: settings, onColorsChanged: onPenColorsChanged)),
      tool(EditorTool.highlighter, Icons.brush_rounded, 'Highlighter', accent: Color(c.hlColor), options: () => HighlighterOptions(c: c)),
      tool(EditorTool.eraser, Icons.auto_fix_normal_rounded, 'Eraser', options: () => EraserOptions(c: c)),
      tool(EditorTool.select, c.selectMode == SelectMode.lasso ? Icons.gesture_rounded : Icons.highlight_alt_rounded, 'Select (lasso / box)',
          options: () => SelectOptions(c: c)),
      _ToolButton(
        icon: Icons.straighten_rounded,
        tooltip: 'Ruler (move & rotate with two fingers)',
        selected: c.rulerVisible,
        onTap: () => c.update(() => c.rulerVisible = !c.rulerVisible),
      ),
      tool(EditorTool.text, Icons.text_fields_rounded, 'Text (Markdown)'),
      _ToolButton(icon: Icons.add_photo_alternate_outlined, tooltip: 'Insert image', selected: false, onTap: onInsertImage),
      _sep(horizontal),
      if (!compact || !horizontal) ..._quickColors(horizontal),
      IconButton(tooltip: 'Undo (Ctrl+Z)', icon: const Icon(Icons.undo_rounded), onPressed: c.canUndo ? c.undo : null),
      IconButton(tooltip: 'Redo (Ctrl+Y)', icon: const Icon(Icons.redo_rounded), onPressed: c.canRedo ? c.redo : null),
      moreMenu,
    ];

    final bar = Material(
      color: t.colorScheme.surfaceContainerLow,
      elevation: settings.toolbarDock == ToolbarDock.floating ? 6 : 0,
      shadowColor: Colors.black38,
      borderRadius: settings.toolbarDock == ToolbarDock.floating ? BorderRadius.circular(28) : null,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: horizontal ? 8 : 4, vertical: horizontal ? 4 : 8),
        child: horizontal
            ? SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(mainAxisSize: MainAxisSize.min, children: items))
            : SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: items)),
      ),
    );

    return GestureDetector(
      onLongPressStart: (d) => onDragStart(d.globalPosition),
      onLongPressMoveUpdate: (d) => onDragUpdate(d.globalPosition),
      onLongPressEnd: (d) => onDragEnd(d.globalPosition),
      child: Tooltip(message: 'Hold to move the toolbar', waitDuration: const Duration(seconds: 2), child: bar),
    );
  }

  List<Widget> _quickColors(bool horizontal) {
    if (c.tool != EditorTool.pen && c.tool != EditorTool.highlighter) return const [];
    final hl = c.tool == EditorTool.highlighter;
    final colors = hl ? highlighterColors : settings.penColors.take(5).toList();
    final current = hl ? c.hlColor : c.penColor;
    return [
      for (final col in colors)
        InkWell(
          customBorder: const CircleBorder(),
          onTap: () => c.update(() => hl ? c.hlColor = col : c.penColor = col),
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: Color(col),
                shape: BoxShape.circle,
                border: Border.all(color: col == current ? Colors.white : Colors.transparent, width: 2),
                boxShadow: col == current ? [BoxShadow(color: Color(col), spreadRadius: 1.5)] : null,
              ),
            ),
          ),
        ),
      _sep(horizontal),
    ];
  }

  Widget _sep(bool horizontal) => horizontal
      ? const SizedBox(height: 28, child: VerticalDivider(width: 14))
      : const SizedBox(width: 28, child: Divider(height: 14));
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool selected;
  final Color? accent;
  final VoidCallback onTap;
  const _ToolButton({required this.icon, required this.tooltip, required this.selected, this.accent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Material(
          color: selected ? t.colorScheme.primary.withValues(alpha: 0.16) : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: selected ? BorderSide(color: t.colorScheme.primary, width: 1.5) : BorderSide.none,
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: SizedBox(
              width: 42,
              height: 42,
              child: Stack(alignment: Alignment.center, children: [
                Icon(icon, color: selected ? t.colorScheme.primary : t.colorScheme.onSurfaceVariant),
                if (accent != null)
                  Positioned(
                    bottom: 5,
                    child: Container(width: 16, height: 3, decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(2))),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
