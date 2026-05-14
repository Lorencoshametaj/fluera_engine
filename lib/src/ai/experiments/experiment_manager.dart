// ============================================================================
// 🧪 ExperimentManager — host-app facing API for the A/B layer.
//
// Combines ActiveExperiments (registry) + VariantAssigner (hashing) into
// a single object the host app instantiates once and injects into:
//   - GeminiProvider (constructor param → VariantOverridesProvider wiring)
//   - 3 controllers (Socratic, Exam, Chat) for telemetry tag
//
// Holds the current userId (provided by the host app). On userId change,
// the in-memory assignment cache is cleared so the new user gets fresh
// assignments. Until a userId is provided, all evaluations return
// 'control' (fail-safe: no experiments run for anonymous sessions).
// ============================================================================

import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;

import 'active_experiments.dart';
import 'experiment_definition.dart';
import 'variant_assigner.dart';

class ExperimentManager {
  /// 🧪 Sprint AB-E — optional global accessor. Host app sets via
  /// `ExperimentManager.activeInstance = myManager` at startup. Telemetry
  /// emitters in Socratic / Exam / Chat controllers consult this to tag
  /// events with `variants_assigned` map. Null = no tagging (events
  /// emit as before, backward compat).
  static ExperimentManager? activeInstance;

  final VariantAssigner _assigner = VariantAssigner();

  /// Reactive map of (experimentId → variantId) for the current user.
  /// UI / telemetry subscribers listen to this to react to assignment
  /// changes (e.g. logout/login → cache cleared → map repopulates).
  final ValueNotifier<Map<String, String>> _assignmentsNotifier =
      ValueNotifier<Map<String, String>>(const {});

  ValueListenable<Map<String, String>> get assignments => _assignmentsNotifier;

  String? _userId;

  /// Set the current user. Pass null on logout. Triggers cache clear +
  /// re-eval of the assignment notifier.
  set userId(String? id) {
    if (_userId == id) return;
    _userId = id;
    _assigner.clearCache();
    _refreshAssignments();
  }

  String? get userId => _userId;

  /// Returns the variant id ('control' | variant.id) for [experimentId]
  /// for the current user. Returns 'control' when:
  ///   - userId is null (anonymous session)
  ///   - experimentId is not registered
  ///   - experiment is inactive / out of date window
  String evaluateVariant(String experimentId, {DateTime? now}) {
    final uid = _userId;
    if (uid == null) return 'control';
    final exp = ActiveExperiments.byId(experimentId);
    if (exp == null) return 'control';
    final assignment = _assigner.assignmentFor(
      userId: uid,
      experiment: exp,
      now: now,
    );
    return assignment.variantId;
  }

  /// Returns the full assignment record (with hash for audit trail).
  /// Returns null when no active experiment for [experimentId] OR no userId.
  VariantAssignment? assignmentFor(String experimentId, {DateTime? now}) {
    final uid = _userId;
    if (uid == null) return null;
    final exp = ActiveExperiments.byId(experimentId);
    if (exp == null) return null;
    return _assigner.assignmentFor(
      userId: uid,
      experiment: exp,
      now: now,
    );
  }

  /// Returns the flat (experimentId → variantId) map for all currently-
  /// loaded experiments. Used by telemetry emission to tag events with
  /// `variants_assigned`. Empty map when no userId or no experiments.
  Map<String, String> currentAssignmentsMap({DateTime? now}) {
    if (_userId == null) return const {};
    final out = <String, String>{};
    for (final exp in ActiveExperiments.current) {
      out[exp.id] = evaluateVariant(exp.id, now: now);
    }
    return out;
  }

  /// Recompute the cached assignment notifier. Called on userId change.
  void _refreshAssignments() {
    _assignmentsNotifier.value = currentAssignmentsMap();
  }

  /// Manually trigger a refresh — useful when ActiveExperiments.load
  /// was called at runtime to add/remove experiments.
  void refresh() => _refreshAssignments();

  void dispose() => _assignmentsNotifier.dispose();
}
