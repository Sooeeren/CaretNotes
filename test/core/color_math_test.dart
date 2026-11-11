import 'package:caret_notes/core/color_math.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('HSV and ARGB convert both ways', () {
    expect(hsvToArgb(0, 1, 1), 0xFFFF0000);
    expect(hsvToArgb(120, 1, 1), 0xFF00FF00);
    expect(hsvToArgb(240, 1, 1), 0xFF0000FF);
    expect(hsvToArgb(0, 0, 1), 0xFFFFFFFF);
    expect(hsvToArgb(0, 0, 0), 0xFF000000);
    for (final c in [0xFFD9772B, 0xFF1B2A6B, 0xFF7CB342, 0xFF424242]) {
      final (h, s, v) = argbToHsv(c);
      expect(hsvToArgb(h, s, v), c);
    }
  });

  test('hex codes parse with or without # and print as #RRGGBB', () {
    expect(parseHexColor('#D9772B'), 0xFFD9772B);
    expect(parseHexColor('d9772b'), 0xFFD9772B);
    expect(parseHexColor('#FFF'), 0xFFFFFFFF);
    expect(parseHexColor('nope'), isNull);
    expect(hexOf(0xFFD9772B), '#D9772B');
  });

  test('color pages: your colors first, then the palette, in groups', () {
    final pages = colorPages([1, 2, 3], [3, 4, 5, 6, 7], perPage: 4);
    expect(pages, [
      [1, 2, 3, 4],
      [5, 6, 7],
    ]);
    expect(colorPages(const [], const [], perPage: 4), [<int>[]]);
  });
}
