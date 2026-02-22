/// 🎨 IMAGE ADJUSTMENT — Non-destructive image adjustments.
///
/// Provides brightness, contrast, saturation, hue rotation, exposure, and
/// temperature adjustments that produce Flutter [ColorFilter]s for the
/// paint pipeline.
///
/// ```dart
/// final adj = ImageAdjustmentConfig(brightness: 0.1, contrast: 1.2);
/// final filter = adj.toColorFilter();
/// canvas.drawImage(image, Offset.zero, Paint()..colorFilter = filter);
/// ```
library;

import 'dart:math' as math;
import 'dart:ui';

/// Non-destructive image adjustment configuration.
class ImageAdjustmentConfig {
  /// Brightness offset (-1.0 to 1.0, 0 = no change).
  final double brightness;

  /// Contrast multiplier (0.0 to 3.0, 1.0 = no change).
  final double contrast;

  /// Saturation multiplier (0.0 = grayscale, 1.0 = normal, 2.0 = vivid).
  final double saturation;

  /// Hue rotation in degrees (0–360).
  final double hueRotation;

  /// Exposure offset (-2.0 to 2.0, 0 = no change).
  final double exposure;

  /// Temperature shift (-1.0 cool to 1.0 warm, 0 = neutral).
  final double temperature;

  const ImageAdjustmentConfig({
    this.brightness = 0.0,
    this.contrast = 1.0,
    this.saturation = 1.0,
    this.hueRotation = 0.0,
    this.exposure = 0.0,
    this.temperature = 0.0,
  });

  /// Whether all values are at their defaults (no adjustment).
  bool get isIdentity =>
      brightness == 0 &&
      contrast == 1.0 &&
      saturation == 1.0 &&
      hueRotation == 0 &&
      exposure == 0 &&
      temperature == 0;

  /// Produce a 5×4 color matrix for this adjustment.
  List<double> toColorMatrix() {
    var m = _identityMatrix();
    if (brightness != 0) m = _multiply(m, _brightnessMatrix(brightness));
    if (contrast != 1.0) m = _multiply(m, _contrastMatrix(contrast));
    if (saturation != 1.0) m = _multiply(m, _saturationMatrix(saturation));
    if (hueRotation != 0) m = _multiply(m, _hueRotationMatrix(hueRotation));
    if (exposure != 0) m = _multiply(m, _exposureMatrix(exposure));
    if (temperature != 0) m = _multiply(m, _temperatureMatrix(temperature));
    return m;
  }

  /// Convert to a Flutter [ColorFilter].
  ColorFilter toColorFilter() => ColorFilter.matrix(toColorMatrix());

  ImageAdjustmentConfig copyWith({
    double? brightness,
    double? contrast,
    double? saturation,
    double? hueRotation,
    double? exposure,
    double? temperature,
  }) => ImageAdjustmentConfig(
    brightness: brightness ?? this.brightness,
    contrast: contrast ?? this.contrast,
    saturation: saturation ?? this.saturation,
    hueRotation: hueRotation ?? this.hueRotation,
    exposure: exposure ?? this.exposure,
    temperature: temperature ?? this.temperature,
  );

  /// Chain another adjustment on top of this one.
  ImageAdjustmentConfig compose(ImageAdjustmentConfig other) =>
      ImageAdjustmentConfig(
        brightness: brightness + other.brightness,
        contrast: contrast * other.contrast,
        saturation: saturation * other.saturation,
        hueRotation: (hueRotation + other.hueRotation) % 360,
        exposure: exposure + other.exposure,
        temperature: temperature + other.temperature,
      );

  Map<String, dynamic> toJson() => {
    if (brightness != 0) 'brightness': brightness,
    if (contrast != 1.0) 'contrast': contrast,
    if (saturation != 1.0) 'saturation': saturation,
    if (hueRotation != 0) 'hueRotation': hueRotation,
    if (exposure != 0) 'exposure': exposure,
    if (temperature != 0) 'temperature': temperature,
  };

