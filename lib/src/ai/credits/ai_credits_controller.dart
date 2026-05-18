// ============================================================================
// 💎 AI CREDITS CONTROLLER — Engine-side abstraction for credit accounting
//
// Mirrors the proven [AiUsageTracker] design (server-authoritative,
// ValueListenable<Snapshot>, broadcast event streams) but exposes a
// "credits per feature" surface rather than raw tokens.
//
// Decision plan: .claude/plans/analizza-tutta-fluera-app-floating-pebble.md §2
//
// Engine ships the [NoopAiCreditsController] as the default so the SDK stays
// usable without a backing implementation. The Fluera app injects the
// Supabase-backed concrete via [EngineScope.push].
//
// THREAD SAFETY: Main isolate only.
// ============================================================================

import 'package:flutter/foundation.dart';

import 'ai_credits_costs.dart';

/// 💎 Immutable snapshot of the user's credit state at a point in time.
///
/// Emitted by [AiCreditsController.credits]. The UI binds to this for the
/// always-visible counter ("Sai sempre quanto AI ti rimane" pillar).
class AiCreditsSnapshot {
  /// Credits granted by the current monthly subscription. Resets on
  /// [monthlyResetAt]. Always ≥ 0.
  final int monthlyCredits;

  /// Credits granted by Spark Pack top-up purchases. Never expire,
  /// consumed BEFORE [monthlyCredits] (psychology: "the user paid for these").
  final int packCredits;

  /// Subscription tier at snapshot time (e.g. "free", "plus", "pro").
  final String tier;

  /// When the monthly allowance refills next (UTC). Pack credits ignore this.
  final DateTime monthlyResetAt;

  const AiCreditsSnapshot({
    required this.monthlyCredits,
    required this.packCredits,
    required this.tier,
    required this.monthlyResetAt,
  });

  /// Total credits available right now (pack + monthly).
  int get total => monthlyCredits + packCredits;

  /// Whether the user has at least [cost] credits available.
  bool canAfford(int cost) => total >= cost;

  /// Whether all credits are exhausted.
  bool get isExhausted => total <= 0;

  /// Fraction of the monthly allowance consumed (0.0..1.0).
  /// Returns 0.0 when the tier has no listed allowance.
  double get monthlyUsedFraction {
    final allowance = AiCreditsCosts.monthlyAllowance[tier] ?? 0;
    if (allowance <= 0) return 0.0;
    final used = (allowance - monthlyCredits).clamp(0, allowance);
    return used / allowance;
  }

  AiCreditsSnapshot copyWith({
    int? monthlyCredits,
    int? packCredits,
    String? tier,
    DateTime? monthlyResetAt,
  }) =>
      AiCreditsSnapshot(
        monthlyCredits: monthlyCredits ?? this.monthlyCredits,
        packCredits: packCredits ?? this.packCredits,
        tier: tier ?? this.tier,
        monthlyResetAt: monthlyResetAt ?? this.monthlyResetAt,
      );

  @override
  String toString() => 'AiCreditsSnapshot(tier: $tier, '
      'pack: $packCredits, monthly: $monthlyCredits, '
      'resets: $monthlyResetAt)';
}

/// 💎 Thrown by [AiCreditsController.consume] when the user has no credits
/// left for the requested feature.
///
/// UI boundary should catch this and surface the Spark Pack purchase dialog
/// instead of propagating it as a generic error.
class AiCreditsExhaustedException implements Exception {
  final AiCreditFeature feature;
  final int needed;
  final int available;
  final DateTime resetAt;

  const AiCreditsExhaustedException({
    required this.feature,
    required this.needed,
    required this.available,
    required this.resetAt,
  });

  @override
  String toString() => 'AiCreditsExhaustedException(feature: ${feature.name}, '
      'needed: $needed, available: $available, resetAt: $resetAt)';
}

/// 💎 Thrown by [AiCreditsController.consume] when the server-side
/// per-feature short-window rate limit fires (anti-script abuse guard,
/// e.g. 60 chat msgs/hour or 30 consume RPC/hour).
///
/// Distinct from [AiCreditsExhaustedException]: the user has credits, but
/// hit a per-feature throttle. UI should show a transient "slow down"
/// snackbar, not the Spark Pack dialog.
class AiCreditsRateLimitedException implements Exception {
  final AiCreditFeature feature;
  final Duration retryAfter;

  const AiCreditsRateLimitedException({
    required this.feature,
    required this.retryAfter,
  });

