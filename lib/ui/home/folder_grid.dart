import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/library/library_store.dart';
import '../controllers.dart';
import '../folder_style.dart';
import 'dialogs.dart';
import 'sidebar.dart';

String formatDate(DateTime utc) {
  final d = utc.toLocal();
  final now = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  if (d.year == now.year && d.month == now.month && d.day == now.day) return 'Today ${two(d.hour)}:${two(d.minute)}';
  if (d.year == now.year) return '${months[d.month - 1]} ${d.day}';
  return '${d.year}-${two(d.month)}-${two(d.day)}';
}

/// Hook for actions implemented elsewhere (export lives with the editor).
typedef NoteAction = Future<void> Function(BuildContext context, NoteEntry entry);
NoteAction? exportNoteAction;

void openNote(BuildContext context, NoteEntry e) async {
  if (e.damaged) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This note file is damaged and can\'t be opened.')));
    return;
  }
  await Navigator.of(context).pushNamed('/editor', arguments: e.relPath);
  if (context.mounted) await context.read<LibraryController>().refresh();
}

Future<void> showNoteMenu(BuildContext context, NoteEntry e, Offset pos) async {
  final lib = context.read<LibraryController>();
  final v = await showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
    items: [
      const PopupMenuItem(value: 'open', child: Text('Open')),
      const PopupMenuItem(value: 'rename', child: Text('Rename')),
      PopupMenuItem(value: 'fav', child: Text(e.favorite ? 'Remove from favorites' : 'Add to favorites')),
      const PopupMenuItem(value: 'move', child: Text('Move to…')),
      const PopupMenuItem(value: 'dup', child: Text('Duplicate')),
      if (exportNoteAction != null) const PopupMenuItem(value: 'export', child: Text('Export…')),
      const PopupMenuItem(value: 'delete', child: Text('Delete')),
    ],
  );
  if (!context.mounted || v == null) return;
  try {
    switch (v) {
      case 'open':
        openNote(context, e);
      case 'rename':
        final n = await askText(context, title: 'Rename note', initial: e.title);
        if (n != null) await lib.renameNote(e.relPath, n);
      case 'fav':
        await lib.setFavorite(e.relPath, !e.favorite);
      case 'move':
        final d = await pickFolder(context, lib.tree);
        if (d != null) await lib.move(e.relPath, d);
      case 'dup':
        await lib.duplicate(e.relPath);
      case 'export':
        await exportNoteAction!(context, e);
      case 'delete':
        await lib.delete(e.relPath);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('"${e.title}" moved to Recently deleted')));
        }
    }
  } catch (err) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $err')));
  }
}

Future<void> showFolderMenu(BuildContext context, FolderEntry f, Offset pos) async {
  final lib = context.read<LibraryController>();
  final v = await showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
    items: const [
      PopupMenuItem(value: 'open', child: Text('Open')),
      PopupMenuItem(value: 'edit', child: Text('Rename, color & icon')),
      PopupMenuItem(value: 'move', child: Text('Move to…')),
      PopupMenuItem(value: 'delete', child: Text('Delete')),
    ],
  );
  if (!context.mounted || v == null) return;
  switch (v) {
    case 'open':
      lib.openFolder(f.relPath);
    case 'edit':
      await editFolderFlow(context, lib, f.relPath, f.meta);
    case 'move':
      final d = await pickFolder(context, lib.tree, exclude: f.relPath);
      if (d != null) await lib.move(f.relPath, d);
    case 'delete':
      if (await confirm(context, 'Delete "${f.name}"?', 'The folder and its notes move to Recently deleted for 30 days.')) {
        await lib.delete(f.relPath);
      }
  }
}

/// Wraps a child so it can be dragged onto a folder after a short press (keeps touch scrolling working).
Widget _draggable(String data, Widget child, Widget feedback) => LongPressDraggable<String>(
      data: data,
      delay: const Duration(milliseconds: 250),
      feedback: feedback,
      childWhenDragging: Opacity(opacity: 0.4, child: child),
      child: child,
    );

