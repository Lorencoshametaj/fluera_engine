// ============================================================================
// ✨ LASER POINTER CHANNEL — Temporary luminous stroke for teaching (P7-15)
//
// The teacher can draw temporary luminous strokes that:
//   - Glow yellow (bright, semi-transparent)
//   - Disappear after 2 seconds (P7-15)
//   - Are NOT saved to the canvas
//   - Are transmitted to the peer at 30fps during active use
//
// ARCHITECTURE: Pure model — no rendering, no platform dependencies.
// THREAD SAFETY: Main isolate only.
// ============================================================================

import '../p2p_message_types.dart';

/// ✨ A single laser pointer stroke segment.
class LaserSegment {
  /// Points (interleaved x,y pairs: [x0,y0, x1,y1, ...]).
  final List<double> points;

  /// Creation time (for expiry calculation).
  final int createdAtMs;

  LaserSegment({
    required this.points,
    required this.createdAtMs,
  });
}

/// ✨ Laser Pointer Sender (P7-15).
///
/// Manages outgoing laser pointer strokes during teaching mode.
class LaserPointerSender {
  /// Target frame rate for laser updates (30fps during active use).
  static const int targetFps = 30;

  /// Frame interval (ms).
  static const int frameIntervalMs = 1000 ~/ targetFps; // ~33ms

  /// Last broadcast timestamp.
  int _lastBroadcastMs = 0;

  /// Current stroke points being built.
  final List<double> _currentPoints = [];

  /// Whether currently drawing a laser stroke.
  bool _isActive = false;
  bool get isActive => _isActive;

  /// Begin a laser stroke.
  void beginStroke(double x, double y) {
    _isActive = true;
    _currentPoints.clear();
    _currentPoints.addAll([x, y]);
  }

  /// Add a point to the current stroke.
  ///
  /// Returns a [P2PMessage] if a frame should be sent, null if throttled.
  P2PMessage? addPoint(double x, double y) {
    if (!_isActive) return null;
    _currentPoints.addAll([x, y]);

    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastBroadcastMs < frameIntervalMs) return null;

    _lastBroadcastMs = now;
    return P2PMessages.laser(points: List<double>.from(_currentPoints));
  }

  /// End the current stroke.
  ///
  /// Returns the final message to send.
  P2PMessage? endStroke() {
    if (!_isActive) return null;
    _isActive = false;

    if (_currentPoints.isEmpty) return null;
    final msg = P2PMessages.laser(points: List<double>.from(_currentPoints));
    _currentPoints.clear();
    return msg;
  }
}

/// ✨ Laser Pointer Receiver (P7-15).
///
/// Manages incoming laser pointer strokes with auto-expiry.
class LaserPointerReceiver {
  /// Lifetime of a laser segment (ms) before fading out.
  static const int segmentLifetimeMs = 2000;

  /// Active laser segments (with creation time).
  final List<LaserSegment> _segments = [];
  List<LaserSegment> get segments => List.unmodifiable(_segments);

  /// Whether there are any visible laser segments.
  bool get hasVisibleSegments => _segments.isNotEmpty;

  /// Process an incoming laser message.
  void receive(P2PMessage message) {
    final points = (message.payload['pts'] as List)
        .map((e) => (e as num).toDouble())
        .toList();

    _segments.add(LaserSegment(
      points: points,
      createdAtMs: message.timestamp,
    ));
  }

  /// Remove expired segments. Call periodically (e.g., each paint frame).
  ///
  /// Returns true if any segments were removed (needs repaint).
  bool pruneExpired() {
    final cutoff =
        DateTime.now().millisecondsSinceEpoch - segmentLifetimeMs;
    final before = _segments.length;
    _segments.removeWhere((s) => s.createdAtMs < cutoff);
    return _segments.length != before;
  }

  /// Get the opacity for a segment based on its age (0.0 – 1.0).
  ///
  /// Segments fade out linearly over their lifetime.
  double getSegmentOpacity(LaserSegment segment) {
    final age =
        DateTime.now().millisecondsSinceEpoch - segment.createdAtMs;
    if (age >= segmentLifetimeMs) return 0.0;
    return 1.0 - (age / segmentLifetimeMs);
  }

  /// Clear all segments.
  void clear() {
    _segments.clear();
  }
}
