import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/pro_brush_settings.dart';
import '../../rendering/optimization/optimization.dart';

/// 📏 Technical Pen — Professional-grade constant-width brush
///
/// Designed to match professional apps (Procreate, GoodNotes, Clip Studio):
/// - **Zero pressure variation** — width is perfectly constant
/// - **No entry/exit taper** — full width from first to last pixel
/// - **Butt cap** — squared line endings (technical drawing look)
/// - **Miter join** — sharp corners at direction changes
/// - **Angle snapping** — optional snap to 15°/30°/45°/90° increments
/// - **Endpoint snapping** — auto-close shapes when end is near start
/// - **Corner sharpening** — sharp corners at direction changes
/// - **Anti-alias optimization** — crisp, pixel-perfect edges
class TechnicalPenBrush {
  static const String name = 'Technical Pen';
  static const IconData icon = Icons.straighten;
  static const double opacity = 1.0;
  static const StrokeCap strokeCap = StrokeCap.butt;
  static const StrokeJoin strokeJoin = StrokeJoin.miter;

  /// Draw a technical pen stroke — constant width, no taper, sharp ends.
  static void drawStroke(
    Canvas canvas,
    List<dynamic> points,
    Color color,
    double baseWidth, {
    bool isLive = false,
    Path? cachedPath,
    ProBrushSettings settings = ProBrushSettings.defaultSettings,
  }) {
    if (points.isEmpty) return;

    if (points.length == 1) {
      // 🟧 Dot override: filled square (butt-cap style, not round)
      final offset = StrokeOptimizer.getOffset(points.first);
      final half = baseWidth * 0.5;
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.fill
        ..isAntiAlias = true
        ..filterQuality = FilterQuality.high;
      canvas.drawRect(
        Rect.fromCenter(center: offset, width: half * 2, height: half * 2),
        paint,
      );
      return;
    }

    // 🎯 Anti-alias optimized paint — crisp edges
    final paint = PaintPool.getStrokePaint(
      color: color,
      strokeWidth: baseWidth,
      strokeCap: strokeCap,
      strokeJoin: strokeJoin,
    );

    // If we have a cached path or no settings features, use fast path
    if (cachedPath != null) {
      canvas.drawPath(cachedPath, paint);
      return;
    }

    // Process points with optional angle snapping and corner sharpening
    final path = _buildTechnicalPath(
      points,
      baseWidth,
      settings: settings,
      isLive: isLive,
    );
    canvas.drawPath(path, paint);
  }

