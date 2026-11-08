import 'dart:io';
import 'dart:typed_data';

import 'package:caret_notes/core/format/note_codec.dart';
import 'package:caret_notes/core/library/library_store.dart';
import 'package:caret_notes/core/model/elements.dart';
import 'package:caret_notes/core/model/folder_meta.dart';
import 'package:caret_notes/core/model/note.dart';
import 'package:caret_notes/core/sync/folder_remote.dart';
import 'package:caret_notes/core/sync/memory_remote.dart';
import 'package:caret_notes/core/sync/remote_store.dart';
import 'package:caret_notes/core/sync/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';

StrokeEl stroke(String id, double x) =>
    StrokeEl(id: id, points: [InkPoint(x, 0, .5), InkPoint(x + 10, 5, .5)], tool: ToolKind.pen, color: 0xFF000000, width: 2);

Future<void> addStroke(LibraryStore lib, String path, String id, double x) async {
  final n = await lib.loadNote(path);
  final pg = n.pages.first;
  await lib.saveNote(path, n.copyWith(pages: [pg.copyWith(elements: [...pg.elements, stroke(id, x)])], modified: DateTime.now().toUtc()));
}

Future<Note> remoteNote(RemoteStore r, String path) async => decodeNote(await r.read(path));

void main() {
  late Directory tmp;
  late LibraryStore lib;
  late MemoryRemote remote;
  late SyncEngine engine;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('cn_sync_');
    lib = LibraryStore('${tmp.path}/lib');
    await lib.ensureRoot();
    remote = MemoryRemote();
    engine = SyncEngine(lib, remote);
  });
  tearDown(() async {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  Future<String> newNote(String dir, String title) async =>
      (await lib.createNote(dir, Note.create(title: title, layout: NoteLayout.paged, deviceName: 'laptop'))).relPath;

  test('a new local note is uploaded', () async {
    final p = await newNote('', 'VL 1');
    final r = await engine.run();
    expect(r.uploaded, contains(p));
    expect((await remoteNote(remote, p)).title, 'VL 1');
  });

  test('a new remote note is downloaded', () async {
    final n = Note.create(title: 'From tablet', layout: NoteLayout.paged, deviceName: 'tablet');
    await remote.write('Physik/From tablet.cnote', encodeNote(n));
    final r = await engine.run();
    expect(r.downloaded, contains('Physik/From tablet.cnote'));
    expect((await lib.loadNote('Physik/From tablet.cnote')).title, 'From tablet');
  });

  test('second sync with no changes does nothing', () async {
    await newNote('', 'VL 1');
    await engine.run();
    final r = await engine.run();
    expect(r.uploaded, isEmpty);
    expect(r.downloaded, isEmpty);
    expect(r.conflicts, isEmpty);
  });

  test('remote edit of an unchanged local note is downloaded', () async {
    final p = await newNote('', 'VL 1');
    await engine.run();
    final n = await remoteNote(remote, p);
    await remote.write(p, encodeNote(n.copyWith(title: 'renamed remotely')));
    await engine.run();
    expect((await lib.loadNote(p)).title, 'renamed remotely');
  });

  test('both edited -> conflict; combine keeps both additions locally and remotely', () async {
    final p = await newNote('', 'VL 4');
    await engine.run();
    await addStroke(lib, p, 'local', 0);
    final rn = await remoteNote(remote, p);
    await remote.write(p, encodeNote(rn.copyWith(pages: [rn.pages.first.copyWith(elements: [stroke('remote', 50)])])));

    final r = await engine.run();
    expect(r.conflicts.map((c) => c.path), [p]);
    expect(engine.pendingConflicts.length, 1);

    await engine.resolve(engine.pendingConflicts.single, Resolution.combine);
    final ids = (await lib.loadNote(p)).pages.first.elements.map((e) => e.id).toSet();
    expect(ids, {'local', 'remote'});
    final rids = (await remoteNote(remote, p)).pages.first.elements.map((e) => e.id).toSet();
    expect(rids, {'local', 'remote'});
    expect(engine.pendingConflicts, isEmpty);
    expect((await engine.run()).conflicts, isEmpty);
  });

  test('keep remote moves the local version to Recently deleted', () async {
    final p = await newNote('', 'VL 5');
    await engine.run();
    await addStroke(lib, p, 'local', 0);
    final rn = await remoteNote(remote, p);
    await remote.write(p, encodeNote(rn.copyWith(title: 'remote wins')));
    await engine.run();
    await engine.resolve(engine.pendingConflicts.single, Resolution.keepRemote);
    expect((await lib.loadNote(p)).title, 'remote wins');
    final trash = await lib.listTrash();
    expect(trash.single.originalPath, p);
  });

  test('keep both creates a separate copy of the remote version', () async {
    final p = await newNote('', 'VL 6');
    await engine.run();
    await addStroke(lib, p, 'local', 0);
    final rn = await remoteNote(remote, p);
    await remote.write(p, encodeNote(rn.copyWith(pages: [rn.pages.first.copyWith(elements: [stroke('remote', 9)])], modifiedBy: 'tablet')));
    await engine.run();
    await engine.resolve(engine.pendingConflicts.single, Resolution.keepBoth);
    final notes = (await lib.listFolder('')).notes;
    expect(notes.length, 2);
    expect(notes.map((n) => n.title), contains('VL 6 (tablet copy)'));
  });

  test('a half-written remote note is skipped, not imported', () async {
    await remote.write('Broken.cnote', Uint8List.fromList([0x50, 0x4B, 3, 4, 1, 2, 3]));
    final r = await engine.run();
    expect(r.skipped, contains('Broken.cnote'));
    expect(await File(lib.abs('Broken.cnote')).exists(), isFalse);
  });

  test('a Proton "Name clash" copy becomes a conflict for the original note', () async {
    final p = await newNote('', 'VL 7');
    await engine.run();
    final rn = await remoteNote(remote, p);
    await remote.write('VL 7 (# Name clash 2026-11-08 ab12cd #).cnote',
        encodeNote(rn.copyWith(pages: [rn.pages.first.copyWith(elements: [stroke('tablet', 3)])])));
    final r = await engine.run();
    expect(r.conflicts.single.path, p);
    expect(r.conflicts.single.remotePath, 'VL 7 (# Name clash 2026-11-08 ab12cd #).cnote');
    expect((await lib.listFolder('')).notes.length, 1, reason: 'the clash copy must not show up as a stray note');

    await engine.resolve(engine.pendingConflicts.single, Resolution.combine);
    expect((await lib.loadNote(p)).pages.first.elements.map((e) => e.id), contains('tablet'));
    expect((await remote.listAll()).map((e) => e.path), isNot(contains('VL 7 (# Name clash 2026-11-08 ab12cd #).cnote')));
  });

  test('a Dropbox conflicted copy is detected too', () async {
    final p = await newNote('', 'Notes');
    await engine.run();
    final rn = await remoteNote(remote, p);
    await remote.write("Notes (Laptop's conflicted copy 2026-11-08).cnote", encodeNote(rn.copyWith(title: 'x')));
    final r = await engine.run();
    expect(r.conflicts.single.path, p);
  });

  test('remote delete + local edit keeps the edited note and its folder', () async {
    final dir = await lib.createFolder('', 'Mathe', const FolderMeta(color: 0xFFD23B3B));
    final p = await newNote(dir, 'Analysis');
    await engine.run();
    await addStroke(lib, p, 'edit', 1);
    await remote.delete(p);
    await remote.delete('Mathe/.folder.json');
    await engine.run();
    expect(await File(lib.abs(p)).exists(), isTrue);
    expect((await remote.listAll()).map((e) => e.path), containsAll([p, 'Mathe/.folder.json']));
  });

  test('local delete + remote edit restores the edited note locally', () async {
    final p = await newNote('', 'Bio');
    await engine.run();
    await lib.trashItem(p);
    final rn = await remoteNote(remote, p);
    await remote.write(p, encodeNote(rn.copyWith(title: 'Bio edited')));
    await engine.run();
    expect((await lib.loadNote(p)).title, 'Bio edited');
  });

  test('remote delete of an unchanged note moves it to Recently deleted', () async {
    final p = await newNote('', 'Chemie');
    await engine.run();
    await remote.delete(p);
    await engine.run();
    expect(await File(lib.abs(p)).exists(), isFalse);
    expect((await lib.listTrash()).single.originalPath, p);
  });

  test('conflicting folder metadata: newer one wins automatically', () async {
    final dir = await lib.createFolder('', 'Info', const FolderMeta(color: 1));
    await engine.run();
    await lib.setFolderMeta(dir, const FolderMeta(color: 2));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final newer = const FolderMeta(color: 3).copyWith(modified: DateTime.now().toUtc().add(const Duration(minutes: 1)));
    await remote.write('Info/.folder.json', Uint8List.fromList('{"color":3,"modified":"${newer.modified!.toIso8601String()}"}'.codeUnits));
    final r = await engine.run();
    expect(r.conflicts, isEmpty);
    expect((await lib.getFolderMeta(dir)).color, 3);
  });

  test('the note open in the editor is not touched by sync', () async {
    final p = await newNote('', 'Open');
    await engine.run();
    final rn = await remoteNote(remote, p);
    await remote.write(p, encodeNote(rn.copyWith(title: 'changed remotely')));
    await engine.run(exclude: {p});
    expect((await lib.loadNote(p)).title, 'Open');
  });

  group('FolderRemote (a Proton Drive / OneDrive synced folder)', () {
    test('round-trips through a real directory and ignores temp files', () async {
      final dir = Directory('${tmp.path}/proton');
      final fr = FolderRemote(dir.path);
      final e = SyncEngine(lib, fr);
      final p = await newNote('', 'Synced');
      await e.run();
      expect(await File('${dir.path}/Synced.cnote').exists(), isTrue);
      await File('${dir.path}/~lock.tmp').writeAsString('x');
      await File('${dir.path}/.hidden.cnote').writeAsString('x');
      final listed = (await fr.listAll()).map((x) => x.path);
      expect(listed, isNot(contains('~lock.tmp')));
      expect(listed, isNot(contains('.hidden.cnote')));
      expect(listed, contains(p));
    });
  });
}
