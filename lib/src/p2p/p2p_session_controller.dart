// ============================================================================
// 🤝 P2P SESSION CONTROLLER — Orchestrates peer session lifecycle (A4)
//
// Specifica: A4-01 → A4-09, P7-01 → P7-34
//
// Central controller for a P2P collaboration session.
// Manages the FSM, validates transitions, tracks peer info,
// handles reconnection logic, and coordinates mode-specific state.
//
// ARCHITECTURE:
//   Pure model — no WebRTC, no UI, no platform dependencies.
//   The host app provides a P2PTransport abstraction that this
//   controller drives.
//
// THREAD SAFETY: Main isolate only.
// ============================================================================

import 'package:flutter/foundation.dart';
import 'p2p_session_state.dart';
import 'p2p_message_types.dart';

/// 🤝 Abstract P2P transport layer.
///
/// Implemented by the host app using flutter_webrtc or similar.
/// This controller drives the transport, not the other way around.
abstract class P2PTransport {
  /// Send a message to the remote peer.
  Future<void> send(P2PMessage message);

  /// Stream of incoming messages from the remote peer.
  Stream<P2PMessage> get incoming;

  /// Close the connection.
  Future<void> close();

  /// Whether the transport is currently connected.
  bool get isConnected;
}

/// 🤝 Abstract signaling service.
///
/// Implemented by the host app using Supabase Realtime Broadcast.
/// Used only during handshake — discarded after P2P is established.
abstract class P2PSignalingService {
  /// Create a room and return the room ID.
  Future<String> createRoom();

  /// Join an existing room.
  Future<void> joinRoom(String roomId);

  /// Send a signaling message (ICE offer/answer/candidate).
  Future<void> sendSignal(Map<String, dynamic> signal);

  /// Stream of signaling messages from the other peer.
  Stream<Map<String, dynamic>> get signals;

  /// Clean up signaling resources.
  Future<void> dispose();
}

/// 🤝 Peer information (exchanged on connection).
class PeerInfo {
  final String displayName;
  final int cursorColor;
  final String engineVersion;
  final String zoneId;
  final String zoneTopic;

  const PeerInfo({
    required this.displayName,
    required this.cursorColor,
    required this.engineVersion,
    required this.zoneId,
    required this.zoneTopic,
  });

  factory PeerInfo.fromPayload(Map<String, dynamic> p) => PeerInfo(
        displayName: p['name'] as String? ?? 'Peer',
        cursorColor: p['color'] as int? ?? 0xFF42A5F5,
        engineVersion: p['ver'] as String? ?? '0.0.0',
        zoneId: p['zone'] as String? ?? '',
        zoneTopic: p['topic'] as String? ?? '',
      );
}

/// 🤝 P2P Session Controller (A4, P7).
///
/// Manages the complete lifecycle of a peer-to-peer session.
///
/// Usage:
/// ```dart
/// final controller = P2PSessionController(
///   localInfo: PeerInfo(displayName: 'Alice', ...),
/// );
///
/// // Host creates a session
/// final roomId = await controller.createSession(signalingService);
/// // Share roomId via link/QR
///
/// // Guest joins a session
/// await controller.joinSession(signalingService, roomId);
///
/// // Once connected
/// controller.selectMode(P2PCollabMode.visit); // Start 7a
///
/// // Listen to state changes
/// controller.addListener(() {
///   print('Phase: ${controller.phase}');
/// });
/// ```
class P2PSessionController extends ChangeNotifier {
  /// Local student info.
  final PeerInfo localInfo;

  /// Current session phase.
  P2PSessionPhase _phase = P2PSessionPhase.idle;
  P2PSessionPhase get phase => _phase;

  /// Local role (host or guest).
  P2PRole? _role;
  P2PRole? get role => _role;

  /// Remote peer info (available after connection).
  PeerInfo? _remotePeer;
  PeerInfo? get remotePeer => _remotePeer;

  /// Current collaboration mode (null if not in a mode).
  P2PCollabMode? _activeMode;
  P2PCollabMode? get activeMode => _activeMode;

  /// Room ID for the current session.
  String? _roomId;
  String? get roomId => _roomId;

  /// Connection quality.
  P2PConnectionQuality _connectionQuality = P2PConnectionQuality.excellent;
  P2PConnectionQuality get connectionQuality => _connectionQuality;

  /// Disconnect reason (set when session ends).
  P2PDisconnectReason? _disconnectReason;
  P2PDisconnectReason? get disconnectReason => _disconnectReason;

