// ============================================================================
// 🛡️ P2P PRIVACY GUARD — Selective canvas area hiding (A4-07/09, P7-31)
//
// Manages the "hidden areas" that the local student defines.
// These areas appear as opaque black blocks in the canvas raster
// sent to the peer (A4-09).
//
// Privacy rules:
//   - The student can hide ANY area at any time (P7-31)
//   - Hidden areas are rendered BLACK in the raster stream
//   - The peer cannot see the underlying content
//   - Hidden areas are NOT persistent — they exist only during the session
//   - No content data (ink, text, images) is ever transmitted — only
//     the raster image (A4-07, A4-08)
//
// ARCHITECTURE: Pure model — no rendering code.
// THREAD SAFETY: Main isolate only.
// ============================================================================

import 'p2p_session_controller.dart';
import 'p2p_message_types.dart';

/// 🛡️ P2P Privacy Guard (A4-09, P7-31).
///
/// Manages hidden areas that the local student defines to prevent
/// the peer from seeing certain parts of the canvas.
///
/// Usage:
/// ```dart
/// final guard = P2PPrivacyGuard();
///
/// // Student selects an area to hide
/// guard.addHiddenArea(P2PRect(left: 100, top: 200, width: 300, height: 150));
///
/// // Before rasterizing the canvas for the peer:
/// for (final rect in guard.hiddenAreas) {
///   canvas.drawRect(rect.toRect(), blackPaint);
/// }
///
/// // Send hidden areas to peer (so they know what's blocked)
/// final message = guard.toMessage();
/// transport.send(message);
/// ```
class P2PPrivacyGuard {
  /// Local hidden areas (what WE are hiding from the peer).
  final List<P2PRect> _localHiddenAreas = [];
  List<P2PRect> get localHiddenAreas => List.unmodifiable(_localHiddenAreas);

  /// Remote hidden areas (what the PEER is hiding from us).
  final List<P2PRect> _remoteHiddenAreas = [];
  List<P2PRect> get remoteHiddenAreas => List.unmodifiable(_remoteHiddenAreas);

  /// Whether privacy guard is active (has any hidden areas).
  bool get isActive => _localHiddenAreas.isNotEmpty;

  /// Number of hidden areas.
  int get localCount => _localHiddenAreas.length;
  int get remoteCount => _remoteHiddenAreas.length;

  // ── Local Operations ───────────────────────────────────────────────

  /// Add a hidden area.
  void addHiddenArea(P2PRect area) {
    _localHiddenAreas.add(area);
  }

  /// Remove a hidden area by index.
  void removeHiddenArea(int index) {
    if (index >= 0 && index < _localHiddenAreas.length) {
      _localHiddenAreas.removeAt(index);
    }
  }

  /// Replace all hidden areas.
  void setHiddenAreas(List<P2PRect> areas) {
    _localHiddenAreas
      ..clear()
      ..addAll(areas);
  }

  /// Clear all local hidden areas.
  void clearLocalHiddenAreas() {
    _localHiddenAreas.clear();
  }

  // ── Remote Operations ──────────────────────────────────────────────

  /// Process incoming hidden areas message from peer.
  void receiveHiddenAreas(P2PMessage message) {
    final rects = (message.payload['rects'] as List?)
            ?.cast<Map<String, dynamic>>()
            .map(P2PRect.fromJson)
            .toList() ??
        [];
    _remoteHiddenAreas
      ..clear()
      ..addAll(rects);
  }

  // ── Serialization ──────────────────────────────────────────────────

  /// Create a message to send local hidden areas to the peer.
  P2PMessage toMessage() => P2PMessages.hiddenAreas(
        rects: _localHiddenAreas.map((r) => r.toJson()).toList(),
      );

  // ── Raster Validation ──────────────────────────────────────────────

  /// Check if a point is inside any local hidden area.
  ///
  /// Use this to validate that the raster pipeline correctly blacks out
  /// hidden content before transmission.
  bool isPointHidden(double x, double y) {
    for (final area in _localHiddenAreas) {
      if (x >= area.left &&
          x <= area.left + area.width &&
          y >= area.top &&
          y <= area.top + area.height) {
        return true;
      }
    }
    return false;
  }

  /// Check if a rect overlaps any local hidden area.
  bool isRectOverlappingHidden(P2PRect rect) {
    for (final area in _localHiddenAreas) {
      if (rect.left < area.left + area.width &&
          rect.left + rect.width > area.left &&
          rect.top < area.top + area.height &&
          rect.top + rect.height > area.top) {
        return true;
      }
    }
    return false;
  }

  /// Reset all state (on session end).
  void reset() {
    _localHiddenAreas.clear();
    _remoteHiddenAreas.clear();
  }
}
