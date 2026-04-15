import 'package:flutter/material.dart';

import '../../systems/prototype_flow.dart';
import '../overlays/animation_timeline_panel.dart';

// ============================================================================
// 🎬 PROTOTYPE & ANIMATION — Standalone helpers (extracted Phase 1)
//
// Previously: part of fluera_canvas_screen.dart → _prototype_animation.dart
// ============================================================================

/// Start interactive prototype preview.
void startPrototypePreview(BuildContext context) {
  final flow = PrototypeFlow(
    id: 'preview_${DateTime.now().millisecondsSinceEpoch}',
  );
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => PrototypePlayerSheet(flow: flow),
  );
}

/// Add a flow link between two frames.
void addFlowLink(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: const Text('Tap source frame, then target frame to link'),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}

/// Show animation timeline panel.
void showAnimationTimeline(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const AnimationTimelinePanel(),
  );
}

/// Enable smart animate between component states.
void enableSmartAnimate(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: const Text(
        'Smart Animate enabled — switch variants to preview',
      ),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// 🎬 Prototype Player — Inline sheet (was _PrototypePlayerSheet)
// ─────────────────────────────────────────────────────────────────────────────

class PrototypePlayerSheet extends StatelessWidget {
  final PrototypeFlow flow;
  const PrototypePlayerSheet({super.key, required this.flow});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (ctx, scrollCtrl) => Container(
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
