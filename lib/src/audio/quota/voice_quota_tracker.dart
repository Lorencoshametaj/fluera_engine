// ============================================================================
// 🎙️ VOICE QUOTA TRACKER — Engine-side abstraction for monthly voice minutes
//
// Plus: 60 minuti/mese di voice recording. Pro: illimitato.
// Mirrors the AiCreditsController pattern: server-authoritative,
// ValueListenable<Snapshot> for UI, broadcast exhaustion events.
//
// Decision plan: .claude/plans/analizza-tutta-fluera-app-floating-pebble.md §3
// THREAD SAFETY: Main isolate only.
// ============================================================================

import 'package:flutter/foundation.dart';

/// 🎙️ Sentinel returned when the tier has no monthly cap (Pro / Edu).
const int voiceMinutesUnlimited = -1;

/// 🎙️ Immutable snapshot of the monthly voice-recording quota.
class VoiceQuotaSnapshot {
  /// Minutes recorded so far in the current monthly window.
  final int minutesUsed;

  /// Monthly allowance in minutes; [voiceMinutesUnlimited] (-1) for Pro.
  final int minutesLimit;

  /// Subscription tier at snapshot time.
  final String tier;

  /// UTC instant when the monthly counter resets.
  final DateTime monthlyResetAt;

  const VoiceQuotaSnapshot({
    required this.minutesUsed,
    required this.minutesLimit,
    required this.tier,
    required this.monthlyResetAt,
  });

  /// Whether this tier has no cap (Pro). Equivalent to `minutesLimit == -1`.
  bool get isUnlimited => minutesLimit == voiceMinutesUnlimited;

  /// Minutes remaining (or [voiceMinutesUnlimited] sentinel for Pro).
  int get minutesRemaining {
    if (isUnlimited) return voiceMinutesUnlimited;
    final r = minutesLimit - minutesUsed;
    return r < 0 ? 0 : r;
  }

  /// Whether the user has burned the entire monthly allowance.
  bool get isExhausted =>
      !isUnlimited && minutesUsed >= minutesLimit;

  /// Fraction of the monthly allowance consumed (0.0..1.0). Returns 0 for
  /// unlimited tiers so the UI doesn't render a progress bar.
  double get usedFraction {
    if (isUnlimited || minutesLimit <= 0) return 0.0;
    return (minutesUsed / minutesLimit).clamp(0.0, 1.0);
  }

  /// Whether the user can record at least one more [requestedMinutes]-long
  /// session. Unlimited tiers always return true.
  bool canRecord({int requestedMinutes = 1}) {
    if (isUnlimited) return true;
    return minutesUsed + requestedMinutes <= minutesLimit;
  }

  VoiceQuotaSnapshot copyWith({
    int? minutesUsed,
    int? minutesLimit,
    String? tier,
    DateTime? monthlyResetAt,
  }) =>
      VoiceQuotaSnapshot(
        minutesUsed: minutesUsed ?? this.minutesUsed,
        minutesLimit: minutesLimit ?? this.minutesLimit,
        tier: tier ?? this.tier,
        monthlyResetAt: monthlyResetAt ?? this.monthlyResetAt,
      );

  @override
  String toString() => 'VoiceQuotaSnapshot(tier: $tier, '
      '$minutesUsed/${isUnlimited ? "∞" : minutesLimit} min, '
      'resets: $monthlyResetAt)';
}

/// 🎙️ Thrown when the user has burned the monthly cap and tries to start
/// another recording. UI should surface the upgrade prompt for Pro
/// (unlimited) — not the Spark Pack purchase, because voice quota is
/// minute-scoped, not credit-scoped.
class VoiceQuotaExhaustedException implements Exception {
  final int requestedMinutes;
  final int minutesRemaining;
  final DateTime resetAt;
  final String tier;

  const VoiceQuotaExhaustedException({
    required this.requestedMinutes,
    required this.minutesRemaining,
    required this.resetAt,
    required this.tier,
  });

  @override
  String toString() => 'VoiceQuotaExhaustedException(tier: $tier, '
      'requested: ${requestedMinutes}m, remaining: ${minutesRemaining}m, '
      'resetAt: $resetAt)';
}

/// 🎙️ Contract for tracking the monthly voice-recording quota.
///
/// Engine-side abstraction. The host (Fluera app) injects a Supabase-backed
/// implementation via `EngineScope.voiceQuotaTracker`. The engine ships a
/// no-op default so the SDK stays usable without a backend.
///
/// The recorder calls [reserve] right before starting a session and
/// [commit] / [refund] when the session ends, with the actual duration
/// rounded up to whole minutes.
abstract class VoiceQuotaTracker {
  /// Reactive snapshot for UI binding (counter pill, settings).
  ValueListenable<VoiceQuotaSnapshot?> get quota;

  /// Broadcast stream of exhaustion events.
  Stream<VoiceQuotaExhaustedException> get exhaustedEvents;

  /// Pull the latest snapshot from the backend.
  Future<VoiceQuotaSnapshot?> refresh();

  /// Pre-flight check: throws [VoiceQuotaExhaustedException] if the user
  /// can't fit [estimateMinutes] more minutes into the monthly bucket.
  /// Returns a [reservationToken] the caller passes back to [commit] /
  /// [refund] so the actual duration can replace the estimate.
  Future<String> reserve({int estimateMinutes = 1});

  /// Commit a previously reserved recording with the actual [actualMinutes]
  /// (rounded up). Reconciles the optimistic reservation; idempotent on
  /// duplicate calls with the same [reservationToken].
  Future<void> commit({
    required String reservationToken,
    required int actualMinutes,
  });

  /// Refund a reservation (e.g. user cancelled, recorder failed to start).
  /// Idempotent.
  Future<void> refund(String reservationToken);

  /// Update the active subscription tier (e.g. after a Plus → Pro upgrade).
  Future<void> updateTier(String tier);

  /// Release held resources.
  void dispose();
}
