import '../model/elements.dart';

/// Paint order for a page: images marked "behind ink" first, then highlighters,
/// then everything else in its stored order. Highlighters never cover writing.
List<Element> paintOrder(List<Element> els) => [
      for (final e in els) if (e is ImageEl && e.behindInk) e,
      for (final e in els) if (e is StrokeEl && e.isHighlighter) e,
      for (final e in els)
        if (!(e is ImageEl && e.behindInk) && !(e is StrokeEl && e.isHighlighter)) e,
    ];
