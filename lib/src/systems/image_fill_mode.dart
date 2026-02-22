/// 🖼️ IMAGE FILL MODE — How images fill their container.
///
/// Computes source/destination rectangles and transforms for different
/// fill strategies: fill, fit, crop, tile, stretch.
///
/// ```dart
/// final config = FillConfig(mode: FillMode.fit);
/// final transform = config.computeTransform(imageSize, containerSize);
/// ```
library;

import 'dart:math' as math;
import 'dart:ui';
import 'package:vector_math/vector_math_64.dart';

/// How an image fills its container bounds.
enum FillMode {
  /// Scale to fill container, cropping excess (preserves aspect ratio).
  fill,

  /// Scale to fit entire image within container (preserves aspect ratio).
  fit,

  /// Display at original size, crop to container.
  crop,

  /// Repeat the image to fill the container.
  tile,

  /// Stretch to exactly match container (ignores aspect ratio).
  stretch,
}

/// Image fill configuration.
class FillConfig {
  final FillMode mode;

  /// Alignment within container (0,0 = center, -1,-1 = top-left).
  final double alignX;
  final double alignY;

  /// Additional offset after alignment.
  final double offsetX;
  final double offsetY;

  /// Additional scale factor (1.0 = no extra scale).
  final double scale;

  const FillConfig({
    this.mode = FillMode.fill,
    this.alignX = 0,
    this.alignY = 0,
    this.offsetX = 0,
    this.offsetY = 0,
    this.scale = 1.0,
  });

  /// Compute the transform matrix for rendering.
  Matrix4 computeTransform(Size imageSize, Size containerSize) {
    if (imageSize.isEmpty || containerSize.isEmpty) return Matrix4.identity();

    switch (mode) {
      case FillMode.fill:
        return _fillTransform(imageSize, containerSize);
      case FillMode.fit:
        return _fitTransform(imageSize, containerSize);
      case FillMode.crop:
        return _cropTransform(imageSize, containerSize);
      case FillMode.tile:
        return _tileTransform(imageSize, containerSize);
      case FillMode.stretch:
        return _stretchTransform(imageSize, containerSize);
    }
  }

  /// Compute the source rectangle for painting.
  Rect computeSourceRect(Size imageSize, Size containerSize) {
    switch (mode) {
      case FillMode.fill:
        final imageAspect = imageSize.width / imageSize.height;
        final containerAspect = containerSize.width / containerSize.height;
        if (imageAspect > containerAspect) {
          final w = imageSize.height * containerAspect;
          final x = (imageSize.width - w) / 2 * (1 + alignX);
          return Rect.fromLTWH(x, 0, w, imageSize.height);
        } else {
          final h = imageSize.width / containerAspect;
          final y = (imageSize.height - h) / 2 * (1 + alignY);
          return Rect.fromLTWH(0, y, imageSize.width, h);
        }
      case FillMode.crop:
        final x = (imageSize.width - containerSize.width) / 2 * (1 + alignX);
        final y = (imageSize.height - containerSize.height) / 2 * (1 + alignY);
        return Rect.fromLTWH(
          x.clamp(0, math.max(0, imageSize.width - containerSize.width)),
          y.clamp(0, math.max(0, imageSize.height - containerSize.height)),
          math.min(imageSize.width, containerSize.width),
          math.min(imageSize.height, containerSize.height),
        );
      default:
        return Rect.fromLTWH(0, 0, imageSize.width, imageSize.height);
    }
  }

