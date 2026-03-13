import 'dart:typed_data';

/// 🎨 GPU Image Filter Parameters
///
/// Encapsulates all filter/effect values for native GPU image processing.
/// Serializable to [Map] for MethodChannel transport.
class ImageFilterParams {
  /// Brightness adjustment (-1.0 to +1.0, 0.0 = neutral)
  final double brightness;

  /// Contrast adjustment (-1.0 to +1.0, 0.0 = neutral)
  final double contrast;

  /// Saturation adjustment (-1.0 to +1.0, 0.0 = neutral)
  final double saturation;

  /// Hue rotation (-1.0 to +1.0, maps to -π..+π)
  final double hueShift;

  /// Temperature shift (-1.0 cool .. +1.0 warm)
  final double temperature;

  /// Opacity (0.0 transparent .. 1.0 opaque)
  final double opacity;

  /// Vignette strength (0.0 off .. 1.0 max)
  final double vignette;

  /// Gaussian blur radius in pixels (0.0 = no blur)
  final double blurRadius;

  /// Unsharp mask amount (0.0 = no sharpen, 1.0 = strong)
  final double sharpenAmount;

  /// Sobel edge detection strength (0.0 = off, 1.0 = full edges)
  final double edgeDetectStrength;

  /// Optional LUT texture index (-1 = no LUT)
  final int lutIndex;

  /// Whether horizontal flip is applied
  final bool flipHorizontal;

  /// Whether vertical flip is applied
  final bool flipVertical;

  /// Rotation in radians
  final double rotation;

  /// Crop rect (normalized 0..1), null = no crop
  final Float64List? cropRect;

  const ImageFilterParams({
    this.brightness = 0.0,
    this.contrast = 0.0,
    this.saturation = 0.0,
    this.hueShift = 0.0,
    this.temperature = 0.0,
    this.opacity = 1.0,
    this.vignette = 0.0,
    this.blurRadius = 0.0,
    this.sharpenAmount = 0.0,
    this.edgeDetectStrength = 0.0,
    this.lutIndex = -1,
    this.flipHorizontal = false,
    this.flipVertical = false,
    this.rotation = 0.0,
    this.cropRect,
  });

  /// Whether any color grading filter is active.
  bool get hasColorFilters =>
      brightness != 0.0 ||
      contrast != 0.0 ||
      saturation != 0.0 ||
      hueShift != 0.0 ||
      temperature != 0.0;

  /// Whether any post-processing effect is active.
  bool get hasPostProcessing =>
      blurRadius > 0.0 || sharpenAmount > 0.0 || edgeDetectStrength > 0.0;

  /// Whether any filter at all is active (worth sending to GPU).
  bool get hasAnyFilter =>
      hasColorFilters ||
      hasPostProcessing ||
      vignette > 0.0 ||
      opacity < 1.0 ||
      lutIndex >= 0;

  /// Serialize to a flat map for MethodChannel transport.
  Map<String, dynamic> toMap() {
    return {
      'brightness': brightness,
      'contrast': contrast,
      'saturation': saturation,
      'hueShift': hueShift,
      'temperature': temperature,
      'opacity': opacity,
      'vignette': vignette,
      'blurRadius': blurRadius,
      'sharpenAmount': sharpenAmount,
      'edgeDetectStrength': edgeDetectStrength,
      'lutIndex': lutIndex,
      'flipHorizontal': flipHorizontal,
      'flipVertical': flipVertical,
      'rotation': rotation,
      if (cropRect != null)
        'cropRect': [cropRect![0], cropRect![1], cropRect![2], cropRect![3]],
    };
  }

