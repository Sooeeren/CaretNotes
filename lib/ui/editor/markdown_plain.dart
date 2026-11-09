import 'package:flutter/painting.dart';

/// Approximate rendering of Markdown as styled text, for thumbnails, image export
/// and as a fallback. Headings get bigger, **bold** / *italic* / `code` are styled,
/// list and quote markers are kept readable, syntax characters are hidden.
/// [maxHeading] caps heading sizes (text on lines must fit one line).
TextSpan markdownToPlainSpan(String md, double fontSize, Color color, {double? maxHeading}) {
  final base = TextStyle(fontSize: fontSize, color: color, height: 1.35, fontFamily: 'Segoe UI');
  final children = <InlineSpan>[];
  final lines = md.split('\n');
  var inCode = false;
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i];
    final nl = i < lines.length - 1 ? '\n' : '';
    if (line.trimLeft().startsWith('```')) {
      inCode = !inCode;
      continue;
    }
    if (inCode) {
      children.add(TextSpan(text: '$line$nl', style: base.copyWith(fontFamily: 'Consolas', fontSize: fontSize * 0.92)));
      continue;
    }
    var style = base;
    final h = RegExp(r'^(#{1,6})\s+').firstMatch(line);
    if (h != null) {
      final level = h.group(1)!.length;
      final size = fontSize * (level == 1 ? 1.7 : level == 2 ? 1.4 : 1.2);
      style = base.copyWith(fontSize: maxHeading != null && size > maxHeading ? maxHeading : size, fontWeight: FontWeight.w700);
      line = line.substring(h.end);
    }
    line = line
        .replaceFirstMapped(RegExp(r'^(\s*)[-*+]\s+\[( |x|X)\]\s+'), (m) => '${m[1]}${m[2] == ' ' ? '☐' : '☑'} ')
        .replaceFirstMapped(RegExp(r'^(\s*)[-*+]\s+'), (m) => '${m[1]}• ')
        .replaceFirstMapped(RegExp(r'^>\s?'), (m) => '│ ');
    children.addAll(_inline(line, style));
    if (nl.isNotEmpty) children.add(const TextSpan(text: '\n'));
  }
  return TextSpan(style: base, children: children);
}

final _inlineRe = RegExp(r'(\*\*[^*]+\*\*|__[^_]+__|\*[^*]+\*|_[^_]+_|`[^`]+`|~~[^~]+~~|\$[^$]+\$|\[[^\]]+\]\([^)]+\))');

List<InlineSpan> _inline(String text, TextStyle style) {
  final out = <InlineSpan>[];
  var pos = 0;
  for (final m in _inlineRe.allMatches(text)) {
    if (m.start > pos) out.add(TextSpan(text: text.substring(pos, m.start), style: style));
    final s = m.group(0)!;
    if (s.startsWith('**') || s.startsWith('__')) {
      out.add(TextSpan(text: s.substring(2, s.length - 2), style: style.copyWith(fontWeight: FontWeight.w700)));
    } else if (s.startsWith('~~')) {
      out.add(TextSpan(text: s.substring(2, s.length - 2), style: style.copyWith(decoration: TextDecoration.lineThrough)));
    } else if (s.startsWith('`')) {
      out.add(TextSpan(text: s.substring(1, s.length - 1), style: style.copyWith(fontFamily: 'Consolas')));
    } else if (s.startsWith(r'$')) {
      out.add(TextSpan(text: s.substring(1, s.length - 1), style: style.copyWith(fontStyle: FontStyle.italic)));
    } else if (s.startsWith('[')) {
      final label = s.substring(1, s.indexOf(']'));
      out.add(TextSpan(text: label, style: style.copyWith(decoration: TextDecoration.underline)));
    } else {
      out.add(TextSpan(text: s.substring(1, s.length - 1), style: style.copyWith(fontStyle: FontStyle.italic)));
    }
    pos = m.end;
  }
  if (pos < text.length) out.add(TextSpan(text: text.substring(pos), style: style));
  return out;
}
