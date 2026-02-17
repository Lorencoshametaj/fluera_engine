import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../drawing/models/pressure_curve.dart';

/// 🎛️ Phase 4A: Interactive Pressure Curve Editor
///
/// Displays a cubic Bézier curve in a square canvas with draggable
/// control points. The user can shape how stylus pressure maps to
/// brush output (width/opacity).
///
/// Features:
/// - Interactive control point handles (P1, P2)
/// - Live curve preview with grid
/// - Preset buttons (Linear, Soft, Firm, S-Curve, Heavy)
/// - Stroke preview strip showing width variation
class PressureCurveEditor extends StatefulWidget {
  final PressureCurve curve;
  final ValueChanged<PressureCurve> onChanged;

  const PressureCurveEditor({
    super.key,
    required this.curve,
    required this.onChanged,
  });

  /// Show as a modal bottom sheet
  static Future<PressureCurve?> show(
    BuildContext context, {
    required PressureCurve initialCurve,
  }) {
    PressureCurve resultCurve = initialCurve;
    return showModalBottomSheet<PressureCurve>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (ctx) => _PressureCurveSheet(
            initialCurve: initialCurve,
            onChanged: (c) => resultCurve = c,
          ),
    ).then((_) => resultCurve);
  }

  @override
  State<PressureCurveEditor> createState() => _PressureCurveEditorState();
}

class _PressureCurveEditorState extends State<PressureCurveEditor> {
  late Offset _p1;
  late Offset _p2;
  int? _draggingPoint; // 1 or 2, null if not dragging

  @override
  void initState() {
    super.initState();
    _p1 = widget.curve.p1;
    _p2 = widget.curve.p2;
  }

  @override
  void didUpdateWidget(PressureCurveEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.curve != widget.curve) {
      _p1 = widget.curve.p1;
      _p2 = widget.curve.p2;
    }
  }

  void _emitCurve() {
    widget.onChanged(PressureCurve(p1: _p1, p2: _p2));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.maxWidth.clamp(0.0, constraints.maxHeight);
        return SizedBox(
          width: size,
          height: size,
          child: GestureDetector(
            onPanStart: (d) => _onPanStart(d, size),
            onPanUpdate: (d) => _onPanUpdate(d, size),
            onPanEnd: (_) => _onPanEnd(),
            child: CustomPaint(
              painter: _CurvePainter(
                p1: _p1,
                p2: _p2,
                isDark: Theme.of(context).brightness == Brightness.dark,
              ),
              size: Size(size, size),
            ),
          ),
        );
      },
    );
  }

  void _onPanStart(DragStartDetails details, double size) {
    final local = details.localPosition;
    final p1Screen = Offset(_p1.dx * size, (1.0 - _p1.dy) * size);
    final p2Screen = Offset(_p2.dx * size, (1.0 - _p2.dy) * size);

    const hitRadius = 28.0;
    final d1 = (local - p1Screen).distance;
    final d2 = (local - p2Screen).distance;

    if (d1 < hitRadius && d1 <= d2) {
      _draggingPoint = 1;
    } else if (d2 < hitRadius) {
      _draggingPoint = 2;
    }
  }

  void _onPanUpdate(DragUpdateDetails details, double size) {
    if (_draggingPoint == null || size <= 0) return;

    final local = details.localPosition;
    final normalized = Offset(
      (local.dx / size).clamp(0.0, 1.0),
      (1.0 - local.dy / size).clamp(0.0, 1.0),
    );

    setState(() {
      if (_draggingPoint == 1) {
        _p1 = normalized;
      } else {
        _p2 = normalized;
      }
    });
    _emitCurve();
    HapticFeedback.selectionClick();
  }

  void _onPanEnd() {
    _draggingPoint = null;
  }
}

/// CustomPainter for the Bézier curve display
class _CurvePainter extends CustomPainter {
  final Offset p1;
  final Offset p2;
  final bool isDark;

