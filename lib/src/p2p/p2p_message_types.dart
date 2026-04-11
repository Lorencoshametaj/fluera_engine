// ============================================================================
// 📡 P2P MESSAGE TYPES — Wire protocol for DataChannel messages (A4)
//
// Specifica: A4-02 → A4-04
//
// Defines the binary-efficient message format transmitted over
// WebRTC DataChannel between two peers.
//
// Design constraints:
//   - Ghost cursor frames: ≤1KB each, 15fps (A4-02, A4-03)
//   - Viewport sync frames: ≤500B each, 5fps (A4-03)
//   - Markers: ≤200B each, max 10 per session (P7-08)
//   - Laser pointer: ≤300B each, 30fps during active use (P7-15)
//
// Serialization: JSON over DataChannel (text mode for debugging,
// binary mode for production — host app decides).
//
// ARCHITECTURE: Pure model — no WebRTC dependency.
// THREAD SAFETY: Main isolate only.
// ============================================================================

import 'p2p_session_state.dart';

/// 📡 Message type identifiers (short for bandwidth).
enum P2PMessageType {
  // ── Control messages ─────────────────────────────────────────────
  /// Session mode negotiation.
  modeSelect,

  /// Duel countdown sync.
  duelCountdown,

  /// Duel "I'm done" signal.
  duelFinished,

  /// Teaching turn switch.
  teachingTurnSwitch,

  /// Session end request.
  sessionEnd,

  /// Heartbeat / keepalive.
  heartbeat,

  /// Reconnection sync.
  reconnectSync,

  // ── Data messages ────────────────────────────────────────────────
  /// Ghost cursor position update (15fps).
  cursor,

  /// Viewport rect + zoom (5fps).
  viewport,

  /// Temporary marker placed on peer's canvas (P7-08).
  marker,

  /// Marker removed.
  markerRemove,

  /// Laser pointer path (P7-15, 30fps during use).
  laser,

  /// Privacy guard: hidden area definition (P7-31).
  hiddenAreas,

  // ── Metadata ─────────────────────────────────────────────────────
  /// Peer info exchange (display name, color, version).
  peerInfo,

  /// Zone/topic matching for mode 7b/7c (P7-03).
  zoneMatch,
}

/// 📡 A single P2P message.
///
/// Compact serialization for DataChannel transmission.
/// Uses short keys to minimize frame size.
class P2PMessage {
  /// Message type.
  final P2PMessageType type;

  /// Timestamp (epoch milliseconds, sender's clock).
  final int timestamp;

  /// Payload — type-specific data.
  final Map<String, dynamic> payload;

  /// Sequence number for ordering (monotonically increasing per sender).
  final int seq;

  const P2PMessage({
    required this.type,
    required this.timestamp,
    required this.payload,
    required this.seq,
  });

  /// Compact JSON for DataChannel (short keys).
  Map<String, dynamic> toJson() => {
        't': type.index,
        'ts': timestamp,
        'p': payload,
        's': seq,
      };

  factory P2PMessage.fromJson(Map<String, dynamic> json) => P2PMessage(
        type: P2PMessageType.values[json['t'] as int],
        timestamp: json['ts'] as int,
        payload: Map<String, dynamic>.from(json['p'] as Map),
        seq: json['s'] as int,
      );
}

// =============================================================================
// TYPED MESSAGE FACTORIES
// =============================================================================

/// 📡 Factory for creating typed P2P messages.
///
/// Provides type-safe constructors for each message type,
/// ensuring payload consistency.
class P2PMessages {
  P2PMessages._();

  static int _seq = 0;
  static int get _nextSeq => ++_seq;
  static void resetSequence() => _seq = 0;

  // ── Ghost Cursor (15fps, ≤1KB) ──────────────────────────────────────

  /// Create a ghost cursor position message.
  ///
  /// Payload: cursor position + optional drawing state.
  /// Target: 15fps, ≤1KB per frame (A4-03).
  static P2PMessage cursor({
    required double x,
    required double y,
    required double zoom,
    bool isDrawing = false,
  }) =>
      P2PMessage(
        type: P2PMessageType.cursor,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        seq: _nextSeq,
        payload: {
          'x': x,
          'y': y,
          'z': zoom,
          if (isDrawing) 'd': true,
        },
      );

  // ── Viewport Sync (5fps, ≤500B) ────────────────────────────────────

