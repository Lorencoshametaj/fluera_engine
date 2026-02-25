/// 🌱 ORGANIC BEHAVIOR ENGINE — L2 Adaptive Intelligence Subsystem.
///
/// Coordinates all emergent organicity across the engine:
/// - Biological micro-variation (tremor, fatigue, breathing)
/// - Physics ink simulation
/// - Elastic stabilization
/// - Fractal noise grain
///
/// Context-dependent intensity:
/// - Drawing mode → full organicity
/// - Selection/shape mode → zero organicity
/// - PDF document → zero organicity
/// - High zoom → detail visible → full
/// - Very low zoom → invisible detail → reduce for performance
///
/// ## Usage
///
/// ```dart
/// // Access global intensity from anywhere (static, zero-cost)
/// final amp = OrganicBehaviorEngine.intensity;
/// if (amp > 0) {
///   // Apply organic modulation
/// }
/// ```
library;

import '../core/conscious_architecture.dart';

/// L2 Intelligence: organic behavior coordination.
///
/// This subsystem is the central brain for emergent organicity.
/// It exposes a single [intensity] value (0.0–1.0) that all organic
/// modulations read. This prevents subsystems from independently
/// adding organicity in ways that compound unnaturally.
class OrganicBehaviorEngine extends IntelligenceSubsystem {
  // ─── Static access (zero-cost from hot path) ───────────────────────

  static OrganicBehaviorEngine? _instance;

  /// Current organic intensity (0.0–1.0).
  ///
  /// Read this from any hot path — it's a simple field access.
  /// Returns 0.0 if the engine is not registered.
  static double get intensity => _instance?._intensity ?? 0.0;

  /// Whether tremor modulation is active.
  static bool get tremorEnabled =>
      _instance != null && _instance!._intensity > 0 && _instance!._tremorOn;

  /// Whether physics ink simulation is active.
  static bool get physicsInkEnabled =>
      _instance != null &&
      _instance!._intensity > 0 &&
      _instance!._physicsInkOn;

  /// Whether elastic stabilizer is active.
  static bool get elasticStabilizerEnabled =>
      _instance != null &&
      _instance!._intensity > 0 &&
      _instance!._elasticStabOn;

  // ─── Instance state ────────────────────────────────────────────────

  double _intensity = 0.0;
  bool _tremorOn = true;
  bool _physicsInkOn = true;
  bool _elasticStabOn = true;
  bool _isActive = true;

  // 🌱 Stroke-pattern adaptive intensity
  // Tracks stroke lengths to detect annotation vs. sketching patterns.
  static const int _patternWindowSize = 10;
  final List<int> _recentStrokeLengths = [];
  double _adaptiveMultiplier = 1.0;

  /// Adaptive multiplier based on stroke patterns (0.3–1.0).
  /// Annotation mode (many short strokes) → reduced.
  /// Sketching mode (long flowing strokes) → full intensity.
  static double get adaptiveMultiplier => _instance?._adaptiveMultiplier ?? 1.0;

  OrganicBehaviorEngine() {
    _instance = this;
  }

  // ─── IntelligenceSubsystem contract ─────────────────────────────────

  @override
  IntelligenceLayer get layer => IntelligenceLayer.adaptive;

  @override
  String get name => 'OrganicBehaviorEngine';

  @override
  bool get isActive => _isActive;

