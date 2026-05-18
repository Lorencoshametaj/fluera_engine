// ============================================================================
// 🎬 TIME TRAVEL RETENTION POLICY — Per-tier ring buffer for recorded sessions
//
// Decision plan: .claude/plans/analizza-tutta-fluera-app-floating-pebble.md §3
//
// V1 split (2026-05-14):
//   • Free → 90-day ring buffer (recovery only, no playback UI)
//   • Plus → unlimited retention (cloud-backed)
//   • Pro  → unlimited retention + playback scrubber UI
//
// Pure policy object — no IO. The cleanup pass lives in the storage adapter
// (host-side) and consults this object to decide which sessions to evict.
// ============================================================================

import '../../canvas/fluera_canvas_config.dart';

/// 🎬 Sentinel returned by [TimeTravelRetentionPolicy.retentionDays] when
/// the tier has no time-based eviction (Plus / Pro).
const int timeTravelRetentionUnlimited = -1;

/// 🎬 Per-tier retention configuration for Time Travel sessions.
///
/// The retention policy is intentionally separate from
/// `TierGateController.canUseFeature(timeTravel)`:
///   • Recording always runs locally on every tier (even Free), because
///     it doubles as the crash-recovery store. The playback UI is what
///     [TierGateController] gates.
///   • Retention decides for how long the recorded events are kept on
///     disk before the storage adapter prunes them.
class TimeTravelRetentionPolicy {
  const TimeTravelRetentionPolicy({required this.tier});

  final FlueraSubscriptionTier tier;

  /// Number of days to keep recorded sessions on disk. Returns
  /// [timeTravelRetentionUnlimited] (-1) for tiers with no time-based
  /// eviction (Plus / Pro / Essential).
  int get retentionDays {
    return switch (tier) {
      FlueraSubscriptionTier.pro => timeTravelRetentionUnlimited,
      FlueraSubscriptionTier.plus => timeTravelRetentionUnlimited,
      FlueraSubscriptionTier.essential => timeTravelRetentionUnlimited,
      FlueraSubscriptionTier.free => 90,
    };
  }

  /// Whether the storage adapter must evict sessions older than the policy.
  /// False for tiers with [timeTravelRetentionUnlimited].
  bool get hasFiniteRetention => retentionDays != timeTravelRetentionUnlimited;

  /// Compute the eviction cutoff timestamp given a reference [now].
  /// Sessions with `createdAt < cutoff` should be pruned by the storage
  /// adapter on its next sweep.
  ///
  /// Returns `null` for unlimited tiers so callers can short-circuit
  /// the pruning pass entirely.
  DateTime? evictionCutoff({DateTime? now}) {
    if (!hasFiniteRetention) return null;
    final ref = (now ?? DateTime.now()).toUtc();
    return ref.subtract(Duration(days: retentionDays));
  }

  /// Whether the playback UI (scrubber overlay) is available for this tier.
  /// Decoupled from [retentionDays] because Plus has unlimited storage but
  /// the scrubber is a Pro pillar (Plus + Pro split, see plan §1).
  bool get canShowPlaybackUi => tier == FlueraSubscriptionTier.pro;

  @override
  String toString() => 'TimeTravelRetentionPolicy(tier: ${tier.name}, '
      'retention: ${hasFiniteRetention ? "$retentionDays d" : "∞"}, '
      'playbackUi: $canShowPlaybackUi)';
}
