import 'package:flutter/material.dart';

import '../../core/model/elements.dart';
import '../../core/model/note.dart';
import '../../core/settings.dart';
import '../theme.dart';
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
    final floating = settings.toolbarDock == ToolbarDock.floating;
    final wide = horizontal && !compact && settings.toolbarDock == ToolbarDock.top;

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
      ToolKind.fineliner => Icons.drive_file_rename_outline,
      ToolKind.pencil => Icons.create_outlined,
      _ => Icons.edit_outlined,
    };

    final back = IconButton(tooltip: 'Back to notes', icon: const Icon(Icons.arrow_back), onPressed: onBack);
    final titleBlock = InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onRename,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(c.note.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.titleSmall),
          Text(_subtitle(), maxLines: 1, style: t.textTheme.bodySmall?.copyWith(fontSize: 11)),
        ]),
      ),
    );
    final history = <Widget>[
      IconButton(tooltip: 'Undo (Ctrl+Z)', icon: const Icon(Icons.undo), onPressed: c.canUndo ? c.undo : null),
      IconButton(tooltip: 'Redo (Ctrl+Y)', icon: const Icon(Icons.redo), onPressed: c.canRedo ? c.redo : null),
      moreMenu,
    ];

    final tools = <Widget>[
      tool(EditorTool.pen, penIcon, 'Pen (tap again for options)',
          accent: Color(c.penColor), options: () => PenOptions(c: c, settings: settings, onColorsChanged: onPenColorsChanged)),
      tool(EditorTool.highlighter, Icons.border_color_outlined, 'Highlighter', accent: Color(c.hlColor), options: () => HighlighterOptions(c: c)),
      tool(EditorTool.eraser, Icons.auto_fix_normal_outlined, 'Eraser', options: () => EraserOptions(c: c)),
      tool(EditorTool.select, c.selectMode == SelectMode.lasso ? Icons.gesture : Icons.highlight_alt, 'Select (lasso / box)',
          options: () => SelectOptions(c: c)),
      _ToolButton(
        icon: Icons.straighten,
        tooltip: 'Ruler (move & rotate with two fingers)',
        selected: c.rulerVisible,
        onTap: () => c.update(() => c.rulerVisible = !c.rulerVisible),
      ),
      tool(EditorTool.text, Icons.title, 'Text (Markdown)'),
      _ToolButton(icon: Icons.add_photo_alternate_outlined, tooltip: 'Insert image', selected: false, onTap: onInsertImage),
      if (!compact || !horizontal) ..._quickColors(horizontal),
    ];

    Widget content;
    if (wide) {
      // Title on the left, tools centered, history on the right.
      content = SizedBox(
        height: 52,
        child: Row(children: [
          const SizedBox(width: 6),
          back,
          ConstrainedBox(constraints: const BoxConstraints(maxWidth: 240), child: titleBlock),
          Expanded(
            child: Center(
              child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(mainAxisSize: MainAxisSize.min, children: tools)),
            ),
          ),
          ...history,
          const SizedBox(width: 8),
        ]),
      );
    } else {
      final all = <Widget>[back, _sep(horizontal), ...tools, _sep(horizontal), ...history];
      content = Padding(
        padding: EdgeInsets.symmetric(horizontal: horizontal ? 6 : 4, vertical: horizontal ? 4 : 8),
        child: horizontal
            ? SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(mainAxisSize: MainAxisSize.min, children: all))
            : SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: all)),
      );
    }

    final bar = Material(
      color: t.colorScheme.surfaceContainerLow,
      elevation: floating ? 8 : 0,
      shadowColor: Colors.black45,
      shape: floating ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: t.dividerColor)) : null,
      child: content,
    );

    return GestureDetector(
      onLongPressStart: (d) => onDragStart(d.globalPosition),
      onLongPressMoveUpdate: (d) => onDragUpdate(d.globalPosition),
      onLongPressEnd: (d) => onDragEnd(d.globalPosition),
      child: bar,
    );
  }

  String _subtitle() {
    final n = c.note;
    return switch (n.layout) {
      NoteLayout.paged => n.pages.length == 1 ? '1 page' : '${n.pages.length} pages',
      NoteLayout.endless => 'Endless page',
      NoteLayout.canvas => 'Canvas',
    };
  }

  List<Widget> _quickColors(bool horizontal) {
    if (c.tool != EditorTool.pen && c.tool != EditorTool.highlighter) return const [];
    final hl = c.tool == EditorTool.highlighter;
    final colors = hl ? highlighterColors : settings.penColors.take(5).toList();
    final current = hl ? c.hlColor : c.penColor;
    return [
      _sep(horizontal),
      for (final col in colors)
        Builder(
          builder: (context) => InkWell(
            customBorder: const CircleBorder(),
            onTap: () => c.update(() => hl ? c.hlColor = col : c.penColor = col),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Container(
                width: 24,
                height: 24,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: col == current ? Theme.of(context).colorScheme.onSurface : Colors.transparent, width: 1.5),
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(col),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.black.withValues(alpha: 0.12)),
                  ),
                ),
              ),
            ),
          ),
        ),
    ];
  }

  Widget _sep(bool horizontal) => horizontal
      ? const SizedBox(height: 22, child: VerticalDivider(width: 17))
      : const SizedBox(width: 22, child: Divider(height: 17));
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
        padding: const EdgeInsets.all(1.5),
        child: Material(
          color: selected ? AppTokens.of(context).selectedFill : Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: SizedBox(
              width: 38,
              height: 38,
              child: Stack(alignment: Alignment.center, children: [
                Icon(icon, size: 20, color: selected ? t.colorScheme.primary : t.colorScheme.onSurfaceVariant),
                if (accent != null)
                  Positioned(
                    bottom: 4,
                    child: Container(width: 12, height: 2, decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(1))),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
