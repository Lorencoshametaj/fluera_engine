// ============================================================================
// 🧪 ExperimentDefinition — typed model for an A/B experiment.
//
// Defines the contract of a single experiment: hypothesis, variants with
// traffic allocation, primary metric, lifecycle dates. Used by:
//   - ActiveExperiments registry (loads + serves to runtime)
//   - VariantAssigner (reads traffic split → deterministic bucket)
//   - VariantOverridesProvider (applies variant cell overrides)
//   - Telemetry event emission (tags events with variant id)
//
// Pure data + validation. No I/O, no async.
// ============================================================================

import 'package:meta/meta.dart';

/// One variant within an experiment. Traffic percent sum across all
/// variants of an experiment must equal 100.
@immutable
class VariantConfig {
  /// Stable variant identifier (e.g. 'control', 'variant_a', 'b').
  /// Used as the value emitted in telemetry `variants_assigned` map.
  final String id;

  /// Human-readable label for dashboards. Optional.
  final String label;

  /// Traffic share 0-100. Sum of all variants in an experiment = 100.
  final int trafficPercent;

  const VariantConfig({
    required this.id,
    required this.label,
    required this.trafficPercent,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'trafficPercent': trafficPercent,
      };

  factory VariantConfig.fromJson(Map<String, dynamic> json) => VariantConfig(
        id: json['id'] as String,
        label: json['label'] as String? ?? json['id'] as String,
        trafficPercent: (json['trafficPercent'] as num).toInt(),
      );
}

/// A pre-registered A/B experiment definition. Loaded once at app
/// startup by `ActiveExperiments.load`.
@immutable
class ExperimentDefinition {
  /// Stable experiment id used as the key in:
  ///   - telemetry `variants_assigned` map
  ///   - YAML config file
  ///   - VariantOverridesProvider lookup
  /// Conventionally `<feature>_<topic>_<version>`, e.g.
  /// `socratic_anchor_register_v1`.
  final String id;

  /// Display name for dashboards.
  final String name;

  /// Pre-registered hypothesis. The reason the experiment exists.
  /// Required to avoid post-hoc cherry-picking — write it BEFORE data.
  final String hypothesis;

  /// Variants with traffic distribution. Must contain ≥1 variant whose
  /// `id == 'control'` (the baseline against which others are compared).
  final List<VariantConfig> variants;

  /// Primary metric name (e.g. `uncertain_reflections_per_session`).
  /// Decision rule operates on this metric.
  final String primaryMetric;

  /// When the experiment went live. Telemetry events before this date
  /// are excluded from analysis.
  final DateTime startedAt;

  /// When the experiment should auto-stop. Past this date the registry
  /// treats it as inactive (all users → 'control'). Null = no auto-stop.
  final DateTime? endsAt;

  /// Kill switch. When false, the experiment is effectively disabled
  /// (all users → 'control', telemetry continues tagging for cleanup).
  final bool active;

  const ExperimentDefinition({
    required this.id,
    required this.name,
    required this.hypothesis,
    required this.variants,
    required this.primaryMetric,
    required this.startedAt,
    this.endsAt,
    this.active = true,
  });

  /// Validate the definition. Returns a non-empty list of violations or
  /// empty when valid. Callers should refuse to load invalid experiments.
  List<String> validate() {
    final issues = <String>[];
    if (id.isEmpty) issues.add('id is empty');
    if (hypothesis.isEmpty) issues.add('hypothesis is empty');
    if (primaryMetric.isEmpty) issues.add('primaryMetric is empty');
    if (variants.isEmpty) {
      issues.add('variants list is empty');
    } else {
      final ids = variants.map((v) => v.id).toSet();
      if (!ids.contains('control')) {
        issues.add("must include a variant with id 'control'");
      }
      if (ids.length != variants.length) {
        issues.add('duplicate variant ids');
      }
      final trafficSum =
          variants.fold<int>(0, (sum, v) => sum + v.trafficPercent);
      if (trafficSum != 100) {
        issues.add('traffic sum is $trafficSum, must be 100');
      }
      if (variants.any((v) => v.trafficPercent < 0)) {
        issues.add('negative trafficPercent not allowed');
      }
    }
    if (endsAt != null && endsAt!.isBefore(startedAt)) {
      issues.add('endsAt is before startedAt');
    }
    return issues;
  }

  /// True when this experiment should serve real variant assignments at
  /// the current moment. False → all users get 'control'.
  bool isLiveAt(DateTime moment) {
    if (!active) return false;
    if (moment.isBefore(startedAt)) return false;
    if (endsAt != null && moment.isAfter(endsAt!)) return false;
    return true;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'hypothesis': hypothesis,
        'variants': variants.map((v) => v.toJson()).toList(),
        'primaryMetric': primaryMetric,
        'startedAt': startedAt.toIso8601String(),
        'endsAt': endsAt?.toIso8601String(),
        'active': active,
      };

  factory ExperimentDefinition.fromJson(Map<String, dynamic> json) =>
      ExperimentDefinition(
        id: json['id'] as String,
        name: json['name'] as String,
        hypothesis: json['hypothesis'] as String,
        variants: (json['variants'] as List)
            .map((v) => VariantConfig.fromJson(v as Map<String, dynamic>))
            .toList(),
        primaryMetric: json['primaryMetric'] as String,
        startedAt: DateTime.parse(json['startedAt'] as String),
        endsAt: json['endsAt'] != null
            ? DateTime.parse(json['endsAt'] as String)
            : null,
        active: json['active'] as bool? ?? true,
      );
}

/// One user's assignment to a specific experiment's variant. Cached
/// in-memory (per session) by VariantAssigner.
@immutable
class VariantAssignment {
  final String experimentId;
  final String variantId;

  /// First 8 chars of the SHA-256(userId+experimentId) hash, useful
  /// for telemetry audit trail (proves the assignment is deterministic).
  final String userIdHashShort;

  const VariantAssignment({
    required this.experimentId,
    required this.variantId,
    required this.userIdHashShort,
  });
}
