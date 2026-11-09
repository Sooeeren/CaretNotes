import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:vector_math/vector_math_64.dart' show Matrix4;

import '../geometry.dart';
import '../ink/paint_order.dart';
import '../ink/stroke_geometry.dart';
import '../model/elements.dart';
import '../model/note.dart';
import '../model/page.dart';
import '../paper.dart';
import 'export_fonts.dart';
import 'pdf_stamp.dart';

enum CanvasExport { onePage, tiles }

/// Renders an imported PDF page to PNG at [px] width (fallback when stamping isn't possible).
typedef PdfPageRaster = Future<Uint8List?> Function(PdfRef ref, int px);

/// One output sheet: a region of one note page.
class ExportSheet {
  final NotePage page;
  final RectD area;
  const ExportSheet(this.page, this.area);
  double get width => area.width;
  double get height => area.height;
}

RectD contentArea(NotePage p, {double pad = 36}) {
  RectD? r;
  for (final e in p.elements) {
    r = r == null ? e.bounds() : r.union(e.bounds());
  }
  return (r ?? const RectD(0, 0, 595.28, 841.89)).inflate(pad);
}

List<ExportSheet> planSheets(Note n, {List<int>? pages, CanvasExport canvas = CanvasExport.onePage}) {
  final idx = pages ?? List.generate(n.pages.length, (i) => i);
  final out = <ExportSheet>[];
  for (final i in idx) {
    if (i < 0 || i >= n.pages.length) continue;
    final p = n.pages[i];
    switch (n.layout) {
      case NoteLayout.paged:
        out.add(ExportSheet(p, RectD(0, 0, p.width, p.height)));
      case NoteLayout.endless:
        final sheetH = n.pageHeight;
        final count = math.max(1, (p.height / sheetH - 0.02).ceil());
        for (var k = 0; k < count; k++) {
          out.add(ExportSheet(p, RectD(0, k * sheetH, p.width, (k + 1) * sheetH)));
        }
      case NoteLayout.canvas:
        final a = contentArea(p);
        if (canvas == CanvasExport.onePage) {
          out.add(ExportSheet(p, a));
        } else {
          final w = n.paper.w, h = n.paper.h;
          final cols = math.max(1, (a.width / w).ceil()), rows = math.max(1, (a.height / h).ceil());
          for (var r = 0; r < rows; r++) {
            for (var c = 0; c < cols; c++) {
              out.add(ExportSheet(p, RectD(a.left + c * w, a.top + r * h, a.left + (c + 1) * w, a.top + (r + 1) * h)));
            }
          }
        }
    }
  }
  return out;
}

/// Vector PDF export: ink as filled outlines, typed text as real text, images embedded,
/// imported PDF pages kept at original quality (stamped via PDFium) when possible.
Future<Uint8List> exportNotePdf(
  Note note, {
  List<int>? pages,
  CanvasExport canvas = CanvasExport.onePage,
  ExportFonts fonts = const ExportFonts(),
  bool compress = true,
  PdfPageRaster? rasterPdfPage,
  PdfStamper? stamper,
}) async {
  final sheets = planSheets(note, pages: pages, canvas: canvas);
  final hasPdf = sheets.any((s) => s.page.pdf != null);

  if (hasPdf && stamper != null) {
    final overlay = await _build(note, sheets, fonts, compress, transparentPdfPages: true);
    try {
      final stamped = stamper([
        for (final s in sheets) s.page.pdf == null ? null : (note.assets[s.page.pdf!.assetId]!, s.page.pdf!.pageIndex),
      ], overlay);
      if (stamped != null) return stamped;
    } catch (_) {
      // fall back to raster backgrounds below
    }
  }
  final rasters = <String, Uint8List>{};
  if (hasPdf && rasterPdfPage != null) {
    for (final s in sheets) {
      final ref = s.page.pdf;
      if (ref == null) continue;
      final key = '${ref.assetId}#${ref.pageIndex}';
      if (rasters.containsKey(key)) continue;
      final png = await rasterPdfPage(ref, (s.page.width / 72 * 300).round()); // 300 dpi
      if (png != null) rasters[key] = png;
    }
  }
  return _build(note, sheets, fonts, compress, rasters: rasters);
}

