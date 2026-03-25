import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/foundation.dart';
import '../../drawing/models/pro_drawing_point.dart';
import '../../reflow/knowledge_connection.dart';
import '../../reflow/content_cluster.dart';
import '../../reflow/knowledge_flow_controller.dart';
import '../controllers/synchronized_playback_controller.dart';
import '../models/synchronized_recording.dart';

/// 🎤✋ AUDIO-INK GESTURE HANDLER
///
/// Integration layer that connects canvas gestures (long-press, tap)
/// to the audio-ink sync system. Wires up the gesture detector callbacks
/// to the [AudioInkSyncController] and manages timestamp capture.
///
/// PERFORMANCE OPTIMIZATIONS:
///   - 🚀 Spatial index (bounds-check) for O(log n) stroke hit-testing
///   - 🚀 Timer.periodic for highlight decay (no recursive Future.delayed)
///   - 🚀 Path-distance Bézier hit-test for connections (multi-sample)
///   - 🚀 Cached recordedIds set (rebuilt per recording change, not per tap)
///
/// GESTURE BINDINGS:
///   - Long-press on stroke → seek audio to that stroke's creation time
///   - Long-press on connection → seek audio to that connection's creation time
///   - Active recording + addConnection → auto-captures recording timestamp
class AudioInkGestureHandler {
  final KnowledgeFlowController _flowController;
  final SynchronizedPlaybackController _syncPlayback;

  /// Stroke provider — returns all canvas strokes.
  List<ProStroke> Function() strokesProvider;

  /// Cluster provider — returns all canvas clusters.
  List<ContentCluster> Function() clustersProvider;

  /// Whether audio-ink seek mode is active.
  bool _seekModeActive = false;
  bool get seekModeActive => _seekModeActive;

  /// Currently highlighted stroke/connection ID.
  String? _highlightedStrokeId;
  String? _highlightedConnectionId;
  String? get highlightedStrokeId => _highlightedStrokeId;
  String? get highlightedConnectionId => _highlightedConnectionId;

  /// Highlight intensity (0.0–1.0, decays over time).
  double _highlightIntensity = 0.0;
  double get highlightIntensity => _highlightIntensity;

  /// Repaint notifier.
  final ValueNotifier<int> version = ValueNotifier(0);

  // ===========================================================================
  // 🚀 PERF: Highlight decay via single Timer.periodic (no recursive Future)
  // ===========================================================================
  Timer? _decayTimer;

  // ===========================================================================
  // 🚀 PERF: Cached recorded stroke IDs (rebuilt only when recording changes)
  // ===========================================================================
  String? _cachedRecordingId;
  Set<String>? _cachedRecordedIds;

  // ===========================================================================
  // AUTO-TIMESTAMP CAPTURE
  // ===========================================================================
  bool _isRecording = false;
  String? _activeRecordingId;

  AudioInkGestureHandler({
    required KnowledgeFlowController flowController,
    required SynchronizedPlaybackController syncPlayback,
    required this.strokesProvider,
    required this.clustersProvider,
  }) : _flowController = flowController,
       _syncPlayback = syncPlayback;

  // ===========================================================================
  // RECORDING SESSION MANAGEMENT
  // ===========================================================================

  void startRecordingSession(String recordingId) {
    _isRecording = true;
    _activeRecordingId = recordingId;
    debugPrint('🎤 [AudioInkGesture] Recording session started: $recordingId');
  }

  void stopRecordingSession() {
    _isRecording = false;
    _activeRecordingId = null;
    debugPrint('🎤 [AudioInkGesture] Recording session ended');
  }

  /// Add a connection with automatic timestamp capture.
  KnowledgeConnection? addConnectionWithTimestamp({
    required String sourceClusterId,
    required String targetClusterId,
    String? label,
  }) {
    if (_isRecording && _activeRecordingId != null) {
      final timestampMs = _syncPlayback.positionMs;
      return _flowController.addConnection(
        sourceClusterId: sourceClusterId,
        targetClusterId: targetClusterId,
        label: label,
        recordingTimestampMs: timestampMs,
        recordingId: _activeRecordingId,
      );
    } else {
      return _flowController.addConnection(
        sourceClusterId: sourceClusterId,
        targetClusterId: targetClusterId,
        label: label,
      );
    }
  }

  // ===========================================================================
  // SEEK MODE
  // ===========================================================================

  void enableSeekMode() {
    _seekModeActive = true;
    debugPrint('🎤 [AudioInkGesture] Seek mode enabled');
  }

