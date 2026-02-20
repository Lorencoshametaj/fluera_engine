import 'dart:collection';
import 'dart:math' as math;

// ---------------------------------------------------------------------------
// Render phases
// ---------------------------------------------------------------------------

/// Named phases of the render pipeline.
///
/// A frame passes through these phases sequentially. The profiler
/// records wall-clock time spent in each phase.
enum RenderPhase {
  /// Scene graph traversal and dirty-flag propagation.
  traversal,

  /// Layout calculation (auto-layout, constraints, responsive variants).
  layout,

  /// Constraint solving (geometric + inter-node).
  constraintSolve,

  /// Paint / rasterisation of dirty regions.
  paint,

  /// Compositing layers and effects.
  composite,

  /// Accessibility tree rebuild.
  accessibility,

  /// Post-frame bookkeeping (cache eviction, spatial index update).
  postFrame,
}

// ---------------------------------------------------------------------------
// FrameProfile
// ---------------------------------------------------------------------------

/// Immutable timing snapshot for a single rendered frame.
class FrameProfile {
  /// Monotonic frame index.
  final int frameIndex;

  /// Timestamp (microseconds since epoch) when the frame started.
  final int startUs;

  /// Total frame duration in microseconds.
  final int totalUs;

  /// Per-phase timings (microseconds).
  final Map<RenderPhase, int> phaseDurations;

  /// Number of dirty nodes processed this frame.
  final int dirtyNodeCount;

  /// Number of nodes painted this frame.
  final int paintedNodeCount;

  const FrameProfile({
    required this.frameIndex,
    required this.startUs,
    required this.totalUs,
    required this.phaseDurations,
    this.dirtyNodeCount = 0,
    this.paintedNodeCount = 0,
  });

  /// Total frame duration as a [Duration].
  Duration get duration => Duration(microseconds: totalUs);

  /// Duration of a specific phase.
  Duration phaseDuration(RenderPhase phase) =>
      Duration(microseconds: phaseDurations[phase] ?? 0);

  /// Whether this frame exceeded the 16.67ms budget (60 FPS).
  bool get isJank => totalUs > 16667;

  /// Whether this frame exceeded the 8.33ms budget (120 FPS).
  bool get isJank120 => totalUs > 8333;

  Map<String, dynamic> toJson() => {
    'frameIndex': frameIndex,
    'startUs': startUs,
    'totalUs': totalUs,
    'phases': {for (final e in phaseDurations.entries) e.key.name: e.value},
    'dirtyNodeCount': dirtyNodeCount,
    'paintedNodeCount': paintedNodeCount,
  };
}

// ---------------------------------------------------------------------------
// ProfileReport
// ---------------------------------------------------------------------------

/// Aggregated statistics over a window of [FrameProfile]s.
class ProfileReport {
  /// Number of frames in the window.
  final int frameCount;

  /// p50 (median) frame time in microseconds.
  final int p50Us;

  /// p95 frame time in microseconds.
  final int p95Us;

  /// p99 frame time in microseconds.
  final int p99Us;

  /// Average frame time in microseconds.
  final double avgUs;

  /// Maximum frame time in microseconds.
  final int maxUs;

  /// Frame rate (average FPS derived from average frame time).
  final double fps;

  /// Number of jank frames (>16.67ms).
  final int jankFrames;

  /// Jank percentage.
  final double jankPercent;

  /// Per-phase averages (microseconds).
  final Map<RenderPhase, double> phaseAverages;

  /// The phase consuming the most time on average (bottleneck).
  final RenderPhase? bottleneck;

  const ProfileReport({
    required this.frameCount,
    required this.p50Us,
    required this.p95Us,
    required this.p99Us,
    required this.avgUs,
    required this.maxUs,
    required this.fps,
    required this.jankFrames,
    required this.jankPercent,
    required this.phaseAverages,
    this.bottleneck,
  });

  Map<String, dynamic> toJson() => {
    'frameCount': frameCount,
    'p50Us': p50Us,
    'p95Us': p95Us,
    'p99Us': p99Us,
    'avgUs': avgUs.round(),
    'maxUs': maxUs,
    'fps': double.parse(fps.toStringAsFixed(1)),
    'jankFrames': jankFrames,
    'jankPercent': double.parse(jankPercent.toStringAsFixed(1)),
    'phaseAverages': {
      for (final e in phaseAverages.entries)
        e.key.name: double.parse(e.value.toStringAsFixed(1)),
    },
    if (bottleneck != null) 'bottleneck': bottleneck!.name,
  };

  @override
  String toString() =>
      'ProfileReport(frames: $frameCount, avg: ${(avgUs / 1000).toStringAsFixed(2)}ms, '
      'p95: ${(p95Us / 1000).toStringAsFixed(2)}ms, '
      'jank: ${jankPercent.toStringAsFixed(1)}%, '
      'fps: ${fps.toStringAsFixed(1)})';
}

// ---------------------------------------------------------------------------
// RenderProfiler
// ---------------------------------------------------------------------------

/// Per-frame render pipeline profiler.
///
/// Records wall-clock time for each [RenderPhase] within a frame and
/// provides aggregated statistics via [report].
///
/// ```dart
/// final profiler = RenderProfiler();
///
/// // Each frame:
/// profiler.beginFrame();
/// profiler.beginPhase(RenderPhase.traversal);
/// // ... traversal work ...
/// profiler.endPhase();
/// profiler.beginPhase(RenderPhase.paint);
/// // ... paint work ...
/// profiler.endPhase();
/// profiler.endFrame(dirtyNodeCount: 42, paintedNodeCount: 12);
///
/// // Get stats:
/// final report = profiler.report();
/// print(report.p95Us); // 95th percentile frame time
/// ```
class RenderProfiler {
  /// Maximum number of frames retained in the ring buffer.
  final int maxFrames;

