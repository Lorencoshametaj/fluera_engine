import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/models/image_element.dart';
import '../../drawing/models/pro_drawing_point.dart';
import '../../tools/image/image_tool.dart';
import '../../drawing/brushes/brushes.dart'; // 🖌️ Import brushes for consistent rendering

/// 🖼️ IMAGE PAINTER
/// Draws images on the canvas with selection and resize handles
class ImagePainter extends CustomPainter {
  final List<ImageElement> images;
  final Map<String, ui.Image> loadedImages; // Cache of images caricate
  final ImageElement? selectedImage;
  final ImageTool imageTool;

  // 🎨 Modalità editing
  final ImageElement? imageInEditMode;
  final List<ProStroke> imageEditingStrokes;
  final ProStroke? currentEditingStroke; // Stroke temporaneo con colore!

  // 🔄 Loading animation value (0.0 - 1.0 for pulse effect)
  final double loadingPulse;

  ImagePainter({
    required this.images,
    required this.loadedImages,
    required this.selectedImage,
    required this.imageTool,
    this.imageInEditMode,
    this.imageEditingStrokes = const [],
    this.currentEditingStroke,
    this.loadingPulse = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final imageElement in images) {
      final image = loadedImages[imageElement.imagePath];
      if (image == null) {
        // 🔄 Draw loading placeholder for images being downloaded
        _drawLoadingPlaceholder(canvas, imageElement);
        continue;
      }

      // Save stato canvas
      canvas.save();

      // Translate alla position
      canvas.translate(imageElement.position.dx, imageElement.position.dy);

      // Applica rotazione
      if (imageElement.rotation != 0) {
        canvas.rotate(imageElement.rotation);
      }

      // Applica flip
      if (imageElement.flipHorizontal || imageElement.flipVertical) {
        canvas.scale(
          imageElement.flipHorizontal ? -1.0 : 1.0,
          imageElement.flipVertical ? -1.0 : 1.0,
        );
      }

      // Applica scala
      if (imageElement.scale != 1.0) {
        canvas.scale(imageElement.scale);
      }

      // Calculate dimensioni (considerando crop if present)
      final imageWidth = image.width.toDouble();
      final imageHeight = image.height.toDouble();

      Rect srcRect; // Area sorgente of the image
      Rect dstRect; // Area destinazione on the canvas

      if (imageElement.cropRect != null) {
        // With crop: use only the cropped area
        final crop = imageElement.cropRect!;
        srcRect = Rect.fromLTRB(
          crop.left * imageWidth,
          crop.top * imageHeight,
          crop.right * imageWidth,
          crop.bottom * imageHeight,
        );
        final croppedWidth = srcRect.width;
        final croppedHeight = srcRect.height;
        dstRect = Rect.fromCenter(
          center: Offset.zero,
          width: croppedWidth,
          height: croppedHeight,
        );
      } else {
        // Without crop: usa l'immagine intera
        srcRect = Rect.fromLTWH(0, 0, imageWidth, imageHeight);
        dstRect = Rect.fromCenter(
          center: Offset.zero,
          width: imageWidth,
          height: imageHeight,
        );
      }

      // Create paint con opacity e filtri colore
      final paint = Paint();

      // Applica opacity
      if (imageElement.opacity < 1.0) {
        paint.color = Color.fromRGBO(255, 255, 255, imageElement.opacity);
        paint.blendMode = BlendMode.dstIn;
      }

      // Applica color filter se ci sono modifiche
      if (imageElement.brightness != 0 ||
          imageElement.contrast != 0 ||
          imageElement.saturation != 0) {
        paint.colorFilter = ColorFilter.matrix(_getColorMatrix(imageElement));
      }

      // Draw l'immagine with all i filtri (usa drawImageRect per crop)
      canvas.drawImageRect(image, srcRect, dstRect, paint);

      // 🎨 SEMPRE disegna gli strokes salvati sull'immagine (PRIMA del restore!)
      // Gli strokes are in coordinate relative all'immagine, quindi beneficiano delle trasformazioni
      if (imageElement.drawingStrokes.isNotEmpty) {
        for (final stroke in imageElement.drawingStrokes) {
          _drawStroke(canvas, stroke, imageElement.scale);
        }
      }

      // 🎨 Se questa immagine is in editing mode, disegna strokes temporanei
      // (l'overlay will come disegnato after the restore in coordinate assolute)
      if (imageInEditMode?.id == imageElement.id) {
        // Draw gli strokes temporanei (durante l'editing corrente)
        for (final stroke in imageEditingStrokes) {
          _drawStroke(canvas, stroke, imageElement.scale);
        }

        // Draw the current stroke in real-time (con colore corretto!)
        if (currentEditingStroke != null) {
          _drawStroke(canvas, currentEditingStroke!, imageElement.scale);
        }
      }

      // Ripristina stato
      canvas.restore();

      // 🎨 Se questa immagine is in editing mode, disegna overlay (in coordinate assolute)
      if (imageInEditMode?.id == imageElement.id) {
        _drawEditingOverlayBorder(canvas, imageElement, image);
      }

      // Draw selezione se selezionata (only if NON in editing)
      if (selectedImage?.id == imageElement.id && imageInEditMode == null) {
        _drawSelection(canvas, imageElement, image);
      }
    }
  }

