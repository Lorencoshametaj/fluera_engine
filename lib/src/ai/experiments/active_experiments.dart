// ============================================================================
// 🧪 ActiveExperiments — runtime registry of A/B experiments.
//
// Static singleton-style registry. Host app calls `load(List<...>)` once
// at startup (typically from main.dart or canvas init) to register the
// experiment catalog. Engine code consults `byId` / `current` to drive
// variant assignment + cell overrides.
//
// Empty by default → no active experiments → all users get 'control'
// → behavior identical to pre-A/B baseline.
// ============================================================================

import 'experiment_definition.dart';

class ActiveExperiments {
  ActiveExperiments._();

  static List<ExperimentDefinition> _experiments = const [];

  /// All currently-loaded experiment definitions, in declaration order.
  /// Includes inactive/expired ones (callers check `isLiveAt`).
  static List<ExperimentDefinition> get current =>
      List.unmodifiable(_experiments);

  /// Replace the registry contents. Host app calls this once at startup.
  /// Re-calling at runtime is supported (e.g. remote-config refresh).
  ///
  /// Validates each definition; throws [StateError] if any is invalid
  /// (better fail-fast than ship a broken experiment).
  static void load(List<ExperimentDefinition> experiments) {
    for (final exp in experiments) {
      final issues = exp.validate();
      if (issues.isNotEmpty) {
        throw StateError(
            'Invalid experiment ${exp.id}: ${issues.join(", ")}');
      }
    }
    final ids = experiments.map((e) => e.id).toSet();
    if (ids.length != experiments.length) {
      throw StateError('Duplicate experiment ids in registry');
    }
    _experiments = experiments;
  }

  /// Lookup by id. Returns null when not registered.
  static ExperimentDefinition? byId(String id) {
    for (final exp in _experiments) {
      if (exp.id == id) return exp;
    }
    return null;
  }

  /// Reset to empty (for tests).
  static void clearForTests() {
    _experiments = const [];
  }
}
