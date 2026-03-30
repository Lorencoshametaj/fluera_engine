part of 'pdf_reader_screen.dart';

/// Radial menu result dispatch handler.
extension _PdfRadialMenuHandler on _PdfReaderScreenState {

  void _handlePdfRadialResult(PdfRadialResult result) {
    // ── Quick-repeat flick → instant undo ──
    if (result.quickRepeat) { _undoLastStroke(); HapticFeedback.mediumImpact(); return; }

    // ── Color selected from sub-ring ──
    if (result.selectedColor != null) { setState(() => _penColor = result.selectedColor!); HapticFeedback.selectionClick(); return; }

    // ── Reading mode actions ──
    if (result.readingAction != null) {
      switch (result.readingAction!) {
        case PdfReadingAction.pen:
          setState(() {
            _isDrawingMode = true; _isErasing = false; _penType = ProPenType.ballpoint; _selectedShapeType = ShapeType.freehand;
            if (_penType == ProPenType.highlighter && _savedPenColor != null) {
              _penColor = _savedPenColor!; _penWidth = _savedPenWidth ?? 2.0; _savedPenColor = null; _savedPenWidth = null;
            }
          });
          _initVulkanIfNeeded(); HapticFeedback.selectionClick();
          break;
        case PdfReadingAction.highlight:
          setState(() {
            _isDrawingMode = true; _isErasing = false; _penType = ProPenType.highlighter; _selectedShapeType = ShapeType.freehand;
            if (_savedPenColor == null) { _savedPenColor = _penColor; _savedPenWidth = _penWidth; _penColor = _PdfReaderScreenState._highlightColors[0]; _penWidth = 6.0; }
          });
          _initVulkanIfNeeded(); HapticFeedback.selectionClick();
          break;
        case PdfReadingAction.eraser:
          setState(() { _isDrawingMode = true; _isErasing = true; }); HapticFeedback.selectionClick();
          break;
        case PdfReadingAction.undo:
          _undoLastStroke();
          break;
        case PdfReadingAction.reading:
          setState(() { _readingMode = _ReadingMode.values[(_readingMode.index + 1) % _ReadingMode.values.length]; }); HapticFeedback.selectionClick();
          break;
        case PdfReadingAction.textSelect:
          setState(() {
            _isTextSelectMode = !_isTextSelectMode;
            if (_isTextSelectMode) { _isDrawingMode = false; _isErasing = false; _showSearchBar = false; } else { _clearTextSelection(); }
          }); HapticFeedback.selectionClick();
          break;
        case PdfReadingAction.search:
          setState(() {
            _showSearchBar = !_showSearchBar;
            if (_showSearchBar) { _isDrawingMode = false; _isErasing = false; _isTextSelectMode = false; _clearTextSelection(); _ensureSearchDocRegistered(); }
            else { _searchController.clearSearch(); _searchTextCtrl.clear(); _textOverlayRepaint.value++; }
          }); HapticFeedback.selectionClick();
          break;
        case PdfReadingAction.sidebar:
          setState(() => _showSidebar = !_showSidebar); HapticFeedback.selectionClick();
          break;
        case PdfReadingAction.bookmark:
          _toggleBookmark();
          break;
        case PdfReadingAction.exportAnnotated:
          _showExportSheet();
          break;
      }
      return;
    }

    // ── Drawing mode actions ──
    if (result.drawingAction != null) {
      switch (result.drawingAction!) {
        case PdfDrawingAction.ballpoint:
        case PdfDrawingAction.pencil:
        case PdfDrawingAction.fountain:
          final penType = result.drawingAction!.penType!;
          setState(() {
            _isErasing = false; _penType = penType; _selectedShapeType = ShapeType.freehand;
            if (_savedPenColor != null) { _penColor = _savedPenColor!; _penWidth = _savedPenWidth ?? 2.0; _savedPenColor = null; _savedPenWidth = null; }
          }); HapticFeedback.selectionClick();
          break;
        case PdfDrawingAction.highlighter:
          setState(() {
            _isErasing = false; _penType = ProPenType.highlighter; _selectedShapeType = ShapeType.freehand;
            if (_savedPenColor == null) { _savedPenColor = _penColor; _savedPenWidth = _penWidth; _penColor = _PdfReaderScreenState._highlightColors[0]; _penWidth = 6.0; }
          }); HapticFeedback.selectionClick();
          break;
        case PdfDrawingAction.eraser:
          setState(() => _isErasing = true); HapticFeedback.selectionClick();
          break;
        case PdfDrawingAction.undo:
          _undoLastStroke();
          break;
        case PdfDrawingAction.exitDraw:
          setState(() {
            _isDrawingMode = false; _isErasing = false;
            if (_savedPenColor != null) { _penColor = _savedPenColor!; _penWidth = _savedPenWidth ?? 2.0; _savedPenColor = null; _savedPenWidth = null; }
          }); HapticFeedback.mediumImpact();
          break;
      }
    }
  }
}
