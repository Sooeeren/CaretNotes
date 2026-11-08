import 'dart:io';

import 'package:caret_notes/core/library/library_store.dart';
import 'package:caret_notes/core/model/folder_meta.dart';
import 'package:caret_notes/core/model/note.dart';
import 'package:caret_notes/ui/controllers.dart';
import 'package:caret_notes/ui/editor/text_box.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('markdown toolbar', () {
    test('bold wraps the selection', () {
      const v = TextEditingValue(text: 'a word b', selection: TextSelection(baseOffset: 2, extentOffset: 6));
      final r = applyMarkdown(v, MdAction.bold);
      expect(r.text, 'a **word** b');
      expect(r.selection, const TextSelection(baseOffset: 4, extentOffset: 8));
    });

    test('heading and checkbox prefix the current line', () {
      const v = TextEditingValue(text: 'one\ntwo', selection: TextSelection.collapsed(offset: 5));
      expect(applyMarkdown(v, MdAction.heading).text, 'one\n# two');
      expect(applyMarkdown(v, MdAction.checkbox).text, 'one\n- [ ] two');
    });

    test('math with empty selection inserts a pair and puts the cursor inside', () {
      const v = TextEditingValue(text: 'x ', selection: TextSelection.collapsed(offset: 2));
      final r = applyMarkdown(v, MdAction.math);
      expect(r.text, r'x $$');
      expect(r.selection.baseOffset, 3);
    });
  });

  group('library selection and manual order', () {
    late Directory tmp;
    late LibraryController lib;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('cn_sel_');
      lib = LibraryController(LibraryStore(tmp.path));
    });
    tearDown(() => tmp.delete(recursive: true));

    Future<String> note(String t) async =>
        (await lib.store.createNote('', Note.create(title: t, layout: NoteLayout.paged, deviceName: 'd'))).relPath;

    test('several selected notes move into a folder at once', () async {
      final a = await note('A'), b = await note('B');
      await note('C');
      final dest = await lib.store.createFolder('', 'Ziel', const FolderMeta());
      await lib.refresh();
      lib.toggleSelect(a);
      lib.toggleSelect(b);
      await lib.moveSelected(dest);
      expect((await lib.store.listFolder(dest)).notes.map((n) => n.title), unorderedEquals(['A', 'B']));
      expect(lib.selected, isEmpty);
    });

    test('dropping a note on another puts it before that one in manual order', () async {
      final a = await note('A'), b = await note('B'), c = await note('C');
      await lib.refresh();
      await lib.setSort(SortMode.name, true); // shown as A, B, C
      await lib.reorderBefore(c, a);
      expect(lib.listing.notes.map((n) => n.relPath), [c, a, b]);
    });
  });
}
