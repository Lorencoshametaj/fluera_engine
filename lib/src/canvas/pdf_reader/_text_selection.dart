part of 'pdf_reader_screen.dart';

/// Text extraction, selection, and copy logic.
extension _PdfTextSelectionMethods on _PdfReaderScreenState {

  // ---------------------------------------------------------------------------
  // Text Selection Logic
  // ---------------------------------------------------------------------------

  /// Clear current text selection.
  void _clearTextSelection() {
    _selSpans = const [];
    _selStartIdx = -1;
    _selEndIdx = -1;
    _selPageIdx = -1;
    _selAnchor = -1;
    _textOverlayRepaint.value++;
  }

  /// Extract text rects for a page (lazy, via native provider).
  /// Phase 1: fast getPageText() on all pages.
  /// Phase 2 (background OCR) is started separately by _startBackgroundOcr.
  Future<List<PdfTextRect>> _ensureTextRects(int pageIndex) async {
    if (_pageTextRects.containsKey(pageIndex)) {
      return _pageTextRects[pageIndex]!;
    }
    if (_isExtractingText) {
      return const [];
    }

    _isExtractingText = true;
    try {
      final provider = widget.provider;
      final totalPages = widget.documentModel.totalPages;

      // Phase 1: fast native text extraction (no OCR)
      final pageTexts = <_PageTextData>[];
      for (int i = 0; i < totalPages; i++) {
        final text = await provider.getPageText(i);

        List<PdfTextRect> rects = const [];
        if (text.trim().isNotEmpty) {
          try {
            rects = await provider.extractTextGeometry(i);
          } catch (_) {}
        }

        _pageTextRects[i] = rects;
        pageTexts.add(_PageTextData(text: text, rects: rects));
      }

      _providerPageTexts = pageTexts;
    } catch (e, st) {
      debugPrint('📝 ERROR in _ensureTextRects: $e\n$st');
      _pageTextRects[pageIndex] = const [];
    } finally {
      _isExtractingText = false;
    }
    return _pageTextRects[pageIndex] ?? const [];
  }

  /// Find the text rect index at a normalized position on the page.
  int _textRectIndexAt(int pageIndex, Offset normalizedPos) {
    final rects = _pageTextRects[pageIndex];
    if (rects == null || rects.isEmpty) return -1;

    // Direct hit test
    for (int i = 0; i < rects.length; i++) {
      if (rects[i].rect.contains(normalizedPos)) return i;
    }

    // Fallback: closest within tolerance
    const tolerance = 0.03; // 3% of page dimension
    double closest = double.infinity;
    int closestIdx = -1;
    for (int i = 0; i < rects.length; i++) {
      final center = rects[i].rect.center;
      final dist = (center - normalizedPos).distance;
      if (dist < closest && dist < tolerance) {
        closest = dist;
        closestIdx = i;
      }
    }
    return closestIdx;
  }

  /// Handle long-press start in text selection mode.
  void _onTextSelectStart(int pageIndex, Offset localPos, Size pageDisplaySize) {
    // Convert to normalized 0-1 coordinates
    final normX = localPos.dx / pageDisplaySize.width;
    final normY = localPos.dy / pageDisplaySize.height;
    final normPos = Offset(normX, normY);

    _ensureTextRects(pageIndex).then((rects) {
      if (!mounted || rects.isEmpty) return;
      final idx = _textRectIndexAt(pageIndex, normPos);
      if (idx < 0) {
        setState(_clearTextSelection);
        return;
      }
      setState(() {
        _selPageIdx = pageIndex;
        _selAnchor = idx;
        _selStartIdx = idx;
        _selEndIdx = idx;
        _selSpans = [rects[idx]];
      });
      _textOverlayRepaint.value++;
      HapticFeedback.selectionClick();
    });
  }

  /// Handle drag update in text selection mode.
  void _onTextSelectUpdate(int pageIndex, Offset localPos, Size pageDisplaySize) {
    if (_selPageIdx != pageIndex || _selAnchor < 0) return;
    final rects = _pageTextRects[pageIndex];
    if (rects == null || rects.isEmpty) return;

    final normX = localPos.dx / pageDisplaySize.width;
    final normY = localPos.dy / pageDisplaySize.height;
    final idx = _textRectIndexAt(pageIndex, Offset(normX, normY));
    if (idx < 0) return;

    final startIdx = idx < _selAnchor ? idx : _selAnchor;
    final endIdx = idx < _selAnchor ? _selAnchor : idx;

    if (startIdx != _selStartIdx || endIdx != _selEndIdx) {
      _selStartIdx = startIdx;
      _selEndIdx = endIdx;
      _selSpans = rects.sublist(startIdx, endIdx + 1);
      _textOverlayRepaint.value++;
    }
  }

