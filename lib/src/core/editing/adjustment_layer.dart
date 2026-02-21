/// 🔄 ADJUSTMENT LAYER — Non-destructive image adjustments.
///
/// Pure-math per-pixel transforms for brightness, contrast, saturation,
/// hue shift, exposure, gamma, levels, invert, threshold, and sepia.
///
/// ```dart
/// final adj = AdjustmentLayer(
///   type: AdjustmentType.brightness,
///   parameters: {'amount': 0.2},
/// );
/// final adjusted = adj.apply(0.5, 0.3, 0.8); // RGB in → RGB out
/// ```
library;

import 'dart:math' as math;

// =============================================================================
// ADJUSTMENT TYPE
// =============================================================================

/// Types of non-destructive adjustments.
enum AdjustmentType {
  /// Shift all channels uniformly (-1 to +1).
  brightness,

  /// Expand/compress dynamic range (0 = flat, 1 = normal, 2 = high).
  contrast,

  /// Color intensity (0 = gray, 1 = normal, 2 = vivid).
  saturation,

  /// Rotate hue wheel (-180° to +180°).
  hueShift,

  /// Photographic exposure stops (-5 to +5).
  exposure,

  /// Power curve (0.1 = dark, 1 = linear, 3 = bright).
  gamma,

  /// Input/output range mapping with black/white/midtone points.
  levels,

  /// Flip all channels (1 - value).
  invert,

  /// Binary threshold (below = 0, above = 1).
  threshold,

  /// Warm sepia tone (0 to 1 intensity).
  sepia,
}

// =============================================================================
// ADJUSTED COLOR
// =============================================================================

/// Result of applying an adjustment.
class AdjustedColor {
  final double r, g, b;
  const AdjustedColor(this.r, this.g, this.b);

  @override
  String toString() =>
      'AdjustedColor(${(r * 255).round()}, ${(g * 255).round()}, ${(b * 255).round()})';
}

// =============================================================================
// ADJUSTMENT LAYER
// =============================================================================

/// A single non-destructive adjustment with configurable parameters.
class AdjustmentLayer {
  /// Adjustment type.
  final AdjustmentType type;

  /// Type-specific parameters.
  final Map<String, double> parameters;

  /// Whether this adjustment is active.
  final bool enabled;

  /// Opacity of the adjustment (0 = no effect, 1 = full).
  final double opacity;

  const AdjustmentLayer({
    required this.type,
    this.parameters = const {},
    this.enabled = true,
    this.opacity = 1.0,
  });

  /// Apply this adjustment to an sRGB pixel (0–1 per channel).
  AdjustedColor apply(double r, double g, double b) {
    if (!enabled) return AdjustedColor(r, g, b);

    final (ar, ag, ab) = _transform(r, g, b);

    // Blend with original by opacity
    if (opacity < 1.0) {
      return AdjustedColor(
        _lerp(r, ar, opacity),
        _lerp(g, ag, opacity),
        _lerp(b, ab, opacity),
      );
    }

    return AdjustedColor(ar, ag, ab);
  }

