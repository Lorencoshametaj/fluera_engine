// lib/screens/professional_canvas/widgets/live_stroke_overlay.dart

import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// 🎨 Overlay that renders remote users' in-progress strokes
///
/// Uses a ValueNotifier of Map (String to Map) where each entry
/// is a userId → strokeData map from RTDB live_strokes.
///
/// Renders strokes as semi-transparent paths so the local user can see
/// what collaborators are drawing in real-time.
class LiveStrokeOverlay extends StatelessWidget {
  /// Live strokes from all remote users (userId → strokeData)
  final ValueNotifier<Map<String, Map<String, dynamic>>> liveStrokes;

  /// Canvas transform for correct positioning
  final Offset canvasOffset;
  final double canvasScale;

  const LiveStrokeOverlay({
    super.key,
    required this.liveStrokes,
    required this.canvasOffset,
    required this.canvasScale,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, Map<String, dynamic>>>(
      valueListenable: liveStrokes,
      builder: (context, strokes, _) {
        if (strokes.isEmpty) return const SizedBox.shrink();

        return Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _LiveStrokePainter(
                liveStrokes: strokes,
                canvasOffset: canvasOffset,
                canvasScale: canvasScale,
              ),
              size: Size.infinite,
            ),
          ),
        );
      },
    );
  }
}

/// 🎨 CustomPainter that renders live strokes from remote users
class _LiveStrokePainter extends CustomPainter {
  final Map<String, Map<String, dynamic>> liveStrokes;
  final Offset canvasOffset;
  final double canvasScale;

  _LiveStrokePainter({
    required this.liveStrokes,
    required this.canvasOffset,
    required this.canvasScale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final entry in liveStrokes.entries) {
      _drawRemoteStroke(canvas, entry.value);
    }
  }

  void _drawRemoteStroke(Canvas canvas, Map<String, dynamic> strokeData) {
    final pointsRaw = strokeData['points'] as List?;
    if (pointsRaw == null || pointsRaw.length < 2) return;

    // Parse stroke properties
    final colorValue = strokeData['color'] as int? ?? 0xFF42A5F5;
    final width = (strokeData['width'] as num?)?.toDouble() ?? 2.0;

    // Create paint — semi-transparent for "preview" feel
    final paint =
        Paint()
          ..color = Color(colorValue).withValues(alpha: 0.5)
          ..strokeWidth = width * canvasScale
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke
          ..isAntiAlias = true;

    // Build path from points
    final path = ui.Path();
    bool first = true;

    for (final point in pointsRaw) {
      if (point is! Map) continue;
      final x = (point['x'] as num?)?.toDouble() ?? 0;
      final y = (point['y'] as num?)?.toDouble() ?? 0;

      // Transform canvas coordinates to screen coordinates
      final screenX = x * canvasScale + canvasOffset.dx;
      final screenY = y * canvasScale + canvasOffset.dy;

      if (first) {
        path.moveTo(screenX, screenY);
        first = false;
      } else {
        path.lineTo(screenX, screenY);
      }
    }

    canvas.drawPath(path, paint);

    // Draw a small colored dot at the last point (pen tip indicator)
    if (pointsRaw.isNotEmpty) {
      final lastPoint = pointsRaw.last;
      if (lastPoint is Map) {
        final lx = (lastPoint['x'] as num?)?.toDouble() ?? 0;
        final ly = (lastPoint['y'] as num?)?.toDouble() ?? 0;
        final sx = lx * canvasScale + canvasOffset.dx;
        final sy = ly * canvasScale + canvasOffset.dy;

        final dotPaint =
            Paint()
              ..color = Color(colorValue)
              ..style = PaintingStyle.fill;

        canvas.drawCircle(Offset(sx, sy), (width * canvasScale) + 2, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(_LiveStrokePainter oldDelegate) {
    return liveStrokes != oldDelegate.liveStrokes ||
        canvasOffset != oldDelegate.canvasOffset ||
        canvasScale != oldDelegate.canvasScale;
  }
}
