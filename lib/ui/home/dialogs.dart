import 'package:flutter/material.dart';

import '../../core/library/library_store.dart';
import '../../core/model/folder_meta.dart';
import '../folder_style.dart';

Future<String?> askText(BuildContext context, {required String title, String initial = '', String label = 'Name', String ok = 'Save'}) {
  final c = TextEditingController(text: initial);
  c.selection = TextSelection(baseOffset: 0, extentOffset: initial.length);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        decoration: InputDecoration(labelText: label),
        onSubmitted: (v) => Navigator.pop(ctx, v.trim().isEmpty ? null : v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim().isEmpty ? null : c.text.trim()), child: Text(ok)),
      ],
    ),
  );
}

Future<bool> confirm(BuildContext context, String title, String body, {String ok = 'Delete'}) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ok)),
        ],
      ),
    ) ??
    false;

/// Name + color + icon editor for folders. Returns (name, meta) or null.
Future<(String, FolderMeta)?> editFolder(BuildContext context, {String name = '', FolderMeta meta = const FolderMeta(), bool isNew = true}) {
  return showDialog<(String, FolderMeta)>(
    context: context,
    builder: (ctx) => _FolderDialog(name: name, meta: meta, isNew: isNew),
  );
}

class _FolderDialog extends StatefulWidget {
  final String name;
  final FolderMeta meta;
  final bool isNew;
  const _FolderDialog({required this.name, required this.meta, required this.isNew});
  @override
  State<_FolderDialog> createState() => _FolderDialogState();
}

class _FolderDialogState extends State<_FolderDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.name);
  late int _color = widget.meta.color;
  late String _icon = widget.meta.icon;

  void _done() {
    final n = _name.text.trim();
    if (n.isEmpty) return;
    Navigator.pop(context, (n, widget.meta.copyWith(color: _color, icon: _icon)));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.isNew ? 'New folder' : 'Edit folder'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              CircleAvatar(radius: 22, backgroundColor: Color(_color), child: Icon(folderIcon(_icon), color: Colors.white)),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _name,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Folder name'),
                  onSubmitted: (_) => _done(),
                ),
              ),
            ]),
            const SizedBox(height: 16),
            Text('Color', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final c in folderColors)
                InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => setState(() => _color = c),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Color(c),
                      shape: BoxShape.circle,
                      border: Border.all(color: c == _color ? Theme.of(context).colorScheme.onSurface : Colors.transparent, width: 3),
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 16),
            Text('Icon', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(spacing: 4, runSpacing: 4, children: [
              for (final e in folderIcons.entries)
                IconButton(
                  tooltip: e.key,
                  isSelected: e.key == _icon,
                  style: IconButton.styleFrom(
                    backgroundColor: e.key == _icon ? Color(_color).withValues(alpha: 0.18) : null,
                  ),
                  onPressed: () => setState(() => _icon = e.key),
                  icon: Icon(e.value, color: e.key == _icon ? Color(_color) : null),
                ),
            ]),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _done, child: Text(widget.isNew ? 'Create' : 'Save')),
      ],
    );
  }
}

/// Folder picker for "Move to…". Returns the chosen relDir.
Future<String?> pickFolder(BuildContext context, FolderNode tree, {String? exclude}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Move to…'),
      content: SizedBox(
        width: 400,
        height: 420,
        child: ListView(children: [
          ListTile(
            leading: const Icon(Icons.home_rounded),
            title: const Text('All notes'),
            onTap: () => Navigator.pop(ctx, ''),
          ),
          ..._nodes(ctx, tree.children, 1, exclude),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel'))],
    ),
  );
}

List<Widget> _nodes(BuildContext ctx, List<FolderNode> nodes, int depth, String? exclude) => [
      for (final n in nodes)
        if (exclude == null || (n.relPath != exclude && !n.relPath.startsWith('$exclude/'))) ...[
          ListTile(
            contentPadding: EdgeInsets.only(left: 16.0 * depth + 8, right: 8),
            leading: Icon(folderIcon(n.meta.icon), color: Color(n.meta.color)),
            title: Text(n.name),
            onTap: () => Navigator.pop(ctx, n.relPath),
          ),
          ..._nodes(ctx, n.children, depth + 1, exclude),
        ],
    ];
