import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../storage/spatial_bookmark.dart';
import '../navigation/bookmark_thumbnail_cache.dart';
import '../navigation/spatial_bookmark_controller.dart';

/// 📌 BOOKMARK LIST SHEET — bottom sheet showing a grid of saved bookmarks.
///
/// Pedagogical contract (§1972-1977):
///   "Un gesto (es. menu rapido) mostra la lista dei segnalibri con
///    anteprima della zona."
///
/// UI tree:
///   Header (title + count + close)
///   GridView (2 cols, 1:1 aspect):
///     each cell = thumbnail + label + tap-to-fly + long-press-actions
///   Footer hint (empty state) when no bookmarks
///
/// Thumbnail flow:
///   - On open, [thumbnailLoader] is invoked for each bookmark whose
///     thumbnail is missing from the cache
///   - Cells show a shimmer placeholder until the [ui.Image] arrives
///   - On rebuild (cache hit), the image is painted via RawImage
///
/// Keep this widget free of business logic — it asks the parent for
/// callbacks and never touches the canvas controller directly.
class BookmarkListSheet extends StatefulWidget {
  final SpatialBookmarkController controller;
  final BookmarkThumbnailCache thumbnailCache;

  /// Called when the user taps a bookmark — caller animates the camera.
  final void Function(SpatialBookmark bookmark) onNavigate;

  /// Called when the user long-presses → "Rinomina". Caller is responsible
  /// for showing the rename dialog and committing via controller.rename.
  final void Function(SpatialBookmark bookmark) onRename;

  /// Called on "Elimina" with confirm. Caller deletes via controller.remove
  /// + invalidates the thumbnail cache entry.
  final void Function(SpatialBookmark bookmark) onDelete;

  /// Asked to lazily generate a thumbnail for [bookmark].
  /// Returns the [ui.Image] or null if no content / generation failed.
  final Future<ui.Image?> Function(SpatialBookmark bookmark) thumbnailLoader;

  const BookmarkListSheet({
    super.key,
    required this.controller,
    required this.thumbnailCache,
    required this.onNavigate,
    required this.onRename,
    required this.onDelete,
    required this.thumbnailLoader,
  });

  @override
  State<BookmarkListSheet> createState() => _BookmarkListSheetState();
}

class _BookmarkListSheetState extends State<BookmarkListSheet> {
  /// Tracks which bookmark ids have an in-flight thumbnail load. Prevents
  /// double-firing the loader for the same id from rapid rebuilds.
  final Set<String> _loadingIds = {};

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    // Kick off thumbnail generation for any bookmark missing one.
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureThumbnails());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  void _ensureThumbnails() {
    for (final bm in widget.controller.bookmarks) {
      if (widget.thumbnailCache.has(bm.id)) continue;
      if (_loadingIds.contains(bm.id)) continue;
      _loadingIds.add(bm.id);
      widget.thumbnailLoader(bm).whenComplete(() {
        _loadingIds.remove(bm.id);
        if (mounted) setState(() {});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bookmarks = widget.controller.bookmarks;
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
              child: Row(
                children: [
                  const Icon(Icons.bookmarks, size: 22),
                  const SizedBox(width: 10),
                  Text(
                    'Bookmarks',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '(${bookmarks.length})',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
            ),
            // Body
            Expanded(
              child: bookmarks.isEmpty
                  ? _EmptyState()
                  : GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 0.85,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: bookmarks.length,
                      itemBuilder: (context, index) {
                        final bm = bookmarks[index];
                        return _BookmarkCell(
                          bookmark: bm,
                          thumbnail: widget.thumbnailCache.get(bm.id),
                          onTap: () {
                            Navigator.of(context).maybePop();
                            widget.onNavigate(bm);
                          },
                          onRename: () => widget.onRename(bm),
                          onDelete: () => widget.onDelete(bm),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BookmarkCell extends StatelessWidget {
  final SpatialBookmark bookmark;
  final ui.Image? thumbnail;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _BookmarkCell({
    required this.bookmark,
    required this.thumbnail,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        onLongPress: () => _showActionMenu(context),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: thumbnail != null
                      ? RawImage(
                          image: thumbnail,
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.medium,
                        )
                      : _ThumbnailPlaceholder(),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                bookmark.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showActionMenu(BuildContext context) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Rinomina'),
              onTap: () => Navigator.of(ctx).pop('rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline,
                  color: Color(0xFFE53935)),
              title: const Text('Elimina',
                  style: TextStyle(color: Color(0xFFE53935))),
              onTap: () => Navigator.of(ctx).pop('delete'),
            ),
          ],
        ),
      ),
    );
    if (action == 'rename') onRename();
    if (action == 'delete') onDelete();
  }
}

class _ThumbnailPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Container(
      color: c.surface,
      alignment: Alignment.center,
      child: Icon(
        Icons.image_outlined,
        size: 32,
        color: c.onSurface.withValues(alpha: 0.18),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.bookmarks_outlined,
              size: 48,
              color: c.onSurface.withValues(alpha: 0.25),
            ),
            const SizedBox(height: 12),
            Text(
              'Nessun bookmark ancora',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: c.onSurface.withValues(alpha: 0.7),
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Long-press su area vuota → "📌 Bookmark"',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: c.onSurface.withValues(alpha: 0.45),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
