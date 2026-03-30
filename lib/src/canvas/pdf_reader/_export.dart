part of 'pdf_reader_screen.dart';

/// Annotated page export logic.
extension _PdfExportMethods on _PdfReaderScreenState {

  void _showExportSheet() {
    showModalBottomSheet(context: context, backgroundColor: const Color(0xFF1A1A36),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: const Color(0x40FFFFFF), borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            const Text('Export Annotated PDF', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Text('Quality: ', style: TextStyle(color: Colors.white54, fontSize: 12)),
              for (final q in [1.0, 2.0, 3.0]) Padding(padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: Text('${q.toInt()}×', style: TextStyle(color: _exportScale == q ? Colors.white : Colors.white54, fontSize: 12, fontWeight: FontWeight.w600)),
                  selected: _exportScale == q, selectedColor: const Color(0xFF42A5F5), backgroundColor: const Color(0x15FFFFFF), side: BorderSide.none,
                  onSelected: (_) { setState(() => _exportScale = q); setSheetState(() {}); })),
            ]),
            const SizedBox(height: 16),
            _exportOption(ctx, icon: Icons.insert_drive_file_rounded, label: 'Current Page', subtitle: 'Page ${_currentPageIndex + 1}', pages: [_currentPageIndex]),
            if (_bookmarkedPages.isNotEmpty) _exportOption(ctx, icon: Icons.bookmark_rounded, label: 'Bookmarked Pages', subtitle: '${_bookmarkedPages.length} pages', pages: _bookmarkedPages.keys.toList()..sort()),
            _exportOption(ctx, icon: Icons.picture_as_pdf_rounded, label: 'All Pages', subtitle: '${widget.documentModel.totalPages} pages', pages: List.generate(widget.documentModel.totalPages, (i) => i)),
            const SizedBox(height: 8),
            if (_bookmarkedPages.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: Material(color: const Color(0x15FFFFFF), borderRadius: BorderRadius.circular(14),
              child: InkWell(borderRadius: BorderRadius.circular(14), onTap: () { Navigator.pop(ctx); _exportBookmarkSummary(); },
                child: Padding(padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16), child: Row(children: [
                  Container(width: 36, height: 36, decoration: BoxDecoration(color: const Color(0x20FFFFFF), borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.summarize_rounded, color: Color(0xFF80CBC4), size: 18)),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Bookmark Summary', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
                    Text('${_bookmarkedPages.length} bookmarks with notes', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                  ])),
                  const Icon(Icons.chevron_right_rounded, color: Colors.white24),
                ]))))),
          ]),
        )),
      ),
    );
  }

  Widget _exportOption(BuildContext ctx, {required IconData icon, required String label, required String subtitle, required List<int> pages}) {
    return Padding(padding: const EdgeInsets.only(bottom: 8), child: Material(color: const Color(0x15FFFFFF), borderRadius: BorderRadius.circular(14),
      child: InkWell(borderRadius: BorderRadius.circular(14), onTap: () { Navigator.pop(ctx); _exportAnnotatedPages(pages); },
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), child: Row(children: [
          Icon(icon, color: const Color(0xFF42A5F5), size: 24), const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
            Text(subtitle, style: const TextStyle(color: Color(0x99FFFFFF), fontSize: 12)),
          ])),
          const Icon(Icons.chevron_right_rounded, color: Color(0x66FFFFFF), size: 20),
        ])))));
  }

  Future<void> _exportAnnotatedPages(List<int> pageIndices) async {
    final progressNotifier = ValueNotifier<double>(0.0);
    final progressText = ValueNotifier<String>('Preparing export...');
    OverlayEntry? overlay;
    overlay = OverlayEntry(builder: (_) => Material(color: const Color(0xCC000000), child: Center(child: Container(
      width: 280, padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(color: const Color(0xFF1A1A36), borderRadius: BorderRadius.circular(20), boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 20)]),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.ios_share_rounded, color: Color(0xFF42A5F5), size: 32), const SizedBox(height: 16),
        const Text('Exporting...', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 16),
        ValueListenableBuilder<double>(valueListenable: progressNotifier, builder: (_, v, __) => ClipRRect(borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: v, backgroundColor: const Color(0x20FFFFFF), valueColor: const AlwaysStoppedAnimation(Color(0xFF42A5F5)), minHeight: 6))),
        const SizedBox(height: 8),
        ValueListenableBuilder<String>(valueListenable: progressText, builder: (_, t, __) => Text(t, style: const TextStyle(color: Colors.white38, fontSize: 12))),
      ])))));
    Overlay.of(context).insert(overlay);

    try {
      final tmpDir = await getTemporaryDirectory();
      final exportDir = Directory('${tmpDir.path}/pdf_export_${DateTime.now().millisecondsSinceEpoch}');
      await exportDir.create(recursive: true);
      final exportedPaths = <String>[];
      final total = pageIndices.length;

      for (int i = 0; i < total; i++) {
        final pageIdx = pageIndices[i];
        if (!mounted) return;
        progressText.value = 'Page ${i + 1} of $total';
        progressNotifier.value = i / total;

        final originalSize = widget.documentModel.pages[pageIdx].originalSize;
        final scale = _exportScale;
        final targetSize = Size(originalSize.width * scale, originalSize.height * scale);
        final pageImage = await widget.provider.renderPage(pageIndex: pageIdx, scale: scale, targetSize: targetSize);
        if (pageImage == null) continue;

        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawImage(pageImage, Offset.zero, Paint());

        final strokes = _pageStrokes[pageIdx] ?? [];
        if (strokes.isNotEmpty) {
          final scaleX = targetSize.width / originalSize.width;
          final scaleY = targetSize.height / originalSize.height;
          canvas.save(); canvas.scale(scaleX, scaleY);
          for (final stroke in strokes) {
            BrushEngine.renderStroke(canvas, stroke.points, stroke.color, stroke.baseWidth, stroke.penType, stroke.settings, engineVersion: stroke.engineVersion);
          }
          canvas.restore();
        }

        final picture = recorder.endRecording();
        final composited = await picture.toImage(targetSize.width.toInt(), targetSize.height.toInt());
        final byteData = await composited.toByteData(format: ui.ImageByteFormat.png);
        if (byteData == null) continue;
        final filePath = '${exportDir.path}/page_${pageIdx + 1}.png';
        await File(filePath).writeAsBytes(byteData.buffer.asUint8List());
        exportedPaths.add(filePath);
        pageImage.dispose(); composited.dispose();
        await Future<void>.delayed(Duration.zero);
      }

      if (!mounted) return;
      overlay.remove(); overlay = null;
      if (exportedPaths.isNotEmpty) {
        await SharePlus.instance.share(ShareParams(files: exportedPaths.map((p) => XFile(p)).toList(), text: 'Annotated PDF export (${exportedPaths.length} pages)'));
      }
    } catch (e) {
      overlay?.remove(); overlay = null;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e'), behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), backgroundColor: const Color(0xFFB71C1C), duration: const Duration(seconds: 3)));
    }
  }
}
