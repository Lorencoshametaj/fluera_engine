import 'package:flutter/foundation.dart' show ValueListenable;

/// Immutable snapshot of the user's AI quota state at a point in time.
///
/// Emitted by [AiUsageTracker.quota] and consumed by reactive UI widgets.
class AiQuotaSnapshot {
  final int tokensUsed;
  final int tokensLimit;
  final String tier;
  final DateTime periodEnd;

  const AiQuotaSnapshot({
    required this.tokensUsed,
    required this.tokensLimit,
    required this.tier,
    required this.periodEnd,
  });

  int get remaining {
    final r = tokensLimit - tokensUsed;
    return r < 0 ? 0 : r;
  }

  bool get isExhausted => remaining <= 0;

  double get usedFraction =>
      tokensLimit <= 0 ? 0.0 : (tokensUsed / tokensLimit).clamp(0.0, 1.0);

  AiQuotaSnapshot copyWith({
    int? tokensUsed,
    int? tokensLimit,
    String? tier,
    DateTime? periodEnd,
  }) => AiQuotaSnapshot(
        tokensUsed: tokensUsed ?? this.tokensUsed,
        tokensLimit: tokensLimit ?? this.tokensLimit,
        tier: tier ?? this.tier,
        periodEnd: periodEnd ?? this.periodEnd,
      );

  @override
  String toString() =>
      'AiQuotaSnapshot(tier: $tier, $tokensUsed/$tokensLimit, resets: $periodEnd)';
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

  /// Pull the latest quota state from the backend.
  Future<AiQuotaSnapshot?> refresh();

  /// Pre-flight check. Throws [AiQuotaExceededException] when the remaining
  /// balance cannot cover [estimate] tokens.
  ///
  /// Should be called before issuing an outbound AI request.
  Future<void> ensureBalance({int estimate = 500});

  /// Record that [tokens] were consumed by [feature].
  ///
  /// Invoked after each AI call completes (including partial/cancelled
  /// streams — see [GeminiProvider]). Implementations should be idempotent-ish
  /// and non-blocking from the caller's perspective (fire-and-forget is OK).
  Future<void> recordUsage(int tokens, String feature);

  /// Release any held resources.
  void dispose();
}