  /// Compute the destination rectangle for painting.
  Rect computeDestRect(Size imageSize, Size containerSize) {
    switch (mode) {
      case FillMode.fill:
      case FillMode.stretch:
        return Rect.fromLTWH(0, 0, containerSize.width, containerSize.height);
      case FillMode.fit:
        final s = _fitScale(imageSize, containerSize);
        final w = imageSize.width * s;
        final h = imageSize.height * s;
        final x = (containerSize.width - w) / 2 * (1 + alignX);
        final y = (containerSize.height - h) / 2 * (1 + alignY);
        return Rect.fromLTWH(x + offsetX, y + offsetY, w, h);
      case FillMode.crop:
        return Rect.fromLTWH(
          offsetX,
          offsetY,
          math.min(imageSize.width, containerSize.width),
          math.min(imageSize.height, containerSize.height),
        );
      case FillMode.tile:
        return Rect.fromLTWH(0, 0, containerSize.width, containerSize.height);
    }
  }

  // ---------------------------------------------------------------------------
  // Private transform builders
  // ---------------------------------------------------------------------------

  Matrix4 _fillTransform(Size imageSize, Size containerSize) {
    final s = _fillScale(imageSize, containerSize) * scale;
    final scaledW = imageSize.width * s;
    final scaledH = imageSize.height * s;
    final dx = (containerSize.width - scaledW) / 2 * (1 + alignX) + offsetX;
    final dy = (containerSize.height - scaledH) / 2 * (1 + alignY) + offsetY;
    return Matrix4.diagonal3Values(s, s, 1.0)..setTranslationRaw(dx, dy, 0);
  }

  Matrix4 _fitTransform(Size imageSize, Size containerSize) {
    final s = _fitScale(imageSize, containerSize) * scale;
    final scaledW = imageSize.width * s;
    final scaledH = imageSize.height * s;
    final dx = (containerSize.width - scaledW) / 2 * (1 + alignX) + offsetX;
    final dy = (containerSize.height - scaledH) / 2 * (1 + alignY) + offsetY;
    return Matrix4.diagonal3Values(s, s, 1.0)..setTranslationRaw(dx, dy, 0);
  }

  Matrix4 _cropTransform(Size imageSize, Size containerSize) {
    final dx =
        (containerSize.width - imageSize.width * scale) / 2 * (1 + alignX) +
        offsetX;
    final dy =
        (containerSize.height - imageSize.height * scale) / 2 * (1 + alignY) +
        offsetY;
    return Matrix4.diagonal3Values(scale, scale, 1.0)
      ..setTranslationRaw(dx, dy, 0);
  }

  Matrix4 _tileTransform(Size imageSize, Size containerSize) {
    return Matrix4.diagonal3Values(scale, scale, 1.0)
      ..setTranslationRaw(offsetX, offsetY, 0);
  }

  Matrix4 _stretchTransform(Size imageSize, Size containerSize) {
    final sx = containerSize.width / imageSize.width * scale;
    final sy = containerSize.height / imageSize.height * scale;
    return Matrix4.diagonal3Values(sx, sy, 1.0)
      ..setTranslationRaw(offsetX, offsetY, 0);
  }

  double _fillScale(Size image, Size container) {
    return math.max(
      container.width / image.width,
      container.height / image.height,
    );
  }

  double _fitScale(Size image, Size container) {
    return math.min(
      container.width / image.width,
      container.height / image.height,
    );
  }

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
    'mode': mode.name,
    if (alignX != 0) 'alignX': alignX,
    if (alignY != 0) 'alignY': alignY,
    if (offsetX != 0) 'offsetX': offsetX,
    if (offsetY != 0) 'offsetY': offsetY,
    if (scale != 1.0) 'scale': scale,
  };

  factory FillConfig.fromJson(Map<String, dynamic> json) => FillConfig(
    mode: FillMode.values.byName(json['mode'] as String? ?? 'fill'),
    alignX: (json['alignX'] as num?)?.toDouble() ?? 0,
    alignY: (json['alignY'] as num?)?.toDouble() ?? 0,
    offsetX: (json['offsetX'] as num?)?.toDouble() ?? 0,
    offsetY: (json['offsetY'] as num?)?.toDouble() ?? 0,
    scale: (json['scale'] as num?)?.toDouble() ?? 1.0,
  );

  @override
  String toString() => 'FillConfig($mode)';
}