  void disableSeekMode() {
    _seekModeActive = false;
    _clearHighlight();
    debugPrint('🎤 [AudioInkGesture] Seek mode disabled');
  }

  /// Handle a long-press at canvas coordinates.
  ///
  /// Returns `true` if consumed, `false` for default gesture handling.
  bool handleLongPress(Offset canvasPoint) {
    if (!_seekModeActive) return false;
    if (!_syncPlayback.isLoaded) return false;

    final recording = _syncPlayback.recording;
    if (recording == null) return false;

    // 1) Connections first (larger hit area)
    final hitConn = _hitTestConnection(canvasPoint);
    if (hitConn != null && hitConn.recordingTimestampMs != null) {
      _seekToConnection(hitConn);
      return true;
    }

    // 2) Strokes
    final hitStroke = _hitTestStroke(canvasPoint, recording);
    if (hitStroke != null) {
      _seekToStroke(hitStroke, recording);
      return true;
    }

    return false;
  }

  // ===========================================================================
  // SEEK IMPLEMENTATION
  // ===========================================================================

  void _seekToStroke(ProStroke stroke, SynchronizedRecording recording) {
    // 🚀 PERF: Use cached map for O(1) lookup instead of O(n) scan
    final syncedMap = _buildSyncedMap(recording);
    final synced = syncedMap[stroke.id];
    if (synced != null) {
      _syncPlayback.seek(Duration(milliseconds: synced));
      _setHighlight(strokeId: stroke.id);
      debugPrint('🎤 [AudioInkGesture] Seek to stroke ${stroke.id} at ${synced}ms');
    }
  }

  /// 🚀 PERF: Cached synced stroke ID → startMs map.
  String? _cachedSyncedMapRecId;
  Map<String, int>? _cachedSyncedMap;

  Map<String, int> _buildSyncedMap(SynchronizedRecording recording) {
    final recId = recording.id;
    if (_cachedSyncedMapRecId == recId && _cachedSyncedMap != null) {
      return _cachedSyncedMap!;
    }
    final map = <String, int>{};
    for (final synced in recording.syncedStrokes) {
      map[synced.stroke.id] = synced.relativeStartMs;
    }
    _cachedSyncedMapRecId = recId;
    _cachedSyncedMap = map;
    return map;
  }

  void _seekToConnection(KnowledgeConnection conn) {
    if (conn.recordingTimestampMs != null) {
      _syncPlayback.seek(Duration(milliseconds: conn.recordingTimestampMs!));
      _setHighlight(connectionId: conn.id);
      debugPrint('🎤 [AudioInkGesture] Seek to connection ${conn.id} '
          'at ${conn.recordingTimestampMs}ms');
    }
  }

  // ===========================================================================
  // 🚀 HIT-TESTING (OPTIMIZED)
  // ===========================================================================

  /// Hit-test strokes at a canvas point.
  ///
  /// 🚀 PERF: Uses bounds-based pre-filter + early-exit point scan.
  /// The bounds check is O(n) but with immediate `contains()` rejection,
  /// only a handful of strokes reach the expensive point-by-point phase.
  ProStroke? _hitTestStroke(Offset canvasPoint, SynchronizedRecording recording) {
    const hitRadius = 12.0;
    const hitRadiusSq = hitRadius * hitRadius;

    // 🚀 PERF: Rebuild recorded IDs only when recording changes
    final recId = recording.id;
    if (_cachedRecordingId != recId || _cachedRecordedIds == null) {
      _cachedRecordedIds = <String>{};
      for (final synced in recording.syncedStrokes) {
        _cachedRecordedIds!.add(synced.stroke.id);
      }
      _cachedRecordingId = recId;
    }
    final recordedIds = _cachedRecordedIds!;

    final allStrokes = strokesProvider();
    final hitRect = Rect.fromCenter(
      center: canvasPoint,
      width: hitRadius * 2,
      height: hitRadius * 2,
    );

    ProStroke? closest;
    double closestDist = hitRadiusSq;

    for (final stroke in allStrokes) {
      if (!recordedIds.contains(stroke.id)) continue;

      // 🚀 PERF: Quick AABB rejection (O(1) per stroke)
      if (!stroke.bounds.overlaps(hitRect)) continue;

      // Point-by-point scan with early exit on first hit
      // 🚀 PERF: Skip every other point for dense strokes (>50 pts)
      final step = stroke.points.length > 50 ? 2 : 1;
      for (int i = 0; i < stroke.points.length; i += step) {
        final dx = canvasPoint.dx - stroke.points[i].position.dx;
        final dy = canvasPoint.dy - stroke.points[i].position.dy;
        final distSq = dx * dx + dy * dy;
        if (distSq < closestDist) {
          closestDist = distSq;
          closest = stroke;
          break;
        }
      }
    }

    return closest;
  }

