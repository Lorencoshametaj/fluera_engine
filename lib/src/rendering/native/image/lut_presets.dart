import 'dart:math' as math;
import 'dart:typed_data';

// ============================================================================
// 🎨 LUT COLOR GRADING PRESETS
//
// Runtime-computed 3D LUT data for cinematic color grading.
// Each LUT is a 64³ RGB lookup table stored as Uint8List (64*64*64*4 bytes).
// The data is computed once and cached for the lifetime of the app.
// ============================================================================

/// A single LUT preset with metadata and lazily computed LUT data.
class LutPreset {
  final String id;
  final String name;
  final String icon; // emoji icon
  final _ColorTransform _transform;
  Uint8List? _lutData;

  LutPreset({
    required this.id,
    required this.name,
    required this.icon,
    required _ColorTransform transform,
  }) : _transform = transform;

  /// 64³ RGBA LUT data (1,048,576 bytes). Computed lazily.
  Uint8List get lutData {
    _lutData ??= _computeLutData(_transform);
    return _lutData!;
  }

  /// Preview color: the output of the transform applied to a mid-gray.
  List<double> get previewColor => _transform(0.5, 0.5, 0.5);

  /// Generate a simple color matrix approximation of this LUT for previews.
  /// Returns a 4×5 color matrix suitable for `ColorFilter.matrix()`.
  List<double> get approximateColorMatrix {
    // Sample the LUT at a few key points to build an approximate matrix
    final black = _transform(0.0, 0.0, 0.0);
    final white = _transform(1.0, 1.0, 1.0);
    final red = _transform(1.0, 0.0, 0.0);
    final green = _transform(0.0, 1.0, 0.0);
    final blue = _transform(0.0, 0.0, 1.0);

    // Build approximate affine color transform:
    // out = M * in + offset
    final rRange = white[0] - black[0];
    final gRange = white[1] - black[1];
    final bRange = white[2] - black[2];

    return [
      // R row
      (red[0] - black[0]).clamp(-2.0, 2.0),
      (green[0] - black[0]).clamp(-2.0, 2.0),
      (blue[0] - black[0]).clamp(-2.0, 2.0),
      0,
      (black[0] * 255).clamp(-128.0, 128.0),
      // G row
      (red[1] - black[1]).clamp(-2.0, 2.0),
      (green[1] - black[1]).clamp(-2.0, 2.0),
      (blue[1] - black[1]).clamp(-2.0, 2.0),
      0,
      (black[1] * 255).clamp(-128.0, 128.0),
      // B row
      (red[2] - black[2]).clamp(-2.0, 2.0),
      (green[2] - black[2]).clamp(-2.0, 2.0),
      (blue[2] - black[2]).clamp(-2.0, 2.0),
      0,
      (black[2] * 255).clamp(-128.0, 128.0),
      // A row (identity)
      0, 0, 0, 1, 0,
    ];
  }
}

/// All available LUT presets.
final List<LutPreset> lutPresets = [
  LutPreset(
    id: 'none',
    name: 'Normal',
    icon: '⬜',
    transform: _identityTransform,
  ),
  LutPreset(
    id: 'cinematic',
    name: 'Cinematic',
    icon: '🎬',
    transform: _cinematicTransform,
  ),
  LutPreset(
    id: 'vintage',
    name: 'Vintage',
    icon: '📷',
    transform: _vintageTransform,
  ),
  LutPreset(
    id: 'portra',
    name: 'Portra',
    icon: '🌅',
    transform: _portraTransform,
  ),
  LutPreset(id: 'fuji', name: 'Fuji', icon: '🌿', transform: _fujiTransform),
  LutPreset(id: 'noir', name: 'Noir', icon: '🖤', transform: _noirTransform),
  LutPreset(
    id: 'sunset',
    name: 'Sunset',
    icon: '🌇',
    transform: _sunsetTransform,
  ),
  LutPreset(
    id: 'arctic',
    name: 'Arctic',
    icon: '❄️',
    transform: _arcticTransform,
  ),
];

// ============================================================================
// Private: LUT Data Generation
// ============================================================================

typedef _ColorTransform = List<double> Function(double r, double g, double b);

/// Compute 64³ RGBA LUT data as flat Uint8List.
/// Layout: for each (r, g, b) triplet, 4 bytes [R, G, B, A].
/// Ordered as: b varies slowest, g medium, r fastest (standard cube LUT).
Uint8List _computeLutData(_ColorTransform transform) {
  const size = 64;
  final data = Uint8List(size * size * size * 4);
  int offset = 0;

  for (int b = 0; b < size; b++) {
    for (int g = 0; g < size; g++) {
      for (int r = 0; r < size; r++) {
        final rNorm = r / (size - 1);
        final gNorm = g / (size - 1);
        final bNorm = b / (size - 1);

        final rgb = transform(rNorm, gNorm, bNorm);

        data[offset++] = (rgb[0].clamp(0.0, 1.0) * 255).round();
        data[offset++] = (rgb[1].clamp(0.0, 1.0) * 255).round();
        data[offset++] = (rgb[2].clamp(0.0, 1.0) * 255).round();
        data[offset++] = 255;
      }
    }
  }

  return data;
}

// ============================================================================
// Color Transforms
// ============================================================================

List<double> _identityTransform(double r, double g, double b) => [r, g, b];