Future<Uint8List> _build(Note note, List<ExportSheet> sheets, ExportFonts fonts, bool compress,
    {bool transparentPdfPages = false, Map<String, Uint8List> rasters = const {}}) async {
  pw.Font? f(Uint8List? b) => b == null ? null : pw.Font.ttf(ByteData.sublistView(b));
  final regular = f(fonts.regular), bold = f(fonts.bold), italic = f(fonts.italic), mono = f(fonts.mono);
  final metrics = _lineMetrics(fonts.regular);
  final doc = pw.Document(
    compress: compress,
    title: note.title,
    creator: 'CaretNotes',
    theme: regular == null ? null : pw.ThemeData.withFont(base: regular, bold: bold ?? regular, italic: italic ?? regular, boldItalic: bold ?? regular),
  );
  final images = <String, PdfImage>{};
  PdfImage? imageFor(String assetId) {
    if (images.containsKey(assetId)) return images[assetId];
    final b = note.assets[assetId];
    if (b == null) return null;
    try {
      return images[assetId] = PdfImage.file(doc.document, bytes: b);
    } catch (_) {
      return null;
    }
  }

  final bgImages = <String, PdfImage>{};
  for (final e in rasters.entries) {
    try {
      bgImages[e.key] = PdfImage.file(doc.document, bytes: e.value);
    } catch (_) {}
  }

  for (final s in sheets) {
    final a = s.area;
    final ref = s.page.pdf;
    final bg = ref == null ? null : bgImages['${ref.assetId}#${ref.pageIndex}'];
    final texts = [
      for (final e in s.page.elements)
        if (e is TextEl && e.rect.overlaps(a)) e,
    ];
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat(a.width, a.height, marginAll: 0),
      margin: pw.EdgeInsets.zero,
      build: (ctx) => pw.Stack(children: [
        pw.CustomPaint(
          size: PdfPoint(a.width, a.height),
          painter: (g, size) => _paintSheet(g, note, s, imageFor, bg, transparentPdfPages),
        ),
        for (final t in texts)
          if (t.ruled)
            pw.Positioned(
              left: t.rect.left - a.left,
              // First baseline where the editor puts it: just above the ruled line.
              top: t.rect.top - a.top + t.lineHeight! * 0.9 - metrics.ascent * t.fontSize,
              child: pw.SizedBox(width: math.max(10, t.rect.width), child: _markdown(t, mono, ruled: metrics)),
            )
          else
            pw.Positioned(
              left: t.rect.left - a.left + 4,
              top: t.rect.top - a.top + 4,
              child: pw.SizedBox(width: math.max(10, t.rect.width - 8), child: _markdown(t, mono)),
            ),
      ]),
    ));
  }
  return doc.save();
}

void _paintSheet(PdfGraphics g, Note note, ExportSheet s, PdfImage? Function(String) imageFor, PdfImage? bg, bool transparentPdf) {
  final a = s.area;
  // page coordinates (y down) → PDF (y up)
  g.setTransform(Matrix4(1, 0, 0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 0, a.height, 0, 1));
  g.setTransform(Matrix4.translationValues(-a.left, -a.top, 0));
  g.drawRect(a.left, a.top, a.width, a.height);
  g.clipPath();

  final p = s.page;
  if (p.pdf != null) {
    if (!transparentPdf) {
      g.setFillColor(PdfColors.white);
      g.drawRect(0, 0, p.width, p.height);
      g.fillPath();
      if (bg != null) {
        g.saveContext();
        g.setTransform(Matrix4.translationValues(0, p.height, 0)..scaleByDouble(1.0, -1.0, 1.0, 1.0));
        g.drawImage(bg, 0, 0, p.width, p.height);
        g.restoreContext();
      }
    }
  } else {
    _template(g, p.templateOverride ?? note.template, a, note.layout == NoteLayout.canvas ? null : RectD(0, 0, p.width, p.height));
  }

  for (final e in paintOrder(p.elements)) {
    if (!e.bounds().overlaps(a)) continue;
    switch (e) {
      case StrokeEl st:
        _stroke(g, st);
      case ImageEl im:
        _image(g, im, imageFor(im.assetId));
      case TextEl _:
        break; // drawn as real text on top
    }
  }
}

