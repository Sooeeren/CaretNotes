import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/library/library_store.dart';
import '../../core/model/folder_meta.dart';
import '../../core/model/note.dart';
import '../controllers.dart';
import 'breadcrumbs.dart';
import 'dialogs.dart';
import 'folder_grid.dart';
import 'sidebar.dart';

/// Optional hooks wired up by the app (sync status, PDF import live in other modules).
WidgetBuilder? sidebarFooterBuilder;
Future<void> Function(BuildContext context)? importPdfAction;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _search = TextEditingController();
  bool _sidebarHidden = false;
  final _scaffold = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final narrow = c.maxWidth < 600;
      final compact = c.maxWidth < 900;
      final footer = sidebarFooterBuilder?.call(context);
      final main = _MainArea(
        search: _search,
        onToggleSidebar: () {
          if (narrow) {
            _scaffold.currentState?.openDrawer();
          } else {
            setState(() => _sidebarHidden = !_sidebarHidden);
          }
        },
      );
      return Scaffold(
        key: _scaffold,
        drawer: narrow ? Drawer(child: Sidebar(footer: footer, onNavigate: () => Navigator.of(context).maybePop())) : null,
        body: SafeArea(
          child: Row(children: [
            if (!narrow && !_sidebarHidden) Sidebar(compact: compact, footer: compact ? null : footer),
            Expanded(child: main),
          ]),
        ),
      );
    });
  }
}

class _MainArea extends StatelessWidget {
  final TextEditingController search;
  final VoidCallback onToggleSidebar;
  const _MainArea({required this.search, required this.onToggleSidebar});

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryController>();
    final t = Theme.of(context);
    final title = switch (lib.view) {
      HomeView.folder => null,
      HomeView.recent => 'Recent',
      HomeView.favorites => 'Favorites',
      HomeView.trash => 'Recently deleted',
      HomeView.search => 'Search results',
    };

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        height: 60,
        padding: const EdgeInsets.fromLTRB(12, 0, 20, 0),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor))),
        child: Row(children: [
          IconButton(tooltip: 'Toggle sidebar', icon: const Icon(Icons.menu), onPressed: onToggleSidebar),
          const SizedBox(width: 4),
          Expanded(
            child: title == null
                ? Breadcrumbs(relDir: lib.currentDir, onOpen: lib.openFolder)
                : Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(title, style: t.textTheme.titleLarge),
                  ),
          ),
          SizedBox(
            width: 240,
            child: TextField(
              controller: search,
              decoration: InputDecoration(
                hintText: 'Search',
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true,
                suffixIcon: search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          search.clear();
                          lib.search('');
                        },
                      ),
              ),
              onChanged: lib.search,
            ),
          ),
          const SizedBox(width: 8),
          if (lib.view == HomeView.folder) _SortMenu(meta: lib.currentMeta),
          if (lib.view != HomeView.trash)
            IconButton(
              tooltip: 'Select several',
              isSelected: lib.selecting,
              icon: const Icon(Icons.checklist),
              onPressed: () => lib.setSelecting(!lib.selecting),
            ),
          IconButton(
            tooltip: lib.grid ? 'List view' : 'Grid view',
            icon: Icon(lib.grid ? Icons.view_list_outlined : Icons.grid_view),
            onPressed: lib.toggleGrid,
          ),
          const SizedBox(width: 4),
          if (lib.view == HomeView.trash)
            TextButton.icon(
              onPressed: lib.trash.isEmpty
                  ? null
                  : () async {
                      if (await confirm(context, 'Empty Recently deleted?', 'These items will be deleted permanently.', ok: 'Empty')) {
                        await lib.emptyTrash();
                      }
                    },
              icon: const Icon(Icons.delete_forever_outlined),
              label: const Text('Empty'),
            )
          else
            const _NewButton(),
        ]),
      ),
      Expanded(child: _content(context, lib)),
      if (lib.selecting) _SelectionBar(lib: lib),
    ]);
  }

  Widget _content(BuildContext context, LibraryController lib) {
    if (lib.view == HomeView.trash) return _TrashList(items: lib.trash);
    final folders = lib.view == HomeView.folder ? lib.listing.folders : const <FolderEntry>[];
    final notes = lib.view == HomeView.folder ? lib.listing.notes : lib.special;
    final showFolder = lib.view != HomeView.folder;
    if (folders.isEmpty && notes.isEmpty) {
      return _Empty(view: lib.view);
    }
    if (!lib.grid) {
      return ListView(padding: const EdgeInsets.fromLTRB(24, 12, 24, 24), children: [
        for (final f in folders) Padding(padding: const EdgeInsets.only(bottom: 8), child: FolderRow(folder: f)),
        for (final n in notes) Padding(padding: const EdgeInsets.only(bottom: 8), child: NoteRow(note: n, showFolder: showFolder)),
      ]);
    }
    final t = Theme.of(context);
    Widget label(String text) => SliverPadding(
          padding: const EdgeInsets.fromLTRB(28, 8, 28, 10),
          sliver: SliverToBoxAdapter(
            child: Text(text, style: t.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
          ),
        );
    return CustomScrollView(slivers: [
      const SliverToBoxAdapter(child: SizedBox(height: 12)),
      if (folders.isNotEmpty && lib.view == HomeView.folder) label('Folders'),
      if (folders.isNotEmpty)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 280, mainAxisExtent: 58, crossAxisSpacing: 10, mainAxisSpacing: 10),
            delegate: SliverChildBuilderDelegate((ctx, i) => FolderTile(folder: folders[i]), childCount: folders.length),
          ),
        ),
      if (notes.isNotEmpty && lib.view == HomeView.folder) label(notes.length == 1 ? '1 note' : '${notes.length} notes'),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 32),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 190, childAspectRatio: 0.66, crossAxisSpacing: 14, mainAxisSpacing: 18),
          delegate: SliverChildBuilderDelegate((ctx, i) => NoteCard(note: notes[i], showFolder: showFolder), childCount: notes.length),
        ),
      ),
    ]);
  }
}

