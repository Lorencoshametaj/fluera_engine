// ============================================================================
// 🖥️ VIEWPORT SYNC CHANNEL — Peer viewport synchronization (A4-03, P7-07)
//
// Manages viewport position broadcasting and reception:
//   - Outgoing: throttled to 5fps (200ms)
//   - Incoming: direct apply (no interpolation needed at 5fps)
//
// Two modes:
//   - INDEPENDENT (7a default): each peer navigates freely
//   - FOLLOW (7b teaching): guest follows host's viewport with 100ms delay
//
// ARCHITECTURE: Pure model — no UI, no platform dependencies.
// THREAD SAFETY: Main isolate only.
// ============================================================================

import '../p2p_message_types.dart';
import '../p2p_session_controller.dart';

/// 🖥️ Viewport sync mode.
enum ViewportSyncMode {
  /// Each peer navigates independently (default for 7a).
  independent,

  /// Guest follows host's viewport (used in 7b teaching, P7-13).
  follow,
}

/// 🖥️ Outgoing viewport state.
///
/// Manages throttling for viewport broadcasts (5fps).
class ViewportSyncSender {
  /// Target frame rate for viewport updates (A4-03: 5fps).
  static const int targetFps = 5;

  /// Minimum interval between frames (ms).
  static const int frameIntervalMs = 1000 ~/ targetFps; // 200ms

  /// Last broadcast timestamp.
  int _lastBroadcastMs = 0;

  /// Last sent values (for dirty detection).
  double _lastLeft = 0;
  double _lastTop = 0;
  double _lastWidth = 0;
  double _lastHeight = 0;
  double _lastZoom = 1.0;

  /// Minimum change threshold for zoom to trigger update.
  static const double zoomThreshold = 0.01;

  /// Minimum change threshold for position (canvas units).
  static const double positionThreshold = 5.0;

  /// Check if a viewport update should be sent.
  P2PMessage? maybeSend({
    required double left,
    required double top,
    required double width,
    required double height,
    required double zoom,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;

    // Throttle to target fps.
    if (now - _lastBroadcastMs < frameIntervalMs) return null;

    // Skip if viewport hasn't changed meaningfully.
    final dl = (left - _lastLeft).abs();
    final dt = (top - _lastTop).abs();
    final dz = (zoom - _lastZoom).abs();

    if (dl < positionThreshold &&
        dt < positionThreshold &&
        dz < zoomThreshold) {
      return null;
    }

    _lastBroadcastMs = now;
    _lastLeft = left;
    _lastTop = top;
    _lastWidth = width;
    _lastHeight = height;
    _lastZoom = zoom;

    return P2PMessages.viewport(
      left: left,
      top: top,
      width: width,
      height: height,
      zoom: zoom,
    );
  }
}

/// 🖥️ Incoming viewport state.
///
/// Stores the latest viewport received from the peer.
class ViewportSyncReceiver {
  /// Current sync mode.
  ViewportSyncMode mode = ViewportSyncMode.independent;

  /// Received viewport.
  P2PRect? lastViewport;

  /// Received zoom level.
  double lastZoom = 1.0;

  /// Last received timestamp.
  int lastReceivedMs = 0;

  /// Whether a new viewport is available (consumed by the rendering layer).
  bool _dirty = false;
  bool get hasPendingViewport => _dirty && mode == ViewportSyncMode.follow;

  /// Process an incoming viewport message.
  void receive(P2PMessage message) {
    final p = message.payload;
    lastViewport = P2PRect(
      left: (p['l'] as num).toDouble(),
      top: (p['t'] as num).toDouble(),
      width: (p['w'] as num).toDouble(),
      height: (p['h'] as num).toDouble(),
    );
    lastZoom = (p['z'] as num).toDouble();
    lastReceivedMs = message.timestamp;
    _dirty = true;
  }

  /// Consume the pending viewport (returns it and clears dirty flag).
  P2PRect? consumeViewport() {
    if (!_dirty || lastViewport == null) return null;
    _dirty = false;
    return lastViewport;
  }

  /// Toggle follow mode.
  void setFollowMode(bool follow) {
    mode = follow ? ViewportSyncMode.follow : ViewportSyncMode.independent;
  }
}