  @override
  String toString() => 'AiCreditsRateLimitedException('
      'feature: ${feature.name}, retryAfter: $retryAfter)';
}

/// 💎 Receipt returned by [AiCreditsController.consume] on success.
///
/// Carry the [idempotencyKey] across the AI call so [AiCreditsController.refund]
/// can be invoked if the call ultimately fails. Without the key, refunds
/// risk double-spending (idempotency layer rejects duplicate consume but
/// also duplicate refund attempts).
class AiCreditsReceipt {
  final String idempotencyKey;
  final AiCreditFeature feature;
  final int cost;
  final AiCreditsSnapshot snapshotAfter;

  const AiCreditsReceipt({
    required this.idempotencyKey,
    required this.feature,
    required this.cost,
    required this.snapshotAfter,
  });
}

/// 💎 Contract for tracking and enforcing AI credit usage.
///
/// Engine-side abstraction. AI call sites invoke [consume] BEFORE the
/// outbound request, then [refund] on failure (within 30 s window). The
/// app provides a concrete implementation that persists state server-side
/// (Supabase).
///
/// The engine ships [NoopAiCreditsController] as the default so the SDK
/// stays usable without a backing implementation.
abstract class AiCreditsController {
  /// Reactive source of the current credit snapshot. UI binds to this.
  ///
  /// Updated on:
  ///   • [refresh] — server snapshot pull
  ///   • [consume] / [refund] — local optimistic mutation
  ///   • Realtime Broadcast `credit_changed` from another device
  ValueListenable<AiCreditsSnapshot?> get credits;

  /// Broadcast stream of exhaustion events. UI subscribes once to show the
  /// Spark Pack purchase dialog without wrapping every call site in try/catch.
  Stream<AiCreditsExhaustedException> get exhaustedEvents;

  /// Broadcast stream of rate-limit events. UI shows a transient
  /// "slow down" snackbar.
  Stream<AiCreditsRateLimitedException> get rateLimitedEvents;

  /// Pull the latest snapshot from the backend.
  ///
  /// Implementations should also refresh the local cache (e.g. SharedPreferences
  /// for the offline grace period) and drain any queued offline operations.
  Future<AiCreditsSnapshot?> refresh();

  /// Atomically pre-flight check and decrement credits for [feature].
  ///
  /// Returns a [AiCreditsReceipt] on success; throws
  /// [AiCreditsExhaustedException] when the balance is insufficient or
  /// [AiCreditsRateLimitedException] when the per-feature throttle fires.
  ///
  /// Spark Pack credits are consumed BEFORE monthly credits (psychology:
  /// the user paid for these specifically).
  ///
  /// The returned [AiCreditsReceipt.idempotencyKey] MUST be passed to
  /// [refund] if the downstream AI call fails — otherwise the user has paid
  /// for an operation that never delivered value.
  Future<AiCreditsReceipt> consume(AiCreditFeature feature);

  /// Reverse a previous [consume] using the receipt's [idempotencyKey].
  ///
  /// Idempotent: calling twice with the same key is a no-op. Safe to call
  /// from a `catch` block without wrapping in another try/catch.
  ///
  /// The 30-second refund window is enforced server-side — refunds after
  /// that are silently dropped (the assumption being that any AI call that
  /// took >30 s likely delivered partial value).
  Future<void> refund(String idempotencyKey);

  /// Record a Spark Pack purchase. Called by the host's purchase observer
  /// after RevenueCat confirms the transaction. The [packSku] must match
  /// a key in [AiCreditsCosts.sparkPackCredits].
  Future<void> applyPackPurchase({
    required String packSku,
    required String purchaseToken,
  });

  /// Update the active subscription tier (e.g. after a Plus → Pro upgrade).
  /// Triggers a refresh so the monthly allowance picks up the new value.
  Future<void> updateTier(String tier);

  /// 🆓 Record a Fluera-absorbed free background AI call (cleanOcr /
  /// clusterTitle / superNodeTheme) against the per-tier monthly cap.
  ///
  /// Server-side semantics (RPC `record_background_ai`):
  ///   • Atomic increment of `ai_background_usage.cluster_count` by [clusterCount]
  ///   • Tier-aware cap: Free=1000, Plus=10000, Pro=50000 (per 30-day rolling)
  ///   • Per-feature rate limit: 50 calls/hour
  ///   • Consent gate via `user_preferences.consent_ai_background`
  ///   • Realtime broadcast `usage_changed` on success
  ///
  /// Returns `true` when the caller may proceed with the Gemini call,
  /// `false` for any negative outcome (cap exceeded, consent off, rate-
  /// limited, offline, RPC failure). On `cap_exceeded` the implementation
  /// should also surface a [BackgroundAiCapExceededException] on a stream
  /// the UI can subscribe to (banner display); the boolean return keeps
  /// the call-site logic simple.
  ///
  /// Default implementation returns `true` so providers that don't
  /// implement the cap (e.g. [NoopAiCreditsController] in tests) stay
  /// backward-compatible.
  Future<bool> recordBackgroundCall({required int clusterCount}) =>
      Future.value(true);

