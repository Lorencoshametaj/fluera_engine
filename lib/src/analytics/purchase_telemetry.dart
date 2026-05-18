// ============================================================================
// 📊 PURCHASE TELEMETRY — Funnel-friendly event format for IAP outcomes
//
// Separates subscription purchases (Plus / Pro mensili o annuali) from
// consumable Spark Pack purchases so the funnel SQL can distinguish:
//   • `purchase_sub` — ARPU / churn / cohort retention metrics
//   • `purchase_pack` — top-up frequency / peak-exam revenue spike
//
// Plan: .claude/plans/analizza-tutta-fluera-app-floating-pebble.md §11
//   "credit_exhausted{tier, feature} → paywall_shown → purchase_pack{sku}
//    OR purchase_sub{tier, sku}"
//
// Engine ships the abstract; the Fluera app injects an implementation that
// forwards to its analytics sink (Sentry, Mixpanel, Supabase telemetry).
// ============================================================================

import '../ai/telemetry_recorder.dart';

/// 📊 Identifies the storefront that completed the purchase.
enum PurchaseStorefront {
  /// Apple App Store (iOS / macOS).
  appStore,

  /// Google Play (Android).
  playStore,

  /// Stripe checkout (desktop, web fallback).
  stripe,

  /// RevenueCat-mediated test or sandbox transaction.
  sandbox,
}

/// 📊 Subscription purchase outcome.
class SubscriptionPurchaseEvent {
  /// Tier resolved after the entitlement update ('plus' / 'pro').
  final String tier;

  /// Storefront product id (e.g. `fluera.plus.monthly`).
  final String productId;

  /// Whether this is an annual plan (drives the 'save X%' label).
  final bool isAnnual;

  /// Storefront that processed the transaction.
  final PurchaseStorefront storefront;

  /// Optional ISO 4217 currency code (e.g. 'EUR') if surfaced by the SDK.
  final String? currencyCode;

  /// Optional gross price as decimal, e.g. `11.99`.
  final double? grossPrice;

  /// Whether the purchase started with the free trial.
  final bool startedAsTrial;

  /// Trigger that surfaced the paywall, e.g. `'limit_dialog'`, `'onboarding'`.
  /// Optional — falls back to `'unknown'` in telemetry.
  final String? trigger;

  const SubscriptionPurchaseEvent({
    required this.tier,
    required this.productId,
    required this.isAnnual,
    required this.storefront,
    this.currencyCode,
    this.grossPrice,
    this.startedAsTrial = false,
    this.trigger,
  });
}

/// 📊 Spark Pack consumable purchase outcome.
class PackPurchaseEvent {
  /// Storefront product id (`fluera.spark.250` / `fluera.spark.500`).
  final String packSku;

  /// Credits granted by the pack (250 / 500).
  final int creditsGranted;

  final PurchaseStorefront storefront;

  /// Optional ISO 4217 currency code.
  final String? currencyCode;

  /// Optional gross price as decimal.
  final double? grossPrice;

  /// Tier the user is on at purchase time (so the funnel can tell
  /// "Plus user buys top-up" from "Free user top-ups before subscribing").
  final String tierAtPurchase;

  /// Surface that triggered the purchase flow, e.g. `'badge_tap'` or
  /// `'credits_exhausted_dialog'`.
  final String? trigger;

  const PackPurchaseEvent({
    required this.packSku,
    required this.creditsGranted,
    required this.storefront,
    required this.tierAtPurchase,
    this.currencyCode,
    this.grossPrice,
    this.trigger,
  });
}

/// 📊 Recorder for purchase telemetry events. Defaults to no-op so the
/// engine ships usable without an analytics backend.
class PurchaseTelemetryRecorder {
  PurchaseTelemetryRecorder({TelemetryRecorder? sink})
      : _sink = sink ?? TelemetryRecorder.noop;

  final TelemetryRecorder _sink;

  /// Event names. Exposed as constants so the host's analytics dashboard
  /// can index them and tests can assert on the wire format.
  static const String eventSubscriptionPurchase = 'purchase_sub';
  static const String eventPackPurchase = 'purchase_pack';
  static const String eventSubscriptionRestored = 'purchase_restored';
  static const String eventPurchaseFailed = 'purchase_failed';

  /// Record a subscription purchase. Emit AFTER RevenueCat confirms the
  /// entitlement so the tier field reflects the new state.
  void recordSubscriptionPurchase(SubscriptionPurchaseEvent event) {
    _sink.logEvent(eventSubscriptionPurchase, properties: {
      'tier': event.tier,
      'product_id': event.productId,
      'is_annual': event.isAnnual,
      'storefront': event.storefront.name,
      if (event.currencyCode != null) 'currency': event.currencyCode,
      if (event.grossPrice != null) 'gross_price': event.grossPrice,
      'started_as_trial': event.startedAsTrial,
      'trigger': event.trigger ?? 'unknown',
    });
  }

  /// Record a Spark Pack consumable purchase. Emit AFTER the server-side
  /// `add_pack_credits` RPC succeeds (credits actually in the bucket).
  void recordPackPurchase(PackPurchaseEvent event) {
    _sink.logEvent(eventPackPurchase, properties: {
      'pack_sku': event.packSku,
      'credits_granted': event.creditsGranted,
      'storefront': event.storefront.name,
      if (event.currencyCode != null) 'currency': event.currencyCode,
      if (event.grossPrice != null) 'gross_price': event.grossPrice,
      'tier_at_purchase': event.tierAtPurchase,
      'trigger': event.trigger ?? 'unknown',
    });
  }

  /// Record a restored subscription (device transfer / reinstall).
  /// Distinct from [recordSubscriptionPurchase] so MRR cohort analysis
  /// doesn't double-count.
  void recordSubscriptionRestored({
    required String tier,
    required PurchaseStorefront storefront,
  }) {
    _sink.logEvent(eventSubscriptionRestored, properties: {
      'tier': tier,
      'storefront': storefront.name,
    });
  }

  /// Record a failed purchase attempt (network / cancelled / store error).
  /// [reason] is the failure category, e.g. `'cancelled'`, `'network'`,
  /// `'already_owned'`, `'pending'`, `'unknown_error'`.
  void recordPurchaseFailed({
    required String productId,
    required String reason,
    PurchaseStorefront? storefront,
    String? trigger,
  }) {
    _sink.logEvent(eventPurchaseFailed, properties: {
      'product_id': productId,
      'reason': reason,
      if (storefront != null) 'storefront': storefront.name,
      'trigger': trigger ?? 'unknown',
    });
  }
}
