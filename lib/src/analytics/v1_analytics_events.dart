// ============================================================================
// 📊 V1 ANALYTICS EVENTS — Canonical event names + property keys
//
// Single source of truth for the V1 launch funnel telemetry. Anywhere
// outside this file that emits an event by hand risks typo-induced data
// loss in the dashboard.
//
// Funnel sequence (plan §11):
//   tier_limit_hit → paywall_shown → purchase_pack | purchase_sub
//
// Plus side-channels: paywall_dismissed, purchase_restored, purchase_failed.
// ============================================================================

/// 📊 Canonical event names emitted across the V1 launch surface.
///
/// Both engine-side (`TierGateController`, `PurchaseTelemetryRecorder`)
/// and host-side analytics consumers SHOULD index against these constants
/// instead of raw strings, so renaming an event auto-propagates to the
/// dashboard.
abstract final class V1AnalyticsEvents {
  V1AnalyticsEvents._();

  // ── Funnel core ────────────────────────────────────────────────────────

  /// Emitted by `TierGateController` when the user hits a frequency / tier
  /// cap. Properties: `feature`, `tier`, `scope`, `remaining`.
  static const String tierLimitHit = 'tier_limit_hit';

  /// Emitted by the host when the upgrade paywall surface is actually
  /// rendered to the user. Properties: `feature`, `tier`, `trigger`.
  static const String paywallShown = 'paywall_shown';

  /// Emitted by the host when the user closes the paywall without buying.
  /// Properties: `feature`, `tier`, `trigger`.
  static const String paywallDismissed = 'paywall_dismissed';

  /// Subscription purchase succeeded (Plus / Pro mo / yr).
  static const String purchaseSubscription = 'purchase_sub';

  /// Spark Pack consumable purchase succeeded.
  static const String purchasePack = 'purchase_pack';

  /// Subscription restored on this device (transfer / reinstall).
  static const String purchaseRestored = 'purchase_restored';

  /// Purchase attempt failed (cancelled, network, store error, etc.).
  static const String purchaseFailed = 'purchase_failed';

  // ── Credit usage signals ───────────────────────────────────────────────

  /// Emitted when an AI call returned `AiCreditsExhaustedException`.
  /// Properties: `feature` (Ghost Map / Socratic / Exam / Chat), `tier`,
  /// `needed`, `available`.
  static const String creditsExhausted = 'credits_exhausted';

  /// Emitted when the user's monthly credits cross the 80 % threshold.
  /// Useful for "warn me before I run out" UX A/B.
  static const String creditsSoftWarn = 'credits_soft_warn';

  /// Emitted when the monthly bucket resets (rollover RPC fired).
  static const String creditsMonthlyReset = 'credits_monthly_reset';

  // ── Voice quota signals ────────────────────────────────────────────────

  /// Emitted when the user hits the monthly voice cap.
  /// Properties: `tier`, `minutesUsed`, `minutesLimit`, `requested`.
  static const String voiceQuotaExhausted = 'voice_quota_exhausted';

  // ── Trial offer ────────────────────────────────────────────────────────

  /// Emitted when the 7-day Plus trial promo is shown on first launch.
  /// Properties: `revenuecat_eligible` (bool).
  static const String trialPromoShown = 'trial_promo_shown';

  /// Emitted when the user accepts the trial.
  static const String trialPromoAccepted = 'trial_promo_accepted';

  /// Emitted when the user dismisses the trial promo without claiming.
  static const String trialPromoDismissed = 'trial_promo_dismissed';

  // ── Helper: all known event names (for dashboard schema validation) ────

  static const List<String> all = [
    tierLimitHit,
    paywallShown,
    paywallDismissed,
    purchaseSubscription,
    purchasePack,
    purchaseRestored,
    purchaseFailed,
    creditsExhausted,
    creditsSoftWarn,
    creditsMonthlyReset,
    voiceQuotaExhausted,
    trialPromoShown,
    trialPromoAccepted,
    trialPromoDismissed,
  ];
}

/// 📊 Canonical property keys shared across V1 events. Same rationale
/// as [V1AnalyticsEvents]: avoid `snake_case` vs `camelCase` drift.
abstract final class V1AnalyticsProps {
  V1AnalyticsProps._();

  static const String feature = 'feature';
  static const String tier = 'tier';
  static const String scope = 'scope';
  static const String trigger = 'trigger';
  static const String remaining = 'remaining';
  static const String storefront = 'storefront';
  static const String productId = 'product_id';
  static const String packSku = 'pack_sku';
  static const String creditsGranted = 'credits_granted';
  static const String tierAtPurchase = 'tier_at_purchase';
  static const String currency = 'currency';
  static const String grossPrice = 'gross_price';
  static const String isAnnual = 'is_annual';
  static const String startedAsTrial = 'started_as_trial';
  static const String reason = 'reason';
  static const String needed = 'needed';
  static const String available = 'available';
  static const String minutesUsed = 'minutes_used';
  static const String minutesLimit = 'minutes_limit';
  static const String requested = 'requested';
}
