import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/latex/ink_stroke_data.dart';
import '../../core/latex/latex_parser.dart';
import '../../core/latex/latex_layout_engine.dart';
import '../../core/latex/latex_draw_command.dart';

/// 🖊️ LatexInkOverlay — Enterprise-grade ink capture surface for stylus/touch.
///
/// ## Enterprise Features
/// - **E16** Stroke undo: floating button that removes the most recent stroke
/// - **E17** Auto-recognize timer: 1.5s after last stroke, auto-triggers
///   recognition via [onStrokesComplete]
///
/// Material Design 3:
/// - Uses `surfaceContainerHighest` for subtle background tint
/// - Animated border glow during active drawing
/// - Haptic-style visual feedback on stroke start/end
class LatexInkOverlay extends StatefulWidget {
  /// Called when a complete set of strokes is available for recognition.
  final ValueChanged<InkData>? onStrokesComplete;

  /// Called on every new point during drawing (for live ink trail).
  final ValueChanged<InkData>? onStrokesChanged;

  /// Whether the overlay is accepting input.
  final bool enabled;

  /// Background color (defaults to M3 surface tint).
  final Color? backgroundColor;

  /// R5: Ghost rendering — if set, shows a semi-transparent preview of
  /// the recognized LaTeX expression overlaid on the ink strokes.
  final String? ghostLatex;

  /// Font size for ghost rendering.
  final double ghostFontSize;

  /// Color for ghost rendering.
  final Color ghostColor;

  const LatexInkOverlay({
    super.key,
    this.onStrokesComplete,
    this.onStrokesChanged,
    this.enabled = true,
    this.backgroundColor,
    this.ghostLatex,
    this.ghostFontSize = 24.0,
    this.ghostColor = Colors.white,
  });

  @override
  State<LatexInkOverlay> createState() => _LatexInkOverlayState();
}

