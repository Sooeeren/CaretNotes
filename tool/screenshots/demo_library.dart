// Demo notes for the README screenshots. Pure Dart (no Flutter), shared by the
// screenshot script. Everything is drawn in document points on A4.
import 'dart:math' as math;

import 'package:caret_notes/core/geometry.dart';
import 'package:caret_notes/core/model/elements.dart';
import 'package:caret_notes/core/model/note.dart';
import 'package:caret_notes/core/model/page.dart';

int _n = 0;
String _id() => 'shot-${_n++}';

const navy = 0xFF1B2A6B;
const red = 0xFFD23B3B;
const green = 0xFF1A8F3C;
const yellow = 0xFFFFE14D;

/// A hand-drawn stroke through [pts]: points are resampled and get a little wobble and pressure.
StrokeEl ink(List<Vec2> pts, {int color = navy, double width = 1.9, ToolKind tool = ToolKind.pen, int seed = 1}) {
  final r = math.Random(seed);
  final out = <InkPoint>[];
  for (var i = 0; i < pts.length - 1; i++) {
    final a = pts[i], b = pts[i + 1];
    final len = (b - a).length;
    final steps = math.max(2, (len / 3).round());
    for (var k = 0; k < steps; k++) {
      final t = k / steps;
      final wob = tool == ToolKind.highlighter ? 0.0 : 0.35;
      out.add(InkPoint(
        a.x + (b.x - a.x) * t + (r.nextDouble() - 0.5) * wob,
        a.y + (b.y - a.y) * t + (r.nextDouble() - 0.5) * wob,
        0.55 + 0.25 * math.sin((out.length / 9) + seed),
      ));
    }
  }
  out.add(InkPoint(pts.last.x, pts.last.y, 0.45));
  return StrokeEl(id: _id(), points: out, tool: tool, color: color, width: width);
}

/// Arrow from [a] to [b] as two strokes (shaft + head).
List<StrokeEl> arrow(Vec2 a, Vec2 b, {int color = navy, double width = 1.9, int seed = 1}) {
  final d = b - a;
  final l = d.length;
  final u = Vec2(d.x / l, d.y / l);
  final n = Vec2(-u.y, u.x);
  const h = 9.0;
  final p1 = Vec2(b.x - u.x * h + n.x * h * 0.55, b.y - u.y * h + n.y * h * 0.55);
  final p2 = Vec2(b.x - u.x * h - n.x * h * 0.55, b.y - u.y * h - n.y * h * 0.55);
  return [ink([a, b], color: color, width: width, seed: seed), ink([p1, b, p2], color: color, width: width, seed: seed + 1)];
}

/// A slightly uneven ellipse around [r], like a circled answer.
StrokeEl loop(RectD r, {int color = red, int seed = 3}) {
  final pts = <Vec2>[];
  for (var i = 0; i <= 44; i++) {
    final t = i / 40 * 2 * math.pi - 0.5;
    final k = 1 + 0.04 * math.sin(t * 3 + seed);
    pts.add(Vec2(r.center.x + math.cos(t) * r.width / 2 * k, r.center.y + math.sin(t) * r.height / 2 * k));
  }
  return ink(pts, color: color, width: 1.7, seed: seed);
}

