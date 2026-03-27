import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/drawing/models/surface_material.dart';

void main() {
  // ===========================================================================
  // SurfaceMaterial
  // ===========================================================================

  group('SurfaceMaterial', () {
    // ── Default constructor ──────────────────────────────────────────

    group('default values', () {
      test('default constructor has sensible defaults', () {
        const s = SurfaceMaterial();
        expect(s.roughness, 0.15);
        expect(s.absorption, 0.4);
        expect(s.pigmentRetention, 0.8);
        expect(s.grainTexture, 'none');
        expect(s.grainScale, 1.0);
      });
    });

    // ── Presets ──────────────────────────────────────────────────────

    group('presets', () {
      test('glass is smooth and non-absorbent', () {
        const s = SurfaceMaterial.glass();
        expect(s.roughness, 0.0);
        expect(s.absorption, 0.0);
        expect(s.pigmentRetention, 0.3);
        expect(s.grainTexture, 'none');
      });

      test('smooth paper has slight roughness', () {
        const s = SurfaceMaterial.smoothPaper();
        expect(s.roughness, 0.15);
        expect(s.absorption, 0.4);
        expect(s.grainTexture, 'pencilGrain');
      });

      test('watercolor paper is absorbent with medium roughness', () {
        const s = SurfaceMaterial.watercolorPaper();
        expect(s.roughness, 0.6);
        expect(s.absorption, 0.8);
        expect(s.grainTexture, 'watercolor');
      });

      test('canvas has high roughness', () {
        const s = SurfaceMaterial.canvas();
        expect(s.roughness, 0.8);
        expect(s.absorption, 0.5);
        expect(s.grainTexture, 'canvas');
        expect(s.grainScale, 1.5);
      });

      test('raw wood is very rough with low absorption', () {
        const s = SurfaceMaterial.rawWood();
        expect(s.roughness, 0.9);
        expect(s.absorption, 0.3);
        expect(s.grainTexture, 'kraft');
        expect(s.grainScale, 2.0);
      });

      test('chalkboard has moderate roughness and very low absorption', () {
        const s = SurfaceMaterial.chalkboard();
        expect(s.roughness, 0.4);
        expect(s.absorption, 0.05);
        expect(s.grainTexture, 'charcoal');
      });
    });

    // ── Equality ─────────────────────────────────────────────────────

    group('equality', () {
      test('two default instances are equal', () {
        const a = SurfaceMaterial();
        const b = SurfaceMaterial();
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });

      test('identical returns true for same reference', () {
        const a = SurfaceMaterial();
        expect(identical(a, a), isTrue);
      });

      test('different roughness are not equal', () {
        const a = SurfaceMaterial(roughness: 0.5);
        const b = SurfaceMaterial(roughness: 0.9);
        expect(a, isNot(equals(b)));
      });

      test('same preset values are equal', () {
        const a = SurfaceMaterial.glass();
        const b = SurfaceMaterial.glass();
        expect(a, equals(b));
      });

      test('not equal to other types', () {
        const a = SurfaceMaterial();
        // ignore: unrelated_type_equality_checks
        expect(a == 42, isFalse);
      });
    });

    // ── copyWith ─────────────────────────────────────────────────────

    group('copyWith', () {
      test('copies all fields when nothing overridden', () {
        const original = SurfaceMaterial.watercolorPaper();
        final copy = original.copyWith();
        expect(copy, equals(original));
      });

      test('overrides single field', () {
        const original = SurfaceMaterial.smoothPaper();
        final copy = original.copyWith(roughness: 0.9);
        expect(copy.roughness, 0.9);
        expect(copy.absorption, original.absorption); // unchanged
        expect(copy.grainTexture, original.grainTexture); // unchanged
      });

      test('overrides multiple fields', () {
        const original = SurfaceMaterial();
        final copy = original.copyWith(
          roughness: 0.7,
          absorption: 0.9,
          grainTexture: 'canvas',
        );
        expect(copy.roughness, 0.7);
        expect(copy.absorption, 0.9);
        expect(copy.grainTexture, 'canvas');
        expect(copy.pigmentRetention, original.pigmentRetention);
      });
    });

    // ── Serialization ────────────────────────────────────────────────

    group('toJson / fromJson', () {
      test('round-trips default values', () {
        const original = SurfaceMaterial();
        final json = original.toJson();
        final restored = SurfaceMaterial.fromJson(json);
        expect(restored.roughness, original.roughness);
        expect(restored.absorption, original.absorption);
        expect(restored.pigmentRetention, original.pigmentRetention);
        expect(restored.grainTexture, original.grainTexture);
        expect(restored.grainScale, original.grainScale);
      });

      test('round-trips all presets', () {
        final presets = [
          const SurfaceMaterial.glass(),
          const SurfaceMaterial.smoothPaper(),
          const SurfaceMaterial.watercolorPaper(),
          const SurfaceMaterial.canvas(),
          const SurfaceMaterial.rawWood(),
          const SurfaceMaterial.chalkboard(),
        ];
        for (final preset in presets) {
          final json = preset.toJson();
          final restored = SurfaceMaterial.fromJson(json);
          expect(restored.roughness, preset.roughness);
          expect(restored.absorption, preset.absorption);
          expect(restored.pigmentRetention, preset.pigmentRetention);
          expect(restored.grainTexture, preset.grainTexture);
          expect(restored.grainScale, preset.grainScale);
        }
      });

      test('fromJson with null returns defaults', () {
        final restored = SurfaceMaterial.fromJson(null);
        expect(restored.roughness, 0.15);
        expect(restored.absorption, 0.4);
      });

      test('fromJson with empty map returns defaults', () {
        final restored = SurfaceMaterial.fromJson({});
        expect(restored.roughness, 0.15);
        expect(restored.absorption, 0.4);
      });

      test('omits default grainTexture and grainScale from JSON', () {
        const s = SurfaceMaterial.glass();
        final json = s.toJson();
        expect(json.containsKey('gt'), isFalse); // grainTexture == 'none'
        expect(json.containsKey('gs'), isFalse); // grainScale == 1.0
      });

      test('includes non-default grainTexture', () {
        const s = SurfaceMaterial.canvas();
        final json = s.toJson();
        expect(json['gt'], 'canvas');
        expect(json['gs'], 1.5);
      });

      test('round-trips custom values', () {
        const original = SurfaceMaterial(
          roughness: 0.42,
          absorption: 0.73,
          pigmentRetention: 0.55,
          grainTexture: 'kraft',
          grainScale: 2.5,
        );
        final json = original.toJson();
        final restored = SurfaceMaterial.fromJson(json);
        expect(restored.roughness, original.roughness);
        expect(restored.absorption, original.absorption);
        expect(restored.pigmentRetention, original.pigmentRetention);
        expect(restored.grainTexture, original.grainTexture);
        expect(restored.grainScale, original.grainScale);
      });
    });

    // ── toString ─────────────────────────────────────────────────────

    group('toString', () {
      test('contains all properties', () {
        const s = SurfaceMaterial.glass();
        final str = s.toString();
        expect(str, contains('roughness'));
        expect(str, contains('absorption'));
        expect(str, contains('SurfaceMaterial'));
      });
    });
  });

  // ===========================================================================
  // MaterialModifiers
  // ===========================================================================

  group('MaterialModifiers', () {
    test('identity has all values at 1.0 (except grain at 0)', () {
      const m = MaterialModifiers.identity;
      expect(m.opacityMultiplier, 1.0);
      expect(m.widthMultiplier, 1.0);
      expect(m.grainIntensity, 0.0);
      expect(m.spreadFactor, 1.0);
    });

    test('toString contains all properties', () {
      const m = MaterialModifiers.identity;
      final str = m.toString();
      expect(str, contains('opacity'));
      expect(str, contains('width'));
      expect(str, contains('grain'));
      expect(str, contains('spread'));
    });
  });

  // ===========================================================================
  // computeModifiers
  // ===========================================================================

  group('computeModifiers', () {
    test('glass produces minimal modifiers', () {
      const s = SurfaceMaterial.glass();
      final m = s.computeModifiers(pressure: 0.5, velocity: 500);
      expect(m.grainIntensity, 0.0); // no roughness = no grain
      expect(m.spreadFactor, 1.0); // no absorption = no spread
      expect(m.opacityMultiplier, 1.0); // no absorption = full opacity
      expect(m.widthMultiplier, 1.0); // no roughness = no width change
    });

    test('rough surface increases grain intensity', () {
      const smooth = SurfaceMaterial(roughness: 0.0);
      const rough = SurfaceMaterial(roughness: 0.9);
      final mSmooth = smooth.computeModifiers(pressure: 0.5, velocity: 500);
      final mRough = rough.computeModifiers(pressure: 0.5, velocity: 500);
      expect(mRough.grainIntensity, greaterThan(mSmooth.grainIntensity));
    });

    test('high pressure reduces grain intensity', () {
      const s = SurfaceMaterial(roughness: 0.8);
      final lowPress = s.computeModifiers(pressure: 0.1, velocity: 500);
      final highPress = s.computeModifiers(pressure: 1.0, velocity: 500);
      expect(highPress.grainIntensity, lessThan(lowPress.grainIntensity));
    });

    test('absorbent surface increases spread', () {
      const low = SurfaceMaterial(absorption: 0.0);
      const high = SurfaceMaterial(absorption: 1.0);
      final mLow = low.computeModifiers(pressure: 0.5, velocity: 500);
      final mHigh = high.computeModifiers(pressure: 0.5, velocity: 500);
      expect(mHigh.spreadFactor, greaterThan(mLow.spreadFactor));
    });

    test('absorbent surface slightly reduces opacity', () {
      const low = SurfaceMaterial(absorption: 0.0);
      const high = SurfaceMaterial(absorption: 1.0);
      final mLow = low.computeModifiers(pressure: 0.5, velocity: 500);
      final mHigh = high.computeModifiers(pressure: 0.5, velocity: 500);
      expect(mHigh.opacityMultiplier, lessThan(mLow.opacityMultiplier));
    });

    test('all modifiers are within valid ranges', () {
      final presets = [
        const SurfaceMaterial.glass(),
        const SurfaceMaterial.smoothPaper(),
        const SurfaceMaterial.watercolorPaper(),
        const SurfaceMaterial.canvas(),
        const SurfaceMaterial.rawWood(),
        const SurfaceMaterial.chalkboard(),
      ];
      for (final s in presets) {
        for (final p in [0.0, 0.5, 1.0]) {
          for (final v in [0.0, 500.0, 2000.0]) {
            final m = s.computeModifiers(pressure: p, velocity: v);
            expect(m.opacityMultiplier, inInclusiveRange(0.0, 2.0));
            expect(m.widthMultiplier, inInclusiveRange(0.5, 2.0));
            expect(m.grainIntensity, inInclusiveRange(0.0, 1.0));
            expect(m.spreadFactor, inInclusiveRange(0.5, 2.0));
          }
        }
      }
    });

    test('fast velocity reduces absorption effect', () {
      const s = SurfaceMaterial(absorption: 0.8);
      final slow = s.computeModifiers(pressure: 0.5, velocity: 0.0);
      final fast = s.computeModifiers(pressure: 0.5, velocity: 2000.0);
      expect(fast.spreadFactor, lessThan(slow.spreadFactor));
    });

    test('rough surface slightly increases width', () {
      const smooth = SurfaceMaterial(roughness: 0.0);
      const rough = SurfaceMaterial(roughness: 1.0);
      final mSmooth = smooth.computeModifiers(pressure: 0.5, velocity: 500);
      final mRough = rough.computeModifiers(pressure: 0.5, velocity: 500);
      expect(mRough.widthMultiplier, greaterThan(mSmooth.widthMultiplier));
    });
  });
}
