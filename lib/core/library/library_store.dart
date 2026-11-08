import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../format/note_codec.dart';
import '../ids.dart';
import '../model/folder_meta.dart';
import '../model/note.dart';

class NoteEntry {
  final String relPath;
  final String title;
  final String? id;
  final DateTime modified;
  final DateTime created;
  final bool favorite;
  final bool damaged;
  final String layout;

  /// Lower-cased title + typed text, for search.
  final String searchText;

  const NoteEntry({
    required this.relPath,
    required this.title,
    required this.id,
    required this.modified,
    required this.created,
    required this.favorite,
    required this.damaged,
    this.layout = 'paged',
    this.searchText = '',
  });

  String get fileName => p.posix.basename(relPath);
  String get dir => dirOfRel(relPath);
}

class FolderEntry {
  final String relPath;
  final FolderMeta meta;
  final int itemCount;
  const FolderEntry(this.relPath, this.meta, this.itemCount);
  String get name => p.posix.basename(relPath);
}

class FolderListing {
  final List<FolderEntry> folders;
  final List<NoteEntry> notes;
  const FolderListing(this.folders, this.notes);
}

class FolderNode {
  final String relPath;
  final FolderMeta meta;
  final List<FolderNode> children;
  const FolderNode(this.relPath, this.meta, this.children);
  String get name => relPath.isEmpty ? '' : p.posix.basename(relPath);
}

class TrashEntry {
  final String trashId;
  final String originalPath;
  final DateTime deletedAt;
  final bool isFolder;
  final String? reason;
  const TrashEntry(this.trashId, this.originalPath, this.deletedAt, this.isFolder, this.reason);
  String get name => p.posix.basename(originalPath);
}

String dirOfRel(String rel) {
  final d = p.posix.dirname(rel);
  return d == '.' ? '' : d;
}

String joinRel(String dir, String name) => dir.isEmpty ? name : '$dir/$name';

/// Characters not allowed in file names on Windows/Android.
String sanitizeFileName(String name) {
  var s = name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_').trim();
  s = s.replaceAll(RegExp(r'[. ]+$'), '');
  if (s.isEmpty) s = 'Untitled';
  if (s.length > 120) s = s.substring(0, 120);
  return s;
}

/// The local working copy of the note library: real folders with `.cnote` files.
class LibraryStore {
  final String root;
  LibraryStore(this.root);

  static const trashDir = '.trash';
  final Map<String, (DateTime, int, NoteEntry)> _metaCache = {};

  String abs(String rel) => rel.isEmpty ? root : p.joinAll([root, ...rel.split('/')]);
  String rel(String absPath) => p.relative(absPath, from: root).replaceAll('\\', '/');

  static bool isHidden(String name) => name.startsWith('.');
  static bool isNoteFile(String name) => name.toLowerCase().endsWith(noteExtension) && !isHidden(name);

  Future<void> ensureRoot() => Directory(root).create(recursive: true);

  // ---------- folders ----------

  Future<FolderMeta> getFolderMeta(String relDir) async {
    final f = File(p.join(abs(relDir), FolderMeta.fileName));
    if (!await f.exists()) return const FolderMeta();
    try {
      return FolderMeta.fromJson(jsonDecode(await f.readAsString()) as Map<String, dynamic>);
    } catch (_) {
      return const FolderMeta();
    }
  }

  Future<void> setFolderMeta(String relDir, FolderMeta meta) async {
    await Directory(abs(relDir)).create(recursive: true);
    final m = meta.copyWith(modified: DateTime.now().toUtc());
    await _writeAtomic(p.join(abs(relDir), FolderMeta.fileName), utf8.encode(jsonEncode(m.toJson())));
  }

  Future<String> createFolder(String parent, String name, FolderMeta meta) async {
    final n = await _uniqueName(parent, sanitizeFileName(name), '');
    final r = joinRel(parent, n);
    await Directory(abs(r)).create(recursive: true);
    await setFolderMeta(r, meta);
    return r;
  }

  Future<String> renameFolder(String relDir, String newName) async {
    final parent = dirOfRel(relDir);
    final n = await _uniqueName(parent, sanitizeFileName(newName), '');
    final r = joinRel(parent, n);
    await Directory(abs(relDir)).rename(abs(r));
    _metaCache.clear();
    return r;
  }

