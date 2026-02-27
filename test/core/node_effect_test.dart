import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/effects/node_effect.dart';

void main() {
  // ===========================================================================
  // BlurEffect
  // ===========================================================================

  group('BlurEffect', () {
    test('creates with defaults', () {
      final blur = BlurEffect();
      expect(blur.sigmaX, greaterThan(0));
      expect(blur.isEnabled, isTrue);
    });

    test('copyWith overrides fields', () {
      final blur = BlurEffect(sigmaX: 5, sigmaY: 5);
      final copy = blur.copyWith(sigmaX: 10, isEnabled: false);
      expect(copy.sigmaX, 10);
      expect(copy.sigmaY, 5);
      expect(copy.isEnabled, isFalse);
    });

    test('createPaint returns Paint', () {
      final blur = BlurEffect(sigmaX: 5, sigmaY: 5);
      final paint = blur.createPaint();
      expect(paint, isA<ui.Paint>());
    });

    test('toJson and fromJson round-trip', () {
      final original = BlurEffect(sigmaX: 8, sigmaY: 6);
      final json = original.toJson();
      final restored = NodeEffect.fromJson(json);
      expect(restored, isA<BlurEffect>());
      expect((restored as BlurEffect).sigmaX, 8);
      expect(restored.sigmaY, 6);
    });
  });

  // ===========================================================================
  // DropShadowEffect
  // ===========================================================================

  group('DropShadowEffect', () {
    test('creates with defaults', () {
      final shadow = DropShadowEffect();
      expect(shadow.isEnabled, isTrue);
      expect(shadow.blurRadius, greaterThanOrEqualTo(0));
    });

    test('copyWith overrides fields', () {
      final shadow = DropShadowEffect(blurRadius: 10);
      final copy = shadow.copyWith(
        blurRadius: 20,
        offset: const ui.Offset(5, 5),
      );
      expect(copy.blurRadius, 20);
      expect(copy.offset, const ui.Offset(5, 5));
    });

    test('toJson and fromJson round-trip', () {
      final original = DropShadowEffect(
        blurRadius: 15,
        offset: ui.Offset(4, 4),
        color: ui.Color(0x80000000),
      );
      final json = original.toJson();
      final restored = NodeEffect.fromJson(json);
      expect(restored, isA<DropShadowEffect>());
      expect((restored as DropShadowEffect).blurRadius, 15);
    });
  });

  // ===========================================================================
  // InnerShadowEffect
  // ===========================================================================

  group('InnerShadowEffect', () {
    test('creates with defaults', () {
      final inner = InnerShadowEffect();
      expect(inner.isEnabled, isTrue);
    });

    test('copyWith overrides fields', () {
      final inner = InnerShadowEffect(blurRadius: 5);
      final copy = inner.copyWith(blurRadius: 12);
      expect(copy.blurRadius, 12);
    });

    test('toJson and fromJson round-trip', () {
      final original = InnerShadowEffect(blurRadius: 8);
      final json = original.toJson();
      final restored = NodeEffect.fromJson(json);
      expect(restored, isA<InnerShadowEffect>());
    });
  });

  // ===========================================================================
  // OuterGlowEffect
  // ===========================================================================

  group('OuterGlowEffect', () {
    test('creates with defaults', () {
      final glow = OuterGlowEffect();
      expect(glow.isEnabled, isTrue);
    });

    test('copyWith overrides color', () {
      final glow = OuterGlowEffect(color: ui.Color(0xFF00FF00));
      final copy = glow.copyWith(color: const ui.Color(0xFFFF0000));
      expect(copy.color, const ui.Color(0xFFFF0000));
    });

    test('createGlowPaint returns Paint', () {
      final glow = OuterGlowEffect(blurRadius: 10);
      final paint = glow.createGlowPaint();
      expect(paint, isA<ui.Paint>());
    });

    test('toJson and fromJson round-trip', () {
      final original = OuterGlowEffect(blurRadius: 20, spread: 5);
      final json = original.toJson();
      final restored = NodeEffect.fromJson(json);
      expect(restored, isA<OuterGlowEffect>());
      expect((restored as OuterGlowEffect).blurRadius, 20);
    });
  });

  // ===========================================================================
  // NodeEffect.fromJson dispatch
  // ===========================================================================

  group('NodeEffect.fromJson', () {
    test('dispatches blur type correctly', () {
      final json = {
        'effectType': 'blur',
        'sigmaX': 5.0,
        'sigmaY': 5.0,
        'enabled': true,
      };
      final effect = NodeEffect.fromJson(json);
      expect(effect, isA<BlurEffect>());
    });

    test('dispatches dropShadow type correctly', () {
      final json = {
        'effectType': 'dropShadow',
        'color': 0x80000000,
        'offsetX': 2.0,
        'offsetY': 2.0,
        'blurRadius': 4.0,
        'spread': 0.0,
        'enabled': true,
      };
      final effect = NodeEffect.fromJson(json);
      expect(effect, isA<DropShadowEffect>());
    });
  });
}
