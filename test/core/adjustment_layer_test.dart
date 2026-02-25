import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/editing/adjustment_layer.dart';

void main() {
  // ===========================================================================
  // AdjustmentLayer — brightness
  // ===========================================================================

  group('AdjustmentLayer - brightness', () {
    test('brightness 0 leaves pixel unchanged', () {
      final layer = AdjustmentLayer(
        type: AdjustmentType.brightness,
        parameters: {'value': 0.0},
      );
      final result = layer.apply(0.5, 0.5, 0.5);
      expect(result.r, closeTo(0.5, 0.01));
      expect(result.g, closeTo(0.5, 0.01));
      expect(result.b, closeTo(0.5, 0.01));
    });

    test('positive brightness increases values', () {
      final layer = AdjustmentLayer(
        type: AdjustmentType.brightness,
        parameters: {'value': 0.5},
      );
      final result = layer.apply(0.5, 0.5, 0.5);
      expect(result.r, greaterThanOrEqualTo(0.5));
    });
  });

  // ===========================================================================
  // AdjustmentLayer — contrast
  // ===========================================================================

  group('AdjustmentLayer - contrast', () {
    test('contrast 0 leaves midgray unchanged', () {
      final layer = AdjustmentLayer(
        type: AdjustmentType.contrast,
        parameters: {'value': 0.0},
      );
      final result = layer.apply(0.5, 0.5, 0.5);
      expect(result.r, closeTo(0.5, 0.05));
    });
  });

  // ===========================================================================
  // AdjustmentLayer — invert
  // ===========================================================================

  group('AdjustmentLayer - invert', () {
    test('invert flips pixel', () {
      final layer = AdjustmentLayer(
        type: AdjustmentType.invert,
        parameters: {},
      );
      final result = layer.apply(1.0, 0.0, 0.5);
      expect(result.r, closeTo(0.0, 0.01));
      expect(result.g, closeTo(1.0, 0.01));
      expect(result.b, closeTo(0.5, 0.01));
    });
  });

  // ===========================================================================
  // AdjustmentLayer — disabled
  // ===========================================================================

  group('AdjustmentLayer - enabled/disabled', () {
    test('disabled layer returns input unchanged', () {
      final layer = AdjustmentLayer(
        type: AdjustmentType.brightness,
        parameters: {'value': 1.0},
        enabled: false,
      );
      final result = layer.apply(0.3, 0.4, 0.5);
      expect(result.r, closeTo(0.3, 0.01));
      expect(result.g, closeTo(0.4, 0.01));
      expect(result.b, closeTo(0.5, 0.01));
    });
  });

  // ===========================================================================
  // AdjustmentLayer — copyWith
  // ===========================================================================

  group('AdjustmentLayer - copyWith', () {
    test('copies with changed opacity', () {
      final original = AdjustmentLayer(
        type: AdjustmentType.brightness,
        parameters: {'value': 0.5},
        opacity: 1.0,
      );
      final copy = original.copyWith(opacity: 0.5);
      expect(copy.opacity, 0.5);
      expect(copy.type, AdjustmentType.brightness);
    });
  });

  // ===========================================================================
  // AdjustmentLayer — toJson
  // ===========================================================================

  group('AdjustmentLayer - toJson', () {
    test('serializes to JSON', () {
      final layer = AdjustmentLayer(
        type: AdjustmentType.contrast,
        parameters: {'value': 0.3},
      );
      final json = layer.toJson();
      expect(json, isA<Map<String, dynamic>>());
      expect(json['type'], 'contrast');
    });
  });

  // ===========================================================================
  // AdjustmentStack
  // ===========================================================================

  group('AdjustmentStack', () {
    test('empty stack returns input unchanged', () {
      final stack = AdjustmentStack();
      final result = stack.apply(0.5, 0.5, 0.5);
      expect(result.r, closeTo(0.5, 0.01));
    });

    test('add and apply single layer', () {
      final stack = AdjustmentStack();
      stack.add(AdjustmentLayer(type: AdjustmentType.invert, parameters: {}));
      final result = stack.apply(1.0, 0.0, 0.5);
      expect(result.r, closeTo(0.0, 0.01));
      expect(result.g, closeTo(1.0, 0.01));
    });

    test('removeAt removes layer', () {
      final stack = AdjustmentStack();
      stack.add(AdjustmentLayer(type: AdjustmentType.invert, parameters: {}));
      stack.add(
        AdjustmentLayer(
          type: AdjustmentType.brightness,
          parameters: {'value': 0.5},
        ),
      );
      stack.removeAt(0);
      // Now only brightness remains — should not invert
      final result = stack.apply(0.5, 0.5, 0.5);
      expect(result.r, greaterThanOrEqualTo(0.5));
    });

    test('toJson serializes layers', () {
      final stack = AdjustmentStack();
      stack.add(
        AdjustmentLayer(
          type: AdjustmentType.contrast,
          parameters: {'value': 0.3},
        ),
      );
      final json = stack.toJson();
      expect(json, isA<List>());
      expect((json as List).length, 1);
    });
  });

  // ===========================================================================
  // AdjustmentType enum
  // ===========================================================================

  group('AdjustmentType', () {
    test('has expected values', () {
      expect(AdjustmentType.values, contains(AdjustmentType.brightness));
      expect(AdjustmentType.values, contains(AdjustmentType.contrast));
      expect(AdjustmentType.values, contains(AdjustmentType.saturation));
      expect(AdjustmentType.values, contains(AdjustmentType.invert));
      expect(AdjustmentType.values, contains(AdjustmentType.sepia));
    });
  });
}
