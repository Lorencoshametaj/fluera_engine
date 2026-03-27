import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/animation.dart';
import '../../canvas/infinite_canvas_controller.dart';
import '../../reflow/knowledge_connection.dart';
import '../../reflow/content_cluster.dart';
import '../models/synchronized_recording.dart';
import './synchronized_playback_controller.dart';

/// 🎬 CINEMATIC PLAYBACK STATE
///
/// State machine for the cinematic playback flow.
enum CinematicState {
  /// No cinematic playback active.
  idle,

  /// Camera is panning to the first/next cluster.
  panningToCluster,

  /// Strokes of the current cluster are being drawn in real-time.
  drawingCluster,

  /// Camera is following a connection Bézier path to the next cluster.
  followingConnection,

  /// Paused by user during cinematic playback.
  paused,

  /// Cinematic playback has finished.
  completed,
}

/// Available playback speeds.
const List<double> kCinematicSpeeds = [0.5, 1.0, 1.5, 2.0, 3.0];

/// 🎬 A step in the cinematic playback sequence.
///
/// Each step represents one cluster's strokes being drawn, followed
/// by a camera transition along a connection to the next cluster.
class _CinematicStep {
  /// The cluster being drawn in this step.
  final ContentCluster cluster;

  /// The connection to follow after this cluster is done (null for last step).
  final KnowledgeConnection? connectionToNext;

  /// The next cluster (null for last step).
  final ContentCluster? nextCluster;

  /// Time range (ms) of strokes in this cluster within the recording.
  final int startMs;
  final int endMs;

  const _CinematicStep({
    required this.cluster,
    required this.startMs,
    required this.endMs,
    this.connectionToNext,
    this.nextCluster,
  });

  /// Duration of the drawing phase in seconds (at 1x speed).
  double get drawDurationSeconds => (endMs - startMs) / 1000.0;
}

/// 🎬 CINEMATIC PLAYBACK CONTROLLER
///
/// Orchestrates "Cinematic Playback" — the canvas becomes a dynamic
/// presentation that replays the user's note-taking process:
///
/// 1. Orders clusters chronologically (by first stroke timestamp)
/// 2. For each cluster:
///    - Camera pans + zooms to frame the cluster
///    - Strokes draw in real-time with synchronized audio
///    - When complete, camera follows the Bézier connection path to the next cluster
/// 3. Repeats until all clusters have been visited
///
/// USES:
/// - [SynchronizedPlaybackController] for audio + stroke timing
/// - [InfiniteCanvasController.animateMultiPhase] for camera flights
/// - [KnowledgeConnection] paths for transition curves
///
/// DESIGN DECISIONS:
/// - Camera dwell time on each cluster = actual stroke drawing duration
/// - Connection transition speed = 0.8s (fixed, with ease-in-out)
/// - Viewport padding = 20% around cluster bounds (breathing room)
/// - Auto-pause on user touch (resume with play button)
class CinematicPlaybackController extends ChangeNotifier {
  /// The synchronized playback controller (audio + strokes).
  final SynchronizedPlaybackController _syncPlayback;

  /// The canvas camera controller (for pan/zoom animations).
  final InfiniteCanvasController _cameraController;

  /// Current state of the cinematic playback.
  CinematicState _state = CinematicState.idle;
  CinematicState get state => _state;

  /// Whether cinematic playback is active.
  bool get isActive => _state != CinematicState.idle &&
                        _state != CinematicState.completed;

  /// Whether currently paused.
  bool get isPaused => _state == CinematicState.paused;

  /// Progress through the entire cinematic (0.0–1.0).
  double get overallProgress {
    if (_steps.isEmpty) return 0.0;
    return (_currentStepIndex + _stepProgress) / _steps.length;
  }

  /// Index of the current step.
  int get currentStepIndex => _currentStepIndex;

  /// Total number of steps.
  int get totalSteps => _steps.length;

  /// ID of the cluster currently being presented.
  String? get activeClusterId =>
      _currentStepIndex < _steps.length
          ? _steps[_currentStepIndex].cluster.id
          : null;