  /// Calculates matrice colori per brightness, contrast, saturation
  List<double> _getColorMatrix(ImageElement element) {
    // Brightness
    final b = element.brightness * 255;

    // Contrast
    final c = element.contrast + 1.0;
    final t = (1.0 - c) / 2.0 * 255;

    // Saturation
    final s = element.saturation + 1.0;
    final sr = (1.0 - s) * 0.3086;
    final sg = (1.0 - s) * 0.6094;
    final sb = (1.0 - s) * 0.0820;

    return [
      sr + s, sg, sb, 0, b + t, // R
      sr, sg + s, sb, 0, b + t, // G
      sr, sg, sb + s, 0, b + t, // B
      0, 0, 0, 1, 0, // A
    ];
  }

  /// Draws selection border and handles
  void _drawSelection(
    Canvas canvas,
    ImageElement imageElement,
    ui.Image image,
  ) {
    canvas.save();
    canvas.translate(imageElement.position.dx, imageElement.position.dy);
    canvas.rotate(imageElement.rotation);

    final scaledWidth = image.width.toDouble() * imageElement.scale;
    final scaledHeight = image.height.toDouble() * imageElement.scale;

    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: scaledWidth,
      height: scaledHeight,
    );

    // Ombra sottile per evidenziare la selezione
    final shadowPaint =
        Paint()
          ..color = Colors.blue.withValues(alpha: 0.1)
          ..style = PaintingStyle.fill;

    canvas.drawRect(rect.inflate(4), shadowPaint);

    // Bordo selezione more sottile e professionale
    final borderPaint =
        Paint()
          ..color = Colors.blue.shade600
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;

    canvas.drawRect(rect, borderPaint);

    // Handle di resize more piccoli e professionali (4 angoli)
    final handlePaint =
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill;

    final handleBorderPaint =
        Paint()
          ..color = Colors.blue.shade600
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;

    final handles = [
      rect.topLeft,
      rect.topRight,
      rect.bottomLeft,
      rect.bottomRight,
    ];

    const handleRadius = 5.0; // Più piccoli per aspetto professionale

