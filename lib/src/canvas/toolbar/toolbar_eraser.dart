import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ============================================================================
// TOOLBAR ERASER — Eraser button (wobble), size slider, mode toggle
// ============================================================================

/// Eraser button with wobble animation when active
class ToolbarEraserButton extends StatefulWidget {
  final bool isActive;
  final VoidCallback onTap;
  final bool isDark;

  const ToolbarEraserButton({
    super.key,
    required this.isActive,
    required this.onTap,
    required this.isDark,
  });

  @override
  State<ToolbarEraserButton> createState() => _ToolbarEraserButtonState();
}

class _ToolbarEraserButtonState extends State<ToolbarEraserButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _wobbleController;
  late final Animation<double> _wobbleAnim;

  @override
  void initState() {
    super.initState();
    _wobbleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _wobbleAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.08), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 0.08, end: -0.08), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -0.08, end: 0.0), weight: 1),
    ]).animate(
      CurvedAnimation(parent: _wobbleController, curve: Curves.easeInOut),
    );

    if (widget.isActive) {
      _wobbleController.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant ToolbarEraserButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _wobbleController.repeat();
    } else if (!widget.isActive && oldWidget.isActive) {
      _wobbleController.stop();
      _wobbleController.reset();
    }
  }

  @override
  void dispose() {
    _wobbleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _wobbleAnim,
      builder: (context, child) {
        return Transform.rotate(
          angle: widget.isActive ? _wobbleAnim.value : 0.0,
          child: child,
        );
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color:
                  widget.isActive
                      ? Colors.red.withValues(
                        alpha: widget.isDark ? 0.25 : 0.08,
                      )
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border:
                  widget.isActive
                      ? Border.all(
                        color: Colors.red.withValues(alpha: 0.5),
                        width: 2,
                      )
                      : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.auto_fix_high_rounded,
                  size: 20,
                  color:
                      widget.isActive
                          ? Colors.red
                          : cs.onSurface.withValues(alpha: 0.6),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Toggle between whole-stroke and partial-stroke erasing
class ToolbarEraseModeToggle extends StatelessWidget {
  final bool isWholeStroke;
  final ValueChanged<bool> onChanged;
  final bool isDark;

  const ToolbarEraseModeToggle({
    super.key,
    required this.isWholeStroke,
    required this.onChanged,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Tooltip(
        message: isWholeStroke ? 'Whole stroke' : 'Partial erase',
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onChanged(!isWholeStroke);
          },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color:
                  isDark
                      ? const Color(0xFFB71C1C).withValues(alpha: 0.3)
                      : const Color(0xFFFFEBEE),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color:
                    isDark ? const Color(0xFFC62828) : const Color(0xFFEF9A9A),
              ),
            ),
            child: Icon(
              isWholeStroke ? Icons.delete_sweep_rounded : Icons.content_cut,
              size: 16,
              color: isDark ? const Color(0xFFE57373) : const Color(0xFFE53935),
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact eraser size slider
class ToolbarEraserSizeSlider extends StatelessWidget {
  final double radius;
  final ValueChanged<double> onChanged;
  final bool isDark;

  const ToolbarEraserSizeSlider({
    super.key,
    required this.radius,
    required this.onChanged,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color:
            isDark
                ? const Color(0xFFB71C1C).withValues(alpha: 0.3)
                : const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? const Color(0xFFC62828) : const Color(0xFFEF9A9A),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.circle,
            size: 8,
            color: isDark ? const Color(0xFFE57373) : const Color(0xFFEF5350),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                trackHeight: 3,
                activeTrackColor:
                    isDark ? const Color(0xFFE57373) : const Color(0xFFEF5350),
                inactiveTrackColor:
                    isDark ? const Color(0xFFB71C1C) : const Color(0xFFFFCDD2),
                thumbColor:
                    isDark ? const Color(0xFFEF9A9A) : const Color(0xFFE53935),
              ),
              child: Slider(
                value: radius,
                min: 5.0,
                max: 80.0,
                label: '${radius.round()}px',
                onChanged: (value) {
                  HapticFeedback.selectionClick();
                  onChanged(value);
                },
              ),
            ),
          ),
          Icon(
            Icons.circle,
            size: 14,
            color: isDark ? const Color(0xFFE57373) : const Color(0xFFEF5350),
          ),
        ],
      ),
    );
  }
}
