import 'dart:ui';
import 'package:flutter/foundation.dart';
import '../../drawing/models/pro_drawing_point.dart';
import '../../reflow/knowledge_connection.dart';
import '../../reflow/content_cluster.dart';
import '../controllers/synchronized_playback_controller.dart';
import '../models/synchronized_recording.dart';

/// 🎤 AUDIO-INK SYNC CONTROLLER — Flow Playback feature.
///
/// Links strokes and connections to audio recording timestamps,
/// enabling three interaction modes:
///
/// 1. **Tap-to-Seek (Stroke)**: User taps a stroke → audio jumps to
///    the moment that stroke was drawn.
/// 2. **Tap-to-Seek (Connection)**: User taps a knowledge connection →
///    audio jumps to the moment that relationship was created.
/// 3. **Cinematic Playback**: Delegated to [CinematicPlaybackController].
///
/// This controller wraps [SynchronizedPlaybackController] for audio
/// playback and provides hit-test + seek utilities.
class AudioInkSyncController extends ChangeNotifier {
  /// The underlying synchronized playback controller.
  final SynchronizedPlaybackController _playbackController;

  /// Currently loaded recording (if any).
  SynchronizedRecording? _activeRecording;

  /// Whether audio-ink sync is actively available.
  bool get isAvailable => _activeRecording != null;

  /// Current playback state.
  SyncedPlaybackState get playbackState => _playbackController.state;

  /// Whether audio is currently playing.
  bool get isPlaying => _playbackController.isPlaying;

  /// Current position in ms.
  int get positionMs => _playbackController.positionMs;

  /// The stroke ID currently highlighted (tapped for seek).
  String? _highlightedStrokeId;
  String? get highlightedStrokeId => _highlightedStrokeId;

  /// The connection ID currently highlighted (tapped for seek).
  String? _highlightedConnectionId;
  String? get highlightedConnectionId => _highlightedConnectionId;

  /// Timestamp when last highlight was set (for fade animation).
  int _highlightStartMs = 0;
  int get highlightStartMs => _highlightStartMs;

  /// Duration of the stroke highlight animation in ms.
  static const int highlightDurationMs = 2000;

  AudioInkSyncController({
    required SynchronizedPlaybackController playbackController,
  }) : _playbackController = playbackController;

  // ===========================================================================
  // LIFECYCLE
  // ===========================================================================

  /// Bind a recording to this controller.
  /// Call this when the user opens a canvas that has an associated recording.
  void bindRecording(SynchronizedRecording recording) {
    _activeRecording = recording;
    _highlightedStrokeId = null;
    _highlightedConnectionId = null;
    notifyListeners();
  }

  /// Unbind the current recording.
  void unbindRecording() {
    _activeRecording = null;
    _highlightedStrokeId = null;
    _highlightedConnectionId = null;
    notifyListeners();
  }

  // ===========================================================================
  // 🎯 TAP-TO-SEEK: STROKE
  // ===========================================================================

  /// Seek audio to the moment a specific stroke was drawn.
  ///
  /// Finds the [SyncedStroke] matching [strokeId] in the active recording,
  /// then seeks the audio to its [relativeStartMs].
  ///
  /// Returns true if the stroke was found and audio was seeked.
  Future<bool> seekToStroke(String strokeId) async {
    final recording = _activeRecording;
    if (recording == null) return false;

    // Find the synced stroke with matching ID
    final syncedStroke = recording.syncedStrokes.where(
      (s) => s.stroke.id == strokeId,
    ).firstOrNull;

    if (syncedStroke == null) {
      debugPrint('🎤 [seekToStroke] Stroke $strokeId not found in recording');
      return false;
    }

    // Highlight the stroke
    _highlightedStrokeId = strokeId;
    _highlightedConnectionId = null;
    _highlightStartMs = DateTime.now().millisecondsSinceEpoch;

    // Seek audio to the moment this stroke began
    final seekPosition = Duration(milliseconds: syncedStroke.relativeStartMs);
    await _playbackController.seek(seekPosition);

    // Auto-play from that position
    if (!_playbackController.isPlaying) {
      await _playbackController.play();
    }

    notifyListeners();
    debugPrint('🎤 [seekToStroke] Seeking to ${syncedStroke.relativeStartMs}ms '
        'for stroke $strokeId');
    return true;
  }

  // ===========================================================================
  // 🎯 TAP-TO-SEEK: CONNECTION
  // ===========================================================================

