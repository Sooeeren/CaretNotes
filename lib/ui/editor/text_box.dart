import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:highlight/highlight.dart' show highlight, Node;
import 'package:markdown/markdown.dart' as md;

import '../../core/model/elements.dart';

/// Text controller that styles Markdown while you type (Typora/Obsidian style):
/// the raw syntax stays in the text, markers are dimmed, content is formatted.
class MarkdownEditingController extends TextEditingController {
  MarkdownEditingController({super.text});

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) =>
      styleMarkdown(text, style ?? const TextStyle());

  static final _inline = RegExp(r'(\*\*)([^*\n]+)(\*\*)|(__)([^_\n]+)(__)|(~~)([^~\n]+)(~~)|(`)([^`\n]+)(`)|(\$)([^$\n]+)(\$)|(\*)([^*\n]+)(\*)|(_)([^_\n]+)(_)');

  static TextSpan styleMarkdown(String text, TextStyle base) {
    final dim = base.copyWith(color: (base.color ?? Colors.black).withValues(alpha: 0.38));
    final children = <InlineSpan>[];
    final lines = text.split('\n');
    var inCode = false;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final nl = i < lines.length - 1 ? '\n' : '';
      final mono = base.copyWith(fontFamily: 'Consolas', backgroundColor: const Color(0x14808080));
      if (line.trimLeft().startsWith('```')) {
        inCode = !inCode;
        children.add(TextSpan(text: '$line$nl', style: dim.copyWith(fontFamily: 'Consolas')));
        continue;
      }
      if (inCode) {
        children.add(TextSpan(text: '$line$nl', style: mono));
        continue;
      }
      var style = base;
      var rest = line;
      final h = RegExp(r'^(#{1,6}\s+)').firstMatch(line);
      final list = RegExp(r'^(\s*(?:[-*+]|\d+\.)\s+(?:\[[ xX]\]\s+)?)').firstMatch(line);
      final quote = RegExp(r'^(>\s?)').firstMatch(line);
      if (h != null) {
        final level = h.group(1)!.trim().length;
        final size = (base.fontSize ?? 14) * (level == 1 ? 1.7 : level == 2 ? 1.4 : 1.2);
        style = base.copyWith(fontSize: size, fontWeight: FontWeight.w700);
        children.add(TextSpan(text: h.group(1), style: dim.copyWith(fontSize: size)));
        rest = line.substring(h.end);
      } else if (list != null) {
        children.add(TextSpan(text: list.group(1), style: base.copyWith(color: (base.color ?? Colors.black).withValues(alpha: 0.6))));
        rest = line.substring(list.end);
      } else if (quote != null) {
        children.add(TextSpan(text: quote.group(1), style: dim));
        style = base.copyWith(fontStyle: FontStyle.italic);
        rest = line.substring(quote.end);
      }
      var pos = 0;
      for (final m in _inline.allMatches(rest)) {
        if (m.start > pos) children.add(TextSpan(text: rest.substring(pos, m.start), style: style));
        // find which group triple matched
        for (var g = 1; g <= 19; g += 3) {
          if (m.group(g) == null) continue;
          final open = m.group(g)!, body = m.group(g + 1)!, close = m.group(g + 2)!;
          final TextStyle bodyStyle = switch (open) {
            '**' || '__' => style.copyWith(fontWeight: FontWeight.w700),
            '~~' => style.copyWith(decoration: TextDecoration.lineThrough),
            '`' => style.copyWith(fontFamily: 'Consolas', backgroundColor: const Color(0x14808080)),
            r'$' => style.copyWith(fontStyle: FontStyle.italic, color: const Color(0xFF3B6FE0)),
            _ => style.copyWith(fontStyle: FontStyle.italic),
          };
          children.add(TextSpan(text: open, style: dim.copyWith(fontSize: style.fontSize)));
          children.add(TextSpan(text: body, style: bodyStyle));
          children.add(TextSpan(text: close, style: dim.copyWith(fontSize: style.fontSize)));
          break;
        }
        pos = m.end;
      }
      if (pos < rest.length) children.add(TextSpan(text: rest.substring(pos), style: style));
      if (nl.isNotEmpty) children.add(TextSpan(text: nl, style: style));
    }
    return TextSpan(style: base, children: children);
  }
}

