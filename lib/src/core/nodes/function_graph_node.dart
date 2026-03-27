import 'dart:ui';
import '../scene_graph/canvas_node.dart';
import '../scene_graph/node_id.dart';
import '../scene_graph/node_visitor.dart';
import '../../utils/uid.dart';
import '../../core/latex/latex_evaluator.dart';

/// 📈 Scene graph node for live function graphs on the canvas.
///
/// Stores the LaTeX function expression(s), viewport range, and display
/// options. The rendering pipeline uses [FunctionGraphPainter] to draw
/// the graph directly on the Canvas.
///
/// Follows the same pattern as [LatexNode].
class FunctionGraphNode extends CanvasNode {
  // ---------------------------------------------------------------------------
  // Fields
  // ---------------------------------------------------------------------------

  /// LaTeX source for function(s), semicolon-separated for multi-function.
  String latexSource;

  /// Canvas-space dimensions.
  double graphWidth;
  double graphHeight;

  /// Viewport range.
  double xMin;
  double xMax;
  double yMin;
  double yMax;

  /// Primary curve color (ARGB).
  int curveColorValue;

  /// Display toggles.
  bool showGrid;
  bool showAxes;
  bool showDerivative;
  bool showRoots;
  bool showArea;
  bool showCriticalPoints;
  bool showAsymptotes;
  bool showInflection;
  bool showLegend;

  // ---------------------------------------------------------------------------
  // Cached sample data (not serialized, computed on demand)
  // ---------------------------------------------------------------------------

  /// Cached primary function points.
  List<Offset>? _cachedPoints;

  /// Cached derivative points.
  List<Offset>? _cachedDerivativePoints;

  /// Cached extra function points.
  List<List<Offset>>? _cachedExtraPoints;

  /// Cached intersection points.
  List<Offset>? _cachedIntersections;

  /// Hash of the state that produced the cache.
  int _cacheHash = 0;

  /// Trace cursor x position (non-serialized, set during drag)
  double? traceX;

  /// Transformation coefficients: y = coeffK · f(x) + offsetD
  double coeffK = 1.0;
  double offsetD = 0.0;

  /// Slider parameters: variable name → current value.
  /// e.g. {'a': 2.0, 'k': 0.5} for f(x) = a*x^2 + k
  Map<String, double> parameters = {};

  /// Custom slider ranges per parameter. Default is [-10, 10].
  Map<String, (double, double)> paramRanges = {};

  /// Parameters currently being auto-animated (oscillating).
  Set<String> animatingParams = {};

  /// Known math function names to exclude from parameter detection.
  static final _mathFunctions = {
    'sin', 'cos', 'tan', 'log', 'ln', 'exp', 'sqrt', 'abs',
    'asin', 'acos', 'atan', 'sec', 'csc', 'cot', 'pi', 'e',
    'sinh', 'cosh', 'tanh', 'sgn', 'max', 'min', 'mod',
  };

  /// Detect single-letter parameters (not x) from the latex source.
  List<String> get detectedParams {
    final found = <String>{};
    // Match single letters that aren't part of function names
    final re = RegExp(r'\b([a-wyzA-WYZ])\b');
    // Remove function names first
    var cleaned = latexSource;
    for (final fn in _mathFunctions) {
      cleaned = cleaned.replaceAll(fn, '');
    }
    for (final m in re.allMatches(cleaned)) {
      final letter = m.group(1)!;
      if (!_mathFunctions.contains(letter)) {
        found.add(letter);
      }
    }
    return found.toList()..sort();
  }

  /// Build the variables map for evaluation (x + parameters).
  Map<String, double> _varsFor(double x) => {'x': x, ...parameters};

  /// Evaluate f(x) at a given x value using the primary function.
  /// Returns null if evaluation fails.
  double? evaluateAt(double x) {
    final fns = functions;
    if (fns.isEmpty) return null;
    // Auto-initialize detected params (may be called before ensureSampled)
    for (final p in detectedParams) {
      parameters.putIfAbsent(p, () => 1.0);
    }
    try {
      final raw = LatexEvaluator.evaluateWith(fns.first, _varsFor(x));
      return coeffK * raw + offsetD;
    } catch (_) {
      return null;
    }
  }

  static const int _sampleCount = 300;
  static const extraPalette = [
    Color(0xFFEA4335),
    Color(0xFF34A853),
    Color(0xFFFF6D01),
    Color(0xFF9334E6),
    Color(0xFF00ACC1),
  ];

  // ---------------------------------------------------------------------------
  // Constructor
  // ---------------------------------------------------------------------------

