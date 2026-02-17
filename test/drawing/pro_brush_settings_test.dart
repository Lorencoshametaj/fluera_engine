import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/drawing/models/pro_brush_settings.dart';

void main() {
  // =========================================================================
  // ProBrushSettings
  // =========================================================================

  group('ProBrushSettings', () {
    // ── Defaults ───────────────────────────────────────────────────────

    group('default values', () {
      test('default constructor produces isDefault == true', () {
        const settings = ProBrushSettings();
        expect(settings.isDefault, isTrue);
      });

      test('defaultSettings singleton is default', () {
        expect(ProBrushSettings.defaultSettings.isDefault, isTrue);
      });

      test('fountain pen defaults', () {
        const s = ProBrushSettings();
        expect(s.fountainMinPressure, 0.35);
        expect(s.fountainMaxPressure, 1.5);
        expect(s.fountainTaperEntry, 6);
        expect(s.fountainTaperExit, 8);
        expect(s.fountainVelocityInfluence, 0.6);
        expect(s.fountainCurvatureInfluence, 0.25);
        expect(s.fountainTiltEnable, isTrue);
        expect(s.fountainTiltInfluence, 1.2);
        expect(s.fountainTiltEllipseRatio, 2.5);
        expect(s.fountainJitter, 0.08);
        expect(s.fountainSmoothPath, isTrue);
        expect(s.fountainThinning, 0.5);
        expect(s.fountainNibAngleDeg, 30.0);
      });

      test('pencil defaults', () {
        const s = ProBrushSettings();
        expect(s.pencilBaseOpacity, 0.4);
        expect(s.pencilMaxOpacity, 0.8);
        expect(s.pencilBlurRadius, 0.3);
        expect(s.pencilMinPressure, 0.5);
        expect(s.pencilMaxPressure, 1.2);
      });

      test('highlighter defaults', () {
        const s = ProBrushSettings();
        expect(s.highlighterOpacity, 0.35);
        expect(s.highlighterWidthMultiplier, 3.0);
      });

      test('ballpoint defaults', () {
        const s = ProBrushSettings();
        expect(s.ballpointMinPressure, 0.7);
        expect(s.ballpointMaxPressure, 1.1);
      });

      test('texture defaults', () {
        const s = ProBrushSettings();
        expect(s.textureType, 'none');
        expect(s.textureIntensity, 0.5);
      });

      test('stamp defaults are disabled', () {
        const s = ProBrushSettings();
        expect(s.stampEnabled, isFalse);
        expect(s.stampSpacing, 0.25);
        expect(s.stampEraserMode, isFalse);
      });

      test('stabilizer off by default', () {
        const s = ProBrushSettings();
        expect(s.stabilizerLevel, 0);
      });

      test('wide gamut off by default', () {
        const s = ProBrushSettings();
        expect(s.useWideGamut, isFalse);
      });
    });

    // ── isDefault ──────────────────────────────────────────────────────

    group('isDefault', () {
      test('changing a fountain parameter makes isDefault false', () {
        const s = ProBrushSettings(fountainMinPressure: 0.5);
        expect(s.isDefault, isFalse);
      });

      test('changing a pencil parameter makes isDefault false', () {
        const s = ProBrushSettings(pencilBaseOpacity: 0.7);
        expect(s.isDefault, isFalse);
      });

      test('enabling stamp makes isDefault false', () {
        const s = ProBrushSettings(stampEnabled: true);
        expect(s.isDefault, isFalse);
      });

      test('enabling wide gamut makes isDefault false', () {
        const s = ProBrushSettings(useWideGamut: true);
        expect(s.isDefault, isFalse);
      });

      test('changing stabilizer makes isDefault false', () {
        const s = ProBrushSettings(stabilizerLevel: 5);
        expect(s.isDefault, isFalse);
      });

      test('changing texture type makes isDefault false', () {
        const s = ProBrushSettings(textureType: 'pencilGrain');
        expect(s.isDefault, isFalse);
      });
    });

    // ── Equality ───────────────────────────────────────────────────────

    group('equality', () {
      test('two default instances are equal', () {
        const a = ProBrushSettings();
        const b = ProBrushSettings();
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });

      test('different settings are not equal', () {
        const a = ProBrushSettings();
        const b = ProBrushSettings(fountainMinPressure: 0.9);
        expect(a, isNot(equals(b)));
      });

      test('identical returns true for same reference', () {
        const a = ProBrushSettings();
        expect(identical(a, a), isTrue);
      });

      test('not equal to other types', () {
        const a = ProBrushSettings();
        expect(a == 42, isFalse);
      });
    });

    // ── copyWith ───────────────────────────────────────────────────────

    group('copyWith', () {
      test('copies all fields when nothing overridden', () {
        const original = ProBrushSettings();
        final copy = original.copyWith();
        expect(copy, equals(original));
        expect(copy.isDefault, isTrue);
      });

      test('overrides fountain parameters', () {
        const original = ProBrushSettings();
        final copy = original.copyWith(
          fountainMinPressure: 0.1,
          fountainMaxPressure: 2.0,
          fountainTaperEntry: 10,
        );
        expect(copy.fountainMinPressure, 0.1);
        expect(copy.fountainMaxPressure, 2.0);
        expect(copy.fountainTaperEntry, 10);
        expect(copy.isDefault, isFalse);
      });

      test('overrides pencil parameters', () {
        const original = ProBrushSettings();
        final copy = original.copyWith(pencilBaseOpacity: 0.9);
        expect(copy.pencilBaseOpacity, 0.9);
        expect(copy.pencilMaxOpacity, 0.8); // unchanged
      });

      test('overrides stamp parameters', () {
        const original = ProBrushSettings();
        final copy = original.copyWith(
          stampEnabled: true,
          stampSpacing: 0.5,
          stampFlow: 0.8,
        );
        expect(copy.stampEnabled, isTrue);
        expect(copy.stampSpacing, 0.5);
        expect(copy.stampFlow, 0.8);
      });

      test('overrides stabilizer and gamut', () {
        const original = ProBrushSettings();
        final copy = original.copyWith(stabilizerLevel: 7, useWideGamut: true);
        expect(copy.stabilizerLevel, 7);
        expect(copy.useWideGamut, isTrue);
      });
    });

    // ── Serialization ──────────────────────────────────────────────────

    group('toJson / fromJson', () {
      test('round-trips default settings', () {
        const original = ProBrushSettings();
        final json = original.toJson();
        final restored = ProBrushSettings.fromJson(json);
        expect(restored, equals(original));
      });

      test('includes format version', () {
        const s = ProBrushSettings();
        final json = s.toJson();
        expect(json['sfv'], ProBrushSettings.currentFormatVersion);
      });

      test('round-trips custom fountain settings', () {
        const original = ProBrushSettings(
          fountainMinPressure: 0.1,
          fountainMaxPressure: 2.5,
          fountainTaperEntry: 12,
          fountainNibAngleDeg: 45.0,
        );
        final json = original.toJson();
        final restored = ProBrushSettings.fromJson(json);
        expect(restored.fountainMinPressure, 0.1);
        expect(restored.fountainMaxPressure, 2.5);
        expect(restored.fountainTaperEntry, 12);
        expect(restored.fountainNibAngleDeg, 45.0);
      });

      test('omits default stamp values from JSON', () {
        const s = ProBrushSettings();
        final json = s.toJson();
        // Default stamp parameters should not be in JSON
        expect(json.containsKey('stmE'), isFalse); // stampEnabled == false
        expect(json.containsKey('stmSJ'), isFalse); // stampSizeJitter == 0
      });

      test('includes non-default stamp values', () {
        const s = ProBrushSettings(stampEnabled: true, stampSizeJitter: 0.3);
        final json = s.toJson();
        expect(json['stmE'], isTrue);
        expect(json['stmSJ'], 0.3);
      });

      test('fromJson with null returns defaults', () {
        final restored = ProBrushSettings.fromJson(null);
        expect(restored.isDefault, isTrue);
      });

      test('fromJson with empty map returns defaults', () {
        final restored = ProBrushSettings.fromJson({});
        expect(restored.fountainMinPressure, 0.35);
        expect(restored.pencilBaseOpacity, 0.4);
      });

      test('ballpoint pressure is clamped on deserialization', () {
        final json = {'bMinP': 0.1, 'bMaxP': 2.5}; // out of range
        final restored = ProBrushSettings.fromJson(json);
        expect(restored.ballpointMinPressure, 0.5); // clamped to min
        expect(restored.ballpointMaxPressure, 1.5); // clamped to max
      });

      test('round-trips texture settings', () {
        const original = ProBrushSettings(
          textureType: 'charcoal',
          textureIntensity: 0.8,
        );
        final json = original.toJson();
        final restored = ProBrushSettings.fromJson(json);
        expect(restored.textureType, 'charcoal');
        expect(restored.textureIntensity, 0.8);
      });

      test('round-trips stabilizer and gamut', () {
        const original = ProBrushSettings(
          stabilizerLevel: 5,
          useWideGamut: true,
        );
        final json = original.toJson();
        final restored = ProBrushSettings.fromJson(json);
        expect(restored.stabilizerLevel, 5);
        expect(restored.useWideGamut, isTrue);
      });
    });
  });
}
