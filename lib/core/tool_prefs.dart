import 'model/elements.dart';

enum SelectMode { lasso, box }

/// What the text tool does on tap: type on the paper's lines, or place a free text box.
enum TextMode { lines, box }

/// The drawing tools' options, remembered across notes and restarts.
class ToolPrefs {
  final ToolKind penKind;
  final int penColor;
  final double penWidth;
  final int hlColor;
  final double hlWidth;

  /// Partial erases only the part of a stroke under the eraser; off erases whole strokes.
  final bool eraserPartial;
  final double eraserSize;
  final SelectMode selectMode;
  final TextMode textMode;

  // Slider ranges in the tool panels; saved values are clamped to them.
  static const penWidthRange = (0.6, 12.0);
  static const hlWidthRange = (4.0, 32.0);
  static const eraserSizeRange = (2.0, 40.0);

  const ToolPrefs({
    this.penKind = ToolKind.pen,
    this.penColor = 0xFF1B2A6B,
    this.penWidth = 2.4,
    this.hlColor = 0xFFFFE14D,
    this.hlWidth = 14,
    this.eraserPartial = true,
    this.eraserSize = 8,
    this.selectMode = SelectMode.box,
    this.textMode = TextMode.lines,
  });

  Map<String, dynamic> toJson() => {
        'penKind': penKind.name,
        'penColor': penColor,
        'penWidth': penWidth,
        'hlColor': hlColor,
        'hlWidth': hlWidth,
        'eraserPartial': eraserPartial,
        'eraserSize': eraserSize,
        'selectMode': selectMode.name,
        'textMode': textMode.name,
      };

  factory ToolPrefs.fromJson(Map<String, dynamic> j) {
    const d = ToolPrefs();
    T e<T extends Enum>(List<T> values, Object? v, T def) => values.asNameMap()[v] ?? def;
    double n(Object? v, double def, (double, double) range) =>
        (v is num ? v.toDouble() : def).clamp(range.$1, range.$2);
    int c(Object? v, int def) => v is int ? v : def;
    // The highlighter has its own tool; the pen's type is one of the others.
    final kind = e(ToolKind.values, j['penKind'], d.penKind);
    return ToolPrefs(
      penKind: kind == ToolKind.highlighter ? d.penKind : kind,
      penColor: c(j['penColor'], d.penColor),
      penWidth: n(j['penWidth'], d.penWidth, penWidthRange),
      hlColor: c(j['hlColor'], d.hlColor),
      hlWidth: n(j['hlWidth'], d.hlWidth, hlWidthRange),
      eraserPartial: j['eraserPartial'] is bool ? j['eraserPartial'] as bool : d.eraserPartial,
      eraserSize: n(j['eraserSize'], d.eraserSize, eraserSizeRange),
      selectMode: e(SelectMode.values, j['selectMode'], d.selectMode),
      textMode: e(TextMode.values, j['textMode'], d.textMode),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ToolPrefs &&
      other.penKind == penKind &&
      other.penColor == penColor &&
      other.penWidth == penWidth &&
      other.hlColor == hlColor &&
      other.hlWidth == hlWidth &&
      other.eraserPartial == eraserPartial &&
      other.eraserSize == eraserSize &&
      other.selectMode == selectMode &&
      other.textMode == textMode;

  @override
  int get hashCode =>
      Object.hash(penKind, penColor, penWidth, hlColor, hlWidth, eraserPartial, eraserSize, selectMode, textMode);
}
