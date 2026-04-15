// ============================================================================
// 🙈 RECALL MODE OVERLAY — Primary visual overlay for Step 2
//
// This overlay renders the visual treatment of the recall mode:
//   - Free Recall: completely hides original nodes (opacity 0%)
//   - Spatial Recall: colored blurred blobs (position visible, text hidden)
//   - Reconstruction zone border
//   - Timer and node counter (optional, discrete)
//   - Free/Spatial mode toggle pill
//
// Spec: P2-02, P2-03, P2-04, P2-05, P2-38→P2-42
// ============================================================================

import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../reflow/content_cluster.dart';
import '../../../l10n/generated/fluera_localizations.g.dart';
import '../../infinite_canvas_controller.dart';
import 'recall_mode_controller.dart';
import 'recall_session_model.dart';

/// 🙈 Main overlay widget for the Recall Mode.
///
/// Positioned as a full-screen overlay in the canvas Stack.
/// Reacts to [RecallModeController] changes via [ListenableBuilder].
class RecallModeOverlay extends StatefulWidget {
  final RecallModeController controller;

  /// Canvas controller for coordinate transforms.
  final InfiniteCanvasController? canvasController;

  /// Callback to switch to Spatial Recall.
  final VoidCallback onSwitchToSpatial;

  /// Callback when user taps "Ho finito" to start comparison.
  final VoidCallback onStartComparison;

  /// Callback to exit Recall Mode.
  final VoidCallback onExit;

  const RecallModeOverlay({
    super.key,
    required this.controller,
    required this.canvasController,
    required this.onSwitchToSpatial,
    required this.onStartComparison,
    required this.onExit,
  });

  @override
  State<RecallModeOverlay> createState() => _RecallModeOverlayState();
}

class _RecallModeOverlayState extends State<RecallModeOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _entranceController;
  late final Animation<double> _entranceFade;

  // Timer display refresh.
  late final Stream<void> _timerStream;

  @override
  void initState() {
    super.initState();

    // Subtle pulse animation for the zone border.
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    // Entrance animation.
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _entranceFade = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOut,
    );
    _entranceController.forward();

    // Tick every second for timer display.
    _timerStream = Stream.periodic(const Duration(seconds: 1));
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // No internal ListenableBuilder needed — this widget is already
    // conditionally mounted by the parent and rebuilt via the parent
    // AnimatedBuilder. Internal listeners cause defunct assertions.
    if (!widget.controller.isActive || widget.controller.isComparing) {
      return const SizedBox.shrink();
    }

    return FadeTransition(
      opacity: _entranceFade,
      child: Stack(
        children: [
          // ── Spatial Recall: colored blobs for original nodes ──
          if (widget.controller.isSpatialRecall)
            ..._buildSpatialBlobs(),

          // ── Top HUD bar ──
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            right: 16,
            child: _buildHudBar(context),
          ),

          // ── Bottom action bar ──
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 16,
            left: 16,
            right: 16,
            child: _buildActionBar(context),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HUD BAR — Timer + Counter + Mode toggle
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildHudBar(BuildContext context) {
    final l10n = FlueraLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xCC0A0A14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF6C63FF).withValues(alpha: 0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Mode indicator.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF6C63FF).withValues(alpha: 0.3),
                  const Color(0xFF6C63FF).withValues(alpha: 0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              widget.controller.isFreeRecall
                  ? l10n.recall_modeFree
                  : l10n.recall_modeSpatial,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

          const SizedBox(width: 12),

          // Timer (P2-04): optional, semi-transparent.
          StreamBuilder<void>(
            stream: _timerStream,
            builder: (_, __) {
              final elapsed = widget.controller.elapsed;
              final mins = elapsed.inMinutes.toString().padLeft(2, '0');
              final secs = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
              return Opacity(
                opacity: 0.5,
                child: Text(
                  '$mins:$secs',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              );
            },
          ),

          const Spacer(),

          // Node counter (P2-05).
          Opacity(
            opacity: 0.6,
            child: Text(
              l10n.recall_counter(
                widget.controller.reconstructedCount,
                widget.controller.originalCount,
              ),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),

          // Missed marker count (live).
          if (widget.controller.missedMarkers.isNotEmpty) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFFF3B30).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '❓ ${widget.controller.missedMarkers.length}',
                style: const TextStyle(
                  color: Color(0xFFFF6B6B),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],

          // Free → Spatial toggle (P2-41).
          if (widget.controller.isFreeRecall) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                widget.onSwitchToSpatial();
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.15),
                    width: 0.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.visibility_rounded,
                        color: Colors.white54, size: 14),
                    const SizedBox(width: 4),
                    Text(
                    l10n.recall_hints,
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ACTION BAR — "Ho finito" + Exit
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildActionBar(BuildContext context) {
    final l10n = FlueraLocalizations.of(context)!;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Exit button.
        GestureDetector(
          onTap: () {
            HapticFeedback.mediumImpact();
            widget.onExit();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
                width: 0.5,
              ),
            ),
            child: Text(
              l10n.recall_exit,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),

        const SizedBox(width: 12),

        // "Ho finito" — Start comparison (P2-23).
        GestureDetector(
          onTap: () {
            HapticFeedback.heavyImpact();
            widget.onStartComparison();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6C63FF), Color(0xFF8B5CF6)],
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6C63FF).withValues(alpha: 0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle_outline_rounded,
                    color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text(
                  l10n.recall_showComparison,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SPATIAL BLOBS (P2-40)
  // ─────────────────────────────────────────────────────────────────────────

  /// Build colored blobs for each original cluster in Spatial Recall.
  ///
  /// Shows position and color, but text is 100% illegible.
  /// Opacity adapts with session count (P2-54).
  List<Widget> _buildSpatialBlobs() {
    final controller = widget.canvasController;
    if (controller == null) return const [];

    final opacity = widget.controller.adaptiveBlobOpacity;

    return widget.controller.originalClusters.map((cluster) {
      // Skip if this node is currently being peeked.
      if (cluster.id == widget.controller.activePeekClusterId) {
        return const SizedBox.shrink();
      }

      // Convert canvas bounds to screen coordinates.
      final screenCenter = controller.canvasToScreen(cluster.centroid);
      final scale = controller.scale;
      final screenWidth = cluster.bounds.width * scale;
      final screenHeight = cluster.bounds.height * scale;

      // Determine blob color from cluster's dominant stroke color.
      // Fallback to a neutral blue-gray.
      const blobColor = Color(0xFF4A5568);

      // Check if this node was peeked (show peek marker color).
      final peekColor = widget.controller.peekMarkerColor(cluster.id);
      final hasPeekMark = peekColor != 0x00000000;

      return AnimatedBuilder(
        animation: _pulseController,
        builder: (_, __) {
          return Positioned(
            left: screenCenter.dx - screenWidth / 2,
            top: screenCenter.dy - screenHeight / 2,
            child: IgnorePointer(
              child: Container(
                width: screenWidth.clamp(20.0, 400.0),
                height: screenHeight.clamp(20.0, 300.0),
                decoration: BoxDecoration(
                  color: (hasPeekMark ? Color(peekColor) : blobColor)
                      .withValues(alpha: opacity),
                  borderRadius: BorderRadius.circular(8),
                  border: hasPeekMark
                      ? Border.all(
                          color: Color(peekColor).withValues(alpha: 0.6),
                          width: 1.5,
                        )
                      : null,
                ),
              ),
            ),
          );
        },
      );
    }).toList();
  }
}
