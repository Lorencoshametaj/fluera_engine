/// 🔄 MASK CHANNEL — Advanced mask system for non-destructive editing.
///
/// Supports vector, raster, and luminosity masks with feathering,
/// inversion, and density control.
///
/// ```dart
/// final mask = MaskChannel(
///   type: MaskType.raster,
///   width: 100,
///   height: 100,
///   density: Float64List(100 * 100), // 0.0–1.0 per pixel
/// );
/// final alpha = mask.sample(50, 50); // get mask value at position
/// ```
library;

import 'dart:math' as math;

// =============================================================================
// MASK TYPE
// =============================================================================

/// Types of masks available.
enum MaskType {
  /// Shape-based mask from vector paths.
  vector,

  /// Bitmap-based mask (per-pixel density).
  raster,

  /// Derived from the luminosity of the source image.
  luminosity,
}

// =============================================================================
// MASK CHANNEL
// =============================================================================

/// A single mask channel with density map and properties.
class MaskChannel {
  /// Mask type.
  final MaskType type;

  /// Mask width in pixels.
  final int width;

  /// Mask height in pixels.
  final int height;

  /// Per-pixel density values (0 = transparent, 1 = opaque).
  /// Length must be width × height. Can be null for fully opaque masks.
  final List<double>? density;

  /// Whether the mask is inverted.
  final bool inverted;

  /// Feather radius in pixels (0 = sharp edges).
  final double featherRadius;

  /// Whether this mask is enabled.
  final bool enabled;

  /// Overall mask opacity (multiplied with density).
  final double opacity;

  MaskChannel({
    required this.type,
    this.width = 0,
    this.height = 0,
    this.density,
    this.inverted = false,
    this.featherRadius = 0,
    this.enabled = true,
    this.opacity = 1.0,
  });

  /// Total number of pixels.
  int get pixelCount => width * height;

  /// Whether this mask has per-pixel data.
  bool get hasData => density != null && density!.length == pixelCount;

  /// Sample mask value at (x, y). Returns 0–1.
  double sample(int x, int y) {
    if (!enabled) return 1.0;
    if (x < 0 || x >= width || y < 0 || y >= height) return 0.0;

    double value;
    if (hasData) {
      value = density![y * width + x].clamp(0.0, 1.0);
    } else {
      value = 1.0; // fully opaque if no data
    }

    if (inverted) value = 1.0 - value;
    return value * opacity;
  }

  /// Sample mask value at normalized coordinates (0–1).
  double sampleNormalized(double nx, double ny) {
    final x = (nx * (width - 1)).round().clamp(0, width - 1);
    final y = (ny * (height - 1)).round().clamp(0, height - 1);
    return sample(x, y);
  }