Widget _feedback(BuildContext context, IconData icon, String label, Color color) => Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, color: color), const SizedBox(width: 8), Text(label)]),
      ),
    );

class FolderTile extends StatelessWidget {
  final FolderEntry folder;
  const FolderTile({super.key, required this.folder});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final color = Color(folder.meta.color);
    final lib = context.watch<LibraryController>();
    final tile = DragTarget<String>(
      onWillAcceptWithDetails: (d) => d.data != folder.relPath && !folder.relPath.startsWith('${d.data}/'),
      onAcceptWithDetails: (d) => context.read<LibraryController>().move(d.data, folder.relPath),
      builder: (ctx, cand, _) => Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: cand.isNotEmpty ? BorderSide(color: t.colorScheme.primary, width: 2) : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('folder-tile-${folder.name}'),
          onTap: () => lib.selecting ? lib.toggleSelect(folder.relPath) : lib.openFolder(folder.relPath),
          onSecondaryTapDown: (d) => showFolderMenu(context, folder, d.globalPosition),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
                  child: Icon(folderIcon(folder.meta.icon), color: Colors.white),
                ),
                const Spacer(),
                if (lib.selecting)
                  _Check(selected: lib.selected.contains(folder.relPath))
                else
                  _MoreButton(onTap: (pos) => showFolderMenu(context, folder, pos)),
              ]),
              const Spacer(),
              Text(folder.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text('${folder.itemCount} ${folder.itemCount == 1 ? 'item' : 'items'}',
                  style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
            ]),
          ),
        ),
      ),
    );
    return _draggable(folder.relPath, tile, _feedback(context, folderIcon(folder.meta.icon), folder.name, color));
  }
}

class _MoreButton extends StatelessWidget {
  final void Function(Offset) onTap;
  const _MoreButton({required this.onTap});
  @override
  Widget build(BuildContext context) => Builder(
        builder: (ctx) => IconButton(
          tooltip: 'More',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.more_vert_rounded),
          onPressed: () {
            final box = ctx.findRenderObject() as RenderBox;
            onTap(box.localToGlobal(box.size.bottomLeft(Offset.zero)));
          },
        ),
      );
}

IconData layoutIcon(String layout) => switch (layout) {
      'endless' => Icons.view_day_rounded,
      'canvas' => Icons.all_out_rounded,
      _ => Icons.description_rounded,
    };

class NoteCard extends StatelessWidget {
  final NoteEntry note;
  final bool showFolder;
  const NoteCard({super.key, required this.note, this.showFolder = false});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final lib = context.watch<LibraryController>();
    final isSel = lib.selected.contains(note.relPath);
    final card = Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isSel ? BorderSide(color: t.colorScheme.primary, width: 2.5) : BorderSide.none,
      ),
      child: InkWell(
        key: ValueKey('note-card-${note.relPath}'),
        onTap: () => lib.selecting ? lib.toggleSelect(note.relPath) : openNote(context, note),
        onSecondaryTapDown: (d) => showNoteMenu(context, note, d.globalPosition),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: Container(
              color: t.brightness == Brightness.dark ? const Color(0xFF2A2E35) : const Color(0xFFF0F2F6),
              child: note.damaged
                  ? Center(child: Icon(Icons.broken_image_outlined, size: 40, color: t.colorScheme.error))
                  : FutureBuilder<Uint8List?>(
                      future: lib.thumb(note),
                      builder: (ctx, s) => s.data == null
                          ? Center(child: Icon(layoutIcon(note.layout), size: 36, color: t.colorScheme.outlineVariant))
                          : Image.memory(s.data!, fit: BoxFit.cover, alignment: Alignment.topCenter, gaplessPlayback: true),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(note.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                  Text(
                    note.damaged ? 'Damaged file' : (showFolder && note.dir.isNotEmpty ? '${formatDate(note.modified)} · ${note.dir}' : formatDate(note.modified)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.textTheme.bodySmall?.copyWith(color: note.damaged ? t.colorScheme.error : t.colorScheme.onSurfaceVariant),
                  ),
                ]),
              ),
              if (note.favorite) Icon(Icons.star_rounded, size: 18, color: t.colorScheme.primary),
              if (lib.selecting) _Check(selected: isSel) else _MoreButton(onTap: (pos) => showNoteMenu(context, note, pos)),
            ]),
          ),
        ]),
      ),
    );
    // Drop another note of this folder here to place it before this one (manual order).
    final target = DragTarget<String>(
      onWillAcceptWithDetails: (d) =>
          lib.view == HomeView.folder && d.data != note.relPath && LibraryStore.isNoteFile(d.data.split('/').last) && dirOfRel(d.data) == note.dir,
      onAcceptWithDetails: (d) => lib.reorderBefore(d.data, note.relPath),
      builder: (ctx, cand, _) => Stack(children: [
        Positioned.fill(child: card),
        if (cand.isNotEmpty)
          Positioned(left: 0, top: 8, bottom: 8, child: Container(width: 4, decoration: BoxDecoration(color: t.colorScheme.primary, borderRadius: BorderRadius.circular(2)))),
      ]),
    );
    return _draggable(note.relPath, target, _feedback(context, layoutIcon(note.layout), note.title, t.colorScheme.primary));
  }
}

