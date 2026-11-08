import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/geometry.dart';
import '../../core/ink/paint_order.dart';
import '../../core/ink/stroke_geometry.dart';
import '../../core/model/elements.dart';
import '../../core/model/note.dart';
import '../../core/model/page.dart';
import 'markdown_plain.dart';

/// Decoded images and rendered PDF pages needed to paint a note.
class RenderAssets {
  final Map<String, ui.Image> images;

  /// Rendered PDF background for a page (any resolution; it is scaled to the page).
  final ui.Image? Function(NotePage page)? pdfImage;
  const RenderAssets({this.images = const {}, this.pdfImage});
}

final _paths = Expando<ui.Path>('strokePath');

ui.Path strokePath(StrokeEl s) => _paths[s] ??= pathFromOutline(strokeOutline(s.points, s.width, s.tool));

ui.Path pathFromOutline(List<Vec2> outline) {
  final path = ui.Path()..fillType = ui.PathFillType.nonZero;
  if (outline.isEmpty) return path;
  path.moveTo(outline.first.x, outline.first.y);
  for (var i = 1; i < outline.length; i++) {
    path.lineTo(outline[i].x, outline[i].y);
  }
  path.close();
  return path;
}

Paint strokePaint(ToolKind tool, int color) {
  final c = Color(color);
  final p = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.fill;
  switch (tool) {
    case ToolKind.highlighter:
      p.color = c.withValues(alpha: 0.42);
    case ToolKind.pencil:
      p.color = c.withValues(alpha: 0.82);
    default:
      p.color = c;
  }
  return p;
}

Template effectiveTemplate(Note n, NotePage p) => p.templateOverride ?? n.template;

/// Paper color + lines/grid/dots across [area] (page-local coordinates).
void paintTemplate(Canvas c, Template t, Rect area, {bool fillPaper = true}) {
  if (fillPaper) c.drawRect(area, Paint()..color = Color(t.paperColor));
  if (t.kind == TemplateKind.blank) return;
  final s = t.spacing;
  if (s < 4) return;
  final line = Paint()
    ..color = Color(t.lineColor)
    ..strokeWidth = 0.6
    ..isAntiAlias = true;
  final x0 = (area.left / s).floor() * s, y0 = (area.top / s).floor() * s;
  switch (t.kind) {
    case TemplateKind.lined:
      for (var y = math.max(y0, area.top + 0.0); y <= area.bottom; y += s) {
        if (y < area.top + s * 2 && area.top == 0) continue; // header margin on pages
        c.drawLine(Offset(area.left, y), Offset(area.right, y), line);
      }
    case TemplateKind.grid:
      for (var y = y0; y <= area.bottom; y += s) {
        c.drawLine(Offset(area.left, y), Offset(area.right, y), line);
      }
      for (var x = x0; x <= area.right; x += s) {
        c.drawLine(Offset(x, area.top), Offset(x, area.bottom), line);
      }
    case TemplateKind.dots:
      final dot = Paint()..color = Color(t.lineColor).withValues(alpha: 1);
      for (var y = y0; y <= area.bottom; y += s) {
        for (var x = x0; x <= area.right; x += s) {
          c.drawCircle(Offset(x, y), 0.9, dot);
        }
      }
    case TemplateKind.blank:
      break;
  }
}

void paintImageEl(Canvas c, ImageEl e, RenderAssets a) {
  final img = a.images[e.assetId];
  final r = e.rect;
  c.save();
  c.translate(r.center.x, r.center.y);
  c.rotate(e.rotation);
  final dst = Rect.fromCenter(center: Offset.zero, width: r.width, height: r.height);
  if (img == null) {
    c.drawRect(dst, Paint()..color = const Color(0x22808080));
  } else {
    final w = img.width.toDouble(), h = img.height.toDouble();
    final src = Rect.fromLTRB(e.crop.left * w, e.crop.top * h, e.crop.right * w, e.crop.bottom * h);
    c.drawImageRect(img, src, dst, Paint()..filterQuality = FilterQuality.medium);
  }
  c.restore();
}

void paintTextEl(Canvas c, TextEl t) {
  final tp = TextPainter(text: markdownToPlainSpan(t.markdown, t.fontSize, Color(t.color)), textDirection: TextDirection.ltr)
    ..layout(maxWidth: math.max(10, t.rect.width - 8));
  tp.paint(c, Offset(t.rect.left + 4, t.rect.top + 4));
}

/// Paints page elements in paint order. Text is skipped when it is shown as live widgets.
void paintElements(Canvas c, NotePage p, RenderAssets a, {bool paintText = true, Set<String> hidden = const {}, Rect? visible}) {
  for (final e in paintOrder(p.elements)) {
    if (hidden.contains(e.id)) continue;
    if (visible != null) {
      final b = e.bounds();
      if (b.right < visible.left || b.left > visible.right || b.bottom < visible.top || b.top > visible.bottom) continue;
    }
    switch (e) {
      case StrokeEl s:
        c.drawPath(strokePath(s), strokePaint(s.tool, s.color));
      case ImageEl i:
        paintImageEl(c, i, a);
      case TextEl t:
        if (paintText) paintTextEl(c, t);
    }
  }
}

