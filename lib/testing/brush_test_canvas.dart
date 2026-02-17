import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import './brush_test_screen.dart';
import './brush_test_painter.dart';

/// 🎨 Optimized Canvas for Brush Testing
///
/// Features:
/// - Stylus detection with REAL pressure, tilt and orientation
/// - Optimized rendering with caching
/// - Performance monitoring real-time
/// - 🚀 RepaintBoundary for rendering isolation
class BrushTestCanvas extends StatefulWidget {
  final List<BrushStroke> strokes;
  final BrushStroke? currentStroke;
  final int repaintKey;
  final Function(Offset position, double pressure, double tiltX, double tiltY)
  onPanStart;
  final Function(Offset position, double pressure, double tiltX, double tiltY)
  onPanUpdate;
  final Function() onPanEnd;

  const BrushTestCanvas({
    super.key,
    required this.strokes,
    required this.currentStroke,
    this.repaintKey = 0,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
  });

  @override
  State<BrushTestCanvas> createState() => _BrushTestCanvasState();
}

class _BrushTestCanvasState extends State<BrushTestCanvas> {
  bool _isDrawing = false;
  Offset? _lastPosition; // 🎯 Per calcolo velocità

  /// 🎯 REALISM: Simula pressione realistica per dito dalla velocità
  double _normalizePressure(PointerEvent event) {
    final rawPressure = event.pressure;

    // Stylus: uses real pressure
    if (event.kind == PointerDeviceKind.stylus) {
      return rawPressure.clamp(0.1, 1.0);
    }

    // Finger: simula pressione dalla velocità
    if (_lastPosition != null) {
      final distance = (event.localPosition - _lastPosition!).distance;

      // Lento = più pressione, veloce = meno pressione
      const double maxDistance = 30.0;
      const double minPressure = 0.3;
      const double maxPressure = 0.9;

      final normalizedDistance = (distance / maxDistance).clamp(0.0, 1.0);
      return maxPressure - (normalizedDistance * (maxPressure - minPressure));
    }

    return 0.6; // Primo punto
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dpr = MediaQuery.devicePixelRatioOf(context);

    return Container(
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      child: Listener(
        onPointerDown: (PointerDownEvent event) {
          _isDrawing = true;
          _lastPosition = event.localPosition; // Track position
          final pressure = _normalizePressure(event);
          // 🖊️ FIX: Calculate tiltX and tiltY from tilt (angle) and orientation (direction)
          // tilt: 0 = perpendicolare, π/2 = piatta sul display (radians)
          // orientation: direzione dell'inclinazione in radians
          final tiltMagnitude = event.tilt; // 0 to π/2
          final orientation = event.orientation; // -π to π
          // Proietta il tilt sugli assi X e Y
          final tiltX = (tiltMagnitude * math.cos(orientation)).clamp(
            -1.0,
            1.0,
          );
          final tiltY = (tiltMagnitude * math.sin(orientation)).clamp(
            -1.0,
            1.0,
          );

          widget.onPanStart(event.localPosition, pressure, tiltX, tiltY);
        },
        onPointerMove: (PointerMoveEvent event) {
          if (_isDrawing) {
            final pressure = _normalizePressure(event);
            _lastPosition =
                event.localPosition; // Update position for next calculation
            // 🖊️ FIX: Calculate real tiltX and tiltY
            final tiltMagnitude = event.tilt;
            final orientation = event.orientation;
            final tiltX = (tiltMagnitude * math.cos(orientation)).clamp(
              -1.0,
              1.0,
            );
            final tiltY = (tiltMagnitude * math.sin(orientation)).clamp(
              -1.0,
              1.0,
            );
            widget.onPanUpdate(event.localPosition, pressure, tiltX, tiltY);
          }
        },
        onPointerUp: (PointerUpEvent event) {
          _isDrawing = false;
          _lastPosition = null; // Reset per prossimo stroke
          widget.onPanEnd();
        },
        onPointerCancel: (PointerCancelEvent event) {
          _isDrawing = false;
          _lastPosition = null;
          widget.onPanEnd();
        },
        // 🚀 RepaintBoundary isolates canvas from rest of widget tree
        // Previene repaint inutili quando altri widget cambiano
        child: RepaintBoundary(
          child: CustomPaint(
            painter: BrushTestPainter(
              strokes: widget.strokes,
              currentStroke: widget.currentStroke,
              devicePixelRatio: dpr,
              isDark: isDark,
              repaintKey: widget.repaintKey,
            ),
            size: Size.infinite,
            // 🚀 isComplex=true suggests Flutter to cache the layer
            isComplex: true,
            // 🚀 willChange=true if we're actively drawing
            willChange: widget.currentStroke != null,
          ),
        ),
      ),
    );
  }
}
