import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/library/library_store.dart';
import '../../core/model/folder_meta.dart';
import '../controllers.dart';
import '../folder_style.dart';
import '../theme.dart';
import 'dialogs.dart';

/// Left navigation: library views, folder tree, Recently deleted, settings, sync status.
class Sidebar extends StatefulWidget {
  final bool compact;
  final Widget? footer;
  final VoidCallback? onNavigate;
  const Sidebar({super.key, this.compact = false, this.footer, this.onNavigate});

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  final Set<String> _expanded = {};

  Widget _item(
    BuildContext context,
    IconData icon,
    String label,
    bool selected,
    VoidCallback onTap, {
    Color? iconColor,
    Key? key,
    Widget? leading,
    double indent = 0,
  }) {
    final t = Theme.of(context);
    final tk = AppTokens.of(context);
    final tile = Material(
      color: selected ? tk.selectedFill : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        key: key,
        borderRadius: BorderRadius.circular(8),
        hoverColor: tk.selectedFill,
        onTap: () {
          onTap();
          widget.onNavigate?.call();
        },
        child: SizedBox(
          height: 34,
          child: Row(
            mainAxisAlignment: widget.compact ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              if (!widget.compact) SizedBox(width: 6 + indent),
              if (leading != null) leading,
              Icon(icon, size: 18, color: iconColor ?? (selected ? t.colorScheme.onSurface : tk.muted)),
              if (!widget.compact) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: t.textTheme.bodyMedium?.copyWith(
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      color: selected ? t.colorScheme.onSurface : t.colorScheme.onSurface.withValues(alpha: 0.86),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return widget.compact ? Tooltip(message: label, child: tile) : tile;
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryController>();
    final t = Theme.of(context);
    final tk = AppTokens.of(context);
    final width = widget.compact ? 60.0 : 252.0;

    Widget section(String label, {Widget? trailing}) => Padding(
          padding: const EdgeInsets.fromLTRB(10, 18, 2, 4),
          child: Row(children: [
            Expanded(
              child: Text(label, style: t.textTheme.labelMedium?.copyWith(color: tk.muted, fontWeight: FontWeight.w600)),
            ),
            ?trailing,
          ]),
        );

    final children = <Widget>[
      if (!widget.compact)
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 16, 10, 14),
          child: Row(children: [
            const _Mark(),
            const SizedBox(width: 10),
            Text('CaretNotes', style: t.textTheme.titleMedium?.copyWith(letterSpacing: -0.1)),
          ]),
        )
      else
        const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: _Mark())),
      _item(context, Icons.notes_outlined, 'All notes', lib.view == HomeView.folder && lib.currentDir.isEmpty, () => lib.openFolder('')),
      _item(context, Icons.schedule_outlined, 'Recent', lib.view == HomeView.recent, () => lib.show(HomeView.recent)),
      _item(context, Icons.star_outline, 'Favorites', lib.view == HomeView.favorites, () => lib.show(HomeView.favorites)),
      if (!widget.compact)
        section(
          'Folders',
          trailing: IconButton(
            tooltip: 'New folder',
            visualDensity: VisualDensity.compact,
            iconSize: 17,
            icon: const Icon(Icons.add),
            onPressed: () async {
              final r = await editFolder(context);
              if (r != null) await lib.createFolder(r.$1, r.$2, parent: '');
            },
          ),
        )
      else
        const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider()),
      ..._tree(context, lib, lib.tree.children, 0),
    ];

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: t.colorScheme.surfaceContainerLow,
        border: Border(right: BorderSide(color: tk.hairline)),
      ),
      child: Column(children: [
        Expanded(child: ListView(padding: const EdgeInsets.symmetric(horizontal: 8), children: children)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(children: [
            _item(context, Icons.delete_outline, 'Recently deleted', lib.view == HomeView.trash, () => lib.show(HomeView.trash)),
            _item(context, Icons.settings_outlined, 'Settings', false, () => Navigator.of(context).pushNamed('/settings')),
          ]),
        ),
        if (widget.footer != null) ...[
          const SizedBox(height: 6),
          Divider(color: tk.hairline),
          widget.footer!,
        ],
        const SizedBox(height: 6),
      ]),
    );
  }

  List<Widget> _tree(BuildContext context, LibraryController lib, List<FolderNode> nodes, int depth) {
    final out = <Widget>[];
    final t = Theme.of(context);
    for (final n in nodes) {
      final selected = lib.view == HomeView.folder && lib.currentDir == n.relPath;
      final open = _expanded.contains(n.relPath) || lib.currentDir.startsWith('${n.relPath}/');
      final chevron = SizedBox(
        width: 20,
        child: n.children.isEmpty
            ? null
            : InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: () => setState(() => open ? _expanded.remove(n.relPath) : _expanded.add(n.relPath)),
                child: Icon(open ? Icons.expand_more : Icons.chevron_right, size: 16, color: AppTokens.of(context).muted),
              ),
      );
      final row = DragTarget<String>(
        onWillAcceptWithDetails: (d) => d.data != n.relPath && !n.relPath.startsWith('${d.data}/'),
        onAcceptWithDetails: (d) => lib.move(d.data, n.relPath),
        builder: (ctx, cand, _) => DecoratedBox(
          decoration: cand.isNotEmpty
              ? BoxDecoration(border: Border.all(color: t.colorScheme.primary, width: 1.5), borderRadius: BorderRadius.circular(8))
              : const BoxDecoration(),
          child: GestureDetector(
            onSecondaryTapDown: (d) => _folderMenu(context, lib, n, d.globalPosition),
            child: _item(
              context,
              folderIcon(n.meta.icon),
              n.name,
              selected,
              () => lib.openFolder(n.relPath),
              iconColor: Color(n.meta.color),
              key: ValueKey('side-folder-${n.relPath}'),
              leading: widget.compact ? null : chevron,
              indent: widget.compact ? 0 : 12.0 * depth - 6,
            ),
          ),
        ),
      );
      out.add(row);
      if (open && !widget.compact) out.addAll(_tree(context, lib, n.children, depth + 1));
    }
    return out;
  }

  Future<void> _folderMenu(BuildContext context, LibraryController lib, FolderNode n, Offset pos) async {
    final v = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: const [
        PopupMenuItem(value: 'sub', child: Text('New subfolder')),
        PopupMenuItem(value: 'edit', child: Text('Rename, color & icon')),
        PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );
    if (!context.mounted) return;
    switch (v) {
      case 'sub':
        final r = await editFolder(context);
        if (r != null) await lib.createFolder(r.$1, r.$2, parent: n.relPath);
      case 'edit':
        await editFolderFlow(context, lib, n.relPath, n.meta);
      case 'delete':
        if (await confirm(context, 'Delete "${n.name}"?', 'The folder and its notes move to Recently deleted for 30 days.')) {
          await lib.delete(n.relPath);
        }
    }
  }
}

/// Small app mark: a caret on an ink square.
class _Mark extends StatelessWidget {
  const _Mark();
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(color: t.colorScheme.onSurface, borderRadius: BorderRadius.circular(6)),
      child: CustomPaint(painter: _CaretPainter(t.colorScheme.surfaceContainerLow, t.colorScheme.primary)),
    );
  }
}

class _CaretPainter extends CustomPainter {
  final Color ink, accent;
  _CaretPainter(this.ink, this.accent);
  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(s.width * 0.28, s.height * 0.62)
      ..lineTo(s.width * 0.5, s.height * 0.36)
      ..lineTo(s.width * 0.72, s.height * 0.62);
    canvas.drawPath(path, p);
    canvas.drawCircle(Offset(s.width * 0.5, s.height * 0.78), 1.6, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(_CaretPainter old) => old.ink != ink || old.accent != accent;
}

Future<void> editFolderFlow(BuildContext context, LibraryController lib, String relPath, FolderMeta meta) async {
  final name = relPath.split('/').last;
  final r = await editFolder(context, name: name, meta: meta, isNew: false);
  if (r == null) return;
  await lib.setFolderMeta(relPath, r.$2);
  if (r.$1 != name) await lib.renameFolder(relPath, r.$1);
}
