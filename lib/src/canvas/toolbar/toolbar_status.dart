import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../storage/nebula_cloud_adapter.dart';

// ============================================================================
// TOOLBAR STATUS WIDGETS — Compact actions, tool sections, time travel, cloud
// ============================================================================

/// Compact action button for quick actions (undo, redo, layers, etc.)
class ToolbarCompactActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final bool isDark;
  final bool isEnabled;

  const ToolbarCompactActionButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    required this.isDark,
    required this.isEnabled,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: IconButton(
        icon: Icon(icon, size: 18),
        onPressed: isEnabled ? onPressed : null,
        padding: const EdgeInsets.all(6),
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        color: isEnabled ? cs.onSurface : cs.onSurface.withValues(alpha: 0.3),
      ),
    );
  }
}

/// Time Travel button with scale-bounce + rotation animation
class ToolbarTimeTravelButton extends StatefulWidget {
  final VoidCallback onPressed;
  final bool isDark;

  const ToolbarTimeTravelButton({
    super.key,
    required this.onPressed,
    required this.isDark,
  });

  @override
  State<ToolbarTimeTravelButton> createState() =>
      _ToolbarTimeTravelButtonState();
}

class _ToolbarTimeTravelButtonState extends State<ToolbarTimeTravelButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() {
    HapticFeedback.lightImpact();
    _controller.forward(from: 0).then((_) {
      if (mounted) widget.onPressed();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        final scale = 1.0 - 0.2 * (t < 0.4 ? t / 0.4 : (1.0 - t) / 0.6);
        final rotation =
            t < 0.5 ? -0.125 * (t / 0.5) : -0.125 * ((1.0 - t) / 0.5);

        return Transform.scale(
          scale: scale,
          child: Transform.rotate(angle: rotation * 2 * 3.14159, child: child),
        );
      },
      child: Tooltip(
        message: 'Time Travel',
        waitDuration: const Duration(milliseconds: 400),
        child: IconButton(
          icon: const Icon(Icons.history_rounded, size: 18),
          onPressed: _handleTap,
          padding: const EdgeInsets.all(6),
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          color: cs.onSurface,
          splashColor: cs.primary.withValues(alpha: 0.2),
          highlightColor: cs.primary.withValues(alpha: 0.1),
        ),
      ),
    );
  }
}

/// Tool section wrapper — passes through child with no chrome.
class ToolbarToolSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final bool isDark;

  const ToolbarToolSection({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return child;
  }
}

/// Compact cloud sync status indicator with animated icon + progress ring
class ToolbarCloudSyncIndicator extends StatefulWidget {
  final NebulaSyncState state;
  final double progress;
  const ToolbarCloudSyncIndicator({
    super.key,
    required this.state,
    this.progress = 0.0,
  });

  @override
  State<ToolbarCloudSyncIndicator> createState() =>
      _ToolbarCloudSyncIndicatorState();
}

class _ToolbarCloudSyncIndicatorState extends State<ToolbarCloudSyncIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pulseAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    if (widget.state != NebulaSyncState.error) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant ToolbarCloudSyncIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state == NebulaSyncState.error) {
      _pulseController.stop();
      _pulseController.value = 1.0;
    } else if (!_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final iconData = switch (widget.state) {
      NebulaSyncState.syncing => Icons.cloud_upload_rounded,
      NebulaSyncState.error => Icons.cloud_off_rounded,
      NebulaSyncState.idle => Icons.cloud_done_rounded,
    };

    final color =
        widget.state == NebulaSyncState.error ? Colors.amber : cs.primary;

    final isActive = widget.state == NebulaSyncState.syncing;

    return SizedBox(
      width: 20,
      height: 20,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (isActive && widget.progress > 0)
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                value: widget.progress,
                strokeWidth: 1.5,
                color: color.withValues(alpha: 0.6),
              ),
            ),
          FadeTransition(
            opacity: _pulseAnimation,
            child: Icon(iconData, size: 12, color: color),
          ),
        ],
      ),
    );
  }
}
