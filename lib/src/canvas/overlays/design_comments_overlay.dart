/// 💬 DESIGN COMMENTS OVERLAY — Pins and thread panel for canvas comments.
///
/// Shows comment pins at anchored positions on the canvas, and opens
/// a thread panel on tap for viewing/adding replies.
///
/// ```dart
/// DesignCommentsOverlay(
///   system: designCommentSystem,
///   canvasOffset: offset,
///   canvasScale: scale,
///   onAddThread: (position) => ...,
/// )
/// ```
library;

import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../collaboration/design_comment.dart';

/// Overlay that renders comment pins on the canvas.
class DesignCommentsOverlay extends StatelessWidget {
  /// The comment system with all threads.
  final DesignCommentSystem system;

  /// Current canvas pan offset.
  final Offset canvasOffset;

  /// Current canvas zoom scale.
  final double canvasScale;

  /// Callback when a thread pin is tapped.
  final void Function(CommentThread thread)? onThreadTap;

  /// Currently selected thread ID (for highlighting).
  final String? selectedThreadId;

  const DesignCommentsOverlay({
    super.key,
    required this.system,
    required this.canvasOffset,
    required this.canvasScale,
    this.onThreadTap,
    this.selectedThreadId,
  });

  @override
  Widget build(BuildContext context) {
    final threads =
        system.threads.values.where((t) => t.anchorPosition != null).toList();

    if (threads.isEmpty) return const SizedBox.shrink();

    return IgnorePointer(
      ignoring: false,
      child: Stack(
        clipBehavior: Clip.none,
        children:
            threads.map((thread) {
              final pos = thread.anchorPosition!;
              final screenX = pos.dx * canvasScale + canvasOffset.dx;
              final screenY = pos.dy * canvasScale + canvasOffset.dy;
              final isSelected = thread.id == selectedThreadId;

              return Positioned(
                left: screenX - 14,
                top: screenY - 14,
                child: GestureDetector(
                  onTap: () => onThreadTap?.call(thread),
                  child: _CommentPin(thread: thread, isSelected: isSelected),
                ),
              );
            }).toList(),
      ),
    );
  }
}

/// A single comment pin icon.
class _CommentPin extends StatelessWidget {
  final CommentThread thread;
  final bool isSelected;

  const _CommentPin({required this.thread, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    final color =
        thread.isResolved
            ? Colors.green
            : (isSelected ? Colors.blue : Colors.orange);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: isSelected ? 3 : 2),
        boxShadow: [
          BoxShadow(color: color.withAlpha(80), blurRadius: isSelected ? 8 : 4),
        ],
      ),
      child: Center(
        child: Text(
          '${thread.commentCount}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet panel for viewing a comment thread.
class CommentThreadPanel extends StatelessWidget {
  final CommentThread thread;
  final void Function(String text)? onAddReply;
  final void Function()? onResolve;
  final void Function()? onClose;

  const CommentThreadPanel({
    super.key,
    required this.thread,
    this.onAddReply,
    this.onResolve,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 400),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(30),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                Icon(
                  thread.isResolved ? Icons.check_circle : Icons.chat_bubble,
                  size: 18,
                  color: thread.isResolved ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    thread.isResolved ? 'Resolved' : 'Open Thread',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (!thread.isResolved)
                  TextButton.icon(
                    onPressed: onResolve,
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Resolve'),
                  ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: onClose,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Comments
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                _CommentBubble(comment: thread.rootComment, isRoot: true),
                ...thread.replies.map(
                  (r) => _CommentBubble(comment: r, isRoot: false),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentBubble extends StatelessWidget {
  final DesignComment comment;
  final bool isRoot;

  const _CommentBubble({required this.comment, required this.isRoot});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: isRoot ? 0 : 24, bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: isRoot ? Colors.blue : Colors.grey.shade600,
            child: Text(
              comment.authorName.isNotEmpty
                  ? comment.authorName[0].toUpperCase()
                  : '?',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  comment.authorName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(comment.text, style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
