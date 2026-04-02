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

  /// Signal to clear all strokes. Increment the value to trigger a clear.
  final ValueNotifier<int>? clearSignal;

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
    this.clearSignal,
  });

  @override
  State<LatexInkOverlay> createState() => _LatexInkOverlayState();
}

class _LatexInkOverlayState extends State<LatexInkOverlay>
    with SingleTickerProviderStateMixin {
  final List<InkStroke> _strokes = [];
  final List<InkPoint> _currentPoints = [];
  bool _isDrawing = false;

  late final AnimationController _glowController;
  late final Animation<double> _glowAnimation;

  // 🚀 PERFORMANCE: Lightweight repaint trigger for the ink trail.
  // Incremented on every pointer-move to repaint ONLY the CustomPaint,
  // without rebuilding the entire widget tree via setState.
  final ValueNotifier<int> _inkRepaintNotifier = ValueNotifier(0);

  // 🚀 PERFORMANCE: Cached painter — created once, survives rebuilds.
  // Holds mutable list references (_strokes, _currentPoints) so paint()
  // always sees the latest data without needing a new painter instance.
  _InkTrailPainter? _cachedInkPainter;

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
    widget.clearSignal?.addListener(_onClearSignal);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Create the cached painter lazily (needs Theme.of which requires context)
    _cachedInkPainter ??= _InkTrailPainter(
      strokes: _strokes,
      currentPoints: _currentPoints,
      strokeColor: Theme.of(context).colorScheme.primary,
      repaint: _inkRepaintNotifier,
    );
  }

  @override
  void didUpdateWidget(covariant LatexInkOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clearSignal != widget.clearSignal) {
      oldWidget.clearSignal?.removeListener(_onClearSignal);
      widget.clearSignal?.addListener(_onClearSignal);
    }
  }

  void _onClearSignal() {
    clear();
  }

  @override
  void dispose() {
    widget.clearSignal?.removeListener(_onClearSignal);
    _autoRecognizeTimer?.cancel();
    _inkRepaintNotifier.dispose();
    _glowController.dispose();
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent event) {
    if (!widget.enabled) return;
    // E17: Cancel any pending auto-recognize when starting a new stroke
    _autoRecognizeTimer?.cancel();

    _isDrawing = true;
    // 🚀 CRITICAL: clear + add, NOT reassign! The cached painter holds
    // a reference to this list. Reassigning would leave it painting
    // from a stale, empty list — causing the "frozen stroke" bug.
    _currentPoints.clear();
    _currentPoints.add(
      InkPoint(
        x: event.localPosition.dx,
        y: event.localPosition.dy,
        pressure: event.pressure,
        timestamp: event.timeStamp.inMilliseconds,
      ),
    );
    // setState only for border glow transition (structural change)
    setState(() {});
    _glowController.forward();
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_isDrawing || !widget.enabled) return;

    // 🚀 NO setState — just mutate the list and trigger a repaint
    // of only the ink trail CustomPaint via ValueNotifier.
    _currentPoints.add(
      InkPoint(
        x: event.localPosition.dx,
        y: event.localPosition.dy,
        pressure: event.pressure,
        timestamp: event.timeStamp.inMilliseconds,
      ),
    );
    _inkRepaintNotifier.value++;

    // Notify live changes
    widget.onStrokesChanged?.call(
      InkData([..._strokes, InkStroke(_currentPoints)]),
    );
  }

  void _onPointerUp(PointerUpEvent event) {
    if (!_isDrawing) return;
    _isDrawing = false;
    if (_currentPoints.length >= 2) {
      _strokes.add(InkStroke(List.from(_currentPoints)));
    }
    _currentPoints.clear(); // 🚀 clear, NOT reassign
    // setState for structural changes (undo button visibility, border)
    setState(() {});
    _inkRepaintNotifier.value++;
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
    _inkRepaintNotifier.value++;

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
    _inkRepaintNotifier.value++;
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
            child: Stack(
              children: [
                // Ghost LaTeX preview — separate RepaintBoundary so it
                // only repaints when the LaTeX source changes, NOT on
                // every pointer move during ink drawing.
                if (widget.ghostLatex != null && widget.ghostLatex!.isNotEmpty)
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: _GhostLatexPainter(
                          latexSource: widget.ghostLatex!,
                          fontSize: widget.ghostFontSize,
                          color: widget.ghostColor.withValues(alpha: 0.35),
                        ),
                      ),
                    ),
                  ),
                // Live ink trail — CACHED painter, driven by repaint Listenable.
                // The painter persists across widget rebuilds. Only paint()
                // is called when _inkRepaintNotifier fires — ZERO allocations.
                Positioned.fill(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _cachedInkPainter!,
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ],
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
///
/// 🚀 PERFORMANCE: Uses [repaint] Listenable for zero-rebuild repaints.
/// [shouldRepaint] always returns false — repaints are driven exclusively
/// by the ValueNotifier, so no widget tree allocation occurs per frame.
class _InkTrailPainter extends CustomPainter {
  final List<InkStroke> strokes;
  final List<InkPoint> currentPoints;
  final Color strokeColor;

  _InkTrailPainter({
    required this.strokes,
    required this.currentPoints,
    required this.strokeColor,
    required Listenable repaint,
  }) : super(repaint: repaint);

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
  bool shouldRepaint(covariant _InkTrailPainter old) => false;
}

/// R5: Ghost rendering painter — draws a semi-transparent LaTeX preview
/// over the ink strokes during handwriting recognition.
///
/// PERFORMANCE: Parse + layout results are cached. The expensive
/// `LatexParser.parse()` + `LatexLayoutEngine.layout()` only run when
/// `shouldRepaint` returns true (i.e., when latexSource changes).
class _GhostLatexPainter extends CustomPainter {
  final String latexSource;
  final double fontSize;
  final Color color;

  // Cached layout result — computed lazily on first paint, reused after.
  List<LatexDrawCommand>? _cachedCommands;
  Size? _cachedSize;
  String? _cachedSource;

  _GhostLatexPainter({
    required this.latexSource,
    required this.fontSize,
    required this.color,
  });

  void _ensureLayout() {
    if (_cachedSource == latexSource) return;
    _cachedSource = latexSource;
    try {
      final ast = LatexParser.parse(latexSource);
      final result = LatexLayoutEngine.layout(
        ast,
        fontSize: fontSize,
        color: color,
      );
      _cachedCommands = result.commands;
      _cachedSize = result.size;
    } catch (_) {
      _cachedCommands = null;
      _cachedSize = null;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    _ensureLayout();
    final commands = _cachedCommands;
    final layoutSize = _cachedSize;
    if (commands == null || commands.isEmpty || layoutSize == null) return;

    // Center the ghost rendering in the available space
    final dx = (size.width - layoutSize.width) / 2;
    final dy = (size.height - layoutSize.height) / 2;

    canvas.save();
    canvas.translate(dx, dy);

    for (final cmd in commands) {
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

        case RectDrawCommand():
          canvas.drawRect(
            Rect.fromLTWH(cmd.x, cmd.y, cmd.width, cmd.height),
            Paint()
              ..color = cmd.color
              ..style = cmd.filled ? PaintingStyle.fill : PaintingStyle.stroke
              ..isAntiAlias = true,
          );
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GhostLatexPainter old) =>
      latexSource != old.latexSource ||
      fontSize != old.fontSize ||
      color != old.color;
}