class _LatexInkOverlayState extends State<LatexInkOverlay>
    with SingleTickerProviderStateMixin {
  final List<InkStroke> _strokes = [];
  List<InkPoint> _currentPoints = [];
  bool _isDrawing = false;

  late final AnimationController _glowController;
  late final Animation<double> _glowAnimation;

  // E17: Auto-recognize timer
  Timer? _autoRecognizeTimer;
  static const _autoRecognizeDelay = Duration(milliseconds: 1500);

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _glowAnimation = CurvedAnimation(
      parent: _glowController,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _autoRecognizeTimer?.cancel();
    _glowController.dispose();
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent event) {
    if (!widget.enabled) return;
    // E17: Cancel any pending auto-recognize when starting a new stroke
    _autoRecognizeTimer?.cancel();

    setState(() {
      _isDrawing = true;
      _currentPoints = [
        InkPoint(
          x: event.localPosition.dx,
          y: event.localPosition.dy,
          pressure: event.pressure,
          timestamp: event.timeStamp.inMilliseconds,
        ),
      ];
    });
    _glowController.forward();
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_isDrawing || !widget.enabled) return;
    setState(() {
      _currentPoints.add(
        InkPoint(
          x: event.localPosition.dx,
          y: event.localPosition.dy,
          pressure: event.pressure,
          timestamp: event.timeStamp.inMilliseconds,
        ),
      );
    });

    // Notify live changes
    widget.onStrokesChanged?.call(
      InkData([..._strokes, InkStroke(_currentPoints)]),
    );
  }

  void _onPointerUp(PointerUpEvent event) {
    if (!_isDrawing) return;
    setState(() {
      _isDrawing = false;
      if (_currentPoints.length >= 2) {
        _strokes.add(InkStroke(List.from(_currentPoints)));
      }
      _currentPoints = [];
    });
    _glowController.reverse();

    // E17: Start auto-recognize timer instead of immediate callback
    _autoRecognizeTimer?.cancel();
    _autoRecognizeTimer = Timer(_autoRecognizeDelay, () {
      if (!mounted || _strokes.isEmpty) return;
      widget.onStrokesComplete?.call(InkData(List.from(_strokes)));
    });
  }

  // E16: Undo last stroke
  void _undoLastStroke() {
    if (_strokes.isEmpty) return;
    HapticFeedback.lightImpact();
    setState(() {
      _strokes.removeLast();
    });

    // E17: Restart auto-recognize timer after undo
    _autoRecognizeTimer?.cancel();
    if (_strokes.isNotEmpty) {
      _autoRecognizeTimer = Timer(_autoRecognizeDelay, () {
        if (!mounted || _strokes.isEmpty) return;
        widget.onStrokesComplete?.call(InkData(List.from(_strokes)));
      });
    }
  }

  /// Clear all captured strokes.
  void clear() {
    _autoRecognizeTimer?.cancel();
    setState(() {
      _strokes.clear();
      _currentPoints.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Stack(
      children: [
        // Main ink surface — decoration only changes on draw start/end,
        // NOT on every pointer move. The AnimatedBuilder is scoped to
        // just the border, not the entire tree.
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color:
                widget.backgroundColor ??
                cs.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _isDrawing ? cs.primary : cs.outlineVariant,
              width: _isDrawing ? 2 : 1,
            ),
          ),
          child: Listener(
            onPointerDown: _onPointerDown,
            onPointerMove: _onPointerMove,
            onPointerUp: _onPointerUp,
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _InkTrailPainter(
                  strokes: _strokes,
                  currentPoints: _currentPoints,
                  strokeColor: cs.primary,
                ),
                foregroundPainter:
                    widget.ghostLatex != null && widget.ghostLatex!.isNotEmpty
                        ? _GhostLatexPainter(
                          latexSource: widget.ghostLatex!,
                          fontSize: widget.ghostFontSize,
                          color: widget.ghostColor.withValues(alpha: 0.35),
                        )
                        : null,
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),

        // E16: Stroke undo FAB
        if (_strokes.isNotEmpty && !_isDrawing)
          Positioned(
            right: 8,
            bottom: 8,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Stroke count badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_strokes.length} tratti',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // Undo last stroke button
                Material(
                  color: cs.secondaryContainer,
                  borderRadius: BorderRadius.circular(12),
                  elevation: 2,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _undoLastStroke,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(
                        Icons.undo_rounded,
                        size: 18,
                        color: cs.onSecondaryContainer,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // Clear all strokes button
                Material(
                  color: cs.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                  elevation: 2,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      clear();
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(
                        Icons.clear_all_rounded,
                        size: 18,
                        color: cs.onErrorContainer,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

        // E17: Auto-recognize indicator (subtle)
        if (_autoRecognizeTimer?.isActive == true && !_isDrawing)
          Positioned(
            left: 8,
            bottom: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Riconoscendo…',
                    style: TextStyle(
                      fontSize: 10,
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Paints live ink trails during drawing.
class _InkTrailPainter extends CustomPainter {
  final List<InkStroke> strokes;
  final List<InkPoint> currentPoints;
  final Color strokeColor;

  _InkTrailPainter({
    required this.strokes,
    required this.currentPoints,
    required this.strokeColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = strokeColor
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true;

    // Draw completed strokes
    for (final stroke in strokes) {
      _drawPoints(canvas, stroke.points, paint);
    }

    // Draw current stroke
    if (currentPoints.isNotEmpty) {
      _drawPoints(canvas, currentPoints, paint);
    }
  }

  void _drawPoints(Canvas canvas, List<InkPoint> points, Paint paint) {
    if (points.length < 2) return;
    for (int i = 0; i < points.length - 1; i++) {
      final p0 = points[i];
      final p1 = points[i + 1];
      paint.strokeWidth = 1.5 + p0.pressure * 3.0;
      canvas.drawLine(Offset(p0.x, p0.y), Offset(p1.x, p1.y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _InkTrailPainter old) =>
      strokes.length != old.strokes.length ||
      currentPoints.length != old.currentPoints.length;
}

/// R5: Ghost rendering painter — draws a semi-transparent LaTeX preview
/// over the ink strokes during handwriting recognition.
class _GhostLatexPainter extends CustomPainter {
  final String latexSource;
  final double fontSize;
  final Color color;

  _GhostLatexPainter({
    required this.latexSource,
    required this.fontSize,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    try {
      final ast = LatexParser.parse(latexSource);
      final result = LatexLayoutEngine.layout(
        ast,
        fontSize: fontSize,
        color: color,
      );

      if (result.commands.isEmpty) return;

      // Center the ghost rendering in the available space
      final dx = (size.width - result.size.width) / 2;
      final dy = (size.height - result.size.height) / 2;

      canvas.save();
      canvas.translate(dx, dy);

      for (final cmd in result.commands) {
        switch (cmd) {
          case GlyphDrawCommand():
            final style = TextStyle(
              fontSize: cmd.fontSize,
              color: cmd.color,
              fontStyle: cmd.italic ? FontStyle.italic : FontStyle.normal,
              fontWeight: cmd.bold ? FontWeight.bold : FontWeight.normal,
              fontFamily: (cmd.fontFamily != null && cmd.fontFamily!.isNotEmpty) ? cmd.fontFamily : null,
            );
            final tp = TextPainter(
              text: TextSpan(text: cmd.text, style: style),
              textDirection: TextDirection.ltr,
            )..layout();
            tp.paint(canvas, Offset(cmd.x, cmd.y));

          case LineDrawCommand():
            canvas.drawLine(
              Offset(cmd.x1, cmd.y1),
              Offset(cmd.x2, cmd.y2),
              Paint()
                ..color = cmd.color
                ..strokeWidth = cmd.thickness
                ..isAntiAlias = true,
            );

          case PathDrawCommand():
            if (cmd.points.isEmpty) continue;
            final path =
                Path()..moveTo(cmd.points.first.dx, cmd.points.first.dy);
            for (int i = 1; i < cmd.points.length; i++) {
              path.lineTo(cmd.points[i].dx, cmd.points[i].dy);
            }
            if (cmd.closed) path.close();
            canvas.drawPath(
              path,
              Paint()
                ..color = cmd.color
                ..style = cmd.filled ? PaintingStyle.fill : PaintingStyle.stroke
                ..strokeWidth = cmd.strokeWidth
                ..isAntiAlias = true,
            );
        }
      }

      canvas.restore();
    } catch (_) {
      // Silently ignore parse/layout errors in ghost rendering
    }
  }

  @override
  bool shouldRepaint(covariant _GhostLatexPainter old) =>
      latexSource != old.latexSource ||
      fontSize != old.fontSize ||
      color != old.color;
}