/// A gentle curve through [pts] (Catmull-Rom), for graph sketches.
List<Vec2> curve(List<Vec2> pts) {
  final out = <Vec2>[];
  for (var i = 0; i < pts.length - 1; i++) {
    final p0 = pts[math.max(0, i - 1)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[math.min(pts.length - 1, i + 2)];
    for (var k = 0; k < 8; k++) {
      final t = k / 8, t2 = t * t, t3 = t2 * t;
      double c(double a, double b, double c, double d) =>
          0.5 * (2 * b + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3);
      out.add(Vec2(c(p0.x, p1.x, p2.x, p3.x), c(p0.y, p1.y, p2.y, p3.y)));
    }
  }
  out.add(pts.last);
  return out;
}

TextEl lines(double top, String md, {double left = 72, double right = 573, int nLines = 1, int color = 0xFF222222}) =>
    TextEl(id: _id(), rect: RectD(left, top, right, top + nLines * 22), markdown: md, fontSize: 13.2, color: color, lineHeight: 22);

TextEl box(RectD r, String md, {double size = 12, int color = 0xFF222222}) => TextEl(id: _id(), rect: r, markdown: md, fontSize: size, color: color);

/// The hero note: typed lecture notes on the lines plus sketches and highlights.
Note lectureNote() {
  final n = Note.create(title: 'Lecture 4 · Eigenvalues', layout: NoteLayout.paged, deviceName: 'demo');
  const o = Vec2(112, 376); // origin of the sketch
  final els = <Element>[
    // Highlighter first: it is painted under the ink anyway.
    ink([const Vec2(246, 80), const Vec2(336, 80)], color: yellow, width: 14, tool: ToolKind.highlighter),
    lines(22, '# Eigenvalues and eigenvectors\n'
        'For a square matrix **A**, find a number λ and a vector v ≠ 0 with **Av = λv**.\n'
        '- Characteristic polynomial: det(A − λI) = 0\n'
        '- Every root λ is an eigenvalue of A\n'
        '- Eigenvectors: solve (A − λI) v = 0 for each λ\n'
        '- A worked 2 × 2 example is below', nLines: 6),
    // Sketch: axes, v and Av on the same line.
    ...arrow(Vec2(o.x - 14, o.y), Vec2(o.x + 214, o.y), seed: 10),
    ...arrow(Vec2(o.x, o.y + 12), Vec2(o.x, o.y - 186), seed: 12),
    ...arrow(o, Vec2(o.x + 62, o.y - 52), seed: 14),
    ...arrow(o, Vec2(o.x + 160, o.y - 134), color: red, width: 2.1, seed: 16),
    box(RectD(o.x + 54, o.y - 34, o.x + 110, o.y - 14), '*v*', size: 13, color: navy),
    box(RectD(o.x + 150, o.y - 168, o.x + 230, o.y - 146), '*Av = 3v*', size: 13, color: red),
    // Worked example in a free text box, answer circled by hand.
    box(const RectD(352, 184, 565, 330), '**Example**  A = [[2, 1], [1, 2]]\n\n| λ | v |\n| --- | --- |\n| 3 | (1, 1) |\n| 1 | (1, −1) |'),
    loop(const RectD(348, 237, 452, 263)),
    // More notes on the lines.
    lines(462, '## Useful facts\n'
        '- λ₁ + λ₂ + … + λₙ = trace(A)\n'
        '- λ₁ · λ₂ · … · λₙ = det(A)\n'
        '- A symmetric: real eigenvalues, orthogonal eigenvectors', nLines: 4),
    ink([const Vec2(72, 487), const Vec2(206, 485)], color: green, width: 1.6, seed: 30),
    ink([const Vec2(258, 495), const Vec2(263, 501), const Vec2(273, 489)], color: green, width: 1.8, seed: 31),
    ink([const Vec2(246, 517), const Vec2(251, 523), const Vec2(261, 511)], color: green, width: 1.8, seed: 32),
  ];
  return n.copyWith(pages: [n.pages.first.copyWith(elements: els), NotePage.blank(n.pageWidth, n.pageHeight)]);
}

Note simpleNote(String title, Template t, {NoteLayout layout = NoteLayout.paged, List<Element> els = const []}) {
  final n = Note.create(title: title, layout: layout, deviceName: 'demo', template: t);
  return n.copyWith(pages: [n.pages.first.copyWith(elements: els)]);
}

/// Cornell sheet used for the dark-mode screenshot and the library.
Note cornellNote({bool dark = false}) {
  final t = Template(
    kind: TemplateKind.cornell,
    paperColor: dark ? Template.darkPaper : 0xFFFFFFFF,
    lineColor: dark ? Template.darkLine : 0xFFD6E0F0,
  );
  final ink1 = dark ? 0xFFE8EAF0 : 0xFF222222;
  final blue = dark ? 0xFF8FB4FF : navy;
  final els = <Element>[
    lines(22, '# Exercise sheet 4', color: ink1, left: 22),
    lines(66, 'Diagonalize?\n\nSpectral theorem\n\nTrace check', left: 22, right: 172, nLines: 5, color: blue),
    lines(66, 'A = PDP⁻¹ works when A has n independent eigenvectors.\n'
        '- Repeated λ: count the eigenvectors, not the roots\n'
        'Symmetric matrices are always diagonalizable, with orthonormal P.\n\n'
        'trace(A) = 4 = 3 + 1, checks out', left: 184, nLines: 6, color: ink1),
    ink([const Vec2(184, 199), const Vec2(300, 197)], color: dark ? 0xFFFFB054 : red, width: 1.6, seed: 40),
    ...arrow(const Vec2(150, 110), const Vec2(182, 110), color: dark ? 0xFFFFB054 : red, seed: 41),
    lines(682, 'Summary: count independent eigenvectors; symmetric ⇒ always works.', left: 22, nLines: 1, color: ink1),
  ];
  return simpleNote('Exercise sheet 4', t, els: els);
}