  FunctionGraphNode({
    required super.id,
    required this.latexSource,
    this.graphWidth = 400.0,
    this.graphHeight = 300.0,
    this.xMin = -10.0,
    this.xMax = 10.0,
    this.yMin = -6.0,
    this.yMax = 6.0,
    this.curveColorValue = 0xFF4285F4,
    this.showGrid = true,
    this.showAxes = true,
    this.showDerivative = false,
    this.showRoots = false,
    this.showArea = false,
    this.showCriticalPoints = false,
    this.showAsymptotes = false,
    this.showInflection = false,
    this.showLegend = false,
    super.name = '',
    super.localTransform,
    super.opacity,
    super.blendMode,
    super.isVisible,
    super.isLocked,
  });

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Color get curveColor => Color(curveColorValue);

  /// Compute a hash of the state that affects sampling.
  int get _stateHash =>
      Object.hash(latexSource, xMin, xMax, yMin, yMax, graphWidth, graphHeight,
          showDerivative, curveColorValue, coeffK, offsetD, Object.hashAll(parameters.values));

  /// Get the parsed function list.
  List<String> get functions =>
      latexSource.split(';').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

  /// Ensure cached points are up-to-date.
  void ensureSampled() {
    final h = _stateHash;
    if (_cachedPoints != null && _cacheHash == h) return;
    _cacheHash = h;
    // Auto-initialize detected parameters with default value 1.0
    for (final p in detectedParams) {
      parameters.putIfAbsent(p, () => 1.0);
    }
    _resample();
  }