  // ===========================================================================
  // INTERNAL STATE
  // ===========================================================================

  /// The computed sequence of cinematic steps.
  List<_CinematicStep> _steps = [];

  /// Current step index.
  int _currentStepIndex = 0;

  /// Progress within the current step (0.0–1.0).
  double _stepProgress = 0.0;

  /// State saved before pause (to resume correctly).
  CinematicState _stateBeforePause = CinematicState.idle;

  /// Viewport size (needed for camera framing calculations).
  Size _viewportSize = Size.zero;

  /// Timer that monitors drawing progress and advances steps.
  Timer? _drawingMonitor;

  /// Camera transition duration in seconds.
  static const double _transitionDuration = 0.8;

  /// Viewport padding ratio around cluster bounds.
  static const double _viewportPadding = 0.20;

  /// Dwell time (seconds) after a cluster finishes drawing before moving on.
  static const double _dwellTime = 0.5;

  /// 🚀 PERF: Adaptive Bézier sample count based on connection distance.
  /// Short connections (<300px): 3 samples (fast)
  /// Medium: 5 samples (balanced)
  /// Long connections (>800px): 8 samples (smooth)
  int _adaptiveBezierSamples(double distance) {
    if (distance < 300) return 3;
    if (distance > 800) return 8;
    return 5;
  }

  /// Current playback speed multiplier.
  double _playbackSpeed = 1.0;
  double get playbackSpeed => _playbackSpeed;

  /// Elapsed playback time in ms (accounting for speed).
  int get elapsedTimeMs {
    if (_steps.isEmpty || _currentStepIndex >= _steps.length) return 0;
    int elapsed = 0;
    for (int i = 0; i < _currentStepIndex; i++) {
      elapsed += _steps[i].endMs - _steps[i].startMs;
    }
    final step = _steps[_currentStepIndex];
    elapsed += ((step.endMs - step.startMs) * _stepProgress).toInt();
    return elapsed;
  }

  /// Total recording time in ms.
  int get totalTimeMs {
    if (_steps.isEmpty) return 0;
    return _steps.last.endMs - _steps.first.startMs;
  }

  CinematicPlaybackController({
    required SynchronizedPlaybackController syncPlayback,
    required InfiniteCanvasController cameraController,
  }) : _syncPlayback = syncPlayback,
       _cameraController = cameraController;

  // ===========================================================================
  // PUBLIC API
  // ===========================================================================

  /// Start cinematic playback.
  ///
  /// [clusters] — all content clusters on the canvas.
  /// [connections] — all knowledge connections between clusters.
  /// [recording] — the synchronized recording (audio + strokes).
  /// [viewportSize] — current viewport dimensions.
  ///
  /// The controller will:
  /// 1. Sort clusters by first stroke timestamp
  /// 2. Build a traversal path following connections
  /// 3. Start audio playback and camera animation
  Future<void> start({
    required List<ContentCluster> clusters,
    required List<KnowledgeConnection> connections,
    required SynchronizedRecording recording,
    required Size viewportSize,
  }) async {
    if (clusters.isEmpty || recording.syncedStrokes.isEmpty) {
      debugPrint('🎬 [CinematicPlayback] Cannot start: no clusters or strokes');
      return;
    }

    _viewportSize = viewportSize;

    // Build the cinematic sequence
    _steps = _buildSteps(clusters, connections, recording);
    if (_steps.isEmpty) {
      debugPrint('🎬 [CinematicPlayback] No valid steps computed');
      return;
    }

    _currentStepIndex = 0;
    _stepProgress = 0.0;

    debugPrint('🎬 [CinematicPlayback] Starting with ${_steps.length} steps');

    // Load and start the recording
    await _syncPlayback.loadRecording(recording);

    // Start with the first step
    _state = CinematicState.panningToCluster;
    notifyListeners();

    _panToCurrentCluster(thenDraw: true);
  }

  /// Pause cinematic playback.
  Future<void> pause() async {
    if (!isActive) return;
    _stateBeforePause = _state;
    _state = CinematicState.paused;
    _drawingMonitor?.cancel();
    await _syncPlayback.pause();
    _cameraController.stopAnimation();
    notifyListeners();
  }

