part of 'pdf_reader_screen.dart';

/// Bookmarks panel bottom sheet UI.
extension _PdfBookmarksPanelMethods on _PdfReaderScreenState {

  void _showBookmarksPanel() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A36),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final sorted = _bookmarkedPages.keys.toList()..sort();
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 40, height: 4, decoration: BoxDecoration(color: const Color(0x40FFFFFF), borderRadius: BorderRadius.circular(2))),
                  const SizedBox(height: 12),
                  Row(children: [
                    const Icon(Icons.bookmark_rounded, color: Color(0xFFEF5350), size: 22),
                    const SizedBox(width: 8),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Bookmarks (${sorted.length})', style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
                      if (sorted.isNotEmpty) Text([
                        '${_bookmarkedPages.values.where((b) => b.note.isNotEmpty).length} with notes',
                        '${sorted.where((p) => (_pageStrokes[p]?.isNotEmpty ?? false)).length} annotated',
                      ].join(' | '), style: const TextStyle(color: Colors.white30, fontSize: 10)),
                    ])),
                    if (sorted.length > 1) ...[
                      IconButton(icon: const Icon(Icons.chevron_left_rounded, color: Colors.white54, size: 24), onPressed: () { Navigator.pop(ctx); _jumpToPrevBookmark(); }, tooltip: 'Previous bookmark'),
                      IconButton(icon: const Icon(Icons.chevron_right_rounded, color: Colors.white54, size: 24), onPressed: () { Navigator.pop(ctx); _jumpToNextBookmark(); }, tooltip: 'Next bookmark'),
                    ],
                  ]),
                  const SizedBox(height: 8),
                  SizedBox(height: 32, child: Row(children: [
                    const Text('Tag color: ', style: TextStyle(color: Colors.white38, fontSize: 11)),
                    const SizedBox(width: 4),
                    for (final c in _PdfReaderScreenState._bookmarkColors) GestureDetector(
                      onTap: () { setState(() => _activeBookmarkColor = c); setSheetState(() {}); },
                      child: Container(width: 22, height: 22, margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: _activeBookmarkColor == c ? Colors.white : Colors.transparent, width: 2))),
                    ),
                  ])),
                  const SizedBox(height: 8),
                  if (sorted.isEmpty)
                    const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Text('No bookmarks yet.\nUse the bookmark sector to add pages.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white38, fontSize: 13, height: 1.5)))
                  else
                    SizedBox(
                      height: math.min(sorted.length * 80.0, 360),
                      child: ListView.builder(
                        itemCount: sorted.length,
                        itemBuilder: (_, idx) => _buildBookmarkRow(ctx, sorted[idx], setSheetState),
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

  Widget _buildBookmarkRow(BuildContext ctx, int pageIdx, StateSetter setSheetState) {
    final bm = _bookmarkedPages[pageIdx]!;
    final page = widget.documentModel.pages[pageIdx];
    final aspect = page.originalSize.height / page.originalSize.width;
    final img = _pageImages[pageIdx];
    return Dismissible(
      key: ValueKey('bm_$pageIdx'),
      direction: DismissDirection.endToStart,
      background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(color: const Color(0xFFB71C1C), borderRadius: BorderRadius.circular(12)),
        child: const Icon(Icons.delete_rounded, color: Colors.white)),
      onDismissed: (_) { setState(() => _bookmarkedPages.remove(pageIdx)); _syncBookmarkToModel(pageIdx, false); setSheetState(() {}); },
      child: Material(color: Colors.transparent, child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () { Navigator.pop(ctx); _scrollToPage(pageIdx); },
        child: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(children: [
          Container(width: 4, height: 40, margin: const EdgeInsets.only(right: 10), decoration: BoxDecoration(color: bm.color, borderRadius: BorderRadius.circular(2))),
          Container(width: 48, height: 48 * aspect, decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(6)),
            child: img != null ? ClipRRect(borderRadius: BorderRadius.circular(6), child: RawImage(image: img, fit: BoxFit.cover))
              : Center(child: Text('${pageIdx + 1}', style: const TextStyle(color: Color(0xFF999999), fontSize: 14)))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Page ${pageIdx + 1}', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
            if (bm.note.isNotEmpty) Text(bm.note, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ])),
          IconButton(
            icon: Icon(bm.note.isEmpty ? Icons.note_add_rounded : Icons.edit_note_rounded, color: const Color(0x66FFFFFF), size: 20),
            onPressed: () async {
              final ctrl = TextEditingController(text: bm.note);
              final result = await showDialog<String>(context: context, builder: (dCtx) => AlertDialog(
                backgroundColor: const Color(0xFF1A1A36),
                title: Text('Note — Page ${pageIdx + 1}', style: const TextStyle(color: Colors.white, fontSize: 16)),
                content: TextField(controller: ctrl, autofocus: true, maxLines: 3, style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(hintText: 'Add a note...', hintStyle: const TextStyle(color: Colors.white24),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0x33FFFFFF))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF6C63FF))))),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('Cancel', style: TextStyle(color: Colors.white38))),
                  TextButton(onPressed: () => Navigator.pop(dCtx, ctrl.text), child: const Text('Save', style: TextStyle(color: Color(0xFF6C63FF)))),
                ],
              ));
              if (result != null) { setState(() => bm.note = result); setSheetState(() {}); }
            },
          ),
        ])),
      )),
    );
  }
}
