// Fills a library folder with demo notes: dart run tool/seed_demo.dart <libraryDir>
import 'dart:io';
import 'dart:math' as math;

import 'package:caret_notes/core/geometry.dart';
import 'package:caret_notes/core/library/library_store.dart';
import 'package:caret_notes/core/model/elements.dart';
import 'package:caret_notes/core/model/folder_meta.dart';
import 'package:caret_notes/core/model/note.dart';
import 'package:caret_notes/core/model/page.dart';

int _id = 0;
String nid() => 'demo-${_id++}';

/// A wavy "handwriting" line of words starting at (x, y).
List<StrokeEl> scribble(double x, double y, int words, {int color = 0xFF1B2A6B}) {
  final r = math.Random(x.toInt() * 31 + y.toInt());
  final out = <StrokeEl>[];
  var cx = x;
  for (var w = 0; w < words; w++) {
    final len = 30 + r.nextDouble() * 50;
    final waves = 6 + r.nextInt(4);
    final pts = <InkPoint>[];
    for (var i = 0; i <= 40; i++) {
      final t = i / 40;
      pts.add(InkPoint(cx + t * len, y + math.sin(t * math.pi * waves) * 6, 0.4 + 0.5 * math.sin(t * math.pi)));
    }
    out.add(StrokeEl(id: nid(), points: pts, tool: ToolKind.pen, color: color, width: 1.8));
    cx += len + 10;
  }
  return out;
}

Future<void> main(List<String> args) async {
  final lib = LibraryStore(args.first);
  await lib.ensureRoot();
  final sem = await lib.createFolder('', 'Semester 3', const FolderMeta(color: 0xFF3B6FE0, icon: 'school'));
  final la = await lib.createFolder(sem, 'Lineare Algebra', const FolderMeta(color: 0xFFFF8A1F, icon: 'functions'));
  await lib.createFolder(sem, 'Physik', const FolderMeta(color: 0xFF1A8F3C, icon: 'science'));
  await lib.createFolder('', 'Privat', const FolderMeta(color: 0xFFD23B3B, icon: 'heart'));

  final n = Note.create(
      title: 'VL 4 · Eigenwerte', layout: NoteLayout.paged, deviceName: 'demo', template: const Template(kind: TemplateKind.grid, spacing: 18));
  final els = <Element>[
    const TextEl(id: 't1', rect: RectD(50, 40, 545, 120), markdown: '# Eigenwerte\nGegeben **A** ∈ ℝⁿˣⁿ. Gesucht: \$\\lambda\$ mit \$Av = \\lambda v\$'),
    StrokeEl(id: 'hl', points: [for (var i = 0; i <= 20; i++) InkPoint(60 + i * 12.0, 162, .5)], tool: ToolKind.highlighter, color: 0xFFFFE14D, width: 16),
    ...scribble(60, 160, 5),
    ...scribble(60, 200, 6),
    ...scribble(60, 240, 4, color: 0xFFD23B3B),
    StrokeEl(
        id: 'box',
        points: [for (final c in const [Vec2(55, 280), Vec2(330, 280), Vec2(330, 360), Vec2(55, 360), Vec2(55, 280)]) InkPoint(c.x, c.y, .6)],
        tool: ToolKind.pen,
        color: 0xFF1A8F3C,
        width: 2),
    ...scribble(70, 320, 3),
    const TextEl(
        id: 't2',
        rect: RectD(50, 400, 545, 560),
        markdown: '## Vorgehen\n- [x] charakteristisches Polynom\n- [ ] Nullstellen\n- Eigenvektoren lösen\n\n```python\nnp.linalg.eig(A)\n```',
        fontSize: 12),
  ];
  await lib.createNote(la, n.copyWith(pages: [n.pages.first.copyWith(elements: els), NotePage.blank(n.pageWidth, n.pageHeight)]));
  final e = Note.create(title: 'Mitschrift endlos', layout: NoteLayout.endless, deviceName: 'demo');
  await lib.createNote(la, e.copyWith(pages: [e.pages.first.copyWith(elements: [...scribble(40, 80, 6), ...scribble(40, 120, 5)])]));
  final c = Note.create(title: 'Brainstorming', layout: NoteLayout.canvas, deviceName: 'demo', template: const Template(kind: TemplateKind.dots));
  await lib.createNote('', c.copyWith(pages: [c.pages.first.copyWith(elements: [...scribble(100, 100, 3), ...scribble(400, 300, 2)])]));
  stdout.writeln('seeded ${lib.root}');
}
