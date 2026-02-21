/// 📊 FEATURE FLAG SERVICE — Boolean/string/double flags with A/B testing.
///
/// Manages feature flags with percentage-based rollout, per-user overrides,
/// and reactive change streams for UI.
///
/// ```dart
/// final flags = FeatureFlagService();
/// flags.define(FeatureFlag.boolean('dark_mode', defaultValue: true));
/// flags.setOverride('dark_mode', false, scope: 'user:u-123');
/// if (flags.isEnabled('dark_mode')) { ... }
/// ```
library;

import 'dart:async';
import 'dart:math' as math;

// =============================================================================
// FLAG TYPE
// =============================================================================

/// Feature flag value type.
enum FlagType { boolean, string, number }

// =============================================================================
// FEATURE FLAG
// =============================================================================

/// A single feature flag definition.
class FeatureFlag {
  /// Flag identifier.
  final String id;

  /// Human-readable description.
  final String description;

  /// Flag type.
  final FlagType type;

  /// Default value.
  final dynamic defaultValue;

  /// Rollout percentage (0–100). Only applies for boolean flags.
  final double rolloutPercent;

  /// Whether this flag is archived (soft-deleted).
  final bool archived;

  /// Tags for organization.
  final List<String> tags;

  const FeatureFlag({
    required this.id,
    required this.type,
    this.description = '',
    this.defaultValue,
    this.rolloutPercent = 100.0,
    this.archived = false,
    this.tags = const [],
  });

  /// Create a boolean flag.
  factory FeatureFlag.boolean(
    String id, {
    bool defaultValue = false,
    String description = '',
    double rolloutPercent = 100.0,
    List<String> tags = const [],
  }) => FeatureFlag(
    id: id,
    type: FlagType.boolean,
    defaultValue: defaultValue,
    description: description,
    rolloutPercent: rolloutPercent,
    tags: tags,
  );

  /// Create a string flag.
  factory FeatureFlag.string(
    String id, {
    String defaultValue = '',
    String description = '',
    List<String> tags = const [],
  }) => FeatureFlag(
    id: id,
    type: FlagType.string,
    defaultValue: defaultValue,
    description: description,
    tags: tags,
  );

  /// Create a number flag.
  factory FeatureFlag.number(
    String id, {
    double defaultValue = 0.0,
    String description = '',
    List<String> tags = const [],
  }) => FeatureFlag(
    id: id,
    type: FlagType.number,
    defaultValue: defaultValue,
    description: description,
    tags: tags,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'description': description,
    'defaultValue': defaultValue,
    'rolloutPercent': rolloutPercent,
    'archived': archived,
    'tags': tags,
  };

  factory FeatureFlag.fromJson(Map<String, dynamic> json) => FeatureFlag(
    id: json['id'] as String,
    type: FlagType.values.firstWhere((v) => v.name == json['type']),
    description: json['description'] as String? ?? '',
    defaultValue: json['defaultValue'],
    rolloutPercent: (json['rolloutPercent'] as num?)?.toDouble() ?? 100.0,
    archived: json['archived'] as bool? ?? false,
    tags: (json['tags'] as List?)?.cast<String>() ?? [],
  );

  @override
  String toString() => 'FeatureFlag($id, ${type.name}, default=$defaultValue)';
}

// =============================================================================
// FLAG OVERRIDE
// =============================================================================

/// An override rule for a specific scope.
class FlagOverride {
  /// Flag ID this override applies to.
  final String flagId;

  /// Override value.
  final dynamic value;

  /// Scope (e.g. "user:u-123", "env:staging", "session:s-abc").
  final String scope;

  /// Priority (higher = takes precedence).
  final int priority;

  const FlagOverride({
    required this.flagId,
    required this.value,
    required this.scope,
    this.priority = 0,
  });

  Map<String, dynamic> toJson() => {
    'flagId': flagId,
    'value': value,
    'scope': scope,
    'priority': priority,
  };
}

// =============================================================================
// FEATURE FLAG SERVICE
// =============================================================================

/// Central feature flag management service.
class FeatureFlagService {
  final Map<String, FeatureFlag> _flags = {};
  final List<FlagOverride> _overrides = [];
  final _changeController = StreamController<String>.broadcast();
  final math.Random _random;

