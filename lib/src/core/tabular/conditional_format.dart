import 'dart:ui';

import 'cell_address.dart';
import 'cell_node.dart';
import 'cell_value.dart';

/// 📊 Conditional formatting engine for the tabular engine.
///
/// Applies dynamic cell formatting based on rules that evaluate cell
/// values. Rules are checked in priority order (lower number = higher
/// priority). Multiple rules can apply to the same cell — their formats
/// are merged, with higher-priority formats taking precedence.
///
/// ```dart
/// final engine = ConditionalFormatEngine();
/// engine.addRule(ConditionalFormatRule(
///   appliesTo: CellRange.fromLabel('A1:A100'),
///   condition: FormatCondition.lessThan,
///   threshold: 0,
///   format: CellFormat(textColor: Color(0xFFFF0000), bold: true),
///   priority: 1,
/// ));
///
/// final fmt = engine.getEffectiveFormat(CellAddress(0, 5), NumberValue(-3));
/// // → CellFormat(textColor: red, bold: true)
/// ```

// ---------------------------------------------------------------------------
// Condition types
// ---------------------------------------------------------------------------

/// The type of conditional comparison.
enum FormatCondition {
  /// Value > threshold.
  greaterThan,

  /// Value >= threshold.
  greaterThanOrEqual,

  /// Value < threshold.
  lessThan,

  /// Value <= threshold.
  lessThanOrEqual,

  /// Value == threshold.
  equal,

  /// Value != threshold.
  notEqual,

  /// threshold <= value <= thresholdMax.
  between,

  /// value < threshold OR value > thresholdMax.
  notBetween,

  /// Cell text contains threshold (as string).
  textContains,

  /// Cell text starts with threshold (as string).
  textStartsWith,

  /// Cell text ends with threshold (as string).
  textEndsWith,

  /// Cell is empty.
  isBlank,

  /// Cell is not empty.
  isNotBlank,

  /// Cell contains an error.
  isError,

  /// Custom formula (always matches — format via formula).
  custom,
}

// ---------------------------------------------------------------------------
// ConditionalFormatRule
// ---------------------------------------------------------------------------

/// A single conditional formatting rule.
///
/// Defines which cells it applies to, what condition to check, and
/// what format to apply when the condition is met.
class ConditionalFormatRule {
  /// The cell range this rule applies to.
  final CellRange appliesTo;

  /// The condition to evaluate.
  final FormatCondition condition;

  /// Primary threshold value for comparison conditions.
  ///
  /// For numeric conditions: the comparison value.
  /// For text conditions: the search string.
  final dynamic threshold;

  /// Secondary threshold for [between] and [notBetween] conditions.
  final num? thresholdMax;

  /// The format to apply when the condition is met.
  final CellFormat format;

  /// Rule priority (lower = higher priority, evaluated first).
  final int priority;

  /// If true, stop evaluating subsequent rules when this rule matches.
  final bool stopIfTrue;

  const ConditionalFormatRule({
    required this.appliesTo,
    required this.condition,
    this.threshold,
    this.thresholdMax,
    required this.format,
    this.priority = 0,
    this.stopIfTrue = false,
  });

  /// Evaluate whether a cell value matches this rule's condition.
  bool matches(CellValue value) {
    switch (condition) {
      case FormatCondition.isBlank:
        return value is EmptyValue;

      case FormatCondition.isNotBlank:
        return value is! EmptyValue;

      case FormatCondition.isError:
        return value is ErrorValue;

      case FormatCondition.custom:
        return true; // Custom rules always match (formatting is conditional).

      case FormatCondition.textContains:
        return value.displayString.contains(threshold?.toString() ?? '');

      case FormatCondition.textStartsWith:
        return value.displayString.startsWith(threshold?.toString() ?? '');

      case FormatCondition.textEndsWith:
        return value.displayString.endsWith(threshold?.toString() ?? '');

      case FormatCondition.greaterThan:
      case FormatCondition.greaterThanOrEqual:
      case FormatCondition.lessThan:
      case FormatCondition.lessThanOrEqual:
      case FormatCondition.equal:
      case FormatCondition.notEqual:
      case FormatCondition.between:
      case FormatCondition.notBetween:
        return _matchesNumeric(value);
    }
  }

  bool _matchesNumeric(CellValue value) {
    final n = value.asNumber;
    if (n == null) return false;

    final t = (threshold is num) ? (threshold as num).toDouble() : null;
    if (t == null &&
        condition != FormatCondition.between &&
        condition != FormatCondition.notBetween) {
      return false;
    }

    return switch (condition) {
      FormatCondition.greaterThan => n > t!,
      FormatCondition.greaterThanOrEqual => n >= t!,
      FormatCondition.lessThan => n < t!,
      FormatCondition.lessThanOrEqual => n <= t!,
      FormatCondition.equal => n == t!,
      FormatCondition.notEqual => n != t!,
      FormatCondition.between =>
        t != null && thresholdMax != null && n >= t && n <= thresholdMax!,
      FormatCondition.notBetween =>
        t != null && thresholdMax != null && (n < t || n > thresholdMax!),
      _ => false,
    };
  }

