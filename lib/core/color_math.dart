/// Color helpers for the color wheel and the pen panel (pure Dart, ARGB ints).
library;

/// Hue 0–360, saturation and value 0–1 → opaque ARGB.
int hsvToArgb(double h, double s, double v) {
  h = h % 360;
  if (h < 0) h += 360;
  final c = v * s;
  final x = c * (1 - ((h / 60) % 2 - 1).abs());
  final m = v - c;
  final (r, g, b) = switch (h ~/ 60) {
    0 => (c, x, 0.0),
    1 => (x, c, 0.0),
    2 => (0.0, c, x),
    3 => (0.0, x, c),
    4 => (x, 0.0, c),
    _ => (c, 0.0, x),
  };
  int ch(double f) => ((f + m) * 255).round().clamp(0, 255);
  return 0xFF000000 | ch(r) << 16 | ch(g) << 8 | ch(b);
}

/// ARGB → (hue 0–360, saturation 0–1, value 0–1). Alpha is ignored.
(double, double, double) argbToHsv(int argb) {
  final r = (argb >> 16 & 0xFF) / 255, g = (argb >> 8 & 0xFF) / 255, b = (argb & 0xFF) / 255;
  final max = [r, g, b].reduce((a, b) => a > b ? a : b);
  final min = [r, g, b].reduce((a, b) => a < b ? a : b);
  final d = max - min;
  double h;
  if (d == 0) {
    h = 0;
  } else if (max == r) {
    h = 60 * (((g - b) / d) % 6);
  } else if (max == g) {
    h = 60 * ((b - r) / d + 2);
  } else {
    h = 60 * ((r - g) / d + 4);
  }
  if (h < 0) h += 360;
  return (h, max == 0 ? 0 : d / max, max);
}

/// "#RRGGBB", "RRGGBB" or "#RGB" → opaque ARGB; null if it isn't a color.
int? parseHexColor(String s) {
  var h = s.trim();
  if (h.startsWith('#')) h = h.substring(1);
  if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
  if (h.length != 6 || !RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(h)) return null;
  return 0xFF000000 | int.parse(h, radix: 16);
}

/// Opaque ARGB → "#RRGGBB".
String hexOf(int argb) => '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// The user's own colors first, then the palette (without repeats), split into pages.
List<List<int>> colorPages(List<int> mine, List<int> palette, {required int perPage}) {
  final all = {...mine, ...palette}.toList();
  if (all.isEmpty) return [<int>[]];
  return [for (var i = 0; i < all.length; i += perPage) all.sublist(i, (i + perPage).clamp(0, all.length))];
}