  _CurvePainter({required this.p1, required this.p2, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Background
    final bgPaint =
        Paint()
          ..color = isDark ? const Color(0xFF1A1A2E) : const Color(0xFFF8F9FA);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12)),
      bgPaint,
    );

    // Grid lines
    final gridPaint =
        Paint()
          ..color = isDark ? Colors.white10 : Colors.black12
          ..strokeWidth = 0.5;

    for (int i = 1; i < 4; i++) {
      final frac = i / 4.0;
      canvas.drawLine(Offset(frac * w, 0), Offset(frac * w, h), gridPaint);
      canvas.drawLine(Offset(0, frac * h), Offset(w, frac * h), gridPaint);
    }

    // Diagonal reference line (linear)
    final diagPaint =
        Paint()
          ..color = isDark ? Colors.white24 : Colors.black26
          ..strokeWidth = 1.0
          ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(0, h), Offset(w, 0), diagPaint);

    // Control point guide lines
    final guidePaint =
        Paint()
          ..color =
              isDark
                  ? Colors.teal.withValues(alpha: 0.4)
                  : Colors.teal.withValues(alpha: 0.3)
          ..strokeWidth = 1.0
          ..style = PaintingStyle.stroke;

    final p0Screen = Offset(0, h);
    final p1Screen = Offset(p1.dx * w, (1.0 - p1.dy) * h);
    final p2Screen = Offset(p2.dx * w, (1.0 - p2.dy) * h);
    final p3Screen = Offset(w, 0);

    // Dashed guide lines from endpoints to control points
    _drawDashed(canvas, p0Screen, p1Screen, guidePaint);
    _drawDashed(canvas, p3Screen, p2Screen, guidePaint);

    // The Bézier curve itself
    final curvePath = Path();
    curvePath.moveTo(0, h); // p0 = (0, 0) → screen (0, h)

    curvePath.cubicTo(
      p1Screen.dx,
      p1Screen.dy,
      p2Screen.dx,
      p2Screen.dy,
      w,
      0, // p3 = (1, 1) → screen (w, 0)
    );

    final curvePaint =
        Paint()
          ..color = isDark ? Colors.tealAccent : Colors.teal
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;
    canvas.drawPath(curvePath, curvePaint);

    // Control point handles
    _drawHandle(
      canvas,
      p1Screen,
      isDark ? Colors.orangeAccent : Colors.deepOrange,
    );
    _drawHandle(
      canvas,
      p2Screen,
      isDark ? Colors.lightBlueAccent : Colors.blue,
    );

    // Axis labels
    _drawLabel(canvas, 'Input', Offset(w / 2, h - 4), isDark, size);
    _drawLabel(
      canvas,
      'Output',
      Offset(4, h / 2),
      isDark,
      size,
      vertical: true,
    );
  }

  void _drawHandle(Canvas canvas, Offset pos, Color color) {
    // Outer ring
    canvas.drawCircle(
      pos,
      10,
      Paint()
        ..color = color.withValues(alpha: 0.3)
        ..style = PaintingStyle.fill,
    );
    // Inner dot
    canvas.drawCircle(
      pos,
      6,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
    // Border
    canvas.drawCircle(
      pos,
      6,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  void _drawDashed(Canvas canvas, Offset from, Offset to, Paint paint) {
    const dashLength = 4.0;
    const gapLength = 3.0;
    final direction = to - from;
    final distance = direction.distance;
    if (distance < 1) return;
    final unit = direction / distance;

    double drawn = 0;
    bool drawing = true;
    while (drawn < distance) {
      final segLen = drawing ? dashLength : gapLength;
      final end = (drawn + segLen).clamp(0.0, distance);
      if (drawing) {
        canvas.drawLine(from + unit * drawn, from + unit * end, paint);
      }
      drawn = end;
      drawing = !drawing;
    }
  }

  void _drawLabel(
    Canvas canvas,
    String text,
    Offset pos,
    bool isDark,
    Size size, {
    bool vertical = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: isDark ? Colors.white38 : Colors.black38,
          fontSize: 10,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    if (vertical) {
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(-1.5708); // -90°
      tp.paint(canvas, Offset(-tp.width / 2, 0));
      canvas.restore();
    } else {
      tp.paint(canvas, Offset(pos.dx - tp.width / 2, pos.dy - tp.height));
    }
  }

  @override
  bool shouldRepaint(_CurvePainter old) =>
      old.p1 != p1 || old.p2 != p2 || old.isDark != isDark;
}

/// Bottom sheet wrapper for the curve editor
class _PressureCurveSheet extends StatefulWidget {
  final PressureCurve initialCurve;
  final ValueChanged<PressureCurve> onChanged;

  const _PressureCurveSheet({
    required this.initialCurve,
    required this.onChanged,
  });

  @override
  State<_PressureCurveSheet> createState() => _PressureCurveSheetState();
}

class _PressureCurveSheetState extends State<_PressureCurveSheet> {
  late PressureCurve _curve;

  @override
  void initState() {
    super.initState();
    _curve = widget.initialCurve;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeName = _curve.presetName;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF16213E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.black12,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Title
          Text(
            'Pressure Curve',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Drag the control points to shape pressure response',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white38 : Colors.black45,
            ),
          ),
          const SizedBox(height: 20),

          // Curve editor
          SizedBox(
            height: 220,
            child: PressureCurveEditor(
              curve: _curve,
              onChanged: (c) {
                setState(() => _curve = c);
                widget.onChanged(c);
              },
            ),
          ),
          const SizedBox(height: 16),

          // Stroke preview
          _StrokePreview(curve: _curve, isDark: isDark),
          const SizedBox(height: 16),

          // Preset buttons
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children:
                  PressureCurve.presets.entries.map((entry) {
                    final isActive = activeName == entry.key;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _PresetChip(
                        label: _presetLabel(entry.key),
                        isActive: isActive,
                        isDark: isDark,
                        onTap: () {
                          HapticFeedback.lightImpact();
                          setState(() => _curve = entry.value);
                          widget.onChanged(entry.value);
                        },
                      ),
                    );
                  }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  String _presetLabel(String key) {
    switch (key) {
      case 'linear':
        return 'Linear';
      case 'soft':
        return 'Soft';
      case 'firm':
        return 'Firm';
      case 'sCurve':
        return 'S-Curve';
      case 'heavy':
        return 'Heavy';
      default:
        return key;
    }
  }
}

/// Preset selection chip
class _PresetChip extends StatelessWidget {
  final String label;
  final bool isActive;
  final bool isDark;
  final VoidCallback onTap;

  const _PresetChip({
    required this.label,
    required this.isActive,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color:
                isActive
                    ? (isDark ? Colors.teal[800] : Colors.teal[50])
                    : (isDark ? Colors.white10 : Colors.grey[100]),
            borderRadius: BorderRadius.circular(20),
            border:
                isActive
                    ? Border.all(
                      color: isDark ? Colors.tealAccent : Colors.teal,
                      width: 1.5,
                    )
                    : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              color:
                  isActive
                      ? (isDark ? Colors.tealAccent : Colors.teal[700])
                      : (isDark ? Colors.white70 : Colors.black54),
            ),
          ),
        ),
      ),
    );
  }
}