  // -------------------------------------------------------------------------
  // Serialization
  // -------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
    'appliesTo': appliesTo.toJson(),
    'condition': condition.name,
    if (threshold != null) 'threshold': threshold,
    if (thresholdMax != null) 'thresholdMax': thresholdMax,
    'format': format.toJson(),
    'priority': priority,
    if (stopIfTrue) 'stopIfTrue': true,
  };

  factory ConditionalFormatRule.fromJson(Map<String, dynamic> json) =>
      ConditionalFormatRule(
        appliesTo: CellRange.fromJson(
          json['appliesTo'] as Map<String, dynamic>,
        ),
        condition: FormatCondition.values.byName(json['condition'] as String),
        threshold: json['threshold'],
        thresholdMax: json['thresholdMax'] as num?,
        format: CellFormat.fromJson(json['format'] as Map<String, dynamic>),
        priority: json['priority'] as int? ?? 0,
        stopIfTrue: json['stopIfTrue'] as bool? ?? false,
      );

  @override
  String toString() =>
      'ConditionalFormatRule(${condition.name}, priority=$priority, '
      'range=${appliesTo.label})';
}

// ---------------------------------------------------------------------------
// ConditionalFormatEngine
// ---------------------------------------------------------------------------

/// Engine that evaluates conditional formatting rules for a spreadsheet.
///
/// Rules are maintained in priority order. When querying the effective
/// format for a cell, all matching rules are evaluated and their formats
/// are merged (higher priority overrides lower priority).
class ConditionalFormatEngine {
  final List<ConditionalFormatRule> _rules = [];

  /// All current rules, sorted by priority.
  List<ConditionalFormatRule> get rules => List.unmodifiable(_rules);

  /// Number of rules.
  int get ruleCount => _rules.length;

  // -------------------------------------------------------------------------
  // Rule management
  // -------------------------------------------------------------------------

  /// Add a conditional formatting rule.
  ///
  /// Rules are automatically sorted by priority (ascending).
  void addRule(ConditionalFormatRule rule) {
    _rules.add(rule);
    _rules.sort((a, b) => a.priority.compareTo(b.priority));
  }

  /// Remove a specific rule. Returns true if found.
  bool removeRule(ConditionalFormatRule rule) => _rules.remove(rule);

  /// Remove all rules that apply to the given range.
  void removeRulesForRange(CellRange range) {
    _rules.removeWhere((r) => r.appliesTo == range);
  }

  /// Remove all rules.
  void clearRules() => _rules.clear();

  // -------------------------------------------------------------------------
  // Format resolution
  // -------------------------------------------------------------------------

  /// Get the effective conditional format for a cell.
  ///
  /// Evaluates all rules that apply to [addr] against [value],
  /// in priority order. Formats from matching rules are merged,
  /// with higher-priority (lower number) formats taking precedence.
  ///
  /// Returns `null` if no rules match.
  CellFormat? getEffectiveFormat(CellAddress addr, CellValue value) {
    CellFormat? result;

    for (final rule in _rules) {
      if (!rule.appliesTo.contains(addr)) continue;
      if (!rule.matches(value)) continue;

      // Merge this rule's format into the result.
      if (result == null) {
        result = rule.format;
      } else {
        result = _mergeFormats(result, rule.format);
      }

      if (rule.stopIfTrue) break;
    }

    return result;
  }

  /// Get all matching rules for a cell (for debugging/inspection).
  List<ConditionalFormatRule> getMatchingRules(
    CellAddress addr,
    CellValue value,
  ) {
    final matches = <ConditionalFormatRule>[];
    for (final rule in _rules) {
      if (!rule.appliesTo.contains(addr) || !rule.matches(value)) continue;
      matches.add(rule);
      if (rule.stopIfTrue) break;
    }
    return matches;
  }

  /// Merge two CellFormats. [base] is the previously-accumulated result
  /// (higher priority). [overlay] is the new rule's format (lower priority).
  /// Higher-priority (base) properties take precedence.
  CellFormat _mergeFormats(CellFormat base, CellFormat overlay) {
    // overlay.mergeWith(base) → base properties override overlay
    return overlay.mergeWith(base);
  }

  // -------------------------------------------------------------------------
  // Serialization
  // -------------------------------------------------------------------------

  List<Map<String, dynamic>> toJson() => _rules.map((r) => r.toJson()).toList();

  void loadFromJson(List<dynamic> json) {
    _rules.clear();
    for (final item in json) {
      _rules.add(ConditionalFormatRule.fromJson(item as Map<String, dynamic>));
    }
    _rules.sort((a, b) => a.priority.compareTo(b.priority));
  }
}