    for (final handlePos in handles) {
      // White circle with blue border
      canvas.drawCircle(handlePos, handleRadius, handlePaint);
      canvas.drawCircle(handlePos, handleRadius, handleBorderPaint);
    }
    canvas.restore();
  }

  /// 🎨 Draw border and editing overlay (in absolute coordinates)
  void _drawEditingOverlayBorder(
    Canvas canvas,
    ImageElement imageElement,
    ui.Image image,
  ) {
    canvas.save();
    canvas.translate(imageElement.position.dx, imageElement.position.dy);
    canvas.rotate(imageElement.rotation);

    final scaledWidth = image.width.toDouble() * imageElement.scale;
    final scaledHeight = image.height.toDouble() * imageElement.scale;

    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: scaledWidth,
      height: scaledHeight,
    );

    // Bordo verde brillante per indicare mode editing
    final editBorderPaint =
        Paint()
          ..color = Colors.green.shade500
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0;

    canvas.drawRect(rect, editBorderPaint);

    // Overlay semi-transparent verde chiaro
    final overlayPaint =
        Paint()
          ..color = Colors.green.withValues(alpha: 0.08)
          ..style = PaintingStyle.fill;

    canvas.drawRect(rect, overlayPaint);

    // Label "EDITING" nell'angolo in alto a sinistra
    final textPainter = TextPainter(
      text: TextSpan(
        text: 'EDITING',
        style: TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          backgroundColor: Colors.green.shade600,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, rect.topLeft + const Offset(8, 8));

    canvas.restore();
  }

  /// Draws a single complete stroke
  /// [scale] is la scala of the image corrente, usata per compensare la larghezza of the stroke
  void _drawStroke(Canvas canvas, ProStroke stroke, [double scale = 1.0]) {
    if (stroke.points.isEmpty) return;

    // 🔄 COMPENSATE FOR SCALE:
    // Divide baseWidth by scale so that when canvas is scaled,
    // the effective width remains visualWidth.
    final scaledBaseWidth = stroke.baseWidth / scale;

    // Use the exact same brush implementations as CurrentStrokePainter
    switch (stroke.penType) {
      case ProPenType.ballpoint:
        BallpointBrush.drawStroke(
          canvas,
          stroke.points,
          stroke.color,
          scaledBaseWidth,
        );
        break;
      case ProPenType.fountain:
        FountainPenBrush.drawStroke(
          canvas,
          stroke.points,
          stroke.color,
          scaledBaseWidth,
        );
        break;
      case ProPenType.pencil:
        PencilBrush.drawStroke(
          canvas,
          stroke.points,
          stroke.color,
          scaledBaseWidth,
        );
        break;
      case ProPenType.highlighter:
        HighlighterBrush.drawStroke(
          canvas,
          stroke.points,
          stroke.color,
          scaledBaseWidth,
        );
        break;
      case ProPenType.watercolor:
      case ProPenType.marker:
      case ProPenType.charcoal:
        BallpointBrush.drawStroke(
          canvas,
          stroke.points,
          stroke.color,
          scaledBaseWidth,
        );
        break;
    }
  }

  /// Draws the current stroke in real-time
  void _drawCurrentStroke(Canvas canvas, List<ProDrawingPoint> points) {
    if (points.isEmpty) return;

    final paint =
        Paint()
          ..color =
              Colors
                  .black // Puoi personalizzare
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0;

    final path = Path();
    path.moveTo(points.first.position.dx, points.first.position.dy);

    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].position.dx, points[i].position.dy);
    }

    canvas.drawPath(path, paint);
  }

  /// 🔄 Draw a loading placeholder for images still being downloaded
  void _drawLoadingPlaceholder(Canvas canvas, ImageElement imageElement) {
    canvas.save();
    canvas.translate(imageElement.position.dx, imageElement.position.dy);

    if (imageElement.rotation != 0) {
      canvas.rotate(imageElement.rotation);
    }
    if (imageElement.scale != 1.0) {
      canvas.scale(imageElement.scale);
    }

    // Default placeholder size
    const placeholderWidth = 200.0;
    const placeholderHeight = 150.0;
    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: placeholderWidth,
      height: placeholderHeight,
    );

    // 🌟 Pulsing background opacity (driven by loadingPulse)
    final pulseOpacity = 0.7 + 0.3 * math.sin(loadingPulse * math.pi * 2);

    // Background — dark rounded rect with pulse
    final bgPaint =
        Paint()
          ..color = Color.fromRGBO(42, 42, 46, pulseOpacity)
          ..style = PaintingStyle.fill;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(12));
    canvas.drawRRect(rrect, bgPaint);

    // 💫 Subtle glow border that pulses
    final glowPaint =
        Paint()
          ..color = Color.fromRGBO(100, 149, 237, 0.15 + 0.2 * pulseOpacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 4);
    canvas.drawRRect(rrect, glowPaint);

    // Inner border
    final borderPaint =
        Paint()
          ..color = Color.fromRGBO(100, 149, 237, 0.3 + 0.2 * pulseOpacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0;
    canvas.drawRRect(rrect, borderPaint);

    // 🔄 Spinning progress arc
    final arcCenter = const Offset(0, -8);
    const arcRadius = 16.0;
    final arcPaint =
        Paint()
          ..color = const Color(0xFF6495ED)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round;

    final sweepAngle = math.pi * 1.2;
    final startAngle = loadingPulse * math.pi * 2;
    canvas.drawArc(
      Rect.fromCircle(center: arcCenter, radius: arcRadius),
      startAngle,
      sweepAngle,
      false,
      arcPaint,
    );

    // Track ring (subtle)
    final trackPaint =
        Paint()
          ..color = Colors.white10
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;
    canvas.drawCircle(arcCenter, arcRadius, trackPaint);

    // "Downloading..." text below spinner
    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'Downloading...',
        style: TextStyle(
          color: Color(0x99FFFFFF),
          fontSize: 11,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.3,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(-textPainter.width / 2, 18));

    canvas.restore();
  }

  @override
  bool shouldRepaint(ImagePainter oldDelegate) {
    // ⚡ Sempre repaint se c'è drag o resize attivo (aggiornamento real-time)
    if (imageTool.isDragging || imageTool.isResizing) {
      return true;
    }

    // ⚡ Sempre repaint se siamo in editing mode
    if (imageInEditMode != null || oldDelegate.imageInEditMode != null) {
      return true;
    }

    return images != oldDelegate.images ||
        selectedImage != oldDelegate.selectedImage ||
        loadedImages.length != oldDelegate.loadedImages.length ||
        imageEditingStrokes != oldDelegate.imageEditingStrokes ||
        currentEditingStroke != oldDelegate.currentEditingStroke ||
        loadingPulse != oldDelegate.loadingPulse;
  }
}
