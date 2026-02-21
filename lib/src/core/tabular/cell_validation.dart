/// 📊 Cell data validation rules for the tabular engine.
///
/// Provides constraints on cell input to enforce data integrity.
/// Each validation rule specifies the allowed type, range, or set
/// of values for a cell.
///
/// ```dart
/// final rule = CellValidation(
///   type: CellValidationType.number,
///   min: 1,
///   max: 100,
///   errorTitle: 'Out of range',
///   errorMessage: 'Please enter a number between 1 and 100',
/// );
/// rule.validate(NumberValue(50));  // true
/// rule.validate(NumberValue(200)); // false
/// ```

import 'cell_value.dart';

// ---------------------------------------------------------------------------
// Validation type
// ---------------------------------------------------------------------------

/// The type of data validation constraint.
enum CellValidationType {
  /// Only numeric values (int or double).
  number,

  /// Only integer values (no decimals).
  integer,

  /// Only values from a predefined list.
  list,

  /// Only date serial numbers within a range.
  date,

  /// Text with constrained length.
  textLength,

  /// Custom formula-based validation (expression must return TRUE).
  custom,

  /// Accept any value (no constraint).
  any,
}

/// How errors are handled when validation fails.
enum ValidationErrorStyle {
  /// Reject the input entirely (strict).
  stop,

  /// Show a warning but allow the input.
  warning,

  /// Show an informational message but allow the input.
  information,
}

// ---------------------------------------------------------------------------
// CellValidation
// ---------------------------------------------------------------------------

/// A data validation rule for one or more cells.
///
/// Supports numeric range constraints, picklist validation,
/// text length limits, and custom formula-based rules.
class CellValidation {
  /// The type of validation constraint.
  final CellValidationType type;

  /// Minimum allowed value (for [number], [integer], [date], [textLength]).
  final num? min;

  /// Maximum allowed value (for [number], [integer], [date], [textLength]).
  final num? max;

  /// Allowed values (for [list] type).
  final List<String>? allowedValues;

  /// Custom validation formula expression (for [custom] type).
  ///
  /// The formula should evaluate to TRUE for valid input.
  final String? customFormula;

  /// Error dialog title shown on validation failure.
  final String? errorTitle;

  /// Error dialog message shown on validation failure.
  final String? errorMessage;

  /// How to handle validation failures.
  final ValidationErrorStyle errorStyle;

  /// Whether to ignore blank cells (skip validation if empty).
  final bool ignoreBlank;

  /// Whether to show an input prompt before editing.
  final bool showInputMessage;

  /// Input prompt title.
  final String? inputTitle;

  /// Input prompt message.
  final String? inputMessage;

  const CellValidation({
    this.type = CellValidationType.any,
    this.min,
    this.max,
    this.allowedValues,
    this.customFormula,
    this.errorTitle,
    this.errorMessage,
    this.errorStyle = ValidationErrorStyle.stop,
    this.ignoreBlank = true,
    this.showInputMessage = false,
    this.inputTitle,
    this.inputMessage,
  });

  // -------------------------------------------------------------------------
  // Validation logic
  // -------------------------------------------------------------------------

  /// Validate a cell value against this rule.
  ///
  /// Returns `true` if the value is valid, `false` otherwise.
  /// Note: [custom] validation always returns `true` here — it must
  /// be evaluated externally by the formula evaluator.
  bool validate(CellValue value) {
    // Ignore blank cells if configured.
    if (ignoreBlank && value is EmptyValue) return true;

    switch (type) {
      case CellValidationType.any:
        return true;

      case CellValidationType.number:
        return _validateNumeric(value, allowDecimal: true);

      case CellValidationType.integer:
        return _validateNumeric(value, allowDecimal: false);

      case CellValidationType.list:
        return _validateList(value);

      case CellValidationType.date:
        return _validateNumeric(value, allowDecimal: false);

      case CellValidationType.textLength:
        return _validateTextLength(value);

      case CellValidationType.custom:
        // Custom formulas must be evaluated externally.
        return true;
    }
  }

