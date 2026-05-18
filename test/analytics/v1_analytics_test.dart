// ============================================================================
// 📊 V1 ANALYTICS — Event constants + PurchaseTelemetryRecorder behaviour
//
// Locks the funnel schema:
//   tier_limit_hit → paywall_shown → purchase_pack | purchase_sub
// so a typo in event names doesn't silently drop data in the dashboard.
// ============================================================================

import 'package:fluera_engine/fluera_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('V1AnalyticsEvents — funnel canonical names', () {
    test('Funnel core events are the documented strings', () {
      expect(V1AnalyticsEvents.tierLimitHit, 'tier_limit_hit');
      expect(V1AnalyticsEvents.paywallShown, 'paywall_shown');
      expect(V1AnalyticsEvents.paywallDismissed, 'paywall_dismissed');
      expect(V1AnalyticsEvents.purchaseSubscription, 'purchase_sub');
      expect(V1AnalyticsEvents.purchasePack, 'purchase_pack');
      expect(V1AnalyticsEvents.purchaseRestored, 'purchase_restored');
      expect(V1AnalyticsEvents.purchaseFailed, 'purchase_failed');
    });

    test('Credit + voice quota signals are wire-compatible with backend', () {
      expect(V1AnalyticsEvents.creditsExhausted, 'credits_exhausted');
      expect(V1AnalyticsEvents.creditsSoftWarn, 'credits_soft_warn');
      expect(V1AnalyticsEvents.creditsMonthlyReset, 'credits_monthly_reset');
      expect(V1AnalyticsEvents.voiceQuotaExhausted, 'voice_quota_exhausted');
    });

    test('Trial promo events round out the funnel', () {
      expect(V1AnalyticsEvents.trialPromoShown, 'trial_promo_shown');
      expect(V1AnalyticsEvents.trialPromoAccepted, 'trial_promo_accepted');
      expect(V1AnalyticsEvents.trialPromoDismissed, 'trial_promo_dismissed');
    });

    test('all list covers every constant (dashboard schema source of truth)',
        () {
      // 14 events as of V1 launch (2026-05-14).
      expect(V1AnalyticsEvents.all.length, 14);
      expect(V1AnalyticsEvents.all.toSet().length, 14,
          reason: 'No duplicates in the events list');
    });
  });

  group('V1AnalyticsProps — canonical property keys', () {
    test('Funnel-critical props use snake_case strings', () {
      expect(V1AnalyticsProps.feature, 'feature');
      expect(V1AnalyticsProps.tier, 'tier');
      expect(V1AnalyticsProps.trigger, 'trigger');
      expect(V1AnalyticsProps.productId, 'product_id');
      expect(V1AnalyticsProps.packSku, 'pack_sku');
      expect(V1AnalyticsProps.tierAtPurchase, 'tier_at_purchase');
      expect(V1AnalyticsProps.startedAsTrial, 'started_as_trial');
      expect(V1AnalyticsProps.isAnnual, 'is_annual');
    });
  });

  group('PurchaseTelemetryRecorder — event format', () {
    late _CapturingTelemetry sink;
    late PurchaseTelemetryRecorder recorder;

    setUp(() {
      sink = _CapturingTelemetry();
      recorder = PurchaseTelemetryRecorder(sink: sink);
    });

    test('recordSubscriptionPurchase emits purchase_sub with all props', () {
      recorder.recordSubscriptionPurchase(const SubscriptionPurchaseEvent(
        tier: 'pro',
        productId: 'fluera.pro.yearly',
        isAnnual: true,
        storefront: PurchaseStorefront.appStore,
        currencyCode: 'EUR',
        grossPrice: 99.00,
        startedAsTrial: false,
        trigger: 'paywall_modal',
      ));
      expect(sink.events.length, 1);
      final entry = sink.events.first;
      expect(entry.name, V1AnalyticsEvents.purchaseSubscription);
      expect(entry.props['tier'], 'pro');
      expect(entry.props['product_id'], 'fluera.pro.yearly');
      expect(entry.props['is_annual'], isTrue);
      expect(entry.props['storefront'], 'appStore');
      expect(entry.props['currency'], 'EUR');
      expect(entry.props['gross_price'], 99.00);
      expect(entry.props['started_as_trial'], isFalse);
      expect(entry.props['trigger'], 'paywall_modal');
    });

    test('recordPackPurchase emits purchase_pack with tier_at_purchase', () {
      recorder.recordPackPurchase(const PackPurchaseEvent(
        packSku: 'fluera.spark.500',
        creditsGranted: 500,
        storefront: PurchaseStorefront.playStore,
        tierAtPurchase: 'plus',
        currencyCode: 'EUR',
        grossPrice: 2.99,
        trigger: 'badge_tap',
      ));
      final entry = sink.events.single;
      expect(entry.name, V1AnalyticsEvents.purchasePack);
      expect(entry.props['pack_sku'], 'fluera.spark.500');
      expect(entry.props['credits_granted'], 500);
      expect(entry.props['tier_at_purchase'], 'plus');
      expect(entry.props['storefront'], 'playStore');
      expect(entry.props['gross_price'], 2.99);
    });

    test('recordPurchaseFailed includes reason + product_id', () {
      recorder.recordPurchaseFailed(
        productId: 'fluera.plus.monthly',
        reason: 'cancelled',
        storefront: PurchaseStorefront.appStore,
      );
      final entry = sink.events.single;
      expect(entry.name, V1AnalyticsEvents.purchaseFailed);
      expect(entry.props['product_id'], 'fluera.plus.monthly');
      expect(entry.props['reason'], 'cancelled');
      expect(entry.props['storefront'], 'appStore');
    });

    test('recordSubscriptionRestored emits a dedicated event (no MRR drift)',
        () {
      recorder.recordSubscriptionRestored(
        tier: 'pro',
        storefront: PurchaseStorefront.appStore,
      );
      final entry = sink.events.single;
      expect(entry.name, V1AnalyticsEvents.purchaseRestored);
      expect(entry.props['tier'], 'pro');
    });

    test('default recorder is no-op (does not throw without a sink)', () {
      final defaultRec = PurchaseTelemetryRecorder();
      defaultRec.recordPackPurchase(const PackPurchaseEvent(
        packSku: 'fluera.spark.250',
        creditsGranted: 250,
        storefront: PurchaseStorefront.sandbox,
        tierAtPurchase: 'free',
      ));
      // No assertion — the test passes if no exception is thrown.
    });
  });

  group('TierGateController paywall telemetry', () {
    test('recordPaywallShown emits paywall_shown with feature + tier + trigger',
        () {
      final sink = _CapturingTelemetry();
      final gate = TierGateController(
        tier: FlueraSubscriptionTier.free,
        telemetry: sink,
      );

      gate.recordPaywallShown(
        feature: GatedFeature.ghostMapComparison,
        trigger: 'limit_dialog',
      );

      expect(sink.events.length, 1);
      expect(sink.events.first.name, V1AnalyticsEvents.paywallShown);
      expect(sink.events.first.props['feature'], 'ghostMapComparison');
      expect(sink.events.first.props['tier'], 'free');
      expect(sink.events.first.props['trigger'], 'limit_dialog');
    });

    test('recordPaywallDismissed emits paywall_dismissed', () {
      final sink = _CapturingTelemetry();
      final gate = TierGateController(
        tier: FlueraSubscriptionTier.plus,
        telemetry: sink,
      );

      gate.recordPaywallDismissed(
        feature: GatedFeature.timeTravel,
        trigger: 'badge_tap',
      );

      expect(sink.events.single.name, V1AnalyticsEvents.paywallDismissed);
      expect(sink.events.single.props['feature'], 'timeTravel');
      expect(sink.events.single.props['tier'], 'plus');
    });
  });
}

// ────────────────────────────────────────────────────────────────────────────
// Test harness
// ────────────────────────────────────────────────────────────────────────────

class _TelemetryEntry {
  final String name;
  final Map<String, Object?> props;
  _TelemetryEntry(this.name, this.props);
}

class _CapturingTelemetry implements TelemetryRecorder {
  final List<_TelemetryEntry> events = [];

  @override
  void logEvent(String name, {Map<String, Object?>? properties}) {
    events.add(_TelemetryEntry(name, properties ?? const {}));
  }
}
