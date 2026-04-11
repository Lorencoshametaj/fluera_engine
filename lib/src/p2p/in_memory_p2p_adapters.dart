// ============================================================================
// 🧪 IN-MEMORY P2P ADAPTERS — Zero-config testing & demos (A4)
//
// Drop-in implementations of P2PTransport and P2PSignalingService that work
// entirely in memory — no WebRTC, no Supabase, no network required.
//
// Two usage patterns:
//   1. LOOPBACK — Single device, messages echo back (for UI testing)
//   2. PAIRED — Two transports connected together (for unit tests)
//
// Usage:
// ```dart
// // Loopback (single device demo)
// final transport = InMemoryP2PTransport();
// engine.attachTransport(transport);
//
// // Paired (unit tests)
// final pair = InMemoryP2PTransport.createPair();
// engineA.attachTransport(pair.first);
// engineB.attachTransport(pair.second);
// ```
//
// ARCHITECTURE: Pure model — for testing only.
// ============================================================================

import 'dart:async';
import 'p2p_session_controller.dart';
import 'p2p_message_types.dart';
import 'collab_invite_service.dart';

/// 🧪 In-memory P2P transport for testing.
///
/// Messages are delivered directly through StreamControllers.
class InMemoryP2PTransport implements P2PTransport {
  final StreamController<P2PMessage> _incomingController =
      StreamController<P2PMessage>.broadcast();

  /// Optional paired transport (for bidirectional testing).
  InMemoryP2PTransport? _peer;

  /// Optional artificial latency (ms).
  final int latencyMs;

  /// Whether this transport is connected.
  bool _connected = true;

  InMemoryP2PTransport({this.latencyMs = 0});

  /// Create a connected pair of transports.
  ///
  /// Messages sent by one are received by the other.
  static (InMemoryP2PTransport, InMemoryP2PTransport) createPair({
    int latencyMs = 0,
  }) {
    final a = InMemoryP2PTransport(latencyMs: latencyMs);
    final b = InMemoryP2PTransport(latencyMs: latencyMs);
    a._peer = b;
    b._peer = a;
    return (a, b);
  }

  @override
  Future<void> send(P2PMessage message) async {
    if (!_connected) return;

    if (latencyMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: latencyMs));
    }

    // Deliver to peer (or loopback if no peer).
    final target = _peer ?? this;
    if (!target._incomingController.isClosed) {
      target._incomingController.add(message);
    }
  }

  @override
  Stream<P2PMessage> get incoming => _incomingController.stream;

  @override
  Future<void> close() async {
    _connected = false;
    await _incomingController.close();
  }

  @override
  bool get isConnected => _connected && !_incomingController.isClosed;

  /// Inject a message as if received from peer (for testing).
  void injectMessage(P2PMessage message) {
    if (!_incomingController.isClosed) {
      _incomingController.add(message);
    }
  }

  /// Simulate connection loss.
  void simulateDisconnect() {
    _connected = false;
  }

  /// Simulate reconnection.
  void simulateReconnect() {
    _connected = true;
  }
}

/// 🧪 In-memory signaling service for testing.
///
/// Simulates Supabase Realtime Broadcast for ICE exchange.
class InMemoryP2PSignaling implements P2PSignalingService {
  final StreamController<Map<String, dynamic>> _signalController =
      StreamController<Map<String, dynamic>>.broadcast();

  /// Optional paired signaling (for bidirectional testing).
  InMemoryP2PSignaling? _peer;

  String? _roomId;

  InMemoryP2PSignaling();

  /// Create a connected pair of signaling services.
  static (InMemoryP2PSignaling, InMemoryP2PSignaling) createPair() {
    final a = InMemoryP2PSignaling();
    final b = InMemoryP2PSignaling();
    a._peer = b;
    b._peer = a;
    return (a, b);
  }

  @override
  Future<String> createRoom() async {
    _roomId = CollabInviteService.generateRoomId();
    return _roomId!;
  }

  @override
  Future<void> joinRoom(String roomId) async {
    _roomId = roomId;
  }

  @override
  Future<void> sendSignal(Map<String, dynamic> signal) async {
    final target = _peer ?? this;
    if (!target._signalController.isClosed) {
      target._signalController.add(signal);
    }
  }

  @override
  Stream<Map<String, dynamic>> get signals => _signalController.stream;

  @override
  Future<void> dispose() async {
    await _signalController.close();
  }

  /// The room ID (for assertions).
  String? get roomId => _roomId;
}
