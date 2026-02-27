/// 🎯 ADAPTIVE PROFILE — L2 Intelligence Subsystem
///
/// Lightweight user behavior profile that tracks interaction patterns
/// within a session and derives tuning recommendations for other
/// engine subsystems.
///
/// NO PERSISTENCE in v1 — lives in memory only. The profile is reset
/// when the canvas is closed. Future versions may persist to disk
/// for cross-session learning.
///
/// ## What It Tracks
///
/// - **Drawing ratio**: how much time is spent drawing vs. navigating
/// - **Zoom change rate**: how often zoom changes per minute
/// - **Average stroke length**: typical stroke point count
/// - **Tool usage distribution**: which tools are used most
///
/// ## What It Recommends
///
/// Based on the tracked behavior, the profile derives:
/// - LOD precomputation aggressiveness
/// - 1€ filter reactivity (beta)
/// - Tile prefetch distance
/// - Memory budget allocation
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import '../utils/safe_path_provider.dart';
import '../core/conscious_architecture.dart';

/// L2 Intelligence: session-based behavior profiling and parameter tuning.
///
/// ## Usage
///
/// ```dart
/// final profile = EngineScope.current.consciousArchitecture
///     .find<AdaptiveProfile>();
///
/// // Read tuning recommendations
/// final beta = profile?.recommendedFilterBeta ?? 0.007;
/// final prefetch = profile?.recommendedTilePrefetch ?? 2;
/// ```
class AdaptiveProfile extends IntelligenceSubsystem {
  @override
  IntelligenceLayer get layer => IntelligenceLayer.adaptive;

  @override
  String get name => 'AdaptiveProfile';

  bool _active = true;

  @override
  bool get isActive => _active;

  // ─────────────────────────────────────────────────────────────────────────
  // Tracked Metrics
  // ─────────────────────────────────────────────────────────────────────────

  /// How much of the session is spent drawing (0.0 = never, 1.0 = always).
  double get drawingRatio =>
      _totalContextChanges > 0 ? _drawingChanges / _totalContextChanges : 0.0;

  /// How many zoom changes per minute.
  double get zoomChangeRate {
    final elapsed = _sessionDuration.inSeconds;
    if (elapsed < 1) return 0.0;
    return _zoomChanges / (elapsed / 60.0);
  }

  /// Average stroke point count observed in context updates.
  double get avgStrokeCount =>
      _strokeCountSamples > 0 ? _totalStrokeCount / _strokeCountSamples : 0.0;

  /// Most used tool in this session (null if no tool used yet).
  String? get dominantTool {
    if (_toolUsage.isEmpty) return null;
    return _toolUsage.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }

  /// Full tool usage distribution.
  Map<String, int> get toolUsage => Map.unmodifiable(_toolUsage);

  // ─── Internal state ───

  int _totalContextChanges = 0;
  int _drawingChanges = 0;
  int _zoomChanges = 0;
  double _lastZoom = 1.0;
  int _strokeCountSamples = 0;
  double _totalStrokeCount = 0;
  final Map<String, int> _toolUsage = {};
  final DateTime _sessionStart = DateTime.now();

  Duration get _sessionDuration => DateTime.now().difference(_sessionStart);

  // ─────────────────────────────────────────────────────────────────────────
  // Derived Recommendations
  // ─────────────────────────────────────────────────────────────────────────

  /// Recommended LOD precomputation batch size.
  ///
  /// Heavy drawers with many strokes benefit from aggressive precomputation.
  /// Navigators who zoom frequently need fast LOD switching.
  int get recommendedLODPrecompute {
    if (zoomChangeRate > 10) return 50; // Frequent zoomer: precompute more
    if (avgStrokeCount > 500) return 30; // Many strokes: worth precomputing
    return 15; // Default
  }

  /// Recommended 1€ filter beta (reactivity).
  ///
  /// Higher beta = more reactive (good for fast writing).
  /// Lower beta = smoother (good for deliberate illustration).
  double get recommendedFilterBeta {
    if (drawingRatio > 0.7) return 0.012; // Heavy drawer: more reactive
    if (drawingRatio < 0.3) return 0.005; // Mostly navigating: smoother
    return 0.007; // Default balanced
  }

  /// Recommended tile prefetch distance (tiles).
  ///
  /// Frequent navigators benefit from deeper prefetch.
  int get recommendedTilePrefetch {
    if (zoomChangeRate > 15) return 4; // Very active navigator
    if (zoomChangeRate > 5) return 3;
    return 2; // Default
  }

