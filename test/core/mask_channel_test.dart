import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/editing/mask_channel.dart';

void main() {
  // ===========================================================================
  // MaskChannel — opaque
  // ===========================================================================

  group('MaskChannel - opaque', () {
    test('fully opaque mask returns 1 everywhere', () {
      final mask = MaskChannel.opaque(10, 10);
      expect(mask.sample(5, 5), closeTo(1.0, 0.01));
      expect(mask.sample(0, 0), closeTo(1.0, 0.01));
    });
  });

  // ===========================================================================
  // MaskChannel — filledRect
  // ===========================================================================

  group('MaskChannel - filledRect', () {
    test('inside rect returns 1', () {
      final mask = MaskChannel.filledRect(20, 20, 5, 5, 10, 10);
      expect(mask.sample(10, 10), closeTo(1.0, 0.01));
    });

    test('outside rect returns 0', () {
      final mask = MaskChannel.filledRect(20, 20, 5, 5, 10, 10);
      expect(mask.sample(0, 0), closeTo(0.0, 0.01));
    });
  });

  // ===========================================================================
  // MaskChannel — sample
  // ===========================================================================

  group('MaskChannel - sample', () {
    test('out of bounds returns 0', () {
      final mask = MaskChannel.opaque(10, 10);
      expect(mask.sample(-1, -1), closeTo(0.0, 0.01));
      expect(mask.sample(20, 20), closeTo(0.0, 0.01));
    });
  });

  // ===========================================================================
  // MaskChannel — sampleNormalized
  // ===========================================================================

  group('MaskChannel - sampleNormalized', () {
    test('center of opaque mask returns 1', () {
      final mask = MaskChannel.opaque(10, 10);
      expect(mask.sampleNormalized(0.5, 0.5), closeTo(1.0, 0.01));
    });
  });

  // ===========================================================================
  // MaskChannel — inversion
  // ===========================================================================

  group('MaskChannel - inversion', () {
    test('inverted opaque mask returns 0', () {
      final mask = MaskChannel.opaque(10, 10).copyWith(inverted: true);
      expect(mask.sample(5, 5), closeTo(0.0, 0.01));
    });
  });

  // ===========================================================================
  // MaskChannel — feather
  // ===========================================================================

  group('MaskChannel - feather', () {
    test('applyFeather returns new mask', () {
      final mask = MaskChannel.filledRect(20, 20, 5, 5, 10, 10);
      final feathered = mask.copyWith(featherRadius: 2.0).applyFeather();
      expect(feathered.width, mask.width);
      expect(feathered.height, mask.height);
    });
  });

  // ===========================================================================
  // MaskChannel — copyWith
  // ===========================================================================

  group('MaskChannel - copyWith', () {
    test('copyWith preserves unchanged fields', () {
      final mask = MaskChannel.opaque(10, 10);
      final copy = mask.copyWith(enabled: false);
      expect(copy.enabled, isFalse);
      expect(copy.width, 10);
    });
  });

  // ===========================================================================
  // MaskChannel — toJson
  // ===========================================================================

  group('MaskChannel - toJson', () {
    test('serializes to map', () {
      final mask = MaskChannel.opaque(5, 5);
      final json = mask.toJson();
      expect(json, isA<Map<String, dynamic>>());
      expect(json['width'], 5);
    });
  });

  // ===========================================================================
  // MaskChannel — fromLuminosity
  // ===========================================================================

  group('MaskChannel - fromLuminosity', () {
    test('creates mask from RGB luminosity', () {
      // White pixel → luminosity ≈ 1
      final mask = MaskChannel.fromLuminosity([1.0], [1.0], [1.0], 1, 1);
      expect(mask.sample(0, 0), closeTo(1.0, 0.1));
    });
  });

  // ===========================================================================
  // MaskCompositor
  // ===========================================================================

  group('MaskCompositor', () {
    test('intersect of two opaque masks is opaque', () {
      final a = MaskChannel.opaque(10, 10);
      final b = MaskChannel.opaque(10, 10);
      final result = MaskCompositor.intersect([a, b]);
      expect(result.sample(5, 5), closeTo(1.0, 0.01));
    });

    test('intersect with empty rect mask is zero', () {
      final opaque = MaskChannel.opaque(10, 10);
      final rect = MaskChannel.filledRect(10, 10, 8, 8, 2, 2);
      final result = MaskCompositor.intersect([opaque, rect]);
      expect(result.sample(0, 0), closeTo(0.0, 0.01));
    });

    test('unite returns max of masks', () {
      final a = MaskChannel.filledRect(10, 10, 0, 0, 5, 5);
      final b = MaskChannel.filledRect(10, 10, 5, 5, 5, 5);
      final result = MaskCompositor.unite([a, b]);
      expect(result.sample(2, 2), closeTo(1.0, 0.01));
      expect(result.sample(7, 7), closeTo(1.0, 0.01));
    });
  });
}
