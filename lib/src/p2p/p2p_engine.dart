// ============================================================================
// ⚙️ P2P ENGINE — Central orchestrator for peer-to-peer sessions (A4)
//
// Ties together all P2P components:
//   - P2PSessionController (FSM, state)
//   - GhostCursorSender/Receiver (15fps)
//   - ViewportSyncSender/Receiver (5fps)
//   - LaserPointerSender/Receiver (30fps, 2s expiry)
//   - VoiceChannelController (audio state)
//   - P2PPrivacyGuard (hidden areas)
//   - P2PTransport (abstract — host app provides implementation)
//
// The engine listens to the transport's incoming messages and dispatches
// them to the correct channel. It also coordinates outgoing messages.
//
// ARCHITECTURE:
//   Engine is internal to fluera_engine.
//   Transport + Signaling are injected by the host app.
//
// THREAD SAFETY: Main isolate only.
// ============================================================================

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'p2p_session_controller.dart';
import 'p2p_session_state.dart';
import 'p2p_message_types.dart';
import 'p2p_privacy_guard.dart';
import 'p2p_session_data.dart';
import 'channels/ghost_cursor_channel.dart';
import 'channels/viewport_sync_channel.dart';
import 'channels/laser_pointer_channel.dart';
import 'channels/voice_channel.dart';

/// ⚙️ P2P Engine (A4).
///
/// Central orchestrator that manages the full P2P session lifecycle,
/// dispatches messages to channels, and coordinates all subsystems.
///
/// Usage:
/// ```dart
/// final engine = P2PEngine(
///   localInfo: PeerInfo(displayName: 'Alice', ...),
/// );
///
/// // Host flow:
/// final roomId = await engine.createSession(signalingService);
/// // Share roomId → user joins → signaling completes
/// engine.attachTransport(webrtcTransport);
///
/// // Guest flow:
/// await engine.joinSession(signalingService, roomId);
/// engine.attachTransport(webrtcTransport);
///
/// // Use channels:
/// engine.sendCursorUpdate(x: 100, y: 200, zoom: 1.5);
/// engine.selectMode(P2PCollabMode.visit);
/// ```
class P2PEngine extends ChangeNotifier {
  /// Session controller (FSM + state).
  final P2PSessionController session;

  /// Ghost cursor channel.
  final GhostCursorSender cursorSender = GhostCursorSender();
  final GhostCursorReceiver cursorReceiver = GhostCursorReceiver();

  /// Viewport sync channel.
  final ViewportSyncSender viewportSender = ViewportSyncSender();
  final ViewportSyncReceiver viewportReceiver = ViewportSyncReceiver();

  /// Laser pointer channel (7b teaching).
  final LaserPointerSender laserSender = LaserPointerSender();
  final LaserPointerReceiver laserReceiver = LaserPointerReceiver();

  /// Voice channel (7b teaching).
  final VoiceChannelController voice = VoiceChannelController();

  /// Privacy guard (P7-31).
  final P2PPrivacyGuard privacyGuard = P2PPrivacyGuard();

  /// Session telemetry data.
  P2PSessionData? _sessionData;
  P2PSessionData? get sessionData => _sessionData;

  /// Active transport (set after WebRTC handshake).
  P2PTransport? _transport;
  StreamSubscription<P2PMessage>? _transportSubscription;

  /// Heartbeat timer.
  Timer? _heartbeatTimer;

  /// Whether the engine has been disposed.
  bool _disposed = false;

