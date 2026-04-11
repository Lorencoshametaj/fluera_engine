// ============================================================================
// 🔗 P2P INVITE SHEET — Share invite link or QR code (P7-02)
//
// Bottom sheet to share a P2P session invite:
//   - Copy link to clipboard
//   - Share via system share sheet
//   - (Future: QR code display)
//
// Used by both host (create) and guest (join) flows.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'invite_code_painter.dart';

/// 🔗 P2P Invite Sheet (P7-02).
///
/// Shows the session invite link with copy and share options.
///
/// Usage:
/// ```dart
/// showModalBottomSheet(
///   context: context,
///   builder: (_) => P2PInviteSheet(
///     roomId: 'abc12345',
///     inviteLink: 'fluera://collab/abc12345',
///     onJoin: (roomId) => connector.joinSession(roomId),
///   ),
/// );
/// ```
class P2PInviteSheet extends StatefulWidget {
  /// The room ID to display.
  final String? roomId;

  /// The full invite link.
  final String? inviteLink;

  /// Callback when the user enters a room ID to join.
  final void Function(String roomId)? onJoin;

  /// Whether this is for creating (host) or joining (guest).
  final bool isHost;

  const P2PInviteSheet({
    super.key,
    this.roomId,
    this.inviteLink,
    this.onJoin,
    this.isHost = true,
  });

  @override
  State<P2PInviteSheet> createState() => _P2PInviteSheetState();
}

class _P2PInviteSheetState extends State<P2PInviteSheet> {
  final _joinController = TextEditingController();
  bool _copied = false;

  @override
  void dispose() {
    _joinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20, 12, 20,
          MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar.
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),

            // Title.
            Text(
              widget.isHost
                  ? '🤝 Invita un compagno'
                  : '🤝 Unisciti a una sessione',
              style: theme.textTheme.titleLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.isHost
                  ? 'Condividi questo link per iniziare la collaborazione P2P'
                  : 'Inserisci il codice o il link ricevuto dal tuo compagno',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white54,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            if (widget.isHost && widget.inviteLink != null)
              _buildHostSection(context)
            else if (!widget.isHost)
              _buildGuestSection(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHostSection(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Link display.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.link,
                color: Colors.white54,
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.inviteLink!,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontFamily: 'monospace',
                    letterSpacing: 0.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Visual code (QR-like grid).
        if (widget.roomId != null)
          Center(
            child: InviteCodeDisplay(
              code: widget.inviteLink ?? widget.roomId!,
              size: 140,
              color: const Color(0xFF42A5F5),
            ),
          ),
        const SizedBox(height: 16),

        // Room code (simple display).
        if (widget.roomId != null)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Codice: ',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 13,
                  ),
                ),
                Text(
                  widget.roomId!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2.0,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),

        // Copy button.
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () {
              Clipboard.setData(
                ClipboardData(text: widget.inviteLink!),
              );
              setState(() => _copied = true);
              Future.delayed(
                const Duration(seconds: 2),
                () => mounted ? setState(() => _copied = false) : null,
              );
            },
            icon: Icon(
              _copied ? Icons.check : Icons.copy,
              size: 18,
            ),
            label: Text(
              _copied ? 'Copiato!' : 'Copia link',
            ),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF1565C0),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGuestSection(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Code input.
        TextField(
          controller: _joinController,
          autofocus: true,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: 3.0,
            fontFamily: 'monospace',
          ),
          decoration: InputDecoration(
            hintText: 'abc12345',
            hintStyle: TextStyle(
              color: Colors.white24,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: 3.0,
              fontFamily: 'monospace',
            ),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.08),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 16,
            ),
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              widget.onJoin?.call(value.trim());
              Navigator.of(context).pop();
            }
          },
        ),
        const SizedBox(height: 16),

        // Join button.
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () {
              final value = _joinController.text.trim();
              if (value.isNotEmpty) {
                widget.onJoin?.call(value);
                Navigator.of(context).pop();
              }
            },
            icon: const Icon(Icons.login, size: 18),
            label: const Text('Unisciti'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF4CAF50),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
