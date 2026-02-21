/// 🧪 PIXEL DIFF ENGINE — Pixel-level image comparison for visual regression.
///
/// Compares two PNG images pixel-by-pixel with configurable tolerance,
/// anti-aliasing detection, and diff image generation.
///
/// ```dart
/// final engine = PixelDiffEngine();
/// final result = engine.compare(
///   actualPng,
///   expectedPng,
///   config: PixelDiffConfig(tolerance: 0.02, maxDiffPercent: 0.5),
/// );
/// if (!result.passed) {
///   print('${result.diffPercent}% pixels differ');
///   // result.diffImage contains visual overlay
/// }
/// ```
library;

import 'dart:typed_data';

// =============================================================================
// PIXEL DIFF CONFIG
// =============================================================================

/// Configuration for pixel-level image comparison.
class PixelDiffConfig {
  /// Per-channel color tolerance (0.0 = exact, 1.0 = anything passes).
  ///
  /// Each RGBA channel difference is divided by 255 and compared against
  /// this threshold. Default: 0.0 (exact match).
  final double tolerance;

  /// Maximum percentage of pixels that can differ before the test fails.
  ///
  /// Even with tolerance, some pixels may still differ (e.g. font rendering).
  /// This sets the overall failure threshold. Default: 0.0%.
  final double maxDiffPercent;

  /// Whether to apply anti-aliasing detection.
  ///
  /// When true, pixels adjacent to edges (where neighboring pixels
  /// differ significantly) are treated more leniently. Default: false.
  final bool ignoreAntialiasing;

  /// Anti-aliasing neighbor threshold — minimum channel difference
  /// to consider a pixel as an edge pixel. Default: 0.1 (10%).
  final double antiAliasingThreshold;

  const PixelDiffConfig({
    this.tolerance = 0.0,
    this.maxDiffPercent = 0.0,
    this.ignoreAntialiasing = false,
    this.antiAliasingThreshold = 0.1,
  });

  /// Exact match — zero tolerance.
  static const exact = PixelDiffConfig();

  /// Lenient — allows minor rendering differences.
  static const lenient = PixelDiffConfig(
    tolerance: 0.02,
    maxDiffPercent: 1.0,
    ignoreAntialiasing: true,
  );

  /// Generous — for cross-platform tolerance.
  static const generous = PixelDiffConfig(
    tolerance: 0.05,
    maxDiffPercent: 5.0,
    ignoreAntialiasing: true,
  );
}

// =============================================================================
// PIXEL DIFF RESULT
// =============================================================================

/// Result of a pixel-level image comparison.
class PixelDiffResult {
  /// Whether the comparison passed the configured thresholds.
  final bool passed;

  /// Total number of pixels compared.
  final int totalPixels;

  /// Number of pixels that differ beyond tolerance.
  final int differentPixels;

  /// Percentage of pixels that differ (0.0–100.0).
  final double diffPercent;

  /// Maximum per-channel difference found (0.0–1.0).
  final double maxChannelDiff;

  /// Average per-channel difference across all pixels (0.0–1.0).
  final double avgChannelDiff;

  /// Visual diff overlay — red pixels where differences exist.
  /// Null if no differences or if not requested.
  final Uint8List? diffImageRgba;

  /// Width of the compared images.
  final int width;

  /// Height of the compared images.
  final int height;

  const PixelDiffResult({
    required this.passed,
    required this.totalPixels,
    required this.differentPixels,
    required this.diffPercent,
    required this.maxChannelDiff,
    required this.avgChannelDiff,
    required this.width,
    required this.height,
    this.diffImageRgba,
  });

  @override
  String toString() =>
      'PixelDiffResult(${passed ? "PASS" : "FAIL"}, '
      'diff=${diffPercent.toStringAsFixed(2)}%, '
      'pixels=$differentPixels/$totalPixels)';
}

// =============================================================================
// DIMENSION MISMATCH
// =============================================================================

/// Thrown when compared images have different dimensions.
class DimensionMismatchError extends Error {
  final int actualWidth, actualHeight;
  final int expectedWidth, expectedHeight;

  DimensionMismatchError({
    required this.actualWidth,
    required this.actualHeight,
    required this.expectedWidth,
    required this.expectedHeight,
  });

  @override
  String toString() =>
      'DimensionMismatchError: actual ${actualWidth}x$actualHeight '
      'vs expected ${expectedWidth}x$expectedHeight';
}

// =============================================================================
// PIXEL DIFF ENGINE
// =============================================================================

/// Pixel-level image comparison engine.
///
/// Compares raw RGBA pixel buffers with configurable tolerance,
/// anti-aliasing detection, and generates visual diff overlays.
class PixelDiffEngine {
  const PixelDiffEngine();