  /// Temporary markers placed by peer (P7-08, max 10).
  final List<P2PMarker> _markers = [];
  List<P2PMarker> get markers => List.unmodifiable(_markers);

  /// Hidden areas defined by local student (P7-31).
  final List<P2PRect> _hiddenAreas = [];
  List<P2PRect> get hiddenAreas => List.unmodifiable(_hiddenAreas);

  // ── Duel state (7c) ──────────────────────────────────────────────

  /// Current duel phase.
  DuelPhase? _duelPhase;
  DuelPhase? get duelPhase => _duelPhase;

  /// Whether the local student has finished recall (7c).
  bool _localDuelFinished = false;
  bool get localDuelFinished => _localDuelFinished;

  /// Whether the remote student has finished recall (7c).
  bool _remoteDuelFinished = false;
  bool get remoteDuelFinished => _remoteDuelFinished;

  // ── Teaching state (7b) ──────────────────────────────────────────

  /// Current teaching turn.
  TeachingTurn? _teachingTurn;
  TeachingTurn? get teachingTurn => _teachingTurn;

  // ── Reconnection ─────────────────────────────────────────────────

  /// Reconnection attempts counter.
  int _reconnectAttempts = 0;
  int get reconnectAttempts => _reconnectAttempts;

  /// Max reconnection window (seconds).
  static const int reconnectTimeoutSeconds = 60;

  /// Momentary disconnect threshold (seconds).
  static const int momentaryDisconnectSeconds = 10;

  /// Max reconnect attempts.
  static const int maxReconnectAttempts = 12;

  // ── Heartbeat ───────────────────────────────────────────────────

  /// Last heartbeat received from peer (epoch ms).
  int _lastPeerHeartbeat = 0;
  int get lastPeerHeartbeat => _lastPeerHeartbeat;

  /// Heartbeat interval (ms).
  static const int heartbeatIntervalMs = 3000;

  /// Heartbeat timeout (ms) — peer considered disconnected.
  static const int heartbeatTimeoutMs = 10000;

  P2PSessionController({required this.localInfo});

  // ─── State Transitions ───────────────────────────────────────────

  /// Transition to a new phase with validation.
  ///
  /// Throws [StateError] if the transition is invalid.
  void _transition(P2PSessionPhase to) {
    if (!isValidP2PTransition(_phase, to)) {
      throw StateError(
        'Invalid P2P transition: $_phase → $to',
      );
    }
    _phase = to;
    notifyListeners();
  }

  // ─── Session Lifecycle ───────────────────────────────────────────

  /// Create a new session (host-side).
  ///
  /// Returns the room ID for sharing via link/QR.
  Future<String> createSession(P2PSignalingService signaling) async {
    _transition(P2PSessionPhase.creating);
    _role = P2PRole.host;

    try {
      _roomId = await signaling.createRoom();
      _transition(P2PSessionPhase.waitingForPeer);
      return _roomId!;
    } catch (e) {
      _transition(P2PSessionPhase.error);
      rethrow;
    }
  }

  /// Join an existing session (guest-side).
  Future<void> joinSession(
    P2PSignalingService signaling,
    String roomId,
  ) async {
    _roomId = roomId;
    _role = P2PRole.guest;
    _transition(P2PSessionPhase.signaling);

    try {
      await signaling.joinRoom(roomId);
    } catch (e) {
      _transition(P2PSessionPhase.error);
      rethrow;
    }
  }

  /// Notify that signaling is complete and P2P connection is establishing.
  void onSignalingComplete() {
    _transition(P2PSessionPhase.connecting);
  }

  /// Notify that P2P connection is established.
  void onConnected(PeerInfo remotePeer) {
    _remotePeer = remotePeer;
    _lastPeerHeartbeat = DateTime.now().millisecondsSinceEpoch;
    _reconnectAttempts = 0;
    _transition(P2PSessionPhase.connected);
  }

  /// Notify that connection was lost.
  void onConnectionLost() {
    if (_phase == P2PSessionPhase.disconnecting ||
        _phase == P2PSessionPhase.ended) {
      return;
    }
    _transition(P2PSessionPhase.reconnecting);
  }