  /// Resume after pause.
  Future<void> resume() async {
    if (_state != CinematicState.paused) return;

    _state = _stateBeforePause;
    notifyListeners();

    switch (_state) {
      case CinematicState.panningToCluster:
        _panToCurrentCluster(thenDraw: true);
        break;
      case CinematicState.drawingCluster:
        await _syncPlayback.play();
        _startDrawingMonitor();
        break;
      case CinematicState.followingConnection:
        _transitionToNextStep();
        break;
      default:
        break;
    }
  }

  /// Toggle pause/resume.
  Future<void> togglePause() async {
    if (_state == CinematicState.paused) {
      await resume();
    } else if (isActive) {
      await pause();
    }
  }

  /// Stop and reset cinematic playback.
  void stop() {
    _drawingMonitor?.cancel();
    _drawingMonitor = null;
    _cameraController.stopAnimation();
    _syncPlayback.stop();
    _steps = [];
    _currentStepIndex = 0;
    _stepProgress = 0.0;
    _playbackSpeed = 1.0;
    _state = CinematicState.idle;
    notifyListeners();
  }

  // ===========================================================================
  // NAVIGATION (SKIP FORWARD / BACKWARD)
  // ===========================================================================

  /// Skip to the next cluster (fast-forward).
  ///
  /// Immediately stops the current drawing/transition and jumps to
  /// the next cluster's camera position + audio start.
  Future<void> skipToNextCluster() async {
    if (!isActive && _state != CinematicState.paused) return;
    if (_currentStepIndex >= _steps.length - 1) {
      _complete();
      return;
    }

    _drawingMonitor?.cancel();
    _cameraController.stopAnimation();

    _currentStepIndex++;
    _stepProgress = 0.0;

    final step = _steps[_currentStepIndex];
    await _syncPlayback.seek(Duration(milliseconds: step.startMs));

    _state = CinematicState.panningToCluster;
    notifyListeners();
    _panToCurrentCluster(thenDraw: true);

    debugPrint('⏩ [CinematicPlayback] Skip to step $_currentStepIndex');
  }

  /// Skip to the previous cluster (rewind).
  ///
  /// If more than 2s into the current cluster, restarts the current one.
  /// Otherwise, goes back to the previous cluster.
  Future<void> skipToPreviousCluster() async {
    if (!isActive && _state != CinematicState.paused) return;

    _drawingMonitor?.cancel();
    _cameraController.stopAnimation();

    // If >2 seconds into current step, restart it
    final step = _steps[_currentStepIndex];
    final currentMs = _syncPlayback.positionMs;
    if (currentMs - step.startMs > 2000 || _currentStepIndex == 0) {
      // Restart current step
      _stepProgress = 0.0;
    } else {
      // Go back one step
      _currentStepIndex--;
      _stepProgress = 0.0;
    }

    final targetStep = _steps[_currentStepIndex];
    await _syncPlayback.seek(Duration(milliseconds: targetStep.startMs));

    _state = CinematicState.panningToCluster;
    notifyListeners();
    _panToCurrentCluster(thenDraw: true);

    debugPrint('⏪ [CinematicPlayback] Back to step $_currentStepIndex');
  }

  // ===========================================================================
  // SPEED CONTROL
  // ===========================================================================

  /// Set playback speed (0.5x–3.0x).
  void setSpeed(double speed) {
    _playbackSpeed = speed.clamp(0.5, 3.0);
    _syncPlayback.setPlaybackSpeed(_playbackSpeed);
    notifyListeners();
    debugPrint('⏯️ [CinematicPlayback] Speed: ${_playbackSpeed}x');
  }

  /// Cycle through preset speeds: 1x → 1.5x → 2x → 3x → 0.5x → 1x
  void cycleSpeed() {
    final idx = kCinematicSpeeds.indexOf(_playbackSpeed);
    final next = (idx + 1) % kCinematicSpeeds.length;
    setSpeed(kCinematicSpeeds[next]);
  }

