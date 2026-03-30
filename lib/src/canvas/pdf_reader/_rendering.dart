part of 'pdf_reader_screen.dart';

/// PDF page rendering, virtualized layout, and cumulative cache.
extension _PdfRenderingMethods on _PdfReaderScreenState {

  // ---------------------------------------------------------------------------
  // PDF page rendering
  // ---------------------------------------------------------------------------

  Future<void> _renderAllPages() async {
    final provider = widget.provider;
    final totalPages = widget.documentModel.totalPages;

    // Only render first few pages initially to avoid OOM
    final initialPages = totalPages.clamp(0, 5);
    for (int i = 0; i < initialPages; i++) {
      if (!mounted) return;
      await _renderPage(i, provider);
    }
  }

  /// Ensure visible pages (current ± 3) are rendered and dispose far-away pages.
  void _ensureVisiblePagesRendered() {
    final total = widget.documentModel.totalPages;
    final current = _currentPageIndex;
    
    // Skip if we already checked for this page
    if (current == _lastVisibleCheckPage) return;
    _lastVisibleCheckPage = current;
    
    const buffer = 3;

    // Render nearby pages
    for (int i = (current - buffer).clamp(0, total); i < (current + buffer + 1).clamp(0, total); i++) {
      if (_pageImages[i] == null) {
        _renderPage(i, widget.provider);
      }
    }

    // Dispose far-away pages to save memory (keep ±7 pages)
    for (int i = 0; i < total; i++) {
      if ((i - current).abs() > buffer + 4 && _pageImages[i] != null) {
        _pageImages[i]?.dispose();
        _pageImages[i] = null;
        _pageRenderScale.remove(i);
      }
    }
  }

  Future<void> _renderPage(int pageIndex, FlueraPdfProvider provider, {
    double renderScale = 1.0,
  }) async {
    // Check if already rendered at this or higher scale
    final existingScale = _pageRenderScale[pageIndex] ?? 0.0;
    if (existingScale >= renderScale && _pageImages[pageIndex] != null) return;

    final page = widget.documentModel.pages[pageIndex];
    final screenWidth = MediaQuery.of(context).size.width;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    if (screenWidth <= 0) return;

    final targetWidth = (screenWidth * dpr * renderScale).clamp(200.0, 2048.0);
    final scale = (targetWidth / page.originalSize.width).clamp(0.5, 3.0);

    try {
      final image = await provider.renderPage(
        pageIndex: pageIndex,
        scale: scale,
        targetSize: Size(
          targetWidth,
          targetWidth * page.originalSize.height / page.originalSize.width,
        ),
      );

      if (mounted) {
        final oldImage = _pageImages[pageIndex];
        setState(() {
          _pageImages[pageIndex] = image;
          _pageRenderScale[pageIndex] = renderScale;
        });
        // Dispose old lower-res image
        oldImage?.dispose();
      }
    } catch (_) {}
  }

  double _getPageDisplayHeight(int pageIndex) {
    final page = widget.documentModel.pages[pageIndex];
    final screenWidth = MediaQuery.sizeOf(context).width - (_showSidebar ? 120 : 0) - 32;
    return screenWidth * page.originalSize.height / page.originalSize.width;
  }

  // ---------------------------------------------------------------------------
  // Virtualized page rendering — O(visible) instead of O(N)
  // ---------------------------------------------------------------------------

  /// Rebuild cumulative tops cache if needed.
  void _ensureCumulativeCache() {
    final screenWidth = MediaQuery.sizeOf(context).width - (_showSidebar ? 120 : 0) - 32;
    if (_cumulativePageTops != null && _cumulativeCacheWidth == screenWidth) return;

    final totalPages = widget.documentModel.totalPages;
    final tops = List<double>.filled(totalPages, 0.0);
    double acc = 16.0;
    for (int i = 0; i < totalPages; i++) {
      tops[i] = acc;
      acc += _getPageDisplayHeight(i) + 16.0;
    }
    _cumulativePageTops = tops;
    _cachedTotalHeight = acc;
    _cumulativeCacheWidth = screenWidth;
  }

  /// Cumulative Y offset for a page index — O(1) with cache.
  double _getPageTop(int pageIndex) {
    _ensureCumulativeCache();
    return _cumulativePageTops![pageIndex];
  }

  /// Total content height for all pages — O(1) with cache.
  double _getTotalContentHeight() {
    _ensureCumulativeCache();
    return _cachedTotalHeight!;
  }

  /// Build only the pages visible in the current viewport.
  Widget _buildVirtualizedPages(double screenWidth) {
    final totalPages = widget.documentModel.totalPages;
    final totalHeight = _getTotalContentHeight();
    final contentWidth = screenWidth - 32; // padding

    // Compute visible range from InteractiveViewer transform
    final scale = _zoomController.value.getMaxScaleOnAxis();
    final yOffset = -_zoomController.value.row1.w / scale;
    final viewportHeight = MediaQuery.of(context).size.height / scale;
    final viewTop = yOffset;
    final viewBottom = yOffset + viewportHeight;

    // Find first and last visible page indices (with buffer)
    const buffer = 3;
    int firstVisible = 0;
    int lastVisible = totalPages - 1;

    double accumulated = 16.0;
    for (int i = 0; i < totalPages; i++) {
      final pageHeight = _getPageDisplayHeight(i);
      final pageBottom = accumulated + pageHeight;

      if (pageBottom < viewTop) {
        firstVisible = i + 1;
      }
      if (accumulated > viewBottom && lastVisible == totalPages - 1) {
        lastVisible = i;
        break;
      }
      accumulated = pageBottom + 16.0;
    }

    // Clamp with buffer
    firstVisible = (firstVisible - buffer).clamp(0, totalPages - 1);
    lastVisible = (lastVisible + buffer).clamp(0, totalPages - 1);

    // Build only visible pages as Positioned children
    return SizedBox(
      width: screenWidth,
      height: totalHeight,
      child: Stack(
        children: [
          for (int i = firstVisible; i <= lastVisible; i++)
            Positioned(
              left: 16,
              top: _getPageTop(i),
              width: contentWidth,
              height: _getPageDisplayHeight(i),
              child: RepaintBoundary(
                child: (i - _currentPageIndex).abs() <= 5
                    ? _buildPageWidget(i)
                    : _pageImages[i] != null
                        ? CustomPaint(
                            painter: _DirectPagePainter(
                              image: _pageImages[i]!,
                              isZoomed: false,
                            ),
                            size: Size(contentWidth, _getPageDisplayHeight(i)),
                          )
                        : const _PageShimmer(),
              ),
            ),
        ],
      ),
    );
  }
}
