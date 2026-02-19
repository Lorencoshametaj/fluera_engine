part of '../../nebula_canvas_screen.dart';

/// 🔷 Shape Recognition Feedback — toast + morph animation overlay.
///
/// Shows a brief confirmation toast with shape name and confidence,
/// and optionally animates the freehand stroke morphing into the
/// recognized shape.
extension ShapeRecognitionFeedbackUI on _NebulaCanvasScreenState {
  // ──────────────────────────────────────────────────────────────────
  // Toast Widget Builder
  // ──────────────────────────────────────────────────────────────────

  /// Build the shape recognition toast overlay.
  /// Uses [_shapeRecognitionToast] ValueNotifier to show/hide.
  Widget _buildShapeRecognitionToast() {
    return ValueListenableBuilder<_ShapeRecognitionToastData?>(
      valueListenable: _shapeRecognitionToast,
      builder: (context, data, _) {
        if (data == null) return const SizedBox.shrink();

        return Positioned(
          bottom: 80,
          left: 0,
          right: 0,
          child: Center(
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 300),
              tween: Tween(begin: 0.0, end: 1.0),
              builder: (context, opacity, child) {
                return Opacity(
                  opacity: opacity,
                  child: Transform.translate(
                    offset: Offset(0, 10 * (1 - opacity)),
                    child: child,
                  ),
                );
              },
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: data.accentColor.withValues(alpha: 0.3),
                        blurRadius: 12,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(data.icon, color: data.accentColor, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        data.shapeName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${(data.confidence * 100).round()}%',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Show a recognition toast for the given result.
  void _showShapeRecognitionToast(ShapeRecognitionResult result) {
    final data = _ShapeRecognitionToastData.fromResult(result);
    _shapeRecognitionToast.value = data;

    // Auto-dismiss after 1.2 seconds
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (_shapeRecognitionToast.value == data) {
        _shapeRecognitionToast.value = null;
      }
    });
  }

  // ──────────────────────────────────────────────────────────────────
  // Ghost Suggestion Overlay
  // ──────────────────────────────────────────────────────────────────

  /// Show a ghost suggestion overlay for the recognized shape.
  /// Auto-accepts after 2 seconds if user doesn't interact.
  void _showGhostSuggestion(
    GeometricShape shape,
    ShapeRecognitionResult result,
  ) {
    _ghostSuggestion.value = _GhostSuggestionData(shape: shape, result: result);

    // Auto-accept after 2s
    Future.delayed(const Duration(milliseconds: 2000), () {
      if (_ghostSuggestion.value?.shape.id == shape.id) {
        _acceptGhostSuggestion();
      }
    });
  }

  /// Accept the ghost suggestion — commit the shape.
  void _acceptGhostSuggestion() {
    final data = _ghostSuggestion.value;
    if (data == null) return;

    _layerController.addShape(data.shape);
    _toolController.clearMultiStrokeBuffer();
    HapticFeedback.mediumImpact();
    DrawingPainter.invalidateAllTiles();
    _showShapeRecognitionToast(data.result);
    _ghostSuggestion.value = null;
    _autoSaveCanvas();
  }

  /// Dismiss the ghost suggestion — keep original stroke.
  void _dismissGhostSuggestion() {
    _ghostSuggestion.value = null;
    HapticFeedback.lightImpact();
  }

  /// Build the ghost suggestion overlay widget.
  Widget _buildGhostSuggestionOverlay() {
    return ValueListenableBuilder<_GhostSuggestionData?>(
      valueListenable: _ghostSuggestion,
      builder: (context, data, _) {
        if (data == null) return const SizedBox.shrink();

        // Convert shape bounding box to screen coordinates
        final topLeft = _canvasController.canvasToScreen(data.shape.startPoint);
        final bottomRight = _canvasController.canvasToScreen(
          data.shape.endPoint,
        );
        final center = Offset(
          (topLeft.dx + bottomRight.dx) / 2,
          (topLeft.dy + bottomRight.dy) / 2,
        );

        return Stack(
          children: [
            // Ghost shape preview (semi-transparent)
            Positioned(
              left: topLeft.dx,
              top: topLeft.dy,
              width: (bottomRight.dx - topLeft.dx).abs(),
              height: (bottomRight.dy - topLeft.dy).abs(),
              child: IgnorePointer(
                child: TweenAnimationBuilder<double>(
                  duration: const Duration(milliseconds: 400),
                  tween: Tween(begin: 0.0, end: 1.0),
                  builder: (context, value, child) {
                    return Opacity(opacity: value * 0.4, child: child);
                  },
                  child: CustomPaint(
                    painter: _GhostShapePainter(
                      type: data.shape.type,
                      color: data.shape.color,
                      rotation: data.shape.rotation,
                    ),
                    size: Size.infinite,
                  ),
                ),
              ),
            ),

            // Accept/Reject buttons
            Positioned(
              left: center.dx - 40,
              top: bottomRight.dy + 8,
              child: TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 300),
                tween: Tween(begin: 0.0, end: 1.0),
                builder: (context, opacity, child) {
                  return Opacity(
                    opacity: opacity,
                    child: Transform.translate(
                      offset: Offset(0, 6 * (1 - opacity)),
                      child: child,
                    ),
                  );
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Accept button
                    GestureDetector(
                      onTap: _acceptGhostSuggestion,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.9),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.green.withValues(alpha: 0.3),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.check,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Reject button
                    GestureDetector(
                      onTap: _dismissGhostSuggestion,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.9),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.red.withValues(alpha: 0.3),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Data class for shape recognition toast.
class _ShapeRecognitionToastData {
  final String shapeName;
  final double confidence;
  final IconData icon;
  final Color accentColor;

  const _ShapeRecognitionToastData({
    required this.shapeName,
    required this.confidence,
    required this.icon,
    required this.accentColor,
  });

  factory _ShapeRecognitionToastData.fromResult(ShapeRecognitionResult result) {
    final (name, icon, color) = switch (result.type!) {
      ShapeType.circle => (
        result.isEllipse ? 'Ellipse' : 'Circle',
        Icons.circle_outlined,
        Colors.blue,
      ),
      ShapeType.rectangle => (
        result.rotationAngle != 0.0 ? 'Rotated Rect' : 'Rectangle',
        Icons.rectangle_outlined,
        Colors.green,
      ),
      ShapeType.triangle => ('Triangle', Icons.change_history, Colors.orange),
      ShapeType.line => ('Line', Icons.horizontal_rule, Colors.teal),
      ShapeType.arrow => ('Arrow', Icons.arrow_forward, Colors.purple),
      ShapeType.star => ('Star', Icons.star_outline, Colors.amber),
      ShapeType.diamond => ('Diamond', Icons.diamond_outlined, Colors.pink),
      ShapeType.pentagon => ('Pentagon', Icons.pentagon_outlined, Colors.cyan),
      ShapeType.hexagon => ('Hexagon', Icons.hexagon_outlined, Colors.indigo),
      _ => ('Shape', Icons.auto_fix_high, Colors.grey),
    };

    return _ShapeRecognitionToastData(
      shapeName: name,
      confidence: result.confidence,
      icon: icon,
      accentColor: color,
    );
  }
}

/// Data class for ghost suggestion overlay.
class _GhostSuggestionData {
  final GeometricShape shape;
  final ShapeRecognitionResult result;

  const _GhostSuggestionData({required this.shape, required this.result});
}

/// CustomPainter that renders a ghost (semi-transparent dashed) shape preview.
class _GhostShapePainter extends CustomPainter {
  final ShapeType type;
  final Color color;
  final double rotation;

  _GhostShapePainter({
    required this.type,
    required this.color,
    this.rotation = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = color.withValues(alpha: 0.6)
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke
          ..isAntiAlias = true;

    final rect = Offset.zero & size;
    final center = rect.center;

    canvas.save();
    if (rotation != 0.0) {
      canvas.translate(center.dx, center.dy);
      canvas.rotate(rotation);
      canvas.translate(-center.dx, -center.dy);
    }

    switch (type) {
      case ShapeType.circle:
        canvas.drawOval(rect, paint);
        break;
      case ShapeType.rectangle:
        canvas.drawRect(rect, paint);
        break;
      case ShapeType.triangle:
        final path =
            Path()
              ..moveTo(center.dx, rect.top)
              ..lineTo(rect.right, rect.bottom)
              ..lineTo(rect.left, rect.bottom)
              ..close();
        canvas.drawPath(path, paint);
        break;
      case ShapeType.diamond:
        final path =
            Path()
              ..moveTo(center.dx, rect.top)
              ..lineTo(rect.right, center.dy)
              ..lineTo(center.dx, rect.bottom)
              ..lineTo(rect.left, center.dy)
              ..close();
        canvas.drawPath(path, paint);
        break;
      case ShapeType.star:
        _drawStar(canvas, center, size, paint);
        break;
      case ShapeType.pentagon:
        _drawRegularPolygon(canvas, center, size, 5, paint);
        break;
      case ShapeType.hexagon:
        _drawRegularPolygon(canvas, center, size, 6, paint);
        break;
      case ShapeType.line:
        canvas.drawLine(
          Offset(rect.left, center.dy),
          Offset(rect.right, center.dy),
          paint,
        );
        break;
      case ShapeType.arrow:
        final arrowEnd = Offset(rect.right - 10, center.dy);
        canvas.drawLine(Offset(rect.left, center.dy), arrowEnd, paint);
        final headSize = size.shortestSide * 0.2;
        canvas.drawLine(
          arrowEnd,
          Offset(arrowEnd.dx - headSize, center.dy - headSize),
          paint,
        );
        canvas.drawLine(
          arrowEnd,
          Offset(arrowEnd.dx - headSize, center.dy + headSize),
          paint,
        );
        break;
      default:
        canvas.drawRect(rect, paint);
    }

    canvas.restore();
  }

  void _drawStar(Canvas canvas, Offset center, Size size, Paint paint) {
    final path = Path();
    final outerR = size.shortestSide / 2;
    final innerR = outerR * 0.4;
    for (int i = 0; i < 10; i++) {
      final r = i.isEven ? outerR : innerR;
      final angle = math.pi * i / 5 - math.pi / 2;
      final point = Offset(
        center.dx + r * math.cos(angle),
        center.dy + r * math.sin(angle),
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawRegularPolygon(
    Canvas canvas,
    Offset center,
    Size size,
    int sides,
    Paint paint,
  ) {
    final path = Path();
    final r = size.shortestSide / 2;
    for (int i = 0; i < sides; i++) {
      final angle = 2 * math.pi * i / sides - math.pi / 2;
      final point = Offset(
        center.dx + r * math.cos(angle),
        center.dy + r * math.sin(angle),
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_GhostShapePainter oldDelegate) =>
      type != oldDelegate.type ||
      color != oldDelegate.color ||
      rotation != oldDelegate.rotation;
}