void _template(PdfGraphics g, Template t, RectD area, RectD? page) {
  g.setFillColor(PdfColor.fromInt(t.paperColor));
  g.drawRect(area.left, area.top, area.width, area.height);
  g.fillPath();
  final geo = paperGeometry(t, area, page: page);
  for (final l in geo.lines) {
    g.setStrokeColor(PdfColor.fromInt(l.color));
    g.setLineWidth(l.width * 0.85);
    g.moveTo(l.a.x, l.a.y);
    g.lineTo(l.b.x, l.b.y);
    g.strokePath();
  }
  if (geo.dots.isNotEmpty) {
    g.setFillColor(PdfColor.fromInt(geo.dotColor));
    for (final d in geo.dots) {
      g.drawEllipse(d.x, d.y, 0.8, 0.8);
    }
    g.fillPath();
  }
}

void _stroke(PdfGraphics g, StrokeEl s) {
  final o = strokeOutline(s.points, s.width, s.tool);
  if (o.isEmpty) return;
  final alpha = s.tool == ToolKind.highlighter ? 0.42 : (s.tool == ToolKind.pencil ? 0.82 : ((s.color >> 24) & 0xFF) / 255);
  g.saveContext();
  if (alpha < 0.999) g.setGraphicState(PdfGraphicState(opacity: alpha));
  g.setFillColor(PdfColor.fromInt(s.color | 0xFF000000));
  g.moveTo(o.first.x, o.first.y);
  for (final v in o.skip(1)) {
    g.lineTo(v.x, v.y);
  }
  g.closePath();
  g.fillPath();
  g.restoreContext();
}

void _image(PdfGraphics g, ImageEl e, PdfImage? img) {
  if (img == null) return;
  final r = e.rect;
  final w = r.width, h = r.height;
  final fullW = w / e.crop.width, fullH = h / e.crop.height;
  g.saveContext();
  g.setTransform(Matrix4.translationValues(r.center.x, r.center.y, 0)
    ..rotateZ(e.rotation)
    ..scaleByDouble(1.0, -1.0, 1.0, 1.0));
  // local coords now y-up, centered on the image
  g.drawRect(-w / 2, -h / 2, w, h);
  g.clipPath();
  final left = -w / 2 - e.crop.left * fullW;
  final bottom = h / 2 + e.crop.top * fullH - fullH;
  g.drawImage(img, left, bottom, fullW, fullH);
  g.restoreContext();
}

// ---------- Markdown → PDF text ----------

final _inlineRe = RegExp(r'(\*\*[^*]+\*\*|__[^_]+__|\*[^*]+\*|_[^_]+_|`[^`]+`|~~[^~]+~~|\$[^$]+\$|\[[^\]]+\]\([^)]+\))');

/// Ascent and descent (per 1 pt of font size) of the font the PDF text uses.
/// The pdf package makes every text line exactly (ascent - descent) × size tall.
class _LineMetrics {
  final double ascent, descent;
  const _LineMetrics(this.ascent, this.descent);
  double get height => ascent - descent;
}

_LineMetrics _lineMetrics(Uint8List? ttf) {
  if (ttf != null) {
    try {
      final p = TtfParser(ByteData.sublistView(ttf));
      return _LineMetrics(p.ascent / p.unitsPerEm, p.descent / p.unitsPerEm);
    } catch (_) {}
  }
  return const _LineMetrics(0.931, -0.225); // Helvetica, the pdf package's default
}

