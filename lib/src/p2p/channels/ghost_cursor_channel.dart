// ============================================================================
// 👻 GHOST CURSOR CHANNEL — Peer cursor position sync (A4-03, P7-05)
//
// Manages ghost cursor transmission and reception:
//   - Outgoing: throttled to 15fps (66ms), interpolated
//   - Incoming: smoothed via linear interpolation for visual continuity
//
// The ghost cursor shows where the peer is looking/working on their canvas.
// Rendered as a semi-transparent circle (30% opacity, P7-05).
//
// ARCHITECTURE: Pure model — no UI, no network code.
// THREAD SAFETY: Main isolate only.
// ============================================================================

import '../p2p_message_types.dart';

/// 👻 Outgoing ghost cursor state.
///
/// Manages throttling and dirty detection for cursor broadcasts.
class GhostCursorSender {
  /// Target frame rate for cursor updates (A4-03: 15fps).
  static const int targetFps = 15;

  /// Minimum interval between frames (ms).
  static const int frameIntervalMs = 1000 ~/ targetFps; // 66ms

  /// Last broadcast timestamp.
  int _lastBroadcastMs = 0;

  /// Last sent position.
  double _lastX = 0;
  double _lastY = 0;
  double _lastZoom = 1.0;
  bool _lastDrawing = false;

  /// Minimum movement threshold to trigger an update (canvas units).
  /// Below this, the cursor is considered "still" and no update is sent.
  static const double movementThreshold = 2.0;

  /// Check if a cursor update should be sent.
  ///
  /// Returns a [P2PMessage] if an update is needed, null otherwise.
  /// Call this on every pointer move — the method handles throttling.
  P2PMessage? maybeSend({
    required double x,
    required double y,
    required double zoom,
    bool isDrawing = false,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;

    // Throttle to target fps.
    if (now - _lastBroadcastMs < frameIntervalMs) return null;

    // Skip if position hasn't changed meaningfully.
    final dx = (x - _lastX).abs();
    final dy = (y - _lastY).abs();
    final stateChanged = isDrawing != _lastDrawing;

    if (dx < movementThreshold &&
        dy < movementThreshold &&
        !stateChanged) {
      return null;
    }

    // Send update.
    _lastBroadcastMs = now;
    _lastX = x;
    _lastY = y;
    _lastZoom = zoom;
    _lastDrawing = isDrawing;

    return P2PMessages.cursor(
      x: x,
      y: y,
      zoom: zoom,
      isDrawing: isDrawing,
    );
  }

  /// Force send (e.g., on mode enter/exit).
  P2PMessage forceSend({
    required double x,
    required double y,
    required double zoom,
    bool isDrawing = false,
  }) {
    _lastBroadcastMs = DateTime.now().millisecondsSinceEpoch;
    _lastX = x;
    _lastY = y;
    _lastZoom = zoom;
    _lastDrawing = isDrawing;

    return P2PMessages.cursor(
      x: x,
      y: y,
      zoom: zoom,
      isDrawing: isDrawing,
    );
  }
}

/// 👻 Incoming ghost cursor state.
///
/// Manages interpolation for smooth visual rendering.
class GhostCursorReceiver {
  /// Current interpolated position.
  double x = 0;
  double y = 0;
  double zoom = 1.0;
  bool isDrawing = false;

  /// Target position (from latest received frame).
  double _targetX = 0;
  double _targetY = 0;
  double _targetZoom = 1.0;

  /// Interpolation factor (0.0–1.0, higher = snappier).
  static const double lerpFactor = 0.3;

  /// Last received timestamp (for stale detection).
  int lastReceivedMs = 0;

  /// Timeout before marking cursor as stale (ms).
  static const int staleTimeoutMs = 2000;

  /// Whether the cursor is stale (no updates for >2s).
  bool get isStale {
    if (lastReceivedMs == 0) return true;
    return DateTime.now().millisecondsSinceEpoch - lastReceivedMs >
        staleTimeoutMs;
  }

  /// Process an incoming cursor message.
  void receive(P2PMessage message) {
    final p = message.payload;
    _targetX = (p['x'] as num).toDouble();
    _targetY = (p['y'] as num).toDouble();
    _targetZoom = (p['z'] as num?)?.toDouble() ?? 1.0;
    isDrawing = p['d'] as bool? ?? false;
    lastReceivedMs = message.timestamp;
  }

  /// Interpolate toward target (call each paint frame).
  ///
  /// Returns true if position changed (needs repaint).
  bool interpolate() {
    final dx = (_targetX - x).abs();
    final dy = (_targetY - y).abs();

    if (dx < 0.5 && dy < 0.5) {
      x = _targetX;
      y = _targetY;
      zoom = _targetZoom;
      return false;
    }

    x += (_targetX - x) * lerpFactor;
    y += (_targetY - y) * lerpFactor;
    zoom += (_targetZoom - zoom) * lerpFactor;
    return true;
  }
}
