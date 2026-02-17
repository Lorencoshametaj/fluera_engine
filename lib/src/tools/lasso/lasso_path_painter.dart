import 'package:flutter/material.dart';
import '../../canvas/infinite_canvas_controller.dart';

/// Widget showing the lasso path during drawing
class LassoPathPainter extends CustomPainter {
  final List<Offset> path;
  final Color color;
  final InfiniteCanvasController canvasController;

  LassoPathPainter({
    required this.path,
    this.color = Colors.blue,
    required this.canvasController,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (path.length < 2) return;

    // Convert i punti canvas in screen coordinates
    final screenPath =
        path.map((p) => canvasController.canvasToScreen(p)).toList();

    // Create il path con screen coordinates
    final pathToDraw = Path();
    pathToDraw.moveTo(screenPath.first.dx, screenPath.first.dy);
    for (var i = 1; i < screenPath.length; i++) {
      pathToDraw.lineTo(screenPath[i].dx, screenPath[i].dy);
    } // 1. Glow esterno (alone luminoso)
    final glowPaint =
        Paint()
          ..color = color.withValues(alpha: 0.15)
          ..strokeWidth = 8.0
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);
    canvas.drawPath(pathToDraw, glowPaint);

    // 2. Area fill (semi-transparent with gradient)
    final fillPaint =
        Paint()
          ..color = color.withValues(alpha: 0.08)
          ..style = PaintingStyle.fill;
    canvas.drawPath(pathToDraw, fillPaint);

    // 3. Main border (animated dash pattern)
    final mainPaint =
        Paint()
          ..color = color.withValues(alpha: 0.8)
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;

    // Create dash pattern (linee tratteggiate)
    final dashPath = _createDashedPath(pathToDraw, dashLength: 8, gapLength: 4);
    canvas.drawPath(dashPath, mainPaint);

    // 4. Inner border more chiaro (depth effect)
    final innerPaint =
        Paint()
          ..color = Colors.white.withValues(alpha: 0.4)
          ..strokeWidth = 1.0
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(pathToDraw, innerPaint);

    // 5. Key points along the path (every 30 points for performance)
    final pointPaint =
        Paint()
          ..color = color
          ..style = PaintingStyle.fill;

    for (var i = 0; i < screenPath.length; i += 30) {
      // Punto esterno (bianco)
      canvas.drawCircle(
        screenPath[i],
        3.5,
        Paint()..color = Colors.white.withValues(alpha: 0.9),
      );
      // Punto interno (colore)
      canvas.drawCircle(screenPath[i], 2.0, pointPaint);
    }

    // 6. Punto iniziale e finale speciali
    if (screenPath.isNotEmpty) {
      // Punto iniziale (more grande)
      _drawSpecialPoint(canvas, screenPath.first, color, isStart: true);
      // Punto finale (forma diversa se vicino all'inizio per chiudere)
      if (screenPath.length > 3) {
        final distance = (screenPath.last - screenPath.first).distance;
        _drawSpecialPoint(
          canvas,
          screenPath.last,
          color,
          isStart: false,
          isClosing: distance < 50,
        );
      }
    }
  }

  /// Draws punti speciali (inizio/fine)
  void _drawSpecialPoint(
    Canvas canvas,
    Offset point,
    Color color, {
    required bool isStart,
    bool isClosing = false,
  }) {
    // Alone esterno
    canvas.drawCircle(
      point,
      8.0,
      Paint()
        ..color = color.withValues(alpha: 0.2)
        ..style = PaintingStyle.fill,
    );

    // White border
    canvas.drawCircle(
      point,
      5.5,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill,
    );

    // Centro colorato
    canvas.drawCircle(
      point,
      4.0,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );

    // Indicatore per punto di chiusura
    if (!isStart && isClosing) {
      // Anello verde per indicare che can chiudere
      canvas.drawCircle(
        point,
        7.0,
        Paint()
          ..color = Colors.green.withValues(alpha: 0.6)
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke,
      );
    }
  }

  /// Creates path con linee tratteggiate
  Path _createDashedPath(
    Path source, {
    required double dashLength,
    required double gapLength,
  }) {
    final dashes = Path();
    final metricsIterator = source.computeMetrics().iterator;

    while (metricsIterator.moveNext()) {
      final metric = metricsIterator.current;
      double distance = 0.0;
      bool draw = true;

      while (distance < metric.length) {
        final length = draw ? dashLength : gapLength;
        final endDistance = (distance + length).clamp(0.0, metric.length);

        if (draw) {
          dashes.addPath(
            metric.extractPath(distance, endDistance),
            Offset.zero,
          );
        }

        distance = endDistance;
        draw = !draw;
      }
    }

    return dashes;
  }

  @override
  bool shouldRepaint(LassoPathPainter oldDelegate) {
    return path != oldDelegate.path;
  }
}
