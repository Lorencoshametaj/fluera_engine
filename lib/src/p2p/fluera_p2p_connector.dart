// ============================================================================
// 🔌 P2P CONNECTOR INTERFACE — Abstract API for P2P collaboration
//
// This interface lives in the engine so that FlueraCanvasConfig can
// accept any P2P implementation without depending on specific backends
// (Supabase, Firebase, etc.).
//
// The host app implements this with concrete signaling + transport.
// ============================================================================

import 'package:flutter/foundation.dart';
import 'p2p_engine.dart';
import 'p2p_session_state.dart';
import 'collab_invite_service.dart';

/// 🔌 Abstract P2P connector — injected into FlueraCanvasConfig.
///
/// The host app provides a concrete implementation (e.g. `P2PConnector`)
/// that bridges signaling (Supabase/Firebase) and transport (WebRTC).
///
/// Usage (host app):
/// ```dart
/// class MyP2PConnector extends FlueraP2PConnector { ... }
///
/// FlueraCanvasConfig(
///   p2pConnector: myP2PConnector,
///   ...
/// );
/// ```
abstract class FlueraP2PConnector extends ChangeNotifier {
  /// The P2P engine instance.
  P2PEngine get engine;

  /// Whether the connection is established.
  bool get isConnected;

  /// Room ID for the current session.
  String? get roomId;

  /// Invite link for sharing.
  String? get inviteLink;

  /// Create a new P2P session (host mode).
  ///
  /// Returns the room ID for sharing.
  Future<String> createSession({bool enableAudio = false});

  /// Join an existing P2P session (guest mode).
  ///
  /// [roomIdOrLink] can be a room ID or a full deep/universal link.
  Future<void> joinSession(String roomIdOrLink, {bool enableAudio = false});

  /// Wait until the P2P connection is fully established.
  Future<void> waitForConnection({
    Duration timeout = const Duration(seconds: 30),
  });

  /// Enable/disable voice audio.
  void setAudioEnabled(bool enabled);

  /// End the session and clean up all resources.
  Future<void> endSession();

  /// Check if a string looks like a P2P invite link.
  static bool isInviteLink(String text) {
    return CollabInviteService.isCollabLink(text);
  }

  /// Parse a room ID from a link or raw string.
  static String? parseInviteLink(String link) {
    return CollabInviteService.parseDeepLink(link);
  }
}
