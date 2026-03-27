import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../core/latex/latex_evaluator.dart';
import 'graph_painter.dart';
import 'graph_widgets.dart';

// =============================================================================
// LATEX FUNCTION GRAPH WIDGET
// =============================================================================

/// 📈 Interactive function graph for LaTeX expressions.
///
/// Full features:
/// - Pan + pinch-to-zoom (A9: focal)
/// - A3: Integral computation
/// - A4: Curve draw animation
/// - A5: Double-tap zoom
/// - A7: Crosshair snapping to notable points
/// - A8: Value table
/// - A10: Screenshot export
/// - G3: Tap + long-press crosshair
/// - G7: Animated viewport transitions
class LatexFunctionGraph extends StatefulWidget {
  final String latexSource;
  final double height;
  final Color? accentColor;

  Color get curveColor => accentColor ?? Colors.blue;

  const LatexFunctionGraph({
    super.key,
    required this.latexSource,
    this.height = 280,
    this.accentColor,
    this.onInsertToCanvas,
  });

  /// Called when the user taps 'Inserisci nel Canvas'.
  /// Receives: latexSource, xMin, xMax, yMin, yMax, curveColor.
  final void Function(String latexSource, double xMin, double xMax, double yMin, double yMax, int curveColor)? onInsertToCanvas;

  @override
  State<LatexFunctionGraph> createState() => _LatexFunctionGraphState();
}

