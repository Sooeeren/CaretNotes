import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/library/library_store.dart';
import '../../core/model/folder_meta.dart';
import '../controllers.dart';
import '../folder_style.dart';
import 'dialogs.dart';

/// Left navigation: Recent, Favorites, folder tree, Recently deleted, footer (sync status).
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

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryController>();
    final t = Theme.of(context);
    final width = widget.compact ? 72.0 : 280.0;

    Widget item(IconData icon, String label, bool selected, VoidCallback onTap, {Color? color, Key? key}) {
      final tile = Material(
        color: selected ? t.colorScheme.primary.withValues(alpha: 0.14) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          key: key,
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            onTap();
            widget.onNavigate?.call();
          },
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: widget.compact ? 0 : 12, vertical: 10),
            child: Row(
              mainAxisAlignment: widget.compact ? MainAxisAlignment.center : MainAxisAlignment.start,
              children: [
                Icon(icon, size: 22, color: color ?? (selected ? t.colorScheme.primary : t.colorScheme.onSurfaceVariant)),
                if (!widget.compact) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(label,
                        overflow: TextOverflow.ellipsis,
                        style: t.textTheme.bodyLarge?.copyWith(fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
      return widget.compact ? Tooltip(message: label, child: tile) : tile;
    }

    final children = <Widget>[
      const SizedBox(height: 12),
      if (!widget.compact)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
          child: Row(children: [
            Icon(Icons.edit_note_rounded, color: t.colorScheme.primary, size: 30),
            const SizedBox(width: 8),
            Flexible(
              child: Text('CaretNotes',
                  overflow: TextOverflow.ellipsis, style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      item(Icons.notes_rounded, 'All notes', lib.view == HomeView.folder && lib.currentDir.isEmpty, () => lib.openFolder('')),
      item(Icons.schedule_rounded, 'Recent', lib.view == HomeView.recent, () => lib.show(HomeView.recent)),
      item(Icons.star_rounded, 'Favorites', lib.view == HomeView.favorites, () => lib.show(HomeView.favorites)),
      if (!widget.compact)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 4, 4),
          child: Row(children: [
            Expanded(child: Text('Folders', style: t.textTheme.labelLarge?.copyWith(color: t.colorScheme.onSurfaceVariant))),
            IconButton(
              tooltip: 'New folder',
              icon: const Icon(Icons.create_new_folder_outlined, size: 20),
              onPressed: () async {
                final r = await editFolder(context);
                if (r != null) await lib.createFolder(r.$1, r.$2, parent: '');
              },
            ),
          ]),
        )
      else
        const Divider(height: 24),
      ..._tree(context, lib, lib.tree.children, 0, item),
    ];

    return Container(
      width: width,
      color: t.colorScheme.surfaceContainerLow,
      child: Column(children: [
        Expanded(child: ListView(padding: const EdgeInsets.symmetric(horizontal: 8), children: children)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: item(Icons.delete_outline_rounded, 'Recently deleted', lib.view == HomeView.trash, () => lib.show(HomeView.trash)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: item(Icons.settings_outlined, 'Settings', false, () => Navigator.of(context).pushNamed('/settings')),
        ),
        if (widget.footer != null) widget.footer!,
        const SizedBox(height: 8),
      ]),
    );
  }

  List<Widget> _tree(BuildContext context, LibraryController lib, List<FolderNode> nodes, int depth,
      Widget Function(IconData, String, bool, VoidCallback, {Color? color, Key? key}) item) {
    final out = <Widget>[];
    for (final n in nodes) {
      final selected = lib.view == HomeView.folder && lib.currentDir == n.relPath;
      final open = _expanded.contains(n.relPath) || lib.currentDir.startsWith('${n.relPath}/');
      final row = DragTarget<String>(
        onWillAcceptWithDetails: (d) => d.data != n.relPath && !n.relPath.startsWith('${d.data}/'),
        onAcceptWithDetails: (d) => lib.move(d.data, n.relPath),
        builder: (ctx, cand, _) => Container(
          decoration: cand.isNotEmpty
              ? BoxDecoration(border: Border.all(color: Theme.of(ctx).colorScheme.primary, width: 2), borderRadius: BorderRadius.circular(12))
              : null,
          child: widget.compact
              ? item(folderIcon(n.meta.icon), n.name, selected, () => lib.openFolder(n.relPath), color: Color(n.meta.color))
              : Row(children: [
                  SizedBox(width: 12.0 * depth),
                  SizedBox(
                    width: 28,
                    child: n.children.isEmpty
                        ? null
                        : IconButton(
                            padding: EdgeInsets.zero,
                            iconSize: 18,
                            icon: Icon(open ? Icons.expand_more_rounded : Icons.chevron_right_rounded),
                            onPressed: () => setState(() => open ? _expanded.remove(n.relPath) : _expanded.add(n.relPath)),
                          ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onSecondaryTapDown: (d) => _folderMenu(context, lib, n, d.globalPosition),
                      child: item(folderIcon(n.meta.icon), n.name, selected, () => lib.openFolder(n.relPath),
                          color: Color(n.meta.color), key: ValueKey('side-folder-${n.relPath}')),
                    ),
                  ),
                ]),
        ),
      );
      out.add(row);
      if (open && !widget.compact) out.addAll(_tree(context, lib, n.children, depth + 1, item));
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

Future<void> editFolderFlow(BuildContext context, LibraryController lib, String relPath, FolderMeta meta) async {
  final name = relPath.split('/').last;
  final r = await editFolder(context, name: name, meta: meta, isNew: false);
  if (r == null) return;
  await lib.setFolderMeta(relPath, r.$2);
  if (r.$1 != name) await lib.renameFolder(relPath, r.$1);
}
