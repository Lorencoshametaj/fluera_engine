import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'dart:math' as math;
import '../drawing/models/pro_drawing_point.dart';

// ============================================================================
// Image Editor — Preview Painter
// Renders the image with all transformations and color adjustments.
// ============================================================================

class PreviewPainter extends CustomPainter {
  final ui.Image image;
  final double rotation;
  final bool flipHorizontal;
  final bool flipVertical;
  final double brightness;
  final double contrast;
  final double saturation;
  final double opacity;
  final double vignette;
  final double hueShift;
  final double temperature;
  final Rect? cropRect;
  final List<ProStroke> drawingStrokes;

  PreviewPainter({
    required this.image,
    required this.rotation,
    required this.flipHorizontal,
    required this.flipVertical,
    required this.brightness,
    required this.contrast,
    required this.saturation,
    required this.opacity,
    this.vignette = 0,
    this.hueShift = 0,
    this.temperature = 0,
    this.cropRect,
    this.drawingStrokes = const [],
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();

    final center = Offset(size.width / 2, size.height / 2);
    canvas.translate(center.dx, center.dy);

    if (rotation != 0) canvas.rotate(rotation);

    if (flipHorizontal || flipVertical) {
      canvas.scale(flipHorizontal ? -1.0 : 1.0, flipVertical ? -1.0 : 1.0);
    }

    Rect srcRect;
    double displayWidth, displayHeight;

    if (cropRect != null) {
      final imgW = image.width.toDouble();
      final imgH = image.height.toDouble();
      srcRect = Rect.fromLTRB(
        cropRect!.left * imgW,
        cropRect!.top * imgH,
        cropRect!.right * imgW,
        cropRect!.bottom * imgH,
      );
      displayWidth = srcRect.width;
      displayHeight = srcRect.height;
    } else {
      srcRect = Rect.fromLTWH(
        0,
        0,
        image.width.toDouble(),
        image.height.toDouble(),
      );
      displayWidth = image.width.toDouble();
      displayHeight = image.height.toDouble();
    }

    final containerRatio = size.width / size.height;
    final imageRatio = displayWidth / displayHeight;
    final scale =
        containerRatio > imageRatio
            ? size.height / displayHeight
            : size.width / displayWidth;

    final dstRect = Rect.fromCenter(
      center: Offset.zero,
      width: displayWidth * scale,
      height: displayHeight * scale,
    );

    final paint = Paint()..filterQuality = FilterQuality.medium;

    if (opacity < 1.0) {
      paint.color = Color.fromRGBO(255, 255, 255, opacity);
    }

    if (brightness != 0 ||
        contrast != 0 ||
        saturation != 0 ||
        hueShift != 0 ||
        temperature != 0) {
      paint.colorFilter = ColorFilter.matrix(_getColorMatrix());
    }

    canvas.drawImageRect(image, srcRect, dstRect, paint);

    // Vignette overlay
    if (vignette > 0) {
      final gradient = RadialGradient(
        radius: 0.85,
        colors: [
          Colors.transparent,
          Colors.black.withValues(alpha: 0.35 * vignette),
          Colors.black.withValues(alpha: 0.7 * vignette),
        ],
        stops: const [0.3, 0.75, 1.0],
      );
      canvas.drawRect(
        dstRect,
        Paint()..shader = gradient.createShader(dstRect),
      );
    }

    // Drawing strokes
    if (drawingStrokes.isNotEmpty) {
      canvas.save();
      canvas.scale(scale);

      for (final stroke in drawingStrokes) {
        if (stroke.points.isEmpty) continue;

        final strokePaint =
            Paint()
              ..color = stroke.color
              ..strokeWidth = stroke.baseWidth
              ..strokeCap = StrokeCap.round
              ..strokeJoin = StrokeJoin.round
              ..style = PaintingStyle.stroke;

        final path = Path();
        bool isFirst = true;
        for (final point in stroke.points) {
          if (isFirst) {
            path.moveTo(point.position.dx, point.position.dy);
            isFirst = false;
          } else {
            path.lineTo(point.position.dx, point.position.dy);
          }
        }
        canvas.drawPath(path, strokePaint);
      }

      canvas.restore();
    }

    canvas.restore();
  }

  List<double> _getColorMatrix() {
    final b = brightness * 255;
    final c = contrast + 1.0;
    final t = (1.0 - c) / 2.0 * 255;
    final s = saturation + 1.0;
    const lumR = 0.3086;
    const lumG = 0.6094;
    const lumB = 0.0820;
    final sr = (1 - s) * lumR, sg = (1 - s) * lumG, sb = (1 - s) * lumB;

    double r0 = (sr + s) * c, r1 = sg * c, r2 = sb * c, r4 = b + t;
    double g0 = sr * c, g1 = (sg + s) * c, g2 = sb * c, g4 = b + t;
    double b0 = sr * c, b1 = sg * c, b2 = (sb + s) * c, b4 = b + t;

    if (temperature != 0) {
      final tmp = temperature * 30;
      r4 += tmp;
      g4 += tmp * 0.4;
      b4 -= tmp;
    }

    if (hueShift != 0) {
      final angle = hueShift * math.pi;
      final cosA = math.cos(angle), sinA = math.sin(angle);
      const k = 1.0 / 3.0;
      const sq = 0.57735; // 1/sqrt(3)
      final m00 = cosA + (1 - cosA) * k;
      final m01 = k * (1 - cosA) - sq * sinA;
      final m02 = k * (1 - cosA) + sq * sinA;
      final m10 = k * (1 - cosA) + sq * sinA;
      final m11 = cosA + (1 - cosA) * k;
      final m12 = k * (1 - cosA) - sq * sinA;
      final m20 = k * (1 - cosA) - sq * sinA;
      final m21 = k * (1 - cosA) + sq * sinA;
      final m22 = cosA + (1 - cosA) * k;
      final nr0 = m00 * r0 + m01 * g0 + m02 * b0;
      final nr1 = m00 * r1 + m01 * g1 + m02 * b1;
      final nr2 = m00 * r2 + m01 * g2 + m02 * b2;
      final ng0 = m10 * r0 + m11 * g0 + m12 * b0;
      final ng1 = m10 * r1 + m11 * g1 + m12 * b1;
      final ng2 = m10 * r2 + m11 * g2 + m12 * b2;
      final nb0 = m20 * r0 + m21 * g0 + m22 * b0;
      final nb1 = m20 * r1 + m21 * g1 + m22 * b1;
      final nb2 = m20 * r2 + m21 * g2 + m22 * b2;
      r0 = nr0;
      r1 = nr1;
      r2 = nr2;
      g0 = ng0;
      g1 = ng1;
      g2 = ng2;
      b0 = nb0;
      b1 = nb1;
      b2 = nb2;
    }

    return [
      r0,
      r1,
      r2,
      0,
      r4,
      g0,
      g1,
      g2,
      0,
      g4,
      b0,
      b1,
      b2,
      0,
      b4,
      0,
      0,
      0,
      1,
      0,
    ];
  }

  @override
  bool shouldRepaint(PreviewPainter old) =>
      old.rotation != rotation ||
      old.flipHorizontal != flipHorizontal ||
      old.flipVertical != flipVertical ||
      old.brightness != brightness ||
      old.contrast != contrast ||
      old.saturation != saturation ||
      old.opacity != opacity ||
      old.vignette != vignette ||
      old.hueShift != hueShift ||
      old.temperature != temperature ||
      old.cropRect != cropRect ||
      old.drawingStrokes != drawingStrokes;
}
