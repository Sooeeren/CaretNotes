import 'dart:io';

import 'package:caret_notes/core/geometry.dart';
import 'package:caret_notes/core/library/library_store.dart';
import 'package:caret_notes/core/model/elements.dart';
import 'package:caret_notes/core/model/folder_meta.dart';
import 'package:caret_notes/core/model/note.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  late LibraryStore lib;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('cn_lib_');
    lib = LibraryStore(tmp.path);
  });
  tearDown(() => tmp.delete(recursive: true));

  Note note(String title) => Note.create(title: title, layout: NoteLayout.paged, deviceName: 'test');

  test('nested folders and notes list folders first, with titles', () async {
    final sem = await lib.createFolder('', 'Semester 3', const FolderMeta(color: 0xFF3B6FE0, icon: 'book'));
    final la = await lib.createFolder(sem, 'Lineare Algebra', const FolderMeta());
    await lib.createNote(sem, note('Organisation'));
    await lib.createNote(la, note('VL 4'));

    final listing = await lib.listFolder(sem);
    expect(listing.folders.map((f) => f.name), ['Lineare Algebra']);
    expect(listing.notes.map((n) => n.title), ['Organisation']);
    expect((await lib.getFolderMeta(sem)).color, 0xFF3B6FE0);

    final tree = await lib.tree();
    expect(tree.children.single.name, 'Semester 3');
    expect(tree.children.single.children.single.name, 'Lineare Algebra');
  });

  test('same title twice gets a unique file name', () async {
    final a = await lib.createNote('', note('VL 1'));
    final b = await lib.createNote('', note('VL 1'));
    expect(a.relPath, isNot(b.relPath));
    expect(b.relPath, 'VL 1 (2).cnote');
  });

  test('trash then restore puts the note back at its original path', () async {
    final f = await lib.createFolder('', 'Physik', const FolderMeta());
    final e = await lib.createNote(f, note('Mechanik'));
    await lib.trashItem(e.relPath);
    expect((await lib.listFolder(f)).notes, isEmpty);
    final trash = await lib.listTrash();
    expect(trash.single.originalPath, e.relPath);
    await lib.restore(trash.single);
    expect((await lib.listFolder(f)).notes.single.title, 'Mechanik');
    expect(await lib.listTrash(), isEmpty);
  });

  test('restore recreates a missing parent folder', () async {
    final f = await lib.createFolder('', 'Chemie', const FolderMeta());
    final e = await lib.createNote(f, note('Atome'));
    await lib.trashItem(e.relPath);
    await Directory('${tmp.path}/Chemie').delete(recursive: true);
    await lib.restore((await lib.listTrash()).single);
    expect((await lib.listFolder('Chemie')).notes.single.title, 'Atome');
  });

  test('purge removes trash entries older than 30 days only', () async {
    final a = await lib.createNote('', note('old'));
    final b = await lib.createNote('', note('new'));
    await lib.trashItem(a.relPath, now: DateTime.now().subtract(const Duration(days: 31)));
    await lib.trashItem(b.relPath);
    await lib.purgeOlderThan(const Duration(days: 30));
    expect((await lib.listTrash()).map((t) => t.name), ['new.cnote']);
  });

  test('a corrupt note file is listed as damaged instead of throwing', () async {
    await File('${tmp.path}/broken.cnote').writeAsString('not a zip');
    await lib.createNote('', note('ok'));
    final notes = (await lib.listFolder('')).notes;
    expect(notes.length, 2);
    expect(notes.firstWhere((n) => n.relPath == 'broken.cnote').damaged, isTrue);
    expect(notes.firstWhere((n) => n.title == 'ok').damaged, isFalse);
  });

  test('search matches title and typed text', () async {
    final n = note('Analysis');
    final withText = n.copyWith(pages: [
      n.pages.first.copyWith(elements: [const TextEl(id: 't', rect: RectD(0, 0, 10, 10), markdown: 'Grenzwert von Folgen')]),
    ]);
    await lib.createNote('', withText);
    await lib.createNote('', note('Other'));
    expect((await lib.search('grenzwert')).single.title, 'Analysis');
    expect((await lib.search('analy')).single.title, 'Analysis');
  });

  test('dot-folders like .trash and .sync are hidden', () async {
    await Directory('${tmp.path}/.sync').create();
    expect((await lib.listFolder('')).folders, isEmpty);
  });

  test('sort by name descending is respected', () async {
    await lib.setFolderMeta('', const FolderMeta(sort: SortMode.name, ascending: false));
    await lib.createNote('', note('A'));
    await lib.createNote('', note('B'));
    expect((await lib.listFolder('')).notes.map((n) => n.title), ['B', 'A']);
  });

  test('move a note into a folder', () async {
    final f = await lib.createFolder('', 'Ziel', const FolderMeta());
    final e = await lib.createNote('', note('Wander'));
    final moved = await lib.move(e.relPath, f);
    expect(moved, 'Ziel/Wander.cnote');
    expect((await lib.listFolder(f)).notes.single.title, 'Wander');
  });
}
