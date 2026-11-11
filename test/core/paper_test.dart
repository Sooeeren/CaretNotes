import 'package:caret_notes/core/format/note_codec.dart';
import 'package:caret_notes/core/geometry.dart';
import 'package:caret_notes/core/model/elements.dart';
import 'package:caret_notes/core/model/note.dart';
import 'package:caret_notes/core/model/page.dart';
import 'package:caret_notes/core/paper.dart';
import 'package:flutter_test/flutter_test.dart';

const a4 = RectD(0, 0, 595.28, 841.89);

void main() {
  group('paper geometry', () {
    test('lined paper: lines every spacing below the header, plus the margin line', () {
      final g = paperGeometry(const Template(kind: TemplateKind.lined, spacing: 22), a4, page: a4);
      final horizontal = g.lines.where((l) => l.a.y == l.b.y).map((l) => l.a.y).toList();
      expect(horizontal.first, 44); // header of two lines
      expect(horizontal[1] - horizontal[0], 22);
      expect(g.lines.where((l) => l.a.x == l.b.x && l.color == marginLineColor), hasLength(1));
    });

    test('lined paper without a margin: the same lines, no red line, text starts at the left', () {
      const plain = Template(kind: TemplateKind.linedPlain, spacing: 22);
      final g = paperGeometry(plain, a4, page: a4);
      final withMargin = paperGeometry(const Template(kind: TemplateKind.lined, spacing: 22), a4, page: a4);
      expect(g.lines.every((l) => l.a.y == l.b.y && l.color != marginLineColor), isTrue);
      expect(g.lines.map((l) => l.a.y), withMargin.lines.where((l) => l.a.y == l.b.y).map((l) => l.a.y));
      expect(paperPresets.where((p) => p.kind == TemplateKind.linedPlain), isNotEmpty);
      final f = ruledFrameAt(plain, const Vec2(300, 100), pageWidth: a4.width, pageHeight: a4.height);
      expect(f.left, lessThan(notebookMargin(22)));
      expect(f.top, 88);
      expect(Template.fromJson(plain.toJson()).kind, TemplateKind.linedPlain);
    });

    test('Cornell paper has a cue column and a summary line', () {
      final g = paperGeometry(const Template(kind: TemplateKind.cornell, spacing: 22), a4, page: a4);
      final cue = cornellCueX(a4.width);
      expect(g.lines.any((l) => l.a.x == cue && l.b.x == cue), isTrue);
      final summary = cornellSummaryY(a4.width, a4.height, 22)!;
      expect(summary % 22, 0);
      expect(g.lines.any((l) => l.a.y == summary && l.width > 1), isTrue);
    });

    test('music staff draws groups of five lines', () {
      final g = paperGeometry(const Template(kind: TemplateKind.staff, spacing: 22), a4, page: a4);
      expect(g.lines.length % 5, 0);
      expect(g.lines.length, greaterThanOrEqualTo(5 * 8));
    });

    test('dots and blank', () {
      expect(paperGeometry(const Template(kind: TemplateKind.blank), a4, page: a4).lines, isEmpty);
      final d = paperGeometry(const Template(kind: TemplateKind.dots, spacing: 20), const RectD(0, 0, 100, 100));
      expect(d.dots, hasLength(36));
    });

    test('only the part of the page inside the area is produced', () {
      final g = paperGeometry(const Template(kind: TemplateKind.lined, spacing: 22), const RectD(0, 400, 595, 500), page: a4);
      expect(g.lines.where((l) => l.a.y == l.b.y).every((l) => l.a.y >= 400 && l.a.y <= 500), isTrue);
    });

    test('unknown template kinds from newer files fall back to lined', () {
      final t = Template.fromJson({'kind': 'hexagons', 'spacing': 22, 'paper': 0xFFFFFFFF, 'line': 0xFFD6E0F0});
      expect(t.kind, TemplateKind.lined);
    });
  });

  group('typing on lines', () {
    const lined = Template(kind: TemplateKind.lined, spacing: 22);

    test('the text frame starts right of the margin and its first line sits on the ruled line', () {
      final f = ruledFrameAt(lined, const Vec2(300, 100), pageWidth: a4.width, pageHeight: a4.height);
      expect(f.left, greaterThan(notebookMargin(22)));
      expect(f.right, a4.width - 22);
      expect(f.lineHeight, 22);
      expect(f.top, 88); // band 88..110 holds y=100, text sits on the line at 110
    });

    test('a tap in the header goes to the first ruled line', () {
      final f = ruledFrameAt(lined, const Vec2(300, 5), pageWidth: a4.width, pageHeight: a4.height);
      expect(f.top + f.lineHeight, headerHeight(22));
    });

    test('Cornell: the cue column and the notes column get their own frames', () {
      const c = Template(kind: TemplateKind.cornell, spacing: 22);
      final cue = ruledFrameAt(c, const Vec2(60, 200), pageWidth: a4.width, pageHeight: a4.height);
      final notes = ruledFrameAt(c, const Vec2(400, 200), pageWidth: a4.width, pageHeight: a4.height);
      expect(cue.right, lessThan(cornellCueX(a4.width)));
      expect(notes.left, greaterThan(cornellCueX(a4.width)));
    });

    test('moving ruled text snaps it back onto the lines', () {
      const t = TextEl(id: 't', rect: RectD(80, 88, 500, 110), markdown: 'x', lineHeight: 22);
      final moved = t.transformed(Affine.translate(5, 30));
      expect(moved.rect.top % 22, 0);
      expect(moved.rect.left, 85);
      expect(moved.lineHeight, 22);
      const free = TextEl(id: 'f', rect: RectD(80, 88, 500, 110), markdown: 'x');
      expect(free.transformed(Affine.translate(5, 30)).rect.top, 118);
    });

    test('changing the line spacing moves text on lines to the same lines of the new paper', () {
      const t = TextEl(id: 't', rect: RectD(80, 88, 500, 132), markdown: 'a\nb', fontSize: 13.2, lineHeight: 22);
      final f = fitTextToLines(t, 33);
      expect(f.lineHeight, 33);
      expect(f.rect.top, 4 * 33); // was on line band 4
      expect(f.rect.height, 2 * 33);
      expect(f.fontSize, closeTo(19.8, 1e-9));
      const box = TextEl(id: 'b', rect: RectD(0, 0, 10, 10), markdown: '');
      expect(identical(fitTextToLines(box, 33), box), isTrue);
    });

    test('ruled text survives saving and loading; old text boxes stay free', () {
      final n = Note.create(title: 'n', layout: NoteLayout.paged, deviceName: 'd');
      final pg = n.pages.first.copyWith(elements: const [
        TextEl(id: 'r', rect: RectD(80, 88, 500, 110), markdown: 'on lines', lineHeight: 22),
        TextEl(id: 'b', rect: RectD(80, 300, 300, 340), markdown: 'box'),
      ]);
      final back = decodeNote(encodeNote(n.copyWith(pages: [pg])));
      expect((back.pages.first.find('r') as TextEl).lineHeight, 22);
      expect((back.pages.first.find('b') as TextEl).lineHeight, isNull);
    });
  });
}
