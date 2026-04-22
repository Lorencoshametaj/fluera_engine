import 'package:flutter/foundation.dart' show ValueListenable;

/// Immutable snapshot of the user's AI quota state at a point in time.
///
/// Emitted by [AiUsageTracker.quota] and consumed by reactive UI widgets.
class AiQuotaSnapshot {
  final int tokensUsed;
  final int tokensLimit;
  final String tier;
  final DateTime periodEnd;

  /// Ghost Map calls consumed in the current period (server-authoritative).
  /// `null` on legacy snapshots produced before the cap system shipped.
  final int? ghostMapCallsThisPeriod;

  /// Hard cap on Ghost Map calls for the user's tier in the current period.
  /// `null` on legacy snapshots.
  final int? ghostMapCap;

  const AiQuotaSnapshot({
    required this.tokensUsed,
    required this.tokensLimit,
    required this.tier,
    required this.periodEnd,
    this.ghostMapCallsThisPeriod,
    this.ghostMapCap,
  });

  int get remaining {
    final r = tokensLimit - tokensUsed;
    return r < 0 ? 0 : r;
  }

  bool get isExhausted => remaining <= 0;

  double get usedFraction =>
      tokensLimit <= 0 ? 0.0 : (tokensUsed / tokensLimit).clamp(0.0, 1.0);

  /// Ghost Map calls remaining in this period, or `null` if the data isn't
  /// available (pre-cap server, or field missing from response).
  int? get ghostMapRemaining {
    if (ghostMapCap == null || ghostMapCallsThisPeriod == null) return null;
    final r = ghostMapCap! - ghostMapCallsThisPeriod!;
    return r < 0 ? 0 : r;
  }

  bool get isGhostMapCapReached =>
      ghostMapRemaining != null && ghostMapRemaining! <= 0;

  AiQuotaSnapshot copyWith({
    int? tokensUsed,
    int? tokensLimit,
    String? tier,
    DateTime? periodEnd,
    int? ghostMapCallsThisPeriod,
    int? ghostMapCap,
  }) => AiQuotaSnapshot(
        tokensUsed: tokensUsed ?? this.tokensUsed,
        tokensLimit: tokensLimit ?? this.tokensLimit,
        tier: tier ?? this.tier,
        periodEnd: periodEnd ?? this.periodEnd,
        ghostMapCallsThisPeriod:
            ghostMapCallsThisPeriod ?? this.ghostMapCallsThisPeriod,
        ghostMapCap: ghostMapCap ?? this.ghostMapCap,
      );

  @override
  String toString() =>
      'AiQuotaSnapshot(tier: $tier, $tokensUsed/$tokensLimit, '
      'ghostMap: $ghostMapCallsThisPeriod/$ghostMapCap, resets: $periodEnd)';
}

/// Thrown by [AiUsageTracker.ensureBalance] when the remaining balance is
/// insufficient for the estimated call cost.
///
/// UI boundary (e.g. `AiCallGuard`) should catch this and surface an upgrade
/// prompt rather than propagating it as a generic error.
class AiQuotaExceededException implements Exception {
  final int needed;
  final int remaining;
  final DateTime? resetAt;

  const AiQuotaExceededException({
    required this.needed,
    required this.remaining,
    this.resetAt,
  });

  @override
  String toString() =>
      'AiQuotaExceededException(needed: $needed, remaining: $remaining, resetAt: $resetAt)';
}

/// Thrown when the server-side short-window rate limit kicks in for a
/// specific feature (e.g. more than 1 Ghost Map call per 3 minutes).
///
/// Distinct from [AiQuotaExceededException]: the user has budget left, but
/// hit a per-feature anti-abuse guard. UI should tell them to slow down,
/// not to upgrade.
class AiRateLimitedException implements Exception {
  final String feature;
  final String message;

  const AiRateLimitedException({
    required this.feature,
    required this.message,
  });

  @override
  String toString() => 'AiRateLimitedException(feature: $feature): $message';
}

/// Thrown when the user has exhausted the per-period Ghost Map cap for
/// their tier (free: 3, plus: 30, pro: 100).
///
/// Distinct from [AiQuotaExceededException]: only Ghost Map is blocked; the
/// user can still use Socratic, chat, exams etc. UI should suggest either
/// waiting for the next period or upgrading the tier.
class GhostMapCapExceededException implements Exception {
  final String tier;
  final int cap;

  const GhostMapCapExceededException({
    required this.tier,
    required this.cap,
  });

  @override
  String toString() =>
      'GhostMapCapExceededException(tier: $tier, cap: $cap/month)';
}

/// Contract for tracking and enforcing AI token usage.
///
/// Engine-side abstraction. The engine invokes it from [GeminiProvider]
/// (or any [AiProvider]) to meter every Gemini call. The app provides a
/// concrete implementation that persists state server-side (e.g. Supabase).
///
/// The engine ships [NoopAiUsageTracker] as the default — so the engine
/// stays usable without a backing tracker, and tests can opt-in with a fake.
abstract class AiUsageTracker {
  /// Reactive source of the current quota snapshot. UI binds to this.
  ValueListenable<AiQuotaSnapshot?> get quota;

  /// Broadcast stream of quota-exceeded events.
  ///
  /// Emitted immediately before [ensureBalance] throws. The app subscribes
  /// to this once globally (e.g. in a bootstrap) and shows an upsell UI —
  /// avoids having to wrap every AI call site with a try/catch.
  Stream<AiQuotaExceededException> get exceededEvents;

  /// Broadcast stream of rate-limited events (short-window anti-abuse
  /// guards). Emitted immediately before a rate-limit exception is thrown.
  /// UI should surface a transient "slow down" snackbar.
  Stream<AiRateLimitedException> get rateLimitedEvents;

  /// Broadcast stream of Ghost Map cap events (per-period hard cap reached).
  /// Emitted immediately before a Ghost Map cap exception is thrown.
  /// UI should surface a dialog with two CTAs: wait until next period, or
  /// upgrade tier.
  Stream<GhostMapCapExceededException> get ghostMapCapEvents;

  /// Pull the latest quota state from the backend.
  Future<AiQuotaSnapshot?> refresh();

  /// Pre-flight check. Throws [AiQuotaExceededException] when the remaining
  /// balance cannot cover [estimate] tokens, or [GhostMapCapExceededException]
  /// when [feature] is `'generateGhostMap'` and the per-period cap is reached.
  ///
  /// Should be called before issuing an outbound AI request.
  Future<void> ensureBalance({int estimate = 500, String? feature});

  /// Record that [tokens] were consumed by [feature].
  ///
  /// Invoked after each AI call completes (including partial/cancelled
  /// streams — see [GeminiProvider]). Implementations should be idempotent-ish
  /// and non-blocking from the caller's perspective (fire-and-forget is OK).
  ///
  /// Optional breakdown for cost-accounting telemetry:
  ///   [inputTokens] — prompt tokens (`usageMetadata.promptTokenCount`).
  ///   [outputTokens] — response tokens (`usageMetadata.candidatesTokenCount`).
  ///   [model] — model id (e.g. `"gemini-2.5-flash-lite"`).
  /// These let back-end billing math split input vs. output pricing and
  /// per-model cost; implementations without that detail can ignore them.
  Future<void> recordUsage(
    int tokens,
    String feature, {
    int? inputTokens,
    int? outputTokens,
    String? model,
  });

  /// Release any held resources.
  void dispose();
}
