import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../core/latex/ink_stroke_data.dart';

/// 🖊️ Ink Rasterizer — converts ink stroke data into a bitmap image.
///
/// Rasterizes [InkData] strokes onto a fixed-size canvas (default 256×256)
/// with black strokes on a white background. The output is raw RGBA bytes
/// suitable for ML model input.
///
/// ## Aspect Ratio Preservation (R2)
///
/// Mathematical expressions are often very wide and short (e.g. a long
/// equation), or tall and narrow (e.g. a tall fraction). Naïvely squashing
/// into a square distorts the shapes and confuses the ML model.
///
/// This rasterizer preserves the original aspect ratio by:
/// 1. Computing dynamic padding based on content shape
/// 2. Scaling uniformly to fit the longer axis
/// 3. Centering on the shorter axis with extra whitespace
///
/// This prevents a long `a + b + c + d = e` from being squished vertically
/// to look like `abcde`, which the model would misrecognize.
class InkRasterizer {
  /// Default raster target size in pixels.
  static const int defaultSize = 256;

  /// Minimum padding ratio (fraction of target size).
  static const double minPaddingRatio = 0.08;

  /// Maximum padding ratio (fraction of target size).
  /// Used for very thin/narrow content to avoid the strokes touching edges.
  static const double maxPaddingRatio = 0.20;

  /// Minimum stroke width in raster pixels.
  static const double minStrokeWidth = 2.0;

  /// Maximum stroke width in raster pixels.
  static const double maxStrokeWidth = 6.0;

  /// Aspect ratio threshold for applying dynamic padding.
  /// Content with aspect ratio beyond this gets extra padding on the short axis.
  static const double _aspectRatioThreshold = 3.0;

  /// Rasterize ink data into a PNG-encoded byte buffer.
  ///
  /// Returns the raw PNG bytes of a [width]×[height] image with black strokes
  /// on a white background. Returns `null` if the ink data is empty.
  ///
  /// For square output, use [size] (legacy). For rectangular output (e.g. to
  /// match an ML model's expected dimensions), use [width] and [height].
  ///
  /// The [preserveAspectRatio] flag (default: true) ensures mathematical
  /// expressions maintain their original proportions.
  static Future<Uint8List?> rasterize(
    InkData inkData, {
    int size = defaultSize,
    int? width,
    int? height,
    bool preserveAspectRatio = true,
  }) async {
    if (inkData.isEmpty) return null;

    final w = width ?? size;
    final h = height ?? size;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // White background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..color = const Color(0xFFFFFFFF),
    );

    // Compute bounding box of all strokes
    final bbox = inkData.boundingBox;
    if (bbox.isEmpty || !bbox.isFinite) return null;

    // ---------------------------------------------------------------------------
    // R2: Dynamic padding + aspect ratio preservation
    // ---------------------------------------------------------------------------
    final double paddingRatio;
    if (preserveAspectRatio) {
      final aspectRatio =
          bbox.width > 0 && bbox.height > 0 ? (bbox.width / bbox.height) : 1.0;
      if (aspectRatio > _aspectRatioThreshold ||
          aspectRatio < 1.0 / _aspectRatioThreshold) {
        paddingRatio = maxPaddingRatio;
      } else {
        paddingRatio = minPaddingRatio;
      }
    } else {
      paddingRatio = minPaddingRatio;
    }

    final paddingX = w * paddingRatio;
    final paddingY = h * paddingRatio;
    final availableWidth = w - paddingX * 2;
    final availableHeight = h - paddingY * 2;

    // Uniform scaling — pick the smaller scale to fit within the canvas
    final scaleX = bbox.width > 0 ? availableWidth / bbox.width : 1.0;
    final scaleY = bbox.height > 0 ? availableHeight / bbox.height : 1.0;
    final scale =
        preserveAspectRatio
            ? (scaleX < scaleY ? scaleX : scaleY)
            : (scaleX < scaleY ? scaleX : scaleY); // Always uniform

    // Center the content (whitespace on the shorter axis)
    final contentWidth = bbox.width * scale;
    final contentHeight = bbox.height * scale;
    final offsetX = (w - contentWidth) / 2 - bbox.left * scale;
    final offsetY = (h - contentHeight) / 2 - bbox.top * scale;

    // Draw strokes
    for (final stroke in inkData.strokes) {
      if (!stroke.isValid) continue;
      _drawStroke(canvas, stroke, scale, offsetX, offsetY);
    }

    // Encode to image
    final picture = recorder.endRecording();
    final image = await picture.toImage(w, h);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    picture.dispose();
    image.dispose();

    return byteData?.buffer.asUint8List();
  }

  /// Draw a single stroke onto the canvas with pressure-sensitive width.
  static void _drawStroke(
    Canvas canvas,
    InkStroke stroke,
    double scale,
    double offsetX,
    double offsetY,
  ) {
    final paint =
        Paint()
          ..color = const Color(0xFF000000)
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true;

    for (int i = 0; i < stroke.points.length - 1; i++) {
      final p0 = stroke.points[i];
      final p1 = stroke.points[i + 1];

      // Pressure-sensitive stroke width
      final avgPressure = (p0.pressure + p1.pressure) / 2;
      paint.strokeWidth =
          minStrokeWidth + (maxStrokeWidth - minStrokeWidth) * avgPressure;

      canvas.drawLine(
        Offset(p0.x * scale + offsetX, p0.y * scale + offsetY),
        Offset(p1.x * scale + offsetX, p1.y * scale + offsetY),
        paint,
      );
    }
  }
}
