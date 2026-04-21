import 'package:flutter/material.dart';
import '../../utils/reduced_motion.dart';

// =============================================================================
// ↩️ ACTION FLASH — Sober toast for undo/redo/selection feedback
//
// Quiet bottom-center pill. No glow, no scale-pop, no sci-fi styling.
// Visible ~350ms then fades. API preserved: showUndo / showRedo / showText.
// Honors OS reduce-motion via effectiveDuration (WCAG 2.3.3).
// =============================================================================

class ActionFlashOverlay extends StatefulWidget {
  const ActionFlashOverlay({super.key});

  @override
  State<ActionFlashOverlay> createState() => ActionFlashOverlayState();
}

class ActionFlashOverlayState extends State<ActionFlashOverlay>
    with SingleTickerProviderStateMixin {
  static const _visibleDuration = Duration(milliseconds: 1100);
  static const _fadeDuration = Duration(milliseconds: 180);

  late final AnimationController _ctrl;
  late final Animation<double> _opacity;

  IconData? _icon;
  String? _label;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: _fadeDuration);
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.addStatusListener(_onStatus);
  }

  @override
  void dispose() {
    _ctrl.removeStatusListener(_onStatus);
    _ctrl.dispose();
    super.dispose();
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      Future.delayed(_visibleDuration - _fadeDuration * 2, () {
        if (mounted && _ctrl.status == AnimationStatus.completed) {
          _ctrl.reverse();
        }
      });
    }
  }

  void showUndo() => _show(Icons.undo_rounded, 'Annullato');
  void showRedo() => _show(Icons.redo_rounded, 'Ripristinato');
  void showText(String text) => _show(null, text);

  void _show(IconData? icon, String label) {
    setState(() {
      _icon = icon;
      _label = label;
    });
    _ctrl.duration = effectiveDuration(context, _fadeDuration);
    _ctrl.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    if (_label == null) return const SizedBox.shrink();

    return Positioned(
      left: 0,
      right: 0,
      bottom: 120,
      child: IgnorePointer(
        child: Center(
          child: FadeTransition(
            opacity: _opacity,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.78),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_icon != null) ...[
                    Icon(_icon, size: 16, color: Colors.white),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    _label!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
