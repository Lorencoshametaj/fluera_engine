// ============================================================================
// 🔍 RECALL COMPARISON OVERLAY — Visual diff between original & reconstructed
//
// Spec: P2-23 → P2-30, P2-57
//
// Triggered by explicit "Ho finito" action. Shows:
//   - Gradual reveal: blur 20px → 0px in ~1000ms (P2-24)
//   - 3+1 color overlay (P2-26, P2-27):
//     🔴 Red (30%): original only (gaps)
//     🟢 Green (20%): both (recalled)
//     🔵 Blue (20%): reconstruction only (additions)
//     🟡 Yellow: peeked nodes
//   - Gap navigation: "→" button to jump between gaps (P2-28)
//   - Recall level selector per node (P2-43)
//   - Mastered nodes: gold border pulse (P2-57)
// ============================================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../reflow/content_cluster.dart';
import '../../../l10n/generated/fluera_localizations.g.dart';
import 'recall_level_l10n.dart';
import 'recall_mode_controller.dart';
import 'recall_session_model.dart';

/// 🔍 Comparison overlay for the reveal phase.
class RecallComparisonOverlay extends StatefulWidget {
  final RecallModeController controller;

  /// Called when user wants to navigate to a gap cluster.
  final void Function(String clusterId) onNavigateToGap;

  /// Called when the user finishes comparison and wants summary.
  final VoidCallback onShowSummary;

  /// Called when user wants to start Step 3 (Socratic).
  final VoidCallback onStartSocratic;

  /// Toggle between original and reconstruction views.
  final VoidCallback onToggleView;

  /// Whether currently showing originals (true) or reconstruction (false).
  final bool showingOriginals;

  const RecallComparisonOverlay({
    super.key,
    required this.controller,
    required this.onNavigateToGap,
    required this.onShowSummary,
    required this.onStartSocratic,
    required this.onToggleView,
    this.showingOriginals = true,
  });

  @override
  State<RecallComparisonOverlay> createState() =>
      _RecallComparisonOverlayState();
}

