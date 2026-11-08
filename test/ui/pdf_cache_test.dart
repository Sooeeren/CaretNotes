import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:caret_notes/core/model/note.dart';
import 'package:caret_notes/ui/editor/painters.dart';
import 'package:caret_notes/ui/editor/pdf_cache.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ui.Image> img() async {
  final r = ui.PictureRecorder();
  ui.Canvas(r).drawRect(const ui.Rect.fromLTWH(0, 0, 4, 4), ui.Paint());
  return r.endRecording().toImage(4, 4);
}

void main() {
  test('a finished PDF render makes the page repaint', () {
    final n = Note.create(title: 'x', layout: NoteLayout.paged, deviceName: 'd');
    PagePainter p(int v) => PagePainter(note: n, page: n.pages.first, assets: const RenderAssets(), scale: 1, assetsVersion: 0, pdfVersion: v);
    expect(p(2).shouldRepaint(p(1)), isTrue);
    expect(p(1).shouldRepaint(p(1)), isFalse);
  });

  test('replaced and evicted page images are disposed; dispose frees all', () async {
    final cache = PdfPageCache(() => <String, Uint8List>{}, maxImages: 2);
    final a1 = await img(), a2 = await img(), b = await img(), c = await img();
    cache.storeImage('a', a1, 100);
    cache.storeImage('a', a2, 200);
    expect(a1.debugDisposed, isTrue, reason: 'replaced by a sharper render');
    final v = cache.version;
    cache.storeImage('b', b, 100);
    expect(cache.version, greaterThan(v));
    cache.storeImage('c', c, 100);
    expect(a2.debugDisposed, isTrue, reason: 'least recently used beyond the limit');
    cache.dispose();
    expect(b.debugDisposed && c.debugDisposed, isTrue);
  });
}
