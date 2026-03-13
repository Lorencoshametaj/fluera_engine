import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../canvas/fluera_canvas_config.dart';
import '../core/models/pdf_document_model.dart';
import '../core/models/pdf_page_model.dart';
import '../rendering/canvas/pdf_page_painter.dart';
import '../rendering/canvas/pdf_memory_budget.dart';
import '../core/nodes/pdf_page_node.dart';
import '../core/scene_graph/node_id.dart';

/// 📖 Full-screen PDF reader mode.
///
/// Opened via long-press on a `PdfPreviewCardNode` on the canvas.
/// Displays all pages in a vertical scrollable list, each with a
/// drawing overlay for annotations. Provides a compact toolbar for
/// drawing tools and a thumbnail sidebar for page navigation.
///
/// This is a SEPARATE Flutter route — it has its own state, lifecycle,
/// and rendering pipeline. Annotations are persisted back to the
/// `PdfDocumentModel` on exit.
class PdfReaderScreen extends StatefulWidget {
  /// The full document model (pages, metadata, file path).
  final PdfDocumentModel documentModel;

  /// Native PDF rendering provider (already loaded).
  final FlueraPdfProvider provider;

  /// Document ID for painter/provider lookup.
  final String documentId;

  /// PDF page painter (reuses existing LOD pipeline).
  final PdfPagePainter pagePainter;

  /// Callback invoked when the reader closes.
  /// Returns updated document model if annotations changed.
  final void Function(PdfDocumentModel updatedModel)? onClose;

  const PdfReaderScreen({
    super.key,
    required this.documentModel,
    required this.provider,
    required this.documentId,
    required this.pagePainter,
    this.onClose,
  });

  @override
  State<PdfReaderScreen> createState() => _PdfReaderScreenState();
}

class _PdfReaderScreenState extends State<PdfReaderScreen> {
  late final ScrollController _scrollController;
  late final List<PdfPageNode> _pageNodes;

  /// Current visible page index (for page counter).
  int _currentPageIndex = 0;

  /// Whether the thumbnail sidebar is visible.
  bool _showSidebar = false;

