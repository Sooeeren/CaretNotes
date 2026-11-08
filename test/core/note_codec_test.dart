import 'dart:convert';
import 'dart:typed_data';

import 'package:caret_notes/core/format/note_codec.dart';
import 'package:caret_notes/core/geometry.dart';
import 'package:caret_notes/core/model/elements.dart';
import 'package:caret_notes/core/model/note.dart';
import 'package:flutter_test/flutter_test.dart';

Note sampleNote() {
  final n = Note.create(title: 'VL 4 · Eigenwerte', layout: NoteLayout.paged, deviceName: 'laptop');
  final page = n.pages.first.copyWith(elements: [
    StrokeEl(
      id: 's1',
      points: const [InkPoint(10, 10, 0.5), InkPoint(20, 30, 0.8)],
      tool: ToolKind.pen,
      color: 0xFF1B2A6B,
      width: 2.5,
    ),
    const TextEl(id: 't1', rect: RectD(50, 50, 250, 120), markdown: '# Hi\n**bold**', fontSize: 14, color: 0xFF222222),
    const ImageEl(id: 'i1', rect: RectD(0, 200, 100, 300), rotation: 0.3, assetId: 'a1', crop: RectD(0, 0, 1, 1), behindInk: true),
  ]);
  return n.copyWith(pages: [page], assets: {'a1': Uint8List.fromList([9, 8, 7])});
}

void main() {
  test('encode then decode round-trips note json and assets', () {
    final note = sampleNote();
    final bytes = encodeNote(note, thumb: Uint8List.fromList([1, 2, 3]));
    final back = decodeNote(bytes);
    expect(jsonEncode(back.toJson()), jsonEncode(note.toJson()));
    expect(back.assets['a1'], [9, 8, 7]);
    expect(readThumb(bytes), [1, 2, 3]);
  });

  test('decoding garbage throws NoteFormatException', () {
    expect(() => decodeNote(Uint8List.fromList([1, 2, 3, 4])), throwsA(isA<NoteFormatException>()));
  });

  test('new paged A4 note has one A4 page with stable uuid ids', () {
    final n = Note.create(title: 'x', layout: NoteLayout.paged, deviceName: 'd');
    expect(n.pages.length, 1);
    expect(n.pages.first.width, closeTo(595.28, 0.01));
    expect(n.pages.first.height, closeTo(841.89, 0.01));
    expect(n.id.length, 36);
  });

  test('stroke bounds include half the width', () {
    const s = StrokeEl(id: 's', points: [InkPoint(10, 10, 1), InkPoint(20, 10, 1)], tool: ToolKind.pen, color: 0, width: 4);
    expect(s.bounds(), const RectD(8, 8, 22, 12));
  });
}
