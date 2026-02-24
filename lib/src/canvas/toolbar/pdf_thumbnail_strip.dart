import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/nodes/pdf_document_node.dart';
import '../../core/nodes/pdf_page_node.dart';

/// 📄 Horizontal thumbnail strip for PDF page navigation.
///
/// Shows miniaturized page previews with the selected page highlighted.
/// Tapping a thumbnail triggers [onPageSelected]. Supports reordering
/// via long-press drag (when [onPageReordered] is provided).
class PdfThumbnailStrip extends StatelessWidget {
  final PdfDocumentNode doc;
  final int selectedPageIndex;
  final ValueChanged<int> onPageSelected;

  /// Called when a page is reordered via drag.
  /// Parameters: (oldIndex, newIndex).
  final void Function(int oldIndex, int newIndex)? onPageReordered;

  /// Height of the thumbnail strip (default: 80).
  final double height;

  const PdfThumbnailStrip({
    super.key,
    required this.doc,
    required this.selectedPageIndex,
    required this.onPageSelected,
    this.onPageReordered,
    this.height = 80,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pages = doc.pageNodes;
    final thumbHeight = height - 16; // padding
    // Aspect ratio from first page (fallback to A4)
    final refSize =
        pages.isNotEmpty
            ? pages.first.pageModel.originalSize
            : const Size(612, 792);
    final aspectRatio = refSize.width / refSize.height;
    final thumbWidth = thumbHeight * aspectRatio;

    if (onPageReordered != null) {
      return SizedBox(
        height: height,
        child: ReorderableListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          buildDefaultDragHandles: false,
          itemCount: pages.length,
          onReorder: onPageReordered!,
          proxyDecorator: (child, index, animation) {
            return Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(6),
              child: child,
            );
          },
          itemBuilder: (context, index) {
            return _PageThumb(
              key: ValueKey(pages[index].id),
              page: pages[index],
              index: index,
              isSelected: index == selectedPageIndex,
              width: thumbWidth,
              height: thumbHeight,
              cs: cs,
              onTap: () => onPageSelected(index),
              reorderable: true,
            );
          },
        ),
      );
    }

    return SizedBox(
      height: height,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        itemCount: pages.length,
        itemBuilder: (context, index) {
          return _PageThumb(
            key: ValueKey(pages[index].id),
            page: pages[index],
            index: index,
            isSelected: index == selectedPageIndex,
            width: thumbWidth,
            height: thumbHeight,
            cs: cs,
            onTap: () => onPageSelected(index),
          );
        },
      ),
    );
  }
}

class _PageThumb extends StatelessWidget {
  final PdfPageNode page;
  final int index;
  final bool isSelected;
  final double width;
  final double height;
  final ColorScheme cs;
  final VoidCallback onTap;
  final bool reorderable;

  const _PageThumb({
    super.key,
    required this.page,
    required this.index,
    required this.isSelected,
    required this.width,
    required this.height,
    required this.cs,
    required this.onTap,
    this.reorderable = false,
  });

  @override
  Widget build(BuildContext context) {
    final isBookmarked = page.pageModel.isBookmarked;
    final isBlank = page.pageModel.isBlank;

    Widget thumb = GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        width: width,
        height: height,
        margin: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: isBlank ? cs.surfaceContainerHighest : Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? cs.primary : cs.outlineVariant,
            width: isSelected ? 2.5 : 1,
          ),
          boxShadow:
              isSelected
                  ? [
                    BoxShadow(
                      color: cs.primary.withValues(alpha: 0.3),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ]
                  : null,
        ),
        child: Stack(
          children: [
            // Page number
            Center(
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                  color:
                      isSelected
                          ? cs.primary
                          : cs.onSurfaceVariant.withValues(alpha: 0.5),
                ),
              ),
            ),
            // Bookmark indicator
            if (isBookmarked)
              Positioned(
                top: 0,
                right: 0,
                child: CustomPaint(
                  size: const Size(12, 12),
                  painter: _BookmarkTrianglePainter(cs.error),
                ),
              ),
          ],
        ),
      ),
    );

    if (reorderable) {
      thumb = ReorderableDragStartListener(index: index, child: thumb);
    }

    return thumb;
  }
}

class _BookmarkTrianglePainter extends CustomPainter {
  final Color color;
  _BookmarkTrianglePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final path =
        Path()
          ..moveTo(0, 0)
          ..lineTo(size.width, 0)
          ..lineTo(size.width, size.height)
          ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _BookmarkTrianglePainter old) =>
      color != old.color;
}