  /// Control the entrance animation.
  bool _isAnimatingIn = true;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);

    // Create PdfPageNode instances for each page (used for rendering).
    _pageNodes = widget.documentModel.pages.map((pageModel) {
      return PdfPageNode(
        id: NodeId('${widget.documentId}_page_${pageModel.pageIndex}'),
        pageModel: pageModel,
        cachedScale: 1.0,
      );
    }).toList();

    // Trigger entrance animation
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _isAnimatingIn = false);
    });

    // Pre-render visible pages
    _warmUpVisiblePages();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    _updateCurrentPage();
  }

  void _updateCurrentPage() {
    if (!_scrollController.hasClients) return;
    final offset = _scrollController.offset;
    final viewportHeight = _scrollController.position.viewportDimension;

    // Find which page is most visible
    double accumulated = 0;
    for (int i = 0; i < _pageNodes.length; i++) {
      final pageHeight = _getPageDisplayHeight(i);
      final spacing = 16.0;
      final pageTop = accumulated;
      final pageBottom = accumulated + pageHeight;

      if (pageTop <= offset + viewportHeight / 2 && pageBottom > offset) {
        if (_currentPageIndex != i) {
          setState(() => _currentPageIndex = i);
        }
        break;
      }
      accumulated += pageHeight + spacing;
    }
  }

  double _getPageDisplayHeight(int pageIndex) {
    final page = widget.documentModel.pages[pageIndex];
    final screenWidth = MediaQuery.of(context).size.width - (_showSidebar ? 120 : 0) - 32;
    final aspect = page.originalSize.height / page.originalSize.width;
    return screenWidth * aspect;
  }

  void _warmUpVisiblePages() {
    widget.pagePainter.warmUpAllPages(
      _pageNodes,
      onNeedRepaint: () {
        if (mounted) setState(() {});
      },
    );
  }

  void _scrollToPage(int pageIndex) {
    double offset = 0;
    for (int i = 0; i < pageIndex; i++) {
      offset += _getPageDisplayHeight(i) + 16.0;
    }
    _scrollController.animateTo(
      offset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final totalPages = widget.documentModel.totalPages;

    return Theme(
      data: ThemeData.dark().copyWith(
        colorScheme: ColorScheme.dark(
          surface: const Color(0xFF1A1A2E),
          primary: const Color(0xFF6C63FF),
          onSurface: Colors.white,
        ),
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF1A1A2E),
        body: AnimatedOpacity(
          duration: const Duration(milliseconds: 300),
          opacity: _isAnimatingIn ? 0.0 : 1.0,
          child: SafeArea(
            child: Column(
              children: [
                // ── Top bar ──
                _buildTopBar(totalPages),

                // ── Main content ──
                Expanded(
                  child: Row(
                    children: [
                      // Thumbnail sidebar
                      if (_showSidebar) _buildThumbnailSidebar(),

                      // Page scroll view
                      Expanded(child: _buildPageList()),
                    ],
                  ),
                ),

                // ── Bottom bar ──
                _buildBottomBar(totalPages),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(int totalPages) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF16213E),
        border: Border(
          bottom: BorderSide(color: Color(0x22FFFFFF)),
        ),
      ),
      child: Row(
        children: [
          // Back button
          IconButton(
            onPressed: () {
              widget.onClose?.call(widget.documentModel);
              Navigator.of(context).pop();
            },
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            tooltip: 'Back to canvas',
          ),

          const SizedBox(width: 8),

          // PDF name
          Expanded(
            child: Text(
              widget.documentModel.fileName ?? 'PDF Document',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Sidebar toggle
          IconButton(
            onPressed: () => setState(() => _showSidebar = !_showSidebar),
            icon: Icon(
              _showSidebar ? Icons.view_sidebar : Icons.view_sidebar_outlined,
              color: _showSidebar ? const Color(0xFF6C63FF) : Colors.white70,
            ),
            tooltip: 'Toggle thumbnails',
          ),
        ],
      ),
    );
  }

  Widget _buildThumbnailSidebar() {
    return Container(
      width: 100,
      decoration: const BoxDecoration(
        color: Color(0xFF0F3460),
        border: Border(
          right: BorderSide(color: Color(0x22FFFFFF)),
        ),
      ),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: widget.documentModel.totalPages,
        itemBuilder: (context, index) {
          final isActive = index == _currentPageIndex;
          final page = widget.documentModel.pages[index];
          final aspect = page.originalSize.height / page.originalSize.width;

          return GestureDetector(
            onTap: () => _scrollToPage(index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isActive ? const Color(0xFF6C63FF) : Colors.transparent,
                  width: 2,
                ),
                boxShadow: isActive
                    ? [
                        BoxShadow(
                          color: const Color(0xFF6C63FF).withValues(alpha: 0.3),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: Column(
                children: [
                  // Thumbnail placeholder
                  Container(
                    width: 80,
                    height: 80 * aspect,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: _buildPageThumbnail(index),
                  ),
                  // Page number
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 2),
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        color: isActive ? const Color(0xFF6C63FF) : Colors.white54,
                        fontSize: 10,
                        fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPageThumbnail(int pageIndex) {
    final node = _pageNodes[pageIndex];
    if (node.cachedImage != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: RawImage(
          image: node.cachedImage,
          fit: BoxFit.cover,
        ),
      );
    }
    // Loading placeholder
    return Center(
      child: Text(
        '${pageIndex + 1}',
        style: const TextStyle(
          color: Color(0xFF999999),
          fontSize: 18,
          fontWeight: FontWeight.w300,
        ),
      ),
    );
  }

  Widget _buildPageList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _pageNodes.length,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _buildPageWidget(index),
        );
      },
    );
  }

  Widget _buildPageWidget(int pageIndex) {
    final page = widget.documentModel.pages[pageIndex];
    final node = _pageNodes[pageIndex];
    final screenWidth = MediaQuery.of(context).size.width - (_showSidebar ? 120 : 0) - 32;
    final aspect = page.originalSize.height / page.originalSize.width;
    final displayHeight = screenWidth * aspect;

    return Container(
      width: screenWidth,
      height: displayHeight,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x30000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CustomPaint(
          painter: _PdfPageViewPainter(
            node: node,
            pageSize: page.originalSize,
          ),
          size: Size(screenWidth, displayHeight),
        ),
      ),
    );
  }

  Widget _buildBottomBar(int totalPages) {
    return Container(
      height: 48,
      decoration: const BoxDecoration(
        color: Color(0xFF16213E),
        border: Border(
          top: BorderSide(color: Color(0x22FFFFFF)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Previous page
          IconButton(
            onPressed: _currentPageIndex > 0
                ? () => _scrollToPage(_currentPageIndex - 1)
                : null,
            icon: const Icon(Icons.chevron_left_rounded),
            iconSize: 20,
            color: Colors.white70,
            disabledColor: Colors.white24,
          ),

          // Page counter
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0x22FFFFFF),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Page ${_currentPageIndex + 1} of $totalPages',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.3,
              ),
            ),
          ),

          // Next page
          IconButton(
            onPressed: _currentPageIndex < totalPages - 1
                ? () => _scrollToPage(_currentPageIndex + 1)
                : null,
            icon: const Icon(Icons.chevron_right_rounded),
            iconSize: 20,
            color: Colors.white70,
            disabledColor: Colors.white24,
          ),
        ],
      ),
    );
  }
}

/// Custom painter for rendering a single PDF page with its cached image.
class _PdfPageViewPainter extends CustomPainter {
  final PdfPageNode node;
  final Size pageSize;

  _PdfPageViewPainter({
    required this.node,
    required this.pageSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final dstRect = Rect.fromLTWH(0, 0, size.width, size.height);

    if (node.cachedImage != null) {
      final img = node.cachedImage!;
      final srcRect = Rect.fromLTWH(
        0, 0, img.width.toDouble(), img.height.toDouble(),
      );
      canvas.drawImageRect(img, srcRect, dstRect, Paint()..filterQuality = FilterQuality.high);
    } else if (node.thumbnailImage != null) {
      // Show thumbnail while loading
      final img = node.thumbnailImage!;
      final srcRect = Rect.fromLTWH(
        0, 0, img.width.toDouble(), img.height.toDouble(),
      );
      canvas.drawImageRect(img, srcRect, dstRect, Paint()..filterQuality = FilterQuality.medium);

      // Loading indicator overlay
      final overlayPaint = Paint()..color = const Color(0x08000000);
      canvas.drawRect(dstRect, overlayPaint);
    } else {
      // Placeholder
      canvas.drawRect(dstRect, Paint()..color = const Color(0xFFF8F8F8));

      // Page number
      final pageNum = '${node.pageModel.pageIndex + 1}';
      final tp = TextPainter(
        text: TextSpan(
          text: pageNum,
          style: const TextStyle(
            color: Color(0xFFCCCCCC),
            fontSize: 48,
            fontWeight: FontWeight.w200,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      tp.paint(
        canvas,
        Offset(
          (size.width - tp.width) / 2,
          (size.height - tp.height) / 2,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(_PdfPageViewPainter oldDelegate) {
    return oldDelegate.node.cachedImage != node.cachedImage ||
           oldDelegate.node.thumbnailImage != node.thumbnailImage;
  }
}
