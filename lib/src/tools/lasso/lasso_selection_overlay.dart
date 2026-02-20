import 'dart:math';
import 'package:flutter/material.dart';
import '../../drawing/models/pro_drawing_point.dart';
import '../../core/models/shape_type.dart';
import '../../core/models/canvas_layer.dart';
import '../../core/models/digital_text_element.dart';
import '../../core/models/image_element.dart';
import '../../layers/nebula_layer_controller.dart';
import '../../canvas/infinite_canvas_controller.dart';

/// Widget overlay showing elements selected by lasso (with animation).
///
/// Uses a single [selectedIds] set and determines element type by
/// checking the active layer's typed lists.
class LassoSelectionOverlay extends StatefulWidget {
  /// Unified set of all selected element IDs.
  final Set<String> selectedIds;
  final NebulaLayerController layerController;
  final InfiniteCanvasController canvasController;
  final bool isDragging;

  /// 🚀 PERF: Optional notifier for smooth repositioning during drag.
  final ValueNotifier<int>? dragNotifier;

  const LassoSelectionOverlay({
    super.key,
    required this.selectedIds,
    required this.layerController,
    required this.canvasController,
    this.isDragging = false,
    this.dragNotifier,
  });

  @override
  State<LassoSelectionOverlay> createState() => _LassoSelectionOverlayState();
}

