/// 📍 CHECKPOINT PANEL — Browse, save and restore canvas checkpoints.
///
/// Tier-aware: Free shows "used/3" counter and a soft upsell modal when the
/// limit is reached. Plus/Pro: counter hidden, unlimited.
library;

import 'package:flutter/material.dart';
import '../../l10n/fluera_localizations.dart';
import '../../history/version_history.dart';
import '../fluera_canvas_config.dart' show FlueraSubscriptionTier;

/// Side panel widget for browsing checkpoint history.
class VersionHistoryPanel extends StatelessWidget {
  final VersionHistory history;
  final FlueraSubscriptionTier tier;
  final void Function(VersionEntry entry)? onRestore;
  final void Function(VersionEntry entry)? onDelete;
  final void Function()? onClose;
  final void Function(String title)? onCreateVersion;
  final VoidCallback? onUpgradePressed;

  const VersionHistoryPanel({
    super.key,
    required this.history,
    this.tier = FlueraSubscriptionTier.free,
    this.onRestore,
    this.onDelete,
    this.onClose,
    this.onCreateVersion,
    this.onUpgradePressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = FlueraLocalizations.of(context)!;
    final limit = CheckpointLimits.limitFor(tier);
    final isLimitReached = limit != null && history.length >= limit;

    return Container(
      width: 300,
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(left: BorderSide(color: cs.outline.withAlpha(30))),
        boxShadow: [
          BoxShadow(color: Colors.black.withAlpha(20), blurRadius: 12),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: cs.outline.withAlpha(20)),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.bookmark_outline_rounded, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.checkpoint_title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add, size: 18),
                  tooltip: l10n.versionHistory_saveVersion,
                  onPressed: () {
                    if (isLimitReached) {
                      _showLimitReachedModal(context);
                    } else {
                      _showCreateDialog(context);
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: onClose,
                ),
              ],
            ),
          ),
          // Counter (Free only)
          if (limit != null)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              decoration: BoxDecoration(
                color: isLimitReached
                    ? cs.errorContainer.withAlpha(60)
                    : cs.surfaceContainerHighest.withAlpha(60),
              ),
              child: Row(
                children: [
                  Icon(
                    isLimitReached
                        ? Icons.info_outline_rounded
                        : Icons.bookmark_outline_rounded,
                    size: 14,
                    color: isLimitReached
                        ? cs.error
                        : cs.onSurface.withAlpha(150),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l10n.checkpoint_counterFree(history.length, limit),
                      style: TextStyle(
                        fontSize: 11,
                        color: isLimitReached
                            ? cs.error
                            : cs.onSurface.withAlpha(150),
                        fontWeight: isLimitReached
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          // Checkpoint list
          Expanded(
            child:
                history.entries.isEmpty
                    ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              l10n.checkpoint_emptyTitle,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: cs.onSurface.withAlpha(180),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              l10n.checkpoint_emptyBody,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: cs.onSurface.withAlpha(100),
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    : ListView.builder(
                      itemCount: history.entries.length,
                      itemBuilder: (context, i) {
                        final entry = history.entries[i];
                        return _CheckpointTile(
                          entry: entry,
                          onRestore: () => onRestore?.call(entry),
                          onDelete: () => onDelete?.call(entry),
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }

  void _showCreateDialog(BuildContext context) {
    final controller = TextEditingController();
    final l10n = FlueraLocalizations.of(context)!;
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(l10n.checkpoint_saveTitle),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: l10n.checkpoint_nameHint,
                border: const OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(l10n.versionHistory_cancel),
              ),
              FilledButton(
                onPressed: () {
                  if (controller.text.trim().isNotEmpty) {
                    onCreateVersion?.call(controller.text.trim());
                    Navigator.pop(ctx);
                  }
                },
                child: Text(l10n.versionHistory_save),
              ),
            ],
          ),
    );
  }

  void _showLimitReachedModal(BuildContext context) {
    final l10n = FlueraLocalizations.of(context)!;
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            icon: const Icon(
              Icons.bookmark_border_rounded,
              size: 36,
              color: Color(0xFF7C4DFF),
            ),
            title: Text(l10n.checkpoint_limitReachedTitle),
            content: Text(
              l10n.checkpoint_limitReachedBody,
              style: const TextStyle(height: 1.4, fontSize: 14),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(l10n.checkpoint_archiveExisting),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  onUpgradePressed?.call();
                },
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF7C4DFF),
                ),
                child: Text(l10n.checkpoint_upgradeToPlus),
              ),
            ],
          ),
    );
  }
}

class _CheckpointTile extends StatelessWidget {
  final VersionEntry entry;
  final VoidCallback? onRestore;
  final VoidCallback? onDelete;

  const _CheckpointTile({required this.entry, this.onRestore, this.onDelete});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = FlueraLocalizations.of(context)!;
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 14,
        backgroundColor: cs.primary.withAlpha(30),
        child: Icon(Icons.bookmark_rounded, size: 14, color: cs.primary),
      ),
      title: Text(
        entry.title,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        l10n.checkpoint_savedAt(_formatDate(entry.createdAt)),
        style: TextStyle(fontSize: 11, color: cs.onSurface.withAlpha(130)),
      ),
      trailing: PopupMenuButton<String>(
        itemBuilder: (_) {
          return [
            PopupMenuItem(
              value: 'restore',
              child: Text(l10n.checkpoint_restore),
            ),
            PopupMenuItem(
              value: 'delete',
              child: Text(l10n.checkpoint_archive),
            ),
          ];
        },
        onSelected: (action) {
          if (action == 'restore') onRestore?.call();
          if (action == 'delete') onDelete?.call();
        },
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
