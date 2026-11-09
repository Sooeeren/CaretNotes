import 'package:caret_notes/core/find.dart';
import 'package:caret_notes/core/geometry.dart';
import 'package:caret_notes/core/model/elements.dart';
import 'package:caret_notes/core/model/note.dart';
import 'package:caret_notes/core/model/page.dart';
import 'package:flutter_test/flutter_test.dart';

TextEl _t(String id, String md, [double y = 0]) => TextEl(id: id, rect: RectD(10, y, 210, y + 40), markdown: md);

Note _note(List<List<Element>> pages) {
  final n = Note.create(title: 'N', layout: NoteLayout.paged, deviceName: 'test');
  return n.copyWith(pages: [
    for (var i = 0; i < pages.length; i++) NotePage(id: 'p$i', width: 595, height: 842, elements: pages[i]),
  ]);
}

void main() {
  test('finds typed text case-insensitively, in page and paint order', () {
    final n = _note([
      [_t('a', 'Eigenvalues are roots', 100), _t('b', 'nothing here', 20)],
      [_t('c', 'More EIGENVALUES')],
    ]);
    final hits = findInNote(n, 'eigenvalue');
    expect(hits.map((h) => h.elementId), ['a', 'c']);
    expect(hits.first.pageId, 'p0');
    expect(hits.first.pageIndex, 0);
    expect(hits.last.pageIndex, 1);
    expect(hits.first.rect.top, 100);
  });

  test('ignores markdown syntax so formatted words still match', () {
    final n = _note([
      [_t('a', 'find **Av** = `λv` here'), _t('b', '# Heading _one_')],
    ]);
    expect(findInNote(n, 'av = λv').map((h) => h.elementId), ['a']);
    expect(findInNote(n, 'heading one').map((h) => h.elementId), ['b']);
  });

  test('counts every occurrence inside a text box', () {
    final n = _note([
      [_t('a', 'ab ab AB')],
    ]);
    expect(findInNote(n, 'ab').single.count, 3);
  });

  test('blank or missing query gives no hits', () {
    final n = _note([
      [_t('a', 'text')],
    ]);
    expect(findInNote(n, '   '), isEmpty);
    expect(findInNote(n, 'zzz'), isEmpty);
  });

  test('plainForFind strips markdown markers', () {
    expect(plainForFind('**bold** and _it_ and `code` and ~~x~~ and [link](http://a)'), 'bold and it and code and x and link');
    expect(plainForFind('## Title\n- [x] done'), 'Title\ndone');
  });
}
