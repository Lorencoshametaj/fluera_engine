// ============================================================================
// 🔒 BRUSH PRESET FREE GATE INVARIANT
//
// Regression test for the 2026-05-16 bug: the toolbar strip gated brushes
// on `BrushPreset.freePresetIds` (preset id) but `_applyBrushPreset` in
// FlueraCanvasScreen gated on `V1FeatureGate.isBrushFree` (pen type) — the
// two whitelists were out of sync, so tapping the (free) Highlighter
// triggered the paywall even though the strip rendered it as free.
//
// This test pins the invariant: every id in `freePresetIds` must:
//   • resolve to a real preset in `builtInPresets`
//   • have a pen type that the back-compat gate `V1FeatureGate.freeBrushes`
//     still considers free
// so any future drift fails fast at CI time, not on a user device.
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/config/v1_feature_gate.dart';
import 'package:fluera_engine/src/drawing/models/brush_preset.dart';

void main() {
  group('Free brush gate — id ↔ pen type alignment', () {
    test('every freePresetIds entry resolves to a real builtin preset', () {
      for (final id in BrushPreset.freePresetIds) {
        final hit =
            BrushPreset.builtInPresets.where((p) => p.id == id).toList();
        expect(hit, hasLength(1),
            reason: 'free preset id "$id" must map to exactly one builtin');
      }
    });

    test('every free preset pen type is also free in V1FeatureGate', () {
      // Back-compat: hosts that gate on pen type via V1FeatureGate.isBrushFree
      // must agree with the id-based gate. If we add a new free preset whose
      // pen type isn't in `freeBrushes`, this fires.
      for (final id in BrushPreset.freePresetIds) {
        final preset = BrushPreset.builtInPresets.firstWhere((p) => p.id == id);
        expect(V1FeatureGate.freeBrushes.contains(preset.penType), isTrue,
            reason:
                'preset "$id" has penType ${preset.penType}; add it to '
                'V1FeatureGate.freeBrushes or remove from freePresetIds');
      }
    });

    test('Highlighter is free (was the trigger for the 2026-05-16 bug)', () {
      // Sanity: explicit pin so a refactor that drops the highlighter id
      // from the free list trips loud.
      expect(BrushPreset.freePresetIds.contains('builtin_highlighter'), isTrue);
      final highlighter = BrushPreset.builtInPresets
          .firstWhere((p) => p.id == 'builtin_highlighter');
      expect(V1FeatureGate.freeBrushes.contains(highlighter.penType), isTrue);
    });
  });
}
