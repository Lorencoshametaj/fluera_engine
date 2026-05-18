// ============================================================================
// 💎 NO-OP AI CREDITS CONTROLLER — Engine default when no host is injected
//
// Lets the SDK build, run and ship demos without requiring the app layer to
// stand up Supabase + RevenueCat. Every operation succeeds with empty state.
//
// Tests can either use this directly (when they don't care about credits)
// or substitute a fake implementation.
// ============================================================================

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'ai_credits_controller.dart';
import 'ai_credits_costs.dart';

/// 💎 No-op [AiCreditsController]. Always succeeds, never throws.
///
/// Returns an effectively unlimited snapshot so call sites can run their
/// happy path without special-casing the absence of a real controller.
class NoopAiCreditsController implements AiCreditsController {
  NoopAiCreditsController();

  static const _unlimited = 1 << 30;

  final ValueNotifier<AiCreditsSnapshot?> _credits =
      ValueNotifier<AiCreditsSnapshot?>(
    AiCreditsSnapshot(
      monthlyCredits: _unlimited,
      packCredits: 0,
      tier: 'free',
      // Far enough out that no UI shows a reset countdown.
      monthlyResetAt: DateTime.utc(2100, 1, 1),
    ),
  );

  final StreamController<AiCreditsExhaustedException> _exhaustedCtrl =
      StreamController<AiCreditsExhaustedException>.broadcast();
  final StreamController<AiCreditsRateLimitedException> _rateLimitedCtrl =
      StreamController<AiCreditsRateLimitedException>.broadcast();

  @override
  ValueListenable<AiCreditsSnapshot?> get credits => _credits;

  @override
  Stream<AiCreditsExhaustedException> get exhaustedEvents =>
      _exhaustedCtrl.stream;

  @override
  Stream<AiCreditsRateLimitedException> get rateLimitedEvents =>
      _rateLimitedCtrl.stream;

  @override
  Future<AiCreditsSnapshot?> refresh() async => _credits.value;

  @override
  Future<AiCreditsReceipt> consume(AiCreditFeature feature) async {
    final cost = AiCreditsCosts.costOf(feature);
    final snapshot = _credits.value ??
        AiCreditsSnapshot(
          monthlyCredits: _unlimited,
          packCredits: 0,
          tier: 'free',
          monthlyResetAt: DateTime.utc(2100, 1, 1),
        );
    return AiCreditsReceipt(
      idempotencyKey: 'noop-${DateTime.now().microsecondsSinceEpoch}',
      feature: feature,
      cost: cost,
      snapshotAfter: snapshot,
    );
  }

  @override
  Future<void> refund(String idempotencyKey) async {}

  @override
  Future<void> applyPackPurchase({
    required String packSku,
    required String purchaseToken,
  }) async {}

  @override
  Future<void> updateTier(String tier) async {
    final current = _credits.value;
    if (current != null) {
      _credits.value = current.copyWith(tier: tier);
    }
  }

  // Background-AI cap is a no-op here: the SDK without a host doesn't
  // enforce the Free=1000 / Plus=10000 / Pro=50000 monthly cluster cap,
  // so every call may proceed and the event stream stays empty.
  @override
  Future<bool> recordBackgroundCall({required int clusterCount}) async =>
      true;

  @override
  Stream<BackgroundAiCapExceededException> get backgroundCapEvents =>
      const Stream.empty();

  // Preflight peek — no server to query, so we report an always-allowed
  // snapshot consistent with the no-op cap behaviour above.
  @override
  Future<BackgroundAiPeek?> peekBackgroundStatus() async =>
      const BackgroundAiPeek(
        ok: true,
        allowed: true,
        error: null,
        tier: 'free',
        used: 0,
        cap: _unlimited,
      );

  @override
  void dispose() {
    _credits.dispose();
    _exhaustedCtrl.close();
    _rateLimitedCtrl.close();
  }
}
