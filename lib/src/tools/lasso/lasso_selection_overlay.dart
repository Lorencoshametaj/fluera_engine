import 'package:flutter/material.dart';
import '../../drawing/models/pro_drawing_point.dart';
import '../../core/models/shape_type.dart';
import '../../core/models/canvas_layer.dart';
import '../../layers/nebula_layer_controller.dart';
import '../../canvas/infinite_canvas_controller.dart';

/// Widget overlay showing elements selected by lasso (with animation)
class LassoSelectionOverlay extends StatefulWidget {
  final Set<String> selectedStrokeIds;
  final Set<String> selectedShapeIds;
  final NebulaLayerController layerController;
  final InfiniteCanvasController canvasController;

  const LassoSelectionOverlay({
    super.key,
    required this.selectedStrokeIds,
    required this.selectedShapeIds,
    required this.layerController,
    required this.canvasController,
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
    // Animazione pulsante per l'highlight
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.3, end: 0.6).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.selectedStrokeIds.isEmpty && widget.selectedShapeIds.isEmpty) {
      return const SizedBox.shrink();
    }

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return CustomPaint(
          painter: _SelectionHighlightPainter(
            selectedStrokeIds: widget.selectedStrokeIds,
            selectedShapeIds: widget.selectedShapeIds,
            layerController: widget.layerController,
            animationValue: _pulseAnimation.value,
            canvasController: widget.canvasController,
          ),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}

/// Painter per evidenziare gli selected elements (con effetti professionali)
class _SelectionHighlightPainter extends CustomPainter {
  final Set<String> selectedStrokeIds;
  final Set<String> selectedShapeIds;
  final NebulaLayerController layerController;
  final double animationValue;
  final InfiniteCanvasController canvasController;

  _SelectionHighlightPainter({
    required this.selectedStrokeIds,
    required this.selectedShapeIds,
    required this.layerController,
    required this.animationValue,
    required this.canvasController,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final activeLayer = layerController.layers.firstWhere(
      (layer) => layer.id == layerController.activeLayerId,
      orElse: () => layerController.layers.first,
    );

    // Evidenzia strokes selezionati
    for (final stroke in activeLayer.strokes) {
      if (selectedStrokeIds.contains(stroke.id)) {
        _drawStrokeHighlight(canvas, stroke);
      }
    }

    // Evidenzia shapes selezionati
    for (final shape in activeLayer.shapes) {
      if (selectedShapeIds.contains(shape.id)) {
        _drawShapeHighlight(canvas, shape);
      }
    }
  }

  void _drawStrokeHighlight(Canvas canvas, ProStroke stroke) {
    if (stroke.points.isEmpty) return;

    // Convert punti canvas in screen coordinates
    final path = Path();
    final firstScreen = canvasController.canvasToScreen(
      stroke.points.first.position,
    );
    path.moveTo(firstScreen.dx, firstScreen.dy);

    for (var i = 1; i < stroke.points.length; i++) {
      final screenPoint = canvasController.canvasToScreen(
        stroke.points[i].position,
      );
      path.lineTo(screenPoint.dx, screenPoint.dy);
    }

    // 1. Main border (blue, flat) - Stile PDF Viewer
    final mainPaint =
        Paint()
          ..color = Colors.blue.withValues(alpha: 0.7)
          ..strokeWidth = 4.0
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, mainPaint);

    // 2. Inner border bianco sottile
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
    // Convert punti canvas in screen coordinates
    final startScreen = canvasController.canvasToScreen(shape.startPoint);
    final endScreen = canvasController.canvasToScreen(shape.endPoint);

    final rect = Rect.fromPoints(startScreen, endScreen);
    final expandedRect = rect.inflate(8);

    // 1. Main border (blue, flat)
    final mainPaint =
        Paint()
          ..color = Colors.blue.withValues(alpha: 0.7)
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke;
    canvas.drawRect(expandedRect, mainPaint);

    // 2. Inner border
    final innerPaint =
        Paint()
          ..color = Colors.white.withValues(alpha: 0.5)
          ..strokeWidth = 1.0
          ..style = PaintingStyle.stroke;
    canvas.drawRect(expandedRect.deflate(1), innerPaint);

    // 3. Corner handles (maniglie angolari)
    final handlePaint =
        Paint()
          ..color = Colors.blue
          ..style = PaintingStyle.fill;

    final handleSize = 6.0;
    final corners = [
      expandedRect.topLeft,
      expandedRect.topRight,
      expandedRect.bottomLeft,
      expandedRect.bottomRight,
    ];

    for (final corner in corners) {
      // Alone bianco
      canvas.drawCircle(corner, handleSize + 2, Paint()..color = Colors.white);
      // Centro blu
      canvas.drawCircle(corner, handleSize, handlePaint);
    }
  }

  @override
  bool shouldRepaint(_SelectionHighlightPainter oldDelegate) {
    return selectedStrokeIds != oldDelegate.selectedStrokeIds ||
        selectedShapeIds != oldDelegate.selectedShapeIds ||
        animationValue != oldDelegate.animationValue;
  }
}
