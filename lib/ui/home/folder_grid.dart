import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/library/library_store.dart';
import '../controllers.dart';
import '../folder_style.dart';
import '../menu.dart';
import '../theme.dart';
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
      iconMenuItem('open', Icons.open_in_new, 'Open'),
      iconMenuItem('rename', Icons.drive_file_rename_outline, 'Rename'),
      iconMenuItem('fav', e.favorite ? Icons.star : Icons.star_outline, e.favorite ? 'Remove from favorites' : 'Add to favorites'),
      iconMenuItem('move', Icons.drive_file_move_outline, 'Move to…'),
      iconMenuItem('dup', Icons.content_copy_outlined, 'Duplicate'),
      if (exportNoteAction != null) iconMenuItem('export', Icons.ios_share_outlined, 'Export…'),
      iconMenuItem('delete', Icons.delete_outline, 'Delete'),
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
    items: [
      iconMenuItem('open', Icons.folder_open_outlined, 'Open'),
      iconMenuItem('edit', Icons.palette_outlined, 'Rename, color & icon'),
      iconMenuItem('move', Icons.drive_file_move_outline, 'Move to…'),
      iconMenuItem('delete', Icons.delete_outline, 'Delete'),
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
      borderRadius: BorderRadius.circular(8),
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, color: color, size: 18), const SizedBox(width: 8), Text(label)]),
      ),
    );

class FolderTile extends StatelessWidget {
  final FolderEntry folder;
  const FolderTile({super.key, required this.folder});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tk = AppTokens.of(context);
    final color = Color(folder.meta.color);
    final lib = context.watch<LibraryController>();
    final isSel = lib.selected.contains(folder.relPath);
    final tile = DragTarget<String>(
      onWillAcceptWithDetails: (d) => d.data != folder.relPath && !folder.relPath.startsWith('${d.data}/'),
      onAcceptWithDetails: (d) => context.read<LibraryController>().move(d.data, folder.relPath),
      builder: (ctx, cand, _) => Material(
        color: t.colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: cand.isNotEmpty || isSel ? t.colorScheme.primary : tk.hairline, width: cand.isNotEmpty || isSel ? 1.5 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('folder-tile-${folder.name}'),
          hoverColor: tk.selectedFill,
          onTap: () => lib.selecting ? lib.toggleSelect(folder.relPath) : lib.openFolder(folder.relPath),
          onSecondaryTapDown: (d) => showFolderMenu(context, folder, d.globalPosition),
          child: Padding(
            padding: const EdgeInsets.only(left: 14, right: 2),
            child: Row(children: [
              Icon(folderIcon(folder.meta.icon), color: color, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(folder.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.titleSmall),
                  Text('${folder.itemCount} ${folder.itemCount == 1 ? 'item' : 'items'}', style: t.textTheme.bodySmall),
                ]),
              ),
              if (lib.selecting) _Check(selected: isSel) else _MoreButton(onTap: (pos) => showFolderMenu(context, folder, pos)),
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
          iconSize: 18,
          icon: const Icon(Icons.more_horiz),
          onPressed: () {
            final box = ctx.findRenderObject() as RenderBox;
            onTap(box.localToGlobal(box.size.bottomLeft(Offset.zero)));
          },
        ),
      );
}

IconData layoutIcon(String layout) => switch (layout) {
      'endless' => Icons.view_agenda_outlined,
      'canvas' => Icons.crop_free,
      _ => Icons.description_outlined,
    };

/// Empty sheet shown until a note has a rendered thumbnail.
class _PaperPlaceholder extends StatelessWidget {
  final String layout;
  const _PaperPlaceholder({required this.layout});
  @override
  Widget build(BuildContext context) => CustomPaint(painter: _PaperPainter(layout), child: const SizedBox.expand());
}

class _PaperPainter extends CustomPainter {
  final String layout;
  _PaperPainter(this.layout);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final line = Paint()
      ..color = const Color(0xFFDDE3EC)
      ..strokeWidth = 1;
    if (layout == 'canvas') {
      for (var y = 10.0; y < size.height; y += 12) {
        for (var x = 10.0; x < size.width; x += 12) {
          canvas.drawCircle(Offset(x, y), 0.8, line);
        }
      }
      return;
    }
    for (var y = 28.0; y < size.height; y += 12) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
    canvas.drawLine(const Offset(18, 0), Offset(18, size.height), Paint()..color = const Color(0x40E06666));
  }

  @override
  bool shouldRepaint(_PaperPainter old) => old.layout != layout;
}

