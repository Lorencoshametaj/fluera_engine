/// 📊 Cell value types for the tabular engine.
///
/// [CellValue] is a sealed class hierarchy representing every possible
/// content type a spreadsheet cell can hold. This enables exhaustive
/// pattern matching and type-safe evaluation.

// ---------------------------------------------------------------------------
// CellError
// ---------------------------------------------------------------------------

/// Error categories for cell evaluation failures.
enum CellError {
  /// Division by zero (e.g. `=1/0`).
  divisionByZero,

  /// Reference to a cell that doesn't exist or is out of range.
  invalidRef,

  /// Circular reference detected in the dependency graph.
  circularRef,

  /// Operand types are incompatible (e.g. `="hello" + 1`).
  typeMismatch,

  /// Unknown function or named reference.
  nameError,

  /// A value cannot be converted to the expected type.
  valueError,

  /// Formula syntax error.
  parseError,

  /// Reference error — index out of bounds in INDEX/VLOOKUP (#REF!).
  referenceError,

  /// Value not available — lookup found no match (#N/A).
  notAvailable,
}

// ---------------------------------------------------------------------------
// CellValue — sealed hierarchy
// ---------------------------------------------------------------------------

/// Base type for all cell values.
///
/// Use Dart pattern matching to handle each variant:
/// ```dart
/// switch (cell.value) {
///   case NumberValue(:final value): print(value);
///   case TextValue(:final value): print(value);
///   case FormulaValue(:final expression): evaluate(expression);
///   case EmptyValue(): break;
///   case BoolValue(:final value): print(value);
///   case ErrorValue(:final error): handleError(error);
///   case ComplexValue(:final metadata): processMetadata(metadata);
/// }
/// ```
sealed class CellValue {
  const CellValue();

  /// JSON serialization tag.
  String get typeTag;

  /// Serialize the value to JSON.
  Map<String, dynamic> toJson();

  /// Deserialize from JSON.
  factory CellValue.fromJson(Map<String, dynamic> json) {
    final tag = json['type'] as String;
    return switch (tag) {
      'empty' => const EmptyValue(),
      'number' => NumberValue(json['value'] as num),
      'text' => TextValue(json['value'] as String),
      'bool' => BoolValue(json['value'] as bool),
      'formula' => FormulaValue(json['expression'] as String),
      'error' => ErrorValue(CellError.values.byName(json['error'] as String)),
      'complex' => ComplexValue(
        json['metadata'] as Map<String, dynamic>? ?? const {},
      ),
      _ => throw ArgumentError('Unknown CellValue type: $tag'),
    };
  }

  /// Extract a numeric value, or `null` if not numeric.
  double? get asNumber => switch (this) {
    NumberValue(:final value) => value.toDouble(),
    BoolValue(:final value) => value ? 1.0 : 0.0,
    _ => null,
  };

  /// Human-readable display string.
  String get displayString;
}

// ---------------------------------------------------------------------------
// Concrete variants
// ---------------------------------------------------------------------------

/// An empty cell (no content).
class EmptyValue extends CellValue {
  const EmptyValue();

  @override
  String get typeTag => 'empty';

  @override
  Map<String, dynamic> toJson() => {'type': 'empty'};

  @override
  String get displayString => '';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is EmptyValue;

  @override
  int get hashCode => 0;

  @override
  String toString() => 'EmptyValue()';
}

/// A numeric value (integer or floating-point stored as double).
class NumberValue extends CellValue {
  final num value;

  const NumberValue(this.value);

  @override
  String get typeTag => 'number';

  @override
  Map<String, dynamic> toJson() => {'type': 'number', 'value': value};

  @override
  String get displayString {
    if (value is int || value == value.toInt()) {
      return value.toInt().toString();
    }
    return value.toString();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is NumberValue && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'NumberValue($value)';
}

/// A text/string value.
class TextValue extends CellValue {
  final String value;

  const TextValue(this.value);

  @override
  String get typeTag => 'text';

  @override
  Map<String, dynamic> toJson() => {'type': 'text', 'value': value};

  @override
  String get displayString => value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is TextValue && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'TextValue("$value")';
}

/// A boolean value.
class BoolValue extends CellValue {
  final bool value;

  const BoolValue(this.value);

  @override
  String get typeTag => 'bool';

  @override
  Map<String, dynamic> toJson() => {'type': 'bool', 'value': value};

  @override
  String get displayString => value ? 'TRUE' : 'FALSE';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is BoolValue && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'BoolValue($value)';
}

/// A formula (raw expression string, e.g. `SUM(A1:A10)`).
///
/// The leading `=` is **not** stored — it is stripped during input.
class FormulaValue extends CellValue {
  final String expression;

  const FormulaValue(this.expression);

  @override
  String get typeTag => 'formula';

  @override
  Map<String, dynamic> toJson() => {
    'type': 'formula',
    'expression': expression,
  };

  @override
  String get displayString => '=$expression';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FormulaValue && expression == other.expression;

  @override
  int get hashCode => expression.hashCode;

  @override
  String toString() => 'FormulaValue($expression)';
}

/// An error value resulting from evaluation failure.
class ErrorValue extends CellValue {
  final CellError error;

  /// Optional human-readable detail message.
  final String? message;

  const ErrorValue(this.error, {this.message});

  @override
  String get typeTag => 'error';

  @override
  Map<String, dynamic> toJson() => {
    'type': 'error',
    'error': error.name,
    if (message != null) 'message': message,
  };

  @override
  String get displayString => switch (error) {
    CellError.divisionByZero => '#DIV/0!',
    CellError.invalidRef => '#REF!',
    CellError.circularRef => '#CIRC!',
    CellError.typeMismatch => '#TYPE!',
    CellError.nameError => '#NAME?',
    CellError.valueError => '#VALUE!',
    CellError.parseError => '#PARSE!',
    CellError.referenceError => '#REF!',
    CellError.notAvailable => '#N/A',
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ErrorValue && error == other.error;

  @override
  int get hashCode => error.hashCode;

  @override
  String toString() => 'ErrorValue(${error.name})';
}

/// A complex/opaque value carrying arbitrary structured metadata.
///
/// Used for domain-specific data: financial transactions, budget items,
/// astronomical measurements, or references to other engine objects.
class ComplexValue extends CellValue {
  final Map<String, dynamic> metadata;

  const ComplexValue(this.metadata);

  @override
  String get typeTag => 'complex';

  @override
  Map<String, dynamic> toJson() => {'type': 'complex', 'metadata': metadata};

  @override
  String get displayString {
    if (metadata.containsKey('label')) return metadata['label'] as String;
    return '{...}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ComplexValue && _mapEquals(metadata, other.metadata);

  @override
  int get hashCode =>
      Object.hashAll(metadata.entries.map((e) => Object.hash(e.key, e.value)));

  @override
  String toString() => 'ComplexValue($metadata)';

  static bool _mapEquals(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || a[key] != b[key]) return false;
    }
    return true;
  }
}