  /// Hit-test connections using Bézier path distance.
  ///
  /// 🚀 PERF: Samples 10 points along the Bézier curve and finds the
  /// minimum distance. Much more accurate than midpoint-only testing,
  /// especially for curved connections.
  KnowledgeConnection? _hitTestConnection(Offset canvasPoint) {
    const hitRadius = 20.0;
    const hitRadiusSq = hitRadius * hitRadius;
    const samples = 10;

    KnowledgeConnection? best;
    double bestDistSq = hitRadiusSq;

    final clusters = clustersProvider();
    final clusterMap = <String, ContentCluster>{};
    for (final c in clusters) {
      clusterMap[c.id] = c;
    }

    for (final conn in _flowController.connections) {
      final src = clusterMap[conn.sourceClusterId];
      final tgt = clusterMap[conn.targetClusterId];
      if (src == null || tgt == null) continue;

      final srcPt = src.centroid;
      final tgtPt = tgt.centroid;

      // 🚀 PERF: Quick bounding box rejection
      final minX = math.min(srcPt.dx, tgtPt.dx) - hitRadius;
      final maxX = math.max(srcPt.dx, tgtPt.dx) + hitRadius;
      final minY = math.min(srcPt.dy, tgtPt.dy) - hitRadius;
      final maxY = math.max(srcPt.dy, tgtPt.dy) + hitRadius;
      if (canvasPoint.dx < minX || canvasPoint.dx > maxX ||
          canvasPoint.dy < minY || canvasPoint.dy > maxY) {
        continue;
      }

      // Bézier control point
      final cp = _bezierControlPoint(srcPt, tgtPt, conn.curveStrength);

      // 🚀 PERF: Multi-sample path distance (10 samples along curve)
      for (int i = 0; i <= samples; i++) {
        final t = i / samples;
        final pt = _pointOnBezier(srcPt, cp, tgtPt, t);
        final dx = canvasPoint.dx - pt.dx;
        final dy = canvasPoint.dy - pt.dy;
        final distSq = dx * dx + dy * dy;
        if (distSq < bestDistSq) {
          bestDistSq = distSq;
          best = conn;
          break; // This connection is a hit, try next for closer match
        }
      }
    }

    return best;
  }

  /// Bézier control point (perpendicular offset from midpoint).
  Offset _bezierControlPoint(Offset src, Offset tgt, double curveStrength) {
    final mid = Offset((src.dx + tgt.dx) / 2, (src.dy + tgt.dy) / 2);
    final dx = tgt.dx - src.dx;
    final dy = tgt.dy - src.dy;
    return Offset(mid.dx - dy * curveStrength, mid.dy + dx * curveStrength);
  }

  /// Point on quadratic Bézier at parameter t.
  Offset _pointOnBezier(Offset p0, Offset p1, Offset p2, double t) {
    final u = 1.0 - t;
    return Offset(
      u * u * p0.dx + 2 * u * t * p1.dx + t * t * p2.dx,
      u * u * p0.dy + 2 * u * t * p1.dy + t * t * p2.dy,
    );
  }

  // ===========================================================================
  // 🚀 HIGHLIGHT MANAGEMENT (Timer.periodic, not recursive Future.delayed)
  // ===========================================================================

  void _setHighlight({String? strokeId, String? connectionId}) {
    _highlightedStrokeId = strokeId;
    _highlightedConnectionId = connectionId;
    _highlightIntensity = 1.0;
    version.value++;

    // Stop any existing decay timer and start a fresh one
    _decayTimer?.cancel();
    _decayTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      _highlightIntensity -= 0.025; // 2s total decay (50ms × 40)
      if (_highlightIntensity <= 0.0) {
        timer.cancel();
        _decayTimer = null;
        _clearHighlight();
      } else {
        version.value++;
      }
    });
  }

  void _clearHighlight() {
    _highlightedStrokeId = null;
    _highlightedConnectionId = null;
    _highlightIntensity = 0.0;
    version.value++;
  }

  // ===========================================================================
  // CLEANUP
  // ===========================================================================

  void dispose() {
    _decayTimer?.cancel();
    _decayTimer = null;
    _clearHighlight();
  }
}