class NoteCard extends StatelessWidget {
  final NoteEntry note;
  final bool showFolder;
  const NoteCard({super.key, required this.note, this.showFolder = false});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tk = AppTokens.of(context);
    final lib = context.watch<LibraryController>();
    final isSel = lib.selected.contains(note.relPath);
    final sub = note.damaged
        ? 'Damaged file'
        : (showFolder && note.dir.isNotEmpty ? '${formatDate(note.modified)} · ${note.dir}' : formatDate(note.modified));

    // A sheet of paper with the title underneath, like a notebook on a shelf.
    final card = InkWell(
      key: ValueKey('note-card-${note.relPath}'),
      borderRadius: BorderRadius.circular(10),
      hoverColor: tk.selectedFill,
      onTap: () => lib.selecting ? lib.toggleSelect(note.relPath) : openNote(context, note),
      onSecondaryTapDown: (d) => showNoteMenu(context, note, d.globalPosition),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: isSel ? t.colorScheme.primary : tk.hairline, width: isSel ? 2 : 1),
                boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 6, offset: Offset(0, 2))],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: Stack(fit: StackFit.expand, children: [
                  if (note.damaged)
                    ColoredBox(
                      color: t.colorScheme.surfaceContainerHigh,
                      child: Center(child: Icon(Icons.broken_image_outlined, size: 32, color: t.colorScheme.error)),
                    )
                  else
                    FutureBuilder<Uint8List?>(
                      future: lib.thumb(note),
                      builder: (ctx, s) => s.data == null
                          ? _PaperPlaceholder(layout: note.layout)
                          : Image.memory(s.data!, fit: BoxFit.cover, alignment: Alignment.topCenter, gaplessPlayback: true),
                    ),
                  if (lib.selecting) Positioned(top: 0, right: 0, child: _Check(selected: isSel)),
                  if (note.favorite && !lib.selecting)
                    Positioned(top: 6, right: 6, child: Icon(Icons.star, size: 16, color: t.colorScheme.primary)),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(note.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.titleSmall),
                const SizedBox(height: 1),
                Text(sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.textTheme.bodySmall?.copyWith(color: note.damaged ? t.colorScheme.error : null)),
              ]),
            ),
            if (!lib.selecting) _MoreButton(onTap: (pos) => showNoteMenu(context, note, pos)),
          ]),
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
        if (cand.isNotEmpty) Positioned(left: 0, top: 10, bottom: 10, child: Container(width: 2, color: t.colorScheme.primary)),
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
        child: Icon(selected ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 20, color: selected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outline),
      );
}

class NoteRow extends StatelessWidget {
  final NoteEntry note;
  final bool showFolder;
  const NoteRow({super.key, required this.note, this.showFolder = false});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final lib = context.watch<LibraryController>();
    return _draggable(
      note.relPath,
      Card(
        child: ListTile(
          key: ValueKey('note-card-${note.relPath}'),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          leading: Icon(note.damaged ? Icons.broken_image_outlined : layoutIcon(note.layout),
              color: note.damaged ? t.colorScheme.error : AppTokens.of(context).muted),
          title: Text(note.title, style: t.textTheme.titleSmall),
          subtitle: Text(showFolder && note.dir.isNotEmpty ? '${formatDate(note.modified)} · ${note.dir}' : formatDate(note.modified),
              style: t.textTheme.bodySmall),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (note.favorite) Icon(Icons.star, size: 16, color: t.colorScheme.primary),
            if (lib.selecting) _Check(selected: lib.selected.contains(note.relPath)) else _MoreButton(onTap: (pos) => showNoteMenu(context, note, pos)),
          ]),
          onTap: () => lib.selecting ? lib.toggleSelect(note.relPath) : openNote(context, note),
          selected: lib.selected.contains(note.relPath),
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
    final lib = context.watch<LibraryController>();
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) => d.data != folder.relPath && !folder.relPath.startsWith('${d.data}/'),
      onAcceptWithDetails: (d) => lib.move(d.data, folder.relPath),
      builder: (ctx, cand, _) => _draggable(
        folder.relPath,
        Card(
          child: ListTile(
            key: ValueKey('folder-tile-${folder.name}'),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: cand.isNotEmpty ? BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.5) : BorderSide.none,
            ),
            leading: Icon(folderIcon(folder.meta.icon), color: color),
            title: Text(folder.name, style: Theme.of(context).textTheme.titleSmall),
            subtitle: Text('${folder.itemCount} items', style: Theme.of(context).textTheme.bodySmall),
            trailing: lib.selecting
                ? _Check(selected: lib.selected.contains(folder.relPath))
                : _MoreButton(onTap: (pos) => showFolderMenu(context, folder, pos)),
            onTap: () => lib.selecting ? lib.toggleSelect(folder.relPath) : lib.openFolder(folder.relPath),
          ),
        ),
        _feedback(context, folderIcon(folder.meta.icon), folder.name, color),
      ),
    );
  }
}