  /// Recommended memory budget allocation strategy.
  ///
  /// Returns a bias factor (0.0 to 1.0) for allocating memory:
  /// - Higher = allocate more to tile cache (navigator)
  /// - Lower = allocate more to stroke cache (drawer)
  double get tileCacheMemoryBias {
    if (drawingRatio > 0.7) return 0.3; // Drawer: prioritize stroke cache
    if (drawingRatio < 0.3) return 0.8; // Navigator: prioritize tile cache
    return 0.5; // Balanced
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void onContextChanged(EngineContext context) {
    _totalContextChanges++;

    // Track drawing state
    if (context.isDrawing) _drawingChanges++;

    // Track zoom changes (threshold to ignore micro-fluctuations)
    if ((context.zoom - _lastZoom).abs() > 0.01) {
      _zoomChanges++;
      _lastZoom = context.zoom;
    }

    // Track stroke count
    if (context.strokeCount > 0) {
      _strokeCountSamples++;
      _totalStrokeCount += context.strokeCount;
    }

    // Track tool usage
    if (context.activeTool != null) {
      _toolUsage[context.activeTool!] =
          (_toolUsage[context.activeTool!] ?? 0) + 1;
    }
  }

  @override
  void onIdle(Duration idleDuration) {
    // In v1, the profile is purely reactive — no idle work needed.
    // Future: could analyze patterns and emit tuning events.
  }

  @override
  void dispose() {
    _active = false;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Diagnostics
  // ─────────────────────────────────────────────────────────────────────────

  /// Summary of the current profile for diagnostics.
  Map<String, dynamic> toJson() => {
    'sessionDuration': _sessionDuration.inSeconds,
    'drawingRatio': drawingRatio,
    'zoomChangeRate': zoomChangeRate,
    'avgStrokeCount': avgStrokeCount,
    'dominantTool': dominantTool,
    'recommendations': {
      'lodPrecompute': recommendedLODPrecompute,
      'filterBeta': recommendedFilterBeta,
      'tilePrefetch': recommendedTilePrefetch,
      'tileCacheMemoryBias': tileCacheMemoryBias,
    },
  };

  // ─────────────────────────────────────────────────────────────────────────
  // Persistence — save/restore across sessions via SharedPreferences
  // ─────────────────────────────────────────────────────────────────────────

  static const String _prefsKey = 'conscious_adaptive_profile';

  /// Serialize internal counters to a map for persistence.
  Map<String, dynamic> _toCountersMap() => {
    'totalCtx': _totalContextChanges,
    'drawCtx': _drawingChanges,
    'zoomChg': _zoomChanges,
    'lastZoom': _lastZoom,
    'strokeSamples': _strokeCountSamples,
    'totalStrokes': _totalStrokeCount,
    'tools': _toolUsage,
  };

  /// Restore internal counters from a previously saved map.
  void _fromCountersMap(Map<String, dynamic> data) {
    _totalContextChanges += (data['totalCtx'] as int?) ?? 0;
    _drawingChanges += (data['drawCtx'] as int?) ?? 0;
    _zoomChanges += (data['zoomChg'] as int?) ?? 0;
    _lastZoom = (data['lastZoom'] as num?)?.toDouble() ?? 1.0;
    _strokeCountSamples += (data['strokeSamples'] as int?) ?? 0;
    _totalStrokeCount += (data['totalStrokes'] as num?)?.toDouble() ?? 0.0;
    final tools = data['tools'];
    if (tools is Map) {
      for (final entry in tools.entries) {
        final key = entry.key as String;
        final val = (entry.value as num?)?.toInt() ?? 0;
        _toolUsage[key] = (_toolUsage[key] ?? 0) + val;
      }
    }
  }

  /// Save the current profile counters to a JSON file in app support dir.
  Future<void> saveToPrefs() async {
    try {
      final dir = await getSafeAppSupportDirectory();
      if (dir == null) return; // Web: no filesystem
      final file = File('${dir.path}/$_prefsKey.json');
      await file.writeAsString(jsonEncode(_toCountersMap()));
    } catch (_) {
      // Best-effort — non-critical.
    }
  }

  /// Restore counters from a previously saved JSON file and merge into
  /// current state.
  Future<void> restoreFromPrefs() async {
    try {
      final dir = await getSafeAppSupportDirectory();
      if (dir == null) return; // Web: no filesystem
      final file = File('${dir.path}/$_prefsKey.json');
      if (await file.exists()) {
        final raw = await file.readAsString();
        final data = jsonDecode(raw) as Map<String, dynamic>;
        _fromCountersMap(data);
      }
    } catch (_) {
      // Best-effort — non-critical.
    }
  }
}