  // ===========================================================================
  // STEP BUILDING
  // ===========================================================================

  /// Build the ordered list of cinematic steps.
  ///
  /// 🚀 PERF: O(n+m) complexity via reverse lookup map:
  ///   1. Build strokeId → clusterId map from clusters O(n)
  ///   2. Scan synced strokes once to compute time ranges O(m)
  ///   3. Sort + link connections O(c log c + k)
  List<_CinematicStep> _buildSteps(
    List<ContentCluster> clusters,
    List<KnowledgeConnection> connections,
    SynchronizedRecording recording,
  ) {
    // 🚀 PERF: Reverse lookup: strokeId → clusterId (O(n) build)
    final strokeToCluster = <String, String>{};
    for (final cluster in clusters) {
      for (final strokeId in cluster.strokeIds) {
        strokeToCluster[strokeId] = cluster.id;
      }
    }

    // 🚀 PERF: Single pass over synced strokes (O(m))
    final clusterTimeRanges = <String, (int, int)>{};
    for (final synced in recording.syncedStrokes) {
      final clusterId = strokeToCluster[synced.stroke.id];
      if (clusterId == null) continue;

      final existing = clusterTimeRanges[clusterId];
      if (existing == null) {
        clusterTimeRanges[clusterId] = (
          synced.relativeStartMs,
          synced.relativeEndMs,
        );
      } else {
        clusterTimeRanges[clusterId] = (
          math.min(existing.$1, synced.relativeStartMs),
          math.max(existing.$2, synced.relativeEndMs),
        );
      }
    }

    // Sort clusters chronologically by first stroke time
    final sortedClusters = clusters
        .where((c) => clusterTimeRanges.containsKey(c.id))
        .toList()
      ..sort((a, b) {
        final aStart = clusterTimeRanges[a.id]!.$1;
        final bStart = clusterTimeRanges[b.id]!.$1;
        return aStart.compareTo(bStart);
      });

    if (sortedClusters.isEmpty) return [];

    // Build connection lookup for fast pair search
    final connectionLookup = <String, KnowledgeConnection>{};
    for (final conn in connections) {
      if (conn.isGhost) continue;
      final key1 = '${conn.sourceClusterId}|${conn.targetClusterId}';
      final key2 = '${conn.targetClusterId}|${conn.sourceClusterId}';
      connectionLookup[key1] = conn;
      connectionLookup[key2] = conn;
    }

    // Build steps
    final steps = <_CinematicStep>[];
    for (int i = 0; i < sortedClusters.length; i++) {
      final cluster = sortedClusters[i];
      final timeRange = clusterTimeRanges[cluster.id]!;

      KnowledgeConnection? connectionToNext;
      ContentCluster? nextCluster;

      if (i < sortedClusters.length - 1) {
        nextCluster = sortedClusters[i + 1];
        final key = '${cluster.id}|${nextCluster.id}';
        connectionToNext = connectionLookup[key];
      }

      steps.add(_CinematicStep(
        cluster: cluster,
        startMs: timeRange.$1,
        endMs: timeRange.$2,
        connectionToNext: connectionToNext,
        nextCluster: nextCluster,
      ));
    }

    return steps;
  }

  // ===========================================================================
  // CAMERA ANIMATION
  // ===========================================================================

  /// Pan camera to frame the current cluster, then start drawing.
  void _panToCurrentCluster({required bool thenDraw}) {
    if (_currentStepIndex >= _steps.length) {
      _complete();
      return;
    }

    final step = _steps[_currentStepIndex];
    final targetRect = _paddedBounds(step.cluster.bounds);

    // Compute the offset and scale to frame the cluster
    final targetScale = _computeFitScale(targetRect);
    final targetOffset = _computeCenterOffset(targetRect, targetScale);

    // Use animateMultiPhase for smooth camera transition
    _cameraController.animateMultiPhase(
      keyframes: [
        CameraKeyframe(
          targetOffset: targetOffset,
          targetScale: targetScale,
          durationSeconds: 0.6,
          curve: Curves.easeInOutCubic,
        ),
      ],
      onComplete: () {
        if (thenDraw && _state != CinematicState.paused) {
          _startDrawingPhase();
        }
      },
    );
  }