/// [ruled]: text typed on lines; every line is exactly [TextEl.lineHeight] apart and
/// headings/code keep the body size and font so they stay on the lines.
pw.Widget _markdown(TextEl t, pw.Font? mono, {_LineMetrics? ruled}) {
  final color = PdfColor.fromInt(t.color | 0xFF000000);
  final gap = ruled == null ? t.fontSize * 0.25 : t.lineHeight! - ruled.height * t.fontSize;
  final base = pw.TextStyle(fontSize: t.fontSize, color: color, lineSpacing: gap);
  if (ruled != null) mono = null;
  final codeStyle = mono == null ? base : base.copyWith(font: mono);
  pw.Widget block(pw.Widget w) => ruled == null ? w : pw.Padding(padding: pw.EdgeInsets.only(bottom: gap), child: w);
  final blocks = <pw.Widget>[];
  var inCode = false;
  final code = StringBuffer();
  for (var line in t.markdown.split('\n')) {
    if (line.trimLeft().startsWith('```')) {
      if (inCode) {
        blocks.add(ruled != null
            ? block(pw.Text(code.toString().trimRight(), style: codeStyle))
            : pw.Container(
                padding: const pw.EdgeInsets.all(4),
                color: PdfColor.fromInt(0x14808080),
                child: pw.Text(code.toString().trimRight(), style: codeStyle.copyWith(fontSize: t.fontSize * 0.92)),
              ));
        code.clear();
      }
      inCode = !inCode;
      continue;
    }
    if (inCode) {
      code.writeln(line);
      continue;
    }
    var style = base;
    final h = RegExp(r'^(#{1,6})\s+').firstMatch(line);
    if (h != null) {
      final level = h.group(1)!.length;
      style = ruled != null
          ? base.copyWith(fontWeight: pw.FontWeight.bold)
          : base.copyWith(fontSize: t.fontSize * (level == 1 ? 1.7 : level == 2 ? 1.4 : 1.2), fontWeight: pw.FontWeight.bold);
      line = line.substring(h.end);
    }
    line = line
        .replaceFirstMapped(RegExp(r'^(\s*)[-*+]\s+\[( |x|X)\]\s+'), (m) => '${m[1]}${m[2] == ' ' ? '[ ]' : '[x]'} ')
        .replaceFirstMapped(RegExp(r'^(\s*)[-*+]\s+'), (m) => '${m[1]}• ')
        .replaceFirstMapped(RegExp(r'^>\s?'), (m) => '| ');
    final spans = <pw.InlineSpan>[];
    var pos = 0;
    for (final m in _inlineRe.allMatches(line)) {
      if (m.start > pos) spans.add(pw.TextSpan(text: line.substring(pos, m.start), style: style));
      final s = m.group(0)!;
      if (s.startsWith('**') || s.startsWith('__')) {
        spans.add(pw.TextSpan(text: s.substring(2, s.length - 2), style: style.copyWith(fontWeight: pw.FontWeight.bold)));
      } else if (s.startsWith('~~')) {
        spans.add(pw.TextSpan(text: s.substring(2, s.length - 2), style: style.copyWith(decoration: pw.TextDecoration.lineThrough)));
      } else if (s.startsWith('`')) {
        spans.add(pw.TextSpan(text: s.substring(1, s.length - 1), style: mono == null ? style : style.copyWith(font: mono)));
      } else if (s.startsWith(r'$')) {
        spans.add(pw.TextSpan(text: s.substring(1, s.length - 1), style: style.copyWith(fontStyle: pw.FontStyle.italic)));
      } else if (s.startsWith('[')) {
        spans.add(pw.TextSpan(text: s.substring(1, s.indexOf(']')), style: style.copyWith(decoration: pw.TextDecoration.underline)));
      } else {
        spans.add(pw.TextSpan(text: s.substring(1, s.length - 1), style: style.copyWith(fontStyle: pw.FontStyle.italic)));
      }
      pos = m.end;
    }
    if (pos < line.length) spans.add(pw.TextSpan(text: line.substring(pos), style: style));
    if (spans.isEmpty) spans.add(pw.TextSpan(text: ' ', style: style));
    blocks.add(block(pw.RichText(text: pw.TextSpan(children: spans, style: style))));
  }
  if (inCode && code.isNotEmpty) blocks.add(pw.Text(code.toString(), style: codeStyle));
  return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: blocks);
}
