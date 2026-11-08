import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:highlight/highlight.dart' show highlight, Node, Result;
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

enum MdAction { heading, bold, italic, bullet, checkbox, code, math }

/// Applies a formatting-bar action to the text: wraps the selection, or prefixes the line.
TextEditingValue applyMarkdown(TextEditingValue v, MdAction a) {
  final text = v.text;
  final sel = v.selection.isValid ? v.selection : TextSelection.collapsed(offset: text.length);
  String? prefix;
  switch (a) {
    case MdAction.heading:
      prefix = '# ';
    case MdAction.bullet:
      prefix = '- ';
    case MdAction.checkbox:
      prefix = '- [ ] ';
    default:
      break;
  }
  if (prefix != null) {
    final lineStart = sel.start == 0 ? 0 : text.lastIndexOf('\n', sel.start - 1) + 1;
    final nt = text.replaceRange(lineStart, lineStart, prefix);
    return TextEditingValue(
      text: nt,
      selection: TextSelection(baseOffset: sel.baseOffset + prefix.length, extentOffset: sel.extentOffset + prefix.length),
    );
  }
  final mark = switch (a) {
    MdAction.bold => '**',
    MdAction.italic => '*',
    MdAction.code => '`',
    _ => r'$',
  };
  final inner = text.substring(sel.start, sel.end);
  final nt = text.replaceRange(sel.start, sel.end, '$mark$inner$mark');
  return TextEditingValue(
    text: nt,
    selection: TextSelection(baseOffset: sel.start + mark.length, extentOffset: sel.start + mark.length + inner.length),
  );
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

  static const _languages = [
    'python', 'java', 'cpp', 'c', 'javascript', 'typescript', 'dart', 'kotlin', 'cs', 'go', 'rust',
    'bash', 'sql', 'json', 'matlab', 'r', 'latex', 'xml', 'css', 'haskell', 'scala', 'php',
  ];

  @override
  TextSpan format(String source) {
    final base = TextStyle(fontFamily: 'Consolas', fontSize: fontSize * 0.92, color: dark ? const Color(0xFFABB2BF) : const Color(0xFF383A42));
    // Auto-detect among common languages (full auto-detection runs grammars that log errors).
    Result? best;
    for (final lang in _languages) {
      try {
        final r = highlight.parse(source, language: lang);
        if (best == null || (r.relevance ?? 0) > (best.relevance ?? 0)) best = r;
      } catch (_) {}
    }
    if (best == null || (best.relevance ?? 0) < 2) return TextSpan(text: source, style: base);
    return TextSpan(style: base, children: _spans(best.nodes ?? const []));
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

  void _apply(MdAction a) {
    _c.value = applyMarkdown(_c.value, a);
    _changed(_c.text);
    _focus.requestFocus();
  }

  Widget _bar(BuildContext context) {
    Widget b(MdAction a, Widget icon, String tip) => Tooltip(
          message: tip,
          child: InkWell(
            canRequestFocus: false,
            borderRadius: BorderRadius.circular(6),
            onTap: () => _apply(a),
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3), child: icon),
          ),
        );
    const s = 15.0;
    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(8),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        b(MdAction.heading, const Text('H', style: TextStyle(fontWeight: FontWeight.w800, fontSize: s)), 'Heading'),
        b(MdAction.bold, const Icon(Icons.format_bold_rounded, size: s + 3), 'Bold'),
        b(MdAction.italic, const Icon(Icons.format_italic_rounded, size: s + 3), 'Italic'),
        b(MdAction.bullet, const Icon(Icons.format_list_bulleted_rounded, size: s + 3), 'List'),
        b(MdAction.checkbox, const Icon(Icons.check_box_outlined, size: s + 3), 'Checkbox'),
        b(MdAction.code, const Icon(Icons.code_rounded, size: s + 3), 'Code'),
        b(MdAction.math, const Text('∑', style: TextStyle(fontSize: s)), 'Math (LaTeX)'),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = Color(widget.el.color);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      _bar(context),
      const SizedBox(height: 4),
      _field(context, color),
    ]);
  }

  Widget _field(BuildContext context, Color color) {
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
  Widget build(BuildContext context) => SizedBox(
        width: width * scale,
        child: FittedBox(
          fit: BoxFit.fitWidth,
          alignment: Alignment.topLeft,
          child: SizedBox(width: width, child: child),
        ),
      );
}