  /// Start the drawing phase: play audio + strokes for the current cluster.
  Future<void> _startDrawingPhase() async {
    if (_currentStepIndex >= _steps.length) {
      _complete();
      return;
    }

    _state = CinematicState.drawingCluster;
    notifyListeners();

    final step = _steps[_currentStepIndex];

    // Seek audio to the start of this cluster's strokes
    await _syncPlayback.seek(Duration(milliseconds: step.startMs));
    await _syncPlayback.play();

    // Monitor drawing progress
    _startDrawingMonitor();
  }

  /// Start a timer that monitors when the current cluster's strokes are done.
  void _startDrawingMonitor() {
    _drawingMonitor?.cancel();
    _drawingMonitor = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => _checkDrawingProgress(),
    );
  }

  /// Check if the current cluster's strokes have all been drawn.
  void _checkDrawingProgress() {
    if (_currentStepIndex >= _steps.length) return;

    final step = _steps[_currentStepIndex];
    final currentMs = _syncPlayback.positionMs;

    // Update step progress
    final totalMs = step.endMs - step.startMs;
    if (totalMs > 0) {
      _stepProgress = ((currentMs - step.startMs) / totalMs).clamp(0.0, 1.0);
    }

    // Check if all strokes in this cluster are done
    if (currentMs >= step.endMs) {
      _drawingMonitor?.cancel();
      _drawingMonitor = null;

      // Dwell briefly before transitioning
      Future.delayed(
        Duration(milliseconds: (_dwellTime * 1000).toInt()),
        () {
          if (_state == CinematicState.drawingCluster) {
            _transitionToNextStep();
          }
        },
      );
    }
  }

  /// Transition camera along the connection to the next cluster.
  void _transitionToNextStep() {
    if (_currentStepIndex >= _steps.length) {
      _complete();
      return;
    }

    final step = _steps[_currentStepIndex];

    if (step.connectionToNext != null && step.nextCluster != null) {
      _state = CinematicState.followingConnection;
      notifyListeners();

      // === BÉZIER CAMERA PATH FOLLOWING ===
      // Instead of a simple zoom-out/zoom-in, the camera traces
      // the actual connection Bézier curve with multiple keyframes.

      final conn = step.connectionToNext!;
      final currentBounds = _paddedBounds(step.cluster.bounds);
      final nextBounds = _paddedBounds(step.nextCluster!.bounds);

      // Source and target points for the Bézier
      final srcPt = step.cluster.centroid;
      final tgtPt = step.nextCluster!.centroid;
      final controlPt = _bezierControlPoint(
        srcPt, tgtPt, conn.curveStrength,
      );

      // Combined rect: needed for the intermediate zoom level
      final combinedRect = currentBounds.expandToInclude(nextBounds);
      final transitScale = _computeFitScale(
        combinedRect.inflate(combinedRect.shortestSide * 0.15),
      );

      // 🚀 PERF: Adaptive Bézier samples based on distance
      final connectionDistance = (srcPt - tgtPt).distance;
      final sampleCount = _adaptiveBezierSamples(connectionDistance);

      // Build multi-keyframe path along the Bézier curve
      final keyframes = <CameraKeyframe>[];

      // Phase 1: Zoom out slightly
      final midPoint = _pointOnBezier(srcPt, controlPt, tgtPt, 0.5);
      final midOffset = _computeCenterOffset(
        Rect.fromCenter(center: midPoint, width: combinedRect.width, height: combinedRect.height),
        transitScale,
      );
      keyframes.add(CameraKeyframe(
        targetOffset: midOffset,
        targetScale: transitScale,
        durationSeconds: _transitionDuration * 0.3 / _playbackSpeed,
        curve: Curves.easeInCubic,
      ));

      // Phase 2..N-1: Follow Bézier curve at intermediate zoom
      final intermediateCount = sampleCount - 2;
      if (intermediateCount > 0) {
        for (int i = 1; i <= intermediateCount; i++) {
          final t = i / (intermediateCount + 1);
          final pt = _pointOnBezier(srcPt, controlPt, tgtPt, t);
          final sampleOffset = _computeCenterOffset(
            Rect.fromCenter(center: pt, width: combinedRect.width, height: combinedRect.height),
            transitScale,
          );
          keyframes.add(CameraKeyframe(
            targetOffset: sampleOffset,
            targetScale: transitScale,
            durationSeconds: _transitionDuration * 0.4 / intermediateCount / _playbackSpeed,
            curve: Curves.linear,
          ));
        }
      }

      // Phase 5: Zoom into next cluster
      final nextScale = _computeFitScale(nextBounds);
      final nextOffset = _computeCenterOffset(nextBounds, nextScale);
      keyframes.add(CameraKeyframe(
        targetOffset: nextOffset,
        targetScale: nextScale,
        durationSeconds: _transitionDuration * 0.3 / _playbackSpeed,
        curve: Curves.easeOutCubic,
      ));

      _cameraController.animateMultiPhase(
        keyframes: keyframes,
        sourceClusterId: step.cluster.id,
        targetClusterId: step.nextCluster!.id,
        onComplete: () {
          _advanceToNextStep();
        },
      );
    } else {
      // No connection to follow — just advance
      _advanceToNextStep();
    }
  }

  /// Move to the next step or complete.
  void _advanceToNextStep() {
    _currentStepIndex++;
    _stepProgress = 0.0;

    if (_currentStepIndex >= _steps.length) {
      _complete();
    } else {
      _state = CinematicState.panningToCluster;
      notifyListeners();
      _panToCurrentCluster(thenDraw: true);
    }
  }

  /// Mark playback as complete.
  void _complete() {
    _drawingMonitor?.cancel();
    _drawingMonitor = null;
    _state = CinematicState.completed;
    notifyListeners();
    debugPrint('🎬 [CinematicPlayback] Complete!');
  }

  // ===========================================================================
  // GEOMETRY HELPERS
  // ===========================================================================

  /// Compute bounds with viewport padding.
  Rect _paddedBounds(Rect bounds) {
    final padX = bounds.width * _viewportPadding;
    final padY = bounds.height * _viewportPadding;
    return bounds.inflate(math.max(padX, padY));
  }

  /// Compute scale to fit a rect in the viewport (contain mode).
  double _computeFitScale(Rect targetRect) {
    if (_viewportSize.isEmpty || targetRect.isEmpty) return 1.0;
    final scaleX = _viewportSize.width / targetRect.width;
    final scaleY = _viewportSize.height / targetRect.height;
    return math.min(scaleX, scaleY).clamp(0.1, 5.0);
  }

  /// Compute offset to center a rect (at given scale) in the viewport.
  Offset _computeCenterOffset(Rect targetRect, double scale) {
    return Offset(
      _viewportSize.width / 2 - targetRect.center.dx * scale,
      _viewportSize.height / 2 - targetRect.center.dy * scale,
    );
  }

  /// Compute Bézier control point for a connection.
  Offset _bezierControlPoint(Offset src, Offset tgt, double curveStrength) {
    final mid = Offset(
      (src.dx + tgt.dx) / 2,
      (src.dy + tgt.dy) / 2,
    );
    // Perpendicular offset
    final dx = tgt.dx - src.dx;
    final dy = tgt.dy - src.dy;
    final perpX = -dy * curveStrength;
    final perpY = dx * curveStrength;
    return Offset(mid.dx + perpX, mid.dy + perpY);
  }

  /// Point on a quadratic Bézier at parameter t.
  Offset _pointOnBezier(Offset p0, Offset p1, Offset p2, double t) {
    final u = 1.0 - t;
    return Offset(
      u * u * p0.dx + 2 * u * t * p1.dx + t * t * p2.dx,
      u * u * p0.dy + 2 * u * t * p1.dy + t * t * p2.dy,
    );
  }

  // ===========================================================================
  // CLEANUP
  // ===========================================================================

  @override
  void dispose() {
    _drawingMonitor?.cancel();
    _drawingMonitor = null;
    super.dispose();
  }
}