  /// Compare two RGBA pixel buffers.
  ///
  /// Both buffers must have exactly `width * height * 4` bytes (RGBA).
  /// Returns a detailed [PixelDiffResult].
  PixelDiffResult compare({
    required Uint8List actual,
    required Uint8List expected,
    required int width,
    required int height,
    PixelDiffConfig config = const PixelDiffConfig(),
    bool generateDiffImage = true,
  }) {
    final pixelCount = width * height;
    final expectedLength = pixelCount * 4;

    if (actual.length != expectedLength || expected.length != expectedLength) {
      throw DimensionMismatchError(
        actualWidth: actual.length ~/ (height * 4),
        actualHeight: height,
        expectedWidth: expected.length ~/ (height * 4),
        expectedHeight: height,
      );
    }

    int differentPixels = 0;
    double maxDiff = 0.0;
    double totalDiff = 0.0;

    final diffImage = generateDiffImage ? Uint8List(expectedLength) : null;

    for (int i = 0; i < pixelCount; i++) {
      final offset = i * 4;

      // Per-channel difference (normalized to 0.0–1.0)
      final dr = (actual[offset] - expected[offset]).abs() / 255.0;
      final dg = (actual[offset + 1] - expected[offset + 1]).abs() / 255.0;
      final db = (actual[offset + 2] - expected[offset + 2]).abs() / 255.0;
      final da = (actual[offset + 3] - expected[offset + 3]).abs() / 255.0;

      final pixelMaxDiff = _max4(dr, dg, db, da);
      totalDiff += pixelMaxDiff;

      if (pixelMaxDiff > maxDiff) maxDiff = pixelMaxDiff;

      final isDifferent = pixelMaxDiff > config.tolerance;

      // Anti-aliasing detection
      if (isDifferent && config.ignoreAntialiasing) {
        if (_isAntiAliasedPixel(
          actual,
          expected,
          i,
          width,
          height,
          config.antiAliasingThreshold,
        )) {
          // Treat as same — anti-aliased pixel
          if (diffImage != null) {
            // Dim yellow for AA pixels
            diffImage[offset] = 255;
            diffImage[offset + 1] = 255;
            diffImage[offset + 2] = 0;
            diffImage[offset + 3] = 40;
          }
          continue;
        }
      }

      if (isDifferent) {
        differentPixels++;
        if (diffImage != null) {
          // Bright red for different pixels
          final intensity = (pixelMaxDiff * 255).clamp(0, 255).toInt();
          diffImage[offset] = 255;
          diffImage[offset + 1] = 0;
          diffImage[offset + 2] = 0;
          diffImage[offset + 3] = intensity;
        }
      } else if (diffImage != null) {
        // Transparent for matching pixels
        diffImage[offset] = 0;
        diffImage[offset + 1] = 0;
        diffImage[offset + 2] = 0;
        diffImage[offset + 3] = 0;
      }
    }

    final diffPercent =
        pixelCount > 0 ? (differentPixels / pixelCount) * 100.0 : 0.0;
    final avgDiff = pixelCount > 0 ? totalDiff / pixelCount : 0.0;
    final passed = diffPercent <= config.maxDiffPercent;

    return PixelDiffResult(
      passed: passed,
      totalPixels: pixelCount,
      differentPixels: differentPixels,
      diffPercent: diffPercent,
      maxChannelDiff: maxDiff,
      avgChannelDiff: avgDiff,
      width: width,
      height: height,
      diffImageRgba: diffImage,
    );
  }

  /// Check if a pixel is likely an anti-aliased edge pixel.
  bool _isAntiAliasedPixel(
    Uint8List actual,
    Uint8List expected,
    int pixelIndex,
    int width,
    int height,
    double threshold,
  ) {
    final x = pixelIndex % width;
    final y = pixelIndex ~/ width;

    // Check 4-connected neighbors
    const offsets = [(-1, 0), (1, 0), (0, -1), (0, 1)];
    int edgeCount = 0;

    for (final (dx, dy) in offsets) {
      final nx = x + dx;
      final ny = y + dy;
      if (nx < 0 || nx >= width || ny < 0 || ny >= height) continue;

      final ni = (ny * width + nx) * 4;
      final dr = (expected[ni] - expected[pixelIndex * 4]).abs() / 255.0;
      final dg =
          (expected[ni + 1] - expected[pixelIndex * 4 + 1]).abs() / 255.0;
      final db =
          (expected[ni + 2] - expected[pixelIndex * 4 + 2]).abs() / 255.0;

      if (_max3(dr, dg, db) > threshold) {
        edgeCount++;
      }
    }

    // If 2+ neighbors are significantly different, this is likely an edge
    return edgeCount >= 2;
  }

  static double _max3(double a, double b, double c) {
    if (a >= b && a >= c) return a;
    if (b >= c) return b;
    return c;
  }

  static double _max4(double a, double b, double c, double d) {
    var m = a;
    if (b > m) m = b;
    if (c > m) m = c;
    if (d > m) m = d;
    return m;
  }
}
