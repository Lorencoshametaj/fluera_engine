import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/models/digital_text_element.dart';
import '../../core/models/image_element.dart';
import '../../drawing/models/pro_drawing_point.dart';
import '../../core/models/shape_type.dart';
import '../services/time_travel_playback_engine.dart';
import '../../canvas/infinite_canvas_controller.dart';

/// 🔮 Overlay per selezione lasso in mode Time Travel
///
/// Captures user gesture → draws dashed lasso →
/// highlights selected elements → confirmation callback with elements.
class TimeTravelLassoOverlay extends StatefulWidget {
  final TimeTravelPlaybackEngine engine;
  final InfiniteCanvasController canvasController;
  final VoidCallback onCancel;
  final void Function(
    List<ProStroke> strokes,
    List<GeometricShape> shapes,
    List<ImageElement> images,
    List<DigitalTextElement> texts,
  )
  onConfirm;

  const TimeTravelLassoOverlay({
    super.key,
    required this.engine,
    required this.canvasController,
    required this.onCancel,
    required this.onConfirm,
  });

  @override
  State<TimeTravelLassoOverlay> createState() => _TimeTravelLassoOverlayState();
}

class _TimeTravelLassoOverlayState extends State<TimeTravelLassoOverlay>
    with SingleTickerProviderStateMixin {
  /// Lasso points in screen coordinates
  final List<Offset> _screenPoints = [];

  /// Points converted to canvas coordinates (for hit test)
  final List<Offset> _canvasPoints = [];

  /// True when the lasso was chiuso (finger up)
  bool _lassoClosed = false;

  /// Selected elements (hit test completed)
  List<ProStroke> _selectedStrokes = [];
  List<GeometricShape> _selectedShapes = [];
  List<ImageElement> _selectedImages = [];
  List<DigitalTextElement> _selectedTexts = [];

  /// Dash animation
  late AnimationController _dashAnimController;

  int get _totalSelected =>
      _selectedStrokes.length +
      _selectedShapes.length +
      _selectedImages.length +
      _selectedTexts.length;

  @override
  void initState() {
    super.initState();
    _dashAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _dashAnimController.dispose();
    super.dispose();
  }

  // ─── Gesture Handling ──────────────────────────────────

  void _onPanStart(DragStartDetails details) {
    if (_lassoClosed) {
      // Reset se si ridisegna
      setState(() {
        _screenPoints.clear();
        _canvasPoints.clear();
        _lassoClosed = false;
        _selectedStrokes = [];
        _selectedShapes = [];
        _selectedImages = [];
        _selectedTexts = [];
      });
    }

    final screenPt = details.localPosition;
    final canvasPt = widget.canvasController.screenToCanvas(screenPt);
    setState(() {
      _screenPoints.add(screenPt);
      _canvasPoints.add(canvasPt);
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_lassoClosed) return;

    final screenPt = details.localPosition;
    final canvasPt = widget.canvasController.screenToCanvas(screenPt);
    setState(() {
      _screenPoints.add(screenPt);
      _canvasPoints.add(canvasPt);
    });
  }

  void _onPanEnd(DragEndDetails details) {
    if (_lassoClosed || _canvasPoints.length < 3) return;

    // Cloif the lasso
    setState(() {
      _lassoClosed = true;
    });

    // Execute hit test
    _performHitTest();
  }

  // ─── Hit Testing ───────────────────────────────────────

  void _performHitTest() {
    if (_canvasPoints.length < 3) return;

    // Create path from lasso in canvas coordinates
    final lassoPath = Path();
    lassoPath.moveTo(_canvasPoints.first.dx, _canvasPoints.first.dy);
    for (int i = 1; i < _canvasPoints.length; i++) {
      lassoPath.lineTo(_canvasPoints[i].dx, _canvasPoints[i].dy);
    }
    lassoPath.close();

    final strokes = <ProStroke>[];
    final shapes = <GeometricShape>[];
    final images = <ImageElement>[];
    final texts = <DigitalTextElement>[];

    for (final layer in widget.engine.currentLayers) {
      if (!layer.isVisible) continue;

      // Test strokes: centro del bounds dentro il lasso
      for (final stroke in layer.strokes) {
        if (stroke.points.isEmpty) continue;
        final center = stroke.bounds.center;
        if (lassoPath.contains(center)) {
          strokes.add(stroke);
        }
      }

      // Test shapes: centro del rect startPoint→endPoint
      for (final shape in layer.shapes) {
        final center = Offset(
          (shape.startPoint.dx + shape.endPoint.dx) / 2,
          (shape.startPoint.dy + shape.endPoint.dy) / 2,
        );
        if (lassoPath.contains(center)) {
          shapes.add(shape);
        }
      }

      // Test images: position of the image
      for (final image in layer.images) {
        if (lassoPath.contains(image.position)) {
          images.add(image);
        }
      }

      // Test texts: position del testo
      for (final text in layer.texts) {
        if (lassoPath.contains(text.position)) {
          texts.add(text);
        }
      }
    }

    setState(() {
      _selectedStrokes = strokes;
      _selectedShapes = shapes;
      _selectedImages = images;
      _selectedTexts = texts;
    });
  }

  // ─── Build ─────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Stack(
      children: [
        // Layer 1: Gesture detector + custom painter (full area)
        Positioned.fill(
          child: GestureDetector(
            onPanStart: _onPanStart,
            onPanUpdate: _onPanUpdate,
            onPanEnd: _onPanEnd,
            behavior: HitTestBehavior.opaque,
            child: AnimatedBuilder(
              animation: _dashAnimController,
              builder: (context, _) {
                return CustomPaint(
                  painter: _LassoPainter(
                    screenPoints: _screenPoints,
                    isClosed: _lassoClosed,
                    dashPhase: _dashAnimController.value * 20,
                    selectedBoundsScreen:
                        _lassoClosed ? _getSelectedBoundsInScreen() : [],
                    accentColor: cs.primary,
                    highlightColor: cs.primaryContainer,
                  ),
                );
              },
            ),
          ),
        ),

        // Layer 2: Close button (torna al player)
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          right: 12,
          child: Material(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(20),
            elevation: 4,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: widget.onCancel,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(Icons.close_rounded, color: cs.onSurface, size: 22),
              ),
            ),
          ),
        ),

        // Layer 2: Bottom control bar
        Positioned(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(context).padding.bottom + 16,
          child: Material(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(28),
            elevation: 8,
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  // Info
                  Icon(Icons.gesture_rounded, color: cs.primary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _lassoClosed
                          ? '$_totalSelected selected elements'
                          : 'Draw un cerchio attorno agli elementi',
                      style: tt.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),

                  // Cancel
                  TextButton(
                    onPressed: widget.onCancel,
                    child: Text('Annulla', style: TextStyle(color: cs.error)),
                  ),

                  const SizedBox(width: 8),

                  // Confirm
                  FilledButton.icon(
                    onPressed:
                        _totalSelected > 0
                            ? () => widget.onConfirm(
                              _selectedStrokes,
                              _selectedShapes,
                              _selectedImages,
                              _selectedTexts,
                            )
                            : null,
                    icon: const Icon(Icons.rocket_launch_rounded, size: 18),
                    label: const Text('Al presente'),
                    style: FilledButton.styleFrom(
                      backgroundColor: cs.primary,
                      foregroundColor: cs.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Convert selected element bounds to screen coordinates
  List<Rect> _getSelectedBoundsInScreen() {
    final rects = <Rect>[];
    final ctrl = widget.canvasController;

    for (final s in _selectedStrokes) {
      final tl = ctrl.canvasToScreen(s.bounds.topLeft);
      final br = ctrl.canvasToScreen(s.bounds.bottomRight);
      rects.add(Rect.fromPoints(tl, br));
    }

    for (final s in _selectedShapes) {
      final tl = ctrl.canvasToScreen(
        Offset(
          math.min(s.startPoint.dx, s.endPoint.dx),
          math.min(s.startPoint.dy, s.endPoint.dy),
        ),
      );
      final br = ctrl.canvasToScreen(
        Offset(
          math.max(s.startPoint.dx, s.endPoint.dx),
          math.max(s.startPoint.dy, s.endPoint.dy),
        ),
      );
      rects.add(Rect.fromPoints(tl, br));
    }

    for (final img in _selectedImages) {
      final tl = ctrl.canvasToScreen(img.position);
      // Approximate image size
      rects.add(Rect.fromLTWH(tl.dx, tl.dy, 80 * ctrl.scale, 80 * ctrl.scale));
    }

    for (final t in _selectedTexts) {
      final tl = ctrl.canvasToScreen(t.position);
      rects.add(Rect.fromLTWH(tl.dx, tl.dy, 100 * ctrl.scale, 30 * ctrl.scale));
    }

    return rects;
  }
}

// ─── Custom Painter ──────────────────────────────────────

class _LassoPainter extends CustomPainter {
  final List<Offset> screenPoints;
  final bool isClosed;
  final double dashPhase;
  final List<Rect> selectedBoundsScreen;
  final Color accentColor;
  final Color highlightColor;

  _LassoPainter({
    required this.screenPoints,
    required this.isClosed,
    required this.dashPhase,
    required this.selectedBoundsScreen,
    required this.accentColor,
    required this.highlightColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (screenPoints.isEmpty) return;

    // ─── Highlight selected ──────────────────────
    if (isClosed) {
      for (final rect in selectedBoundsScreen) {
        // Glow
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect.inflate(4), const Radius.circular(8)),
          Paint()
            ..color = highlightColor.withValues(alpha: 0.3)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
        );
        // Border
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect.inflate(2), const Radius.circular(6)),
          Paint()
            ..color = accentColor.withValues(alpha: 0.6)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }

    // ─── Lasso path ─────────────────────────────────
    final path = Path();
    path.moveTo(screenPoints.first.dx, screenPoints.first.dy);
    for (int i = 1; i < screenPoints.length; i++) {
      path.lineTo(screenPoints[i].dx, screenPoints[i].dy);
    }
    if (isClosed) {
      path.close();

      // Semi-transparent fill
      canvas.drawPath(
        path,
        Paint()..color = accentColor.withValues(alpha: 0.08),
      );
    }

    // Animated dash
    final dashPaint =
        Paint()
          ..color = accentColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round;

    // Draw with dash pattern
    final metric = path.computeMetrics().firstOrNull;
    if (metric != null) {
      const dashLength = 8.0;
      const gapLength = 6.0;
      double distance = dashPhase;
      while (distance < metric.length) {
        final start = distance;
        final end = math.min(distance + dashLength, metric.length);
        final segment = metric.extractPath(start, end);
        canvas.drawPath(segment, dashPaint);
        distance += dashLength + gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LassoPainter oldDelegate) =>
      screenPoints.length != oldDelegate.screenPoints.length ||
      isClosed != oldDelegate.isClosed ||
      dashPhase != oldDelegate.dashPhase ||
      selectedBoundsScreen.length != oldDelegate.selectedBoundsScreen.length;
}
