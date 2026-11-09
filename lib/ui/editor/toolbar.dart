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

/// The bar across the top: the note itself (back, title) and what you do with it
/// (undo, find, read mode, insert, pages, more). Drawing tools live in [ToolPill].
class NoteBar extends StatelessWidget {
  final EditorController c;
  final VoidCallback onBack;
  final VoidCallback onRename;
  final VoidCallback onFind;
  final bool finding;
  final Widget insertMenu;
  final Widget? pagesButton;
  final Widget moreMenu;

  const NoteBar({
    super.key,
    required this.c,
    required this.onBack,
    required this.onRename,
    required this.onFind,
    required this.finding,
    required this.insertMenu,
    required this.pagesButton,
    required this.moreMenu,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Material(
      color: t.colorScheme.surfaceContainerLow,
      child: SizedBox(
        height: 52,
        child: Row(
          children: [
            const SizedBox(width: 6),
            IconButton(tooltip: 'Back to notes', icon: const Icon(Icons.arrow_back), onPressed: onBack),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: onRename,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.note.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.titleSmall),
                        Text(_subtitle(), maxLines: 1, style: t.textTheme.bodySmall?.copyWith(fontSize: 11)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            IconButton(tooltip: 'Undo (Ctrl+Z)', icon: const Icon(Icons.undo), onPressed: c.canUndo && !c.readOnly ? c.undo : null),
            IconButton(tooltip: 'Redo (Ctrl+Y)', icon: const Icon(Icons.redo), onPressed: c.canRedo && !c.readOnly ? c.redo : null),
            const SizedBox(height: 22, child: VerticalDivider(width: 17)),
            BarToggle(icon: Icons.search, tooltip: 'Find in note (Ctrl+F)', on: finding, onTap: onFind),
            BarToggle(
              icon: Icons.visibility_outlined,
              tooltip: c.readOnly ? 'Read mode is on: tap to write again' : 'Read mode (only scroll, no accidental marks)',
              on: c.readOnly,
              onTap: c.toggleReadOnly,
            ),
            insertMenu,
            ?pagesButton,
            moreMenu,
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  String _subtitle() {
    final n = c.note;
    final kind = switch (n.layout) {
      NoteLayout.paged => n.pages.length == 1 ? '1 page' : '${n.pages.length} pages',
      NoteLayout.endless => 'Endless page',
      NoteLayout.canvas => 'Canvas',
    };
    return c.readOnly ? '$kind · Read mode' : kind;
  }
}

class BarToggle extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool on;
  final VoidCallback onTap;
  const BarToggle({super.key, required this.icon, required this.tooltip, required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return IconButton(
      tooltip: tooltip,
      style: IconButton.styleFrom(
        backgroundColor: on ? AppTokens.of(context).selectedFill : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      icon: Icon(icon, color: on ? t.colorScheme.primary : null),
      onPressed: onTap,
    );
  }
}

/// The drawing tools as a small rounded pill over the page. Tap a tool to pick it,
/// tap it again for its options (type, size, colors). Long-press and drag to move
/// it; drop near an edge to dock it there.
class ToolPill extends StatelessWidget {
  final EditorController c;
  final AppSettings settings;
  final Axis axis;
  final void Function(Offset global) onDragStart;
  final void Function(Offset global) onDragUpdate;
  final void Function(Offset global) onDragEnd;
  final ValueChanged<int> onPenColorsChanged;

  const ToolPill({
    super.key,
    required this.c,
    required this.settings,
    required this.axis,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onPenColorsChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tk = AppTokens.of(context);
    final horizontal = axis == Axis.horizontal;

    Widget tool(EditorTool tl, IconData icon, String tip, {Color? accent, Widget Function()? options}) {
      final selected = c.tool == tl && !c.readOnly;
      return Builder(
        builder: (ctx) => ToolButton(
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

    final tools = <Widget>[
      tool(
        EditorTool.text,
        c.textMode == TextMode.lines ? Icons.keyboard_alt_outlined : Icons.text_fields,
        c.textMode == TextMode.lines ? 'Type on the lines (tap again for options)' : 'Text box (tap again for options)',
        options: () => TextOptions(c: c),
      ),
      horizontal ? const SizedBox(height: 22, child: VerticalDivider(width: 13)) : const SizedBox(width: 22, child: Divider(height: 13)),
      tool(
        EditorTool.pen,
        penIcon,
        'Pen (tap again for type, size and color)',
        accent: Color(c.penColor),
        options: () => PenOptions(c: c, settings: settings, onColorsChanged: onPenColorsChanged),
      ),
      tool(
        EditorTool.highlighter,
        Icons.border_color_outlined,
        'Highlighter (tap again for color)',
        accent: Color(c.hlColor),
        options: () => HighlighterOptions(c: c),
      ),
      tool(EditorTool.eraser, Icons.auto_fix_normal_outlined, 'Eraser (tap again for options)', options: () => EraserOptions(c: c)),
      tool(
        EditorTool.select,
        c.selectMode == SelectMode.lasso ? Icons.gesture : Icons.highlight_alt,
        'Select (tap again for lasso / box)',
        options: () => SelectOptions(c: c),
      ),
      ToolButton(
        icon: Icons.straighten,
        tooltip: 'Ruler (move & rotate with two fingers)',
        selected: c.rulerVisible,
        onTap: () => c.update(() => c.rulerVisible = !c.rulerVisible),
      ),
    ];

    final pill = Material(
      color: t.colorScheme.surfaceContainerLow,
      elevation: 6,
      shadowColor: Colors.black38,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(26),
        side: BorderSide(color: tk.hairline),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: horizontal ? 8 : 4, vertical: horizontal ? 4 : 8),
        child: horizontal ? Row(mainAxisSize: MainAxisSize.min, children: tools) : Column(mainAxisSize: MainAxisSize.min, children: tools),
      ),
    );

    return GestureDetector(
      onLongPressStart: (d) => onDragStart(d.globalPosition),
      onLongPressMoveUpdate: (d) => onDragUpdate(d.globalPosition),
      onLongPressEnd: (d) => onDragEnd(d.globalPosition),
      child: AnimatedOpacity(opacity: c.readOnly ? 0.55 : 1, duration: const Duration(milliseconds: 150), child: pill),
    );
  }
}

class ToolButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool selected;
  final Color? accent;
  final VoidCallback onTap;
  const ToolButton({super.key, required this.icon, required this.tooltip, required this.selected, this.accent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: Padding(
        padding: const EdgeInsets.all(1.5),
        child: Material(
          color: selected ? AppTokens.of(context).selectedFill : Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 40,
              height: 40,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(icon, size: 20, color: selected ? t.colorScheme.primary : t.colorScheme.onSurfaceVariant),
                  if (accent != null)
                    Positioned(
                      bottom: 5,
                      child: Container(
                        width: 12,
                        height: 3,
                        decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(1.5)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
