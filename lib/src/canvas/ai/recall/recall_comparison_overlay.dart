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
import 'recall_mode_controller.dart';
import 'recall_session_model.dart';

/// 🔍 Comparison overlay for the reveal phase.
class RecallComparisonOverlay extends StatefulWidget {
  final RecallModeController controller;
  final dynamic canvasController;

  /// Called when user wants to navigate to a gap cluster.
  final void Function(String clusterId) onNavigateToGap;

  /// Called when the user finishes comparison and wants summary.
  final VoidCallback onShowSummary;

  /// Called when user wants to start Step 3 (Socratic).
  final VoidCallback onStartSocratic;

  const RecallComparisonOverlay({
    super.key,
    required this.controller,
    required this.canvasController,
    required this.onNavigateToGap,
    required this.onShowSummary,
    required this.onStartSocratic,
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
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        if (!widget.controller.isComparing) {
          return const SizedBox.shrink();
        }

        return Stack(
          children: [
            // ── Color-coded node overlays (P2-26) ──
            ..._buildNodeOverlays(),

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
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // COLOR-CODED NODE OVERLAYS (P2-26)
  // ─────────────────────────────────────────────────────────────────────────

  List<Widget> _buildNodeOverlays() {
    final controller = widget.canvasController;
    if (controller == null) return const [];

    final entries = widget.controller.nodeEntries;
    final widgets = <Widget>[];

    for (final entry in entries.entries) {
      final cluster = widget.controller.originalClusters
          .where((c) => c.id == entry.key)
          .firstOrNull;
      if (cluster == null) continue;

      final status = widget.controller.comparisonStatus(entry.key);
      final color = _statusColor(status);
      final opacity = _statusOpacity(status);

      // Convert to screen coordinates.
      final Offset screenCenter;
      final double screenWidth;
      final double screenHeight;
      try {
        screenCenter = (controller as dynamic).canvasToScreen(cluster.centroid) as Offset;
        final scale = (controller as dynamic).scale as double;
        screenWidth = cluster.bounds.width * scale;
        screenHeight = cluster.bounds.height * scale;
      } catch (_) {
        continue;
      }

      final w = screenWidth.clamp(40.0, 400.0);
      final h = screenHeight.clamp(30.0, 300.0);

      // Mastery check (P2-57): gold pulse for mastered nodes.
      final isMastered = entry.value.mastered;
      final isRecalled = entry.value.recallLevel.isSuccessful;

      widgets.add(
        AnimatedBuilder(
          animation: _revealController,
          builder: (_, __) {
            return Positioned(
              left: screenCenter.dx - w / 2,
              top: screenCenter.dy - h / 2,
              child: Opacity(
                opacity: _fadeAnim.value,
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    widget.controller.cycleRecallLevel(entry.key);
                  },
                  onDoubleTap: () {
                    HapticFeedback.mediumImpact();
                    widget.onNavigateToGap(entry.key);
                  },
                  child: AnimatedBuilder(
                    animation: _pulseController,
                    builder: (_, __) {
                      final goldGlow = isMastered
                          ? _pulseController.value * 0.4
                          : 0.0;
                      return Container(
                        width: w,
                        height: h,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: opacity),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isMastered
                                ? const Color(0xFFFFD700).withValues(
                                    alpha: 0.5 + goldGlow,
                                  )
                                : color.withValues(alpha: opacity + 0.15),
                            width: isMastered ? 2.0 : 1.0,
                          ),
                          boxShadow: [
                            if (isMastered)
                              BoxShadow(
                                color: const Color(0xFFFFD700)
                                    .withValues(alpha: goldGlow * 0.5),
                                blurRadius: 12,
                                spreadRadius: 2,
                              ),
                            if (isRecalled && !isMastered)
                              BoxShadow(
                                color: const Color(0xFF30D158)
                                    .withValues(alpha: 0.15),
                                blurRadius: 8,
                              ),
                          ],
                        ),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Status icon.
                              Text(
                                _statusIcon(status),
                                style: const TextStyle(fontSize: 20),
                              ),
                              const SizedBox(height: 2),
                              // Recall level indicator.
                              Text(
                                entry.value.recallLevel.label,
                                style: TextStyle(
                                  color: color.withValues(alpha: 0.9),
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              // Mastery star.
                              if (isMastered)
                                const Text('⭐',
                                    style: TextStyle(fontSize: 12)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
      );
    }

    return widgets;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // NAVIGATION BAR
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildNavigationBar(BuildContext context) {
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
              '${idx + 1} / ${gaps.length} da rivedere',
              style: const TextStyle(
                color: Color(0xFFFF3B30),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),

          if (!hasGaps)
            const Text(
              '🎉 Nessuna lacuna!',
              style: TextStyle(
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
              child: const Text(
                'Riepilogo',
                style: TextStyle(
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