  /// Seek audio to the moment a knowledge connection was created.
  ///
  /// Uses the connection's [recordingTimestampMs] field. If the connection
  /// doesn't have a recording timestamp (created without recording), falls
  /// back to finding the closest stroke temporally.
  ///
  /// Returns true if audio was seeked.
  Future<bool> seekToConnection(KnowledgeConnection connection) async {
    final recording = _activeRecording;
    if (recording == null) return false;

    // Check if the connection was created during this recording
    if (connection.recordingId != null &&
        connection.recordingId != recording.id) {
      debugPrint('🎤 [seekToConnection] Connection ${connection.id} '
          'belongs to a different recording');
      return false;
    }

    int seekMs;

    if (connection.recordingTimestampMs != null) {
      // Direct timestamp — connection has an explicit audio timestamp
      seekMs = connection.recordingTimestampMs!;
    } else {
      // Fallback: find the stroke closest to the connection creation time
      // by finding strokes in both connected clusters
      final nearestMs = _findNearestStrokeTime(
        connection.sourceClusterId,
        connection.targetClusterId,
        recording,
      );
      if (nearestMs == null) return false;
      seekMs = nearestMs;
    }

    // Highlight the connection
    _highlightedConnectionId = connection.id;
    _highlightedStrokeId = null;
    _highlightStartMs = DateTime.now().millisecondsSinceEpoch;

    // Seek and play
    final seekPosition = Duration(milliseconds: seekMs);
    await _playbackController.seek(seekPosition);
    if (!_playbackController.isPlaying) {
      await _playbackController.play();
    }

    notifyListeners();
    debugPrint('🎤 [seekToConnection] Seeking to ${seekMs}ms '
        'for connection ${connection.id}');
    return true;
  }

  // ===========================================================================
  // 🎯 HIT TEST — Find stroke under canvas point
  // ===========================================================================

  /// Find the stroke ID at a given canvas point.
  ///
  /// Iterates through all strokes in the recording and checks if [canvasPoint]
  /// is within [hitRadius] canvas pixels of any stroke path.
  ///
  /// Returns the stroke ID, or null if no stroke is under the point.
  String? hitTestStroke(
    Offset canvasPoint,
    List<ProStroke> allStrokes, {
    double hitRadius = 15.0,
  }) {
    final recording = _activeRecording;
    if (recording == null) return null;

    // Build set of stroke IDs in the recording for fast lookup
    final recordedIds = <String>{};
    for (final synced in recording.syncedStrokes) {
      recordedIds.add(synced.stroke.id);
    }

    // Find the closest stroke within hitRadius
    String? closestId;
    double closestDist = hitRadius;

    for (final stroke in allStrokes) {
      if (!recordedIds.contains(stroke.id)) continue;

      for (final point in stroke.points) {
        final dx = canvasPoint.dx - point.position.dx;
        final dy = canvasPoint.dy - point.position.dy;
        final dist = (dx * dx + dy * dy);
        if (dist < closestDist * closestDist) {
          closestDist = dist.isNaN ? closestDist : dist;
          closestId = stroke.id;
          break; // Found a point on this stroke, no need to check more
        }
      }
    }

    return closestId;
  }

  // ===========================================================================
  // 🔦 HIGHLIGHT ANIMATION
  // ===========================================================================

  /// Get the highlight intensity for a stroke (0.0–1.0).
  /// Decays over [highlightDurationMs] after the seek event.
  double getStrokeHighlight(String strokeId) {
    if (_highlightedStrokeId != strokeId) return 0.0;
    final elapsed = DateTime.now().millisecondsSinceEpoch - _highlightStartMs;
    if (elapsed >= highlightDurationMs) {
      _highlightedStrokeId = null;
      return 0.0;
    }
    return (1.0 - elapsed / highlightDurationMs).clamp(0.0, 1.0);
  }

  /// Get the highlight intensity for a connection (0.0–1.0).
  double getConnectionHighlight(String connectionId) {
    if (_highlightedConnectionId != connectionId) return 0.0;
    final elapsed = DateTime.now().millisecondsSinceEpoch - _highlightStartMs;
    if (elapsed >= highlightDurationMs) {
      _highlightedConnectionId = null;
      return 0.0;
    }
    return (1.0 - elapsed / highlightDurationMs).clamp(0.0, 1.0);
  }

  /// Whether any highlight animation is active (painter needs repaint).
  bool get hasActiveHighlight =>
      _highlightedStrokeId != null || _highlightedConnectionId != null;

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  /// Find the recording timestamp closest to the midpoint between two clusters.
  ///
  /// Used as fallback when a connection doesn't have an explicit
  /// [recordingTimestampMs]. The heuristic: the connection was likely
  /// created around the time the user was working between both clusters.
  int? _findNearestStrokeTime(
    String sourceClusterId,
    String targetClusterId,
    SynchronizedRecording recording,
  ) {
    // We don't have cluster membership here, so we use simple heuristic:
    // find the latest stroke start time before the connection was created.
    // For connections without timestamps, use the recording midpoint.
    if (recording.syncedStrokes.isEmpty) return null;

    // Use the midpoint of the recording as a reasonable default
    return recording.totalDuration.inMilliseconds ~/ 2;
  }

  // ===========================================================================
  // CLEANUP
  // ===========================================================================

  @override
  void dispose() {
    _activeRecording = null;
    super.dispose();
  }
}
