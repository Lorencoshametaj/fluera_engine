/// 📜 VERSION HISTORY PANEL — UI for browsing and restoring named versions.
///
/// Slide-out panel showing version entries with restore actions.
///
/// ```dart
/// VersionHistoryPanel(
///   history: versionHistory,
///   onRestore: (entry) => applySnapshot(entry.data),
///   onDelete: (entry) => history.deleteEntry(entry.id),
/// )
/// ```
library;

import 'package:flutter/material.dart';
import '../../history/version_history.dart';

/// Side panel widget for browsing version history.
class VersionHistoryPanel extends StatelessWidget {
  final VersionHistory history;
  final void Function(VersionEntry entry)? onRestore;
  final void Function(VersionEntry entry)? onDelete;
  final void Function()? onClose;
  final void Function(String title)? onCreateVersion;

  const VersionHistoryPanel({
    super.key,
    required this.history,
    this.onRestore,
    this.onDelete,
    this.onClose,
    this.onCreateVersion,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
                const Icon(Icons.history, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Version History',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add, size: 18),
                  tooltip: 'Save version',
                  onPressed: () => _showCreateDialog(context),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: onClose,
                ),
              ],
            ),
          ),
          // Version list
          Expanded(
            child:
                history.entries.isEmpty
                    ? Center(
                      child: Text(
                        'No versions yet',
                        style: TextStyle(color: cs.onSurface.withAlpha(100)),
                      ),
                    )
                    : ListView.builder(
                      itemCount: history.entries.length,
                      itemBuilder: (context, i) {
                        final entry = history.entries[i];
                        return _VersionTile(
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
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Save Version'),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Version name...',
                border: OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  if (controller.text.trim().isNotEmpty) {
                    onCreateVersion?.call(controller.text.trim());
                    Navigator.pop(ctx);
                  }
                },
                child: const Text('Save'),
              ),
            ],
          ),
    );
  }
}

class _VersionTile extends StatelessWidget {
  final VersionEntry entry;
  final VoidCallback? onRestore;
  final VoidCallback? onDelete;

  const _VersionTile({required this.entry, this.onRestore, this.onDelete});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 14,
        backgroundColor: cs.primary.withAlpha(30),
        child: Icon(Icons.save, size: 14, color: cs.primary),
      ),
      title: Text(
        entry.title,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        '${entry.authorId} · ${_formatDate(entry.createdAt)}',
        style: TextStyle(fontSize: 11, color: cs.onSurface.withAlpha(130)),
      ),
      trailing: PopupMenuButton<String>(
        itemBuilder:
            (_) => [
              const PopupMenuItem(value: 'restore', child: Text('Restore')),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
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
