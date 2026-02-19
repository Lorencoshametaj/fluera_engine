import 'package:flutter/material.dart';
import '../../core/nodes/pdf_document_node.dart';
import '../../core/nodes/pdf_page_node.dart';

// =============================================================================
// 📑 PDF THUMBNAIL SIDEBAR — Navigable page miniature strip
// =============================================================================

/// Callback when a thumbnail is tapped.
typedef PdfThumbnailTapCallback = void Function(int pageIndex);

/// Callback when pages are reordered via drag.
typedef PdfThumbnailReorderCallback = void Function(int oldIndex, int newIndex);

/// 📑 Material 3 thumbnail sidebar for PDF page navigation.
///
/// Displays vertically-scrollable miniatures of all PDF pages using cached
/// images from [PdfPageNode.cachedImage]. Supports:
/// - **Tap to navigate** — calls [onPageTapped]
/// - **Drag to reorder** — calls [onPageReordered]
/// - **Visual selection** — highlights the selected page
/// - **Page number badges** — shows 1-based page numbers
///
/// DESIGN PRINCIPLES:
/// - Uses cached images — no extra rendering overhead
/// - Lazy ListView.builder for scalability to 1000+ pages
/// - Material 3 design with rounded cards and elevation
/// - Reorder uses Flutter's ReorderableListView
class PdfThumbnailSidebar extends StatefulWidget {
  /// The PDF document to show thumbnails for.
  final PdfDocumentNode document;

  /// Currently selected page index.
  final int selectedPageIndex;

  /// Called when a thumbnail is tapped.
  final PdfThumbnailTapCallback? onPageTapped;

  /// Called when a page is reordered by drag.
  final PdfThumbnailReorderCallback? onPageReordered;

  /// Width of the sidebar.
  final double width;

  const PdfThumbnailSidebar({
    super.key,
    required this.document,
    this.selectedPageIndex = 0,
    this.onPageTapped,
    this.onPageReordered,
    this.width = 120,
  });

  @override
  State<PdfThumbnailSidebar> createState() => _PdfThumbnailSidebarState();
}

class _PdfThumbnailSidebarState extends State<PdfThumbnailSidebar> {
  final ScrollController _scrollController = ScrollController();

  List<PdfPageNode> get _pages => widget.document.pageNodes;

  // I12: Estimated item height for auto-scroll calculation
  static const double _estimatedItemHeight = 140.0;

  @override
  void didUpdateWidget(covariant PdfThumbnailSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // I12: Auto-scroll to newly selected page
    if (oldWidget.selectedPageIndex != widget.selectedPageIndex &&
        _scrollController.hasClients) {
      final targetOffset = widget.selectedPageIndex * _estimatedItemHeight;
      final maxScroll = _scrollController.position.maxScrollExtent;
      _scrollController.animateTo(
        targetOffset.clamp(0.0, maxScroll),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: widget.width,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(
          right: BorderSide(color: colorScheme.outlineVariant, width: 0.5),
        ),
      ),
      child: Column(
        children: [
          // Header
          _buildHeader(colorScheme),
          const Divider(height: 1),
          // Thumbnail list
          Expanded(
            child:
                _pages.isEmpty
                    ? _buildEmptyState(colorScheme)
                    : _buildThumbnailList(colorScheme),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Icon(
            Icons.view_sidebar,
            size: 18,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Text(
            'Pages',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const Spacer(),
          Text(
            '${_pages.length}',
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme) {
    return Center(
      child: Text(
        'No pages',
        style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
      ),
    );
  }

  Widget _buildThumbnailList(ColorScheme colorScheme) {
    if (widget.onPageReordered != null) {
      return ReorderableListView.builder(
        scrollController: _scrollController,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        itemCount: _pages.length,
        onReorder: (oldIndex, newIndex) {
          // ReorderableListView gives newIndex shifted for removals
          if (newIndex > oldIndex) newIndex--;
          widget.onPageReordered?.call(oldIndex, newIndex);
        },
        itemBuilder:
            (context, index) => _buildThumbnailCard(
              key: ValueKey(_pages[index].id),
              page: _pages[index],
              index: index,
              colorScheme: colorScheme,
            ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      itemCount: _pages.length,
      itemBuilder:
          (context, index) => _buildThumbnailCard(
            page: _pages[index],
            index: index,
            colorScheme: colorScheme,
          ),
    );
  }

  Widget _buildThumbnailCard({
    Key? key,
    required PdfPageNode page,
    required int index,
    required ColorScheme colorScheme,
  }) {
    final isSelected = index == widget.selectedPageIndex;
    final pageSize = page.pageModel.originalSize;
    final aspectRatio =
        pageSize.width > 0 && pageSize.height > 0
            ? pageSize.width / pageSize.height
            : 0.707; // A4 fallback

    return Padding(
      key: key,
      padding: const EdgeInsets.only(bottom: 8),
      child: Tooltip(
        // I14: Page info tooltip
        message:
            'Page ${index + 1}${page.pageModel.isLocked ? ' (locked)' : ''}',
        waitDuration: const Duration(milliseconds: 500),
        child: GestureDetector(
          onTap: () => widget.onPageTapped?.call(index),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color:
                    isSelected
                        ? colorScheme.primary
                        : colorScheme.outlineVariant.withAlpha(128),
                width: isSelected ? 2 : 1,
              ),
              boxShadow:
                  isSelected
                      ? [
                        BoxShadow(
                          color: colorScheme.primary.withAlpha(40),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ]
                      : null,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: Stack(
                children: [
                  Column(
                    children: [
                      // Thumbnail image
                      AspectRatio(
                        aspectRatio: aspectRatio,
                        child: _buildThumbnailImage(page, colorScheme),
                      ),
                      // Page number badge
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        color:
                            isSelected
                                ? colorScheme.primaryContainer
                                : colorScheme.surfaceContainerHigh,
                        child: Text(
                          '${index + 1}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight:
                                isSelected ? FontWeight.w600 : FontWeight.w400,
                            color:
                                isSelected
                                    ? colorScheme.onPrimaryContainer
                                    : colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                  // I13: Lock icon overlay for locked pages
                  if (page.pageModel.isLocked)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: colorScheme.surface.withAlpha(180),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Icon(
                          Icons.lock,
                          size: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnailImage(PdfPageNode page, ColorScheme colorScheme) {
    if (page.cachedImage != null) {
      return RawImage(image: page.cachedImage, fit: BoxFit.cover);
    }

    // Placeholder for uncached pages
    return Container(
      color: colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.picture_as_pdf,
          size: 24,
          color: colorScheme.onSurfaceVariant.withAlpha(100),
        ),
      ),
    );
  }
}
