import 'package:caret_notes/ui/editor/text_box.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

List<TextSpan> flat(InlineSpan s) {
  final out = <TextSpan>[];
  s.visitChildren((c) {
    if (c is TextSpan && c.text != null) out.add(c);
    return true;
  });
  return out;
}

void main() {
  const base = TextStyle(fontSize: 14, color: Colors.black);

  test('**x** renders x in bold while keeping the raw text', () {
    final span = MarkdownEditingController.styleMarkdown('a **x** b', base);
    final parts = flat(span);
    expect(parts.map((p) => p.text).join(), 'a **x** b');
    final x = parts.firstWhere((p) => p.text == 'x');
    expect(x.style?.fontWeight, FontWeight.w700);
  });

  test('# heading is larger than body text', () {
    final parts = flat(MarkdownEditingController.styleMarkdown('# Title\nbody', base));
    final title = parts.firstWhere((p) => p.text!.contains('Title'));
    final body = parts.firstWhere((p) => p.text!.contains('body'));
    expect(title.style!.fontSize!, greaterThan(body.style?.fontSize ?? 14));
  });

  test('syntax markers are dimmed', () {
    final parts = flat(MarkdownEditingController.styleMarkdown('**x**', base));
    final marker = parts.firstWhere((p) => p.text == '**');
    expect(marker.style!.color!.a, lessThan(1));
  });

  test('inline code uses a monospace font', () {
    final parts = flat(MarkdownEditingController.styleMarkdown('use `x+1` here', base));
    expect(parts.firstWhere((p) => p.text == 'x+1').style!.fontFamily, 'Consolas');
  });
}
