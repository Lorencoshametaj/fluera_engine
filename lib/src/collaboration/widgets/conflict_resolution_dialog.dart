import 'package:flutter/material.dart';
import '../conflict_resolution.dart';
import '../nebula_realtime_adapter.dart';

/// 🔀 Conflict Resolution Dialog
///
/// Displays a Material 3 bottom sheet showing the conflicting local and
/// remote versions, letting the user choose which to keep.
///
/// **Usage:**
/// ```dart
/// showConflictDialog(context, conflictRecord, resolver)
///   .then((result) {
///     if (result != null) applyEvent(result.resolvedEvent);
///   });
/// ```
Future<ConflictResult?> showConflictDialog(
  BuildContext context,
  ConflictRecord conflict, {
  ConflictResolver? resolver,
}) async {
  return showModalBottomSheet<ConflictResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder:
        (ctx) =>
            _ConflictResolutionSheet(conflict: conflict, resolver: resolver),
  );
}

class _ConflictResolutionSheet extends StatelessWidget {
  final ConflictRecord conflict;
  final ConflictResolver? resolver;

  const _ConflictResolutionSheet({required this.conflict, this.resolver});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ─── Handle bar ──────────────────────
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(
              color: colorScheme.onSurface.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // ─── Header ──────────────────────────
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.merge_type_rounded,
                    color: Colors.orange,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Conflict Detected',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        _describeConflict(),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // ─── Conflict details ────────────────
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _VersionCard(
                    title: 'Your Version',
                    subtitle: 'Local changes',
                    icon: Icons.person,
                    color: Colors.blue,
                    event: conflict.localEvent,
                    onSelect: () => _resolve(context, keepLocal: true),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 4,
                      horizontal: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'VS',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.orange,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _VersionCard(
                    title: 'Their Version',
                    subtitle: 'From ${conflict.remoteEvent.senderId}',
                    icon: Icons.people,
                    color: Colors.purple,
                    event: conflict.remoteEvent,
                    onSelect: () => _resolve(context, keepLocal: false),
                  ),
                ],
              ),
            ),
          ),

          // ─── Actions ─────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: colorScheme.outline.withValues(alpha: 0.2),
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _resolve(context, keepLocal: true),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Keep Mine'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blue,
                      side: const BorderSide(color: Colors.blue),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _resolve(context, keepLocal: false),
                    icon: const Icon(Icons.sync, size: 18),
                    label: const Text('Keep Theirs'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.purple,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _describeConflict() {
    final type = conflict.remoteEvent.type.name;
    final element = conflict.elementId ?? 'unknown';
    return 'Concurrent $type on element $element';
  }

  void _resolve(BuildContext context, {required bool keepLocal}) {
    final event = keepLocal ? conflict.localEvent : conflict.remoteEvent;
    final resolution =
        keepLocal
            ? ConflictResolution.keepLocal
            : ConflictResolution.keepRemote;

    resolver?.resolveManually(conflict, resolution);

    Navigator.of(context).pop(
      ConflictResult(
        resolvedEvent: event,
        resolution: resolution,
        description: keepLocal ? 'User kept local version' : 'User kept remote',
      ),
    );
  }
}

class _VersionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final CanvasRealtimeEvent event;
  final VoidCallback onSelect;

  const _VersionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.event,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onSelect,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                    const SizedBox(height: 6),
                    _PayloadPreview(event: event),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 14,
                color: colorScheme.onSurface.withValues(alpha: 0.3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PayloadPreview extends StatelessWidget {
  final CanvasRealtimeEvent event;
  const _PayloadPreview({required this.event});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries =
        event.payload.entries
            .where((e) => !e.key.startsWith('_'))
            .take(3)
            .toList();

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children:
          entries.map((e) {
            final value =
                e.value is String
                    ? (e.value as String).length > 20
                        ? '"${(e.value as String).substring(0, 20)}…"'
                        : '"${e.value}"'
                    : '${e.value}';
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${e.key}: $value',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontFamily: 'monospace',
                  fontSize: 10,
                ),
              ),
            );
          }).toList(),
    );
  }
}
