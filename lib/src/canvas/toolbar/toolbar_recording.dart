import 'package:flutter/material.dart';

// ============================================================================
// TOOLBAR RECORDING — Recording button (pulse) + view recordings
// ============================================================================

/// Recording button with pulse animation when active
class ToolbarRecordingButton extends StatefulWidget {
  final bool isActive;
  final Duration duration;
  final VoidCallback onTap;
  final bool isDark;

  const ToolbarRecordingButton({
    super.key,
    required this.isActive,
    required this.duration,
    required this.onTap,
    required this.isDark,
  });

  @override
  State<ToolbarRecordingButton> createState() => _ToolbarRecordingButtonState();
}

class _ToolbarRecordingButtonState extends State<ToolbarRecordingButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Active recording state with pulse animation
    if (widget.isActive) {
      return AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          final minutes = widget.duration.inMinutes.toString().padLeft(2, '0');
          final seconds = (widget.duration.inSeconds % 60).toString().padLeft(
            2,
            '0',
          );

          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(15),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: cs.error,
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [
                    BoxShadow(
                      color: cs.error.withValues(
                        alpha: 0.3 + _pulseController.value * 0.3,
                      ),
                      blurRadius: 8 + _pulseController.value * 8,
                      spreadRadius: _pulseController.value * 2,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Pulsing dot
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: cs.onError.withValues(
                          alpha: 0.7 + _pulseController.value * 0.3,
                        ),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Timer
                    Text(
                      '$minutes:$seconds',
                      style: TextStyle(
                        color: cs.onError,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Stop icon
                    Icon(Icons.stop_rounded, size: 18, color: cs.onError),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }

    // Inactive state — mic icon
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.mic_rounded,
            size: 20,
            color: cs.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }
}

/// Button to view saved recordings
class ToolbarViewRecordingsButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool isDark;

  const ToolbarViewRecordingsButton({
    super.key,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.headphones_rounded,
            size: 20,
            color: cs.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }
}
