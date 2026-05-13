// Widget-level test for the Cross-Zone Bridge tier gate (Passo 9, Fase 5.6).
//
// We can't mount the full FlueraCanvasScreen here (requires GPU, MethodChannels,
// l10n, native plugins). Instead this test isolates the *gate-check + SnackBar*
// pattern the Cross-Zone handler uses, asserting that:
//   • Free tier → `crossDomainInteractive` is blocked and the
//     upgrade SnackBar surfaces.
//   • Pro tier → the gate is unlimited and no SnackBar appears; the
//     gated action is allowed to run.
//
// Why a focused test? The actual `_checkTierGate` helper is a Dart `part of`
// the canvas screen, not directly importable. The behavior we care about
// — "Free is blocked, Pro is unlimited" + the SnackBar surface — lives
// inside [TierGateController.checkFeature] + a `ScaffoldMessenger.showSnackBar`
// call. We exercise that exact composition.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluera_engine/src/canvas/ai/tier_gate_controller.dart';
import 'package:fluera_engine/src/canvas/fluera_canvas_config.dart';

void main() {
  group('Cross-Zone Bridge tier gate', () {
    Widget buildHarness({
      required FlueraSubscriptionTier tier,
      required ValueChanged<int> onActionFired,
    }) {
      final gate = TierGateController(tier: tier);
      addTearDown(gate.dispose);
      int actionCount = 0;
      return MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () {
                    final result = gate.checkFeature(
                      GatedFeature.crossDomainInteractive,
                    );
                    if (!result.allowed) {
                      if (result.upgradeMessage != null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(result.upgradeMessage!),
                            behavior: SnackBarBehavior.floating,
                            backgroundColor: const Color(0xFF6A1B9A),
                          ),
                        );
                      }
                      return;
                    }
                    gate.recordUsage(GatedFeature.crossDomainInteractive);
                    actionCount++;
                    onActionFired(actionCount);
                  },
                  child: const Text('Suggeriscimi ponti'),
                ),
              ),
            );
          },
        ),
      );
    }

    testWidgets(
        'Free tier → SnackBar with upgrade prompt, gated action does not fire',
        (tester) async {
      int firedCount = 0;
      await tester.pumpWidget(buildHarness(
        tier: FlueraSubscriptionTier.free,
        onActionFired: (n) => firedCount = n,
      ));

      await tester.tap(find.byType(ElevatedButton));
      await tester.pump(); // SnackBar enter animation start

      // SnackBar is on-screen with the upgrade copy.
      expect(
        find.textContaining('Pro'),
        findsOneWidget,
        reason: 'Free users must see the Pro upgrade prompt',
      );
      // The gated action did not fire.
      expect(firedCount, 0,
          reason: 'Free tier must not execute the gated action');
    });

    testWidgets(
        'Pro tier → no SnackBar, gated action fires every time',
        (tester) async {
      int firedCount = 0;
      await tester.pumpWidget(buildHarness(
        tier: FlueraSubscriptionTier.pro,
        onActionFired: (n) => firedCount = n,
      ));

      // Tap 3 times — Pro is unlimited.
      for (int i = 0; i < 3; i++) {
        await tester.tap(find.byType(ElevatedButton));
        await tester.pump();
      }

      expect(find.byType(SnackBar), findsNothing);
      expect(firedCount, 3,
          reason: 'Pro tier must execute the gated action without limits');
    });

    test('TierGateController weekly limit for crossDomainInteractive is 0',
        () {
      // Sanity: the gate is Pro-only by definition (0/week in Free).
      // This is a compile-time guarantee read off the public surface, so
      // a regression that flips the limit (e.g. promotional unlock) is loud.
      final freeGate = TierGateController(tier: FlueraSubscriptionTier.free);
      addTearDown(freeGate.dispose);
      final result =
          freeGate.checkFeature(GatedFeature.crossDomainInteractive);
      expect(result.allowed, isFalse);
      expect(result.blockedFeature, GatedFeature.crossDomainInteractive);
      expect(result.upgradeMessage, isNotNull);
      expect(result.upgradeMessage, contains('Pro'));
    });

    test('Plus tier is treated as Pro for the gate (unlimited)', () {
      final plusGate = TierGateController(tier: FlueraSubscriptionTier.plus);
      addTearDown(plusGate.dispose);
      final result =
          plusGate.checkFeature(GatedFeature.crossDomainInteractive);
      expect(result.allowed, isTrue,
          reason:
              'Plus/Pro tiers must have unlimited cross-domain interaction');
    });
  });
}
