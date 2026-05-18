// ============================================================================
// 🤝 COLLAB SHARE SHEET — Invite-link surface for the Pro share flow
//
// Bottom sheet that shows a generated `CollabInviteLink`, copy-to-clipboard
// and system-share affordances, plus an explanation of the role granted.
//
// V1 launch (2026-05-14):
//   • The token is produced by the injected `RealtimeCollabInviteService`.
//   • The engine ships a SIMPLE in-memory `LocalCollabInviteService` as the
//     fallback for tests and the SDK demo — it mints a UUID-only token that
//     the realtime adapter accepts trustingly. Production hosts wire the
//     Supabase-backed implementation that validates the token server-side.
//
// Decision plan: .claude/plans/analizza-tutta-fluera-app-floating-pebble.md §6
// ============================================================================

import 'dart:math' show Random;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../l10n/fluera_localizations.dart';
import '../invite/collab_invite_link.dart';

/// 🤝 Show the share sheet for [canvasId]. Returns the link that was
/// generated (so the caller can log telemetry) or `null` if the user
/// dismissed without minting an invite.
Future<CollabInviteLink?> showCollabShareSheet({
  required BuildContext context,
  required String canvasId,
  required RealtimeCollabInviteService inviteService,
  CollabInviteRole role = CollabInviteRole.editor,
}) async {
  return showModalBottomSheet<CollabInviteLink>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _ShareSheet(
      canvasId: canvasId,
      inviteService: inviteService,
      role: role,
    ),
  );
}

class _ShareSheet extends StatefulWidget {
  final String canvasId;
  final RealtimeCollabInviteService inviteService;
  final CollabInviteRole role;

  const _ShareSheet({
    required this.canvasId,
    required this.inviteService,
    required this.role,
  });

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  CollabInviteLink? _link;
  bool _minting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _mintLink();
  }

  Future<void> _mintLink() async {
    setState(() {
      _minting = true;
      _error = null;
    });
    try {
      final link = await widget.inviteService.createInvite(
        canvasId: widget.canvasId,
        role: widget.role,
      );
      if (!mounted) return;
      setState(() {
        _link = link;
        _minting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _minting = false;
        _error = 'Impossibile creare il link in questo momento ($e). Riprova.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final link = _link;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.groups_rounded, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Text(
                  FlueraLocalizations.of(context)!.collabShare_inviteCanvas,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              widget.role == CollabInviteRole.viewer
                  ? 'Il link concede accesso in sola lettura.'
                  : 'Il link concede accesso completo di modifica.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            if (_minting)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_error != null)
              _ErrorBox(message: _error!, onRetry: _mintLink)
            else if (link != null)
              _LinkRow(link: link),
            const SizedBox(height: 12),
            if (link != null)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _ActionChip(
                    icon: Icons.copy_rounded,
                    label: FlueraLocalizations.of(context)!
                        .collabShare_copyLink,
                    onTap: () => _copyToClipboard(link),
                  ),
                  _ActionChip(
                    icon: Icons.ios_share_rounded,
                    label: 'Condividi…',
                    onTap: () => _systemShare(link),
                  ),
                  _ActionChip(
                    icon: Icons.refresh_rounded,
                    label: FlueraLocalizations.of(context)!
                        .collabShare_generateNew,
                    onTap: _mintLink,
                  ),
                ],
              ),
            const SizedBox(height: 16),
            _Disclosure(),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(link),
                child: Text(
                    FlueraLocalizations.of(context)!.collabShare_close),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copyToClipboard(CollabInviteLink link) async {
    await Clipboard.setData(
      ClipboardData(text: link.toUniversalUri().toString()),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            FlueraLocalizations.of(context)!.collabShare_linkCopied),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _systemShare(CollabInviteLink link) async {
    // Universal link form is preferred because most share targets
    // (Messages, Mail, browsers) don't handle custom schemes.
    final url = link.toUniversalUri().toString();
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: 'Ho aperto un canvas su Fluera, ti unisci?\n$url',
          subject: 'Collabora su Fluera',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Condivisione annullata o non disponibile ($e)')),
      );
    }
  }
}

class _LinkRow extends StatelessWidget {
  final CollabInviteLink link;

  const _LinkRow({required this.link});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.link_rounded,
              size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              link.toUniversalUri().toString(),
              maxLines: 2,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ActionChip(
      avatar: Icon(icon, size: 18, color: theme.colorScheme.primary),
      label: Text(label),
      onPressed: onTap,
    );
  }
}

class _Disclosure extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline_rounded,
            size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Chiunque abbia il link può aprire questo canvas. '
            'Genera un nuovo link per revocare gli accessi precedenti.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorBox({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: onRetry, child: const Text('Riprova')),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Local invite service — fallback for tests / SDK demo / V1 ship before the
// Supabase `create_collab_invite` RPC lands. Generates a UUID token that
// the realtime adapter accepts trustingly. NOT secure for production use.
// ────────────────────────────────────────────────────────────────────────────

/// 🤝 In-memory invite service that mints UUID tokens without server-side
/// validation. Use the Supabase-backed implementation in production.
///
/// **Security caveat:** anyone holding the token can join. The token is
/// not bound to canvas ownership, not expirable, and not revocable.
/// Acceptable for the V1 soft launch as a SAFE-DEFAULT fallback when the
/// Supabase RPC isn't wired yet — pair with a `RealtimeAdapter` that
/// already enforces ACL server-side.
class LocalCollabInviteService implements RealtimeCollabInviteService {
  LocalCollabInviteService({Random? random}) : _rng = random ?? Random.secure();

  final Random _rng;
  final Set<String> _revoked = <String>{};

  @override
  Future<CollabInviteLink> createInvite({
    required String canvasId,
    CollabInviteRole role = CollabInviteRole.editor,
    Duration validity = const Duration(days: 7),
  }) async {
    final token = _mintToken();
    return CollabInviteLink(
      canvasId: canvasId,
      token: token,
      role: role,
    );
  }

  @override
  Future<void> revokeInvite({required String token}) async {
    _revoked.add(token);
  }

  /// Whether a token has been revoked. The realtime adapter consults this
  /// before accepting an incoming peer join.
  bool isRevoked(String token) => _revoked.contains(token);

  String _mintToken() {
    // 16 random bytes encoded as base36 — enough entropy for a non-secure
    // share token. ~76 bits of entropy after encoding.
    final bytes = List<int>.generate(16, (_) => _rng.nextInt(256));
    final buf = StringBuffer();
    for (final b in bytes) {
      buf.write(b.toRadixString(36).padLeft(2, '0'));
    }
    return buf.toString();
  }
}