  @override
  void onContextChanged(EngineContext context) {
    // ── Tool-based gating ──
    final tool = context.activeTool ?? '';
    final isDrawingTool = const {
      'pen',
      'pencil',
      'fountain',
      'highlighter',
      'brush',
      'marker',
      'charcoal',
      'watercolor',
      'eraser',
    }.contains(tool);

    // Drawing tools → full organicity, everything else → zero
    if (!isDrawingTool && !context.isDrawing) {
      _intensity = 0.0;
      return;
    }

    // ── PDF documents → zero (no strokes) ──
    if (context.isPdfDocument) {
      _intensity = 0.0;
      return;
    }

    // ── Zoom-based scaling ──
    // At zoom < 0.3, organic detail is invisible → reduce to save perf.
    // At zoom 0.3–1.0 → linear ramp.
    // At zoom > 1.0 → full intensity (detail is magnified).
    final zoom = context.zoom;
    double zoomFactor;
    if (zoom >= 1.0) {
      zoomFactor = 1.0;
    } else if (zoom >= 0.3) {
      zoomFactor = (zoom - 0.3) / 0.7; // 0.3→0, 1.0→1
    } else {
      zoomFactor = 0.0;
    }

    // ── Active drawing boost ──
    // While actively drawing, always full intensity regardless of zoom
    // (the user sees the pen tip at full detail).
    if (context.isDrawing) {
      zoomFactor = 1.0;
    }

    _intensity = zoomFactor.clamp(0.0, 1.0);
  }

  @override
  void onIdle(Duration idleDuration) {
    // After 5s idle, decay adaptive multiplier toward 1.0 (reset pattern)
    if (idleDuration.inSeconds >= 5) {
      _adaptiveMultiplier =
          _adaptiveMultiplier + (1.0 - _adaptiveMultiplier) * 0.3;
    }
  }

  /// 🌱 Record a completed stroke for pattern analysis.
  ///
  /// Call this from endStroke() so the engine learns whether
  /// the user is annotating (short strokes) or sketching (long strokes).
  void recordStroke(int pointCount) {
    _recentStrokeLengths.add(pointCount);
    if (_recentStrokeLengths.length > _patternWindowSize) {
      _recentStrokeLengths.removeAt(0);
    }
    _updateAdaptiveMultiplier();
  }

  /// Static convenience for callers that don't have the instance.
  static void notifyStrokeCompleted(int pointCount) {
    _instance?.recordStroke(pointCount);
  }

  void _updateAdaptiveMultiplier() {
    if (_recentStrokeLengths.length < 3) return; // need minimum data

    final avgLength =
        _recentStrokeLengths.reduce((a, b) => a + b) /
        _recentStrokeLengths.length;

    // Annotation mode: avgLength < 80 points → reduce to 0.3
    // Sketching mode: avgLength > 200 points → full (1.0)
    // EMA for smooth transitions
    double target;
    if (avgLength < 80) {
      target = 0.3 + (avgLength / 80.0) * 0.4; // 0.3–0.7
    } else if (avgLength < 200) {
      target = 0.7 + ((avgLength - 80) / 120.0) * 0.3; // 0.7–1.0
    } else {
      target = 1.0;
    }

    // EMA smoothing (alpha=0.3 — responsive but not jumpy)
    _adaptiveMultiplier = _adaptiveMultiplier * 0.7 + target * 0.3;
  }

  @override
  void dispose() {
    _isActive = false;
    if (_instance == this) {
      _instance = null;
    }
  }

  // ─── Configuration API ──────────────────────────────────────────────

  /// Enable/disable individual organic behaviors.
  void configure({bool? tremor, bool? physicsInk, bool? elasticStabilizer}) {
    if (tremor != null) _tremorOn = tremor;
    if (physicsInk != null) _physicsInkOn = physicsInk;
    if (elasticStabilizer != null) _elasticStabOn = elasticStabilizer;
  }

  /// Diagnostics for debug overlay.
  Map<String, dynamic> get diagnosticsMap => {
    'intensity': _intensity,
    'adaptiveMultiplier': _adaptiveMultiplier,
    'recentAvgLength':
        _recentStrokeLengths.isEmpty
            ? 0
            : _recentStrokeLengths.reduce((a, b) => a + b) ~/
                _recentStrokeLengths.length,
    'tremor': _tremorOn,
    'physicsInk': _physicsInkOn,
    'elasticStabilizer': _elasticStabOn,
  };
}
