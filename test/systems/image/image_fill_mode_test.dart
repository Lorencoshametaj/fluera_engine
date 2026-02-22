import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/systems/image_fill_mode.dart';
import 'dart:ui';
import 'package:vector_math/vector_math_64.dart';

void main() {
  group('ImageFillMode Tests', () {
    const imageSize = Size(200, 100);
    const containerSize = Size(100, 100);

    test('fill mode covers entire container', () {
      final config = const FillConfig(mode: FillMode.fill);
      final destRect = config.computeDestRect(imageSize, containerSize);

      expect(destRect.width, containerSize.width);
      expect(destRect.height, containerSize.height);
    });

    test('fit mode keeps aspect ratio within container', () {
      final config = const FillConfig(mode: FillMode.fit);
      final destRect = config.computeDestRect(imageSize, containerSize);

      // Image 200x100 should scale to fit 100x100 -> result = 100x50, centered
      expect(destRect.width, closeTo(100, 0.1));
      expect(destRect.height, closeTo(50, 0.1));
      // Centered vertically: y = (100 - 50) / 2 = 25
      expect(destRect.top, closeTo(25, 0.1));
    });

    test('stretch mode ignores aspect ratio', () {
      final config = const FillConfig(mode: FillMode.stretch);
      final destRect = config.computeDestRect(imageSize, containerSize);

      expect(destRect.width, containerSize.width);
      expect(destRect.height, containerSize.height);
    });

    test('crop mode uses original image size bounded by container', () {
      final config = const FillConfig(mode: FillMode.crop);
      final srcRect = config.computeSourceRect(imageSize, containerSize);

      // Source rect should be clamped to container dimensions
      expect(srcRect.width, containerSize.width);
      expect(srcRect.height, containerSize.height);
    });

    test('computeTransform returns identity for empty sizes', () {
      final config = const FillConfig(mode: FillMode.fill);
      final transform = config.computeTransform(Size.zero, containerSize);
      expect(transform, Matrix4.identity());
    });

    test('alignment offsets dest rect for fit mode', () {
      // Top-left alignment
      final config = const FillConfig(
        mode: FillMode.fit,
        alignX: -1.0,
        alignY: -1.0,
      );
      final destRect = config.computeDestRect(imageSize, containerSize);

      // With alignX=-1: x = (100-100)/2 * (1+(-1)) = 0
      // With alignY=-1: y = (100-50)/2 * (1+(-1)) = 0
      expect(destRect.left, closeTo(0, 0.1));
      expect(destRect.top, closeTo(0, 0.1));
    });

    test('fill mode source rect crops wider image', () {
      final config = const FillConfig(mode: FillMode.fill);
      // Image 200x100 filling 100x100 container
      // Image aspect (2:1) > container aspect (1:1) -> crop width
      final srcRect = config.computeSourceRect(imageSize, containerSize);

      // Should crop to 100x100 from center of image
      expect(srcRect.width, closeTo(100, 0.1));
      expect(srcRect.height, closeTo(100, 0.1));
      expect(srcRect.left, closeTo(50, 0.1)); // Centered
    });

    test('tile mode dest rect covers container', () {
      final config = const FillConfig(mode: FillMode.tile);
      final destRect = config.computeDestRect(imageSize, containerSize);

      expect(destRect.width, containerSize.width);
      expect(destRect.height, containerSize.height);
    });
  });
}
