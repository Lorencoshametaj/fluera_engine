/// 🎯 PREFERRED VALUES — Constrained value sets for design properties.
///
/// Provides suggested/enforced values for spacing, sizing, colors, etc.
/// Supports snap-to-nearest for interactive editing.
///
/// ```dart
/// final registry = PreferredValueRegistry();
/// registry.register(PreferredValueSet(
///   id: 'spacing',
///   name: 'Spacing Scale',
///   property: 'spacing',
///   values: [
///     PreferredValue(label: 'xs', value: 4),
///     PreferredValue(label: 'sm', value: 8),
///     PreferredValue(label: 'md', value: 16),
///     PreferredValue(label: 'lg', value: 24),
///     PreferredValue(label: 'xl', value: 32),
///   ],
/// ));
/// final nearest = registry.snapToNearest('spacing', 15.0); // → 16
/// ```
library;

// =============================================================================
// PREFERRED VALUE
// =============================================================================

/// A single suggested value with a human-readable label.
class PreferredValue {
  /// Display label (e.g., "sm", "medium", "primary").
  final String label;

  /// The actual numeric value.
  final double value;

  /// Optional description.
  final String description;

  const PreferredValue({
    required this.label,
    required this.value,
    this.description = '',
  });

  Map<String, dynamic> toJson() => {
    'label': label,
    'value': value,
    if (description.isNotEmpty) 'description': description,
  };

  factory PreferredValue.fromJson(Map<String, dynamic> json) => PreferredValue(
    label: json['label'] as String,
    value: (json['value'] as num).toDouble(),
    description: json['description'] as String? ?? '',
  );
}

// =============================================================================
// PREFERRED VALUE SET
// =============================================================================

/// A named set of preferred values for a specific property.
class PreferredValueSet {
  /// Unique set ID.
  final String id;

  /// Display name (e.g., "Spacing Scale").
  final String name;

  /// Property this set applies to (e.g., "spacing", "borderRadius", "fontSize").
  final String property;

  /// Ordered list of preferred values.
  final List<PreferredValue> values;

  /// Whether to enforce these values (strict) or just suggest them (loose).
  final bool isStrict;

  const PreferredValueSet({
    required this.id,
    required this.name,
    required this.property,
    required this.values,
    this.isStrict = false,
  });

  /// Find the nearest preferred value to [input].
  PreferredValue? snapToNearest(double input) {
    if (values.isEmpty) return null;
    PreferredValue? best;
    double bestDist = double.infinity;
    for (final v in values) {
      final dist = (v.value - input).abs();
      if (dist < bestDist) {
        bestDist = dist;
        best = v;
      }
    }
    return best;
  }

  /// Check if a value matches any preferred value exactly.
  bool contains(double value) => values.any((v) => v.value == value);

  /// Get the label for a value (or null if not preferred).
  String? labelFor(double value) {
    for (final v in values) {
      if (v.value == value) return v.label;
    }
    return null;
  }

  /// Get the next preferred value after [current] (or wrap to first).
  PreferredValue? nudgeUp(double current) {
    if (values.isEmpty) return null;
    for (final v in values) {
      if (v.value > current) return v;
    }
    return values.last;
  }

  /// Get the previous preferred value before [current] (or wrap to last).
  PreferredValue? nudgeDown(double current) {
    if (values.isEmpty) return null;
    for (int i = values.length - 1; i >= 0; i--) {
      if (values[i].value < current) return values[i];
    }
    return values.first;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'property': property,
    'values': values.map((v) => v.toJson()).toList(),
    'isStrict': isStrict,
  };

  factory PreferredValueSet.fromJson(Map<String, dynamic> json) =>
      PreferredValueSet(
        id: json['id'] as String,
        name: json['name'] as String,
        property: json['property'] as String,
        values:
            (json['values'] as List<dynamic>)
                .map((v) => PreferredValue.fromJson(v as Map<String, dynamic>))
                .toList(),
        isStrict: json['isStrict'] as bool? ?? false,
      );
}

// =============================================================================
// PREFERRED VALUE REGISTRY
// =============================================================================

/// Global registry of preferred value sets for all properties.
class PreferredValueRegistry {
  final Map<String, PreferredValueSet> _sets = {};

  /// All registered sets (unmodifiable).
  Map<String, PreferredValueSet> get sets => Map.unmodifiable(_sets);

  /// Register a preferred value set.
  void register(PreferredValueSet set) => _sets[set.property] = set;

  /// Remove a preferred value set by property.
  bool unregister(String property) => _sets.remove(property) != null;

  /// Get the set for a property.
  PreferredValueSet? forProperty(String property) => _sets[property];

  /// Snap to nearest preferred value for a property.
  double snapToNearest(String property, double input) {
    final set = _sets[property];
    if (set == null) return input;
    return set.snapToNearest(input)?.value ?? input;
  }

  /// Nudge to next preferred value for a property.
  double nudgeUp(String property, double current) {
    final set = _sets[property];
    return set?.nudgeUp(current)?.value ?? current;
  }

  /// Nudge to previous preferred value for a property.
  double nudgeDown(String property, double current) {
    final set = _sets[property];
    return set?.nudgeDown(current)?.value ?? current;
  }

  /// Check if a value is preferred for a property.
  bool isPreferred(String property, double value) {
    final set = _sets[property];
    return set?.contains(value) ?? false;
  }

  Map<String, dynamic> toJson() => {
    'sets': _sets.values.map((s) => s.toJson()).toList(),
  };

  static PreferredValueRegistry fromJson(Map<String, dynamic> json) {
    final reg = PreferredValueRegistry();
    for (final s in (json['sets'] as List<dynamic>? ?? [])) {
      final set = PreferredValueSet.fromJson(s as Map<String, dynamic>);
      reg._sets[set.property] = set;
    }
    return reg;
  }
}
