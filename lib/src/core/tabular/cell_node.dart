import 'dart:ui';

import 'cell_value.dart';

/// 📊 Formatting options for a spreadsheet cell.
///
/// All fields are optional — only non-null values override defaults.
class CellFormat {
  /// Number format pattern (e.g. `#,##0.00`, `0%`, `yyyy-MM-dd`).
  final String? numberFormat;

  /// Horizontal alignment.
  final CellAlignment? horizontalAlign;

  /// Vertical alignment.
  final CellVerticalAlignment? verticalAlign;

  /// Font size override (logical pixels).
  final double? fontSize;

  /// Text color override.
  final Color? textColor;

  /// Background color override.
  final Color? backgroundColor;

  /// Whether text is bold.
  final bool? bold;

  /// Whether text is italic.
  final bool? italic;

  const CellFormat({
    this.numberFormat,
    this.horizontalAlign,
    this.verticalAlign,
    this.fontSize,
    this.textColor,
    this.backgroundColor,
    this.bold,
    this.italic,
  });

  CellFormat copyWith({
    String? numberFormat,
    CellAlignment? horizontalAlign,
    CellVerticalAlignment? verticalAlign,
    double? fontSize,
    Color? textColor,
    Color? backgroundColor,
    bool? bold,
    bool? italic,
  }) => CellFormat(
    numberFormat: numberFormat ?? this.numberFormat,
    horizontalAlign: horizontalAlign ?? this.horizontalAlign,
    verticalAlign: verticalAlign ?? this.verticalAlign,
    fontSize: fontSize ?? this.fontSize,
    textColor: textColor ?? this.textColor,
    backgroundColor: backgroundColor ?? this.backgroundColor,
    bold: bold ?? this.bold,
    italic: italic ?? this.italic,
  );

  Map<String, dynamic> toJson() => {
    if (numberFormat != null) 'numberFormat': numberFormat,
    if (horizontalAlign != null) 'hAlign': horizontalAlign!.name,
    if (verticalAlign != null) 'vAlign': verticalAlign!.name,
    if (fontSize != null) 'fontSize': fontSize,
    if (textColor != null) 'textColor': textColor!.toARGB32(),
    if (backgroundColor != null) 'bgColor': backgroundColor!.toARGB32(),
    if (bold != null) 'bold': bold,
    if (italic != null) 'italic': italic,
  };

  factory CellFormat.fromJson(Map<String, dynamic> json) => CellFormat(
    numberFormat: json['numberFormat'] as String?,
    horizontalAlign:
        json['hAlign'] != null
            ? CellAlignment.values.byName(json['hAlign'] as String)
            : null,
    verticalAlign:
        json['vAlign'] != null
            ? CellVerticalAlignment.values.byName(json['vAlign'] as String)
            : null,
    fontSize: (json['fontSize'] as num?)?.toDouble(),
    textColor:
        json['textColor'] != null ? Color(json['textColor'] as int) : null,
    backgroundColor:
        json['bgColor'] != null ? Color(json['bgColor'] as int) : null,
    bold: json['bold'] as bool?,
    italic: json['italic'] as bool?,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CellFormat &&
          numberFormat == other.numberFormat &&
          horizontalAlign == other.horizontalAlign &&
          verticalAlign == other.verticalAlign &&
          fontSize == other.fontSize &&
          textColor == other.textColor &&
          backgroundColor == other.backgroundColor &&
          bold == other.bold &&
          italic == other.italic;

  @override
  int get hashCode => Object.hash(
    numberFormat,
    horizontalAlign,
    verticalAlign,
    fontSize,
    textColor,
    backgroundColor,
    bold,
    italic,
  );
}

/// Horizontal alignment options.
enum CellAlignment { left, center, right }

/// Vertical alignment options.
enum CellVerticalAlignment { top, middle, bottom }

// ---------------------------------------------------------------------------
// CellNode
// ---------------------------------------------------------------------------

/// A stateful container for a single spreadsheet cell.
///
/// Holds the raw [value], the cached [computedValue] (for formulas),
/// optional [format], and extensible [metadata].
///
/// ```dart
/// final cell = CellNode(value: NumberValue(42));
/// cell.format = CellFormat(bold: true, textColor: Colors.red);
/// ```
class CellNode {
  /// The raw input value (what the user typed / set).
  CellValue value;

  /// The evaluated result for formula cells.
  ///
  /// For non-formula cells this mirrors [value]. Set by the evaluator.
  CellValue? computedValue;

  /// Display formatting overrides.
  CellFormat? format;

  /// Extensible metadata (financial data, domain tags, etc.).
  Map<String, dynamic>? metadata;

  CellNode({
    required this.value,
    this.computedValue,
    this.format,
    this.metadata,
  });

  /// The value to display: [computedValue] if available, otherwise [value].
  CellValue get displayValue => computedValue ?? value;

  /// Whether this cell contains a formula.
  bool get isFormula => value is FormulaValue;

  // -------------------------------------------------------------------------
  // Serialization
  // -------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
    'value': value.toJson(),
    if (format != null) 'format': format!.toJson(),
    if (metadata != null && metadata!.isNotEmpty) 'metadata': metadata,
    // computedValue is NOT serialized — it is re-evaluated on load.
  };

  factory CellNode.fromJson(Map<String, dynamic> json) => CellNode(
    value: CellValue.fromJson(json['value'] as Map<String, dynamic>),
    format:
        json['format'] != null
            ? CellFormat.fromJson(json['format'] as Map<String, dynamic>)
            : null,
    metadata:
        json['metadata'] != null
            ? Map<String, dynamic>.from(json['metadata'] as Map)
            : null,
  );

  /// Create a deep copy of this cell node.
  CellNode clone() => CellNode(
    value: value,
    computedValue: computedValue,
    format: format,
    metadata: metadata != null ? Map<String, dynamic>.from(metadata!) : null,
  );

  @override
  String toString() => 'CellNode(${value.displayString})';
}
