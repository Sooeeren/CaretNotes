import 'dart:math' as math;

import 'geometry.dart';
import 'model/elements.dart';
import 'model/page.dart';

/// One line of a paper template, in page coordinates.
class PaperLine {
  final Vec2 a, b;
  final double width;
  final int color;
  const PaperLine(this.a, this.b, this.width, this.color);
}

/// Everything a template draws inside an area: lines and dots. Shared by the
/// screen painter and the PDF export so both look the same.
class PaperGeometry {
  final List<PaperLine> lines;
  final List<Vec2> dots;
  final int dotColor;
  const PaperGeometry(this.lines, this.dots, this.dotColor);
}

/// Red notebook margin color on lined and Cornell paper.
const marginLineColor = 0x66E07070;

/// X position of the red margin line on lined paper (~2.5 cm on A4).
double notebookMargin(double spacing) => (spacing * 3).clamp(48.0, 84.0);

/// Ruled lines start this far down a page (room for a title).
double headerHeight(double spacing) => spacing * 2;

/// X of the Cornell cue column line.
double cornellCueX(double pageWidth) => (pageWidth * 0.3).roundToDouble();

/// Y of the Cornell summary line, on a ruled line, or null when the page is too tall for one (endless page).
double? cornellSummaryY(double pageWidth, double pageHeight, double spacing) {
  if (pageHeight > pageWidth * 1.8) return null;
  return (pageHeight * 0.8 / spacing).round() * spacing;
}

/// Music staff: distance between the five lines of one staff, and from one staff to the next.
double staffGap(double spacing) => spacing * 0.32;
double staffPitch(double spacing) => spacing * 3.4;

/// Lines and dots of [t] inside [area]. [page] is the whole page (null on an
/// infinite canvas); the header, margin and Cornell areas are placed relative to it.
PaperGeometry paperGeometry(Template t, RectD area, {RectD? page}) {
  final lines = <PaperLine>[];
  final dots = <Vec2>[];
  final s = t.spacing;
  if (t.kind == TemplateKind.blank || s < 4) return PaperGeometry(lines, dots, t.lineColor);
  final lc = t.lineColor;
  void h(double y, {double? x0, double? x1, double w = 0.6, int? color}) {
    if (y < area.top || y > area.bottom) return;
    final l = math.max(area.left, x0 ?? area.left), r = math.min(area.right, x1 ?? area.right);
    if (r > l) lines.add(PaperLine(Vec2(l, y), Vec2(r, y), w, color ?? lc));
  }

  void v(double x, {double? y0, double? y1, double w = 0.6, int? color}) {
    if (x < area.left || x > area.right) return;
    final top = math.max(area.top, y0 ?? area.top), bottom = math.min(area.bottom, y1 ?? area.bottom);
    if (bottom > top) lines.add(PaperLine(Vec2(x, top), Vec2(x, bottom), w, color ?? lc));
  }

  final x0 = (area.left / s).floor() * s, y0 = (area.top / s).floor() * s;
  final headerY = page == null ? -double.infinity : page.top + headerHeight(s);
  switch (t.kind) {
    case TemplateKind.lined:
      for (var y = y0; y <= area.bottom; y += s) {
        if (y < headerY) continue;
        h(y);
      }
      if (page != null) v(page.left + notebookMargin(s), y0: page.top, y1: page.bottom, w: 0.8, color: marginLineColor);
    case TemplateKind.cornell:
      if (page == null) return paperGeometry(t.copyWith(kind: TemplateKind.lined), area);
      final summary = cornellSummaryY(page.width, page.height, s);
      for (var y = y0; y <= area.bottom; y += s) {
        if (y < headerY) continue;
        h(y);
      }
      final cue = page.left + cornellCueX(page.width);
      v(cue, y0: headerY, y1: summary ?? page.bottom, w: 0.9, color: marginLineColor);
      h(headerY, w: 0.9, color: marginLineColor);
      if (summary != null) h(summary, w: 1.1, color: marginLineColor);
    case TemplateKind.grid:
      for (var y = y0; y <= area.bottom; y += s) {
        h(y);
      }
      for (var x = x0; x <= area.right; x += s) {
        v(x);
      }
    case TemplateKind.dots:
      for (var y = y0; y <= area.bottom; y += s) {
        if (y < area.top) continue;
        for (var x = x0; x <= area.right; x += s) {
          if (x >= area.left) dots.add(Vec2(x, y));
        }
      }
    case TemplateKind.staff:
      final gap = staffGap(s), pitch = staffPitch(s);
      final start = page == null ? 0.0 : headerY;
      final side = page == null ? null : s * 1.5;
      final first = math.max(0, ((area.top - start - 4 * gap) / pitch).floor());
      for (var i = first;; i++) {
        final top = start + i * pitch;
        if (top > area.bottom) break;
        if (page != null && top + 4 * gap > page.bottom - s) break;
        for (var k = 0; k < 5; k++) {
          h(top + k * gap, x0: side == null ? null : page!.left + side, x1: side == null ? null : page!.right - side, w: 0.7);
        }
      }
    case TemplateKind.blank:
      break;
  }
  return PaperGeometry(lines, dots, lc);
}

