import 'dart:convert';
import 'dart:io';

import 'package:caret_notes/core/export/pdf_export.dart';
import 'package:caret_notes/core/export/pdf_stamp.dart';
import 'package:caret_notes/core/geometry.dart';
import 'package:caret_notes/core/model/elements.dart';
import 'package:caret_notes/core/model/note.dart';
import 'package:caret_notes/core/model/page.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter_test/flutter_test.dart';

int pageCount(List<int> pdf) => RegExp(r'/Type\s*/Page(?!s)').allMatches(latin1.decode(pdf)).length;

void main() {
  const s = StrokeEl(id: 's', points: [InkPoint(10, 10, .5), InkPoint(100, 120, .8)], tool: ToolKind.pen, color: 0xFF1B2A6B, width: 2);

  test('a one-stroke note exports to a PDF', () async {
    final n = Note.create(title: 'x', layout: NoteLayout.paged, deviceName: 'd');
    final note = n.copyWith(pages: [n.pages.first.copyWith(elements: [s])]);
    final bytes = await exportNotePdf(note);
    expect(latin1.decode(bytes.take(5).toList()), '%PDF-');
    expect(pageCount(bytes), 1);
  });

  test('an endless note 2000 pt tall becomes 3 A4 pages', () async {
    final n = Note.create(title: 'x', layout: NoteLayout.endless, deviceName: 'd');
    final note = n.copyWith(pages: [n.pages.first.copyWith(height: 2000, elements: [s])]);
    expect(pageCount(await exportNotePdf(note)), 3);
  });

  test('a sheet ends in a gap of the writing, not through it', () {
    StrokeEl line(String id, double y0, double y1) =>
        StrokeEl(id: id, points: [InkPoint(50, y0, .5), InkPoint(300, y1, .5)], tool: ToolKind.pen, color: 0xFF000000, width: 2);
    // nothing in the way: the sheet ends where it would anyway
    expect(sheetBreak([line('a', 100, 120)], 500, 800), 800);
    // a word written across the cut: the sheet ends just above it
    final cut = sheetBreak([line('a', 100, 120), line('b', 780, 820)], 500, 800);
    expect(cut, lessThan(780));
    expect(cut, greaterThan(760));
    // writing everywhere near the cut: the fewest strokes are cut
    final busy = [line('a', 700, 900), line('b', 760, 790), line('c', 795, 805)];
    expect(sheetBreak(busy, 500, 800), lessThanOrEqualTo(700));
  });

  test('an endless note splits into A4 sheets without cutting handwriting in half', () async {
    final n = Note.create(title: 'x', layout: NoteLayout.endless, deviceName: 'd');
    final sheetH = n.pageHeight;
    // a line of handwriting right across the first A4 page boundary
    final across = StrokeEl(id: 'x', points: [InkPoint(60, sheetH - 15, .5), InkPoint(400, sheetH + 15, .5)], tool: ToolKind.pen, color: 0xFF000000, width: 2);
    final note = n.copyWith(pages: [n.pages.first.copyWith(height: 2000, elements: [s, across])]);
    final sheets = planSheets(note);
    final b = across.bounds();
    for (final sh in sheets) {
      expect(sh.height, closeTo(sheetH, 1e-6), reason: 'every sheet is A4');
      expect(sh.area.top < b.top && b.top < sh.area.bottom && sh.area.bottom < b.bottom, isFalse, reason: 'no sheet ends inside the stroke');
    }
    expect(sheets.first.area.bottom, lessThan(b.top));
    expect(sheets[1].area.top, sheets.first.area.bottom);
    expect(pageCount(await exportNotePdf(note)), sheets.length);
  });

  test('only selected pages are exported', () async {
    final n = Note.create(title: 'x', layout: NoteLayout.paged, deviceName: 'd');
    final p = n.pages.first;
    final note = n.copyWith(pages: [p, p.copyWith(id: 'b'), p.copyWith(id: 'c')]);
    expect(pageCount(await exportNotePdf(note, pages: [0, 2])), 2);
  });

  test('a canvas note can be tiled into A4 sheets', () async {
    final n = Note.create(title: 'x', layout: NoteLayout.canvas, deviceName: 'd');
    const wide = StrokeEl(id: 'w', points: [InkPoint(0, 0, .5), InkPoint(1500, 10, .5)], tool: ToolKind.pen, color: 0xFF000000, width: 2);
    final note = n.copyWith(pages: [n.pages.first.copyWith(elements: [wide])]);
    expect(pageCount(await exportNotePdf(note)), 1);
    expect(pageCount(await exportNotePdf(note, canvas: CanvasExport.tiles)), greaterThanOrEqualTo(3));
  });

  test('typed text is real text in the PDF', () async {
    final n = Note.create(title: 'x', layout: NoteLayout.paged, deviceName: 'd');
    const t = TextEl(id: 't', rect: RectD(40, 40, 300, 100), markdown: '# Eigenwerte\nHello **world**');
    final note = n.copyWith(pages: [n.pages.first.copyWith(elements: [t])]);
    final bytes = await exportNotePdf(note, compress: false);
    final txt = latin1.decode(bytes);
    expect(txt.contains('Eigenwerte') || txt.contains('/Font'), isTrue);
  });

  test('text on lines and the new paper kinds export', () async {
    final n = Note.create(title: 'x', layout: NoteLayout.paged, deviceName: 'd');
    const t = TextEl(id: 't', rect: RectD(72, 88, 573, 154), markdown: '# Title\nfirst line\n```\ncode\n```', fontSize: 13.2, lineHeight: 22);
    for (final kind in [TemplateKind.cornell, TemplateKind.staff, TemplateKind.lined]) {
      final note = n.copyWith(template: Template(kind: kind), pages: [n.pages.first.copyWith(elements: [t])]);
      expect(pageCount(await exportNotePdf(note)), 1);
    }
  });

  test('imported PDF pages are stamped (original page kept, ink on top) via PDFium', () async {
    const dll = 'build/windows/x64/runner/Debug/pdfium.dll';
    final stamper = File(dll).existsSync() ? PdfiumStamper.tryLoad(File(dll).absolute.path) : null;
    if (stamper == null) {
      markTestSkipped('pdfium.dll not built yet');
      return;
    }
    final src = pw.Document()..addPage(pw.Page(build: (_) => pw.Text('Original lecture slide')));
    final srcBytes = await src.save();
    final n = Note.create(title: 'slides', layout: NoteLayout.paged, deviceName: 'd');
    final page = NotePage(id: 'p', width: PdfPageFormat.a4.width, height: PdfPageFormat.a4.height, pdf: const PdfRef('pdf-1', 0), elements: const [s]);
    final note = n.copyWith(pages: [page, n.pages.first], assets: {'pdf-1': srcBytes});
    final out = await exportNotePdf(note, stamper: stamper.stamp);
    expect(latin1.decode(out.take(5).toList()), '%PDF-');
    expect(pageCount(out), 2);
  });
}