  bool _validateNumeric(CellValue value, {required bool allowDecimal}) {
    final n = value.asNumber;
    if (n == null) return false;

    if (!allowDecimal && n != n.toInt()) return false;

    if (min != null && n < min!) return false;
    if (max != null && n > max!) return false;

    return true;
  }

  bool _validateList(CellValue value) {
    if (allowedValues == null || allowedValues!.isEmpty) return true;
    final display = value.displayString;
    return allowedValues!.contains(display);
  }

  bool _validateTextLength(CellValue value) {
    final text = value.displayString;
    final length = text.length;

    if (min != null && length < min!.toInt()) return false;
    if (max != null && length > max!.toInt()) return false;

    return true;
  }

  /// Get the error message to display on validation failure.
  String get effectiveErrorMessage {
    if (errorMessage != null) return errorMessage!;
    return switch (type) {
      CellValidationType.number =>
        'Value must be a number${_rangeDescription()}.',
      CellValidationType.integer =>
        'Value must be an integer${_rangeDescription()}.',
      CellValidationType.list =>
        'Value must be one of: ${allowedValues?.join(', ') ?? '(none)'}.',
      CellValidationType.textLength =>
        'Text length${_rangeDescription(' characters')}.',
      CellValidationType.date => 'Value must be a valid date.',
      CellValidationType.custom => 'Value does not satisfy the custom rule.',
      CellValidationType.any => '',
    };
  }

  String _rangeDescription([String suffix = '']) {
    if (min != null && max != null) return ' between $min and $max$suffix';
    if (min != null) return ' ≥ $min$suffix';
    if (max != null) return ' ≤ $max$suffix';
    return '';
  }

  // -------------------------------------------------------------------------
  // Serialization
  // -------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
    'type': type.name,
    if (min != null) 'min': min,
    if (max != null) 'max': max,
    if (allowedValues != null) 'allowedValues': allowedValues,
    if (customFormula != null) 'customFormula': customFormula,
    if (errorTitle != null) 'errorTitle': errorTitle,
    if (errorMessage != null) 'errorMessage': errorMessage,
    if (errorStyle != ValidationErrorStyle.stop) 'errorStyle': errorStyle.name,
    if (!ignoreBlank) 'ignoreBlank': false,
    if (showInputMessage) 'showInputMessage': true,
    if (inputTitle != null) 'inputTitle': inputTitle,
    if (inputMessage != null) 'inputMessage': inputMessage,
  };

  factory CellValidation.fromJson(Map<String, dynamic> json) => CellValidation(
    type: CellValidationType.values.byName(json['type'] as String),
    min: json['min'] as num?,
    max: json['max'] as num?,
    allowedValues: (json['allowedValues'] as List<dynamic>?)?.cast<String>(),
    customFormula: json['customFormula'] as String?,
    errorTitle: json['errorTitle'] as String?,
    errorMessage: json['errorMessage'] as String?,
    errorStyle:
        json['errorStyle'] != null
            ? ValidationErrorStyle.values.byName(json['errorStyle'] as String)
            : ValidationErrorStyle.stop,
    ignoreBlank: json['ignoreBlank'] as bool? ?? true,
    showInputMessage: json['showInputMessage'] as bool? ?? false,
    inputTitle: json['inputTitle'] as String?,
    inputMessage: json['inputMessage'] as String?,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CellValidation &&
          type == other.type &&
          min == other.min &&
          max == other.max &&
          errorStyle == other.errorStyle;

  @override
  int get hashCode => Object.hash(type, min, max, errorStyle);

  @override
  String toString() =>
      'CellValidation(${type.name}'
      '${min != null ? ', min=$min' : ''}'
      '${max != null ? ', max=$max' : ''})';
}
