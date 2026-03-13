import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;
import '../drawing/models/pro_drawing_point.dart';
import '../rendering/native/image/lut_presets.dart';
import '../core/models/text_overlay.dart';
import '../core/models/tone_curve.dart';
import '../core/models/color_adjustments.dart';
import '../core/models/gradient_filter.dart' as gf;
import '../core/models/perspective_settings.dart';
import '../rendering/image_adjustment_engine.dart';

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
  final int vignetteColor;
  final double hueShift;
  final double temperature;
  final double highlights;
  final double shadows;
  final double fade;
  final double blurRadius;
  final double sharpenAmount;
  final double edgeDetectStrength;
  final int lutIndex;
  final List<TextOverlay> textOverlays;
  final int splitHighlightColor;
  final int splitShadowColor;
  final double splitBalance;
  final double splitIntensity;
  final double clarity;
  final double texture;
  final double dehaze;
  final ToneCurve toneCurve;
  final List<double> hslAdjustments;
  final double noiseReduction;
  final double gradientAngle, gradientPosition, gradientStrength;
  final int gradientColor;
  final double perspectiveX, perspectiveY;
  final double grainAmount;
  final double grainSize;
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
    this.vignetteColor = 0xFF000000,
    this.hueShift = 0,
    this.temperature = 0,
    this.highlights = 0,
    this.shadows = 0,
    this.fade = 0,
    this.blurRadius = 0,
    this.sharpenAmount = 0,
    this.edgeDetectStrength = 0,
    this.lutIndex = -1,
    this.grainAmount = 0,
    this.grainSize = 1.0,
    this.textOverlays = const [],
    this.splitHighlightColor = 0,
    this.splitShadowColor = 0,
    this.splitBalance = 0,
    this.splitIntensity = 0.5,
    this.clarity = 0,
    this.texture = 0,
    this.dehaze = 0,
    this.toneCurve = const ToneCurve(),
    this.hslAdjustments = const [
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
    ],
    this.noiseReduction = 0,
    this.gradientAngle = 0,
    this.gradientPosition = 0.5,
    this.gradientStrength = 0,
    this.gradientColor = 0,
    this.perspectiveX = 0,
    this.perspectiveY = 0,
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

    // Perspective correction (via shared engine)
    ImageAdjustmentEngine.applyPerspective(
      canvas,
      PerspectiveSettings(x: perspectiveX, y: perspectiveY),
    );

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

    // Apply color adjustments via shared engine
    final adj = ColorAdjustments(
      brightness: brightness,
      contrast: contrast,
      saturation: saturation,
      hueShift: hueShift,
      temperature: temperature,
      highlights: highlights,
      shadows: shadows,
      fade: fade,
      clarity: clarity,
      splitHighlightColor: splitHighlightColor,
      splitShadowColor: splitShadowColor,
    );
    if (ImageAdjustmentEngine.needsColorMatrix(adj, toneCurve, lutIndex)) {
      paint.colorFilter = ColorFilter.matrix(
        ImageAdjustmentEngine.computeColorMatrix(
          adj,
          toneCurve: toneCurve,
          lutIndex: lutIndex,
        ),
      );
    }

    canvas.drawImageRect(image, srcRect, dstRect, paint);

    // Blur preview via Flutter's built-in ImageFilter
    if (blurRadius > 0) {
      final sigma = blurRadius * 0.5; // Convert pixel radius to sigma
      canvas.saveLayer(
        dstRect,
        Paint()
          ..imageFilter = ui.ImageFilter.blur(
            sigmaX: sigma,
            sigmaY: sigma,
            tileMode: TileMode.clamp,
          ),
      );
      canvas.drawImageRect(image, srcRect, dstRect, paint);
      canvas.restore();
    }

    // Sharpen preview: draw sharpened overlay (unsharp mask approximation)
    if (sharpenAmount > 0 && blurRadius <= 0) {
      // Subtle sharpen effect: overlay original with slight contrast boost
      final sharpenPaint =
          Paint()
            ..filterQuality = FilterQuality.medium
            ..colorFilter = ColorFilter.matrix([
              1.0 + sharpenAmount * 0.5,
              0,
              0,
              0,
              0,
              0,
              1.0 + sharpenAmount * 0.5,
              0,
              0,
              0,
              0,
              0,
              1.0 + sharpenAmount * 0.5,
              0,
              0,
              0,
              0,
              0,
              1,
              0,
            ])
            ..blendMode = BlendMode.overlay
            ..color = Color.fromRGBO(
              255,
              255,
              255,
              (sharpenAmount * 0.3).clamp(0.0, 0.5),
            );
      canvas.drawImageRect(image, srcRect, dstRect, sharpenPaint);
    }

    // Edge detection preview: desaturate + high contrast (CPU Sobel approximation)
    if (edgeDetectStrength > 0) {
      final es = edgeDetectStrength;
      // High-contrast grayscale overlay to simulate edge detection
      final edgePaint =
          Paint()
            ..filterQuality = FilterQuality.medium
            ..colorFilter = ColorFilter.matrix([
              0.299 * es + (1 - es),
              0.587 * es,
              0.114 * es,
              0,
              0,
              0.299 * es,
              0.587 * es + (1 - es),
              0.114 * es,
              0,
              0,
              0.299 * es,
              0.587 * es,
              0.114 * es + (1 - es),
              0,
              0,
              0,
              0,
              0,
              1,
              0,
            ]);
      canvas.drawImageRect(image, srcRect, dstRect, edgePaint);
    }
    if (vignette > 0) {
      final vColor = Color(vignetteColor);
      final gradient = RadialGradient(
        radius: 0.85,
        colors: [
          Colors.transparent,
          vColor.withValues(alpha: 0.35 * vignette),
          vColor.withValues(alpha: 0.7 * vignette),
        ],
        stops: const [0.3, 0.75, 1.0],
      );
      canvas.drawRect(
        dstRect,
        Paint()..shader = gradient.createShader(dstRect),
      );
    }

    // Film grain overlay — sparse noise pattern (200 dots vs ~1600 rects)
    if (grainAmount > 0) {
      canvas.saveLayer(dstRect, Paint()..blendMode = BlendMode.overlay);
      final rng = math.Random(42);
      const dotCount = 200;
      final maxR = math.max(1.5, dstRect.width / 120);
      for (int i = 0; i < dotCount; i++) {
        final x = dstRect.left + rng.nextDouble() * dstRect.width;
        final y = dstRect.top + rng.nextDouble() * dstRect.height;
        final b = rng.nextDouble();
        canvas.drawCircle(
          Offset(x, y),
          maxR * (0.5 + rng.nextDouble() * 0.5),
          Paint()
            ..color = (b > 0.5 ? Colors.white : Colors.black).withValues(
              alpha: (grainAmount * 0.25 * b).clamp(0.0, 1.0),
            ),
        );
      }
      canvas.restore();
    }

    // Gradient filter overlay (via shared engine)
    ImageAdjustmentEngine.drawGradientOverlay(
      canvas,
      dstRect,
      gf.GradientFilter(
        angle: gradientAngle,
        position: gradientPosition,
        strength: gradientStrength,
        color: gradientColor,
      ),
    );

    // Noise reduction (via shared engine)
    ImageAdjustmentEngine.drawNoiseReduction(
      canvas,
      image,
      srcRect,
      dstRect,
      noiseReduction,
    );

    // Text overlays
    if (textOverlays.isNotEmpty) {
      for (final t in textOverlays) {
        final tp = TextPainter(
          text: TextSpan(
            text: t.text,
            style: TextStyle(
              fontSize: t.fontSize * scale,
              color: Color(t.color).withValues(alpha: t.opacity),
              fontFamily: t.fontFamily,
              fontWeight: t.bold ? FontWeight.bold : FontWeight.normal,
              fontStyle: t.italic ? FontStyle.italic : FontStyle.normal,
              shadows:
                  t.shadowColor != 0
                      ? [
                        Shadow(
                          color: Color(t.shadowColor),
                          blurRadius: 4,
                          offset: const Offset(1, 1),
                        ),
                      ]
                      : null,
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        tp.layout();
        final tx = dstRect.left + t.x * dstRect.width - tp.width / 2;
        final ty = dstRect.top + t.y * dstRect.height - tp.height / 2;
        if (t.rotation != 0) {
          canvas.save();
          canvas.translate(tx + tp.width / 2, ty + tp.height / 2);
          canvas.rotate(t.rotation);
          tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
          canvas.restore();
        } else {
          tp.paint(canvas, Offset(tx, ty));
        }
        tp.dispose();
      }
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

  // Color matrix and LUT composition are now in ImageAdjustmentEngine.

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
      old.vignetteColor != vignetteColor ||
      old.hueShift != hueShift ||
      old.temperature != temperature ||
      old.highlights != highlights ||
      old.shadows != shadows ||
      old.fade != fade ||
      old.blurRadius != blurRadius ||
      old.sharpenAmount != sharpenAmount ||
      old.edgeDetectStrength != edgeDetectStrength ||
      old.lutIndex != lutIndex ||
      old.textOverlays.length != textOverlays.length ||
      old.splitHighlightColor != splitHighlightColor ||
      old.splitShadowColor != splitShadowColor ||
      old.splitBalance != splitBalance ||
      old.splitIntensity != splitIntensity ||
      old.clarity != clarity ||
      old.texture != texture ||
      old.dehaze != dehaze ||
      old.toneCurve.isIdentity != toneCurve.isIdentity ||
      old.hslAdjustments != hslAdjustments ||
      old.noiseReduction != noiseReduction ||
      old.gradientAngle != gradientAngle ||
      old.gradientPosition != gradientPosition ||
      old.gradientStrength != gradientStrength ||
      old.gradientColor != gradientColor ||
      old.perspectiveX != perspectiveX ||
      old.perspectiveY != perspectiveY ||
      old.grainAmount != grainAmount ||
      old.grainSize != grainSize ||
      old.cropRect != cropRect ||
      old.drawingStrokes != drawingStrokes;
}