class _Check extends StatelessWidget {
  final bool selected;
  const _Check({required this.selected});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
            color: selected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outline),
      );
}

class NoteRow extends StatelessWidget {
  final NoteEntry note;
  final bool showFolder;
  const NoteRow({super.key, required this.note, this.showFolder = false});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return _draggable(
      note.relPath,
      Card(
        child: ListTile(
          key: ValueKey('note-card-${note.relPath}'),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          leading: Icon(note.damaged ? Icons.broken_image_outlined : layoutIcon(note.layout),
              color: note.damaged ? t.colorScheme.error : t.colorScheme.primary),
          title: Text(note.title),
          subtitle: Text(showFolder && note.dir.isNotEmpty ? '${formatDate(note.modified)} · ${note.dir}' : formatDate(note.modified)),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (note.favorite) Icon(Icons.star_rounded, size: 18, color: t.colorScheme.primary),
            _MoreButton(onTap: (pos) => showNoteMenu(context, note, pos)),
          ]),
          onTap: () {
            final lib = context.read<LibraryController>();
            lib.selecting ? lib.toggleSelect(note.relPath) : openNote(context, note);
          },
          selected: context.watch<LibraryController>().selected.contains(note.relPath),
        ),
      ),
      _feedback(context, layoutIcon(note.layout), note.title, t.colorScheme.primary),
    );
  }
}

class FolderRow extends StatelessWidget {
  final FolderEntry folder;
  const FolderRow({super.key, required this.folder});
  @override
  Widget build(BuildContext context) {
    final color = Color(folder.meta.color);
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) => d.data != folder.relPath && !folder.relPath.startsWith('${d.data}/'),
      onAcceptWithDetails: (d) => context.read<LibraryController>().move(d.data, folder.relPath),
      builder: (ctx, cand, _) => _draggable(
        folder.relPath,
        Card(
          child: ListTile(
            key: ValueKey('folder-tile-${folder.name}'),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: cand.isNotEmpty ? BorderSide(color: Theme.of(context).colorScheme.primary, width: 2) : BorderSide.none,
            ),
            leading: Icon(folderIcon(folder.meta.icon), color: color),
            title: Text(folder.name),
            subtitle: Text('${folder.itemCount} items'),
            trailing: _MoreButton(onTap: (pos) => showFolderMenu(context, folder, pos)),
            onTap: () => context.read<LibraryController>().openFolder(folder.relPath),
          ),
        ),
        _feedback(context, folderIcon(folder.meta.icon), folder.name, color),
      ),
    );
  }
}
