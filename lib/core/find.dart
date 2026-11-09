import 'geometry.dart';
import 'model/elements.dart';
import 'model/note.dart';

/// A text box (or text on lines) that contains the search query.
class FindHit {
  final int pageIndex;
  final String pageId;
  final String elementId;
  final RectD rect;

  /// How often the query occurs in this text.
  final int count;
  const FindHit(this.pageIndex, this.pageId, this.elementId, this.rect, this.count);
}

/// Every typed text in [note] that contains [query] (case-insensitive, markdown
/// syntax ignored), in page order, then top to bottom. Handwriting isn't searched.
List<FindHit> findInNote(Note note, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];
  final out = <FindHit>[];
  for (var i = 0; i < note.pages.length; i++) {
    final pg = note.pages[i];
    final onPage = <FindHit>[];
    for (final e in pg.elements) {
      if (e is! TextEl) continue;
      final n = _count(plainForFind(e.markdown).toLowerCase(), q);
      if (n > 0) onPage.add(FindHit(i, pg.id, e.id, e.rect, n));
    }
    onPage.sort((a, b) {
      final dy = a.rect.top.compareTo(b.rect.top);
      return dy != 0 ? dy : a.rect.left.compareTo(b.rect.left);
    });
    out.addAll(onPage);
  }
  return out;
}

int _count(String text, String q) {
  var n = 0;
  var from = 0;
  while (true) {
    final i = text.indexOf(q, from);
    if (i < 0) return n;
    n++;
    from = i + q.length;
  }
}

final _link = RegExp(r'\[([^\]]*)\]\([^)]*\)');
final _lineStart = RegExp(r'^\s*(#{1,6}\s+|[-*+]\s+\[[ xX]\]\s+|[-*+]\s+|\d+[.)]\s+|>\s?)', multiLine: true);
final _markers = RegExp(r'\*\*|__|~~|[*_`$]');

/// Markdown reduced to the words a reader sees.
String plainForFind(String md) =>
    md.replaceAllMapped(_link, (m) => m[1]!).replaceAll(_lineStart, '').replaceAll(_markers, '');