  P2PEngine({required PeerInfo localInfo})
      : session = P2PSessionController(localInfo: localInfo) {
    // Forward session notifications.
    session.addListener(_onSessionChanged);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SESSION LIFECYCLE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create a new session (host-side).
  Future<String> createSession(P2PSignalingService signaling) {
    return session.createSession(signaling);
  }

  /// Join an existing session (guest-side).
  Future<void> joinSession(
    P2PSignalingService signaling,
    String roomId,
  ) {
    return session.joinSession(signaling, roomId);
  }

  /// Attach a transport after WebRTC handshake completes.
  ///
  /// This starts listening for incoming messages and begins heartbeats.
  void attachTransport(P2PTransport transport) {
    _transport = transport;

    // Listen to incoming messages.
    _transportSubscription = transport.incoming.listen(
      _onMessage,
      onError: (_) => _onTransportError(),
      onDone: _onTransportClosed,
    );

    // Send peer info.
    _send(P2PMessages.peerInfo(
      displayName: session.localInfo.displayName,
      cursorColor: session.localInfo.cursorColor,
      engineVersion: session.localInfo.engineVersion,
      zoneId: session.localInfo.zoneId,
      zoneTopic: session.localInfo.zoneTopic,
    ));

    // Start heartbeat.
    _startHeartbeat();

    // Reset message sequence.
    P2PMessages.resetSequence();
  }

  /// Detach transport (cleanup).
  Future<void> detachTransport() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    await _transportSubscription?.cancel();
    _transportSubscription = null;
    await _transport?.close();
    _transport = null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MODE SELECTION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Select a collaboration mode and notify peer.
  void selectMode(P2PCollabMode mode) {
    session.selectMode(mode);
    _send(P2PMessages.modeSelect(mode: mode));

    // Initialize session data.
    _sessionData = P2PSessionData(
      sessionId: 'p7_${DateTime.now().millisecondsSinceEpoch}',
      startedAt: DateTime.now(),
      mode: mode,
      participants: [
        session.localInfo.displayName,
        session.remotePeer?.displayName ?? 'Peer',
      ],
      zoneId: session.localInfo.zoneId,
      visitData: mode == P2PCollabMode.visit ? VisitData() : null,
      teachingData: mode == P2PCollabMode.teaching ? TeachingData() : null,
      duelData: mode == P2PCollabMode.duel ? DuelData() : null,
    );

    // Mode-specific setup.
    if (mode == P2PCollabMode.teaching) {
      viewportReceiver.setFollowMode(
          session.teachingTurn != TeachingTurn.localTeaching);
    } else {
      viewportReceiver.setFollowMode(false);
    }
  }

  /// Exit the current mode.
  void exitMode() {
    _sessionData?.end();
    session.exitMode();
    viewportReceiver.setFollowMode(false);
    laserReceiver.clear();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CURSOR (15fps)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Send a cursor position update (throttled at 15fps).
  void sendCursorUpdate({
    required double x,
    required double y,
    required double zoom,
    bool isDrawing = false,
  }) {
    final msg = cursorSender.maybeSend(
      x: x, y: y, zoom: zoom, isDrawing: isDrawing);
    if (msg != null) _send(msg);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // VIEWPORT (5fps)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Send a viewport update (throttled at 5fps).
  void sendViewportUpdate({
    required double left,
    required double top,
    required double width,
    required double height,
    required double zoom,
  }) {
    final msg = viewportSender.maybeSend(
      left: left, top: top, width: width, height: height, zoom: zoom);
    if (msg != null) _send(msg);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LASER POINTER (P7-15)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Begin a laser pointer stroke.
  void beginLaser(double x, double y) {
    laserSender.beginStroke(x, y);
  }

  /// Continue a laser pointer stroke.
  void continueLaser(double x, double y) {
    final msg = laserSender.addPoint(x, y);
    if (msg != null) _send(msg);
  }

  /// End the laser pointer stroke.
  void endLaser() {
    final msg = laserSender.endStroke();
    if (msg != null) _send(msg);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MARKERS (P7-08)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Place a marker on the peer's canvas.
  void placeMarker({
    required String markerId,
    required double x,
    required double y,
    required String symbol,
    required int color,
  }) {
    _send(P2PMessages.marker(
      markerId: markerId, x: x, y: y, symbol: symbol, color: color));
  }

  /// Remove a marker.
  void removeMarker(String markerId) {
    _send(P2PMessages.markerRemove(markerId: markerId));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DUEL (7c)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Send the duel countdown tick (host sends to guest).
  void sendDuelCountdown(int secondsRemaining) {
    _send(P2PMessages.duelCountdown(secondsRemaining: secondsRemaining));
  }

  /// Signal that local student finished the recall.
  void finishDuel() {
    session.finishLocalDuel();
    _send(P2PMessages.duelFinished());
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TEACHING (7b)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Switch teaching turns and notify peer.
  void switchTeachingTurn() {
    session.switchTeachingTurn();
    _send(P2PMessages.teachingTurnSwitch(
      turn: session.teachingTurn ?? TeachingTurn.localTeaching));

    // Update follow mode: guest follows during remote teaching.
    viewportReceiver.setFollowMode(!session.isLocalTeaching);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PRIVACY (P7-31)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Update hidden areas and notify peer.
  void updateHiddenAreas(List<P2PRect> areas) {
    privacyGuard.setHiddenAreas(areas);
    session.setHiddenAreas(areas);
    _send(privacyGuard.toMessage());
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SESSION END
  // ═══════════════════════════════════════════════════════════════════════════

  /// End the session gracefully and notify peer.
  Future<void> endSession() async {
    _send(P2PMessages.sessionEnd());
    session.endSession(P2PDisconnectReason.localLeft);
    _sessionData?.end();
    await detachTransport();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INTERNAL: MESSAGE DISPATCH
  // ═══════════════════════════════════════════════════════════════════════════

  /// Send a message via transport.
  void _send(P2PMessage message) {
    _transport?.send(message);
  }

  /// Handle an incoming message.
  void _onMessage(P2PMessage message) {
    if (_disposed) return;

    // Let the session controller handle control messages.
    if (session.handleMessage(message)) {
      notifyListeners();
      return;
    }

    // Dispatch data messages to channels.
    switch (message.type) {
      case P2PMessageType.cursor:
        cursorReceiver.receive(message);
        notifyListeners();
        break;

      case P2PMessageType.viewport:
        viewportReceiver.receive(message);
        notifyListeners();
        break;

      case P2PMessageType.laser:
        laserReceiver.receive(message);
        notifyListeners();
        break;

      case P2PMessageType.hiddenAreas:
        privacyGuard.receiveHiddenAreas(message);
        notifyListeners();
        break;

      default:
        break;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INTERNAL: HEARTBEAT
  // ═══════════════════════════════════════════════════════════════════════════

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      Duration(milliseconds: P2PSessionController.heartbeatIntervalMs),
      (_) {
        if (_disposed) return;
        _send(P2PMessages.heartbeat());

        // Check for stale peer.
        if (session.isPeerStale &&
            session.phase != P2PSessionPhase.reconnecting &&
            session.phase != P2PSessionPhase.ended) {
          session.onConnectionLost();
          notifyListeners();
        }
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INTERNAL: TRANSPORT EVENTS
  // ═══════════════════════════════════════════════════════════════════════════

  void _onTransportError() {
    if (_disposed) return;
    if (session.phase != P2PSessionPhase.ended &&
        session.phase != P2PSessionPhase.disconnecting) {
      session.onConnectionLost();
      notifyListeners();
    }
  }

  void _onTransportClosed() {
    if (_disposed) return;
    if (session.phase != P2PSessionPhase.ended &&
        session.phase != P2PSessionPhase.disconnecting) {
      session.endSession(P2PDisconnectReason.remoteLeft);
      notifyListeners();
    }
  }

  void _onSessionChanged() {
    if (!_disposed) notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DISPOSE
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  void dispose() {
    _disposed = true;
    _heartbeatTimer?.cancel();
    _transportSubscription?.cancel();
    session.removeListener(_onSessionChanged);
    session.dispose();
    voice.dispose();
    privacyGuard.reset();
    super.dispose();
  }
}
