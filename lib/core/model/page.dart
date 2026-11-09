import '../ids.dart';
import 'elements.dart';

/// Paper kinds. Cornell and staff were added in format 2.
enum TemplateKind { blank, lined, grid, dots, cornell, staff }

class Template {
  final TemplateKind kind;

  /// Line/grid spacing in points.
  final double spacing;
  final int paperColor;
  final int lineColor;

  const Template({
    this.kind = TemplateKind.lined,
    this.spacing = 22,
    this.paperColor = 0xFFFFFFFF,
    this.lineColor = 0xFFD6E0F0,
  });

  static const darkPaper = 0xFF22252B;
  static const darkLine = 0xFF3A4150;

  Template copyWith({TemplateKind? kind, double? spacing, int? paperColor, int? lineColor}) => Template(
        kind: kind ?? this.kind,
        spacing: spacing ?? this.spacing,
        paperColor: paperColor ?? this.paperColor,
        lineColor: lineColor ?? this.lineColor,
      );

  Map<String, dynamic> toJson() => {'kind': kind.name, 'spacing': spacing, 'paper': paperColor, 'line': lineColor};
  factory Template.fromJson(Map<String, dynamic> j) => Template(
        kind: TemplateKind.values.asNameMap()[j['kind']] ?? TemplateKind.lined,
        spacing: (j['spacing'] as num).toDouble(),
        paperColor: j['paper'] as int,
        lineColor: j['line'] as int,
      );
}

/// Reference to a page of an imported PDF stored as a note asset.
class PdfRef {
  final String assetId;
  final int pageIndex;
  const PdfRef(this.assetId, this.pageIndex);
  Map<String, dynamic> toJson() => {'asset': assetId, 'page': pageIndex};
  factory PdfRef.fromJson(Map<String, dynamic> j) => PdfRef(j['asset'] as String, j['page'] as int);
}

class NotePage {
  final String id;
  final double width;

  /// For canvas notes height is ignored (unbounded).
  final double height;
  final Template? templateOverride;
  final PdfRef? pdf;

  /// Paint order: list order (later = on top), highlighters drawn under pens by the renderer.
  final List<Element> elements;

  const NotePage({
    required this.id,
    required this.width,
    required this.height,
    this.templateOverride,
    this.pdf,
    this.elements = const [],
  });

  factory NotePage.blank(double w, double h) => NotePage(id: newId(), width: w, height: h);

  NotePage copyWith({
    String? id,
    double? width,
    double? height,
    Template? templateOverride,
    bool clearTemplateOverride = false,
    List<Element>? elements,
  }) =>
      NotePage(
        id: id ?? this.id,
        width: width ?? this.width,
        height: height ?? this.height,
        templateOverride: clearTemplateOverride ? null : (templateOverride ?? this.templateOverride),
        pdf: pdf,
        elements: elements ?? this.elements,
      );

  Element? find(String id) {
    for (final e in elements) {
      if (e.id == id) return e;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'w': width,
        'h': height,
        if (templateOverride != null) 'template': templateOverride!.toJson(),
        if (pdf != null) 'pdf': pdf!.toJson(),
        'elements': [for (final e in elements) e.toJson()],
      };

  factory NotePage.fromJson(Map<String, dynamic> j) => NotePage(
        id: j['id'] as String,
        width: (j['w'] as num).toDouble(),
        height: (j['h'] as num).toDouble(),
        templateOverride: j['template'] == null ? null : Template.fromJson(j['template'] as Map<String, dynamic>),
        pdf: j['pdf'] == null ? null : PdfRef.fromJson(j['pdf'] as Map<String, dynamic>),
        elements: [for (final e in j['elements'] as List) Element.fromJson(e as Map<String, dynamic>)],
      );
}