class _RecallComparisonOverlayState extends State<RecallComparisonOverlay>
    with TickerProviderStateMixin {
  // Blur reveal animation (P2-24): 20px → 0px over 1000ms.
  late final AnimationController _revealController;
  late final Animation<double> _blurAnim;
  late final Animation<double> _fadeAnim;

  // Gold pulse for mastered nodes (P2-57).
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();

    _revealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _blurAnim = Tween<double>(begin: 20.0, end: 0.0).animate(
      CurvedAnimation(parent: _revealController, curve: Curves.easeOut),
    );
    _fadeAnim = CurvedAnimation(
      parent: _revealController,
      curve: Curves.easeOut,
    );
    _revealController.forward();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _revealController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // This widget is already conditionally mounted by the parent
    // (if isComparing) and rebuilt via the parent AnimatedBuilder
    // listening to _canvasController. No internal ListenableBuilder
    // needed — it caused _ElementLifecycle.defunct assertions when
    // the controller notified during widget teardown.
    if (!widget.controller.isComparing) {
      return const SizedBox.shrink();
    }

    return SizedBox.expand(
      child: Stack(
        children: [
          // ── Navigation bar (bottom) ──
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 16,
            left: 16,
            right: 16,
            child: _buildNavigationBar(context),
          ),

          // ── Gap count badge (top right) ──
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 16,
            child: _buildGapBadge(),
          ),
        ],
      ),
    );
  }


  // ─────────────────────────────────────────────────────────────────────────
  // NAVIGATION BAR
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildNavigationBar(BuildContext context) {
    final l10n = FlueraLocalizations.of(context)!;
    final gaps = widget.controller.gapClusterIds;
    final hasGaps = gaps.isNotEmpty;
    final idx = widget.controller.gapNavigationIndex;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xCC0A0A14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 20,
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Previous gap.
          if (hasGaps)
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                final id = widget.controller.navigateToPreviousGap();
                if (id != null) widget.onNavigateToGap(id);
              },
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.arrow_back_ios_rounded,
                    color: Colors.white54, size: 16),
              ),
            ),

          // Gap counter.
          if (hasGaps)
            Text(
              l10n.recall_gapCounter(
                (idx + 1).clamp(1, gaps.length), // idx=-1 → show 1, not 0
                gaps.length,
              ),
              style: const TextStyle(
                color: Color(0xFFFF3B30),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),

          if (!hasGaps)
            Text(
              l10n.recall_noGaps,
              style: const TextStyle(
                color: Color(0xFF30D158),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),

          // Next gap.
          if (hasGaps)
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                final id = widget.controller.navigateToNextGap();
                if (id != null) widget.onNavigateToGap(id);
              },
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.arrow_forward_ios_rounded,
                    color: Colors.white54, size: 16),
              ),
            ),

          const Spacer(),

          // 🧠 Toggle: split view ↔ reconstruction only
          GestureDetector(
            onTap: widget.onToggleView,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: widget.showingOriginals
                    ? const Color(0xFF007AFF).withValues(alpha: 0.2)
                    : const Color(0xFF30D158).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: widget.showingOriginals
                      ? const Color(0xFF007AFF).withValues(alpha: 0.5)
                      : const Color(0xFF30D158).withValues(alpha: 0.5),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    widget.showingOriginals
                        ? Icons.compare_rounded
                        : Icons.edit_rounded,
                    color: Colors.white70,
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    // Shows where you'll GO, not where you ARE:
                    // on comparison → button says 'Attempt'
                    // on attempt    → button says 'Comparison'
                    widget.showingOriginals
                        ? l10n.recall_viewAttempt
                        : l10n.recall_viewComparison,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 8),

          // Show summary.
          GestureDetector(
            onTap: () {
              HapticFeedback.mediumImpact();
              widget.onShowSummary();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6C63FF), Color(0xFF8B5CF6)],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                l10n.recall_summary,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // GAP BADGE
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildGapBadge() {
    final session = widget.controller.session;
    if (session == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xCC0A0A14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('✅', style: TextStyle(fontSize: 12)),
          const SizedBox(width: 4),
          Text(
            '${session.recalledCount}',
            style: const TextStyle(
              color: Color(0xFF30D158),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 8),
          const Text('❌', style: TextStyle(fontSize: 12)),
          const SizedBox(width: 4),
          Text(
            '${session.missedCount}',
            style: const TextStyle(
              color: Color(0xFFFF3B30),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (session.peekedCount > 0) ...[
            const SizedBox(width: 8),
            const Text('👁️', style: TextStyle(fontSize: 12)),
            const SizedBox(width: 4),
            Text(
              '${session.peekedCount}',
              style: const TextStyle(
                color: Color(0xFFFFCC00),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────────────────────

  Color _statusColor(ComparisonNodeStatus status) {
    switch (status) {
      case ComparisonNodeStatus.missed:
        return const Color(0xFFFF3B30); // Red
      case ComparisonNodeStatus.recalled:
        return const Color(0xFF30D158); // Green
      case ComparisonNodeStatus.added:
        return const Color(0xFF007AFF); // Blue
      case ComparisonNodeStatus.peeked:
        return const Color(0xFFFFCC00); // Yellow
    }
  }

  double _statusOpacity(ComparisonNodeStatus status) {
    switch (status) {
      case ComparisonNodeStatus.missed:
        return 0.30; // P2-26
      case ComparisonNodeStatus.recalled:
        return 0.20; // P2-26
      case ComparisonNodeStatus.added:
        return 0.20; // P2-26
      case ComparisonNodeStatus.peeked:
        return 0.30; // P2-27
    }
  }

  String _statusIcon(ComparisonNodeStatus status) {
    switch (status) {
      case ComparisonNodeStatus.missed:
        return '🔴';
      case ComparisonNodeStatus.recalled:
        return '🟢';
      case ComparisonNodeStatus.added:
        return '🔵';
      case ComparisonNodeStatus.peeked:
        return '👁️';
    }
  }
}
