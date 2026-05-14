// ============================================================================
// 💰 AiBudgetMonitor — threshold alerting + per-feature breakdown decorator.
//
// Wraps an [AiUsageTracker] without changing its contract. Adds:
//   1. Telemetry events on quota-fraction threshold crossings (70%, 90%, 100%)
//   2. In-memory per-feature breakdown of token spend (chat/exam/socratic/...)
//   3. Reactive notification of threshold state for UI banners
//
// The base [AiUsageTracker] enforces the hard cap (throws
// `AiQuotaExceededException`); this monitor adds visibility into the SLOPE
// of consumption + alerting before exhaustion + per-feature attribution.
//
// Engine-side. App provides concrete tracker + telemetry sink; monitor
// is optional opt-in.
// ============================================================================

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../ai_usage_tracker.dart';
import '../telemetry_recorder.dart';

/// Threshold crossing levels emitted by the monitor.
enum AiBudgetThreshold {
  /// 70% of monthly budget consumed — soft warning.
  warning70,

  /// 90% of monthly budget consumed — urgent.
  warning90,

  /// 100% consumed — hard cap reached (next call throws).
  exhausted,
}

/// Immutable snapshot of the budget state with per-feature breakdown.
class AiBudgetSnapshot {
  /// Underlying quota snapshot (tokens, tier, periodEnd).
  final AiQuotaSnapshot? quota;

  /// Highest threshold reached this period (if any).
  final AiBudgetThreshold? thresholdReached;

  /// Per-feature token breakdown for the current period.
  /// Keys: feature names emitted via `recordUsage` (e.g. 'askChatStream',
  /// 'generateExamQuestions', 'streamForStage::anchor::it', etc).
  final Map<String, int> featureBreakdown;

  const AiBudgetSnapshot({
    required this.quota,
    required this.thresholdReached,
    required this.featureBreakdown,
  });

  /// Total tokens consumed this period across all features (sum of values
  /// in [featureBreakdown]; should match `quota.tokensUsed` modulo races).
  int get totalTokens =>
      featureBreakdown.values.fold<int>(0, (a, b) => a + b);

  /// The feature responsible for the largest share of consumption.
  /// Returns null when no usage recorded yet.
  String? get topSpender {
    if (featureBreakdown.isEmpty) return null;
    final sorted = featureBreakdown.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.first.key;
  }
}

/// Decorator over [AiUsageTracker] that emits threshold telemetry +
/// tracks per-feature breakdown. Safe to instantiate without affecting
/// the wrapped tracker's contract.
class AiBudgetMonitor {
  final AiUsageTracker _tracker;
  final TelemetryRecorder _telemetry;

  /// Reactive snapshot listenable. Updates whenever the underlying
  /// `_tracker.quota` changes OR `recordSpend` is called.
  final ValueNotifier<AiBudgetSnapshot> snapshot;

  final Map<String, int> _featureBreakdown = {};
  AiBudgetThreshold? _lastThresholdEmitted;

  late final VoidCallback _quotaListener;

  AiBudgetMonitor({
    required AiUsageTracker tracker,
    required TelemetryRecorder telemetry,
  })  : _tracker = tracker,
        _telemetry = telemetry,
        snapshot = ValueNotifier<AiBudgetSnapshot>(
          AiBudgetSnapshot(
            quota: tracker.quota.value,
            thresholdReached: null,
            featureBreakdown: const {},
          ),
        ) {
    _quotaListener = _onQuotaChanged;
    _tracker.quota.addListener(_quotaListener);
  }

  /// Called externally after each `recordUsage` to attribute spend to a
  /// feature. Idempotent in spirit: increments running counter, refreshes
  /// snapshot. Safe to call from a fire-and-forget context.
  ///
  /// We separate this from [AiUsageTracker.recordUsage] so the monitor
  /// stays additive — the host app can wire it (or not) without changing
  /// the existing tracker contract.
  void recordSpend(String feature, int tokens) {
    if (tokens <= 0) return;
    _featureBreakdown[feature] = (_featureBreakdown[feature] ?? 0) + tokens;
    _refreshSnapshot();
  }

  /// Reset the in-memory breakdown (e.g. at period rollover). The
  /// threshold emission state also resets, so the next 70%/90%/100%
  /// crossing emits fresh events.
  void resetPeriod() {
    _featureBreakdown.clear();
    _lastThresholdEmitted = null;
    _refreshSnapshot();
  }

  void _onQuotaChanged() {
    _checkThreshold();
    _refreshSnapshot();
  }

  void _checkThreshold() {
    final q = _tracker.quota.value;
    if (q == null || q.tokensLimit <= 0) return;
    final fraction = q.usedFraction;
    AiBudgetThreshold? hit;
    if (fraction >= 1.0) {
      hit = AiBudgetThreshold.exhausted;
    } else if (fraction >= 0.9) {
      hit = AiBudgetThreshold.warning90;
    } else if (fraction >= 0.7) {
      hit = AiBudgetThreshold.warning70;
    }
    if (hit == null) return;
    // Only emit when we CROSS a new threshold (avoid spam on every
    // recordUsage that nudges fraction by epsilon).
    if (_lastThresholdEmitted != null &&
        hit.index <= _lastThresholdEmitted!.index) {
      return;
    }
    _lastThresholdEmitted = hit;
    _telemetry.logEvent('ai_budget_threshold_crossed', properties: {
      'threshold': hit.name,
      'tier': q.tier,
      'fraction': fraction,
      'tokens_used': q.tokensUsed,
      'tokens_limit': q.tokensLimit,
      'top_spender': _topSpender() ?? 'none',
    });
  }

  String? _topSpender() {
    if (_featureBreakdown.isEmpty) return null;
    final sorted = _featureBreakdown.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.first.key;
  }

  void _refreshSnapshot() {
    snapshot.value = AiBudgetSnapshot(
      quota: _tracker.quota.value,
      thresholdReached: _lastThresholdEmitted,
      featureBreakdown: Map.unmodifiable(_featureBreakdown),
    );
  }

  /// Release listener on the wrapped tracker.
  void dispose() {
    _tracker.quota.removeListener(_quotaListener);
    snapshot.dispose();
  }
}
