// ============================================================================
// 🔗 COLLAB INVITE SERVICE — Session invitation link/QR (A4, P7-02)
//
// Generates and parses collaboration invite links and QR payloads.
// Methods of invitation (P7-02):
//   - Deep link: fluera://collab/{roomId}
//   - QR code: encodes the same deep link
//   - Nearby (V2, future): Bluetooth LE discovery
//
// No lobby, no matchmaking — explicit invites only (P7-02).
//
// ARCHITECTURE: Pure model — no platform channels, no QR rendering.
// THREAD SAFETY: Main isolate only.
// ============================================================================

import 'dart:math';

/// 🔗 Collab Invite Service (A4, P7-02).
///
/// Generates room IDs and invite links for P2P sessions.
///
/// Usage:
/// ```dart
/// final invite = CollabInviteService();
///
/// // Host generates an invite
/// final roomId = invite.generateRoomId();
/// final link = invite.createDeepLink(roomId);
/// // Share link or render QR from invite.qrPayload(roomId)
///
/// // Guest parses the invite
/// final parsed = invite.parseDeepLink('fluera://collab/abc123');
/// if (parsed != null) {
///   await sessionController.joinSession(signaling, parsed);
/// }
/// ```
class CollabInviteService {
  CollabInviteService._();

  /// Deep link scheme.
  static const String scheme = 'fluera';

  /// Deep link host.
  static const String host = 'collab';

  /// Generate a unique room ID.
  ///
  /// Format: 6 alphanumeric characters (case-insensitive).
  /// Collision probability: ~2.17 billion combinations.
  static String generateRoomId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rng = Random.secure();
    return List.generate(8, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  /// Create a deep link for sharing.
  ///
  /// Format: `fluera://collab/{roomId}`
  static String createDeepLink(String roomId) {
    return '$scheme://$host/$roomId';
  }

  /// Create a universal link (HTTPS) for platforms that prefer it.
  ///
  /// Format: `https://fluera.app/collab/{roomId}`
  static String createUniversalLink(
    String roomId, {
    String domain = 'fluera.app',
  }) {
    return 'https://$domain/$host/$roomId';
  }

  /// Parse a deep link and extract the room ID.
  ///
  /// Returns null if the link is not a valid collab invite.
  static String? parseDeepLink(String link) {
    try {
      final uri = Uri.parse(link);

      // Handle fluera://collab/{roomId}
      if (uri.scheme == scheme && uri.host == host) {
        final segments = uri.pathSegments;
        if (segments.isNotEmpty) {
          return _validateRoomId(segments.first);
        }
      }

      // Handle https://fluera.app/collab/{roomId}
      if (uri.scheme == 'https' && uri.pathSegments.length >= 2) {
        if (uri.pathSegments[0] == host) {
          return _validateRoomId(uri.pathSegments[1]);
        }
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  /// Payload for QR code generation (same as deep link).
  ///
  /// The host app renders this string as a QR code.
  static String qrPayload(String roomId) => createDeepLink(roomId);

  /// Validate a room ID format.
  static String? _validateRoomId(String id) {
    if (id.isEmpty || id.length > 16) return null;
    // Only alphanumeric.
    if (!RegExp(r'^[a-z0-9]+$').hasMatch(id)) return null;
    return id;
  }

  /// Check if a string looks like a collab invite (quick check).
  static bool isCollabLink(String text) {
    return text.startsWith('$scheme://$host/') ||
        text.contains('/$host/');
  }
}