  factory ImageAdjustmentConfig.fromJson(Map<String, dynamic> json) =>
      ImageAdjustmentConfig(
        brightness: (json['brightness'] as num?)?.toDouble() ?? 0,
        contrast: (json['contrast'] as num?)?.toDouble() ?? 1.0,
        saturation: (json['saturation'] as num?)?.toDouble() ?? 1.0,
        hueRotation: (json['hueRotation'] as num?)?.toDouble() ?? 0,
        exposure: (json['exposure'] as num?)?.toDouble() ?? 0,
        temperature: (json['temperature'] as num?)?.toDouble() ?? 0,
      );

  @override
  String toString() =>
      'ImageAdjustmentConfig('
      'brightness: $brightness, contrast: $contrast, '
      'saturation: $saturation)';

  // ===========================================================================
  // Color matrix math
  // ===========================================================================

  static List<double> _identityMatrix() => [
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];

  static List<double> _brightnessMatrix(double b) {
    final v = b * 255;
    return [1, 0, 0, 0, v, 0, 1, 0, 0, v, 0, 0, 1, 0, v, 0, 0, 0, 1, 0];
  }

  static List<double> _contrastMatrix(double c) {
    final t = (1.0 - c) / 2.0 * 255;
    return [c, 0, 0, 0, t, 0, c, 0, 0, t, 0, 0, c, 0, t, 0, 0, 0, 1, 0];
  }

  static List<double> _saturationMatrix(double s) {
    const lr = 0.2126;
    const lg = 0.7152;
    const lb = 0.0722;
    final sr = (1 - s) * lr;
    final sg = (1 - s) * lg;
    final sb = (1 - s) * lb;
    return [
      sr + s,
      sg,
      sb,
      0,
      0,
      sr,
      sg + s,
      sb,
      0,
      0,
      sr,
      sg,
      sb + s,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ];
  }

  static List<double> _hueRotationMatrix(double degrees) {
    final rad = degrees * math.pi / 180;
    final cosVal = math.cos(rad);
    final sinVal = math.sin(rad);
    const lr = 0.213;
    const lg = 0.715;
    const lb = 0.072;
    return [
      lr + cosVal * (1 - lr) + sinVal * (-lr),
      lg + cosVal * (-lg) + sinVal * (-lg),
      lb + cosVal * (-lb) + sinVal * (1 - lb),
      0,
      0,
      lr + cosVal * (-lr) + sinVal * 0.143,
      lg + cosVal * (1 - lg) + sinVal * 0.140,
      lb + cosVal * (-lb) + sinVal * (-0.283),
      0,
      0,
      lr + cosVal * (-lr) + sinVal * (-(1 - lr)),
      lg + cosVal * (-lg) + sinVal * lg,
      lb + cosVal * (1 - lb) + sinVal * lb,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ];
  }

  static List<double> _exposureMatrix(double exposure) {
    final m = math.pow(2.0, exposure).toDouble();
    return [m, 0, 0, 0, 0, 0, m, 0, 0, 0, 0, 0, m, 0, 0, 0, 0, 0, 1, 0];
  }

  static List<double> _temperatureMatrix(double temp) {
    // Warm = increase red, decrease blue. Cool = opposite.
    final r = 1.0 + temp * 0.1;
    final b = 1.0 - temp * 0.1;
    return [r, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, b, 0, 0, 0, 0, 0, 1, 0];
  }

  static List<double> _multiply(List<double> a, List<double> b) {
    final result = List<double>.filled(20, 0);
    for (int row = 0; row < 4; row++) {
      for (int col = 0; col < 5; col++) {
        double sum = 0;
        for (int k = 0; k < 4; k++) {
          sum += a[row * 5 + k] * b[k * 5 + col];
        }
        if (col == 4) sum += a[row * 5 + 4];
        result[row * 5 + col] = sum;
      }
    }
    return result;
  }
}