class _SelectionBar extends StatelessWidget {
  final LibraryController lib;
  const _SelectionBar({required this.lib});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final n = lib.selected.length;
    return Material(
      color: t.colorScheme.surfaceContainerLow,
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          Text(n == 0 ? 'Tap notes or folders to select them' : '$n selected', style: t.textTheme.titleSmall),
          const Spacer(),
          TextButton.icon(
            onPressed: n == 0
                ? null
                : () async {
                    final d = await pickFolder(context, lib.tree);
                    if (d != null) await lib.moveSelected(d);
                  },
            icon: const Icon(Icons.drive_file_move_outline),
            label: const Text('Move to…'),
          ),
          TextButton.icon(
            onPressed: n == 0
                ? null
                : () async {
                    if (await confirm(context, 'Delete $n item${n == 1 ? '' : 's'}?', 'They move to Recently deleted for 30 days.')) {
                      await lib.deleteSelected();
                    }
                  },
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete'),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(onPressed: () => lib.setSelecting(false), child: const Text('Done')),
        ]),
      ),
    );
  }
}

class _SortMenu extends StatelessWidget {
  final FolderMeta meta;
  const _SortMenu({required this.meta});
  @override
  Widget build(BuildContext context) {
    final lib = context.read<LibraryController>();
    const labels = {
      SortMode.modified: 'Date edited',
      SortMode.created: 'Date created',
      SortMode.name: 'Name',
      SortMode.manual: 'Manual',
    };
    return PopupMenuButton<Object>(
      tooltip: 'Sort',
      icon: const Icon(Icons.sort),
      itemBuilder: (_) => [
        for (final e in labels.entries)
          CheckedPopupMenuItem(value: e.key, checked: meta.sort == e.key, child: Text(e.value)),
        const PopupMenuDivider(),
        CheckedPopupMenuItem(value: 'asc', checked: meta.ascending, child: const Text('Ascending')),
      ],
      onSelected: (v) {
        if (v is SortMode) lib.setSort(v, meta.ascending);
        if (v == 'asc') lib.setSort(meta.sort, !meta.ascending);
      },
    );
  }
}