  (double, double, double) _transform(double r, double g, double b) {
    switch (type) {
      case AdjustmentType.brightness:
        final amount = parameters['amount'] ?? 0.0;
        return (
          (r + amount).clamp(0.0, 1.0),
          (g + amount).clamp(0.0, 1.0),
          (b + amount).clamp(0.0, 1.0),
        );

      case AdjustmentType.contrast:
        final factor = parameters['factor'] ?? 1.0;
        return (
          ((r - 0.5) * factor + 0.5).clamp(0.0, 1.0),
          ((g - 0.5) * factor + 0.5).clamp(0.0, 1.0),
          ((b - 0.5) * factor + 0.5).clamp(0.0, 1.0),
        );

      case AdjustmentType.saturation:
        final factor = parameters['factor'] ?? 1.0;
        final lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;
        return (
          (lum + (r - lum) * factor).clamp(0.0, 1.0),
          (lum + (g - lum) * factor).clamp(0.0, 1.0),
          (lum + (b - lum) * factor).clamp(0.0, 1.0),
        );

      case AdjustmentType.hueShift:
        final degrees = parameters['degrees'] ?? 0.0;
        final hsl = _rgbToHsl(r, g, b);
        final newHue = (hsl.$1 + degrees) % 360.0;
        return _hslToRgb(newHue < 0 ? newHue + 360 : newHue, hsl.$2, hsl.$3);

      case AdjustmentType.exposure:
        final stops = parameters['stops'] ?? 0.0;
        final multiplier = math.pow(2.0, stops).toDouble();
        return (
          (r * multiplier).clamp(0.0, 1.0),
          (g * multiplier).clamp(0.0, 1.0),
          (b * multiplier).clamp(0.0, 1.0),
        );

      case AdjustmentType.gamma:
        final gamma = parameters['gamma'] ?? 1.0;
        if (gamma <= 0) return (r, g, b);
        final invGamma = 1.0 / gamma;
        return (
          math.pow(r.clamp(0.0, 1.0), invGamma).toDouble(),
          math.pow(g.clamp(0.0, 1.0), invGamma).toDouble(),
          math.pow(b.clamp(0.0, 1.0), invGamma).toDouble(),
        );

      case AdjustmentType.levels:
        final inBlack = parameters['inBlack'] ?? 0.0;
        final inWhite = parameters['inWhite'] ?? 1.0;
        final outBlack = parameters['outBlack'] ?? 0.0;
        final outWhite = parameters['outWhite'] ?? 1.0;
        final mid = parameters['midtone'] ?? 1.0;
        return (
          _applyLevels(r, inBlack, inWhite, outBlack, outWhite, mid),
          _applyLevels(g, inBlack, inWhite, outBlack, outWhite, mid),
          _applyLevels(b, inBlack, inWhite, outBlack, outWhite, mid),
        );

      case AdjustmentType.invert:
        return (1.0 - r, 1.0 - g, 1.0 - b);

      case AdjustmentType.threshold:
        final t = parameters['threshold'] ?? 0.5;
        final lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;
        final v = lum >= t ? 1.0 : 0.0;
        return (v, v, v);

      case AdjustmentType.sepia:
        final intensity = parameters['intensity'] ?? 1.0;
        final sr = (r * 0.393 + g * 0.769 + b * 0.189).clamp(0.0, 1.0);
        final sg = (r * 0.349 + g * 0.686 + b * 0.168).clamp(0.0, 1.0);
        final sb = (r * 0.272 + g * 0.534 + b * 0.131).clamp(0.0, 1.0);
        return (
          _lerp(r, sr, intensity),
          _lerp(g, sg, intensity),
          _lerp(b, sb, intensity),
        );
    }
  }

