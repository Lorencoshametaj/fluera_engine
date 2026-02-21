part of '../nebula_canvas_screen.dart';

/// 📄 PDF Features — pick and import PDF documents onto the canvas.
extension NebulaCanvasPdfFeatures on _NebulaCanvasScreenState {
  /// 📄 Pick a PDF file and import it onto the canvas.
  ///
  /// Uses [FilePicker] to let the user select a PDF, then feeds the bytes
  /// to [PdfImportController] via a [NativeNebulaPdfProvider].
  Future<void> pickAndAddPdf() async {
    // 🔒 VIEWER GUARD
    if (_checkViewerGuard()) return;

    try {
      // 1. Pick PDF file
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return; // User cancelled

      final fileBytes = result.files.single.bytes;
      if (fileBytes == null || fileBytes.isEmpty) {
        // On some platforms, bytes may be null — read from path
        final filePath = result.files.single.path;
        if (filePath == null) return;
        final file = File(filePath);
        if (!await file.exists()) return;
        final bytes = await file.readAsBytes();
        await _importPdfBytes(bytes);
      } else {
        await _importPdfBytes(fileBytes);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('PDF import error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Internal: import PDF from bytes using native provider.
  Future<void> _importPdfBytes(Uint8List bytes) async {
    final documentId = 'pdf_${DateTime.now().microsecondsSinceEpoch}';

    // 💾 Save PDF bytes to local cache for persistence
    final appDir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${appDir.path}/nebula_pdf_cache');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    final pdfFile = File('${cacheDir.path}/$documentId.pdf');
    await pdfFile.writeAsBytes(bytes);

    // ☁️ Upload PDF to cloud storage for cross-device access
    if (_syncEngine != null) {
      try {
        await _syncEngine!.adapter.uploadAsset(
          _canvasId,
          documentId,
          bytes,
          mimeType: 'application/pdf',
        );
        debugPrint('☁️ PDF uploaded to cloud: $documentId');
      } catch (e) {
        debugPrint('☁️ PDF cloud upload failed (local only): $e');
      }
    }

    // Create a native provider for this document
    final provider = NativeNebulaPdfProvider(documentId: documentId);

    // Import via PdfImportController
    final controller = PdfImportController(provider: provider);

    // Calculate center of viewport for placement
    final screenCenter = Offset(
      MediaQuery.of(context).size.width / 2,
      MediaQuery.of(context).size.height / 2,
    );
    final viewportCenter = _canvasController.screenToCanvas(screenCenter);

    final docNode = await controller.importDocument(
      documentId: documentId,
      bytes: bytes,
      insertPosition: viewportCenter,
      gridColumns: 1, // 📄 Single column: natural reading flow
    );

    if (docNode == null) {
      provider.dispose();
      // Clean up cached file on failure
      if (await pdfFile.exists()) await pdfFile.delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to load PDF document'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // 💾 Store file path in document model for persistence
    docNode.documentModel = docNode.documentModel.copyWith(
      filePath: pdfFile.path,
    );

    // 📄 Store provider and create LOD-aware painter for this document
    _pdfProviders[documentId] = provider;
    _pdfPainters[documentId] = PdfPagePainter(
      provider: provider,
      memoryBudget: PdfMemoryBudget(),
      documentId: documentId,
    );

    // 📄 Initialize annotation controller for toolbar
    _pdfAnnotationController?.dispose();
    _pdfAnnotationController = PdfAnnotationController();
    _pdfAnnotationController!.attach(docNode);

    // 📄 Register document in search controller (multi-doc aware)
    _pdfSearchController ??= PdfSearchController();
    _pdfSearchController!.registerDocument(
      documentId,
      Uint8List.fromList(bytes),
      provider: provider,
    );

    // 🔋 Update shared budget: divide memory across all active documents
    final docCount = _pdfPainters.length;
    for (final p in _pdfPainters.values) {
      p.memoryBudget.activeDocumentCount = docCount;
    }

    // Add to active layer's scene graph
    final activeLayer = _layerController.activeLayer;
    if (activeLayer != null) {
      activeLayer.node.add(docNode);
    }

    // 📄 Auto-select newly imported PDF in toolbar
    _activePdfDocumentId = documentId;

    // Trigger rebuild + auto-save
    if (mounted) setState(() {});
    _autoSaveCanvas();

    HapticFeedback.mediumImpact();

    // 🔥 Background warm-up: pre-render all pages at low LOD
    final painter = _pdfPainters[documentId];
    if (painter != null) {
      painter.warmUpAllPages(
        docNode.pageNodes,
        onNeedRepaint: () {
          if (mounted) setState(() {});
        },
      );
    }

    // 📄 Auto-scroll to center on first page
    final firstPage = docNode.pageNodes.firstOrNull;
    if (firstPage != null) {
      final pagePos = firstPage.position;
      final pageSize = firstPage.pageModel.originalSize;
      final pageCenter = Offset(
        pagePos.dx + pageSize.width / 2,
        pagePos.dy + pageSize.height / 2,
      );
      final screenSize = MediaQuery.of(context).size;
      final scale = _canvasController.scale;
      _canvasController.setOffset(
        Offset(
          screenSize.width / 2 - pageCenter.dx * scale,
          screenSize.height / 2 - pageCenter.dy * scale,
        ),
      );
    }

    debugPrint(
      '[PDF] Imported "$documentId" — ${docNode.documentModel.totalPages} pages',
    );
  }

  /// 📄 Restore PDF documents from saved metadata on canvas load.
  ///
  /// Re-opens each PDF file from disk, creates native providers and painters,
  /// and attaches the document nodes to their respective layers.
  Future<void> _restorePdfDocuments(List<dynamic> pdfDocsList) async {
    for (final entry in pdfDocsList) {
      try {
        final map = Map<String, dynamic>.from(entry as Map);
        final layerId = map['layerId'] as String;
        final docJson = Map<String, dynamic>.from(map['document'] as Map);

        // Reconstruct the PdfDocumentNode from JSON
        final docNode = PdfDocumentNode.fromJson(docJson);
        final filePath = docNode.documentModel.filePath;

        if (filePath == null || filePath.isEmpty) {
          debugPrint('[PDF] Skipping restore — no filePath for ${docNode.id}');
          continue;
        }

        // Check if the PDF file still exists on disk
        final pdfFile = File(filePath);
        if (!await pdfFile.exists()) {
          // ☁️ Try downloading from cloud
          if (_syncEngine != null) {
            try {
              final cloudBytes = await _syncEngine!.adapter.downloadAsset(
                _canvasId,
                docNode.id,
              );
              if (cloudBytes != null) {
                await pdfFile.parent.create(recursive: true);
                await pdfFile.writeAsBytes(cloudBytes);
                debugPrint('☁️ Downloaded PDF from cloud: ${docNode.id}');
              } else {
                debugPrint('[PDF] Skipping restore — not in cloud: $filePath');
                continue;
              }
            } catch (e) {
              debugPrint('[PDF] Cloud download failed: $e');
              continue;
            }
          } else {
            debugPrint('[PDF] Skipping restore — file missing: $filePath');
            continue;
          }
        }

        // Create a new native provider and load the PDF bytes
        final documentId = docNode.id;
        final provider = NativeNebulaPdfProvider(documentId: documentId);
        final bytes = await pdfFile.readAsBytes();
        final loaded = await provider.loadDocument(bytes);

        if (!loaded) {
          debugPrint('[PDF] Failed to reload PDF: $documentId');
          provider.dispose();
          continue;
        }

        // Store provider and create LOD-aware painter
        _pdfProviders[documentId] = provider;
        _pdfPainters[documentId] = PdfPagePainter(
          provider: provider,
          memoryBudget: PdfMemoryBudget(),
          documentId: documentId,
        );

        // Re-layout and attach to the correct layer
        docNode.performGridLayout();

        final targetLayer = _layerController.layers.firstWhere(
          (l) => l.id == layerId,
          orElse: () => _layerController.layers.first,
        );
        targetLayer.node.add(docNode);

        // 📄 Initialize controllers for toolbar (uses last restored doc)
        _pdfAnnotationController?.dispose();
        _pdfAnnotationController = PdfAnnotationController();
        _pdfAnnotationController!.attach(docNode);

        // 📄 Auto-select last restored PDF in toolbar
        _activePdfDocumentId = documentId;

        // 📄 Register document in search controller (multi-doc aware)
        _pdfSearchController ??= PdfSearchController();
        _pdfSearchController!.registerDocument(
          documentId,
          Uint8List.fromList(bytes),
          provider: provider,
        );

        debugPrint(
          '[PDF] Restored "$documentId" — '
          '${docNode.documentModel.totalPages} pages',
        );
      } catch (e) {
        debugPrint('[PDF] Error restoring document: $e');
      }
    }

    // Trigger rebuild after all PDFs are restored
    if (mounted) setState(() {});

    // 🔥 Background warm-up: pre-render restored pages at low LOD
    for (final entry in _pdfPainters.entries) {
      final painter = entry.value;
      // Collect all page nodes for this document
      final allPageNodes = <PdfPageNode>[];
      for (final layer in _layerController.layers) {
        for (final child in layer.node.children) {
          if (child is PdfDocumentNode && child.id == entry.key) {
            allPageNodes.addAll(child.pageNodes);
          }
        }
      }
      if (allPageNodes.isNotEmpty) {
        painter.warmUpAllPages(
          allPageNodes,
          onNeedRepaint: () {
            if (mounted) setState(() {});
          },
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Annotation linking
  // ---------------------------------------------------------------------------

  /// 📄 Link a finished stroke to the PDF page it overlaps (if any).
  ///
  /// Walks all layers looking for [PdfDocumentNode]s, then uses
  /// [PdfDocumentNode.linkAnnotation] to hit-test the stroke bounds
  /// against page rects.
  void _linkStrokeToPdfPage(ProStroke stroke) {
    final strokeBounds = stroke.bounds;
    // Skip strokes with degenerate bounds
    if (strokeBounds.isEmpty) return;

    for (final layer in _layerController.layers) {
      for (final child in layer.node.children) {
        if (child is PdfDocumentNode) {
          final pageIdx = child.linkAnnotation(stroke.id, strokeBounds);
          if (pageIdx >= 0) {
            debugPrint(
              '[PDF] Linked annotation ${stroke.id.substring(0, 8)} → page $pageIdx',
            );
            return; // Link to first matching page only
          }
        }
      }
    }
  }
}