  /// Handle release in text selection mode.
  void _onTextSelectEnd() {
    if (_selSpans.isNotEmpty) {
      // Show copy context action
      HapticFeedback.lightImpact();
    }
  }

  /// Copy selected text to clipboard.
  void _copySelectedText() {
    if (_selSpans.isEmpty) return;
    final buf = StringBuffer();
    for (int i = 0; i < _selSpans.length; i++) {
      if (i > 0) {
        final prevBottom = _selSpans[i - 1].rect.bottom;
        final currTop = _selSpans[i].rect.top;
        final lineH = _selSpans[i - 1].rect.height;
        if ((currTop - prevBottom).abs() < lineH * 0.5) {
          // Same line → space
          buf.write(' ');
        } else {
          buf.write('\n');
        }
      }
      buf.write(_selSpans[i].text);
    }
    Clipboard.setData(ClipboardData(text: buf.toString()));
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Copied to clipboard'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        backgroundColor: const Color(0xFF2A2A4A),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  /// Combined selected text string.
  String get _selectedText {
    if (_selSpans.isEmpty) return '';
    final buf = StringBuffer();
    for (int i = 0; i < _selSpans.length; i++) {
      if (i > 0) buf.write(' ');
      buf.write(_selSpans[i].text);
    }
    return buf.toString();
  }

  // ---------------------------------------------------------------------------
  // PDF Text Extraction Sheet
  // ---------------------------------------------------------------------------

  /// Opens the text extraction bottom sheet immediately, resolving text in background.
  void _showPdfTextExtractionSheet() {
    HapticFeedback.mediumImpact();

    final filePath = widget.documentModel.filePath;
    final pageIndex = _currentPageIndex;
    final totalPages = widget.documentModel.totalPages;

    final Future<String> textFuture = () async {
      if (filePath == null || filePath.isEmpty) return '';
      try {
        final bytes = await File(filePath).readAsBytes();
        final pages = await PdfTextExtractor.extractInIsolate(
          bytes,
          pageCount: totalPages,
        );
        if (pageIndex < pages.length) {
          return pages[pageIndex].text.trim();
        }
      } catch (_) {}
      return '';
    }();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PdfTextSheet(
        pageIndex: pageIndex,
        textFuture: textFuture,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Text Selection Context Toolbar
  // ---------------------------------------------------------------------------

  Widget _buildTextSelectionToolbar(Size pageDisplaySize) {
    if (_selSpans.isEmpty || _selPageIdx < 0) return const SizedBox.shrink();

    // Compute the top-center of the selection in page-display coordinates
    double minY = double.infinity;
    double sumX = 0;
    for (final span in _selSpans) {
      final top = span.rect.top * pageDisplaySize.height;
      if (top < minY) minY = top;
      sumX += span.rect.center.dx * pageDisplaySize.width;
    }
    final avgX = sumX / _selSpans.length;

    return Positioned(
      left: (avgX - 50).clamp(4.0, pageDisplaySize.width - 100),
      top: (minY - 44).clamp(0.0, pageDisplaySize.height - 36),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xEE1A1A36),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0x30FFFFFF), width: 0.5),
          boxShadow: const [
            BoxShadow(color: Color(0x60000000), blurRadius: 8),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ctxButton('Copy', Icons.copy_rounded, _copySelectedText),
            _ctxButton('All', Icons.select_all_rounded, () {
              final rects = _pageTextRects[_selPageIdx];
              if (rects == null || rects.isEmpty) return;
              setState(() {
                _selStartIdx = 0;
                _selEndIdx = rects.length - 1;
                _selSpans = rects;
              });
              _textOverlayRepaint.value++;
            }),
          ],
        ),
      ),
    );
  }

  Widget _ctxButton(String label, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: const Color(0xCCFFFFFF)),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(
              color: Color(0xCCFFFFFF), fontSize: 11,
              fontWeight: FontWeight.w600,
            )),
          ],
        ),
      ),
    );
  }
}