/// Full page: paper, template, PDF background, elements. [area] limits drawing for canvas notes.
void paintPage(Canvas c, Note n, NotePage p, RenderAssets a, {Rect? area, bool paintText = true, Set<String> hidden = const {}}) {
  final canvasLayout = n.layout == NoteLayout.canvas;
  final pageRect = canvasLayout ? (area ?? const Rect.fromLTWH(0, 0, 800, 800)) : Rect.fromLTWH(0, 0, p.width, p.height);
  final t = effectiveTemplate(n, p);
  if (p.pdf != null) {
    c.drawRect(pageRect, Paint()..color = Colors.white);
    final img = a.pdfImage?.call(p);
    if (img != null) {
      c.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), pageRect,
          Paint()..filterQuality = FilterQuality.medium);
    }
  } else {
    paintTemplate(c, t, pageRect);
  }
  if (!canvasLayout) {
    c.save();
    c.clipRect(pageRect);
  }
  paintElements(c, p, a, paintText: paintText, hidden: hidden, visible: area);
  if (!canvasLayout) c.restore();
}

/// Bounds of everything drawn on a canvas note (for thumbnails/export).
Rect contentBounds(NotePage p, {double pad = 40}) {
  RectD? r;
  for (final e in p.elements) {
    r = r == null ? e.bounds() : r.union(e.bounds());
  }
  if (r == null) return const Rect.fromLTWH(0, 0, 800, 600);
  return Rect.fromLTRB(r.left - pad, r.top - pad, r.right + pad, r.bottom + pad);
}

/// Renders [area] of a page (page coords; defaults to the whole page) at [scale] px per point.
Future<ui.Image> renderPageImage(Note n, NotePage p, RenderAssets a, double scale, {Rect? area, bool paintText = true}) async {
  final rect = area ?? (n.layout == NoteLayout.canvas ? contentBounds(p) : Rect.fromLTWH(0, 0, p.width, p.height));
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  c.scale(scale);
  c.translate(-rect.left, -rect.top);
  if (n.layout == NoteLayout.canvas) {
    paintPage(c, n, p, a, area: rect, paintText: paintText);
  } else {
    c.clipRect(rect);
    paintPage(c, n, p, a, paintText: paintText);
  }
  final pic = rec.endRecording();
  final img = await pic.toImage(math.max(1, (rect.width * scale).round()), math.max(1, (rect.height * scale).round()));
  pic.dispose();
  return img;
}

Future<Uint8List?> encodePng(ui.Image img) async {
  final bd = await img.toByteData(format: ui.ImageByteFormat.png);
  return bd?.buffer.asUint8List();
}

/// First-page thumbnail, ~360 px wide. Endless notes show their top part.
Future<Uint8List?> renderThumbnail(Note n, RenderAssets a) async {
  if (n.pages.isEmpty) return null;
  final p = n.pages.first;
  Rect area;
  if (n.layout == NoteLayout.canvas) {
    final b = contentBounds(p);
    final h = math.max(b.height, b.width * 4 / 3);
    area = Rect.fromLTWH(b.left, b.top, b.width, h);
  } else {
    area = Rect.fromLTWH(0, 0, p.width, math.min(p.height, p.width * 4 / 3));
  }
  final img = await renderPageImage(n, p, a, 360 / area.width, area: area);
  final png = await encodePng(img);
  img.dispose();
  return png;
}

/// Decodes all image assets used by a note.
Future<Map<String, ui.Image>> decodeImages(Note n, {Map<String, ui.Image>? into}) async {
  final out = into ?? <String, ui.Image>{};
  final used = <String>{
    for (final p in n.pages)
      for (final e in p.elements)
        if (e is ImageEl) e.assetId,
  };
  for (final id in used) {
    if (out.containsKey(id)) continue;
    final bytes = n.assets[id];
    if (bytes == null) continue;
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      out[id] = (await codec.getNextFrame()).image;
    } catch (_) {}
  }
  return out;
}

/// One page as a widget-layer painter (document coords × [scale]).
class PagePainter extends CustomPainter {
  final Note note;
  final NotePage page;
  final RenderAssets assets;
  final double scale;
  final int assetsVersion;
  final Set<String> hidden;

  /// For canvas notes: page-coordinate rect currently visible.
  final Rect? area;

  PagePainter({
    required this.note,
    required this.page,
    required this.assets,
    required this.scale,
    required this.assetsVersion,
    this.hidden = const {},
    this.area,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    if (area != null) {
      canvas.scale(scale);
      canvas.translate(-area!.left, -area!.top);
      paintPage(canvas, note, page, assets, area: area, paintText: false, hidden: hidden);
    } else {
      canvas.scale(scale);
      paintPage(canvas, note, page, assets, paintText: false, hidden: hidden);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(PagePainter old) =>
      !identical(old.page, page) ||
      old.scale != scale ||
      old.assetsVersion != assetsVersion ||
      old.area != area ||
      !identical(old.note.template, note.template) ||
      old.hidden.length != hidden.length;
}
