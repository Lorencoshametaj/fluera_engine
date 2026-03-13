import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// 🖊️ HOVER TOOL MODE — what the cursor should preview
enum HoverToolMode {
  brush,    // Pen/pencil/marker — circular cursor with color
  eraser,   // Eraser — dashed circle
  selection, // Lasso/selection — crosshair
  pan,      // Pan mode — open hand
  text,     // Text mode — I-beam with word highlight
}

/// 🖊️ STYLUS HOVER STATE
///
/// Lightweight ChangeNotifier tracking stylus hover position and tool context.
/// Fed by InfiniteCanvasGestureDetector._onPointerHover.
/// Consumed by StylusHoverOverlay for rendering.
class StylusHoverState extends ChangeNotifier {
  // ========================================================================
  // SINGLETON
  // ========================================================================

  static final StylusHoverState instance = StylusHoverState._();
  StylusHoverState._();

  // ========================================================================
  // STATE
  // ========================================================================

  bool _isHovering = false;
  Offset _position = Offset.zero;
  double _distance = 1.0; // 0.0 = touching, 1.0 = max hover distance

  // Tool context (set by canvas screen when tool changes)
  HoverToolMode _toolMode = HoverToolMode.brush;
  double _brushSize = 3.0;   // Current brush stroke width
  Color _brushColor = Colors.black;
  double _brushOpacity = 1.0;
  double _eraserSize = 20.0;

  // Velocity for ink prediction
  Offset _velocity = Offset.zero;
  Offset? _previousPosition;
  int _previousTimestamp = 0;

  // Snap guides (set by smart guides system)
  List<double> _snapGuidesX = [];
  List<double> _snapGuidesY = [];

  // Text hover highlight
  Rect? _hoveredWordRect;

  // ========================================================================
  // GETTERS
  // ========================================================================

  bool get isHovering => _isHovering;
  Offset get position => _position;
  double get distance => _distance;
  HoverToolMode get toolMode => _toolMode;
  double get brushSize => _brushSize;
  Color get brushColor => _brushColor;
  double get brushOpacity => _brushOpacity;
  double get eraserSize => _eraserSize;
  Offset get velocity => _velocity;
  List<double> get snapGuidesX => _snapGuidesX;
  List<double> get snapGuidesY => _snapGuidesY;
  Rect? get hoveredWordRect => _hoveredWordRect;

  // ========================================================================
  // UPDATES (from gesture detector)
  // ========================================================================

  /// Update hover position. Call on every PointerHoverEvent.
  void updateHover(Offset position, {double distance = 0.5}) {
    _isHovering = true;
    _position = position;
    _distance = distance.clamp(0.0, 1.0);

    // Calculate velocity for ink prediction
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_previousPosition != null && _previousTimestamp > 0) {
      final dt = (now - _previousTimestamp).clamp(1, 100);
      _velocity = Offset(
        (position.dx - _previousPosition!.dx) / dt,
        (position.dy - _previousPosition!.dy) / dt,
      );
    }
    _previousPosition = position;
    _previousTimestamp = now;

    notifyListeners();
  }

  /// Stylus left hover range.
  void endHover() {
    if (!_isHovering) return;
    _isHovering = false;
    _velocity = Offset.zero;
    _previousPosition = null;
    notifyListeners();
  }

  // ========================================================================
  // TOOL CONTEXT (from canvas screen)
  // ========================================================================

  void setToolMode(HoverToolMode mode) {
    if (_toolMode == mode) return;
    _toolMode = mode;
    if (_isHovering) notifyListeners();
  }

  void setBrushContext({
    required double size,
    required Color color,
    required double opacity,
  }) {
    _brushSize = size;
    _brushColor = color;
    _brushOpacity = opacity;
    if (_isHovering) notifyListeners();
  }

  void setEraserSize(double size) {
    _eraserSize = size;
    if (_isHovering) notifyListeners();
  }

  // ========================================================================
  // SNAP GUIDES (from smart guides system)
  // ========================================================================

  void setSnapGuides({List<double>? x, List<double>? y}) {
    _snapGuidesX = x ?? [];
    _snapGuidesY = y ?? [];
    if (_isHovering) notifyListeners();
  }

  void clearSnapGuides() {
    _snapGuidesX = [];
    _snapGuidesY = [];
  }

  // ========================================================================
  // TEXT HOVER (from text overlay)
  // ========================================================================

  void setHoveredWord(Rect? wordRect) {
    _hoveredWordRect = wordRect;
    if (_isHovering) notifyListeners();
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 🖊️ STYLUS HOVER OVERLAY — renders the cursor preview
// ══════════════════════════════════════════════════════════════════════════════

/// Overlay widget that renders stylus hover cursor preview.
///
/// Features:
/// 1. Brush preview cursor (size + color)
/// 2. Eraser preview (dashed circle)
/// 3. Selection crosshair
/// 4. Snap guide lines
/// 5. Hovered word highlight
/// 6. Distance-based size (closer = larger)
/// 7. Ink prediction trail
class StylusHoverOverlay extends StatelessWidget {
  const StylusHoverOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StylusHoverState.instance,
      builder: (context, _) {
        final state = StylusHoverState.instance;
        if (!state.isHovering) return const SizedBox.shrink();

        return Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _StylusHoverPainter(state),
            ),
          ),
        );
      },
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 🎨 HOVER CURSOR PAINTER
// ══════════════════════════════════════════════════════════════════════════════

