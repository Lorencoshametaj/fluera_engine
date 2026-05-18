// ============================================================================
// 🤝 COLLAB INVITE LINK — Deep-link DTO + parser for canvas sharing
//
// Format: `fluera://collab/<canvas_id>?token=<token>&inviter=<peer_id>&role=editor`
//   (universal link form: `https://fluera.dev/collab/<canvas_id>?token=...`)
//
// The engine ships the DTO + parser. The actual token issuance happens
// server-side (Supabase RPC `create_collab_invite`) and verification on
// join also lives server-side — the engine treats the token as opaque.
//
// Decision plan: .claude/plans/analizza-tutta-fluera-app-floating-pebble.md
// Pillar Pro #2 — see §1 Pro = "Studio amplificato".
// ============================================================================

/// 🤝 Collaboration role granted to the invitee.
enum CollabInviteRole {
  /// View-only access (cannot mutate the scene graph).
  viewer,

  /// Read + write access (strokes, text, scene-graph mutations).
  editor,
}

/// 🤝 Parsed representation of a canvas-collaboration invite.
class CollabInviteLink {
  /// The canvas the link grants access to.
  final String canvasId;

  /// Opaque token issued by the host's Supabase RPC. Validated on join,
  /// not here.
  final String token;

  /// CRDT peer id of the user who created the invite. Optional — falls
  /// back to `null` for legacy or malformed links.
  final String? inviterPeerId;

  /// Role granted to the invitee. Defaults to [CollabInviteRole.editor]
  /// when the link omits the parameter.
  final CollabInviteRole role;

  const CollabInviteLink({
    required this.canvasId,
    required this.token,
    this.inviterPeerId,
    this.role = CollabInviteRole.editor,
  });

  /// Canonical scheme for in-app deep links.
  static const String customScheme = 'fluera';
  static const String customHost = 'collab';

  /// HTTPS universal-link host (mirrors the in-app scheme so both work).
  static const String universalHost = 'fluera.dev';

  /// Encode this invite as a `fluera://collab/<id>?...` deep link.
  Uri toCustomSchemeUri() => Uri(
        scheme: customScheme,
        host: customHost,
        path: '/$canvasId',
        queryParameters: _queryParameters(),
      );

  /// Encode this invite as an `https://fluera.dev/collab/<id>?...` universal link.
  /// Use when sending via SMS / mail / clipboard — most platforms only
  /// honour custom schemes when the app is already known to the OS.
  Uri toUniversalUri() => Uri(
        scheme: 'https',
        host: universalHost,
        path: '/collab/$canvasId',
        queryParameters: _queryParameters(),
      );

  Map<String, String> _queryParameters() {
    return {
      'token': token,
      if (inviterPeerId != null) 'inviter': inviterPeerId!,
      'role': role.name,
    };
  }

  /// Attempt to parse [uri] as a collaboration invite. Returns `null` when
  /// the URI does not match the contract (wrong scheme, missing canvas id,
  /// missing token). Silent on malformed input by design — callers fall
  /// back to a generic "invalid link" UI.
  static CollabInviteLink? tryParse(Uri uri) {
    // Accept both fluera://collab/<id> and https://fluera.dev/collab/<id>.
    final isCustom =
        uri.scheme == customScheme && uri.host == customHost;
    final isUniversal = uri.scheme == 'https' &&
        uri.host == universalHost &&
        uri.pathSegments.isNotEmpty &&
        uri.pathSegments.first == 'collab';
    if (!isCustom && !isUniversal) return null;

    final segments = uri.pathSegments;
    String? canvasId;
    if (isCustom) {
      // fluera://collab/<id> → host = 'collab', pathSegments = [<id>]
      // OR fluera://collab/<id> may parse as a path on some platforms.
      if (segments.isNotEmpty && segments.first.isNotEmpty) {
        canvasId = segments.first;
      }
    } else {
      // https://fluera.dev/collab/<id> → pathSegments = ['collab', '<id>']
      if (segments.length >= 2 && segments[1].isNotEmpty) {
        canvasId = segments[1];
      }
    }
    if (canvasId == null || canvasId.isEmpty) return null;

    final token = uri.queryParameters['token'];
    if (token == null || token.isEmpty) return null;

    final inviter = uri.queryParameters['inviter'];
    final roleRaw = uri.queryParameters['role'];
    final role = _parseRole(roleRaw) ?? CollabInviteRole.editor;

    return CollabInviteLink(
      canvasId: canvasId,
      token: token,
      inviterPeerId: inviter,
      role: role,
    );
  }

  static CollabInviteRole? _parseRole(String? value) {
    if (value == null) return null;
    for (final r in CollabInviteRole.values) {
      if (r.name == value) return r;
    }
    return null;
  }

  @override
  String toString() => 'CollabInviteLink(canvas: $canvasId, '
      'role: ${role.name}, inviter: $inviterPeerId)';
}

/// 🤝 Contract for issuing realtime CRDT collaboration invites server-side.
///
/// The engine ships the abstract; the Fluera app injects a Supabase-backed
/// implementation that hits the `create_collab_invite` RPC to mint a
/// signed token. Tests can supply an in-memory fake.
///
/// Distinct from the legacy P2P `CollabInviteService` in `src/p2p/`
/// (which negotiates direct WebRTC peer connections, not Supabase
/// broadcast). Renamed to [RealtimeCollabInviteService] to keep both
/// namespaces compatible.
abstract class RealtimeCollabInviteService {
  /// Mint a new invite for [canvasId] granting [role] access.
  ///
  /// Implementations should:
  ///   1. Verify the caller owns the canvas (server-side RLS).
  ///   2. Issue a token bound to canvas + expiry + role (HMAC or JWT).
  ///   3. Return the assembled [CollabInviteLink].
  Future<CollabInviteLink> createInvite({
    required String canvasId,
    CollabInviteRole role = CollabInviteRole.editor,
    Duration validity = const Duration(days: 7),
  });

  /// Revoke a previously issued invite. Idempotent.
  Future<void> revokeInvite({required String token});
}