class _LatexFunctionGraphState extends State<LatexFunctionGraph>
    with TickerProviderStateMixin {
  // ── Viewport ──
  double _xMin = -10;
  double _xMax = 10;
  double _yMin = -6;
  double _yMax = 6;

  // ── G7: Animated viewport ──
  late final AnimationController _viewportAnim;
  double _animFromXMin = -10, _animFromXMax = 10;
  double _animFromYMin = -6, _animFromYMax = 6;
  double _animToXMin = -10, _animToXMax = 10;
  double _animToYMin = -6, _animToYMax = 6;

  // ── A4: Curve draw animation ──
  late final AnimationController _curveAnim;

  // ── Samples ──
  static const int _sampleCount = 500;
  List<Offset> _points = [];
  List<Offset> _derivativePoints = [];

  // ── E1: Multi-function ──
  List<String> _functions = []; // parsed from latexSource via `;`
  List<List<Offset>> _extraPoints = [];
  List<double> _extraCrosshairYs = [];
  List<Offset> _intersectionPts = [];
  Set<int> _hiddenFunctions = {};  // indices of hidden functions (0 = primary)
  static const _extraPalette = [
    Color(0xFFEA4335), // red
    Color(0xFF34A853), // green
    Color(0xFFFF6D01), // orange
    Color(0xFF9334E6), // purple
    Color(0xFF00ACC1), // teal
  ];

  // ── M3 Toolbar tab ──
  int _selectedTab = 0;

  // ── Display toggles ──
  bool _showGrid = true;
  bool _showMinorGrid = false;
  bool _showAxes = true;
  bool _showDerivative = false;
  bool _showArea = false;
  int _areaMode = 0; // 0 = to x-axis (∫), 1 = fill below
  bool _showRoots = true;
  bool _useGradient = true;
  bool _showCriticalPoints = false;
  bool _showAsymptotes = false;
  bool _showMonotonicity = false;
  bool _showInflection = false;
  bool _showLegend = false;

  // ── D1: Parameter sliders ──
  List<String> _detectedParams = [];
  Map<String, double> _paramValues = {};
  double _coeffK = 1.0;  // function coefficient multiplier
  double _offsetD = 0.0; // vertical offset
  double _lastSnapK = 1.0; // track last snapped integer for haptic
  double _lastSnapD = 0.0;

  // ── A3: Integral ──
  double? _integralValue;

  // ── B2: Inflection points ──
  List<Offset> _inflectionPoints = [];

  // ── Crosshair ──
  Offset? _crosshair;
  bool _isTouching = false;
  String? _crosshairSnapLabel;
  double? _tangentSlope;

  // ── Gesture state ──
  double? _panStartX;
  double? _panStartY;
  double _panAnchorXMin = 0;
  double _panAnchorXMax = 0;
  double _panAnchorYMin = 0;
  double _panAnchorYMax = 0;
  Offset _lastFocalPoint = Offset.zero;
  DateTime _lastFocalTime = DateTime.now();
  Offset _flingVelocity = Offset.zero;
  bool _isFlingRunning = false;
  bool _isPinching = false;

  // ── B7: Debounce timer ──
  Timer? _resampleDebounce;

  // ── B4: Zoom limits ──
  static const double _minRange = 0.01;
  static const double _maxRange = 10000;

  // ── C1: Crosshair fade animation ──
  late final AnimationController _crosshairAnim;

  // ── A10: Screenshot key ──
  final GlobalKey _graphKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _viewportAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    )..addListener(_onViewportAnimTick);

    // A4: Curve draw animation
    _curveAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..addListener(() => setState(() {}));

    // D1: Detect parameters (BEFORE resample so _paramValues is populated)
    _detectParams();

    // E1: Parse functions
    _parseFunctions();

    _resample();
    _curveAnim.forward();

    // C1: Crosshair fade
    _crosshairAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    )..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _viewportAnim.dispose();
    _curveAnim.dispose();
    _crosshairAnim.dispose();
    _resampleDebounce?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant LatexFunctionGraph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.latexSource != widget.latexSource) {
      _detectParams();
      _parseFunctions();
      _resample();
      _curveAnim.forward(from: 0);
    }
  }

  // ── G7: Animate to a new viewport ──
  void _animateToViewport(double xMin, double xMax, double yMin, double yMax) {
    _animFromXMin = _xMin;
    _animFromXMax = _xMax;
    _animFromYMin = _yMin;
    _animFromYMax = _yMax;
    _animToXMin = xMin;
    _animToXMax = xMax;
    _animToYMin = yMin;
    _animToYMax = yMax;
    _viewportAnim.forward(from: 0);
  }

  void _onViewportAnimTick() {
    final t = Curves.easeInOut.transform(_viewportAnim.value);
    setState(() {
      _xMin = _lerp(_animFromXMin, _animToXMin, t);
      _xMax = _lerp(_animFromXMax, _animToXMax, t);
      _yMin = _lerp(_animFromYMin, _animToYMin, t);
      _yMax = _lerp(_animFromYMax, _animToYMax, t);
    });
    _resample();
  }

  // ── D1: Detect non-x parameters ──
  void _detectParams() {
    final candidates = 'abcdklmnpqrst'.split('');
    final found = <String>[];
    for (final c in candidates) {
      if (LatexEvaluator.containsVariable(_primarySource, c)) {
        found.add(c);
      }
    }
    setState(() {
      _detectedParams = found;
      // Preserve existing values, default new ones to 1.0
      final newMap = <String, double>{};
      for (final p in found) {
        newMap[p] = _paramValues[p] ?? 1.0;
      }
      _paramValues = newMap;
    });
  }

  /// Build variable bindings for evaluateWith (x + params)
  Map<String, double> _vars(double x) {
    return {'x': x, ..._paramValues};
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t;

  /// E1: Parse semicolon-separated functions
  void _parseFunctions() {
    _functions = widget.latexSource
        .split(';')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (_functions.isEmpty) _functions = [widget.latexSource];
  }

  /// Primary function source (first one)
  String get _primarySource => _functions.isNotEmpty ? _functions.first : widget.latexSource;

  void _resample() {
    final xRange = _xMax - _xMin;
    final step = xRange / _sampleCount;

    final pts = <Offset>[];
    final dpts = <Offset>[];

    for (int i = 0; i <= _sampleCount; i++) {
      final x = _xMin + step * i;
      try {
        final y = LatexEvaluator.evaluateWith(_primarySource, _vars(x));
        pts.add(Offset(x, y * _coeffK + _offsetD));
      } catch (_) {
        pts.add(Offset(x, double.nan));
      }
    }

    // Only compute derivative when needed
    if (_showDerivative || _showCriticalPoints || _showMonotonicity || _showInflection) {
      for (int i = 0; i <= _sampleCount; i++) {
        final x = _xMin + step * i;
        const h = 0.001;
        try {
          final yPlus = LatexEvaluator.evaluateWith(_primarySource, _vars(x + h));
          final yMinus = LatexEvaluator.evaluateWith(_primarySource, _vars(x - h));
          final dy = (yPlus - yMinus) / (2 * h);
          dpts.add(Offset(x, dy));
        } catch (_) {
          dpts.add(Offset(x, double.nan));
        }
      }
    }

    // B2: Detect inflection points (where f''(x) changes sign)
    final infPts = <Offset>[];
    if (_showInflection && dpts.length >= 3) {
      for (int i = 1; i < dpts.length - 1; i++) {
        final prev = dpts[i - 1].dy;
        final next = dpts[i + 1].dy;
        if (!prev.isFinite || !next.isFinite) continue;
        // Sign change in f'(x) derivative = inflection
        // Approximate f''(x) at i-1 and i+1 via second difference
        final fpp_prev = dpts[i].dy - dpts[i - 1].dy;
        final fpp_next = dpts[i + 1].dy - dpts[i].dy;
        if ((fpp_prev > 0 && fpp_next < 0) || (fpp_prev < 0 && fpp_next > 0)) {
          if (i < pts.length && pts[i].dy.isFinite) {
            infPts.add(Offset(pts[i].dx, pts[i].dy));
          }
        }
      }
    }

    // A3: Compute integral (trapezoidal rule)
    double? integral;
    if (_showArea) {
      double sum = 0;
      for (int i = 0; i < pts.length - 1; i++) {
        final a = pts[i];
        final b = pts[i + 1];
        if (a.dy.isFinite && b.dy.isFinite) {
          sum += (a.dy + b.dy) / 2 * (b.dx - a.dx);
        }
      }
      integral = sum;
    }

    setState(() {
      _points = pts;
      _derivativePoints = dpts;
      _integralValue = integral;
      _inflectionPoints = infPts;
    });

    // E1: Sample extra functions (index 1, 2, ...)
    final extras = <List<Offset>>[];
    for (int fi = 1; fi < _functions.length; fi++) {
      final src = _functions[fi];
      final ep = <Offset>[];
      for (int i = 0; i <= _sampleCount; i++) {
        final x = _xMin + step * i;
        try {
          final y = LatexEvaluator.evaluateWith(src, _vars(x));
          ep.add(Offset(x, y * _coeffK + _offsetD));
        } catch (_) {
          ep.add(Offset(x, double.nan));
        }
      }
      extras.add(ep);
    }
    setState(() => _extraPoints = extras);

    // E3: Detect intersections between primary and each extra curve
    final inters = <Offset>[];
    for (final ep in extras) {
      for (int i = 0; i < pts.length - 1 && i < ep.length - 1; i++) {
        final a1 = pts[i].dy, b1 = pts[i + 1].dy;
        final a2 = ep[i].dy, b2 = ep[i + 1].dy;
        if (!a1.isFinite || !b1.isFinite || !a2.isFinite || !b2.isFinite) continue;
        final diff1 = a1 - a2;
        final diff2 = b1 - b2;
        if ((diff1 > 0 && diff2 < 0) || (diff1 < 0 && diff2 > 0)) {
          // Linear interpolation for intersection x
          final t = diff1 / (diff1 - diff2);
          final ix = pts[i].dx + t * (pts[i + 1].dx - pts[i].dx);
          final iy = a1 + t * (b1 - a1);
          inters.add(Offset(ix, iy));
        }
      }
    }
    setState(() => _intersectionPts = inters);
  }

  // B7: Debounced resample for gestures
  void _resampleDebounced() {
    _resampleDebounce?.cancel();
    _resampleDebounce = Timer(const Duration(milliseconds: 16), _resample);
  }

  // B4: Clamp viewport to zoom limits
  void _clampViewport() {
    final xRange = _xMax - _xMin;
    final yRange = _yMax - _yMin;
    if (xRange < _minRange) {
      final cx = (_xMin + _xMax) / 2;
      _xMin = cx - _minRange / 2;
      _xMax = cx + _minRange / 2;
    }
    if (xRange > _maxRange) {
      final cx = (_xMin + _xMax) / 2;
      _xMin = cx - _maxRange / 2;
      _xMax = cx + _maxRange / 2;
    }
    if (yRange < _minRange) {
      final cy = (_yMin + _yMax) / 2;
      _yMin = cy - _minRange / 2;
      _yMax = cy + _minRange / 2;
    }
    if (yRange > _maxRange) {
      final cy = (_yMin + _yMax) / 2;
      _yMin = cy - _maxRange / 2;
      _yMax = cy + _maxRange / 2;
    }
  }

  void _resetView() => _animateToViewport(-10, 10, -6, 6);

  void _zoomIn() {
    final cx = (_xMin + _xMax) / 2;
    final cy = (_yMin + _yMax) / 2;
    final xr = (_xMax - _xMin) * 0.35;
    final yr = (_yMax - _yMin) * 0.35;
    _animateToViewport(cx - xr, cx + xr, cy - yr, cy + yr);
  }

  void _zoomOut() {
    final cx = (_xMin + _xMax) / 2;
    final cy = (_yMin + _yMax) / 2;
    final xr = (_xMax - _xMin) * 0.75;
    final yr = (_yMax - _yMin) * 0.75;
    _animateToViewport(cx - xr, cx + xr, cy - yr, cy + yr);
  }

  void _autoFit() {
    double minY = double.infinity;
    double maxY = double.negativeInfinity;
    for (final pt in _points) {
      if (pt.dy.isFinite && pt.dy.abs() < 1e6) {
        if (pt.dy < minY) minY = pt.dy;
        if (pt.dy > maxY) maxY = pt.dy;
      }
    }
    if (minY.isInfinite || maxY.isInfinite) return;
    if (minY == maxY) {
      // Constant function — show ±1 around the value
      minY -= 1;
      maxY += 1;
    }
    final margin = (maxY - minY) * 0.15;
    _animateToViewport(_xMin, _xMax, minY - margin, maxY + margin);
  }

  // ── A5: Double-tap zoom at point ──
  void _onDoubleTap(TapDownDetails details) {
    final size = context.size;
    if (size == null) return;

    HapticFeedback.lightImpact();

    // Convert tap position to math coords
    final xRange = _xMax - _xMin;
    final yRange = _yMax - _yMin;
    final tapX = _xMin + (details.localPosition.dx / size.width) * xRange;
    final tapY = _yMax - (details.localPosition.dy / size.height) * yRange;

    // Zoom in 2x toward this point
    final newXRange = xRange * 0.5;
    final newYRange = yRange * 0.5;
    _animateToViewport(
      tapX - newXRange / 2,
      tapX + newXRange / 2,
      tapY - newYRange / 2,
      tapY + newYRange / 2,
    );
  }

  // ── A7: Crosshair with snapping ──
  void _updateCrosshair(Offset localPos) {
    final size = context.size;
    if (size == null) return;
    final mx = _xMin + (localPos.dx / size.width) * (_xMax - _xMin);
    double my;
    try {
      my = LatexEvaluator.evaluateWith(_primarySource, _vars(mx)) * _coeffK + _offsetD;
    } catch (_) {
      my = double.nan;
    }

    // A7: Check for snap targets
    String? snapLabel;
    final snapThreshold = (_xMax - _xMin) / _sampleCount * 3;

    // Snap to roots
    for (int i = 0; i < _points.length - 1; i++) {
      final a = _points[i];
      final b = _points[i + 1];
      if (!a.dy.isFinite || !b.dy.isFinite) continue;
      if ((a.dy > 0 && b.dy < 0) || (a.dy < 0 && b.dy > 0)) {
        final rootX = a.dx + a.dy / (a.dy - b.dy) * (b.dx - a.dx);
        if ((mx - rootX).abs() < snapThreshold) {
          snapLabel = 'RADICE';
          break;
        }
      }
    }

    // Snap to critical points
    if (snapLabel == null) {
      for (int i = 1; i < _derivativePoints.length - 1; i++) {
        if (!_derivativePoints[i].dy.isFinite) continue;
        final prev = _derivativePoints[i - 1].dy;
        final next = _derivativePoints[i + 1].dy;
        if ((prev > 0 && next < 0) || (prev < 0 && next > 0)) {
          if ((mx - _derivativePoints[i].dx).abs() < snapThreshold) {
            snapLabel = prev > 0 ? 'MAX' : 'MIN';
            break;
          }
        }
      }
    }

    // Snap to integer x
    if (snapLabel == null) {
      final nearestInt = mx.round().toDouble();
      if ((mx - nearestInt).abs() < snapThreshold * 0.5) {
        snapLabel = 'x=${nearestInt.toInt()}';
      }
    }

    // B1: Compute tangent slope at crosshair x
    double? slope;
    if (my.isFinite) {
      const h = 0.001;
      try {
        final yp = LatexEvaluator.evaluateWith(_primarySource, _vars(mx + h));
        final ym = LatexEvaluator.evaluateWith(_primarySource, _vars(mx - h));
        slope = (yp - ym) / (2 * h);
        if (!slope.isFinite) slope = null;
      } catch (_) {
        slope = null;
      }
    }

    // C2: Differentiated haptic feedback
    if (snapLabel == 'RADICE') {
      HapticFeedback.heavyImpact();
    } else if (snapLabel == 'MAX' || snapLabel == 'MIN') {
      HapticFeedback.mediumImpact();
    } else if (snapLabel != null && snapLabel.startsWith('x=')) {
      HapticFeedback.lightImpact();
    }

    setState(() {
      if (my.isFinite) {
        _crosshair = Offset(mx, my);
      } else {
        _crosshair = Offset(mx, 0);
        snapLabel = 'NON DEF.';
      }
      _crosshairSnapLabel = snapLabel;
      _tangentSlope = slope;

      // E2: Evaluate extra functions at crosshair x
      final extraYs = <double>[];
      for (int fi = 1; fi < _functions.length; fi++) {
        try {
          final ey = LatexEvaluator.evaluateWith(_functions[fi], _vars(mx));
          extraYs.add(ey);
        } catch (_) {
          extraYs.add(double.nan);
        }
      }
      _extraCrosshairYs = extraYs;
    });

    // C1: Fade in crosshair
    if (!_crosshairAnim.isCompleted) {
      _crosshairAnim.forward();
    }
  }

  // ── A10: Screenshot (enhanced) ──
  Future<void> _exportScreenshot() async {
    try {
      final boundary = _graphKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final bytes = byteData.buffer.asUint8List();
      final sizeKB = (bytes.length / 1024).toStringAsFixed(0);
      final dim = '${image.width}×${image.height}';

      // Copy info to clipboard
      await Clipboard.setData(ClipboardData(
        text: 'Grafico f(x) = ${widget.latexSource}\n'
            'Dimensione: $dim px, $sizeKB KB\n'
            'Dominio: x ∈ [${_xMin.toStringAsFixed(2)}, ${_xMax.toStringAsFixed(2)}]',
      ));

      if (mounted) {
        HapticFeedback.mediumImpact();
        final cs = Theme.of(context).colorScheme;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: cs.inversePrimary, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Screenshot $dim • $sizeKB KB',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Screenshot error: $e');
    }
  }

  // ── A8: Value table (enhanced) ──
  void _showValueTable() {
    final cs = Theme.of(context).colorScheme;
    final step = (_xMax - _xMin) / 20;
    final hasDeriv = _showDerivative || _showCriticalPoints || _showMonotonicity;
    final entries = <(double, double, double?)>[];

    // Find roots and extrema for highlighting
    final rootXs = <double>{};
    final minXs = <double>{};
    final maxXs = <double>{};

    for (int i = 0; i <= 20; i++) {
      final x = _xMin + step * i;
      double y;
      try {
        y = LatexEvaluator.evaluateWith(_primarySource, _vars(x));
      } catch (_) {
        y = double.nan;
      }
      double? dy;
      if (hasDeriv) {
        const h = 0.001;
        try {
          final yp = LatexEvaluator.evaluateWith(_primarySource, _vars(x + h));
          final ym = LatexEvaluator.evaluateWith(_primarySource, _vars(x - h));
          dy = (yp - ym) / (2 * h);
          if (!dy.isFinite) dy = null;
        } catch (_) {
          dy = null;
        }
      }
      entries.add((x, y, dy));

      // Detect roots (y close to 0)
      if (y.isFinite && y.abs() < 0.05 * (_xMax - _xMin) / 20) {
        rootXs.add(x);
      }
    }

    // Detect extrema from sign changes in derivative
    for (int i = 1; i < entries.length; i++) {
      final prevDy = entries[i - 1].$3;
      final currDy = entries[i].$3;
      if (prevDy != null && currDy != null && prevDy.isFinite && currDy.isFinite) {
        if (prevDy > 0 && currDy < 0) maxXs.add(entries[i].$1);
        if (prevDy < 0 && currDy > 0) minXs.add(entries[i].$1);
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.8,
        expand: false,
        builder: (ctx, scrollController) => Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header with copy button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Icon(Icons.table_chart_rounded, size: 18, color: cs.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Tabella Valori',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  const Spacer(),
                  // Copy button
                  IconButton(
                    icon: Icon(Icons.copy_rounded, size: 18, color: cs.primary),
                    onPressed: () {
                      final sb = StringBuffer();
                      sb.writeln(hasDeriv ? 'x\tf(x)\tf\'(x)' : 'x\tf(x)');
                      for (final (x, y, dy) in entries) {
                        final yStr = y.isFinite ? y.toStringAsFixed(4) : '∞';
                        if (hasDeriv && dy != null) {
                          sb.writeln('${x.toStringAsFixed(2)}\t$yStr\t${dy.toStringAsFixed(4)}');
                        } else {
                          sb.writeln('${x.toStringAsFixed(2)}\t$yStr');
                        }
                      }
                      Clipboard.setData(ClipboardData(text: sb.toString()));
                      HapticFeedback.mediumImpact();
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(
                          content: const Text('Tabella copiata'),
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    },
                    tooltip: 'Copia tabella',
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${entries.length} punti',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const Divider(),
            // Column headers
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  SizedBox(
                    width: 70,
                    child: Text('x', style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: cs.primary,
                      fontFamily: 'monospace',
                    )),
                  ),
                  Expanded(
                    child: Text('f(x)', style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: cs.primary,
                      fontFamily: 'monospace',
                    )),
                  ),
                  if (hasDeriv)
                    SizedBox(
                      width: 80,
                      child: Text("f'(x)", style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: cs.tertiary,
                        fontFamily: 'monospace',
                      )),
                    ),
                ],
              ),
            ),
            const Divider(height: 8),
            // Data rows with special highlighting
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: entries.length,
                itemBuilder: (_, i) {
                  final (x, y, dy) = entries[i];
                  final yStr = y.isFinite ? y.toStringAsFixed(4) : '∞';
                  final dyStr = dy != null && dy.isFinite ? dy.toStringAsFixed(4) : '—';

                  // Row highlighting
                  Color? rowColor;
                  String? badge;
                  if (rootXs.contains(x)) {
                    rowColor = Colors.green.withValues(alpha: 0.08);
                    badge = 'RADICE';
                  } else if (maxXs.contains(x)) {
                    rowColor = Colors.red.withValues(alpha: 0.08);
                    badge = 'MAX';
                  } else if (minXs.contains(x)) {
                    rowColor = Colors.blue.withValues(alpha: 0.08);
                    badge = 'MIN';
                  } else if (i.isEven) {
                    rowColor = cs.surfaceContainerHighest.withValues(alpha: 0.3);
                  }

                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    color: rowColor,
                    child: Row(
                      children: [
                        SizedBox(
                          width: 70,
                          child: Text(
                            x.toStringAsFixed(2),
                            style: TextStyle(
                              fontSize: 12,
                              fontFamily: 'monospace',
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Row(
                            children: [
                              Text(
                                yStr,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                  color: y.isFinite ? cs.onSurface : cs.error,
                                  fontWeight: y.isFinite ? FontWeight.w400 : FontWeight.w600,
                                ),
                              ),
                              if (badge != null) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: badge == 'RADICE'
                                        ? Colors.green.withValues(alpha: 0.2)
                                        : badge == 'MAX'
                                            ? Colors.red.withValues(alpha: 0.2)
                                            : Colors.blue.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    badge,
                                    style: TextStyle(
                                      fontSize: 8,
                                      fontWeight: FontWeight.w700,
                                      color: badge == 'RADICE'
                                          ? Colors.green
                                          : badge == 'MAX'
                                              ? Colors.red
                                              : Colors.blue,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (hasDeriv)
                          SizedBox(
                            width: 80,
                            child: Text(
                              dyStr,
                              style: TextStyle(
                                fontSize: 12,
                                fontFamily: 'monospace',
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Enhanced Condividi: comprehensive report ──
  void _shareReport() {
    final sb = StringBuffer();
    sb.writeln('=== Analisi Funzione ===');
    sb.writeln('f(x) = ${_primarySource}');
    sb.writeln('Dominio: x ∈ [${_xMin.toStringAsFixed(2)}, ${_xMax.toStringAsFixed(2)}]');
    sb.writeln('Codominio: y ∈ [${_yMin.toStringAsFixed(2)}, ${_yMax.toStringAsFixed(2)}]');
    sb.writeln();

    // Find roots
    final roots = <double>[];
    for (int i = 0; i < _points.length - 1; i++) {
      final a = _points[i];
      final b = _points[i + 1];
      if (a.dy.isFinite && b.dy.isFinite) {
        if ((a.dy > 0 && b.dy < 0) || (a.dy < 0 && b.dy > 0)) {
          // Linear interpolation for root
          final x0 = a.dx - a.dy * (b.dx - a.dx) / (b.dy - a.dy);
          roots.add(x0);
        }
      }
    }
    if (roots.isNotEmpty) {
      sb.writeln('Radici (zeri): ${roots.map((r) => 'x ≈ ${r.toStringAsFixed(3)}').join(', ')}');
    } else {
      sb.writeln('Radici: nessuna nel dominio visibile');
    }

    // Find extrema from derivative points
    if (_derivativePoints.length >= 2) {
      final maxima = <String>[];
      final minima = <String>[];
      for (int i = 1; i < _derivativePoints.length; i++) {
        final prev = _derivativePoints[i - 1].dy;
        final curr = _derivativePoints[i].dy;
        if (!prev.isFinite || !curr.isFinite) continue;
        if (prev > 0 && curr < 0 && i < _points.length) {
          maxima.add('(${_points[i].dx.toStringAsFixed(3)}, ${_points[i].dy.toStringAsFixed(3)})');
        }
        if (prev < 0 && curr > 0 && i < _points.length) {
          minima.add('(${_points[i].dx.toStringAsFixed(3)}, ${_points[i].dy.toStringAsFixed(3)})');
        }
      }
      if (maxima.isNotEmpty) sb.writeln('Massimi: ${maxima.join(', ')}');
      if (minima.isNotEmpty) sb.writeln('Minimi: ${minima.join(', ')}');
      if (maxima.isEmpty && minima.isEmpty) sb.writeln('Estremi: nessuno');
    }

    // Inflection
    if (_inflectionPoints.isNotEmpty) {
      final infStr = _inflectionPoints.map((p) =>
        '(${p.dx.toStringAsFixed(3)}, ${p.dy.toStringAsFixed(3)})'
      ).join(', ');
      sb.writeln('Flessi: $infStr');
    }

    // Integral
    if (_integralValue != null) {
      sb.writeln();
      sb.writeln('∫ f(x)dx ≈ ${_integralValue!.toStringAsFixed(4)} '
          '(su [${_xMin.toStringAsFixed(2)}, ${_xMax.toStringAsFixed(2)}])');
    }

    Clipboard.setData(ClipboardData(text: sb.toString()));
    HapticFeedback.mediumImpact();
    final cs = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle_rounded, color: cs.inversePrimary, size: 18),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Report analisi copiato', style: TextStyle(fontWeight: FontWeight.w500)),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final zoomLevel = (20 / (_xMax - _xMin) * 100).round();

    return SizedBox(
      height: widget.height,
      child: Column(
        children: [
          // ── Graph area ──
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              decoration: BoxDecoration(
                color: isDark
                    ? cs.surfaceContainerLowest
                    : cs.surfaceContainerLow,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.2),
                  width: 0.5,
                ),
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                child: RepaintBoundary(
                  key: _graphKey,
                  child: Stack(
                    children: [
                      // Graph with gestures
                      GestureDetector(
                        onDoubleTapDown: _onDoubleTap,
                        onDoubleTap: () {},
                        onTapDown: (d) {
                          HapticFeedback.selectionClick();
                          _updateCrosshair(d.localPosition);
                          setState(() => _isTouching = true);
                        },
                        onTapUp: (_) {
                          Future.delayed(const Duration(seconds: 2), () {
                            if (mounted && !_isTouching) {
                              setState(() {
                                _crosshair = null;
                                _crosshairSnapLabel = null;
                              });
                              _crosshairAnim.reset();
                            }
                          });
                          setState(() => _isTouching = false);
                        },
                        onScaleStart: (d) {
                          _panStartX = d.localFocalPoint.dx;
                          _panStartY = d.localFocalPoint.dy;
                          _panAnchorXMin = _xMin;
                          _panAnchorXMax = _xMax;
                          _panAnchorYMin = _yMin;
                          _panAnchorYMax = _yMax;
                          _lastFocalPoint = d.localFocalPoint;
                          _lastFocalTime = DateTime.now();
                          _flingVelocity = Offset.zero;
                          _isFlingRunning = false;
                          _isPinching = d.pointerCount > 1;
                          setState(() {
                            _crosshair = null;
                            _crosshairSnapLabel = null;
                            _isTouching = false;
                            _crosshairAnim.reset();
                          });
                        },
                        onScaleUpdate: (d) {
                          if (_panStartX == null) return;
                          final size = context.size;
                          if (size == null) return;
                          _isPinching = d.pointerCount > 1;

                          // Track velocity for fling
                          final now = DateTime.now();
                          final dt = now.difference(_lastFocalTime).inMicroseconds / 1000000.0;
                          if (dt > 0.001) {
                            final vx = (d.localFocalPoint.dx - _lastFocalPoint.dx) / dt;
                            final vy = (d.localFocalPoint.dy - _lastFocalPoint.dy) / dt;
                            // Exponential smoothing for velocity
                            _flingVelocity = Offset(
                              _flingVelocity.dx * 0.5 + vx * 0.5,
                              _flingVelocity.dy * 0.5 + vy * 0.5,
                            );
                          }
                          _lastFocalPoint = d.localFocalPoint;
                          _lastFocalTime = now;

                          final anchorXRange = _panAnchorXMax - _panAnchorXMin;
                          final anchorYRange = _panAnchorYMax - _panAnchorYMin;

                          // Pan (always applies)
                          final dx = d.localFocalPoint.dx - _panStartX!;
                          final dy = d.localFocalPoint.dy - _panStartY!;
                          final xShift = -dx / size.width * anchorXRange;
                          final yShift = dy / size.height * anchorYRange;

                          if (d.scale != 1.0) {
                            // Simultaneous pan + zoom
                            final focalX = _panAnchorXMin + xShift + (d.localFocalPoint.dx / size.width) * anchorXRange;
                            final focalY = _panAnchorYMax + yShift - (d.localFocalPoint.dy / size.height) * anchorYRange;
                            final factor = 1 / d.scale;
                            final panXMin = _panAnchorXMin + xShift;
                            final panXMax = _panAnchorXMax + xShift;
                            final panYMin = _panAnchorYMin + yShift;
                            final panYMax = _panAnchorYMax + yShift;
                            setState(() {
                              _xMin = focalX - (focalX - panXMin) * factor;
                              _xMax = focalX + (panXMax - focalX) * factor;
                              _yMin = focalY - (focalY - panYMin) * factor;
                              _yMax = focalY + (panYMax - focalY) * factor;
                              _clampViewport();
                            });
                          } else {
                            setState(() {
                              _xMin = _panAnchorXMin + xShift;
                              _xMax = _panAnchorXMax + xShift;
                              _yMin = _panAnchorYMin + yShift;
                              _yMax = _panAnchorYMax + yShift;
                            });
                          }
                          _resampleDebounced();
                        },
                        onScaleEnd: (d) {
                          final wasPinching = _isPinching;
                          _panStartX = null;
                          _panStartY = null;
                          _isPinching = false;

                          // Fling momentum (only for single-finger pan, not pinch)
                          if (!wasPinching && _flingVelocity.distance > 200) {
                            _isFlingRunning = true;
                            var vx = _flingVelocity.dx;
                            var vy = _flingVelocity.dy;
                            void _flingTick() {
                              if (!mounted || !_isFlingRunning) return;
                              if (vx.abs() < 5 && vy.abs() < 5) {
                                _isFlingRunning = false;
                                return;
                              }
                              final size = context.size;
                              if (size == null) return;
                              // Decelerate
                              vx *= 0.92;
                              vy *= 0.92;
                              final xRange = _xMax - _xMin;
                              final yRange = _yMax - _yMin;
                              final dxShift = -vx / size.width * xRange * 0.016; // ~60fps
                              final dyShift = vy / size.height * yRange * 0.016;
                              setState(() {
                                _xMin += dxShift;
                                _xMax += dxShift;
                                _yMin += dyShift;
                                _yMax += dyShift;
                              });
                              _resampleDebounced();
                              WidgetsBinding.instance.addPostFrameCallback((_) => _flingTick());
                            }
                            WidgetsBinding.instance.addPostFrameCallback((_) => _flingTick());
                          }
                        },
                        onLongPressStart: (d) {
                          HapticFeedback.selectionClick();
                          _updateCrosshair(d.localPosition);
                          setState(() => _isTouching = true);
                        },
                        onLongPressMoveUpdate: (d) => _updateCrosshair(d.localPosition),
                        onLongPressEnd: (_) {
                          setState(() {
                            _isTouching = false;
                            _crosshair = null;
                            _crosshairSnapLabel = null;
                            _crosshairAnim.reset();
                          });
                        },
                        child: CustomPaint(
                          painter: FunctionGraphPainter(
                            points: _points,
                            derivativePoints: _showDerivative || _showCriticalPoints || _showMonotonicity
                                ? _derivativePoints
                                : null,
                            xMin: _xMin,
                            xMax: _xMax,
                            yMin: _yMin,
                            yMax: _yMax,
                            showGrid: _showGrid,
                            showMinorGrid: _showMinorGrid,
                            showAxes: _showAxes,
                            showDerivative: _showDerivative,
                            showArea: _showArea,
                            areaMode: _areaMode,
                            crosshair: _crosshair,
                            curveColor: widget.curveColor,
                            useGradient: _useGradient,
                            showRoots: _showRoots,
                            showCriticalPoints: _showCriticalPoints,
                            showAsymptotes: _showAsymptotes,
                            integralValue: _integralValue,
                            curveProgress: Curves.easeOut.transform(
                              _curveAnim.value.clamp(0.0, 1.0),
                            ),
                            crosshairSnapLabel: _crosshairSnapLabel,
                            tangentSlope: _tangentSlope,
                            inflectionPoints: _showInflection ? _inflectionPoints : null,
                            showMonotonicity: _showMonotonicity,
                            isDark: isDark,
                            showLegend: _showLegend,
                            crosshairOpacity: _crosshairAnim.value,
                            extraPoints: [
                              for (int i = 0; i < _extraPoints.length; i++)
                                if (!_hiddenFunctions.contains(i + 1)) _extraPoints[i],
                            ],
                            extraColors: [
                              for (int i = 0; i < _extraPoints.length; i++)
                                if (!_hiddenFunctions.contains(i + 1))
                                  i < _extraPalette.length ? _extraPalette[i] : Colors.grey,
                            ],
                            functionLabels: _functions,
                            extraCrosshairYs: _crosshair != null ? _extraCrosshairYs : const [],
                            intersectionPoints: _intersectionPts,
                          ),
                          size: Size.infinite,
                        ),
                      ),

                      // Floating zoom controls (left)
                      Positioned(
                        left: 8,
                        bottom: 8,
                        child: GraphZoomControls(
                          onZoomIn: _zoomIn,
                          onZoomOut: _zoomOut,
                          onAutoFit: _autoFit,
                          onReset: _resetView,
                        ),
                      ),

                      // Info badges (top-right) — tappable to edit coordinates
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            GraphInfoBadge(
                              icon: Icons.zoom_in_rounded,
                              label: '$zoomLevel%',
                            ),
                            const SizedBox(height: 4),
                            GestureDetector(
                              onTap: () {
                                final xMinC = TextEditingController(text: _xMin.toStringAsFixed(1));
                                final xMaxC = TextEditingController(text: _xMax.toStringAsFixed(1));
                                final yMinC = TextEditingController(text: _yMin.toStringAsFixed(1));
                                final yMaxC = TextEditingController(text: _yMax.toStringAsFixed(1));
                                showDialog(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Coordinate Viewport', style: TextStyle(fontSize: 16)),
                                    content: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Row(
                                          children: [
                                            const SizedBox(width: 24, child: Text('x', style: TextStyle(fontWeight: FontWeight.w700, fontFamily: 'serif', fontStyle: FontStyle.italic))),
                                            Expanded(child: TextField(controller: xMinC, decoration: const InputDecoration(labelText: 'Min', isDense: true), keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true))),
                                            const SizedBox(width: 12),
                                            Expanded(child: TextField(controller: xMaxC, decoration: const InputDecoration(labelText: 'Max', isDense: true), keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true))),
                                          ],
                                        ),
                                        const SizedBox(height: 12),
                                        Row(
                                          children: [
                                            const SizedBox(width: 24, child: Text('y', style: TextStyle(fontWeight: FontWeight.w700, fontFamily: 'serif', fontStyle: FontStyle.italic))),
                                            Expanded(child: TextField(controller: yMinC, decoration: const InputDecoration(labelText: 'Min', isDense: true), keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true))),
                                            const SizedBox(width: 12),
                                            Expanded(child: TextField(controller: yMaxC, decoration: const InputDecoration(labelText: 'Max', isDense: true), keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true))),
                                          ],
                                        ),
                                      ],
                                    ),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annulla')),
                                      FilledButton(
                                        onPressed: () {
                                          final x0 = double.tryParse(xMinC.text);
                                          final x1 = double.tryParse(xMaxC.text);
                                          final y0 = double.tryParse(yMinC.text);
                                          final y1 = double.tryParse(yMaxC.text);
                                          if (x0 != null && x1 != null && y0 != null && y1 != null && x0 < x1 && y0 < y1) {
                                            setState(() {
                                              _xMin = x0; _xMax = x1;
                                              _yMin = y0; _yMax = y1;
                                            });
                                            _resample();
                                          }
                                          Navigator.pop(ctx);
                                        },
                                        child: const Text('OK'),
                                      ),
                                    ],
                                  ),
                                );
                                HapticFeedback.selectionClick();
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: cs.surfaceContainerHighest.withValues(alpha: 0.85),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.straighten_rounded, size: 12, color: cs.onSurfaceVariant),
                                    const SizedBox(width: 4),
                                    Text(
                                      'x∈[${_xMin.toStringAsFixed(1)}, ${_xMax.toStringAsFixed(1)}]',
                                      style: TextStyle(fontSize: 10, fontFamily: 'monospace', color: cs.onSurfaceVariant),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(Icons.edit, size: 10, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Crosshair tooltip
                      if (_crosshair != null)
                        Positioned(
                          top: 8,
                          left: 8,
                          child: GraphValueTooltip(
                            x: _crosshair!.dx,
                            y: _crosshair!.dy,
                            extraValues: [
                              for (int i = 0; i < _extraCrosshairYs.length; i++)
                                (
                                  i < _extraPalette.length ? _extraPalette[i] : Colors.grey,
                                  _extraCrosshairYs[i],
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── M3 Tabbed toolbar ──
          _buildM3Toolbar(cs, isDark),
        ],
      ),
    );
  }

  Widget _buildM3Toolbar(ColorScheme cs, bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.2),
          width: 0.5,
        ),
      ),
      child: Column(
        children: [
          // Tab bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GraphToolbarTab(
                  icon: Icons.insights_rounded,
                  label: 'Analisi',
                  selected: _selectedTab == 0,
                  onTap: () => setState(() => _selectedTab = 0),
                ),
                const SizedBox(width: 4),
                GraphToolbarTab(
                  icon: Icons.palette_rounded,
                  label: 'Display',
                  selected: _selectedTab == 1,
                  onTap: () => setState(() => _selectedTab = 1),
                ),
                const SizedBox(width: 4),
                GraphToolbarTab(
                  icon: Icons.build_rounded,
                  label: 'Strumenti',
                  selected: _selectedTab == 2,
                  onTap: () => setState(() => _selectedTab = 2),
                ),
              ],
            ),
          ),

          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.15)),

          // Tab content
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: Padding(
              key: ValueKey(_selectedTab),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: _buildTabContent(cs),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabContent(ColorScheme cs) {
    switch (_selectedTab) {
      case 0: // Analisi
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // E1: Function visibility toggles (only show when multi-function)
            if (_functions.length > 1) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(Icons.visibility_rounded, size: 14, color: cs.primary),
                    const SizedBox(width: 4),
                    Text(
                      'Funzioni',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cs.primary,
                      ),
                    ),
                  ],
                ),
              ),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (int i = 0; i < _functions.length; i++)
                    _m3Toggle(
                      cs,
                      Icons.show_chart_rounded,
                      'f${_subscriptLabel(i + 1)}',
                      !_hiddenFunctions.contains(i),
                      () {
                        setState(() {
                          if (_hiddenFunctions.contains(i)) {
                            _hiddenFunctions.remove(i);
                          } else {
                            _hiddenFunctions.add(i);
                          }
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _m3Toggle(cs, Icons.show_chart_rounded, "f'(x)", _showDerivative, () {
                  setState(() => _showDerivative = !_showDerivative);
                  _resample();
                }),
                _m3Toggle(cs, Icons.area_chart_rounded, _showArea ? (_areaMode == 0 ? 'Area ∫' : 'Area ▼') : 'Area', _showArea, () {
                  setState(() {
                    if (!_showArea) {
                      _showArea = true;
                      _areaMode = 0;
                    } else if (_areaMode == 0) {
                      _areaMode = 1;
                    } else {
                      _showArea = false;
                      _areaMode = 0;
                    }
                  });
                  _resample();
                }),
                _m3Toggle(cs, Icons.radio_button_checked_rounded, 'Radici', _showRoots, () {
                  setState(() => _showRoots = !_showRoots);
                }),
                _m3Toggle(cs, Icons.star_rounded, 'Min/Max', _showCriticalPoints, () {
                  setState(() => _showCriticalPoints = !_showCriticalPoints);
                  if (_showCriticalPoints) _resample();
                }),
                _m3Toggle(cs, Icons.vertical_align_center_rounded, 'Asintoti', _showAsymptotes, () {
                  setState(() => _showAsymptotes = !_showAsymptotes);
                }),
                _m3Toggle(cs, Icons.change_history_rounded, 'Flessi', _showInflection, () {
                  setState(() => _showInflection = !_showInflection);
                  if (_showInflection) _resample();
                }),
                _m3Toggle(cs, Icons.trending_up_rounded, '↑↓ Colore', _showMonotonicity, () {
                  setState(() => _showMonotonicity = !_showMonotonicity);
                  if (_showMonotonicity) _resample();
                }),
              ],
            ),
          ],
        );
      case 1: // Display
        return Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            _m3Toggle(cs, Icons.grid_on_rounded, 'Griglia', _showGrid, () {
              setState(() => _showGrid = !_showGrid);
            }),
            _m3Toggle(cs, Icons.grid_4x4_rounded, 'Minore', _showMinorGrid, () {
              setState(() => _showMinorGrid = !_showMinorGrid);
            }),
            _m3Toggle(cs, Icons.straighten_rounded, 'Assi', _showAxes, () {
              setState(() => _showAxes = !_showAxes);
            }),
            _m3Toggle(cs, Icons.gradient_rounded, 'Gradiente', _useGradient, () {
              setState(() => _useGradient = !_useGradient);
            }),
            _m3Toggle(cs, Icons.list_alt_rounded, 'Legenda', _showLegend, () {
              setState(() => _showLegend = !_showLegend);
            }),
          ],
        );
      case 2: // Strumenti
        // Build formula string
        final kStr = _coeffK == 1.0 ? '' : '${_coeffK.toStringAsFixed(1)}·';
        final dStr = _offsetD == 0.0 ? '' : (_offsetD > 0 ? ' + ${_offsetD.toStringAsFixed(1)}' : ' − ${(-_offsetD).toStringAsFixed(1)}');
        final formulaStr = '${kStr}f(x)$dStr';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with formula badge
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Icon(Icons.straighten_rounded, size: 14, color: cs.primary),
                  const SizedBox(width: 4),
                  Text(
                    'Trasformazione',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cs.primary,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      formulaStr.isEmpty ? 'f(x)' : formulaStr,
                      style: TextStyle(
                        fontSize: 10,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // K slider (coefficient) with double-tap reset
            GestureDetector(
              onDoubleTap: () {
                HapticFeedback.mediumImpact();
                setState(() {
                  _coeffK = 1.0;
                  _lastSnapK = 1.0;
                });
                _resample();
              },
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: Text(
                      'k',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        fontStyle: FontStyle.italic,
                        color: cs.primary,
                        fontFamily: 'serif',
                      ),
                    ),
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                        activeTrackColor: cs.primary,
                        inactiveTrackColor: cs.surfaceContainerHighest,
                        thumbColor: cs.primary,
                        overlayColor: cs.primary.withValues(alpha: 0.12),
                      ),
                      child: Slider(
                        value: _coeffK.clamp(-5.0, 5.0),
                        min: -5,
                        max: 5,
                        onChanged: (v) {
                          final rounded = double.parse(v.toStringAsFixed(2));
                          // Snap haptic on integer crossing
                          final nearInt = rounded.roundToDouble();
                          if ((rounded - nearInt).abs() < 0.08 && _lastSnapK != nearInt) {
                            HapticFeedback.lightImpact();
                            _lastSnapK = nearInt;
                          }
                          setState(() => _coeffK = rounded);
                          _resample();
                        },
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 38,
                    child: Text(
                      _coeffK.toStringAsFixed(1),
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: cs.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
            ),

            // D slider (vertical offset) with double-tap reset
            GestureDetector(
              onDoubleTap: () {
                HapticFeedback.mediumImpact();
                setState(() {
                  _offsetD = 0.0;
                  _lastSnapD = 0.0;
                });
                _resample();
              },
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: Text(
                      'd',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        fontStyle: FontStyle.italic,
                        color: cs.secondary,
                        fontFamily: 'serif',
                      ),
                    ),
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                        activeTrackColor: cs.secondary,
                        inactiveTrackColor: cs.surfaceContainerHighest,
                        thumbColor: cs.secondary,
                        overlayColor: cs.secondary.withValues(alpha: 0.12),
                      ),
                      child: Slider(
                        value: _offsetD.clamp(-10.0, 10.0),
                        min: -10,
                        max: 10,
                        onChanged: (v) {
                          final rounded = double.parse(v.toStringAsFixed(2));
                          final nearInt = rounded.roundToDouble();
                          if ((rounded - nearInt).abs() < 0.15 && _lastSnapD != nearInt) {
                            HapticFeedback.lightImpact();
                            _lastSnapD = nearInt;
                          }
                          setState(() => _offsetD = rounded);
                          _resample();
                        },
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 38,
                    child: Text(
                      _offsetD.toStringAsFixed(1),
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: cs.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
            ),

            // Parameter sliders (only when non-x params detected)
            if (_detectedParams.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 4),
                child: Row(
                  children: [
                    Icon(Icons.tune_rounded, size: 14, color: cs.tertiary),
                    const SizedBox(width: 4),
                    Text(
                      'Parametri',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cs.tertiary,
                      ),
                    ),
                  ],
                ),
              ),
              ..._detectedParams.map((param) {
                final value = _paramValues[param] ?? 1.0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 24,
                        child: Text(
                          param,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            fontStyle: FontStyle.italic,
                            color: cs.tertiary,
                            fontFamily: 'serif',
                          ),
                        ),
                      ),
                      Expanded(
                        child: SliderTheme(
                          data: SliderThemeData(
                            trackHeight: 3,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                            activeTrackColor: cs.tertiary,
                            inactiveTrackColor: cs.surfaceContainerHighest,
                            thumbColor: cs.tertiary,
                            overlayColor: cs.tertiary.withValues(alpha: 0.12),
                          ),
                          child: Slider(
                            value: value.clamp(-10.0, 10.0),
                            min: -10,
                            max: 10,
                            onChanged: (v) {
                              setState(() {
                                _paramValues[param] = double.parse(v.toStringAsFixed(2));
                              });
                              _resample();
                            },
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 38,
                        child: Text(
                          value.toStringAsFixed(1),
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: cs.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.end,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
            const SizedBox(height: 4),
            // Tools
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (widget.onInsertToCanvas != null) ...[
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.add_to_photos_rounded),
                      label: const Text('Inserisci nel Canvas'),
                      style: FilledButton.styleFrom(
                        backgroundColor: widget.curveColor,
                        foregroundColor: widget.curveColor.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      onPressed: () {
                        widget.onInsertToCanvas!(
                          widget.latexSource,
                          _xMin, _xMax, _yMin, _yMax,
                          widget.curveColor.toARGB32(),
                        );
                        Navigator.of(context).pop();
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                _m3Action(cs, Icons.table_chart_rounded, 'Tabella', _showValueTable),
                _m3Action(cs, Icons.camera_alt_rounded, 'Screenshot', _exportScreenshot),
                _m3Action(cs, Icons.share_rounded, 'Report', _shareReport),
              ],
            ),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  /// Helper for subscript labels
  static String _subscriptLabel(int n) {
    const subs = '₀₁₂₃₄₅₆₇₈₉';
    return String.fromCharCodes(
      n.toString().codeUnits.map((c) => subs.codeUnitAt(c - 48)),
    );
  }

  Widget _m3Toggle(ColorScheme cs, IconData icon, String label, bool active, VoidCallback onTap) {
    return FilterChip(
      avatar: Icon(icon, size: 16, color: active ? cs.onSecondaryContainer : cs.onSurfaceVariant),
      label: Text(label),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: active ? FontWeight.w600 : FontWeight.w400,
        color: active ? cs.onSecondaryContainer : cs.onSurfaceVariant,
      ),
      selected: active,
      selectedColor: cs.secondaryContainer,
      checkmarkColor: cs.onSecondaryContainer,
      side: BorderSide(
        color: active ? Colors.transparent : cs.outlineVariant,
        width: 0.5,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      showCheckmark: false,
      onSelected: (_) {
        HapticFeedback.selectionClick();
        onTap();
      },
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Widget _m3Action(ColorScheme cs, IconData icon, String label, VoidCallback onTap) {
    return ActionChip(
      avatar: Icon(icon, size: 16, color: cs.primary),
      label: Text(label),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: cs.onSurface,
      ),
      side: BorderSide(color: cs.outlineVariant, width: 0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onPressed: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

