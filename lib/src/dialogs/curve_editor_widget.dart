import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/models/tone_curve.dart';

/// Interactive curve editor widget for tone curve adjustment.
///
/// Displays a square grid with a cubic spline curve.
/// Users can tap to add control points and drag them to adjust.
/// Double-tap a point to remove it.
class CurveEditorWidget extends StatefulWidget {
  final ToneCurve curve;
  final ValueChanged<ToneCurve> onChanged;
  final double size;
  final Color? curveColor;

  const CurveEditorWidget({
    super.key,
    required this.curve,
    required this.onChanged,
    this.size = 200,
    this.curveColor,
  });

  @override
  State<CurveEditorWidget> createState() => _CurveEditorWidgetState();
}

class _CurveEditorWidgetState extends State<CurveEditorWidget> {
  int? _draggingIndex;

  List<CurvePoint> get _allPoints {
    final pts = <CurvePoint>[
      const CurvePoint(0, 0),
      ...widget.curve.points,
      const CurvePoint(1, 1),
    ];
    pts.sort((a, b) => a.x.compareTo(b.x));
    return pts;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: _onPanStart,
      onPanUpdate: _onPanUpdate,
      onPanEnd: (_) => setState(() => _draggingIndex = null),
      onDoubleTapDown: _onDoubleTap,
      child: CustomPaint(
        size: Size(widget.size, widget.size),
        painter: _CurvePainter(
          points: _allPoints,
          curve: widget.curve,
          primaryColor: widget.curveColor ?? cs.primary,
          gridColor: cs.outlineVariant.withValues(alpha: 0.3),
          lineColor: widget.curveColor ?? cs.primary,
          pointColor: cs.onPrimary,
        ),
      ),
    );
  }

  Offset _toNormalized(Offset local) {
    return Offset(
      (local.dx / widget.size).clamp(0.0, 1.0),
      1.0 - (local.dy / widget.size).clamp(0.0, 1.0), // flip Y
    );
  }

  void _onPanStart(DragStartDetails d) {
    final pos = _toNormalized(d.localPosition);
    final pts = widget.curve.points;

    // Find closest existing point
    double minDist = double.infinity;
    int? closest;
    for (int i = 0; i < pts.length; i++) {
      final dx = pts[i].x - pos.dx;
      final dy = pts[i].y - pos.dy;
      final dist = math.sqrt(dx * dx + dy * dy);
      if (dist < minDist) {
        minDist = dist;
        closest = i;
      }
    }

    // Threshold: if close enough, drag existing point
    if (closest != null && minDist < 0.08) {
      setState(() => _draggingIndex = closest);
    } else {
      // Add new point
      final newPts =
          List<CurvePoint>.from(pts)
            ..add(CurvePoint(pos.dx, pos.dy))
            ..sort((a, b) => a.x.compareTo(b.x));
      widget.onChanged(widget.curve.copyWith(points: newPts));
      setState(() {
        _draggingIndex = newPts.indexWhere((p) => p.x == pos.dx && p.y == pos.dy);
      });
    }
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_draggingIndex == null) return;
    final pos = _toNormalized(d.localPosition);
    final pts = List<CurvePoint>.from(widget.curve.points);
    if (_draggingIndex! >= 0 && _draggingIndex! < pts.length) {
      pts[_draggingIndex!] = CurvePoint(
        pos.dx.clamp(0.01, 0.99),
        pos.dy.clamp(0.0, 1.0),
      );
      pts.sort((a, b) => a.x.compareTo(b.x));
      // Re-find dragging index after sort
      setState(() {
        _draggingIndex = pts.indexWhere(
          (p) => (p.x - pos.dx.clamp(0.01, 0.99)).abs() < 0.001,
        );
      });
      widget.onChanged(widget.curve.copyWith(points: pts));
    }
  }

  void _onDoubleTap(TapDownDetails d) {
    final pos = _toNormalized(d.localPosition);
    final pts = List<CurvePoint>.from(widget.curve.points);

    // Find closest point and remove it
    double minDist = double.infinity;
    int? closest;
    for (int i = 0; i < pts.length; i++) {
      final dx = pts[i].x - pos.dx;
      final dy = pts[i].y - pos.dy;
      final dist = math.sqrt(dx * dx + dy * dy);
      if (dist < minDist) {
        minDist = dist;
        closest = i;
      }
    }

    if (closest != null && minDist < 0.08) {
      pts.removeAt(closest);
      widget.onChanged(widget.curve.copyWith(points: pts));
    }
  }
}

class _CurvePainter extends CustomPainter {
  final List<CurvePoint> points;
  final ToneCurve curve;
  final Color primaryColor;
  final Color gridColor;
  final Color lineColor;
  final Color pointColor;

  _CurvePainter({
    required this.points,
    required this.curve,
    required this.primaryColor,
    required this.gridColor,
    required this.lineColor,
    required this.pointColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Background
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, h),
        const Radius.circular(8),
      ),
      Paint()..color = const Color(0xFF1A1A2E),
    );

    // Grid lines
    final gridPaint =
        Paint()
          ..color = gridColor
          ..strokeWidth = 0.5;
    for (int i = 1; i < 4; i++) {
      final pos = i * w / 4;
      canvas.drawLine(Offset(pos, 0), Offset(pos, h), gridPaint);
      canvas.drawLine(Offset(0, pos), Offset(w, pos), gridPaint);
    }

    // Diagonal reference (identity)
    canvas.drawLine(
      Offset(0, h),
      Offset(w, 0),
      Paint()
        ..color = gridColor
        ..strokeWidth = 1,
    );

    // Draw curve path
    final curvePaint =
        Paint()
          ..color = lineColor
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;

    final path = Path();
    const steps = 100;
    for (int i = 0; i <= steps; i++) {
      final x = i / steps;
      final y = curve.isIdentity ? x : curve.evaluate(x);
      final px = x * w;
      final py = (1 - y) * h;
      if (i == 0) {
        path.moveTo(px, py);
      } else {
        path.lineTo(px, py);
      }
    }
    canvas.drawPath(path, curvePaint);

    // Draw control points
    for (final pt in points) {
      final px = pt.x * w;
      final py = (1 - pt.y) * h;

      // Outer ring
      canvas.drawCircle(
        Offset(px, py),
        7,
        Paint()
          ..color = primaryColor
          ..style = PaintingStyle.fill,
      );
      // Inner dot
      canvas.drawCircle(
        Offset(px, py),
        4,
        Paint()
          ..color = pointColor
          ..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(_CurvePainter old) => true;
}