  Future<FolderNode> tree([String relDir = '']) async {
    final dir = Directory(abs(relDir));
    final kids = <FolderNode>[];
    if (await dir.exists()) {
      await for (final e in dir.list()) {
        final name = p.basename(e.path);
        if (e is Directory && !isHidden(name)) kids.add(await tree(joinRel(relDir, name)));
      }
    }
    kids.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return FolderNode(relDir, await getFolderMeta(relDir), kids);
  }

  Future<FolderListing> listFolder(String relDir) async {
    final dir = Directory(abs(relDir));
    final folders = <FolderEntry>[];
    final notes = <NoteEntry>[];
    if (await dir.exists()) {
      await for (final e in dir.list()) {
        final name = p.basename(e.path);
        if (isHidden(name)) continue;
        if (e is Directory) {
          final r = joinRel(relDir, name);
          var count = 0;
          await for (final c in e.list()) {
            if (!isHidden(p.basename(c.path))) count++;
          }
          folders.add(FolderEntry(r, await getFolderMeta(r), count));
        } else if (e is File && isNoteFile(name)) {
          notes.add(await entryFor(joinRel(relDir, name)));
        }
      }
    }
    final meta = await getFolderMeta(relDir);
    _sortFolders(folders, meta);
    _sortNotes(notes, meta);
    return FolderListing(folders, notes);
  }

