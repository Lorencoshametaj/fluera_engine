import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/editing/blend_mode_engine.dart';

void main() {
  // ===========================================================================
  // Normal blend
  // ===========================================================================

  group('BlendModeEngine - normal', () {
    test('opaque source replaces destination', () {
      final result = BlendModeEngine.blend(
        srcR: 1.0,
        srcG: 0.0,
        srcB: 0.0,
        srcA: 1.0,
        dstR: 0.0,
        dstG: 1.0,
        dstB: 0.0,
        dstA: 1.0,
        mode: EngineBlendMode.normal,
      );
      expect(result.r, closeTo(1.0, 0.01));
      expect(result.g, closeTo(0.0, 0.01));
    });

    test('transparent source shows destination', () {
      final result = BlendModeEngine.blend(
        srcR: 1.0,
        srcG: 0.0,
        srcB: 0.0,
        srcA: 0.0,
        dstR: 0.0,
        dstG: 1.0,
        dstB: 0.0,
        dstA: 1.0,
        mode: EngineBlendMode.normal,
      );
      expect(result.g, closeTo(1.0, 0.01));
    });
  });

  // ===========================================================================
  // Multiply
  // ===========================================================================

  group('BlendModeEngine - multiply', () {
    test('multiply darkens', () {
      final result = BlendModeEngine.blend(
        srcR: 0.5,
        srcG: 0.5,
        srcB: 0.5,
        srcA: 1.0,
        dstR: 0.8,
        dstG: 0.8,
        dstB: 0.8,
        dstA: 1.0,
        mode: EngineBlendMode.multiply,
      );
      expect(result.r, lessThan(0.8));
    });

    test('multiply with white preserves destination', () {
      final result = BlendModeEngine.blend(
        srcR: 1.0,
        srcG: 1.0,
        srcB: 1.0,
        srcA: 1.0,
        dstR: 0.5,
        dstG: 0.3,
        dstB: 0.7,
        dstA: 1.0,
        mode: EngineBlendMode.multiply,
      );
      expect(result.r, closeTo(0.5, 0.01));
      expect(result.g, closeTo(0.3, 0.01));
    });
  });

  // ===========================================================================
  // Screen
  // ===========================================================================

  group('BlendModeEngine - screen', () {
    test('screen lightens', () {
      final result = BlendModeEngine.blend(
        srcR: 0.5,
        srcG: 0.5,
        srcB: 0.5,
        srcA: 1.0,
        dstR: 0.3,
        dstG: 0.3,
        dstB: 0.3,
        dstA: 1.0,
        mode: EngineBlendMode.screen,
      );
      expect(result.r, greaterThan(0.3));
    });

    test('screen with black preserves destination', () {
      final result = BlendModeEngine.blend(
        srcR: 0.0,
        srcG: 0.0,
        srcB: 0.0,
        srcA: 1.0,
        dstR: 0.5,
        dstG: 0.5,
        dstB: 0.5,
        dstA: 1.0,
        mode: EngineBlendMode.screen,
      );
      expect(result.r, closeTo(0.5, 0.01));
    });
  });

  // ===========================================================================
  // Overlay
  // ===========================================================================

  group('BlendModeEngine - overlay', () {
    test('overlay combines multiply and screen', () {
      final result = BlendModeEngine.blend(
        srcR: 0.5,
        srcG: 0.5,
        srcB: 0.5,
        srcA: 1.0,
        dstR: 0.5,
        dstG: 0.5,
        dstB: 0.5,
        dstA: 1.0,
        mode: EngineBlendMode.overlay,
      );
      expect(result.r, greaterThanOrEqualTo(0.0));
      expect(result.r, lessThanOrEqualTo(1.0));
    });
  });

  // ===========================================================================
  // Categories
  // ===========================================================================

  group('BlendModeEngine - categories', () {
    test('categoryOf returns correct category for normal', () {
      final category = BlendModeEngine.categoryOf(EngineBlendMode.normal);
      expect(category, isNotNull);
    });

    test('modesInCategory returns modes', () {
      final darkening = BlendModeEngine.modesInCategory(
        BlendModeCategory.darken,
      );
      expect(darkening, isNotEmpty);
      expect(darkening, contains(EngineBlendMode.multiply));
    });
  });

  // ===========================================================================
  // EngineBlendMode enum
  // ===========================================================================

  group('EngineBlendMode', () {
    test('has expected values', () {
      expect(EngineBlendMode.values, contains(EngineBlendMode.normal));
      expect(EngineBlendMode.values, contains(EngineBlendMode.multiply));
      expect(EngineBlendMode.values, contains(EngineBlendMode.screen));
      expect(EngineBlendMode.values, contains(EngineBlendMode.overlay));
    });
  });
}