  void _resample() {
    final fns = functions;
    if (fns.isEmpty) {
      _cachedPoints = const [];
      _cachedExtraPoints = const [];
      _cachedDerivativePoints = null;
      _cachedIntersections = const [];
      return;
    }

    final step = (xMax - xMin) / _sampleCount;

    // Primary — adaptive sampling: base 300 points + refinement near discontinuities
    final pts = <Offset>[];
    for (int i = 0; i <= _sampleCount; i++) {
      final x = xMin + step * i;
      try {
        final raw = LatexEvaluator.evaluateWith(fns.first, _varsFor(x));
        pts.add(Offset(x, coeffK * raw + offsetD));
      } catch (_) {
        pts.add(Offset(x, double.nan));
      }
    }
    // Adaptive refinement: add extra points in high-curvature/discontinuity regions
    final refined = <Offset>[];
    for (int i = 0; i < pts.length; i++) {
      refined.add(pts[i]);
      if (i < pts.length - 1) {
        final a = pts[i], b = pts[i + 1];
        final needsRefinement = !a.dy.isFinite || !b.dy.isFinite ||
            (a.dy.isFinite && b.dy.isFinite && (b.dy - a.dy).abs() > (yMax - yMin) * 0.5);
        if (needsRefinement) {
          // Bisect: add midpoint and quarter points for smooth transition
          final midX = (a.dx + b.dx) / 2;
          final q1X = (a.dx + midX) / 2;
          final q3X = (midX + b.dx) / 2;
          for (final rx in [q1X, midX, q3X]) {
            try {
              final ry = LatexEvaluator.evaluateWith(fns.first, _varsFor(rx));
              refined.add(Offset(rx, ry));
            } catch (_) {
              refined.add(Offset(rx, double.nan));
            }
          }
        }
      }
    }
    _cachedPoints = refined;

    // Derivative
    if (showDerivative) {
      final dpts = <Offset>[];
      for (int i = 0; i <= _sampleCount; i++) {
        final x = xMin + step * i;
        const h = 0.001;
        try {
          final yp = LatexEvaluator.evaluateWith(fns.first, _varsFor(x + h));
          final ym = LatexEvaluator.evaluateWith(fns.first, _varsFor(x - h));
          dpts.add(Offset(x, (yp - ym) / (2 * h)));
        } catch (_) {
          dpts.add(Offset(x, double.nan));
        }
      }
      _cachedDerivativePoints = dpts;
    } else {
      _cachedDerivativePoints = null;
    }

    // Extra functions
    final extras = <List<Offset>>[];
    for (int fi = 1; fi < fns.length; fi++) {
      final ep = <Offset>[];
      for (int i = 0; i <= _sampleCount; i++) {
        final x = xMin + step * i;
        try {
          final y = LatexEvaluator.evaluateWith(fns[fi], _varsFor(x));
          ep.add(Offset(x, y));
        } catch (_) {
          ep.add(Offset(x, double.nan));
        }
      }
      extras.add(ep);
    }
    _cachedExtraPoints = extras;

    // Intersections
    final ints = <Offset>[];
    for (final ep in extras) {
      for (int i = 0; i < pts.length - 1 && i < ep.length - 1; i++) {
        final a1 = pts[i].dy, b1 = pts[i + 1].dy;
        final a2 = ep[i].dy, b2 = ep[i + 1].dy;
        if (!a1.isFinite || !b1.isFinite || !a2.isFinite || !b2.isFinite) continue;
        final d1 = a1 - a2, d2 = b1 - b2;
        if ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) {
          final t = d1 / (d1 - d2);
          ints.add(Offset(
            pts[i].dx + t * (pts[i + 1].dx - pts[i].dx),
            a1 + t * (b1 - a1),
          ));
        }
      }
    }
    _cachedIntersections = ints;
  }

  /// Invalidate cache (call after changing latexSource or viewport).
  void invalidateCache() {
    _cachedPoints = null;
    _cachedExtraPoints = null;
    _cachedDerivativePoints = null;
    _cachedIntersections = null;
    _cacheHash = 0;
  }

  /// Access cached data (call ensureSampled() first).
  List<Offset> get cachedPoints => _cachedPoints ?? const [];
  List<Offset>? get cachedDerivativePoints => _cachedDerivativePoints;
  List<List<Offset>> get cachedExtraPoints => _cachedExtraPoints ?? const [];
  List<Offset> get cachedIntersections => _cachedIntersections ?? const [];

  // ---------------------------------------------------------------------------
  // Bounds
  // ---------------------------------------------------------------------------

  @override
  Rect get localBounds => Rect.fromLTWH(0, 0, graphWidth, graphHeight);

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  @override
  Map<String, dynamic> toJson() {
    final json = baseToJson();
    json['nodeType'] = 'functionGraph';
    json['latexSource'] = latexSource;
    json['graphWidth'] = graphWidth;
    json['graphHeight'] = graphHeight;
    json['xMin'] = xMin;
    json['xMax'] = xMax;
    json['yMin'] = yMin;
    json['yMax'] = yMax;
    json['curveColor'] = curveColorValue;
    if (showGrid) json['showGrid'] = true;
    if (showAxes) json['showAxes'] = true;
    if (showDerivative) json['showDerivative'] = true;
    if (showRoots) json['showRoots'] = true;
    if (showArea) json['showArea'] = true;
    if (showCriticalPoints) json['showCriticalPoints'] = true;
    if (showAsymptotes) json['showAsymptotes'] = true;
    if (showInflection) json['showInflection'] = true;
    if (showLegend) json['showLegend'] = true;
    return json;
  }

  factory FunctionGraphNode.fromJson(Map<String, dynamic> json) {
    final node = FunctionGraphNode(
      id: NodeId(json['id'] as String),
      latexSource: json['latexSource'] as String? ?? '',
      graphWidth: (json['graphWidth'] as num?)?.toDouble() ?? 400.0,
      graphHeight: (json['graphHeight'] as num?)?.toDouble() ?? 300.0,
      xMin: (json['xMin'] as num?)?.toDouble() ?? -10.0,
      xMax: (json['xMax'] as num?)?.toDouble() ?? 10.0,
      yMin: (json['yMin'] as num?)?.toDouble() ?? -6.0,
      yMax: (json['yMax'] as num?)?.toDouble() ?? 6.0,
      curveColorValue: json['curveColor'] as int? ?? 0xFF4285F4,
      showGrid: json['showGrid'] as bool? ?? true,
      showAxes: json['showAxes'] as bool? ?? true,
      showDerivative: json['showDerivative'] as bool? ?? false,
      showRoots: json['showRoots'] as bool? ?? false,
      showArea: json['showArea'] as bool? ?? false,
      showCriticalPoints: json['showCriticalPoints'] as bool? ?? false,
      showAsymptotes: json['showAsymptotes'] as bool? ?? false,
      showInflection: json['showInflection'] as bool? ?? false,
      showLegend: json['showLegend'] as bool? ?? false,
    );
    CanvasNode.applyBaseFromJson(node, json);
    return node;
  }

  // ---------------------------------------------------------------------------
  // Clone
  // ---------------------------------------------------------------------------

  @override
  CanvasNode cloneInternal() {
    final cloned = FunctionGraphNode(
      id: NodeId(generateUid()),
      latexSource: latexSource,
      graphWidth: graphWidth,
      graphHeight: graphHeight,
      xMin: xMin,
      xMax: xMax,
      yMin: yMin,
      yMax: yMax,
      curveColorValue: curveColorValue,
      showGrid: showGrid,
      showAxes: showAxes,
      showDerivative: showDerivative,
      showRoots: showRoots,
      showArea: showArea,
      showCriticalPoints: showCriticalPoints,
      showAsymptotes: showAsymptotes,
      showInflection: showInflection,
      showLegend: showLegend,
      name: name,
    );
    cloned.opacity = opacity;
    cloned.blendMode = blendMode;
    cloned.isVisible = isVisible;
    cloned.isLocked = isLocked;
    cloned.localTransform = localTransform.clone();
    return cloned;
  }

  // ---------------------------------------------------------------------------
  // Visitor
  // ---------------------------------------------------------------------------

  @override
  R accept<R>(NodeVisitor<R> visitor) => visitor.visitFunctionGraph(this);

  @override
  String toString() {
    final preview = latexSource.length > 30
        ? '${latexSource.substring(0, 30)}...'
        : latexSource;
    return 'FunctionGraphNode(id: $id, source: "$preview", ${graphWidth}x$graphHeight)';
  }
}