  /// Notify that reconnection succeeded.
  void onReconnected() {
    _reconnectAttempts = 0;
    _lastPeerHeartbeat = DateTime.now().millisecondsSinceEpoch;

    // Return to the mode that was active before disconnect.
    if (_activeMode != null) {
      final targetPhase = switch (_activeMode!) {
        P2PCollabMode.visit => P2PSessionPhase.mode7a,
        P2PCollabMode.teaching => P2PSessionPhase.mode7b,
        P2PCollabMode.duel => P2PSessionPhase.mode7c,
      };
      _transition(targetPhase);
    } else {
      _transition(P2PSessionPhase.connected);
    }
  }

  /// Increment reconnection counter.
  ///
  /// Returns true if we should keep trying, false if we've exceeded max.
  bool incrementReconnectAttempt() {
    _reconnectAttempts++;
    return _reconnectAttempts < maxReconnectAttempts;
  }

  // ─── Mode Selection ──────────────────────────────────────────────

  /// Select a collaboration mode.
  ///
  /// Can only be called when in [P2PSessionPhase.connected].
  void selectMode(P2PCollabMode mode) {
    _activeMode = mode;
    final targetPhase = switch (mode) {
      P2PCollabMode.visit => P2PSessionPhase.mode7a,
      P2PCollabMode.teaching => P2PSessionPhase.mode7b,
      P2PCollabMode.duel => P2PSessionPhase.mode7c,
    };
    _transition(targetPhase);

    // Initialize mode-specific state.
    if (mode == P2PCollabMode.duel) {
      _duelPhase = DuelPhase.countdown;
      _localDuelFinished = false;
      _remoteDuelFinished = false;
    } else if (mode == P2PCollabMode.teaching) {
      // Host teaches first by default.
      _teachingTurn = _role == P2PRole.host
          ? TeachingTurn.localTeaching
          : TeachingTurn.remoteTeaching;
    }
  }

  /// Return to mode selection (connected state).
  void exitMode() {
    _activeMode = null;
    _duelPhase = null;
    _teachingTurn = null;
    _transition(P2PSessionPhase.connected);
  }

  // ─── Duel Operations (7c) ────────────────────────────────────────

  /// Start the recall phase (after countdown).
  void startDuelRecall() {
    _duelPhase = DuelPhase.recalling;
    notifyListeners();
  }

  /// Mark local student as finished recalling.
  void finishLocalDuel() {
    _localDuelFinished = true;
    _duelPhase = _remoteDuelFinished
        ? DuelPhase.splitView
        : DuelPhase.waitingForOther;
    notifyListeners();
  }

  /// Mark remote student as finished recalling.
  void finishRemoteDuel() {
    _remoteDuelFinished = true;
    _duelPhase = _localDuelFinished
        ? DuelPhase.splitView
        : DuelPhase.waitingForOther;
    notifyListeners();
  }

  // ─── Teaching Operations (7b) ────────────────────────────────────

  /// Switch teaching turns.
  void switchTeachingTurn() {
    _teachingTurn = _teachingTurn == TeachingTurn.localTeaching
        ? TeachingTurn.remoteTeaching
        : TeachingTurn.localTeaching;
    notifyListeners();
  }

  /// Whether the local student is currently teaching.
  bool get isLocalTeaching => _teachingTurn == TeachingTurn.localTeaching;

  // ─── Markers (P7-08) ─────────────────────────────────────────────

  /// Max markers per session.
  static const int maxMarkers = 10;

  /// Add a marker from the peer.
  bool addMarker(P2PMarker marker) {
    if (_markers.length >= maxMarkers) return false;
    _markers.add(marker);
    notifyListeners();
    return true;
  }

  /// Remove a marker.
  void removeMarker(String markerId) {
    _markers.removeWhere((m) => m.id == markerId);
    notifyListeners();
  }

  /// Clear all markers (on session end).
  void clearMarkers() {
    _markers.clear();
    notifyListeners();
  }

  // ─── Privacy Guard (P7-31) ───────────────────────────────────────

  /// Set hidden areas (local student defines what the peer can't see).
  void setHiddenAreas(List<P2PRect> areas) {
    _hiddenAreas
      ..clear()
      ..addAll(areas);
    notifyListeners();
  }

  // ─── Heartbeat ───────────────────────────────────────────────────

  /// Process a heartbeat from the peer.
  void onPeerHeartbeat(int timestamp) {
    _lastPeerHeartbeat = timestamp;
  }

  /// Check if the peer is stale (no heartbeat for too long).
  bool get isPeerStale {
    if (_lastPeerHeartbeat == 0) return false;
    final elapsed =
        DateTime.now().millisecondsSinceEpoch - _lastPeerHeartbeat;
    return elapsed > heartbeatTimeoutMs;
  }