  void _sortFolders(List<FolderEntry> f, FolderMeta meta) {
    if (meta.sort == SortMode.manual) {
      f.sort((a, b) => _orderIdx(meta, a.name).compareTo(_orderIdx(meta, b.name)));
    } else {
      f.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
  }

  int _orderIdx(FolderMeta m, String name) {
    final i = m.order.indexOf(name);
    return i == -1 ? 1 << 30 : i;
  }

  void _sortNotes(List<NoteEntry> n, FolderMeta meta) {
    int cmp(NoteEntry a, NoteEntry b) => switch (meta.sort) {
          SortMode.name => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
          SortMode.created => a.created.compareTo(b.created),
          SortMode.modified => a.modified.compareTo(b.modified),
          SortMode.manual => _orderIdx(meta, a.fileName).compareTo(_orderIdx(meta, b.fileName)),
        };
    n.sort((a, b) => meta.ascending || meta.sort == SortMode.manual ? cmp(a, b) : cmp(b, a));
  }

  // ---------- notes ----------

  Future<NoteEntry> entryFor(String relPath) async {
    final f = File(abs(relPath));
    final stat = await f.stat();
    final cached = _metaCache[relPath];
    if (cached != null && cached.$1 == stat.modified && cached.$2 == stat.size) return cached.$3;
    NoteEntry entry;
    try {
      final meta = readNoteMeta(await f.readAsBytes());
      if (meta == null) throw NoteFormatException('unreadable');
      final text = StringBuffer(meta['title'] as String);
      for (final pg in meta['pages'] as List) {
        for (final el in (pg as Map)['elements'] as List) {
          if ((el as Map)['md'] case final String md) text.write('\n$md');
        }
      }
      entry = NoteEntry(
        relPath: relPath,
        title: meta['title'] as String,
        id: meta['id'] as String?,
        modified: DateTime.parse(meta['modified'] as String),
        created: DateTime.parse(meta['created'] as String),
        favorite: meta['favorite'] as bool? ?? false,
        damaged: false,
        layout: meta['layout'] as String? ?? 'paged',
        searchText: text.toString().toLowerCase(),
      );
    } catch (_) {
      final name = p.posix.basenameWithoutExtension(relPath);
      entry = NoteEntry(
        relPath: relPath,
        title: name,
        id: null,
        modified: stat.modified.toUtc(),
        created: stat.modified.toUtc(),
        favorite: false,
        damaged: true,
        searchText: name.toLowerCase(),
      );
    }
    _metaCache[relPath] = (stat.modified, stat.size, entry);
    return entry;
  }

  Future<NoteEntry> createNote(String relDir, Note note, {Uint8List? thumb}) async {
    await Directory(abs(relDir)).create(recursive: true);
    final name = await _uniqueName(relDir, sanitizeFileName(note.title), noteExtension);
    final r = joinRel(relDir, name);
    await saveNote(r, note, thumb: thumb);
    return entryFor(r);
  }

  Future<Note> loadNote(String relPath) async => decodeNote(await File(abs(relPath)).readAsBytes());

  Future<Uint8List?> loadThumb(String relPath) async {
    try {
      return readThumb(await File(abs(relPath)).readAsBytes());
    } catch (_) {
      return null;
    }
  }

  Future<void> saveNote(String relPath, Note note, {Uint8List? thumb}) async {
    thumb ??= await loadThumbIfExists(relPath);
    await _writeAtomic(abs(relPath), encodeNote(note, thumb: thumb));
  }

  Future<Uint8List?> loadThumbIfExists(String relPath) async =>
      await File(abs(relPath)).exists() ? loadThumb(relPath) : null;

  /// Renames the note file to match [newTitle] and updates the title inside.
  Future<String> renameNote(String relPath, String newTitle) async {
    final note = await loadNote(relPath);
    final thumb = await loadThumb(relPath);
    final dir = dirOfRel(relPath);
    final base = sanitizeFileName(newTitle);
    var target = relPath;
    if ('$base$noteExtension' != p.posix.basename(relPath)) {
      target = joinRel(dir, await _uniqueName(dir, base, noteExtension));
    }
    await saveNote(target, note.copyWith(title: newTitle, modified: DateTime.now().toUtc()), thumb: thumb);
    if (target != relPath) await File(abs(relPath)).delete();
    return target;
  }

  Future<void> setFavorite(String relPath, bool fav) async {
    final note = await loadNote(relPath);
    await saveNote(relPath, note.copyWith(favorite: fav, modified: DateTime.now().toUtc()));
  }

  /// Moves a note or folder into [destDir]. Returns the new relative path.
  Future<String> move(String relPath, String destDir) async {
    if (dirOfRel(relPath) == destDir) return relPath;
    if (destDir == relPath || destDir.startsWith('$relPath/')) {
      throw ArgumentError('cannot move a folder into itself');
    }
    final name = p.posix.basename(relPath);
    final isNote = isNoteFile(name);
    final base = isNote ? p.posix.basenameWithoutExtension(name) : name;
    await Directory(abs(destDir)).create(recursive: true);
    final target = joinRel(destDir, await _uniqueName(destDir, base, isNote ? noteExtension : ''));
    final entity = isNote ? File(abs(relPath)) : Directory(abs(relPath));
    await _renameOrCopy(entity, abs(target));
    _metaCache.clear();
    return target;
  }

  Future<NoteEntry> duplicateNote(String relPath) async {
    final note = await loadNote(relPath);
    final thumb = await loadThumb(relPath);
    final now = DateTime.now().toUtc();
    final copy = Note(
      id: newId(),
      title: '${note.title} (copy)',
      layout: note.layout,
      paper: note.paper,
      landscape: note.landscape,
      template: note.template,
      pages: note.pages,
      created: now,
      modified: now,
      modifiedBy: note.modifiedBy,
      favorite: false,
      assets: note.assets,
    );
    return createNote(dirOfRel(relPath), copy, thumb: thumb);
  }

  Future<List<NoteEntry>> allNotes() async {
    final out = <NoteEntry>[];
    Future<void> walk(String relDir) async {
      final dir = Directory(abs(relDir));
      if (!await dir.exists()) return;
      await for (final e in dir.list()) {
        final name = p.basename(e.path);
        if (isHidden(name)) continue;
        if (e is Directory) {
          await walk(joinRel(relDir, name));
        } else if (isNoteFile(name)) {
          out.add(await entryFor(joinRel(relDir, name)));
        }
      }
    }

    await walk('');
    return out;
  }

  Future<List<NoteEntry>> recent([int n = 30]) async {
    final all = await allNotes();
    all.sort((a, b) => b.modified.compareTo(a.modified));
    return all.take(n).toList();
  }

  Future<List<NoteEntry>> favorites() async {
    final all = (await allNotes()).where((e) => e.favorite).toList();
    all.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return all;
  }

  Future<List<NoteEntry>> search(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];
    final hits = (await allNotes()).where((e) => e.searchText.contains(q)).toList();
    hits.sort((a, b) => b.modified.compareTo(a.modified));
    return hits;
  }

  // ---------- trash ----------

  Future<TrashEntry> trashItem(String relPath, {DateTime? now, String? reason}) async {
    final when = (now ?? DateTime.now()).toUtc();
    final id = newId();
    final tdir = Directory(p.join(root, trashDir, id));
    await tdir.create(recursive: true);
    final name = p.posix.basename(relPath);
    final isFolder = await FileSystemEntity.isDirectory(abs(relPath));
    final info = {'original': relPath, 'deletedAt': when.toIso8601String(), 'folder': isFolder, 'reason': ?reason};
    await File(p.join(tdir.path, 'info.json')).writeAsString(jsonEncode(info));
    final entity = isFolder ? Directory(abs(relPath)) : File(abs(relPath));
    await _renameOrCopy(entity, p.join(tdir.path, name));
    _metaCache.remove(relPath);
    return TrashEntry(id, relPath, when, isFolder, reason);
  }