  static double _applyLevels(
    double v,
    double inBlack,
    double inWhite,
    double outBlack,
    double outWhite,
    double mid,
  ) {
    final range = inWhite - inBlack;
    if (range <= 0) return outBlack;
    var normalized = ((v - inBlack) / range).clamp(0.0, 1.0);
    if (mid != 1.0 && mid > 0) {
      normalized = math.pow(normalized, 1.0 / mid).toDouble();
    }
    return (outBlack + normalized * (outWhite - outBlack)).clamp(0.0, 1.0);
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  // HSL helpers
  static (double, double, double) _rgbToHsl(double r, double g, double b) {
    final cMax = math.max(r, math.max(g, b));
    final cMin = math.min(r, math.min(g, b));
    final delta = cMax - cMin;
    final l = (cMax + cMin) / 2.0;

    if (delta == 0) return (0.0, 0.0, l);

    final s = delta / (1.0 - (2.0 * l - 1.0).abs());

    double h;
    if (cMax == r) {
      h = 60.0 * (((g - b) / delta) % 6.0);
    } else if (cMax == g) {
      h = 60.0 * ((b - r) / delta + 2.0);
    } else {
      h = 60.0 * ((r - g) / delta + 4.0);
    }
    if (h < 0) h += 360.0;
    return (h, s.clamp(0.0, 1.0), l.clamp(0.0, 1.0));
  }

  static (double, double, double) _hslToRgb(double h, double s, double l) {
    if (s == 0) return (l, l, l);

    final c = (1.0 - (2.0 * l - 1.0).abs()) * s;
    final x = c * (1.0 - ((h / 60.0) % 2.0 - 1.0).abs());
    final m = l - c / 2.0;

    double r, g, b;
    if (h < 60) {
      r = c;
      g = x;
      b = 0;
    } else if (h < 120) {
      r = x;
      g = c;
      b = 0;
    } else if (h < 180) {
      r = 0;
      g = c;
      b = x;
    } else if (h < 240) {
      r = 0;
      g = x;
      b = c;
    } else if (h < 300) {
      r = x;
      g = 0;
      b = c;
    } else {
      r = c;
      g = 0;
      b = x;
    }

    return (
      (r + m).clamp(0.0, 1.0),
      (g + m).clamp(0.0, 1.0),
      (b + m).clamp(0.0, 1.0),
    );
  }

  /// Create a copy with updated fields.
  AdjustmentLayer copyWith({
    AdjustmentType? type,
    Map<String, double>? parameters,
    bool? enabled,
    double? opacity,
  }) => AdjustmentLayer(
    type: type ?? this.type,
    parameters: parameters ?? this.parameters,
    enabled: enabled ?? this.enabled,
    opacity: opacity ?? this.opacity,
  );

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'parameters': parameters,
    'enabled': enabled,
    'opacity': opacity,
  };

  factory AdjustmentLayer.fromJson(Map<String, dynamic> json) =>
      AdjustmentLayer(
        type: AdjustmentType.values.firstWhere((v) => v.name == json['type']),
        parameters:
            (json['parameters'] as Map<String, dynamic>?)?.map(
              (k, v) => MapEntry(k, (v as num).toDouble()),
            ) ??
            {},
        enabled: json['enabled'] as bool? ?? true,
        opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
      );

  @override
  String toString() => 'AdjustmentLayer(${type.name}, enabled=$enabled)';
}

// =============================================================================
// ADJUSTMENT STACK
// =============================================================================

/// Composable stack of adjustment layers applied in order.
class AdjustmentStack {
  final List<AdjustmentLayer> _layers;

  AdjustmentStack([List<AdjustmentLayer>? layers]) : _layers = layers ?? [];

  List<AdjustmentLayer> get layers => List.unmodifiable(_layers);
  int get count => _layers.length;
  bool get isEmpty => _layers.isEmpty;

  void add(AdjustmentLayer layer) => _layers.add(layer);
  void insert(int index, AdjustmentLayer layer) => _layers.insert(index, layer);
  void removeAt(int index) => _layers.removeAt(index);

  /// Move a layer from [from] to [to].
  void reorder(int from, int to) {
    final layer = _layers.removeAt(from);
    _layers.insert(to.clamp(0, _layers.length), layer);
  }

  /// Apply all active layers in order.
  AdjustedColor apply(double r, double g, double b) {
    var cr = r, cg = g, cb = b;
    for (final layer in _layers) {
      if (layer.enabled) {
        final result = layer.apply(cr, cg, cb);
        cr = result.r;
        cg = result.g;
        cb = result.b;
      }
    }
    return AdjustedColor(cr, cg, cb);
  }

  List<Map<String, dynamic>> toJson() =>
      _layers.map((l) => l.toJson()).toList();

  factory AdjustmentStack.fromJson(List<dynamic> json) => AdjustmentStack(
    json
        .map((j) => AdjustmentLayer.fromJson(j as Map<String, dynamic>))
        .toList(),
  );
}