class _NewButton extends StatelessWidget {
  const _NewButton();
  @override
  Widget build(BuildContext context) {
    final lib = context.read<LibraryController>();
    final device = context.read<SettingsController>().value.deviceName;
    Future<void> create(NoteLayout layout) async {
      final e = await lib.createNote(layout, device);
      if (context.mounted) openNote(context, e);
    }

    return PopupMenuButton<String>(
      tooltip: 'New',
      position: PopupMenuPosition.under,
      onSelected: (v) async {
        switch (v) {
          case 'paged':
            await create(NoteLayout.paged);
          case 'endless':
            await create(NoteLayout.endless);
          case 'canvas':
            await create(NoteLayout.canvas);
          case 'folder':
            final r = await editFolder(context);
            if (r != null) await lib.createFolder(r.$1, r.$2);
          case 'pdf':
            await importPdfAction?.call(context);
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'paged', child: ListTile(leading: Icon(Icons.description_outlined), title: Text('Note with pages'), subtitle: Text('A4 sheets'))),
        const PopupMenuItem(value: 'endless', child: ListTile(leading: Icon(Icons.view_agenda_outlined), title: Text('Endless note'), subtitle: Text('One long page'))),
        const PopupMenuItem(value: 'canvas', child: ListTile(leading: Icon(Icons.crop_free), title: Text('Canvas'), subtitle: Text('Infinite in every direction'))),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'folder', child: ListTile(leading: Icon(Icons.create_new_folder_outlined), title: Text('Folder'))),
        if (importPdfAction != null)
          const PopupMenuItem(value: 'pdf', child: ListTile(leading: Icon(Icons.picture_as_pdf_outlined), title: Text('Import PDF'))),
      ],
      child: IgnorePointer(
        child: FilledButton.icon(onPressed: () {}, icon: const Icon(Icons.add), label: const Text('New')),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final HomeView view;
  const _Empty({required this.view});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final (icon, text) = switch (view) {
      HomeView.favorites => (Icons.star_outline, 'No favorites yet. Use a note\'s menu to add one.'),
      HomeView.search => (Icons.search_off, 'Nothing found.'),
      HomeView.recent => (Icons.schedule_outlined, 'No notes yet.'),
      _ => (Icons.edit_note_outlined, 'This folder is empty. Tap "New" to start writing.'),
    };
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 64, color: t.colorScheme.outlineVariant),
        const SizedBox(height: 12),
        Text(text, style: t.textTheme.bodyLarge?.copyWith(color: t.colorScheme.onSurfaceVariant)),
      ]),
    );
  }
}

class _TrashList extends StatelessWidget {
  final List<TrashEntry> items;
  const _TrashList({required this.items});
  @override
  Widget build(BuildContext context) {
    final lib = context.read<LibraryController>();
    final t = Theme.of(context);
    if (items.isEmpty) {
      return Center(child: Text('Nothing here. Deleted items are kept for 30 days.', style: t.textTheme.bodyLarge));
    }
    return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 4),
        child: Text('Items are deleted permanently 30 days after they were removed.', style: t.textTheme.bodySmall),
      ),
      for (final e in items)
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Icon(e.isFolder ? Icons.folder_outlined : Icons.description_outlined),
            title: Text(e.name.replaceAll('.cnote', '')),
            subtitle: Text([
              'Deleted ${formatDate(e.deletedAt)}',
              if (dirOfRel(e.originalPath).isNotEmpty) 'from ${dirOfRel(e.originalPath)}',
              if (e.reason != null) e.reason!,
            ].join(' · ')),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              TextButton(onPressed: () => lib.restore(e), child: const Text('Restore')),
              IconButton(
                tooltip: 'Delete permanently',
                icon: const Icon(Icons.delete_forever_outlined),
                onPressed: () async {
                  if (await confirm(context, 'Delete permanently?', 'This can\'t be undone.')) await lib.deleteForever(e);
                },
              ),
            ]),
          ),
        ),
    ]);
  }
}