  /// Create from map (deserialization).
  factory ImageFilterParams.fromMap(Map<String, dynamic> map) {
    Float64List? crop;
    if (map['cropRect'] != null) {
      final c = map['cropRect'] as List;
      crop = Float64List.fromList([
        (c[0] as num).toDouble(),
        (c[1] as num).toDouble(),
        (c[2] as num).toDouble(),
        (c[3] as num).toDouble(),
      ]);
    }
    return ImageFilterParams(
      brightness: (map['brightness'] as num?)?.toDouble() ?? 0.0,
      contrast: (map['contrast'] as num?)?.toDouble() ?? 0.0,
      saturation: (map['saturation'] as num?)?.toDouble() ?? 0.0,
      hueShift: (map['hueShift'] as num?)?.toDouble() ?? 0.0,
      temperature: (map['temperature'] as num?)?.toDouble() ?? 0.0,
      opacity: (map['opacity'] as num?)?.toDouble() ?? 1.0,
      vignette: (map['vignette'] as num?)?.toDouble() ?? 0.0,
      blurRadius: (map['blurRadius'] as num?)?.toDouble() ?? 0.0,
      sharpenAmount: (map['sharpenAmount'] as num?)?.toDouble() ?? 0.0,
      edgeDetectStrength:
          (map['edgeDetectStrength'] as num?)?.toDouble() ?? 0.0,
      lutIndex: (map['lutIndex'] as num?)?.toInt() ?? -1,
      flipHorizontal: map['flipHorizontal'] as bool? ?? false,
      flipVertical: map['flipVertical'] as bool? ?? false,
      rotation: (map['rotation'] as num?)?.toDouble() ?? 0.0,
      cropRect: crop,
    );
  }

  /// Create from an ImageElement's properties.
  factory ImageFilterParams.fromImageElement(dynamic element) {
    Float64List? crop;
    if (element.cropRect != null) {
      crop = Float64List.fromList([
        element.cropRect!.left,
        element.cropRect!.top,
        element.cropRect!.right,
        element.cropRect!.bottom,
      ]);
    }
    return ImageFilterParams(
      brightness: (element.brightness as num).toDouble(),
      contrast: (element.contrast as num).toDouble(),
      saturation: (element.saturation as num).toDouble(),
      hueShift: (element.hueShift as num).toDouble(),
      temperature: (element.temperature as num).toDouble(),
      opacity: (element.opacity as num).toDouble(),
      vignette: (element.vignette as num).toDouble(),
      blurRadius: (element.blurRadius as num?)?.toDouble() ?? 0.0,
      sharpenAmount: (element.sharpenAmount as num?)?.toDouble() ?? 0.0,
      edgeDetectStrength:
          (element.edgeDetectStrength as num?)?.toDouble() ?? 0.0,
      flipHorizontal: element.flipHorizontal as bool,
      flipVertical: element.flipVertical as bool,
      rotation: (element.rotation as num).toDouble(),
      cropRect: crop,
    );
  }

  ImageFilterParams copyWith({
    double? brightness,
    double? contrast,
    double? saturation,
    double? hueShift,
    double? temperature,
    double? opacity,
    double? vignette,
    double? blurRadius,
    double? sharpenAmount,
    double? edgeDetectStrength,
    int? lutIndex,
    bool? flipHorizontal,
    bool? flipVertical,
    double? rotation,
    Float64List? cropRect,
  }) {
    return ImageFilterParams(
      brightness: brightness ?? this.brightness,
      contrast: contrast ?? this.contrast,
      saturation: saturation ?? this.saturation,
      hueShift: hueShift ?? this.hueShift,
      temperature: temperature ?? this.temperature,
      opacity: opacity ?? this.opacity,
      vignette: vignette ?? this.vignette,
      blurRadius: blurRadius ?? this.blurRadius,
      sharpenAmount: sharpenAmount ?? this.sharpenAmount,
      edgeDetectStrength: edgeDetectStrength ?? this.edgeDetectStrength,
      lutIndex: lutIndex ?? this.lutIndex,
      flipHorizontal: flipHorizontal ?? this.flipHorizontal,
      flipVertical: flipVertical ?? this.flipVertical,
      rotation: rotation ?? this.rotation,
      cropRect: cropRect ?? this.cropRect,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ImageFilterParams &&
          brightness == other.brightness &&
          contrast == other.contrast &&
          saturation == other.saturation &&
          hueShift == other.hueShift &&
          temperature == other.temperature &&
          opacity == other.opacity &&
          vignette == other.vignette &&
          blurRadius == other.blurRadius &&
          sharpenAmount == other.sharpenAmount &&
          edgeDetectStrength == other.edgeDetectStrength &&
          lutIndex == other.lutIndex;

  @override
  int get hashCode =>
      brightness.hashCode ^
      contrast.hashCode ^
      saturation.hashCode ^
      hueShift.hashCode ^
      temperature.hashCode ^
      opacity.hashCode ^
      vignette.hashCode ^
      blurRadius.hashCode ^
      sharpenAmount.hashCode ^
      edgeDetectStrength.hashCode ^
      lutIndex.hashCode;
}