List<double> _cinematicTransform(double r, double g, double b) {
  r = _liftBlacks(r, 0.05);
  g = _liftBlacks(g, 0.05);
  b = _liftBlacks(b, 0.05);

  final lum = 0.299 * r + 0.587 * g + 0.114 * b;

  // Shadows → teal
  final sw = (1.0 - lum).clamp(0.0, 1.0);
  r -= 0.08 * sw;
  g += 0.02 * sw;
  b += 0.12 * sw;

  // Highlights → warm orange
  final hw = lum.clamp(0.0, 1.0);
  r += 0.08 * hw;
  g += 0.03 * hw;
  b -= 0.06 * hw;

  // Desaturate midtones
  r = lum + (r - lum) * 0.85;
  g = lum + (g - lum) * 0.85;
  b = lum + (b - lum) * 0.85;

  // Boost contrast
  r = _contrast(r, 1.15);
  g = _contrast(g, 1.15);
  b = _contrast(b, 1.15);

  return [r, g, b];
}

List<double> _vintageTransform(double r, double g, double b) {
  r = _liftBlacks(r, 0.10);
  g = _liftBlacks(g, 0.08);
  b = _liftBlacks(b, 0.06);

  r += 0.06;
  g += 0.02;
  b -= 0.04;

  r = _contrast(r, 0.85);
  g = _contrast(g, 0.85);
  b = _contrast(b, 0.85);

  final lum = 0.299 * r + 0.587 * g + 0.114 * b;
  r = lum + (r - lum) * 0.70;
  g = lum + (g - lum) * 0.70;
  b = lum + (b - lum) * 0.65;

  final sw = (1.0 - lum).clamp(0.0, 1.0);
  r += 0.04 * sw;
  b += 0.02 * sw;

  return [r, g, b];
}

List<double> _portraTransform(double r, double g, double b) {
  r += 0.04;
  g += 0.01;
  b -= 0.02;

  r = _contrast(r, 0.95);
  g = _contrast(g, 0.95);
  b = _contrast(b, 0.95);

  r = _liftBlacks(r, 0.03);
  g = _liftBlacks(g, 0.03);
  b = _liftBlacks(b, 0.03);

  final lum = 0.299 * r + 0.587 * g + 0.114 * b;
  r = lum + (r - lum) * 0.90;
  g = lum + (g - lum) * 0.88;
  b = lum + (b - lum) * 0.85;

  final hw = lum.clamp(0.0, 1.0);
  r += 0.03 * hw;
  g += 0.02 * hw;

  return [r, g, b];
}

List<double> _fujiTransform(double r, double g, double b) {
  final lum = 0.299 * r + 0.587 * g + 0.114 * b;
  final sw = (1.0 - lum).clamp(0.0, 1.0);
  r -= 0.04 * sw;
  g += 0.02 * sw;
  b += 0.08 * sw;

  if (g > r && g > b) g += 0.05;

  final hw = lum.clamp(0.0, 1.0);
  r += 0.04 * hw;
  g += 0.01 * hw;

  r = _contrast(r, 1.08);
  g = _contrast(g, 1.08);
  b = _contrast(b, 1.08);

  r = lum + (r - lum) * 1.10;
  g = lum + (g - lum) * 1.15;
  b = lum + (b - lum) * 1.05;

  return [r, g, b];
}

List<double> _noirTransform(double r, double g, double b) {
  var lum = 0.299 * r + 0.587 * g + 0.114 * b;

  // High contrast S-curve
  lum = _sCurve(lum, 1.5);
  if (lum < 0.15) lum *= 0.7;

  // Warm sepia tint
  return [lum + 0.04, lum + 0.02, lum - 0.02];
}

List<double> _sunsetTransform(double r, double g, double b) {
  final lum = 0.299 * r + 0.587 * g + 0.114 * b;

  // Warm golden tones
  r += 0.10;
  g += 0.04;
  b -= 0.08;

  // Boost saturation in warm colors
  r = lum + (r - lum) * 1.20;
  g = lum + (g - lum) * 1.05;
  b = lum + (b - lum) * 0.80;

  // Gentle contrast
  r = _contrast(r, 1.10);
  g = _contrast(g, 1.05);
  b = _contrast(b, 1.00);

  return [r, g, b];
}

List<double> _arcticTransform(double r, double g, double b) {
  final lum = 0.299 * r + 0.587 * g + 0.114 * b;

  // Cool blue tones
  r -= 0.06;
  g += 0.02;
  b += 0.10;

  // Desaturate warm colors, boost cool
  r = lum + (r - lum) * 0.80;
  g = lum + (g - lum) * 0.95;
  b = lum + (b - lum) * 1.10;

  // Lift blacks
  r = _liftBlacks(r, 0.04);
  g = _liftBlacks(g, 0.06);
  b = _liftBlacks(b, 0.08);

  // Slight contrast
  r = _contrast(r, 1.05);
  g = _contrast(g, 1.05);
  b = _contrast(b, 1.05);

  return [r, g, b];
}

// ============================================================================
// Helpers
// ============================================================================

double _liftBlacks(double v, double amount) => v + amount * (1.0 - v);

double _contrast(double v, double c) => (v - 0.5) * c + 0.5;

double _sCurve(double v, double strength) {
  final x = (v - 0.5) * strength;
  return 1.0 / (1.0 + math.exp(-x * 5.0));
}
