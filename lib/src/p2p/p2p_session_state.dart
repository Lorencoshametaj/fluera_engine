// ============================================================================
// 🤝 P2P SESSION STATE — Finite State Machine for peer connections (A4)
//
// Specifica: A4-01 → A4-09, P7-01 → P7-04
//
// Models the lifecycle of a P2P session between two students:
//   idle → creating → waitingForPeer → signaling → connecting →
//   connected → [mode7a | mode7b | mode7c] → disconnecting → ended
//
// Pure model — no WebRTC, no network, no platform dependencies.
// Fully serializable for state persistence.
//
// THREAD SAFETY: Main isolate only.
// ============================================================================

/// 🤝 P2P session lifecycle states.
enum P2PSessionPhase {
  /// No session active. Entry point.
  idle,

  /// Student A created a room and is generating the invite link/QR.
  creating,

  /// Room created, waiting for Student B to join via link/QR.
  waitingForPeer,

  /// Both students present. Exchanging ICE offer/answer via signaling.
  signaling,

  /// ICE exchange complete. WebRTC P2P connection establishing.
  connecting,

  /// P2P connection established. Ready to select a mode.
  connected,

  /// Active in Mode 7a: Read-only visit.
  mode7a,

  /// Active in Mode 7b: Teaching reciprocal (Protégé Effect).
  mode7b,

  /// Active in Mode 7c: Recall duel.
  mode7c,

  /// Graceful disconnection in progress.
  disconnecting,

  /// Session ended (graceful or timeout).
  ended,

  /// Connection lost, attempting reconnection.
  reconnecting,

  /// Permanent error (auth failure, incompatible versions, etc).
  error,
}

/// 🤝 Role of the local student in the session.
enum P2PRole {
  /// Student who created the session (offer-side).
  host,

  /// Student who joined via invite (answer-side).
  guest,
}

/// 🤝 Passo 7 collaboration modes.
enum P2PCollabMode {
  /// 7a: Read-only visit — observe the other's canvas.
  visit,

  /// 7b: Teaching reciprocal — voice + follow + laser pointer.
  teaching,

  /// 7c: Recall duel — simultaneous recall, then split-view.
  duel,
}

/// 🤝 Recall duel sub-phases (7c).
enum DuelPhase {
  /// Countdown ("3... 2... 1... Via!")
  countdown,

  /// Both students are recalling (isolated canvases).
  recalling,

  /// One student finished, waiting for the other.
  waitingForOther,

  /// Both finished — showing split-view comparison.
  splitView,
}

/// 🤝 Teaching turn (7b).
enum TeachingTurn {
  /// Local student is teaching (navigating, voice, laser).
  localTeaching,

  /// Remote student is teaching (following, listening).
  remoteTeaching,
}

/// 🤝 Connection quality indicator.
enum P2PConnectionQuality {
  /// Excellent (≤50ms latency).
  excellent,

  /// Good (50-100ms latency).
  good,

  /// Degraded (100-300ms latency).
  degraded,

  /// Poor (>300ms or packet loss).
  poor,
}

/// 🤝 Disconnection reason.
enum P2PDisconnectReason {
  /// User chose to leave.
  localLeft,

  /// Remote peer left.
  remoteLeft,

  /// Network timeout (60s without reconnection).
  timeout,

  /// Version mismatch between peers.
  versionMismatch,

  /// Session expired.
  expired,

  /// Error during connection.
  error,
}

// =============================================================================
// STATE TRANSITIONS — Valid transitions matrix
// =============================================================================

/// 🤝 Validates state transitions.
///
/// Returns true if transitioning from [from] to [to] is valid.
/// Invalid transitions are programming errors and should be caught.
bool isValidP2PTransition(P2PSessionPhase from, P2PSessionPhase to) {
  return _validTransitions[from]?.contains(to) ?? false;
}

const Map<P2PSessionPhase, Set<P2PSessionPhase>> _validTransitions = {
  P2PSessionPhase.idle: {
    P2PSessionPhase.creating,
    P2PSessionPhase.signaling, // Guest joins directly
  },
  P2PSessionPhase.creating: {
    P2PSessionPhase.waitingForPeer,
    P2PSessionPhase.error,
  },
  P2PSessionPhase.waitingForPeer: {
    P2PSessionPhase.signaling,
    P2PSessionPhase.disconnecting, // Host cancels
    P2PSessionPhase.error,
  },
  P2PSessionPhase.signaling: {
    P2PSessionPhase.connecting,
    P2PSessionPhase.error,
  },
  P2PSessionPhase.connecting: {
    P2PSessionPhase.connected,
    P2PSessionPhase.error,
  },
  P2PSessionPhase.connected: {
    P2PSessionPhase.mode7a,
    P2PSessionPhase.mode7b,
    P2PSessionPhase.mode7c,
    P2PSessionPhase.disconnecting,
    P2PSessionPhase.reconnecting,
  },
  P2PSessionPhase.mode7a: {
    P2PSessionPhase.connected, // Return to mode selection
    P2PSessionPhase.disconnecting,
    P2PSessionPhase.reconnecting,
  },
  P2PSessionPhase.mode7b: {
    P2PSessionPhase.connected,
    P2PSessionPhase.disconnecting,
    P2PSessionPhase.reconnecting,
  },
  P2PSessionPhase.mode7c: {
    P2PSessionPhase.connected,
    P2PSessionPhase.disconnecting,
    P2PSessionPhase.reconnecting,
  },
  P2PSessionPhase.disconnecting: {
    P2PSessionPhase.ended,
  },
  P2PSessionPhase.reconnecting: {
    P2PSessionPhase.connected,
    P2PSessionPhase.mode7a, // Reconnect to active mode
    P2PSessionPhase.mode7b,
    P2PSessionPhase.mode7c,
    P2PSessionPhase.disconnecting, // Timeout
    P2PSessionPhase.error,
  },
  P2PSessionPhase.ended: {
    P2PSessionPhase.idle, // Reset for new session
  },
  P2PSessionPhase.error: {
    P2PSessionPhase.idle, // Reset
    P2PSessionPhase.ended,
  },
};