class _LassoSelectionOverlayState extends State<LassoSelectionOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.3, end: 0.6).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // 🚀 Follow canvas transform (zoom/pan/rotate)
    widget.canvasController.addListener(_onTransformChanged);
    // 🚀 PERF: Listen to drag updates for smooth highlight repositioning
    widget.dragNotifier?.addListener(_onTransformChanged);
  }

  @override
  void dispose() {
    widget.canvasController.removeListener(_onTransformChanged);
    widget.dragNotifier?.removeListener(_onTransformChanged);
    _pulseController.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (widget.selectedIds.isEmpty) {
      return const SizedBox.shrink();
    }

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return CustomPaint(
          painter: _SelectionHighlightPainter(
            selectedIds: widget.selectedIds,
            layerController: widget.layerController,
            animationValue: _pulseAnimation.value,
            canvasController: widget.canvasController,
            isDragging: widget.isDragging,
          ),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}

/// Painter that highlights all selected elements with professional effects.
///
/// Determines element type dynamically from the active layer's typed lists.
class _SelectionHighlightPainter extends CustomPainter {
  final Set<String> selectedIds;
  final NebulaLayerController layerController;
  final double animationValue;
  final InfiniteCanvasController canvasController;
  final bool isDragging;

  _SelectionHighlightPainter({
    required this.selectedIds,
    required this.layerController,
    required this.animationValue,
    required this.canvasController,
    this.isDragging = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final activeLayer = layerController.layers.firstWhere(
      (layer) => layer.id == layerController.activeLayerId,
      orElse: () => layerController.layers.first,
    );

    // Highlight selected strokes
    for (final stroke in activeLayer.strokes) {
      if (selectedIds.contains(stroke.id)) {
        _drawStrokeHighlight(canvas, stroke);
      }
    }

    // Highlight selected shapes
    for (final shape in activeLayer.shapes) {
      if (selectedIds.contains(shape.id)) {
        _drawShapeHighlight(canvas, shape);
      }
    }

    // Highlight selected text elements
    for (final text in activeLayer.texts) {
      if (selectedIds.contains(text.id)) {
        _drawTextHighlight(canvas, text);
      }
    }

    // Highlight selected image elements
    for (final image in activeLayer.images) {
      if (selectedIds.contains(image.id)) {
        _drawImageHighlight(canvas, image);
      }
    }
  }

  void _drawStrokeHighlight(Canvas canvas, ProStroke stroke) {
    if (stroke.points.isEmpty) return;

    final path = Path();
    final screenPoints =
        stroke.points
            .map((p) => canvasController.canvasToScreen(p.position))
            .toList();

    if (screenPoints.length < 2) return;

    path.moveTo(screenPoints[0].dx, screenPoints[0].dy);

    if (screenPoints.length == 2) {
      path.lineTo(screenPoints[1].dx, screenPoints[1].dy);
    } else {
      // Smooth Catmull-Rom style interpolation using quadratic Bézier
      for (var i = 0; i < screenPoints.length - 1; i++) {
        final p0 = screenPoints[i];
        final p1 = screenPoints[i + 1];
        final midX = (p0.dx + p1.dx) / 2;
        final midY = (p0.dy + p1.dy) / 2;

        if (i == 0) {
          // First segment: line to midpoint
          path.lineTo(midX, midY);
        } else {
          // Use previous point as control point, midpoint as endpoint
          path.quadraticBezierTo(p0.dx, p0.dy, midX, midY);
        }
      }
      // Final segment: curve to last point
      final last = screenPoints.last;
      final secondLast = screenPoints[screenPoints.length - 2];
      path.quadraticBezierTo(secondLast.dx, secondLast.dy, last.dx, last.dy);
    }

    // Blue highlight border
    final mainPaint =
        Paint()
          ..color = Colors.blue.withValues(alpha: 0.7)
          ..strokeWidth = 4.0
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, mainPaint);

    // White inner border
    final innerPaint =
        Paint()
          ..color = Colors.white.withValues(alpha: 0.5)
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, innerPaint);
  }

  void _drawShapeHighlight(Canvas canvas, GeometricShape shape) {
    final startScreen = canvasController.canvasToScreen(shape.startPoint);
    final endScreen = canvasController.canvasToScreen(shape.endPoint);

    final rect = Rect.fromPoints(startScreen, endScreen);
    final expandedRect = rect.inflate(8);

    // Blue border
    final mainPaint =
        Paint()
          ..color = Colors.blue.withValues(alpha: 0.7)
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke;
    canvas.drawRect(expandedRect, mainPaint);

    // White inner border
    final innerPaint =
        Paint()
          ..color = Colors.white.withValues(alpha: 0.5)
          ..strokeWidth = 1.0
          ..style = PaintingStyle.stroke;
    canvas.drawRect(expandedRect.deflate(1), innerPaint);

    // Corner handles (hidden during drag-move)
    if (!isDragging) _drawCornerHandles(canvas, expandedRect);
  }

  void _drawTextHighlight(Canvas canvas, DigitalTextElement text) {
    final screenPos = canvasController.canvasToScreen(text.position);

    // Estimate text size using TextPainter
    final textPainter = TextPainter(
      text: TextSpan(
        text: text.text,
        style: TextStyle(
          fontSize: text.fontSize * text.scale,
          fontWeight: text.fontWeight,
          fontFamily: text.fontFamily,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final scale = canvasController.scale;
    final rect = Rect.fromLTWH(
      screenPos.dx,
      screenPos.dy,
      max(textPainter.width * scale, 60),
      max(textPainter.height * scale, 24),
    );
    final expandedRect = rect.inflate(6);

    // Deep purple border for text
    final mainPaint =
        Paint()
          ..color = Colors.deepPurple.withValues(alpha: 0.7)
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke;
    canvas.drawRRect(
      RRect.fromRectAndRadius(expandedRect, const Radius.circular(4)),
      mainPaint,
    );

    // Semi-transparent fill
    final fillPaint =
        Paint()
          ..color = Colors.deepPurple.withValues(alpha: 0.08)
          ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(expandedRect, const Radius.circular(4)),
      fillPaint,
    );

    // Text icon indicator
    final iconPaint =
        Paint()
          ..color = Colors.deepPurple.withValues(alpha: 0.6)
          ..style = PaintingStyle.fill;
    canvas.drawCircle(
      expandedRect.topRight + const Offset(4, -4),
      8,
      iconPaint,
    );
    canvas.drawCircle(
      expandedRect.topRight + const Offset(4, -4),
      6,
      Paint()..color = Colors.white,
    );

    // "T" letter in indicator
    final tp = TextPainter(
      text: TextSpan(
        text: 'T',
        style: TextStyle(
          color: Colors.deepPurple,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      expandedRect.topRight + Offset(4 - tp.width / 2, -4 - tp.height / 2),
    );
  }

  void _drawImageHighlight(Canvas canvas, ImageElement image) {
    final screenPos = canvasController.canvasToScreen(image.position);

    final scale = canvasController.scale;
    final size = 200.0 * image.scale * scale;
    final rect = Rect.fromLTWH(screenPos.dx, screenPos.dy, size, size);
    final expandedRect = rect.inflate(6);

    // Teal border for images
    final mainPaint =
        Paint()
          ..color = Colors.teal.withValues(alpha: 0.7)
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke;
    canvas.drawRRect(
      RRect.fromRectAndRadius(expandedRect, const Radius.circular(4)),
      mainPaint,
    );

    // Semi-transparent fill
    final fillPaint =
        Paint()
          ..color = Colors.teal.withValues(alpha: 0.08)
          ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(expandedRect, const Radius.circular(4)),
      fillPaint,
    );

    // Corner handles (hidden during drag-move)
    if (!isDragging)
      _drawCornerHandles(canvas, expandedRect, color: Colors.teal);
  }

  /// Draw corner handles on a rect.
  void _drawCornerHandles(
    Canvas canvas,
    Rect rect, {
    Color color = Colors.blue,
  }) {
    final handlePaint =
        Paint()
          ..color = color
          ..style = PaintingStyle.fill;

    const handleSize = 6.0;
    final corners = [
      rect.topLeft,
      rect.topRight,
      rect.bottomLeft,
      rect.bottomRight,
    ];

    for (final corner in corners) {
      canvas.drawCircle(corner, handleSize + 2, Paint()..color = Colors.white);
      canvas.drawCircle(corner, handleSize, handlePaint);
    }
  }

  @override
  bool shouldRepaint(_SelectionHighlightPainter oldDelegate) {
    return selectedIds != oldDelegate.selectedIds ||
        animationValue != oldDelegate.animationValue;
  }
}
