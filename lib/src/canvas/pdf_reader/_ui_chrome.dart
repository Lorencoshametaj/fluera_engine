part of 'pdf_reader_screen.dart';

/// UI chrome widgets: floating title, back button, zoom exit hint, sidebar, page list.
extension _PdfUIChromeMethods on _PdfReaderScreenState {

  Widget _buildFloatingTitle(int totalPages) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Expanded(child: Text(widget.documentModel.fileName ?? 'PDF Document', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 8),
            Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
              child: Text('${_currentPageIndex + 1}/$totalPages', style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600))),
          ]),
        ),
      ),
    );
  }

  Widget _buildBackButton() {
    return GestureDetector(
      onTap: () { widget.onClose?.call(_buildUpdatedModel()); Navigator.of(context).pop(); },
      child: ClipOval(child: BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(width: 40, height: 40,
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.40), shape: BoxShape.circle, border: Border.all(color: Colors.white.withValues(alpha: 0.15))),
          child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 18)))),
    );
  }

  Widget _buildZoomExitHint() {
    final progress = ((0.95 - _currentZoomScale) / 0.30).clamp(0.0, 1.0);
    if (progress <= 0) return const SizedBox.shrink();
    final exitReady = _currentZoomScale < 0.75;
    return Positioned.fill(child: IgnorePointer(child: Stack(children: [
      Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: RadialGradient(
        colors: [const Color(0x00000000), Color.fromARGB((progress * 180).round(), 0, 0, 0)], stops: const [0.2, 1.0], radius: 1.1)))),
      if (progress > 0.15) Center(child: Opacity(opacity: ((progress - 0.15) / 0.5).clamp(0.0, 1.0),
        child: AnimatedContainer(duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(horizontal: exitReady ? 28 : 24, vertical: exitReady ? 14 : 12),
          decoration: BoxDecoration(
            color: exitReady ? const Color(0xCC6C63FF) : const Color(0x88000000), borderRadius: BorderRadius.circular(28),
            border: Border.all(color: exitReady ? const Color(0x60FFFFFF) : const Color(0x30FFFFFF), width: exitReady ? 1.5 : 0.5),
            boxShadow: exitReady ? [BoxShadow(color: const Color(0xFF6C63FF).withValues(alpha: 0.4), blurRadius: 20, spreadRadius: 2)] : null),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(exitReady ? Icons.check_circle_outline_rounded : Icons.zoom_out_map_rounded, color: Colors.white.withValues(alpha: 0.95), size: exitReady ? 20 : 18),
            const SizedBox(width: 10),
            Text(exitReady ? 'Release to go back' : 'Pinch to exit',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.95), fontSize: exitReady ? 15 : 14, fontWeight: exitReady ? FontWeight.w600 : FontWeight.w500, letterSpacing: 0.3)),
          ])))),
    ])));
  }

  Widget _buildThumbnailSidebar() {
    return Container(width: 100, decoration: const BoxDecoration(color: Color(0xFF0F3460), border: Border(right: BorderSide(color: Color(0x22FFFFFF)))),
      child: ListView.builder(padding: const EdgeInsets.symmetric(vertical: 8), itemCount: widget.documentModel.totalPages, itemBuilder: (context, index) {
        final isActive = index == _currentPageIndex;
        final page = widget.documentModel.pages[index];
        final aspect = page.originalSize.height / page.originalSize.width;
        final img = _pageImages[index];
        return GestureDetector(onTap: () => _scrollToPage(index),
          child: AnimatedContainer(duration: const Duration(milliseconds: 200), margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: isActive ? const Color(0xFF6C63FF) : Colors.transparent, width: 2)),
            child: Column(children: [
              Stack(children: [
                Container(width: 80, height: 80 * aspect, decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(6)),
                  child: img != null ? ClipRRect(borderRadius: BorderRadius.circular(6), child: RawImage(image: img, fit: BoxFit.cover))
                    : Center(child: Text('${index + 1}', style: const TextStyle(color: Color(0xFF999999), fontSize: 18, fontWeight: FontWeight.w300)))),
                if (_bookmarkedPages.containsKey(index)) Positioned(top: 4, right: 4, child: Container(width: 10, height: 10,
                  decoration: BoxDecoration(color: _bookmarkedPages[index]?.color ?? const Color(0xFFEF5350), shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: (_bookmarkedPages[index]?.color ?? const Color(0xFFEF5350)).withValues(alpha: 0.4), blurRadius: 4)]))),
              ]),
              Padding(padding: const EdgeInsets.only(top: 4, bottom: 2),
                child: Text('${index + 1}', style: TextStyle(color: isActive ? const Color(0xFF6C63FF) : Colors.white54, fontSize: 10, fontWeight: isActive ? FontWeight.bold : FontWeight.normal))),
            ])));
      }));
  }

  Widget _buildPageList() {
    final screenWidth = MediaQuery.of(context).size.width - (_showSidebar ? 120 : 0);
    return GestureDetector(
      onDoubleTapDown: _isDrawingMode ? null : _onDoubleTapZoom,
      onDoubleTap: () {},
      behavior: HitTestBehavior.translucent,
      onLongPressStart: (d) { if (!_usePdfRadialWheel) return; setState(() { _showPdfRadialMenu = true; _pdfRadialMenuCenter = d.globalPosition; }); HapticFeedback.mediumImpact(); },
      onLongPressMoveUpdate: (d) => _pdfRadialMenuKey.currentState?.updateFinger(d.globalPosition),
      onLongPressEnd: (_) => _pdfRadialMenuKey.currentState?.release(),
      child: InteractiveViewer(
        transformationController: _zoomController, constrained: false, boundaryMargin: const EdgeInsets.all(double.infinity),
        minScale: 0.3, maxScale: 4.0, panEnabled: !_isDrawingMode, scaleEnabled: true,
        onInteractionUpdate: _onInteractionUpdate, onInteractionEnd: _onInteractionEnd,
        child: SizedBox(width: screenWidth, child: _buildVirtualizedPages(screenWidth)),
      ),
    );
  }

  Widget _buildPageWidget(int pageIndex) {
    final page = widget.documentModel.pages[pageIndex];
    final screenWidth = MediaQuery.sizeOf(context).width - (_showSidebar ? 120 : 0) - 32;
    final aspect = page.originalSize.height / page.originalSize.width;
    final displayHeight = screenWidth * aspect;
    final img = _pageImages[pageIndex];
    final pageDisplaySize = Size(screenWidth, displayHeight);
    final strokes = _pageStrokes[pageIndex] ?? const [];
    final isLivePage = _livePageIndex == pageIndex;
    final isZoomed = _isInteracting || _currentZoomScale > 1.1;

    Widget pageContent = Container(width: screenWidth, height: displayHeight,
      decoration: BoxDecoration(
        color: _readingMode == _ReadingMode.dark ? const Color(0xFF2A2A2A) : _readingMode == _ReadingMode.sepia ? const Color(0xFFF5E6D3) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [BoxShadow(color: Color(_readingMode != _ReadingMode.light ? 0x60000000 : 0x30000000), blurRadius: 12, offset: const Offset(0, 4))]),
      child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Stack(children: [
        if (img != null && (strokes.isNotEmpty || (isLivePage && _livePoints != null) || (isLivePage && _shapeStartPos != null)))
          RepaintBoundary(child: CustomPaint(
            painter: _AnnotationOverlayPainter(
              strokes: strokes, livePoints: (isLivePage && !_vulkanActive) ? _livePoints : null,
              liveColor: _penColor.withValues(alpha: _penOpacity), liveWidth: _penWidth * (page.originalSize.width / pageDisplaySize.width),
              livePenType: _penType, pageOriginalSize: page.originalSize, displaySize: pageDisplaySize,
              visibleRect: _computeVisibleRect(pageIndex, pageDisplaySize, page.originalSize),
              repaintNotifier: isLivePage ? _annotationRepaint : null,
              shapeStart: (isLivePage && _shapePageIndex == pageIndex) ? _shapeStartPos : null,
              shapeEnd: (isLivePage && _shapePageIndex == pageIndex) ? _shapeEndPos : null,
              shapeType: _selectedShapeType, liveBrushSettings: _brushSettings, pageImage: img, isZoomed: isZoomed),
            size: pageDisplaySize))
        else if (img != null) CustomPaint(painter: _DirectPagePainter(image: img, isZoomed: isZoomed), size: pageDisplaySize)
        else SizedBox(width: screenWidth, height: displayHeight, child: const _PageShimmer()),

        // Bookmark ribbon
        Positioned(top: 0, right: 16, child: GestureDetector(
          onTap: () { if (_bookmarkedPages.containsKey(pageIndex)) _removeBookmarkWithUndo(pageIndex); },
          onDoubleTap: () { if (_bookmarkedPages.containsKey(pageIndex)) _editBookmarkNote(pageIndex); },
          onLongPress: () { HapticFeedback.mediumImpact(); _showBookmarksPanel(); },
          child: AnimatedSlide(duration: const Duration(milliseconds: 300), curve: Curves.easeOutBack,
            offset: _bookmarkedPages.containsKey(pageIndex) ? Offset.zero : const Offset(0, -1.5),
            child: AnimatedOpacity(duration: const Duration(milliseconds: 200), opacity: _bookmarkedPages.containsKey(pageIndex) ? 1.0 : 0.0,
              child: CustomPaint(size: const Size(24, 36), painter: _BookmarkRibbonPainter(color: _bookmarkedPages[pageIndex]?.color ?? const Color(0xFFEF5350))))))),

        if (_isDrawingMode) Listener(behavior: HitTestBehavior.opaque,
          onPointerDown: (e) => _onPointerDown(e, pageIndex, pageDisplaySize),
          onPointerMove: (e) => _onPointerMove(e, pageIndex, pageDisplaySize),
          onPointerUp: (e) => _onPointerUp(e, pageIndex, pageDisplaySize),
          child: SizedBox(width: screenWidth, height: displayHeight)),

        if (_isTextSelectMode || _searchMatches.isNotEmpty) Positioned.fill(child: ValueListenableBuilder<int>(
          valueListenable: _textOverlayRepaint,
          builder: (_, __, ___) => CustomPaint(painter: _TextHighlightPainter(
            selectionSpans: (pageIndex == _selPageIdx) ? _selSpans : const [],
            searchHighlights: _searchHighlightsForPage(pageIndex),
            currentSearchHighlight: _currentSearchHighlightForPage(pageIndex)), size: pageDisplaySize))),

        if (_isTextSelectMode && !_isDrawingMode) GestureDetector(behavior: HitTestBehavior.opaque,
          onLongPressStart: (d) => _onTextSelectStart(pageIndex, d.localPosition, pageDisplaySize),
          onLongPressMoveUpdate: (d) => _onTextSelectUpdate(pageIndex, d.localPosition, pageDisplaySize),
          onLongPressEnd: (_) => _onTextSelectEnd(),
          onTap: () => setState(_clearTextSelection),
          child: SizedBox(width: screenWidth, height: displayHeight)),

        if (pageIndex == _selPageIdx && _selSpans.isNotEmpty) _buildTextSelectionToolbar(pageDisplaySize),
      ])));

    if (_readingMode == _ReadingMode.dark) {
      pageContent = ColorFiltered(colorFilter: const ColorFilter.matrix(<double>[-0.9, 0, 0, 0, 230, 0, -0.9, 0, 0, 220, 0, 0, -0.9, 0, 210, 0, 0, 0, 1, 0]), child: pageContent);
    } else if (_readingMode == _ReadingMode.sepia) {
      pageContent = ColorFiltered(colorFilter: const ColorFilter.matrix(<double>[0.95, 0.05, 0.02, 0, 10, 0.02, 0.90, 0.05, 0, 5, 0.02, 0.05, 0.80, 0, 0, 0, 0, 0, 1, 0]), child: pageContent);
    }
    return pageContent;
  }
}