  /// Broadcast stream of background-AI cap events. UI subscribes once
  /// to show the upsell banner.
  ///
  /// Default implementation yields nothing (matches the no-op cap).
  Stream<BackgroundAiCapExceededException> get backgroundCapEvents =>
      const Stream.empty();

  /// 🔍 Read-only snapshot of the background-AI quota state for the
  /// calling user. Companion to [recordBackgroundCall].
  ///
  /// Returns `null` when the host doesn't implement the peek (engine
  /// default + no-op + tests). Concrete implementations call the
  /// `peek_background_ai_status` RPC (migration 018).
  ///
  /// Used by `BackgroundAiController._logPreflightStatus` at canvas
  /// open to surface every gate (auth / consent / cap) in one block,
  /// without mutating the usage counter.
  Future<BackgroundAiPeek?> peekBackgroundStatus() => Future.value(null);

  /// Release held resources (stream controllers, listeners, Realtime
  /// subscriptions, etc.).
  void dispose();
}

/// 🔍 Snapshot of the background-AI quota state returned by
/// [AiCreditsController.peekBackgroundStatus]. Mirrors the shape of the
/// `peek_background_ai_status` RPC response (migration 018) — read-only,
/// no side effects.
///
/// Used by `BackgroundAiController._logPreflightStatus` to surface the
/// cap headroom (and any pre-existing block: `consent_off`, `cap_exceeded`,
/// `not_authenticated`) at canvas open, so device runs no longer have to
/// trip on each gate sequentially.
class BackgroundAiPeek {
  const BackgroundAiPeek({
    required this.ok,
    required this.allowed,
    this.error,
    this.tier,
    this.used,
    this.cap,
  });

  /// `true` when the RPC ran end-to-end; `false` on `not_authenticated`
  /// or `internal_error`. Distinct from [allowed], which can be `false`
  /// even when ok is `true` (consent_off / cap_exceeded).
  final bool ok;

  /// `true` when a record_background_ai call would currently be
  /// accepted, `false` when the server would deny.
  final bool allowed;

  /// Deny reason when [allowed] is `false`: `not_authenticated`,
  /// `consent_off`, `cap_exceeded`, `internal_error`, or `null`.
  final String? error;

  /// Current subscription tier (`'free'`, `'plus'`, `'pro'`). Absent
  /// when [ok] is `false`.
  final String? tier;

  /// Cluster count consumed in the current 30-day window.
  final int? used;

  /// Per-tier monthly cap (Free=1000 / Plus=10000 / Pro=50000).
  final int? cap;

  @override
  String toString() {
    if (!ok) return 'BackgroundAiPeek(ok=false, error=$error)';
    if (!allowed) {
      return 'BackgroundAiPeek(denied: $error, tier=$tier, used=$used/$cap)';
    }
    return 'BackgroundAiPeek(allowed, tier=$tier, used=$used/$cap)';
  }
}

/// Raised (and broadcast on [AiCreditsController.backgroundCapEvents])
/// when the monthly free-background cap is reached for the current tier.
///
/// Unlike [AiCreditsExhaustedException] (which blocks paid features),
/// this never blocks user input — the client degrades gracefully to raw
/// OCR + heuristic titles until the next monthly rollover or a tier
/// upgrade. The exception type carries the snapshot so the banner copy
/// can read `"used 1000 of 1000"` directly.
class BackgroundAiCapExceededException implements Exception {
  BackgroundAiCapExceededException({
    required this.tier,
    required this.cap,
    required this.used,
  });

  /// Current tier (`'free'`, `'plus'`, `'pro'`, …).
  final String tier;

  /// Per-tier monthly cap (Free=1000, Plus=10000, Pro=50000).
  final int cap;

  /// Cluster count already consumed in the current 30-day window.
  final int used;

  @override
  String toString() =>
      'BackgroundAiCapExceededException(tier=$tier, used=$used/$cap)';
}
