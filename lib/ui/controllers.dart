import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/library/library_store.dart';
import '../core/model/folder_meta.dart';
import '../core/model/note.dart';
import '../core/settings.dart';

class SettingsController extends ChangeNotifier {
  AppSettings _s;
  final String? _path;
  SettingsController(this._s, this._path);

  AppSettings get value => _s;

  Future<void> update(AppSettings Function(AppSettings) f) async {
    _s = f(_s);
    notifyListeners();
    if (_path != null) await _s.save(_path);
  }
}

enum HomeView { folder, recent, favorites, trash, search }

/// State of the home screen: which folder/view is shown and its contents.
class LibraryController extends ChangeNotifier {
  final LibraryStore store;
  LibraryController(this.store);

  HomeView view = HomeView.folder;
  String currentDir = '';
  String query = '';
  bool grid = true;

  FolderListing listing = const FolderListing([], []);
  List<NoteEntry> special = const [];
  List<TrashEntry> trash = const [];
  FolderNode tree = const FolderNode('', FolderMeta(), []);
  FolderMeta currentMeta = const FolderMeta();

  Future<void>? lastLoad;
  final Map<String, (DateTime, Uint8List?)> _thumbs = {};

  Future<void> refresh() => lastLoad = _load();

  Future<void> _load() async {
    await store.ensureRoot();
    tree = await store.tree();
    switch (view) {
      case HomeView.folder:
        listing = await store.listFolder(currentDir);
        currentMeta = await store.getFolderMeta(currentDir);
      case HomeView.recent:
        special = await store.recent(40);
      case HomeView.favorites:
        special = await store.favorites();
      case HomeView.trash:
        trash = await store.listTrash();
      case HomeView.search:
        special = await store.search(query);
    }
    notifyListeners();
  }

  void openFolder(String relDir) {
    view = HomeView.folder;
    currentDir = relDir;
    refresh();
  }

  void show(HomeView v) {
    view = v;
    refresh();
  }

  void search(String q) {
    query = q;
    view = q.trim().isEmpty ? HomeView.folder : HomeView.search;
    refresh();
  }

  void toggleGrid() {
    grid = !grid;
    notifyListeners();
  }

  Future<Uint8List?> thumb(NoteEntry e) async {
    final c = _thumbs[e.relPath];
    if (c != null && c.$1 == e.modified) return c.$2;
    final t = await store.loadThumb(e.relPath);
    _thumbs[e.relPath] = (e.modified, t);
    return t;
  }

  Future<NoteEntry> createNote(NoteLayout layout, String deviceName, {String? title, String? inDir}) async {
    final n = Note.create(title: title ?? _defaultTitle(), layout: layout, deviceName: deviceName);
    final e = await store.createNote(inDir ?? (view == HomeView.folder ? currentDir : ''), n);
    await refresh();
    return e;
  }

  String _defaultTitle() {
    final d = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'Note ${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}.${two(d.minute)}';
  }

  Future<void> createFolder(String name, FolderMeta meta, {String? parent}) async {
    await store.createFolder(parent ?? currentDir, name, meta);
    await refresh();
  }

  Future<void> setFolderMeta(String relDir, FolderMeta meta) async {
    await store.setFolderMeta(relDir, meta);
    await refresh();
  }

  Future<void> setSort(SortMode mode, bool ascending) =>
      setFolderMeta(currentDir, currentMeta.copyWith(sort: mode, ascending: ascending));

  Future<void> renameNote(String relPath, String title) async {
    await store.renameNote(relPath, title);
    await refresh();
  }

  Future<void> renameFolder(String relDir, String name) async {
    final n = await store.renameFolder(relDir, name);
    if (currentDir == relDir || currentDir.startsWith('$relDir/')) currentDir = n + currentDir.substring(relDir.length);
    await refresh();
  }

  Future<void> move(String relPath, String destDir) async {
    if (relPath == destDir) return;
    await store.move(relPath, destDir);
    await refresh();
  }

  Future<void> duplicate(String relPath) async {
    await store.duplicateNote(relPath);
    await refresh();
  }

  Future<void> setFavorite(String relPath, bool fav) async {
    await store.setFavorite(relPath, fav);
    await refresh();
  }

  Future<void> delete(String relPath) async {
    await store.trashItem(relPath);
    if (currentDir == relPath || currentDir.startsWith('$relPath/')) currentDir = dirOfRel(relPath);
    await refresh();
  }

  Future<void> restore(TrashEntry t) async {
    await store.restore(t);
    await refresh();
  }

  Future<void> deleteForever(TrashEntry t) async {
    await store.deleteForever(t);
    await refresh();
  }

  Future<void> emptyTrash() async {
    for (final t in await store.listTrash()) {
      await store.deleteForever(t);
    }
    await refresh();
  }

  /// Saves a manual order for the current folder after a drag reorder.
  Future<void> reorder(List<String> fileNames) =>
      setFolderMeta(currentDir, currentMeta.copyWith(sort: SortMode.manual, order: fileNames));
}
