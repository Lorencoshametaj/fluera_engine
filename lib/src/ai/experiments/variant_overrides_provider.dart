// ============================================================================
// 🧪 VariantOverridesProvider — cell text override resolution per variant.
//
// When an experiment is live and a user is assigned to a non-control
// variant, this provider returns the override cell text for the
// (feature, unit, langCode) triple. Returns null when:
//   - user is in 'control' branch (no override → use default cell)
//   - no experiment overrides the requested (feature, unit, langCode)
//   - userId is null (anonymous → no experiments)
//
// Engine consumers (PedagogyRegistry / ExamPedagogyRegistry /
// ChatPedagogyRegistry) call this BEFORE falling back to the default
// dispatch. When null is returned, default behavior is preserved
// (zero regression for non-experiment users).
// ============================================================================

import 'experiment_manager.dart';

/// Abstract interface — host app can plug a custom resolver, or use
/// the default [MapVariantOverridesProvider] which reads from an
/// in-memory map populated at startup.
abstract class VariantOverridesProvider {
  /// Returns the override cell text for the (feature, unit, langCode)
  /// triple, or null when there's no override for the current user's
  /// active variants.
  ///
  /// Conventions:
  ///   - feature: 'socratic' | 'exam' | 'chat'
  ///   - unit:    e.g. 'anchor' (Socratic stage), 'generation' (Exam
  ///             phase), 'chat' (single Chat surface), or
  ///             'discipline.physics' for discipline hints
  ///   - langCode: ISO 639-1 (e.g. 'it', 'en', 'es', 'ja')
  String? cellOverrideFor({
    required String feature,
    required String unit,
    required String langCode,
  });
}

/// Default implementation: an in-memory map populated at startup, keyed
/// by (experimentId → variantId → feature → unit → langCode) → text.
///
/// The host app builds the map from experiment definitions + cell
/// override fixtures. Engine code remains agnostic.
class MapVariantOverridesProvider implements VariantOverridesProvider {
  final ExperimentManager _manager;

  /// Map: experimentId → variantId → feature → unit → langCode → cell text
  final Map<String,
          Map<String, Map<String, Map<String, Map<String, String>>>>>
      _overrides;

  MapVariantOverridesProvider({
    required ExperimentManager manager,
    required Map<String,
            Map<String, Map<String, Map<String, Map<String, String>>>>>
        overrides,
  })  : _manager = manager,
        _overrides = overrides;

  @override
  String? cellOverrideFor({
    required String feature,
    required String unit,
    required String langCode,
  }) {
    if (_manager.userId == null) return null;
    // Check all active experiments; first matching override wins.
    // Experiment authors should keep cell-coverage non-overlapping.
    final assignments = _manager.currentAssignmentsMap();
    for (final entry in assignments.entries) {
      final variantId = entry.value;
      if (variantId == 'control') continue; // control = default cell
      final cell =
          _overrides[entry.key]?[variantId]?[feature]?[unit]?[langCode];
      if (cell != null) return cell;
    }
    return null;
  }
}

/// A simple test/dev helper: always returns null (no overrides).
/// Same as not injecting any provider — but useful for explicit wiring
/// in tests or to satisfy required-non-null APIs.
class NoopVariantOverridesProvider implements VariantOverridesProvider {
  const NoopVariantOverridesProvider();

  @override
  String? cellOverrideFor({
    required String feature,
    required String unit,
    required String langCode,
  }) =>
      null;
}