  /// Optional active scopes for evaluation (e.g. ["user:u-123", "env:prod"]).
  List<String> activeScopes;

  FeatureFlagService({List<String>? activeScopes, math.Random? random})
    : activeScopes = activeScopes ?? [],
      _random = random ?? math.Random();

  /// Stream of flag ID changes (fires when value changes).
  Stream<String> get changes => _changeController.stream;

  /// Define a feature flag.
  void define(FeatureFlag flag) {
    _flags[flag.id] = flag;
    _changeController.add(flag.id);
  }

  /// Remove a flag definition.
  void remove(String flagId) {
    _flags.remove(flagId);
    _overrides.removeWhere((o) => o.flagId == flagId);
    _changeController.add(flagId);
  }

  /// Get a flag definition.
  FeatureFlag? getFlag(String flagId) => _flags[flagId];

  /// All defined flags.
  List<FeatureFlag> get allFlags => _flags.values.toList();

  /// Set an override for a flag.
  void setOverride(
    String flagId,
    dynamic value, {
    String scope = 'global',
    int priority = 0,
  }) {
    // Remove existing override for same flag+scope
    _overrides.removeWhere((o) => o.flagId == flagId && o.scope == scope);
    _overrides.add(
      FlagOverride(
        flagId: flagId,
        value: value,
        scope: scope,
        priority: priority,
      ),
    );
    _changeController.add(flagId);
  }

  /// Remove an override.
  void removeOverride(String flagId, {String scope = 'global'}) {
    _overrides.removeWhere((o) => o.flagId == flagId && o.scope == scope);
    _changeController.add(flagId);
  }

  /// Evaluate a flag value (considers overrides, rollout, and active scopes).
  dynamic evaluate(String flagId) {
    final flag = _flags[flagId];
    if (flag == null) return null;

    // Check overrides (highest priority first, matching active scopes)
    final matchingOverrides =
        _overrides
            .where(
              (o) =>
                  o.flagId == flagId &&
                  (o.scope == 'global' || activeScopes.contains(o.scope)),
            )
            .toList()
          ..sort((a, b) => b.priority.compareTo(a.priority));

    if (matchingOverrides.isNotEmpty) {
      return matchingOverrides.first.value;
    }

    // For boolean flags, apply rollout percentage
    if (flag.type == FlagType.boolean && flag.rolloutPercent < 100.0) {
      // Deterministic rollout based on flag ID hash
      final roll = _random.nextDouble() * 100.0;
      return roll < flag.rolloutPercent;
    }

    return flag.defaultValue;
  }

  /// Convenience: check if a boolean flag is enabled.
  bool isEnabled(String flagId) {
    final value = evaluate(flagId);
    return value == true;
  }

  /// Convenience: get a string flag value.
  String stringValue(String flagId, {String defaultValue = ''}) {
    final value = evaluate(flagId);
    return value is String ? value : defaultValue;
  }

  /// Convenience: get a number flag value.
  double numberValue(String flagId, {double defaultValue = 0.0}) {
    final value = evaluate(flagId);
    return value is num ? value.toDouble() : defaultValue;
  }

  /// Export all flags and overrides as JSON.
  Map<String, dynamic> toJson() => {
    'flags': {for (final f in _flags.values) f.id: f.toJson()},
    'overrides': _overrides.map((o) => o.toJson()).toList(),
  };

  /// Import flags from JSON config.
  void loadFromJson(Map<String, dynamic> json) {
    final flags = json['flags'] as Map<String, dynamic>? ?? {};
    for (final entry in flags.entries) {
      define(FeatureFlag.fromJson(entry.value as Map<String, dynamic>));
    }
    final overrides = json['overrides'] as List<dynamic>? ?? [];
    for (final o in overrides) {
      final map = o as Map<String, dynamic>;
      setOverride(
        map['flagId'] as String,
        map['value'],
        scope: map['scope'] as String? ?? 'global',
        priority: map['priority'] as int? ?? 0,
      );
    }
  }

  /// Reset all flags and overrides.
  void reset() {
    _flags.clear();
    _overrides.clear();
  }

  /// Dispose the change stream.
  void dispose() {
    _changeController.close();
  }
}
