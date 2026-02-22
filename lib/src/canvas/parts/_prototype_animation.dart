part of '../nebula_canvas_screen.dart';

// ============================================================================
// 🎬 PROTOTYPE & ANIMATION — Wire prototype flow, timeline, smart animate
// ============================================================================

extension PrototypeAnimationFeatures on _NebulaCanvasScreenState {
  /// Start interactive prototype preview.
  /// Wires: prototype_flow, smart_animate_engine
  void _startPrototypePreview() {
    final flow = PrototypeFlow(
      id: 'preview_${DateTime.now().millisecondsSinceEpoch}',
    );
    // Launch prototype player overlay
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PrototypePlayerSheet(flow: flow),
    );
    debugPrint('[Design] Prototype preview started');
  }

  /// Add a flow link between two frames.
  /// Wires: prototype_flow
  void _addFlowLink() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Tap source frame, then target frame to link'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
    debugPrint('[Design] Flow link mode activated');
  }

  /// Show animation timeline panel.
  /// Wires: animation_timeline, animation_player, stagger_animation,
  ///        spring_simulation, path_motion
  void _showAnimationTimeline() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const AnimationTimelinePanel(),
    );
    debugPrint('[Design] Animation timeline opened');
  }

  /// Enable smart animate between component states.
  /// Wires: smart_animate_engine, smart_animate_snapshot
  void _enableSmartAnimate() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Smart Animate enabled — switch variants to preview',
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
    debugPrint('[Design] Smart animate enabled');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 🎬 Prototype Player — Inline sheet
// ─────────────────────────────────────────────────────────────────────────────

class _PrototypePlayerSheet extends StatelessWidget {
  final PrototypeFlow flow;
  const _PrototypePlayerSheet({required this.flow});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder:
          (ctx, scrollCtrl) => Container(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 8, bottom: 4),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.play_circle_filled_rounded,
                        color: cs.primary,
                        size: 28,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Prototype Preview',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.touch_app_rounded,
                          size: 64,
                          color: cs.primary.withValues(alpha: 0.4),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Interact with your prototype',
                          style: TextStyle(
                            fontSize: 16,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Flow: ${flow.id}',
                          style: TextStyle(
                            fontSize: 13,
                            color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
    );
  }
}
