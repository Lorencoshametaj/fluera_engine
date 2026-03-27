import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/systems/image_adjustment.dart';
import 'dart:ui';

void main() {
  group('ImageAdjustmentConfig Tests', () {
    test('identity config produces identity matrix', () {
      const config = ImageAdjustmentConfig();
      expect(config.isIdentity, isTrue);

      final matrix = config.toColorMatrix();
      expect(matrix.length, 20);
      // Identity: diagonal = 1, rest = 0
      expect(matrix[0], 1.0); // R→R
      expect(matrix[6], 1.0); // G→G
      expect(matrix[12], 1.0); // B→B
      expect(matrix[18], 1.0); // A→A
      expect(matrix[4], 0.0); // R offset
    });

    test('brightness shifts RGB offsets', () {
      final config = const ImageAdjustmentConfig(brightness: 0.5);
      expect(config.isIdentity, isFalse);

      final matrix = config.toColorMatrix();
      // Brightness adds b*255 to RGB offsets (columns 4, 9, 14)
      expect(matrix[4], closeTo(127.5, 0.1));
      expect(matrix[9], closeTo(127.5, 0.1));
      expect(matrix[14], closeTo(127.5, 0.1));
    });

    test('contrast scales diagonal entries', () {
      final config = const ImageAdjustmentConfig(contrast: 2.0);
      final matrix = config.toColorMatrix();
      expect(matrix[0], closeTo(2.0, 0.01));
      expect(matrix[6], closeTo(2.0, 0.01));
      expect(matrix[12], closeTo(2.0, 0.01));
    });

    test('saturation=0 produces grayscale matrix', () {
      final config = const ImageAdjustmentConfig(saturation: 0.0);
      final matrix = config.toColorMatrix();
      // Row 0: [lr, lg, lb, 0, 0] where lr=0.2126, lg=0.7152, lb=0.0722
      expect(matrix[0], closeTo(0.2126, 0.001));
      expect(matrix[1], closeTo(0.7152, 0.001));
      expect(matrix[2], closeTo(0.0722, 0.001));
    });

    test('toColorFilter returns a ColorFilter', () {
      final config = const ImageAdjustmentConfig(brightness: 0.1);
      final filter = config.toColorFilter();
      expect(filter, isA<ColorFilter>());
    });

    test('compose chains adjustments', () {
      final a = const ImageAdjustmentConfig(brightness: 0.1, contrast: 1.2);
      final b = const ImageAdjustmentConfig(brightness: 0.2, exposure: 0.5);

      final composed = a.compose(b);
      expect(composed.brightness, closeTo(0.3, 0.001));
      expect(composed.contrast, closeTo(1.2, 0.001)); // 1.2 * 1.0
      expect(composed.exposure, closeTo(0.5, 0.001));
    });

    test('copyWith preserves unchanged values', () {
      final config = const ImageAdjustmentConfig(
        brightness: 0.5,
        contrast: 1.5,
      );
      final copy = config.copyWith(brightness: 0.0);

      expect(copy.brightness, 0.0);
      expect(copy.contrast, 1.5); // Preserved
    });

    test('serialization roundtrip', () {
      final config = const ImageAdjustmentConfig(
        brightness: 0.2,
        contrast: 1.3,
        saturation: 0.8,
        hueRotation: 45,
        exposure: 0.5,
        temperature: -0.3,
      );

      final json = config.toJson();
      final restored = ImageAdjustmentConfig.fromJson(json);

      expect(restored.brightness, 0.2);
      expect(restored.contrast, 1.3);
      expect(restored.saturation, 0.8);
      expect(restored.hueRotation, 45);
      expect(restored.exposure, 0.5);
      expect(restored.temperature, -0.3);
    });
  });
}