/// Height in document points that [markdown] needs at [width], when editing.
double measureMarkdownHeight(String markdown, double width, double fontSize) {
  final tp = TextPainter(
    text: MarkdownEditingController.styleMarkdown(markdown.isEmpty ? ' ' : markdown, TextStyle(fontSize: fontSize, height: 1.35)),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: math.max(10, width - 8));
  return tp.height + 12;
}

class _MathSyntax extends md.InlineSyntax {
  _MathSyntax() : super(r'\$\$([^$]+)\$\$|\$([^$\n]+)\$');
  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final display = match.group(1) != null;
    final el = md.Element.text('math', match.group(1) ?? match.group(2)!);
    el.attributes['display'] = display ? '1' : '0';
    parser.addNode(el);
    return true;
  }
}

class _MathBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(BuildContext context, md.Element element, TextStyle? preferredStyle, TextStyle? parentStyle) {
    final display = element.attributes['display'] == '1';
    final w = Math.tex(
      element.textContent,
      mathStyle: display ? MathStyle.display : MathStyle.text,
      textStyle: preferredStyle ?? parentStyle,
      onErrorFallback: (e) => Text(element.textContent, style: (preferredStyle ?? const TextStyle()).copyWith(color: Colors.red)),
    );
    return display ? Center(child: w) : w;
  }
}

class _Highlighter extends SyntaxHighlighter {
  final double fontSize;
  final bool dark;
  _Highlighter(this.fontSize, this.dark);

  static const _light = {
    'keyword': Color(0xFFA626A4),
    'built_in': Color(0xFFC18401),
    'type': Color(0xFFC18401),
    'literal': Color(0xFF0184BB),
    'number': Color(0xFF986801),
    'string': Color(0xFF50A14F),
    'comment': Color(0xFFA0A1A7),
    'title': Color(0xFF4078F2),
    'function': Color(0xFF4078F2),
    'params': Color(0xFF383A42),
    'meta': Color(0xFF4078F2),
  };
  static const _dark = {
    'keyword': Color(0xFFC678DD),
    'built_in': Color(0xFFE6C07B),
    'type': Color(0xFFE6C07B),
    'literal': Color(0xFF56B6C2),
    'number': Color(0xFFD19A66),
    'string': Color(0xFF98C379),
    'comment': Color(0xFF7F848E),
    'title': Color(0xFF61AFEF),
    'function': Color(0xFF61AFEF),
    'params': Color(0xFFABB2BF),
    'meta': Color(0xFF61AFEF),
  };

  @override
  TextSpan format(String source) {
    final base = TextStyle(fontFamily: 'Consolas', fontSize: fontSize * 0.92, color: dark ? const Color(0xFFABB2BF) : const Color(0xFF383A42));
    try {
      final result = highlight.parse(source, autoDetection: true);
      return TextSpan(style: base, children: _spans(result.nodes ?? const []));
    } catch (_) {
      return TextSpan(text: source, style: base);
    }
  }

  List<TextSpan> _spans(List<Node> nodes) {
    final theme = dark ? _dark : _light;
    return [
      for (final n in nodes)
        if (n.value != null)
          TextSpan(text: n.value, style: n.className == null ? null : TextStyle(color: theme[n.className]))
        else
          TextSpan(style: n.className == null ? null : TextStyle(color: theme[n.className]), children: _spans(n.children ?? const [])),
    ];
  }
}

/// Fully rendered Markdown for a text box that isn't being edited.
class RenderedMarkdown extends StatelessWidget {
  final TextEl el;
  const RenderedMarkdown({super.key, required this.el});