  /// Apply feathering to the density map.
  ///
  /// Returns a new MaskChannel with blurred density.
  MaskChannel applyFeather() {
    if (featherRadius <= 0 || !hasData) return this;

    final radius = featherRadius.ceil();
    final newDensity = List<double>.filled(pixelCount, 0);

    // Simple box blur approximation for feathering
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        double sum = 0;
        int count = 0;

        for (int dy = -radius; dy <= radius; dy++) {
          for (int dx = -radius; dx <= radius; dx++) {
            final nx = x + dx;
            final ny = y + dy;
            if (nx >= 0 && nx < width && ny >= 0 && ny < height) {
              // Circular kernel
              if (dx * dx + dy * dy <= radius * radius) {
                sum += density![ny * width + nx];
                count++;
              }
            }
          }
        }

        newDensity[y * width + x] = count > 0 ? sum / count : 0;
      }
    }

    return MaskChannel(
      type: type,
      width: width,
      height: height,
      density: newDensity,
      inverted: inverted,
      featherRadius: 0, // already applied
      enabled: enabled,
      opacity: opacity,
    );
  }

  /// Create a mask from luminosity values of RGB pixels.
  static MaskChannel fromLuminosity(
    List<double> r,
    List<double> g,
    List<double> b,
    int width,
    int height,
  ) {
    assert(r.length == width * height);
    final density = List<double>.filled(width * height, 0);
    for (int i = 0; i < density.length; i++) {
      density[i] = (0.2126 * r[i] + 0.7152 * g[i] + 0.0722 * b[i]).clamp(
        0.0,
        1.0,
      );
    }
    return MaskChannel(
      type: MaskType.luminosity,
      width: width,
      height: height,
      density: density,
    );
  }

  /// Create a filled rectangular mask.
  static MaskChannel filledRect(
    int width,
    int height,
    int rectX,
    int rectY,
    int rectW,
    int rectH,
  ) {
    final density = List<double>.filled(width * height, 0);
    for (int y = rectY; y < math.min(rectY + rectH, height); y++) {
      for (int x = rectX; x < math.min(rectX + rectW, width); x++) {
        if (x >= 0 && y >= 0) {
          density[y * width + x] = 1.0;
        }
      }
    }
    return MaskChannel(
      type: MaskType.raster,
      width: width,
      height: height,
      density: density,
    );
  }

  /// Create a fully opaque mask.
  static MaskChannel opaque(int width, int height) => MaskChannel(
    type: MaskType.raster,
    width: width,
    height: height,
    density: List<double>.filled(width * height, 1.0),
  );

  /// Create a copy with updated fields.
  MaskChannel copyWith({
    MaskType? type,
    int? width,
    int? height,
    List<double>? density,
    bool? inverted,
    double? featherRadius,
    bool? enabled,
    double? opacity,
  }) => MaskChannel(
    type: type ?? this.type,
    width: width ?? this.width,
    height: height ?? this.height,
    density: density ?? this.density,
    inverted: inverted ?? this.inverted,
    featherRadius: featherRadius ?? this.featherRadius,
    enabled: enabled ?? this.enabled,
    opacity: opacity ?? this.opacity,
  );

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'width': width,
    'height': height,
    'inverted': inverted,
    'featherRadius': featherRadius,
    'enabled': enabled,
    'opacity': opacity,
    // density omitted for compact serialization (stored separately)
  };

  factory MaskChannel.fromJson(Map<String, dynamic> json) => MaskChannel(
    type: MaskType.values.firstWhere(
      (v) => v.name == json['type'],
      orElse: () => MaskType.raster,
    ),
    width: json['width'] as int? ?? 0,
    height: json['height'] as int? ?? 0,
    inverted: json['inverted'] as bool? ?? false,
    featherRadius: (json['featherRadius'] as num?)?.toDouble() ?? 0,
    enabled: json['enabled'] as bool? ?? true,
    opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
  );

  @override
  String toString() =>
      'MaskChannel(${type.name}, ${width}x$height, '
      'inverted=$inverted, feather=$featherRadius)';
}

// =============================================================================
// MASK COMPOSITOR
// =============================================================================

/// Composes multiple mask channels together.
class MaskCompositor {
  const MaskCompositor._();

  /// Combine multiple masks using multiplication (intersection).
  static MaskChannel intersect(List<MaskChannel> masks) {
    if (masks.isEmpty) return MaskChannel(type: MaskType.raster);
    if (masks.length == 1) return masks.first;

    final w = masks.first.width;
    final h = masks.first.height;
    final density = List<double>.filled(w * h, 1.0);

    for (final mask in masks) {
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          density[y * w + x] *= mask.sample(x, y);
        }
      }
    }

    return MaskChannel(
      type: MaskType.raster,
      width: w,
      height: h,
      density: density,
    );
  }

  /// Combine masks using maximum (union).
  static MaskChannel unite(List<MaskChannel> masks) {
    if (masks.isEmpty) return MaskChannel(type: MaskType.raster);
    if (masks.length == 1) return masks.first;

    final w = masks.first.width;
    final h = masks.first.height;
    final density = List<double>.filled(w * h, 0);

    for (final mask in masks) {
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          density[y * w + x] = math.max(density[y * w + x], mask.sample(x, y));
        }
      }
    }

    return MaskChannel(
      type: MaskType.raster,
      width: w,
      height: h,
      density: density,
    );
  }
}