  /// Ring buffer of recent frame profiles.
  final Queue<FrameProfile> _frames = Queue<FrameProfile>();

  /// Whether profiling is enabled. Disable in release for zero overhead.
  bool enabled;

  // -- Per-frame state ------------------------------------------------------

  int _frameCounter = 0;
  int _frameStartUs = 0;
  final Map<RenderPhase, int> _currentPhases = {};
  RenderPhase? _activePhase;
  int _phaseStartUs = 0;

  RenderProfiler({this.maxFrames = 300, this.enabled = true});

  // -------------------------------------------------------------------------
  // Frame lifecycle
  // -------------------------------------------------------------------------

  /// Begin profiling a new frame.
  void beginFrame() {
    if (!enabled) return;
    _frameStartUs = _nowUs();
    _currentPhases.clear();
    _activePhase = null;
  }

  /// Begin a named phase within the current frame.
  ///
  /// Automatically ends the previous phase if one is active.
  void beginPhase(RenderPhase phase) {
    if (!enabled) return;
    // Auto-end previous phase.
    if (_activePhase != null) {
      _endCurrentPhase();
    }
    _activePhase = phase;
    _phaseStartUs = _nowUs();
  }

  /// End the current phase.
  void endPhase() {
    if (!enabled || _activePhase == null) return;
    _endCurrentPhase();
  }

  /// End the current frame and record its profile.
  void endFrame({int dirtyNodeCount = 0, int paintedNodeCount = 0}) {
    if (!enabled) return;
    // Auto-end any active phase.
    if (_activePhase != null) {
      _endCurrentPhase();
    }

    final totalUs = _nowUs() - _frameStartUs;
    final profile = FrameProfile(
      frameIndex: _frameCounter++,
      startUs: _frameStartUs,
      totalUs: totalUs,
      phaseDurations: Map.unmodifiable(_currentPhases),
      dirtyNodeCount: dirtyNodeCount,
      paintedNodeCount: paintedNodeCount,
    );

    _frames.addLast(profile);
    if (_frames.length > maxFrames) {
      _frames.removeFirst();
    }
  }

  void _endCurrentPhase() {
    final elapsed = _nowUs() - _phaseStartUs;
    _currentPhases[_activePhase!] =
        (_currentPhases[_activePhase!] ?? 0) + elapsed;
    _activePhase = null;
  }

  // -------------------------------------------------------------------------
  // Queries
  // -------------------------------------------------------------------------

  /// Number of recorded frames.
  int get frameCount => _frames.length;

  /// Get the last N frame profiles.
  List<FrameProfile> lastFrames([int count = 60]) {
    final c = math.min(count, _frames.length);
    return _frames.toList().sublist(_frames.length - c);
  }

  /// Latest frame profile, or null if none recorded.
  FrameProfile? get lastFrame => _frames.isNotEmpty ? _frames.last : null;

  /// Generate an aggregated report over the last [windowSize] frames.
  ProfileReport report({int windowSize = 120}) {
    final window = lastFrames(windowSize);
    if (window.isEmpty) {
      return const ProfileReport(
        frameCount: 0,
        p50Us: 0,
        p95Us: 0,
        p99Us: 0,
        avgUs: 0,
        maxUs: 0,
        fps: 0,
        jankFrames: 0,
        jankPercent: 0,
        phaseAverages: {},
      );
    }

    // Sort frame times for percentile calculation.
    final sorted = window.map((f) => f.totalUs).toList()..sort();
    final n = sorted.length;

    final p50 = sorted[(n * 0.50).floor()];
    final p95 = sorted[(n * 0.95).floor().clamp(0, n - 1)];
    final p99 = sorted[(n * 0.99).floor().clamp(0, n - 1)];
    final avg = sorted.reduce((a, b) => a + b) / n;
    final maxVal = sorted.last;
    final janks = window.where((f) => f.isJank).length;

    // Per-phase averages.
    final phaseTotals = <RenderPhase, int>{};
    final phaseCounts = <RenderPhase, int>{};
    for (final frame in window) {
      for (final e in frame.phaseDurations.entries) {
        phaseTotals[e.key] = (phaseTotals[e.key] ?? 0) + e.value;
        phaseCounts[e.key] = (phaseCounts[e.key] ?? 0) + 1;
      }
    }
    final phaseAvgs = <RenderPhase, double>{};
    RenderPhase? bottleneck;
    double bottleneckAvg = 0;
    for (final phase in RenderPhase.values) {
      final total = phaseTotals[phase] ?? 0;
      final count = phaseCounts[phase] ?? 0;
      if (count > 0) {
        final a = total / count;
        phaseAvgs[phase] = a;
        if (a > bottleneckAvg) {
          bottleneckAvg = a;
          bottleneck = phase;
        }
      }
    }

    return ProfileReport(
      frameCount: n,
      p50Us: p50,
      p95Us: p95,
      p99Us: p99,
      avgUs: avg,
      maxUs: maxVal,
      fps: avg > 0 ? 1000000.0 / avg : 0,
      jankFrames: janks,
      jankPercent: n > 0 ? (janks / n) * 100 : 0,
      phaseAverages: phaseAvgs,
      bottleneck: bottleneck,
    );
  }

  /// Clear all recorded frames.
  void reset() {
    _frames.clear();
    _frameCounter = 0;
  }

  static int _nowUs() => DateTime.now().microsecondsSinceEpoch;
}
