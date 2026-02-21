import 'package:flutter/material.dart';
import '../nebula_realtime_adapter.dart';

/// 👥 Connected Users Toolbar Widget
///
/// Shows avatars/initials of currently connected collaborators in a
/// compact horizontal strip. Tap a user to follow their viewport.
///
/// Designed to be placed in the toolbar or app bar.
class ConnectedUsersStrip extends StatelessWidget {
  /// The realtime engine providing remote cursor data.
  final NebulaRealtimeEngine? engine;

  /// Callback fired when a user avatar is tapped (for follow mode).
  final void Function(String userId)? onTapUser;

  /// Currently followed user ID (highlighted with a border).
  final String? followingUserId;

  /// Max avatars to show before overflow indicator.
  final int maxVisible;

  const ConnectedUsersStrip({
    super.key,
    required this.engine,
    this.onTapUser,
    this.followingUserId,
    this.maxVisible = 5,
  });

  @override
  Widget build(BuildContext context) {
    if (engine == null) return const SizedBox.shrink();

    return ValueListenableBuilder<Map<String, Map<String, dynamic>>>(
      valueListenable: engine!.remoteCursors,
      builder: (context, cursors, _) {
        if (cursors.isEmpty) return const SizedBox.shrink();

        final entries = cursors.entries.toList();
        final visible =
            entries.length > maxVisible
                ? entries.sublist(0, maxVisible)
                : entries;
        final overflow = entries.length - maxVisible;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 🟢 Connection indicator
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: _connectionColor(engine!.connectionState.value),
                  shape: BoxShape.circle,
                ),
              ),
              // 👥 User avatars
              ...visible.map((entry) {
                final data = entry.value;
                final name =
                    (data['n'] ?? data['displayName']) as String? ?? '?';
                final colorValue =
                    (data['c'] ?? data['cursorColor']) as int? ?? 0xFF42A5F5;
                final color = Color(colorValue);
                final isDrawing =
                    (data['d'] ?? data['isDrawing']) as bool? ?? false;
                final isTyping =
                    (data['t'] ?? data['isTyping']) as bool? ?? false;
                final isFollowing = followingUserId == entry.key;
                final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: GestureDetector(
                    onTap: () => onTapUser?.call(entry.key),
                    child: Tooltip(
                      message: isFollowing ? '$name (following)' : name,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color:
                                isFollowing ? Colors.white : Colors.transparent,
                            width: isFollowing ? 2.5 : 0,
                          ),
                          boxShadow: [
                            if (isDrawing || isTyping)
                              BoxShadow(
                                color: color.withValues(alpha: 0.6),
                                blurRadius: 6,
                                spreadRadius: 1,
                              ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            initial,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
              // Overflow indicator
              if (overflow > 0)
                Container(
                  width: 28,
                  height: 28,
                  margin: const EdgeInsets.only(left: 2),
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outline,
                      width: 1,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      '+$overflow',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Color _connectionColor(RealtimeConnectionState state) {
    switch (state) {
      case RealtimeConnectionState.connected:
        return Colors.green;
      case RealtimeConnectionState.connecting:
      case RealtimeConnectionState.reconnecting:
        return Colors.orange;
      case RealtimeConnectionState.disconnected:
      case RealtimeConnectionState.error:
        return Colors.red;
    }
  }
}