/// Live stroke preview showing width variation based on current curve
class _StrokePreview extends StatelessWidget {
  final PressureCurve curve;
  final bool isDark;

  const _StrokePreview({required this.curve, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
      ),
      child: CustomPaint(
        painter: _StrokePreviewPainter(curve: curve, isDark: isDark),
        size: const Size(double.infinity, 40),
      ),
    );
  }
}

/// Paints a simulated variable-width stroke to preview the pressure curve
class _StrokePreviewPainter extends CustomPainter {
  final PressureCurve curve;
  final bool isDark;

  _StrokePreviewPainter({required this.curve, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    const padding = 16.0;
    const maxWidth = 8.0;
    const minWidth = 1.0;

    final paint =
        Paint()
          ..color =
              isDark ? Colors.tealAccent.withValues(alpha: 0.8) : Colors.teal
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;

    final steps = 60;
    for (int i = 0; i < steps; i++) {
      final t = i / steps;
      final nextT = (i + 1) / steps;

      // Simulate pressure: ramp up then down
      final rawPressure = _trianglePressure(t);
      final mappedPressure = curve.evaluate(rawPressure);

      final strokeWidth = minWidth + (maxWidth - minWidth) * mappedPressure;
      paint.strokeWidth = strokeWidth;

      final x1 = padding + t * (w - 2 * padding);
      final x2 = padding + nextT * (w - 2 * padding);
      final y = h / 2;

      canvas.drawLine(Offset(x1, y), Offset(x2, y), paint);
    }
  }

  /// Simulates a triangular pressure profile (ramp up, hold, ramp down)
  double _trianglePressure(double t) {
    if (t < 0.3) return t / 0.3;
    if (t < 0.7) return 1.0;
    return (1.0 - t) / 0.3;
  }

  @override
  bool shouldRepaint(_StrokePreviewPainter old) =>
      old.curve != curve || old.isDark != isDark;
}