  /// Build a path with angle snapping, corner sharpening, and endpoint snapping.
  static Path _buildTechnicalPath(
    List<dynamic> points,
    double baseWidth, {
    required ProBrushSettings settings,
    required bool isLive,
  }) {
    final offsets = <Offset>[];
    for (final p in points) {
      offsets.add(StrokeOptimizer.getOffset(p));
    }

    // 🧲 Angle snapping: when enabled, quantize directions.
    // ⚡ SKIP for live strokes — the input state machine already handles
    // angle snapping. Re-snapping during rendering would corrupt the
    // already-projected positions. Only apply to saved/historical strokes.
    List<Offset> processed;
    if (settings.techAngleSnap && offsets.length >= 2 && !isLive) {
      processed = _applyAngleSnapping(offsets, settings.techSnapAngleDeg);
    } else {
      processed = offsets;
    }

    if (processed.length < 2) {
      return Path()..moveTo(processed.first.dx, processed.first.dy);
    }

    // 🔷 Corner sharpening: detect sharp direction changes and use lineTo
    final path = Path();
    path.moveTo(processed.first.dx, processed.first.dy);

    final cornerThreshold = _cornerThresholdFromSharpening(
      settings.techCornerSharpening,
    );

    for (int i = 1; i < processed.length; i++) {
      if (i < processed.length - 1) {
        // Check if this is a sharp corner
        final angle = _angleAtPoint(processed[i - 1], processed[i], processed[i + 1]);
        if (angle < cornerThreshold) {
          // Sharp corner: use lineTo for a crisp vertex
          path.lineTo(processed[i].dx, processed[i].dy);
          continue;
        }
      }

      // Smooth segment: use Catmull-Rom for the curve
      if (i > 1 && i < processed.length - 1) {
        // Catmull-Rom with control points
        final p0 = processed[i - 2];
        final p1 = processed[i - 1];
        final p2 = processed[i];
        final p3 = i + 1 < processed.length ? processed[i + 1] : p2;

        // Control points from Catmull-Rom
        final cp1x = p1.dx + (p2.dx - p0.dx) / 6.0;
        final cp1y = p1.dy + (p2.dy - p0.dy) / 6.0;
        final cp2x = p2.dx - (p3.dx - p1.dx) / 6.0;
        final cp2y = p2.dy - (p3.dy - p1.dy) / 6.0;

        path.cubicTo(cp1x, cp1y, cp2x, cp2y, p2.dx, p2.dy);
      } else {
        path.lineTo(processed[i].dx, processed[i].dy);
      }
    }

    // 🔗 Endpoint snapping: close path if end is near start
    if (settings.techEndpointSnap &&
        !isLive &&
        processed.length >= 3) {
      final start = processed.first;
      final end = processed.last;
      final dist = (end - start).distance;
      final snapThreshold = baseWidth * 3.0;
      if (dist < snapThreshold && dist > 0.1) {
        path.close();
      }
    }

    return path;
  }

  /// Apply angle snapping: quantize movement direction to nearest angle step.
  ///
  /// Only snaps segments that are relatively straight (low velocity deviation).
  /// This preserves curves while snapping deliberate straight lines.
  static List<Offset> _applyAngleSnapping(
    List<Offset> points,
    double snapAngleDeg,
  ) {
    if (points.length < 2) return points;

    final snapRad = snapAngleDeg * math.pi / 180.0;
    final result = <Offset>[points.first];
    var anchor = points.first;

    for (int i = 1; i < points.length; i++) {
      final current = points[i];
      final delta = current - anchor;
      final dist = delta.distance;

      if (dist < 2.0) continue; // Skip tiny movements

      // Calculate angle and snap to nearest increment
      final rawAngle = math.atan2(delta.dy, delta.dx);
      final snapped = (rawAngle / snapRad).round() * snapRad;

      // Only snap if direction is relatively stable (within 15° of snap)
      final deviation = (rawAngle - snapped).abs();
      if (deviation < 0.26) {
        // ~15° tolerance
        // Snap: project distance onto snapped angle
        final snappedPoint = Offset(
          anchor.dx + dist * math.cos(snapped),
          anchor.dy + dist * math.sin(snapped),
        );
        result.add(snappedPoint);
        anchor = snappedPoint;
      } else {
        // Don't snap — freehand curve
        result.add(current);
        anchor = current;
      }
    }

    return result;
  }

  /// Calculate the angle (in radians) at point b, between segments a→b and b→c.
  /// Returns 0 for a perfect U-turn, π for a straight line.
  static double _angleAtPoint(Offset a, Offset b, Offset c) {
    final ab = b - a;
    final bc = c - b;
    final dot = ab.dx * bc.dx + ab.dy * bc.dy;
    final cross = ab.dx * bc.dy - ab.dy * bc.dx;
    return math.atan2(cross.abs(), dot);
  }

  /// Convert sharpening slider (0-1) to corner angle threshold (radians).
  /// 0.0 = no sharpening (threshold = 0, nothing detected)
  /// 0.5 = moderate (60° = ~1.05 rad)
  /// 1.0 = aggressive (120° = ~2.09 rad — even gentle curves get sharpened)
  static double _cornerThresholdFromSharpening(double sharpening) {
    // Map 0-1 → 0.3-2.2 radians (~17° to ~126°)
    return 0.3 + sharpening * 1.9;
  }
}