  // ─── Connection Quality ──────────────────────────────────────────

  /// Update connection quality based on measured latency.
  void updateConnectionQuality(int latencyMs) {
    final quality = switch (latencyMs) {
      <= 50 => P2PConnectionQuality.excellent,
      <= 100 => P2PConnectionQuality.good,
      <= 300 => P2PConnectionQuality.degraded,
      _ => P2PConnectionQuality.poor,
    };
    if (quality != _connectionQuality) {
      _connectionQuality = quality;
      notifyListeners();
    }
  }

  // ─── Session End ─────────────────────────────────────────────────

  /// @visibleForTesting — force phase for test setup (bypasses FSM).
  @visibleForTesting
  void setPhaseForTesting(P2PSessionPhase phase) {
    _phase = phase;
    notifyListeners();
  }

  /// End the session gracefully.
  void endSession(P2PDisconnectReason reason) {
    _disconnectReason = reason;
    if (_phase != P2PSessionPhase.ended &&
        _phase != P2PSessionPhase.disconnecting) {
      _transition(P2PSessionPhase.disconnecting);
    }
    _clearSessionState();
    _transition(P2PSessionPhase.ended);
  }

  /// Reset to idle for a new session.
  void reset() {
    _clearSessionState();
    _phase = P2PSessionPhase.idle;
    notifyListeners();
  }

  void _clearSessionState() {
    _markers.clear();
    _hiddenAreas.clear();
    _activeMode = null;
    _duelPhase = null;
    _teachingTurn = null;
    _localDuelFinished = false;
    _remoteDuelFinished = false;
    _reconnectAttempts = 0;
  }

  // ─── Message Handling ────────────────────────────────────────────

  /// Process an incoming P2P message.
  ///
  /// Returns true if the message was handled, false if unknown.
  bool handleMessage(P2PMessage message) {
    switch (message.type) {
      case P2PMessageType.heartbeat:
        onPeerHeartbeat(message.timestamp);
        return true;

      case P2PMessageType.peerInfo:
        _remotePeer = PeerInfo.fromPayload(message.payload);
        notifyListeners();
        return true;

      case P2PMessageType.modeSelect:
        final modeIndex = message.payload['mode'] as int;
        if (modeIndex >= 0 && modeIndex < P2PCollabMode.values.length) {
          selectMode(P2PCollabMode.values[modeIndex]);
        }
        return true;

      case P2PMessageType.duelCountdown:
        _duelPhase = DuelPhase.countdown;
        notifyListeners();
        return true;

      case P2PMessageType.duelFinished:
        finishRemoteDuel();
        return true;

      case P2PMessageType.teachingTurnSwitch:
        switchTeachingTurn();
        return true;

      case P2PMessageType.sessionEnd:
        endSession(P2PDisconnectReason.remoteLeft);
        return true;

      case P2PMessageType.marker:
        final p = message.payload;
        addMarker(P2PMarker(
          id: p['id'] as String,
          x: (p['x'] as num).toDouble(),
          y: (p['y'] as num).toDouble(),
          symbol: p['sym'] as String,
          color: p['c'] as int,
        ));
        return true;

      case P2PMessageType.markerRemove:
        removeMarker(message.payload['id'] as String);
        return true;

      case P2PMessageType.hiddenAreas:
        // Handled by P2PEngine → P2PPrivacyGuard (not session controller).
        return false;

      default:
        // cursor, viewport, laser — handled by channel processors.
        return false;
    }
  }
}

// =============================================================================
// SUPPORTING DATA MODELS
// =============================================================================

/// 📌 A temporary marker placed on the peer's canvas (P7-08).
class P2PMarker {
  final String id;
  final double x;
  final double y;
  final String symbol; // '!' or '?'
  final int color;

  const P2PMarker({
    required this.id,
    required this.x,
    required this.y,
    required this.symbol,
    required this.color,
  });
}

/// 📐 A rectangle (for hidden areas, viewport, etc).
class P2PRect {
  final double left;
  final double top;
  final double width;
  final double height;

  const P2PRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  Map<String, double> toJson() => {
        'l': left,
        't': top,
        'w': width,
        'h': height,
      };

  factory P2PRect.fromJson(Map<String, dynamic> json) => P2PRect(
        left: (json['l'] as num).toDouble(),
        top: (json['t'] as num).toDouble(),
        width: (json['w'] as num).toDouble(),
        height: (json['h'] as num).toDouble(),
      );
}