  /// Create a viewport sync message.
  ///
  /// Payload: viewport rect + zoom level.
  /// Target: 5fps (A4-03).
  static P2PMessage viewport({
    required double left,
    required double top,
    required double width,
    required double height,
    required double zoom,
  }) =>
      P2PMessage(
        type: P2PMessageType.viewport,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        seq: _nextSeq,
        payload: {
          'l': left,
          't': top,
          'w': width,
          'h': height,
          'z': zoom,
        },
      );

  // ── Markers (P7-08, max 10) ────────────────────────────────────────

  /// Create a temporary marker message.
  ///
  /// Markers are placed by the guest on the host's canvas.
  /// Max 10 per session, disappear when session ends.
  static P2PMessage marker({
    required String markerId,
    required double x,
    required double y,
    required String symbol, // '!' or '?'
    required int color,
  }) =>
      P2PMessage(
        type: P2PMessageType.marker,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        seq: _nextSeq,
        payload: {
          'id': markerId,
          'x': x,
          'y': y,
          'sym': symbol,
          'c': color,
        },
      );

  /// Remove a marker.
  static P2PMessage markerRemove({required String markerId}) => P2PMessage(
        type: P2PMessageType.markerRemove,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        seq: _nextSeq,
        payload: {'id': markerId},
      );

  // ── Laser Pointer (P7-15, 30fps during use) ────────────────────────

  /// Create a laser pointer path message.
  ///
  /// Laser: temporary luminous stroke that disappears after 2s.
  /// Only available during teaching mode (7b).
  static P2PMessage laser({
    required List<double> points, // [x1,y1, x2,y2, ...]
  }) =>
      P2PMessage(
        type: P2PMessageType.laser,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        seq: _nextSeq,
        payload: {'pts': points},
      );

  // ── Control Messages ───────────────────────────────────────────────

  /// Mode selection agreement.
  static P2PMessage modeSelect({required P2PCollabMode mode}) => P2PMessage(
        type: P2PMessageType.modeSelect,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        seq: _nextSeq,
        payload: {'mode': mode.index},
      );

  /// Duel countdown tick.
  static P2PMessage duelCountdown({required int secondsRemaining}) =>
      P2PMessage(
        type: P2PMessageType.duelCountdown,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        seq: _nextSeq,
        payload: {'sec': secondsRemaining},
      );

  /// Duel "I'm done" signal.
  static P2PMessage duelFinished() => P2PMessage(
        type: P2PMessageType.duelFinished,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        seq: _nextSeq,
        payload: const {},
      );

  /// Teaching turn switch.
  static P2PMessage teachingTurnSwitch({required TeachingTurn turn}) =>
      P2PMessage(
        type: P2PMessageType.teachingTurnSwitch,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        seq: _nextSeq,
        payload: {'turn': turn.index},
      );

  /// Session end request.
  static P2PMessage sessionEnd() => P2PMessage(
        type: P2PMessageType.sessionEnd,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        seq: _nextSeq,
        payload: const {},
      );

  /// Heartbeat / keepalive.
  static P2PMessage heartbeat() => P2PMessage(
        type: P2PMessageType.heartbeat,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        seq: _nextSeq,
        payload: const {},
      );

  // ── Peer Info ────────────────────────────────────────────────────────

  /// Peer info exchange (sent on connection established).
  static P2PMessage peerInfo({
    required String displayName,
    required int cursorColor,
    required String engineVersion,
    required String zoneId,
    required String zoneTopic,
  }) =>
      P2PMessage(
        type: P2PMessageType.peerInfo,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        seq: _nextSeq,
        payload: {
          'name': displayName,
          'color': cursorColor,
          'ver': engineVersion,
          'zone': zoneId,
          'topic': zoneTopic,
        },
      );

  // ── Privacy Guard (P7-31) ──────────────────────────────────────────

  /// Hidden areas definition — sent to peer so they black out those rects.
  static P2PMessage hiddenAreas({
    required List<Map<String, double>> rects, // [{l,t,w,h}, ...]
  }) =>
      P2PMessage(
        type: P2PMessageType.hiddenAreas,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        seq: _nextSeq,
        payload: {'rects': rects},
      );

  // ── Zone Matching (P7-03) ──────────────────────────────────────────

  /// Zone/topic match request for modes 7b and 7c.
  static P2PMessage zoneMatch({
    required String zoneId,
    required String topic,
    required List<String> completedSteps,
  }) =>
      P2PMessage(
        type: P2PMessageType.zoneMatch,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        seq: _nextSeq,
        payload: {
          'zone': zoneId,
          'topic': topic,
          'steps': completedSteps,
        },
      );
}
