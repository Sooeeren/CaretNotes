import 'dart:typed_data';

import 'package:caret_notes/core/geometry.dart';
import 'package:caret_notes/core/merge/note_merge.dart';
import 'package:caret_notes/core/model/elements.dart';
import 'package:caret_notes/core/model/note.dart';
import 'package:caret_notes/core/model/page.dart';
import 'package:flutter_test/flutter_test.dart';

StrokeEl s(String id, [double x = 0]) =>
    StrokeEl(id: id, points: [InkPoint(x, 0, .5), InkPoint(x + 10, 0, .5)], tool: ToolKind.pen, color: 0xFF000000, width: 2);

NotePage pg(String id, List<Element> els) => NotePage(id: id, width: 595, height: 842, elements: els);

final _t0 = DateTime.utc(2026, 11, 1);
Note note(List<NotePage> pages, {String title = 'N', int minutes = 0, Map<String, Uint8List> assets = const {}}) => Note(
      id: 'note',
      title: title,
      layout: NoteLayout.paged,
      pages: pages,
      created: _t0,
      modified: _t0.add(Duration(minutes: minutes)),
      modifiedBy: 'x',
      assets: assets,
    );

List<String> ids(Note n, int page) => n.pages[page].elements.map((e) => e.id).toList();

void main() {
  test('additions on both sides are kept', () {
    final base = note([pg('p1', [s('a')])]);
    final local = note([pg('p1', [s('a'), s('l')])]);
    final remote = note([pg('p1', [s('a'), s('r')])]);
    final m = mergeNotes(base: base, local: local, remote: remote);
    expect(ids(m, 0), unorderedEquals(['a', 'l', 'r']));
  });

  test('deleted on one side and unchanged on the other is deleted', () {
    final base = note([pg('p1', [s('a'), s('b')])]);
    final local = note([pg('p1', [s('b')])]);
    final remote = note([pg('p1', [s('a'), s('b')])]);
    expect(ids(mergeNotes(base: base, local: local, remote: remote), 0), ['b']);
  });

  test('deleted on one side but changed on the other is kept (changed)', () {
    final base = note([pg('p1', [s('a')])]);
    final local = note([pg('p1', [])]);
    final remote = note([pg('p1', [s('a', 50)])]);
    final m = mergeNotes(base: base, local: local, remote: remote);
    expect(ids(m, 0), ['a']);
    expect((m.pages[0].elements.single as StrokeEl).points.first.x, 50);
  });

  test('changed differently on both sides keeps both copies', () {
    final base = note([pg('p1', [s('a')])]);
    final local = note([pg('p1', [s('a', 10)])]);
    final remote = note([pg('p1', [s('a', 20)])]);
    final m = mergeNotes(base: base, local: local, remote: remote);
    final els = m.pages[0].elements.cast<StrokeEl>();
    expect(els.length, 2);
    expect(els.firstWhere((e) => e.id == 'a').points.first.x, 10);
    expect(els.firstWhere((e) => e.id != 'a').points.first.x, 20);
  });

  test('changed on one side only takes that change', () {
    final base = note([pg('p1', [s('a')])]);
    final local = note([pg('p1', [s('a')])]);
    final remote = note([pg('p1', [s('a', 30)])]);
    final m = mergeNotes(base: base, local: local, remote: remote);
    expect((m.pages[0].elements.single as StrokeEl).points.first.x, 30);
  });

  test('new pages from both sides are kept in order', () {
    final base = note([pg('p1', []), pg('p2', [])]);
    final local = note([pg('p1', []), pg('L', []), pg('p2', [])]);
    final remote = note([pg('p1', []), pg('p2', []), pg('R', [])]);
    final m = mergeNotes(base: base, local: local, remote: remote);
    expect(m.pages.map((p) => p.id), ['p1', 'L', 'p2', 'R']);
  });

  test('page deleted on one side with additions on the other survives', () {
    final base = note([pg('p1', []), pg('p2', [])]);
    final local = note([pg('p1', [])]);
    final remote = note([pg('p1', []), pg('p2', [s('new')])]);
    final m = mergeNotes(base: base, local: local, remote: remote);
    expect(m.pages.map((p) => p.id), ['p1', 'p2']);
    expect(ids(m, 1), ['new']);
  });

  test('page deleted on one side and untouched on the other is deleted', () {
    final base = note([pg('p1', []), pg('p2', [s('x')])]);
    final local = note([pg('p1', [])]);
    final remote = note([pg('p1', []), pg('p2', [s('x')])]);
    expect(mergeNotes(base: base, local: local, remote: remote).pages.map((p) => p.id), ['p1']);
  });

  test('note title takes the side modified later; assets are unioned', () {
    final base = note([pg('p1', [])]);
    final local = note([pg('p1', [])], title: 'Local', minutes: 5, assets: {'a': Uint8List(1)});
    final remote = note([pg('p1', [])], title: 'Remote', minutes: 9, assets: {'b': Uint8List(1)});
    final m = mergeNotes(base: base, local: local, remote: remote);
    expect(m.title, 'Remote');
    expect(m.assets.keys, unorderedEquals(['a', 'b']));
  });

  test('without a base, everything from both sides is kept', () {
    final local = note([pg('p1', [s('a')])]);
    final remote = note([pg('p1', [s('b')]), pg('p2', [s('c')])]);
    final m = mergeNotes(base: null, local: local, remote: remote);
    expect(m.pages.map((p) => p.id), ['p1', 'p2']);
    expect(ids(m, 0), unorderedEquals(['a', 'b']));
  });

  test('text box edited on both sides keeps both', () {
    const t = TextEl(id: 't', rect: RectD(0, 0, 10, 10), markdown: 'base');
    final base = note([pg('p1', [t])]);
    final local = note([pg('p1', [t.copyWith(markdown: 'L')])]);
    final remote = note([pg('p1', [t.copyWith(markdown: 'R')])]);
    final m = mergeNotes(base: base, local: local, remote: remote);
    expect(m.pages[0].elements.map((e) => (e as TextEl).markdown), unorderedEquals(['L', 'R']));
  });
}
