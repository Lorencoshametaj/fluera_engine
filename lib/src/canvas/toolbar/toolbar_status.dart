import 'package:flutter/material.dart';
import '../../storage/fluera_cloud_adapter.dart';

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

/// ToolbarTimeTravelButton removed 2026-05-16: chip consolidated
/// into the CognitiveFeaturesSheet. Callback `onTimeTravelPressed`
/// is invoked via the sheet's actions map (see _ui_toolbar.dart).

/// Section wrapper used across the tools-area toolbar. Originally
/// rendered an uppercase title + icon header above the payload, but
/// the labels (PEN / COLOR / THICKNESS / OPACITY) added ~16dp of
/// vertical clutter while the icons inside each section already
/// communicate purpose. Now it's a transparent passthrough.
///
/// The `title` / `icon` / `isDark` fields are kept on the constructor
/// so existing call sites don't need touching; they're accepted and
/// ignored. Tooltip discovery happens on the inner widgets themselves.
class ToolbarToolSection extends StatelessWidget {
  // ignore: unused_element
  final String title;
  // ignore: unused_element
  final IconData icon;
  // ignore: unused_element
  final bool isDark;
  final Widget child;

  const ToolbarToolSection({
    super.key,
    required this.title,
    required this.icon,
    required this.isDark,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => child;
}

/// Compact icon-only indicator for the cloud-sync state. Pinned next to
/// the branch chip on the top row so users see "saving…" / "error"
/// without having to open a settings sheet. The host controls
/// visibility (typically hidden on idle).
class ToolbarCloudSyncIndicator extends StatelessWidget {
  final FlueraSyncState state;
  /// Optional 0..1 progress hint for the syncing state. Reserved for
  /// future use; ignored when state != syncing.
  final double progress;

  const ToolbarCloudSyncIndicator({
    super.key,
    required this.state,
    this.progress = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (icon, color, tooltip) = switch (state) {
      FlueraSyncState.idle => (
        Icons.cloud_done_rounded,
        cs.onSurfaceVariant,
        'Synced',
      ),
      FlueraSyncState.syncing => (
        Icons.cloud_sync_rounded,
        cs.primary,
        'Syncing…',
      ),
      FlueraSyncState.error => (
        Icons.cloud_off_rounded,
        cs.error,
        'Sync error',
      ),
    };
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: SizedBox(
        width: 22,
        height: 22,
        child: Icon(icon, size: 16, color: color),
      ),
    );
  }
}
