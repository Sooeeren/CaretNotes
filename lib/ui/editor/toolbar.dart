import 'package:flutter/material.dart';

import '../../core/model/elements.dart';
import '../../core/model/note.dart';
import '../../core/settings.dart';
import '../theme.dart';
import '../window_chrome.dart';
import 'color_wheel.dart';
import 'editor_controller.dart';
import 'tool_options.dart';

/// Where a toolbar dropped at [pos] (in the editor area) should dock.
ToolbarDock dockFor(Offset pos, Size area, {double edge = 90}) {
  if (pos.dy < edge) return ToolbarDock.top;
  if (pos.dy > area.height - edge) return ToolbarDock.bottom;
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
  final VoidCallback onFullScreen;

  /// A small window: find, read mode and full screen move into [moreMenu], so the
  /// title keeps room (and the window stays easy to grab).
  final bool compact;
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
    required this.onFullScreen,
    this.compact = false,
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
        child: CaptionArea(
          child: Row(
            children: [
              const SizedBox(width: 6),
              IconButton(tooltip: 'Back to notes', icon: const Icon(Icons.arrow_back), onPressed: onBack),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  // Tap to rename, drag to move the window.
                  child: CaptionDrag(
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
              ),
              IconButton(
                tooltip: 'Undo (Ctrl+Z)',
                icon: const Icon(Icons.undo),
                onPressed: c.canUndo && !c.readOnly ? c.undo : null,
              ),
              IconButton(
                tooltip: 'Redo (Ctrl+Y)',
                icon: const Icon(Icons.redo),
                onPressed: c.canRedo && !c.readOnly ? c.redo : null,
              ),
              if (!compact) ...[
                const SizedBox(height: 22, child: VerticalDivider(width: 17)),
                BarToggle(icon: Icons.search, tooltip: 'Find in note (Ctrl+F)', on: finding, onTap: onFind),
                BarToggle(
                  icon: Icons.visibility_outlined,
                  tooltip: c.readOnly ? 'Read mode is on: tap to write again' : 'Read mode (only scroll, no accidental marks)',
                  on: c.readOnly,
                  onTap: c.toggleReadOnly,
                ),
              ],
              insertMenu,
              ?pagesButton,
              if (!compact)
                IconButton(tooltip: 'Full screen (F11)', icon: const Icon(Icons.fullscreen), onPressed: onFullScreen),
              moreMenu,
              // The gap is empty title bar: there is always a strip to grab the window by.
              const WindowButtons(height: 52, gap: 20, inactiveWidth: 8),
            ],
          ),
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
/// tap it again for its options (type, size, colors). Drag the grip (or long-press
/// anywhere) to move it; drop near an edge to dock it there.
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

  /// A quick color applies to the highlighter while it's in hand, otherwise to the pen
  /// (and picks the pen up again if another tool was in use).
  void _useColor(int col) {
    if (c.tool == EditorTool.highlighter && !c.readOnly) {
      c.update(() => c.hlColor = col);
      return;
    }
    c.update(() => c.penColor = col);
    if (c.tool != EditorTool.pen || c.readOnly) c.setTool(EditorTool.pen);
    onPenColorsChanged(col);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tk = AppTokens.of(context);
    final horizontal = axis == Axis.horizontal;

    Widget tool(
      EditorTool tl,
      IconData? icon,
      String tip, {
      Color? accent,
      Widget Function()? options,
      Widget Function(Color)? glyph,
    }) {
      final selected = c.tool == tl && !c.readOnly;
      return Builder(
        builder: (ctx) => ToolButton(
          icon: icon,
          glyph: glyph,
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

    Widget divider() => horizontal
        ? const SizedBox(height: 22, child: VerticalDivider(width: 13))
        : const SizedBox(width: 22, child: Divider(height: 13));
    final quick = settings.penColors.take(settings.quickColors).toList();
    final activeColor = c.tool == EditorTool.highlighter ? c.hlColor : c.penColor;

    final tools = <Widget>[
      Tooltip(
        message: 'Drag to move the toolbar',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) => onDragStart(d.globalPosition),
          onPanUpdate: (d) => onDragUpdate(d.globalPosition),
          onPanEnd: (d) => onDragEnd(d.globalPosition),
          child: MouseRegion(
            cursor: SystemMouseCursors.move,
            child: SizedBox(
              width: horizontal ? 22 : 40,
              height: horizontal ? 40 : 22,
              // Painted rather than an icon: the release build's icon font drops this glyph.
              child: CustomPaint(painter: _GripPainter(tk.muted, horizontal)),
            ),
          ),
        ),
      ),
      tool(
        EditorTool.text,
        c.textMode == TextMode.lines ? Icons.keyboard_alt_outlined : Icons.text_fields,
        c.textMode == TextMode.lines ? 'Type on the lines (tap again for options)' : 'Text box (tap again for options)',
        options: () => TextOptions(c: c),
      ),
      divider(),
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
      tool(
        EditorTool.eraser,
        null,
        'Eraser (tap again for options)',
        glyph: (color) => EraserGlyph(color: color),
        options: () => EraserOptions(c: c),
      ),
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
      divider(),
      for (final col in quick) QuickColor(color: col, selected: col == activeColor, onTap: () => _useColor(col)),
      ToolButton(
        icon: Icons.palette_outlined,
        tooltip: 'Any color…',
        selected: false,
        onTap: () async {
          final col = await showColorWheel(context, activeColor);
          if (col != null) _useColor(col);
        },
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
        child: horizontal
            ? Row(mainAxisSize: MainAxisSize.min, children: tools)
            : Column(mainAxisSize: MainAxisSize.min, children: tools),
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
  final IconData? icon;

  /// Drawn instead of [icon], in the given color (for tools without a fitting icon).
  final Widget Function(Color color)? glyph;
  final String tooltip;
  final bool selected;
  final Color? accent;
  final VoidCallback onTap;
  const ToolButton({
    super.key,
    this.icon,
    this.glyph,
    required this.tooltip,
    required this.selected,
    this.accent,
    required this.onTap,
  }) : assert(icon != null || glyph != null);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final fg = selected ? t.colorScheme.primary : t.colorScheme.onSurfaceVariant;
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
                  if (glyph != null) SizedBox.square(dimension: 20, child: glyph!(fg)) else Icon(icon, size: 20, color: fg),
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

/// One of the quick colors in the pill: a dot, ringed when it's the color in use.
class QuickColor extends StatelessWidget {
  final int color;
  final bool selected;
  final VoidCallback onTap;
  const QuickColor({super.key, required this.color, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final size = selected ? 24.0 : 20.0;
    return Padding(
      padding: const EdgeInsets.all(1.5),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 34,
          height: 34,
          child: Center(
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: Color(color),
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? t.colorScheme.primary : AppTokens.of(context).hairline,
                  width: selected ? 2.5 : 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// An outlined eraser block, tilted as if rubbing out the line under it.
class EraserGlyph extends StatelessWidget {
  final Color color;
  const EraserGlyph({super.key, required this.color});
  @override
  Widget build(BuildContext context) => CustomPaint(painter: _EraserPainter(color));
}

class _EraserPainter extends CustomPainter {
  final Color color;
  _EraserPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.width / 24; // drawn on a 24-unit grid, like Material icons
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7 * u
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    canvas.save();
    canvas.translate(12.5 * u, 10.5 * u);
    canvas.rotate(-0.7854); // 45 degrees
    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: 17 * u, height: 9 * u),
      Radius.circular(2 * u),
    );
    // The rubber end, filled lightly.
    canvas.save();
    canvas.clipRRect(body);
    canvas.drawRect(Rect.fromLTRB(-8.5 * u, -4.5 * u, -2.5 * u, 4.5 * u), Paint()..color = color.withValues(alpha: 0.35));
    canvas.restore();
    canvas.drawRRect(body, p);
    canvas.drawLine(Offset(-2.5 * u, -4.5 * u), Offset(-2.5 * u, 4.5 * u), p);
    canvas.restore();
    // The line being rubbed out.
    canvas.drawLine(Offset(9 * u, 21 * u), Offset(21 * u, 21 * u), p);
  }

  @override
  bool shouldRepaint(_EraserPainter old) => old.color != color;
}

/// Six dots, the usual "grab here" sign.
class _GripPainter extends CustomPainter {
  final Color color;
  final bool horizontal;
  _GripPainter(this.color, this.horizontal);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    final c = size.center(Offset.zero);
    for (final a in [-1.0, 1.0]) {
      for (final b in [-1.0, 0.0, 1.0]) {
        canvas.drawCircle(c + (horizontal ? Offset(a * 3, b * 5.5) : Offset(b * 5.5, a * 3)), 1.6, p);
      }
    }
  }

  @override
  bool shouldRepaint(_GripPainter old) => old.color != color || old.horizontal != horizontal;
}