class _StylusHoverPainter extends CustomPainter {
  final StylusHoverState state;

  _StylusHoverPainter(this.state);

  @override
  void paint(Canvas canvas, Size size) {
    final pos = state.position;

    // ── FEATURE 4: SNAP PREVIEW GUIDES ──
    _drawSnapGuides(canvas, size, pos);

    // ── FEATURE 5: TEXT HOVER HIGHLIGHT ──
    if (state.hoveredWordRect != null) {
      _drawWordHighlight(canvas, state.hoveredWordRect!);
    }

    // ── TOOL-SPECIFIC CURSOR ──
    switch (state.toolMode) {
      case HoverToolMode.brush:
        _drawBrushCursor(canvas, pos);
        break;
      case HoverToolMode.eraser:
        _drawEraserCursor(canvas, pos);
        break;
      case HoverToolMode.selection:
        _drawSelectionCursor(canvas, pos);
        break;
      case HoverToolMode.pan:
        _drawPanCursor(canvas, pos);
        break;
      case HoverToolMode.text:
        _drawTextCursor(canvas, pos);
        break;
    }

    // ── FEATURE 8: INK PREDICTION ──
    if (state.toolMode == HoverToolMode.brush &&
        state.velocity.distance > 0.3) {
      _drawInkPrediction(canvas, pos);
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // FEATURE 1+2+7: BRUSH CURSOR (size + color + distance)
  // ════════════════════════════════════════════════════════════════════════

  void _drawBrushCursor(Canvas canvas, Offset pos) {
    // Feature 7: Distance affects size — closer = full size, far = smaller
    final distanceFactor = 1.0 - (state.distance * 0.4); // 60%-100%
    final radius = (state.brushSize / 2) * distanceFactor;
    final effectiveRadius = radius.clamp(1.5, 200.0);

    // Feature 2: Color preview — filled circle with brush color + opacity
    final fillPaint = Paint()
      ..color = state.brushColor.withValues(alpha: state.brushOpacity * 0.3)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(pos, effectiveRadius, fillPaint);

    // Outline ring
    final outlinePaint = Paint()
      ..color = state.brushColor.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawCircle(pos, effectiveRadius, outlinePaint);

    // Center dot (precise tip position)
    canvas.drawCircle(
      pos,
      1.5,
      Paint()..color = state.brushColor.withValues(alpha: 0.8),
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  // FEATURE 3: ERASER CURSOR (dashed circle)
  // ════════════════════════════════════════════════════════════════════════

  void _drawEraserCursor(Canvas canvas, Offset pos) {
    final distanceFactor = 1.0 - (state.distance * 0.4);
    final radius = (state.eraserSize / 2) * distanceFactor;

    // Dashed circle effect using arcs
    final paint = Paint()
      ..color = Colors.red.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    const segments = 12;
    const gapAngle = math.pi / segments;
    for (int i = 0; i < segments; i++) {
      final startAngle = i * 2 * gapAngle;
      canvas.drawArc(
        Rect.fromCircle(center: pos, radius: radius),
        startAngle,
        gapAngle,
        false,
        paint,
      );
    }

    // X mark in center
    const crossSize = 4.0;
    final crossPaint = Paint()
      ..color = Colors.red.withValues(alpha: 0.6)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      pos + const Offset(-crossSize, -crossSize),
      pos + const Offset(crossSize, crossSize),
      crossPaint,
    );
    canvas.drawLine(
      pos + const Offset(crossSize, -crossSize),
      pos + const Offset(-crossSize, crossSize),
      crossPaint,
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  // FEATURE 3: SELECTION CURSOR (crosshair)
  // ════════════════════════════════════════════════════════════════════════

  void _drawSelectionCursor(Canvas canvas, Offset pos) {
    final paint = Paint()
      ..color = Colors.blue.withValues(alpha: 0.5)
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;

    const armLen = 10.0;
    const gap = 3.0;

    // Horizontal arms with gap
    canvas.drawLine(pos + const Offset(-armLen - gap, 0),
        pos + const Offset(-gap, 0), paint);
    canvas.drawLine(pos + const Offset(gap, 0),
        pos + const Offset(armLen + gap, 0), paint);
    // Vertical arms with gap
    canvas.drawLine(pos + const Offset(0, -armLen - gap),
        pos + const Offset(0, -gap), paint);
    canvas.drawLine(pos + const Offset(0, gap),
        pos + const Offset(0, armLen + gap), paint);
  }

  // ════════════════════════════════════════════════════════════════════════
  // PAN CURSOR (open hand icon approximation)
  // ════════════════════════════════════════════════════════════════════════

  void _drawPanCursor(Canvas canvas, Offset pos) {
    // Simple open-hand icon (circle with fingers)
    final paint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(pos, 8, paint);

    // 4 dots for finger tips
    final dotPaint = Paint()..color = Colors.grey.withValues(alpha: 0.5);
    for (int i = 0; i < 4; i++) {
      final angle = -math.pi / 4 + (i * math.pi / 6);
      canvas.drawCircle(
        pos + Offset(math.cos(angle) * 12, math.sin(angle) * -12),
        2,
        dotPaint,
      );
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // FEATURE 5: TEXT CURSOR (I-beam)
  // ════════════════════════════════════════════════════════════════════════

  void _drawTextCursor(Canvas canvas, Offset pos) {
    final paint = Paint()
      ..color = Colors.blue.withValues(alpha: 0.6)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    // I-beam shape
    const height = 18.0;
    const serifW = 4.0;

    // Vertical bar
    canvas.drawLine(
        pos + const Offset(0, -height / 2),
        pos + const Offset(0, height / 2),
        paint);
    // Top serif
    canvas.drawLine(
        pos + const Offset(-serifW, -height / 2),
        pos + const Offset(serifW, -height / 2),
        paint);
    // Bottom serif
    canvas.drawLine(
        pos + const Offset(-serifW, height / 2),
        pos + const Offset(serifW, height / 2),
        paint);
  }

  // ════════════════════════════════════════════════════════════════════════
  // FEATURE 4: SNAP PREVIEW GUIDES
  // ════════════════════════════════════════════════════════════════════════

  void _drawSnapGuides(Canvas canvas, Size size, Offset pos) {
    if (state.snapGuidesX.isEmpty && state.snapGuidesY.isEmpty) return;

    final paint = Paint()
      ..color = Colors.cyan.withValues(alpha: 0.3)
      ..strokeWidth = 0.5;

    // Vertical snap guides
    for (final x in state.snapGuidesX) {
      // Only show nearby guides (within 30px)
      if ((x - pos.dx).abs() < 30) {
        final guidePaint = Paint()
          ..color = Colors.cyan.withValues(alpha: 0.5)
          ..strokeWidth = 1.0;
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), guidePaint);
      }
    }

    // Horizontal snap guides
    for (final y in state.snapGuidesY) {
      if ((y - pos.dy).abs() < 30) {
        final guidePaint = Paint()
          ..color = Colors.cyan.withValues(alpha: 0.5)
          ..strokeWidth = 1.0;
        canvas.drawLine(Offset(0, y), Offset(size.width, y), guidePaint);
      }
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // FEATURE 5: WORD HIGHLIGHT
  // ════════════════════════════════════════════════════════════════════════

  void _drawWordHighlight(Canvas canvas, Rect wordRect) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(wordRect, const Radius.circular(2)),
      Paint()..color = Colors.yellow.withValues(alpha: 0.25),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(wordRect, const Radius.circular(2)),
      Paint()
        ..color = Colors.yellow.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5,
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  // FEATURE 8: INK PREDICTION (trajectory line)
  // ════════════════════════════════════════════════════════════════════════

  void _drawInkPrediction(Canvas canvas, Offset pos) {
    final vel = state.velocity;
    if (vel.distance < 0.3) return;

    // Predict trajectory for next ~80ms
    const predictionMs = 80.0;
    final predEnd = Offset(
      pos.dx + vel.dx * predictionMs,
      pos.dy + vel.dy * predictionMs,
    );

    // Draw dotted prediction line
    final path = Path()
      ..moveTo(pos.dx, pos.dy)
      ..lineTo(predEnd.dx, predEnd.dy);

    final paint = Paint()
      ..color = state.brushColor.withValues(alpha: 0.2)
      ..strokeWidth = state.brushSize * 0.3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Simple dashed effect
    final pathMetrics = path.computeMetrics();
    for (final metric in pathMetrics) {
      final length = metric.length;
      double drawn = 0;
      while (drawn < length) {
        final segLen = math.min(4.0, length - drawn);
        final segment = metric.extractPath(drawn, drawn + segLen);
        canvas.drawPath(segment, paint);
        drawn += segLen + 4.0; // dash + gap
      }
    }

    // Fading dot at prediction end
    canvas.drawCircle(
      predEnd,
      state.brushSize * 0.15,
      Paint()..color = state.brushColor.withValues(alpha: 0.1),
    );
  }

  @override
  bool shouldRepaint(covariant _StylusHoverPainter old) => true;
  // Always repaint — hover updates are 120fps and listener-driven
}
