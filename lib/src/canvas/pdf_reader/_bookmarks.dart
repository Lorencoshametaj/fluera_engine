part of 'pdf_reader_screen.dart';

/// Bookmark CRUD, panel, and export summary.
extension _PdfBookmarkMethods on _PdfReaderScreenState {

  void _toggleBookmark() {
    final page = _currentPageIndex;
    if (_bookmarkedPages.containsKey(page)) {
      _removeBookmarkWithUndo(page);
    } else {
      setState(() {
        _bookmarkedPages[page] = _BookmarkData(color: _activeBookmarkColor);
      });
      _syncBookmarkToModel(page, true);
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Page ${page + 1} bookmarked'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          backgroundColor: const Color(0xFF2A2A4A),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  void _removeBookmarkWithUndo(int pageIndex) {
    final savedData = _bookmarkedPages[pageIndex];
    setState(() => _bookmarkedPages.remove(pageIndex));
    _syncBookmarkToModel(pageIndex, false);
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Page ${pageIndex + 1} bookmark removed'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        backgroundColor: const Color(0xFF2A2A4A),
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: 'Undo',
          textColor: const Color(0xFF42A5F5),
          onPressed: () {
            if (savedData != null) {
              setState(() => _bookmarkedPages[pageIndex] = savedData);
              _syncBookmarkToModel(pageIndex, true);
            }
          },
        ),
      ),
    );
  }

  void _jumpToPrevBookmark() {
    if (_bookmarkedPages.isEmpty) return;
    final sorted = _bookmarkedPages.keys.toList()..sort();
    final before = sorted.where((p) => p < _currentPageIndex).toList();
    if (before.isNotEmpty) {
      _scrollToPage(before.last);
    } else {
      _scrollToPage(sorted.last);
    }
    HapticFeedback.selectionClick();
  }

  void _jumpToNextBookmark() {
    if (_bookmarkedPages.isEmpty) return;
    final sorted = _bookmarkedPages.keys.toList()..sort();
    final after = sorted.where((p) => p > _currentPageIndex).toList();
    if (after.isNotEmpty) {
      _scrollToPage(after.first);
    } else {
      _scrollToPage(sorted.first);
    }
    HapticFeedback.selectionClick();
  }

  void _editBookmarkNote(int pageIndex) {
    final bm = _bookmarkedPages[pageIndex];
    if (bm == null) return;
    final ctrl = TextEditingController(text: bm.note);
    showDialog<String>(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A36),
        title: Text('Note - Page ${pageIndex + 1}',
            style: const TextStyle(color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: ctrl, autofocus: true, maxLines: 3,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Add a note...', hintStyle: const TextStyle(color: Colors.white24),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0x33FFFFFF))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF6C63FF))),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('Cancel', style: TextStyle(color: Colors.white38))),
          TextButton(onPressed: () => Navigator.pop(dCtx, ctrl.text), child: const Text('Save', style: TextStyle(color: Color(0xFF6C63FF)))),
        ],
      ),
    ).then((result) { if (result != null) setState(() => bm.note = result); });
  }

  Future<void> _exportBookmarkSummary() async {
    final sorted = _bookmarkedPages.keys.toList()..sort();
    if (sorted.isEmpty) return;
    final buffer = StringBuffer();
    buffer.writeln('Bookmark Summary');
    buffer.writeln('========================================');
    buffer.writeln('Total bookmarks: ${sorted.length}\n');
    for (final pageIdx in sorted) {
      final bm = _bookmarkedPages[pageIdx]!;
      buffer.writeln('Page ${pageIdx + 1}');
      if (bm.note.isNotEmpty) buffer.writeln('   Note: ${bm.note}');
      buffer.writeln('   Annotations: ${(_pageStrokes[pageIdx]?.isNotEmpty ?? false) ? 'Yes' : 'None'}\n');
    }
    final tmpDir = await getTemporaryDirectory();
    final file = File('${tmpDir.path}/bookmark_summary.txt');
    await file.writeAsString(buffer.toString());
    if (!mounted) return;
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], text: 'Bookmark summary (${sorted.length} pages)'));
  }

  void _syncBookmarkToModel(int pageIndex, bool isBookmarked) {
    final pages = widget.documentModel.pages;
    if (pageIndex < pages.length) {
      pages[pageIndex] = pages[pageIndex].copyWith(isBookmarked: isBookmarked);
    }
  }

  void _loadBookmarksFromModel() {
    for (int i = 0; i < widget.documentModel.pages.length; i++) {
      if (widget.documentModel.pages[i].isBookmarked) {
        _bookmarkedPages[i] = _BookmarkData();
      }
    }
  }
}
