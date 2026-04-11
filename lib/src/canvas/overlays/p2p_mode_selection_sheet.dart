// ============================================================================
// 🎯 P2P MODE SELECTION SHEET — Choose collaboration mode (Passo 7)
//
// Material 3 bottom sheet presenting the three P2P collaboration modes:
//   - Mode 7a: Visita (Visit) — browse peer's notes
//   - Mode 7b: Insegnamento (Teaching) — alternating explanations + voice
//   - Mode 7c: Duello (Duel) — timed recall race
//
// Shown after P2P connection is established.
// ============================================================================

import 'package:flutter/material.dart';
import '../../p2p/p2p_session_state.dart';

/// 🎯 P2P Mode Selection Sheet.
///
/// Usage:
/// ```dart
/// final mode = await showModalBottomSheet<P2PCollabMode>(
///   context: context,
///   isScrollControlled: true,
///   builder: (_) => P2PModeSelectionSheet(
///     peerName: 'Alice',
///     peerTopic: 'Biologia',
///   ),
/// );
/// ```
class P2PModeSelectionSheet extends StatelessWidget {
  /// Peer's display name.
  final String peerName;

  /// Peer's zone topic for context.
  final String? peerTopic;

  const P2PModeSelectionSheet({
    super.key,
    required this.peerName,
    this.peerTopic,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Handle bar ──────────────────────────────────────────
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),

            // ── Title ──────────────────────────────────────────────
            Text(
              'Collabora con $peerName',
              style: theme.textTheme.titleLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (peerTopic != null) ...[
              const SizedBox(height: 4),
              Text(
                peerTopic!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white54,
                ),
              ),
            ],
            const SizedBox(height: 24),

            // ── Mode Cards ─────────────────────────────────────────
            _ModeCard(
              icon: Icons.explore_outlined,
              title: 'Visita (7a)',
              subtitle:
                  'Esplora gli appunti del peer. Puoi navigare, '
                  'posizionare marker, e prendere ispirazione.',
              color: const Color(0xFF1565C0),
              mode: P2PCollabMode.visit,
              onTap: () => Navigator.of(context).pop(P2PCollabMode.visit),
            ),
            const SizedBox(height: 12),

            _ModeCard(
              icon: Icons.school_outlined,
              title: 'Insegnamento (7b)',
              subtitle:
                  'Insegnamento reciproco con voice e laser '
                  'pointer. Chi spiega impara di più.',
              color: const Color(0xFF6A1B9A),
              mode: P2PCollabMode.teaching,
              onTap: () =>
                  Navigator.of(context).pop(P2PCollabMode.teaching),
            ),
            const SizedBox(height: 12),

            _ModeCard(
              icon: Icons.sports_esports_outlined,
              title: 'Duello (7c)',
              subtitle:
                  'Richiamo a tempo! Entrambi ricostruite dalla '
                  'memoria, poi confrontate i risultati.',
              color: const Color(0xFFC62828),
              mode: P2PCollabMode.duel,
              onTap: () => Navigator.of(context).pop(P2PCollabMode.duel),
            ),

            const SizedBox(height: 16),

            // ── Cancel ─────────────────────────────────────────────
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Annulla',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final P2PCollabMode mode;
  final VoidCallback onTap;

  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.mode,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: color.withValues(alpha: 0.4),
              width: 1.0,
            ),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withValues(alpha: 0.15),
                color.withValues(alpha: 0.05),
              ],
            ),
          ),
          child: Row(
            children: [
              // Icon circle.
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 14),

              // Text.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),

              // Arrow.
              Icon(
                Icons.chevron_right,
                color: color.withValues(alpha: 0.6),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