  @override
  Widget build(BuildContext context) {
    final color = Color(el.color);
    final dark = color.computeLuminance() > 0.6;
    final base = TextStyle(fontSize: el.fontSize, color: color, height: 1.35, fontFamily: 'Segoe UI');
    final sheet = MarkdownStyleSheet(
      p: base,
      h1: base.copyWith(fontSize: el.fontSize * 1.7, fontWeight: FontWeight.w700),
      h2: base.copyWith(fontSize: el.fontSize * 1.4, fontWeight: FontWeight.w700),
      h3: base.copyWith(fontSize: el.fontSize * 1.2, fontWeight: FontWeight.w700),
      h4: base.copyWith(fontWeight: FontWeight.w700),
      h5: base.copyWith(fontWeight: FontWeight.w700),
      h6: base.copyWith(fontWeight: FontWeight.w700),
      listBullet: base,
      code: base.copyWith(fontFamily: 'Consolas', backgroundColor: const Color(0x14808080)),
      codeblockDecoration: BoxDecoration(color: const Color(0x10808080), borderRadius: BorderRadius.circular(6)),
      codeblockPadding: const EdgeInsets.all(8),
      blockquote: base.copyWith(fontStyle: FontStyle.italic),
      blockquoteDecoration: BoxDecoration(border: Border(left: BorderSide(color: color.withValues(alpha: 0.4), width: 3))),
      blockquotePadding: const EdgeInsets.only(left: 10),
      tableBody: base,
      tableHead: base.copyWith(fontWeight: FontWeight.w700),
      tableBorder: TableBorder.all(color: color.withValues(alpha: 0.3)),
      tableCellsPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      a: base.copyWith(color: const Color(0xFF3B6FE0), decoration: TextDecoration.underline),
      checkbox: base,
      pPadding: const EdgeInsets.only(bottom: 2),
    );
    return Padding(
      padding: const EdgeInsets.all(4),
      child: MarkdownBody(
        data: el.markdown,
        styleSheet: sheet,
        softLineBreak: true,
        extensionSet: md.ExtensionSet.gitHubFlavored,
        inlineSyntaxes: [_MathSyntax()],
        builders: {'math': _MathBuilder()},
        syntaxHighlighter: _Highlighter(el.fontSize, dark),
        checkboxBuilder: (v) => Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Icon(v ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded, size: el.fontSize * 1.15, color: color),
        ),
      ),
    );
  }
}

/// Inline editor for a text box: live-styled Markdown plus a mini formatting bar.
class TextBoxEditor extends StatefulWidget {
  final TextEl el;
  final void Function(String markdown, double height) onChanged;
  final VoidCallback onDone;
  const TextBoxEditor({super.key, required this.el, required this.onChanged, required this.onDone});

  @override
  State<TextBoxEditor> createState() => _TextBoxEditorState();
}

class _TextBoxEditorState extends State<TextBoxEditor> {
  late final MarkdownEditingController _c = MarkdownEditingController(text: widget.el.markdown);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) widget.onDone();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _changed(String v) => widget.onChanged(v, measureMarkdownHeight(v, widget.el.rect.width, widget.el.fontSize));

  @override
  Widget build(BuildContext context) {
    final color = Color(widget.el.color);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.primary, width: 1.2),
        borderRadius: BorderRadius.circular(4),
      ),
      padding: const EdgeInsets.all(3),
      child: TextField(
        controller: _c,
        focusNode: _focus,
        maxLines: null,
        style: TextStyle(fontSize: widget.el.fontSize, color: color, height: 1.35, fontFamily: 'Segoe UI'),
        cursorColor: Theme.of(context).colorScheme.primary,
        decoration: const InputDecoration(
          isCollapsed: true,
          border: InputBorder.none,
          filled: false,
          contentPadding: EdgeInsets.zero,
          hintText: 'Type — Markdown works: # heading, **bold**, - list, \$x^2\$',
        ),
        onChanged: _changed,
      ),
    );
  }
}

/// Wraps text-box content laid out at document size, scaled to screen size.
class ScaledBox extends StatelessWidget {
  final double width, height, scale;
  final Widget child;
  const ScaledBox({super.key, required this.width, required this.height, required this.scale, required this.child});
  @override
  Widget build(BuildContext context) => Transform.scale(
        scale: scale,
        alignment: Alignment.topLeft,
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: width,
          maxWidth: width,
          minHeight: 0,
          maxHeight: double.infinity,
          child: SizedBox(width: width, child: child),
        ),
      );
}
