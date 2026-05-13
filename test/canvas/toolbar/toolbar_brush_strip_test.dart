// ============================================================================
// 🔒 BRUSH STRIP TIER GATE — Free-tier paywall behaviour.
//
// Pins down the contract that protects the paywall from being trivially
// bypassed:
//   • Free users see the same pills as paying users (no quiet hiding) but
//     premium pills get a 🔒 badge and a dimmed icon.
//   • Tapping a locked pill on Free fires the upgrade prompt and does NOT
//     dispatch the preset selection (anti-fraud).
//   • Tapping any pill on Plus / Pro behaves as before (no badge, normal
//     dispatch).
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/canvas/fluera_canvas_config.dart';
import 'package:fluera_engine/src/canvas/toolbar/toolbar_brush_strip.dart';
import 'package:fluera_engine/src/drawing/models/brush_preset.dart';

Widget _harness(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(width: 800, height: 60, child: child),
    ),
  );
}

BrushPreset _firstFreePreset() => BrushPreset.defaultPresets
    .firstWhere((p) => BrushPreset.freePresetIds.contains(p.id));

BrushPreset _firstPremiumPreset() => BrushPreset.defaultPresets
    .firstWhere((p) => !BrushPreset.freePresetIds.contains(p.id));

void main() {
  group('ToolbarBrushStrip — Free-tier paywall gate', () {
    testWidgets('Tapping a locked preset fires onUpgradePrompt + skips selection',
        (tester) async {
      final selected = <String>[];
      final upgradeMessages = <String>[];
      final premium = _firstPremiumPreset();

      await tester.pumpWidget(_harness(ToolbarBrushStrip(
        presets: BrushPreset.defaultPresets,
        selectedPresetId: null,
        isPenActive: true,
        isDark: true,
        subscriptionTier: FlueraSubscriptionTier.free,
        onPresetSelected: (p) => selected.add(p.id),
        onUpgradePrompt: upgradeMessages.add,
      )));
      await tester.pump();

      await tester.tap(find.text(premium.icon).first);
      await tester.pump();

      expect(selected, isEmpty,
          reason: 'locked tap must not flow through to preset selection');
      expect(upgradeMessages, hasLength(1));
      expect(upgradeMessages.first, contains(premium.name));
    });

    testWidgets('Tapping a free preset still dispatches normally on Free tier',
        (tester) async {
      final selected = <String>[];
      final upgradeMessages = <String>[];
      final free = _firstFreePreset();

      await tester.pumpWidget(_harness(ToolbarBrushStrip(
        presets: BrushPreset.defaultPresets,
        selectedPresetId: null,
        isPenActive: true,
        isDark: true,
        subscriptionTier: FlueraSubscriptionTier.free,
        onPresetSelected: (p) => selected.add(p.id),
        onUpgradePrompt: upgradeMessages.add,
      )));
      await tester.pump();

      await tester.tap(find.text(free.icon).first);
      await tester.pump();

      expect(selected, [free.id]);
      expect(upgradeMessages, isEmpty);
    });

    testWidgets('Plus tier disables the gate — every preset selectable',
        (tester) async {
      final selected = <String>[];
      final upgradeMessages = <String>[];
      final premium = _firstPremiumPreset();

      await tester.pumpWidget(_harness(ToolbarBrushStrip(
        presets: BrushPreset.defaultPresets,
        selectedPresetId: null,
        isPenActive: true,
        isDark: true,
        subscriptionTier: FlueraSubscriptionTier.plus,
        onPresetSelected: (p) => selected.add(p.id),
        onUpgradePrompt: upgradeMessages.add,
      )));
      await tester.pump();

      await tester.tap(find.text(premium.icon).first);
      await tester.pump();

      expect(selected, [premium.id]);
      expect(upgradeMessages, isEmpty);
    });

    testWidgets('Lock badge renders only on locked Free pills', (tester) async {
      await tester.pumpWidget(_harness(ToolbarBrushStrip(
        presets: BrushPreset.defaultPresets,
        selectedPresetId: null,
        isPenActive: true,
        isDark: true,
        subscriptionTier: FlueraSubscriptionTier.free,
        onPresetSelected: (_) {},
        onUpgradePrompt: (_) {},
      )));
      await tester.pump();

      final lockedCount = BrushPreset.defaultPresets
          .where((p) => !BrushPreset.freePresetIds.contains(p.id))
          .length;

      // Each locked pill paints exactly one Icons.lock_rounded badge —
      // free pills paint none.
      expect(find.byIcon(Icons.lock_rounded), findsNWidgets(lockedCount));
    });

    testWidgets('Pro tier paints zero lock badges', (tester) async {
      await tester.pumpWidget(_harness(ToolbarBrushStrip(
        presets: BrushPreset.defaultPresets,
        selectedPresetId: null,
        isPenActive: true,
        isDark: true,
        subscriptionTier: FlueraSubscriptionTier.pro,
        onPresetSelected: (_) {},
        onUpgradePrompt: (_) {},
      )));
      await tester.pump();

      expect(find.byIcon(Icons.lock_rounded), findsNothing);
    });
  });
}
