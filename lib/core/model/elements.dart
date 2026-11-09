import '../geometry.dart';

enum ToolKind { pen, fineliner, pencil, highlighter }

/// One sampled pen point; [p] is pressure 0..1.
class InkPoint {
  final double x, y, p;
  const InkPoint(this.x, this.y, this.p);
  Vec2 get v => Vec2(x, y);

  @override
  bool operator ==(Object other) => other is InkPoint && other.x == x && other.y == y && other.p == p;
  @override
  int get hashCode => Object.hash(x, y, p);
}

double _r(double v) => (v * 100).roundToDouble() / 100;

/// Any object placed on a page.
sealed class Element {
  const Element();
  String get id;
  RectD bounds();
  Element transformed(Affine t);
  Element withId(String id);
  Map<String, dynamic> toJson();

  static Element fromJson(Map<String, dynamic> j) {
    switch (j['type']) {
      case 'stroke':
        return StrokeEl.fromJson(j);
      case 'text':
        return TextEl.fromJson(j);
      case 'image':
        return ImageEl.fromJson(j);
    }
    throw FormatException('unknown element type ${j['type']}');
  }
}

class StrokeEl extends Element {
  @override
  final String id;
  final List<InkPoint> points;
  final ToolKind tool;
  final int color; // ARGB
  final double width;

  const StrokeEl({required this.id, required this.points, required this.tool, required this.color, required this.width});

  bool get isHighlighter => tool == ToolKind.highlighter;

  @override
  RectD bounds() => RectD.fromPoints(points.map((p) => p.v)).inflate(width / 2);

  @override
  StrokeEl transformed(Affine t) {
    final s = t.scaleFactor;
    return StrokeEl(
      id: id,
      points: [for (final p in points) _pt(t.apply(p.v), p.p)],
      tool: tool,
      color: color,
      width: width * s,
    );
  }

  static InkPoint _pt(Vec2 v, double p) => InkPoint(v.x, v.y, p);

  StrokeEl copyWith({List<InkPoint>? points, int? color, double? width, String? id}) =>
      StrokeEl(id: id ?? this.id, points: points ?? this.points, tool: tool, color: color ?? this.color, width: width ?? this.width);

  @override
  StrokeEl withId(String id) => copyWith(id: id);

  @override
  Map<String, dynamic> toJson() => {
        'type': 'stroke',
        'id': id,
        'tool': tool.name,
        'color': color,
        'width': width,
        // flat [x, y, p, x, y, p, ...] keeps files compact
        'pts': [for (final p in points) ...[_r(p.x), _r(p.y), (p.p * 1000).roundToDouble() / 1000]],
      };

  factory StrokeEl.fromJson(Map<String, dynamic> j) {
    final flat = (j['pts'] as List).cast<num>();
    return StrokeEl(
      id: j['id'] as String,
      tool: ToolKind.values.byName(j['tool'] as String),
      color: j['color'] as int,
      width: (j['width'] as num).toDouble(),
      points: [
        for (var i = 0; i + 2 < flat.length; i += 3) InkPoint(flat[i].toDouble(), flat[i + 1].toDouble(), flat[i + 2].toDouble()),
      ],
    );
  }
}

class TextEl extends Element {
  @override
  final String id;
  final RectD rect;
  final String markdown;
  final double fontSize;
  final int color;

  /// Set for text typed on the paper's lines: every text line is exactly this tall
  /// and sits on a ruled line. Null for a free text box.
  final double? lineHeight;

  const TextEl({
    required this.id,
    required this.rect,
    required this.markdown,
    this.fontSize = 14,
    this.color = 0xFF222222,
    this.lineHeight,
  });

  bool get ruled => lineHeight != null;

  @override
  RectD bounds() => rect;

  @override
  TextEl transformed(Affine t) {
    final tl = t.apply(rect.topLeft);
    final s = t.scaleFactor;
    final lh = lineHeight;
    if (lh != null && (s - 1).abs() < 1e-6) {
      // Moved, not resized: stay on the lines.
      final top = snapToLines(tl.y, lh);
      return copyWith(rect: RectD(tl.x, top, tl.x + rect.width, top + rect.height));
    }
    return TextEl(
      id: id,
      rect: RectD(tl.x, tl.y, tl.x + rect.width * s, tl.y + rect.height * s),
      markdown: markdown,
      fontSize: fontSize * s,
      color: color,
      lineHeight: lh == null ? null : lh * s,
    );
  }

  TextEl copyWith({RectD? rect, String? markdown, double? fontSize, int? color, String? id}) => TextEl(
        id: id ?? this.id,
        rect: rect ?? this.rect,
        markdown: markdown ?? this.markdown,
        fontSize: fontSize ?? this.fontSize,
        color: color ?? this.color,
        lineHeight: lineHeight,
      );

  @override
  TextEl withId(String id) => copyWith(id: id);

  @override
  Map<String, dynamic> toJson() => {
        'type': 'text',
        'id': id,
        'rect': rect.toJson(),
        'md': markdown,
        'size': fontSize,
        'color': color,
        if (lineHeight != null) 'lh': lineHeight,
      };

  factory TextEl.fromJson(Map<String, dynamic> j) => TextEl(
        id: j['id'] as String,
        rect: RectD.fromJson(j['rect'] as List),
        markdown: j['md'] as String,
        fontSize: (j['size'] as num).toDouble(),
        color: j['color'] as int,
        lineHeight: (j['lh'] as num?)?.toDouble(),
      );
}

class ImageEl extends Element {
  @override
  final String id;

  /// Unrotated placement rect; [rotation] (radians) is applied about its center.
  final RectD rect;
  final double rotation;
  final String assetId;

  /// Visible part of the source image, normalized 0..1.
  final RectD crop;
  final bool behindInk;

  const ImageEl({
    required this.id,
    required this.rect,
    this.rotation = 0,
    required this.assetId,
    this.crop = const RectD(0, 0, 1, 1),
    this.behindInk = false,
  });

  List<Vec2> get corners {
    final t = Affine.about(rect.center, Affine.rotate(rotation));
    return [for (final c in rect.corners) t.apply(c)];
  }

  @override
  RectD bounds() => RectD.fromPoints(corners);

  @override
  ImageEl transformed(Affine t) {
    final c = t.apply(rect.center);
    final s = t.scaleFactor;
    final w = rect.width * s, h = rect.height * s;
    return copyWith(rect: RectD(c.x - w / 2, c.y - h / 2, c.x + w / 2, c.y + h / 2), rotation: rotation + t.rotation);
  }

  ImageEl copyWith({RectD? rect, double? rotation, RectD? crop, bool? behindInk, String? id}) => ImageEl(
        id: id ?? this.id,
        rect: rect ?? this.rect,
        rotation: rotation ?? this.rotation,
        assetId: assetId,
        crop: crop ?? this.crop,
        behindInk: behindInk ?? this.behindInk,
      );

  @override
  ImageEl withId(String id) => copyWith(id: id);

  @override
  Map<String, dynamic> toJson() => {
        'type': 'image',
        'id': id,
        'rect': rect.toJson(),
        'rot': rotation,
        'asset': assetId,
        'crop': crop.toJson(),
        'behind': behindInk,
      };

  factory ImageEl.fromJson(Map<String, dynamic> j) => ImageEl(
        id: j['id'] as String,
        rect: RectD.fromJson(j['rect'] as List),
        rotation: (j['rot'] as num).toDouble(),
        assetId: j['asset'] as String,
        crop: RectD.fromJson(j['crop'] as List),
        behindInk: j['behind'] as bool? ?? false,
      );
}