  /// Stores [bytes] directly in the trash as if [originalPath] had been deleted.
  Future<TrashEntry> trashBytes(String originalPath, Uint8List bytes, {String? reason}) async {
    final when = DateTime.now().toUtc();
    final id = newId();
    final tdir = Directory(p.join(root, trashDir, id));
    await tdir.create(recursive: true);
    await File(p.join(tdir.path, 'info.json')).writeAsString(
        jsonEncode({'original': originalPath, 'deletedAt': when.toIso8601String(), 'folder': false, 'reason': ?reason}));
    await File(p.join(tdir.path, p.posix.basename(originalPath))).writeAsBytes(bytes, flush: true);
    return TrashEntry(id, originalPath, when, false, reason);
  }

  Future<List<TrashEntry>> listTrash() async {
    final dir = Directory(p.join(root, trashDir));
    if (!await dir.exists()) return [];
    final out = <TrashEntry>[];
    await for (final e in dir.list()) {
      if (e is! Directory) continue;
      try {
        final j = jsonDecode(await File(p.join(e.path, 'info.json')).readAsString()) as Map<String, dynamic>;
        out.add(TrashEntry(p.basename(e.path), j['original'] as String, DateTime.parse(j['deletedAt'] as String),
            j['folder'] as bool? ?? false, j['reason'] as String?));
      } catch (_) {
        // incomplete trash entry; ignore
      }
    }
    out.sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
    return out;
  }

  Future<String> restore(TrashEntry t) async {
    final src = p.join(root, trashDir, t.trashId, t.name);
    final dir = dirOfRel(t.originalPath);
    await Directory(abs(dir)).create(recursive: true);
    final isNote = isNoteFile(t.name);
    final base = isNote ? p.posix.basenameWithoutExtension(t.name) : t.name;
    final target = joinRel(dir, await _uniqueName(dir, base, isNote ? noteExtension : ''));
    final entity = t.isFolder ? Directory(src) : File(src);
    await _renameOrCopy(entity, abs(target));
    await Directory(p.join(root, trashDir, t.trashId)).delete(recursive: true);
    return target;
  }

  Future<void> deleteForever(TrashEntry t) async {
    final d = Directory(p.join(root, trashDir, t.trashId));
    if (await d.exists()) await d.delete(recursive: true);
  }

  Future<void> purgeOlderThan(Duration age, {DateTime? now}) async {
    final cutoff = (now ?? DateTime.now()).toUtc().subtract(age);
    for (final t in await listTrash()) {
      if (t.deletedAt.isBefore(cutoff)) await deleteForever(t);
    }
  }

  // ---------- helpers ----------

  Future<String> _uniqueName(String relDir, String base, String ext) async {
    var name = '$base$ext';
    var i = 2;
    while (await FileSystemEntity.type(abs(joinRel(relDir, name))) != FileSystemEntityType.notFound) {
      name = '$base ($i)$ext';
      i++;
    }
    return name;
  }

  Future<void> writeBytesAtomic(String relPath, List<int> bytes) => _writeAtomic(abs(relPath), bytes);

  Future<void> _writeAtomic(String absPath, List<int> bytes) async {
    await Directory(p.dirname(absPath)).create(recursive: true);
    final tmp = File('${p.join(p.dirname(absPath), '.${p.basename(absPath)}')}.${newId().substring(0, 8)}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    try {
      await tmp.rename(absPath);
    } on FileSystemException {
      // Windows: rename can fail when the target is locked; fall back to copy.
      await tmp.copy(absPath);
      await tmp.delete();
    }
    _metaCache.remove(rel(absPath));
  }

  Future<void> _renameOrCopy(FileSystemEntity e, String target) async {
    try {
      await e.rename(target);
    } on FileSystemException {
      if (e is File) {
        await e.copy(target);
        await e.delete();
      } else if (e is Directory) {
        await _copyDir(e, Directory(target));
        await e.delete(recursive: true);
      }
    }
  }

  Future<void> _copyDir(Directory src, Directory dst) async {
    await dst.create(recursive: true);
    await for (final e in src.list()) {
      final t = p.join(dst.path, p.basename(e.path));
      if (e is File) {
        await e.copy(t);
      } else if (e is Directory) {
        await _copyDir(e, Directory(t));
      }
    }
  }
}
