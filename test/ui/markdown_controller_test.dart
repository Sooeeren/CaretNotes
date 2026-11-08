import 'package:caret_notes/core/geometry.dart';
import 'package:caret_notes/core/model/elements.dart';
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

  testWidgets('rendered text box with heading, math, checkbox and code shows without errors', (tester) async {
    const el = TextEl(
      id: 't',
      rect: RectD(0, 0, 400, 200),
      markdown: '# Eigenwerte\nGegeben **A**. Gesucht: '
          r'$\lambda$ mit $Av = \lambda v$'
          '\n- [x] done\n- [ ] open\n\n```python\nnp.linalg.eig(A)\n```',
    );
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox(width: 400, child: RenderedMarkdown(el: el)))));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Eigenwerte', findRichText: true), findsWidgets);
  });

  testWidgets('a scaled text box placed on the canvas is visible at the scaled position', (tester) async {
    const el = TextEl(id: 't', rect: RectD(0, 0, 300, 60), markdown: '# Heading here');
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Stack(children: [
          Positioned(left: 50, top: 40, child: ScaledBox(width: 300, height: 60, scale: 1.5, child: RenderedMarkdown(el: el))),
        ]),
      ),
    ));
    await tester.pump();
    final f = find.textContaining('Heading here', findRichText: true);
    expect(f, findsWidgets);
    final r = tester.getRect(f.first);
    expect(r.left, greaterThanOrEqualTo(50));
    expect(r.width, greaterThan(10));
    expect(r.top, lessThan(200));
  });
}