/// Where typed text goes on the lines: a full-width text frame whose first line
/// sits on the ruled line at or below [tap].
class RuledFrame {
  final double left, top, right;

  /// Height of one text line = the line spacing of the paper.
  final double lineHeight;
  const RuledFrame(this.left, this.top, this.right, this.lineHeight);
}

/// Text frame for typing on the lines of [t] at [tap]. [pageWidth] is null on an infinite canvas.
RuledFrame ruledFrameAt(Template t, Vec2 tap, {double? pageWidth, double? pageHeight}) {
  final s = t.spacing < 8 ? 22.0 : t.spacing;
  final isPage = pageWidth != null;
  // The text line band [(k-1)s, ks] holding the tap; its text sits on the line at y = ks.
  var k = (tap.y / s).floor() + 1;
  if (isPage) k = math.max(k, (headerHeight(s) / s).round()); // first ruled line is at the header
  final top = (k - 1) * s;
  double left, right;
  if (!isPage) {
    left = tap.x;
    right = tap.x + 480;
  } else {
    right = pageWidth - s;
    switch (t.kind) {
      case TemplateKind.lined:
        left = notebookMargin(s) + 6;
      case TemplateKind.cornell:
        final cue = cornellCueX(pageWidth);
        final summary = pageHeight == null ? null : cornellSummaryY(pageWidth, pageHeight, s);
        if (summary != null && top >= summary) {
          left = s;
        } else if (tap.x < cue) {
          left = s;
          right = cue - 6;
        } else {
          left = cue + 6;
        }
      case TemplateKind.grid || TemplateKind.dots:
        left = math.max(s, (tap.x / s).floor() * s);
      case TemplateKind.blank || TemplateKind.staff:
        left = math.max(s, tap.x);
    }
    if (right - left < 60) left = math.max(0, right - 60);
  }
  return RuledFrame(left, top, right, s);
}

/// Font size for text typed on lines with spacing [lineHeight].
double ruledFontSize(double lineHeight) => (lineHeight * 0.6).clamp(8.0, 40.0);

/// Ready-made paper templates shown in the template picker.
class PaperPreset {
  final String name;
  final TemplateKind kind;
  final double spacing;
  const PaperPreset(this.name, this.kind, this.spacing);
}

const _mm = 2.83465;
const paperPresets = [
  PaperPreset('Blank', TemplateKind.blank, 22),
  PaperPreset('Lined', TemplateKind.lined, 22),
  PaperPreset('Narrow lined', TemplateKind.lined, 6 * _mm),
  PaperPreset('Wide lined', TemplateKind.lined, 10 * _mm),
  PaperPreset('Cornell', TemplateKind.cornell, 22),
  PaperPreset('Grid 5 mm', TemplateKind.grid, 5 * _mm),
  PaperPreset('Grid 1 cm', TemplateKind.grid, 10 * _mm),
  PaperPreset('Dots', TemplateKind.dots, 5 * _mm),
  PaperPreset('Music staff', TemplateKind.staff, 22),
];

/// Moves text typed on lines onto paper with line spacing [lineHeight]: same line
/// number, same number of lines, font scaled along. Free text boxes are returned as is.
TextEl fitTextToLines(TextEl e, double lineHeight) {
  final old = e.lineHeight;
  if (old == null || old == lineHeight || lineHeight <= 0) return e;
  final k = (e.rect.top / old).round();
  final lines = math.max(1, (e.rect.height / old).round());
  final top = k * lineHeight;
  return TextEl(
    id: e.id,
    rect: RectD(e.rect.left, top, e.rect.right, top + lines * lineHeight),
    markdown: e.markdown,
    fontSize: e.fontSize * lineHeight / old,
    color: e.color,
    lineHeight: lineHeight,
  );
}
