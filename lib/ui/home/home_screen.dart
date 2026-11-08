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
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 16, 8),
        child: Row(children: [
          IconButton(tooltip: 'Toggle sidebar', icon: const Icon(Icons.menu_rounded), onPressed: onToggleSidebar),
          const SizedBox(width: 4),
          Expanded(
            child: title == null
                ? Breadcrumbs(relDir: lib.currentDir, onOpen: lib.openFolder)
                : Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(title, style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
                  ),
          ),
          SizedBox(
            width: 240,
            child: TextField(
              controller: search,
              decoration: InputDecoration(
                hintText: 'Search',
                prefixIcon: const Icon(Icons.search_rounded),
                isDense: true,
                suffixIcon: search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded),
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
          IconButton(
            tooltip: lib.grid ? 'List view' : 'Grid view',
            icon: Icon(lib.grid ? Icons.view_list_rounded : Icons.grid_view_rounded),
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
              icon: const Icon(Icons.delete_forever_rounded),
              label: const Text('Empty'),
            )
          else
            const _NewButton(),
        ]),
      ),
      Expanded(child: _content(context, lib)),
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
      return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
        for (final f in folders) Padding(padding: const EdgeInsets.only(bottom: 8), child: FolderRow(folder: f)),
        for (final n in notes) Padding(padding: const EdgeInsets.only(bottom: 8), child: NoteRow(note: n, showFolder: showFolder)),
      ]);
    }
    return CustomScrollView(slivers: [
      if (folders.isNotEmpty)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220, mainAxisExtent: 130, crossAxisSpacing: 12, mainAxisSpacing: 12),
            delegate: SliverChildBuilderDelegate((ctx, i) => FolderTile(folder: folders[i]), childCount: folders.length),
          ),
        ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 200, childAspectRatio: 0.72, crossAxisSpacing: 12, mainAxisSpacing: 12),
          delegate: SliverChildBuilderDelegate((ctx, i) => NoteCard(note: notes[i], showFolder: showFolder), childCount: notes.length),
        ),
      ),
    ]);
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
      icon: const Icon(Icons.sort_rounded),
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
        const PopupMenuItem(value: 'paged', child: ListTile(leading: Icon(Icons.description_rounded), title: Text('Note with pages'), subtitle: Text('A4 sheets'))),
        const PopupMenuItem(value: 'endless', child: ListTile(leading: Icon(Icons.view_day_rounded), title: Text('Endless note'), subtitle: Text('One long page'))),
        const PopupMenuItem(value: 'canvas', child: ListTile(leading: Icon(Icons.all_out_rounded), title: Text('Canvas'), subtitle: Text('Infinite in every direction'))),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'folder', child: ListTile(leading: Icon(Icons.create_new_folder_rounded), title: Text('Folder'))),
        if (importPdfAction != null)
          const PopupMenuItem(value: 'pdf', child: ListTile(leading: Icon(Icons.picture_as_pdf_rounded), title: Text('Import PDF'))),
      ],
      child: IgnorePointer(
        child: FilledButton.icon(onPressed: () {}, icon: const Icon(Icons.add_rounded), label: const Text('New')),
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
      HomeView.favorites => (Icons.star_outline_rounded, 'No favorites yet. Use a note\'s menu to add one.'),
      HomeView.search => (Icons.search_off_rounded, 'Nothing found.'),
      HomeView.recent => (Icons.schedule_rounded, 'No notes yet.'),
      _ => (Icons.edit_note_rounded, 'This folder is empty. Tap "New" to start writing.'),
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
            leading: Icon(e.isFolder ? Icons.folder_rounded : Icons.description_rounded),
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
                icon: const Icon(Icons.delete_forever_rounded),
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
