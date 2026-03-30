part of '../fluera_canvas_screen.dart';

/// 📄 PDF Features — pick and import PDF documents onto the canvas.
extension FlueraCanvasPdfFeatures on _FlueraCanvasScreenState {
  /// 📄 Pick a PDF file and import it onto the canvas.
  ///
  /// Uses [FilePicker] to let the user select a PDF, then feeds the bytes
  /// to [PdfImportController] via a [NativeFlueraPdfProvider].
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

      final pickedFile = result.files.single;
      final rawName = pickedFile.name;
      // Strip .pdf extension for cleaner display
      final displayName =
          rawName.endsWith('.pdf')
              ? rawName.substring(0, rawName.length - 4)
              : rawName;

      final fileBytes = pickedFile.bytes;
      if (fileBytes == null || fileBytes.isEmpty) {
        // On some platforms, bytes may be null — read from path
        if (kIsWeb) return; // Web: bytes should always be present with withData
        final filePath = pickedFile.path;
        if (filePath == null) return;
        final file = File(filePath);
        if (!await file.exists()) return;
        final bytes = await file.readAsBytes();
        await _importPdfBytes(bytes, fileName: displayName);
      } else {
        await _importPdfBytes(fileBytes, fileName: displayName);
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

  /// 📄 Create a blank PDF document with empty white pages.
  ///
  /// Creates a [PdfDocumentNode] with [pageCount] blank pages of the given
  /// [pageSize] (defaults to A4: 595×842 pts) and inserts it at the center
  /// of the current viewport.
  ///
  /// Blank pages have no backing [FlueraPdfProvider] — the painter renders
  /// them as white rectangles. Users can draw strokes on them which will
  /// be linked as annotations, just like imported PDFs.
  void createBlankPdfDocument({
    int pageCount = 1,
    Size pageSize = const Size(595, 842), // A4
    PdfPageBackground background = PdfPageBackground.blank,
    bool broadcast = true,
    Offset? position, // If null, uses viewport center
    String?
    documentId, // If null, generates a new ID (remote sync passes sender's ID)
  }) {
    // 🔒 VIEWER GUARD
    if (_checkViewerGuard()) return;

    final docId =
        documentId ?? 'pdf_blank_${DateTime.now().microsecondsSinceEpoch}';
    final now = DateTime.now().millisecondsSinceEpoch;

    // Create page models and nodes
    final pageModels = <PdfPageModel>[];
    final pageNodes = <PdfPageNode>[];

    for (int i = 0; i < pageCount; i++) {
      final pageModel = PdfPageModel(
        pageIndex: i,
        originalSize: pageSize,
        lastModifiedAt: now,
        isBlank: true,
        background: background,
      );
      pageModels.add(pageModel);

      final pageNode = PdfPageNode(
        id: NodeId('${docId}_page_$i'),
        pageModel: pageModel,
        name: 'Page ${i + 1}',
      );
      pageNodes.add(pageNode);
    }

    // Use provided position (remote sync) or calculate from viewport center
    final gridOrigin =
        position ??
        _canvasController.screenToCanvas(
          Offset(
            MediaQuery.of(context).size.width / 2,
            MediaQuery.of(context).size.height / 2,
          ),
        );

    // Create document model
    final documentModel = PdfDocumentModel(
      sourceHash: 'blank',
      totalPages: pageCount,
      pages: pageModels,
      gridColumns: 1,
      gridSpacing: 20.0,
      gridOrigin: gridOrigin,
      createdAt: now,
      lastModifiedAt: now,
      fileName: 'Blank Document',
    );

    // Create document node
    final docNode = PdfDocumentNode(
      id: NodeId(docId),
      documentModel: documentModel,
      name: 'Blank Document',
    );

    // 📡 Wire real-time broadcast callback
    if (_realtimeEngine != null) {
      docNode.onMutation = (subAction, data) {
        _realtimeEngine!.broadcastPdfUpdated(
          documentId: docId,
          subAction: subAction,
          data: data,
        );
      };
    }

    // Add page nodes as children
    for (final page in pageNodes) {
      docNode.add(page);
    }

    // Perform initial grid layout
    docNode.performGridLayout();

    // 📄 Initialize annotation controller for toolbar
    _pdfAnnotationController?.dispose();
    _pdfAnnotationController = PdfAnnotationController();
    _pdfAnnotationController!.attach(docNode);

    // Add to active layer's scene graph
    final activeLayer = _layerController.activeLayer;
    if (activeLayer != null) {
      activeLayer.node.add(docNode);

      // 📄 Retroactively link strokes that arrived before this PDF (race condition)
      if (!broadcast) _retroactiveLinkStrokesToPdf(docNode);
    }

    // 📄 Create painter for background pattern rendering
    _pdfPainters[docId] = PdfPagePainter(
      provider: null,
      memoryBudget: PdfMemoryBudget(),
      documentId: docId,
    );

    // 📄 Auto-select newly created PDF in toolbar
    _activePdfDocumentId = docId;

    // Trigger rebuild + auto-save
    if (mounted) setState(() {});
    _autoSaveCanvas();

    // 📄 Auto-scroll and haptic (LOCAL creation only — never on remote sync)
    if (broadcast) {
      HapticFeedback.mediumImpact();
      final firstPage = docNode.pageNodes.firstOrNull;
      if (firstPage != null) {
        final pagePos = firstPage.position;
        final pSize = firstPage.pageModel.originalSize;
        final pageCenter = Offset(
          pagePos.dx + pSize.width / 2,
          pagePos.dy + pSize.height / 2,
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
    }

    // 📡 Broadcast to collaborators
    if (broadcast && _realtimeEngine != null) {
      _realtimeEngine!.broadcastPdfBlankCreated(
        documentId: docId,
        fileName: 'Blank Document',
        pageCount: pageCount,
        pageWidth: pageSize.width,
        pageHeight: pageSize.height,
        background: background.name,
        positionX: gridOrigin.dx,
        positionY: gridOrigin.dy,
      );
    }
  }

  /// Internal: import PDF from bytes using native provider.
  ///
  /// Set [broadcast] to false when importing from a remote collaboration event
  /// to avoid re-broadcasting.
  Future<void> _importPdfBytes(
    Uint8List bytes, {
    String? fileName,
    bool broadcast = true,
    String? documentId, // Remote sync passes sender's ID
    Offset? position, // Remote sync passes sender's position
  }) async {
    final docId = documentId ?? 'pdf_${DateTime.now().microsecondsSinceEpoch}';

    // 💾 Save PDF bytes to local cache for persistence
    final appDir = await getSafeDocumentsDirectory();
    if (appDir == null) return; // Web: no filesystem
    final cacheDir = Directory('${appDir.path}/fluera_pdf_cache');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    final pdfFile = File('${cacheDir.path}/$docId.pdf');
    await pdfFile.writeAsBytes(bytes);

    // Create a native provider for this document
    final provider = NativeFlueraPdfProvider(documentId: docId);
    final loaded = await provider.loadDocument(bytes);

    if (!loaded) {
      provider.dispose();
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

    final pageCount = provider.pageCount;
    if (pageCount == 0) {
      provider.dispose();
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;

    // Build page models (for the reader, not displayed on canvas)
    final pageModels = <PdfPageModel>[];
    for (int i = 0; i < pageCount; i++) {
      final size = provider.pageSize(i);
      pageModels.add(PdfPageModel(
        pageIndex: i,
        originalSize: size,
        lastModifiedAt: now,
      ));
    }

    // Compute source hash (simple non-crypto hash for dedup)
    int _h = bytes.length;
    final _ss = bytes.length < 512 ? bytes.length : 256;
    for (int i = 0; i < _ss; i++) {
      _h = (_h * 31 + bytes[i]) & 0x7FFFFFFF;
    }
    if (bytes.length > 512) {
      for (int i = bytes.length - 256; i < bytes.length; i++) {
        _h = (_h * 31 + bytes[i]) & 0x7FFFFFFF;
      }
    }
    final sourceHash = _h.toRadixString(16).padLeft(8, '0');

    // Use sender's position (remote sync) or calculate from viewport center
    final insertPosition =
        position ??
        _canvasController.screenToCanvas(
          Offset(
            MediaQuery.of(context).size.width / 2,
            MediaQuery.of(context).size.height / 2,
          ),
        );

    // Create document model (full data for the reader)
    final documentModel = PdfDocumentModel(
      sourceHash: sourceHash,
      totalPages: pageCount,
      pages: pageModels,
      gridColumns: 1,
      gridSpacing: 20.0,
      gridOrigin: insertPosition,
      createdAt: now,
      lastModifiedAt: now,
      filePath: pdfFile.path,
      fileName: fileName,
    );

    // 📄 Create preview card node (single compact element on canvas)
    final cardNode = PdfPreviewCardNode(
      id: NodeId(docId),
      documentModel: documentModel,
      documentId: docId,
      name: fileName ?? 'PDF ($pageCount pages)',
    );
    cardNode.fitToPageAspectRatio(targetWidth: 200);
    cardNode.setPosition(insertPosition.dx, insertPosition.dy);

    // 📄 Store provider and create LOD-aware painter
    _pdfProviders[docId] = provider;
    _pdfPainters[docId] = PdfPagePainter(
      provider: provider,
      memoryBudget: PdfMemoryBudget(),
      documentId: docId,
    );

    // 📄 Render page 1 thumbnail for the preview card
    try {
      final firstPageSize = pageModels.first.originalSize;
      final thumbScale = 200.0 / firstPageSize.width;
      final thumbImage = await provider.renderPage(
        pageIndex: 0,
        scale: thumbScale,
        targetSize: Size(200, 200 * firstPageSize.height / firstPageSize.width),
      );
      if (thumbImage != null) {
        cardNode.thumbnailImage = thumbImage;
      }
    } catch (_) {}

    // 📡 Wire real-time broadcast callback
    // ... (to be added when reader mode handles mutations)

    // 📄 Register document in search controller (multi-doc aware)
    _pdfSearchController ??= PdfSearchController();
    _pdfSearchController!.registerDocument(
      docId,
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
      activeLayer.node.add(cardNode);
      // 📌 Register in scene graph so the spatial index finds it
      _layerController.sceneGraph.registerSubtreeForRollback(cardNode);
      _layerController.sceneGraph.bumpVersion();
    }

    // 📄 Auto-select newly imported PDF
    _activePdfDocumentId = docId;

    // Trigger repaint + auto-save
    DrawingPainter.invalidateAllTiles();
    if (mounted) setState(() {});
    _autoSaveCanvas();

    if (broadcast) HapticFeedback.mediumImpact();

    // 📄 Auto-scroll to center on the preview card
    if (broadcast) {
      final cardPos = cardNode.position;
      final cardCenter = Offset(
        cardPos.dx + cardNode.cardWidth / 2,
        cardPos.dy + cardNode.cardHeight / 2,
      );
      final screenSize = MediaQuery.of(context).size;
      final scale = _canvasController.scale;
      _canvasController.setOffset(
        Offset(
          screenSize.width / 2 - cardCenter.dx * scale,
          screenSize.height / 2 - cardCenter.dy * scale,
        ),
      );
    }

    // ☁️ Always upload PDF to Supabase Storage when cloud sync is available
    if (_syncEngine != null) {
      final firstPageSize = pageModels.first.originalSize;

      final uploadFuture = Future(() async {
        bool uploaded = false;

        // 🔄 Retry with exponential backoff (3 attempts)
        for (int attempt = 1; attempt <= 3; attempt++) {
          try {
            // ⚡ Parallel: upload PDF + thumbnail concurrently
            final pdfFuture = _syncEngine!.adapter.uploadAsset(
              _canvasId,
              docId,
              bytes,
              mimeType: 'application/pdf',
              onProgress: (p) {
                _realtimeEngine?.broadcastPdfProgress(
                  documentId: docId,
                  progress: p * 0.6,
                );
              },
            );

            final thumbFuture = _renderPdfThumbnailBytes(
              provider, firstPageSize,
            ).then((thumbBytes) {
              if (thumbBytes == null) return '';
              return _syncEngine!.adapter.uploadAsset(
                _canvasId,
                '${docId}_thumb',
                thumbBytes,
                mimeType: 'image/png',
              );
            }).catchError((_) => ''); // Thumbnail is non-critical

            await Future.wait([pdfFuture, thumbFuture]);
            uploaded = true;
            break;
          } catch (e) {
            if (attempt < 3) {
              await Future.delayed(Duration(seconds: attempt));
            }
          }
        }

        // 📶 Queue for offline retry if all attempts failed
        if (!uploaded) {
          _offlinePdfUploadQueue[docId] = _OfflinePdfUploadEntry(
            docId: docId,
            bytes: bytes,
            provider: provider,
            pageSize: firstPageSize,
          );
        } else {
          // Drain any previously queued offline uploads
          _drainOfflinePdfQueue();
        }

        // 📊 Sync PDF metadata to dedicated table
        if (uploaded && _syncEngine != null) {
          try {
            _syncEngine!.adapter.syncPdfElements(_canvasId, [
              {
                'id': docId,
                'storageUrl': '', // Storage URL from upload
                'pageCount': pageModels.length,
                'position': {'dx': position?.dx ?? 0, 'dy': position?.dy ?? 0},
                'scale': 1.0,
                'pageIndex': 0,
                'fileName': docId,
                'fileSizeBytes': bytes.length,
              },
            ]);
          } catch (_) {} // Non-critical
        }

        _activePdfUploads.remove(docId);
      });

      _activePdfUploads[docId] = uploadFuture;
    }

    // 📡 Broadcast to collaborators (realtime only)
    if (broadcast && _realtimeEngine != null) {
      final firstPageSize =
          pageModels.firstOrNull?.originalSize ?? const Size(595, 842);

      // 📸 Capture first-page thumbnail (~50px wide, ~2KB PNG)
      String? thumbnailBase64;
      try {
        final thumbScale = 50.0 / firstPageSize.width;
        final thumbImage = await provider.renderPage(
          pageIndex: 0,
          scale: thumbScale,
          targetSize: Size(50, 50 * firstPageSize.height / firstPageSize.width),
        );
        if (thumbImage != null) {
          final byteData = await thumbImage.toByteData(
            format: ui.ImageByteFormat.png,
          );
          if (byteData != null) {
            thumbnailBase64 = base64Encode(byteData.buffer.asUint8List());
          }
          thumbImage.dispose();
        }
      } catch (e) {}

      // 🛡️ RTDB payload guard: drop thumbnail if too large (>50KB base64)
      if (thumbnailBase64 != null && thumbnailBase64.length > 50000) {
        thumbnailBase64 = null;
      }

      // Phase 1: Immediate placeholder notification
      _realtimeEngine!.broadcastPdfLoading(
        documentId: docId,
        pageCount: documentModel.totalPages,
        pageWidth: firstPageSize.width,
        pageHeight: firstPageSize.height,
        positionX: insertPosition.dx,
        positionY: insertPosition.dy,
        fileName: fileName,
        thumbnailBase64: thumbnailBase64,
      );

      // Phase 2: gzip broadcast for inline transfer (fire-and-forget)
      Future(() async {
        try {
          String? b64;
          if (bytes.length <= 10 * 1024 * 1024) {
            _realtimeEngine?.broadcastPdfProgress(
              documentId: docId,
              progress: 0.8,
            );
            final compressed = GZipCodec().encode(bytes);
            _realtimeEngine?.broadcastPdfProgress(
              documentId: docId,
              progress: 0.9,
            );
            b64 = base64Encode(compressed);
          }

          _realtimeEngine?.broadcastPdfAdded(
            documentId: docId,
            fileName: fileName,
            pageCount: documentModel.totalPages,
            positionX: insertPosition.dx,
            positionY: insertPosition.dy,
            pdfBytesBase64: b64,
          );
        } catch (e) {
          _realtimeEngine?.broadcastPdfLoadingFailed(documentId: docId);
        }
      });
    }
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

        // 📄 Blank PDF documents — no file needed, just restore the nodes
        if (filePath == null || filePath.isEmpty) {
          if (docNode.documentModel.sourceHash == 'blank') {
            docNode.performGridLayout();
            if (docNode.name.isEmpty &&
                docNode.documentModel.fileName != null) {
              docNode.name = docNode.documentModel.fileName!;
            }
            // Attach to correct layer
            final targetLayer = _layerController.layers.firstWhere(
              (l) => l.id == layerId,
              orElse: () => _layerController.layers.first,
            );
            targetLayer.node.add(docNode);

            // Create a provider-less painter for blank pages
            final documentId = docNode.id;
            _pdfPainters[documentId] = PdfPagePainter(
              provider: null,
              memoryBudget: PdfMemoryBudget(),
              documentId: documentId,
            );

            // 📡 Wire real-time broadcast callback
            if (_realtimeEngine != null) {
              docNode.onMutation = (subAction, data) {
                _realtimeEngine!.broadcastPdfUpdated(
                  documentId: documentId,
                  subAction: subAction,
                  data: data,
                );
              };
            }

            _pdfAnnotationController?.dispose();
            _pdfAnnotationController = PdfAnnotationController();
            _pdfAnnotationController!.attach(docNode);
            _activePdfDocumentId = documentId;

            continue;
          }
          continue;
        }

        // Check if the PDF file still exists on disk
        if (kIsWeb) continue; // No local file on web
        final pdfFile = File(filePath);
        if (!await pdfFile.exists() || await pdfFile.length() == 0) {
          // ☁️ Try downloading from cloud (handles missing + corrupted files)
          if (_syncEngine != null) {
            try {
              final cloudBytes = await _syncEngine!.adapter.downloadAsset(
                _canvasId,
                docNode.id,
              );
              if (cloudBytes != null) {
                await pdfFile.parent.create(recursive: true);
                await pdfFile.writeAsBytes(cloudBytes);
              } else {
                continue;
              }
            } catch (e) {
              continue;
            }
          } else {
            continue;
          }
        }

        // Create a new native provider and load the PDF bytes
        final documentId = docNode.id;
        final provider = NativeFlueraPdfProvider(documentId: documentId);
        final bytes = await pdfFile.readAsBytes();
        final loaded = await provider.loadDocument(bytes);

        if (!loaded) {
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

        // 📡 Wire real-time broadcast callback
        if (_realtimeEngine != null) {
          docNode.onMutation = (subAction, data) {
            _realtimeEngine!.broadcastPdfUpdated(
              documentId: documentId,
              subAction: subAction,
              data: data,
            );
          };
        }

        // Re-layout and attach to the correct layer
        docNode.performGridLayout();

        // Restore display name from model if node name was empty
        if (docNode.name.isEmpty && docNode.documentModel.fileName != null) {
          docNode.name = docNode.documentModel.fileName!;
        }

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
      } catch (e) {}
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
            if (mounted) {
              _pdfLayoutVersion++;
              setState(() {});
            }
          },
        );
      }
    }
  }

  /// 📄 Restore a [PdfPreviewCardNode] that was deserialized from the
  /// `scene_nodes_json` sidecar during canvas load.
  ///
  /// Re-opens the PDF file from disk, creates the native provider and
  /// LOD-aware painter, renders the page-1 thumbnail, and registers the
  /// document in the search controller — exactly like [_importPdfBytes]
  /// but for a node that already exists in the scene graph.
  Future<void> _restorePdfPreviewCardNode(PdfPreviewCardNode cardNode) async {
    final docId = cardNode.documentId;
    final filePath = cardNode.documentModel.filePath;

    // Skip if provider already exists (e.g. double-restore guard)
    if (_pdfProviders.containsKey(docId)) return;

    // Blank PDFs have no backing file — create provider-less painter
    if (filePath == null || filePath.isEmpty) {
      _pdfPainters[docId] = PdfPagePainter(
        provider: null,
        memoryBudget: PdfMemoryBudget(),
        documentId: docId,
      );
      _activePdfDocumentId = docId;
      return;
    }

    // Check if the PDF file still exists on disk
    if (kIsWeb) return;
    final pdfFile = File(filePath);
    if (!await pdfFile.exists() || await pdfFile.length() == 0) {
      // ☁️ Try downloading from cloud
      if (_syncEngine != null) {
        try {
          final cloudBytes = await _syncEngine!.adapter.downloadAsset(
            _canvasId,
            docId,
          );
          if (cloudBytes != null) {
            await pdfFile.parent.create(recursive: true);
            await pdfFile.writeAsBytes(cloudBytes);
          } else {
            return;
          }
        } catch (_) {
          return;
        }
      } else {
        return;
      }
    }

    // Create native provider and load the document
    final provider = NativeFlueraPdfProvider(documentId: docId);
    final bytes = await pdfFile.readAsBytes();
    final loaded = await provider.loadDocument(bytes);

    if (!loaded) {
      provider.dispose();
      return;
    }

    // Store provider and create LOD-aware painter
    _pdfProviders[docId] = provider;
    _pdfPainters[docId] = PdfPagePainter(
      provider: provider,
      memoryBudget: PdfMemoryBudget(),
      documentId: docId,
    );

    // 🔋 Update shared budget across all active documents
    final docCount = _pdfPainters.length;
    for (final p in _pdfPainters.values) {
      p.memoryBudget.activeDocumentCount = docCount;
    }

    // Render page 1 thumbnail for the preview card
    try {
      final firstPage = cardNode.documentModel.pages.first;
      final thumbScale = 200.0 / firstPage.originalSize.width;
      final thumbImage = await provider.renderPage(
        pageIndex: 0,
        scale: thumbScale,
        targetSize: Size(
          200,
          200 * firstPage.originalSize.height / firstPage.originalSize.width,
        ),
      );
      if (thumbImage != null) {
        cardNode.disposeThumbnail();
        cardNode.thumbnailImage = thumbImage;
      }
    } catch (_) {}

    // Register document in search controller
    _pdfSearchController ??= PdfSearchController();
    _pdfSearchController!.registerDocument(
      docId,
      Uint8List.fromList(bytes),
      provider: provider,
    );

    // Auto-select last restored PDF
    _activePdfDocumentId = docId;
  }

  // ---------------------------------------------------------------------------
  // PDF thumbnail rendering for cloud upload
  // ---------------------------------------------------------------------------

  /// 🖼️ Render page 1 of a PDF as PNG bytes (200px wide) for cloud thumbnail.
  ///
  /// Used during upload to create a lightweight preview that syncs ~95% faster
  /// than the full PDF on new-device restore.
  Future<Uint8List?> _renderPdfThumbnailBytes(
    NativeFlueraPdfProvider provider,
    Size pageSize,
  ) async {
    try {
      final thumbScale = 200.0 / pageSize.width;
      final thumbImage = await provider.renderPage(
        pageIndex: 0,
        scale: thumbScale,
        targetSize: Size(200, 200 * pageSize.height / pageSize.width),
      );
      if (thumbImage == null) return null;

      final byteData = await thumbImage.toByteData(
        format: ui.ImageByteFormat.png,
      );
      thumbImage.dispose();
      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // PDF offline upload queue
  // ---------------------------------------------------------------------------

  /// 📶 Offline PDF upload queue — failed uploads queued for retry.
  static final Map<String, _OfflinePdfUploadEntry> _offlinePdfUploadQueue = {};

  /// 📶 Drain the offline PDF retry queue (called after a successful upload).
  Future<void> _drainOfflinePdfQueue() async {
    if (_offlinePdfUploadQueue.isEmpty || _syncEngine == null) return;

    final entries = Map.of(_offlinePdfUploadQueue);
    _offlinePdfUploadQueue.clear();

    for (final entry in entries.values) {
      if (!mounted) break;
      try {
        final pdfFuture = _syncEngine!.adapter.uploadAsset(
          _canvasId, entry.docId, entry.bytes,
          mimeType: 'application/pdf',
        );
        final thumbFuture = _renderPdfThumbnailBytes(
          entry.provider, entry.pageSize,
        ).then((tb) {
          if (tb == null) return '';
          return _syncEngine!.adapter.uploadAsset(
            _canvasId, '${entry.docId}_thumb', tb,
            mimeType: 'image/png',
          );
        }).catchError((_) => '');

        await Future.wait([pdfFuture, thumbFuture]);
      } catch (_) {
        // Re-queue if still failing
        _offlinePdfUploadQueue[entry.docId] = entry;
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
            return; // Link to first matching page only
          }
        }
      }
    }
  }

  /// 📄 Retroactively link existing strokes to a newly-created PDF document.
  ///
  /// Fixes race condition: when collaborating, strokes may arrive BEFORE
  /// the PDF creation event. Those strokes aren't linked because no PDF
  /// existed at `_linkStrokeToPdfPage` time. After the PDF is created,
  /// we scan all existing strokes and link any that overlap the new pages.
  void _retroactiveLinkStrokesToPdf(PdfDocumentNode doc) {
    int linked = 0;
    for (final layer in _layerController.layers) {
      for (final strokeNode in layer.node.strokeNodes) {
        final stroke = strokeNode.stroke;
        final bounds = stroke.bounds;
        if (bounds.isEmpty) continue;

        // Check if this stroke is ALREADY linked to any page in any doc
        bool alreadyLinked = false;
        for (final child in layer.node.children) {
          if (child is PdfDocumentNode) {
            for (final page in child.pageNodes) {
              if (page.pageModel.annotations.contains(stroke.id)) {
                alreadyLinked = true;
                break;
              }
            }
          }
          if (alreadyLinked) break;
        }
        if (alreadyLinked) continue;

        // Try to link this unlinked stroke to the new PDF's pages
        final pageIdx = doc.linkAnnotation(stroke.id, bounds);
        if (pageIdx >= 0) {
          linked++;
        }
      }
    }
    if (linked > 0) {}
  }

  /// 📄 Reconcile PDF annotation IDs with actual strokes in the scene graph.
  ///
  /// Removes any annotation IDs from PDF pages whose strokes no longer
  /// exist in any layer (e.g. after erasing). This prevents orphaned
  /// references from accumulating.
  void _reconcilePdfAnnotations() {
    // Build a set of all existing stroke IDs across all layers
    final existingIds = <String>{};
    for (final layer in _layerController.layers) {
      for (final strokeNode in layer.node.strokeNodes) {
        existingIds.add(strokeNode.stroke.id);
      }
    }

    // Walk all PDF documents and remove orphaned annotation IDs
    for (final layer in _layerController.layers) {
      for (final child in layer.node.children) {
        if (child is PdfDocumentNode) {
          for (final page in child.pageNodes) {
            final annotations = page.pageModel.annotations;
            if (annotations.isEmpty) continue;
            final orphaned =
                annotations.where((id) => !existingIds.contains(id)).toList();
            if (orphaned.isNotEmpty) {
              for (final id in orphaned) {
                child.unlinkAnnotation(id);
              }
            }
          }
        }
      }
    }
  }

  /// 📄 Re-link strokes to PDF pages after they have been moved (e.g. by lasso).
  ///
  /// Unlinks [movedStrokeIds] from their current pages, then re-links them
  /// based on their new bounds. This ensures strokes dragged from one page
  /// to another correctly transfer their page binding.
  void _relinkStrokesToPdfPages(Set<String> movedStrokeIds) {
    if (movedStrokeIds.isEmpty) return;

    // Step 1: Unlink all moved strokes from their current pages
    for (final layer in _layerController.layers) {
      for (final child in layer.node.children) {
        if (child is PdfDocumentNode) {
          for (final id in movedStrokeIds) {
            child.unlinkAnnotation(id);
          }
        }
      }
    }

    // Step 2: Re-link based on current bounds
    for (final layer in _layerController.layers) {
      for (final strokeNode in layer.node.strokeNodes) {
        if (!movedStrokeIds.contains(strokeNode.stroke.id)) continue;
        _linkStrokeToPdfPage(strokeNode.stroke);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // 📖 PDF Reader Mode — full-screen navigation
  // ---------------------------------------------------------------------------

  /// Hit-test a canvas position against all PdfPreviewCardNodes.
  /// Returns the matching node, or null.
  PdfPreviewCardNode? _hitTestPdfPreviewCard(Offset canvasPos) {
    for (final layer in _layerController.layers) {
      for (final child in layer.node.children) {
        if (child is PdfPreviewCardNode && child.hitTest(canvasPos)) {
          return child;
        }
      }
    }
    return null;
  }

  /// Enter the full-screen PDF reader for a given preview card.
  ///
  /// Uses [transitionsBuilder] with child always in the tree from frame 0.
  /// The [WormholeDivePainter]'s cross-fade dissolve handles seamless reveal.
  void _enterPdfReader(PdfPreviewCardNode cardNode) {
    final docId = cardNode.documentId;
    final provider = _pdfProviders[docId];

    if (provider == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PDF not loaded — try re-importing'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }


    // Capture card's screen rect
    final canvasRenderBox = _canvasRepaintBoundaryKey.currentContext
        ?.findRenderObject() as RenderBox?;
    final canvasGlobalOffset =
        canvasRenderBox?.localToGlobal(Offset.zero) ?? Offset.zero;
    final worldBounds = cardNode.worldBounds;
    final rawTL = _canvasController.canvasToScreen(worldBounds.topLeft);
    final rawBR = _canvasController.canvasToScreen(worldBounds.bottomRight);
    final cardRect = Rect.fromPoints(
      rawTL + canvasGlobalOffset,
      rawBR + canvasGlobalOffset,
    );
    final vp = MediaQuery.sizeOf(context);
    final fullRect = Offset.zero & vp;
    final thumbnail = cardNode.thumbnailImage?.clone();

    // Haptic sequence: light "grab" → delayed medium "dive"
    HapticFeedback.lightImpact();
    Future.delayed(const Duration(milliseconds: 135), () {
      HapticFeedback.mediumImpact();
    });

    // Warm amber accent for PDF content
    const pdfAccent = Color(0xFFE8A84C);

    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 900),
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (context, _, __) => PdfReaderScreen(
          documentModel: cardNode.documentModel,
          provider: provider,
          documentId: docId,
          onClose: (updatedModel) {
            cardNode.documentModel = updatedModel;
            _refreshPreviewCardThumbnail(cardNode);
            if (mounted) setState(() {});
          },
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return AnimatedBuilder(
            animation: animation,
            builder: (context, _) {
              final t = animation.value;
              // On reverse (pop), skip painter — cardRect is stale
              // after canvas repositioning. Instant pop instead.
              if (animation.status == AnimationStatus.reverse) {
                return child;
              }
              return Stack(
                children: [
                  child,
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: WormholeDivePainter(
                            t: t,
                            thumbnail: thumbnail,
                            cardRect: cardRect,
                            fullRect: fullRect,
                            accentColor: pdfAccent,
                          ),
                          size: Size.infinite,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 🔍 PDF Zoom-to-Enter — "dive into" a PDF by zooming
  // ---------------------------------------------------------------------------

  /// Called continuously during canvas transform changes.
  /// Only checks zoom-to-enter when canvas is actively being scaled.
  void _onPdfZoomCheck() {
    if (!mounted) return;
    if (_pdfZoomEnterCooldown) return;
    // 🚀 THROTTLE: Skip if called too recently (zoom fires 60fps)
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastZoomCheckTime < 200) return;
    // Only check during active zooming (scale > 1.2)
    if (_canvasController.scale > 1.2) {
      _checkPdfZoomToEnter();
    }
  }

  /// Check if any PDF preview card fills enough of the viewport to trigger
  /// the immersive zoom-to-enter animation.
  ///
  /// Called both on gesture end AND continuously during zoom (throttled).
  /// Two-phase entry: auto-center snap → then cinematic transition.
  void _checkPdfZoomToEnter() {
    if (_pdfZoomEnterCooldown) return;

    // Throttle: max once per 100ms during continuous zoom
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastZoomCheckTime < 100) return;
    _lastZoomCheckTime = now;

    final viewportSize = MediaQuery.of(context).size;
    final scale = _canvasController.scale;

    if (scale < 1.2) return;

    PdfPreviewCardNode? bestCard;
    double bestCoverage = 0;

    for (final layer in _layerController.layers) {
      for (final child in layer.node.children) {
        if (child is! PdfPreviewCardNode) continue;

        final worldBounds = child.worldBounds;
        final screenTopLeft = _canvasController.canvasToScreen(worldBounds.topLeft);
        final screenBottomRight = _canvasController.canvasToScreen(worldBounds.bottomRight);
        final screenRect = Rect.fromPoints(screenTopLeft, screenBottomRight);

        final viewportRect = Rect.fromLTWH(0, 0, viewportSize.width, viewportSize.height);
        final intersection = screenRect.intersect(viewportRect);
        if (intersection.isEmpty) continue;

        final widthCoverage = screenRect.width / viewportSize.width;
        final cardCenter = screenRect.center;
        final viewportCenter = viewportRect.center;
        final centerDistance = (cardCenter - viewportCenter).distance;
        final maxDistance = viewportSize.width * 0.35;

        if (widthCoverage > bestCoverage && centerDistance < maxDistance) {
          bestCoverage = widthCoverage;
          bestCard = child;
        }
      }
    }

    // Trigger at >75% coverage: center and enter
    if (bestCard != null && bestCoverage > 0.75) {
      _pdfZoomEnterCooldown = true;

      // Snap-center the canvas on the card INSTANTLY.
      // Using animateOffsetTo + delay is unreliable: the spring may not
      // finish in time, leaving the canvas mid-animation when the
      // transition captures coordinates. Use setOffset for an instant snap.
      final worldCenter = bestCard.worldBounds.center;
      final screenCenter = Offset(viewportSize.width / 2, viewportSize.height / 2);
      final targetOffset = Offset(
        screenCenter.dx - worldCenter.dx * scale,
        screenCenter.dy - worldCenter.dy * scale,
      );
      _canvasController.stopAnimation();
      _canvasController.setOffset(targetOffset);

      // Launch cinematic transition immediately (canvas is now stable)
      _enterPdfReaderWithZoomAnimation(bestCard);
    }
  }


  /// Open the PDF reader with a cinematic Wormhole Dive animation.
  ///
  /// Uses [transitionsBuilder] with child always in the tree from frame 0.
  void _enterPdfReaderWithZoomAnimation(PdfPreviewCardNode cardNode) {
    final docId = cardNode.documentId;
    final provider = _pdfProviders[docId];
    if (provider == null) return;

    _pdfZoomEnterCooldown = true;

    // 🛑 Stop all canvas animations BEFORE capturing coordinates.
    _canvasController.stopAnimation();

    // Capture card's current screen rect.
    final canvasRenderBox = _canvasRepaintBoundaryKey.currentContext
        ?.findRenderObject() as RenderBox?;
    final canvasGlobalOffset =
        canvasRenderBox?.localToGlobal(Offset.zero) ?? Offset.zero;
    final worldBounds = cardNode.worldBounds;
    final rawTL = _canvasController.canvasToScreen(worldBounds.topLeft);
    final rawBR = _canvasController.canvasToScreen(worldBounds.bottomRight);
    final cardRect = Rect.fromPoints(
      rawTL + canvasGlobalOffset,
      rawBR + canvasGlobalOffset,
    );
    final vp = MediaQuery.sizeOf(context);
    final fullRect = Offset.zero & vp;
    final thumbnail = cardNode.thumbnailImage?.clone();

    // Haptic sequence: light "grab" → delayed medium "dive"
    HapticFeedback.lightImpact();
    Future.delayed(const Duration(milliseconds: 135), () {
      HapticFeedback.mediumImpact();
    });

    const pdfAccent = Color(0xFFE8A84C);

    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 900),
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (context, _, __) => PdfReaderScreen(
          documentModel: cardNode.documentModel,
          provider: provider,
          documentId: docId,
          onClose: (updatedModel) {
            cardNode.documentModel = updatedModel;
            _refreshPreviewCardThumbnail(cardNode);
            if (mounted) setState(() {});
          },
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return AnimatedBuilder(
            animation: animation,
            builder: (context, _) {
              final t = animation.value;
              if (animation.status == AnimationStatus.reverse) {
                return child;
              }
              return Stack(
                children: [
                  child,
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: WormholeDivePainter(
                            t: t,
                            thumbnail: thumbnail,
                            cardRect: cardRect,
                            fullRect: fullRect,
                            accentColor: pdfAccent,
                          ),
                          size: Size.infinite,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    ).then((_) {
      final currentScale = _canvasController.scale;
      if (currentScale > 1.1) {
        _canvasController.setScale(1.0);
      }
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) _pdfZoomEnterCooldown = false;
      });
    });
  }

  /// Re-render the page 1 thumbnail on a preview card.
  Future<void> _refreshPreviewCardThumbnail(PdfPreviewCardNode cardNode) async {
    final provider = _pdfProviders[cardNode.documentId];
    if (provider == null) return;

    try {
      final firstPage = cardNode.documentModel.pages.first;
      final thumbScale = 200.0 / firstPage.originalSize.width;
      final thumbImage = await provider.renderPage(
        pageIndex: 0,
        scale: thumbScale,
        targetSize: Size(
          200,
          200 * firstPage.originalSize.height / firstPage.originalSize.width,
        ),
      );
      if (thumbImage != null) {
        cardNode.disposeThumbnail();
        cardNode.thumbnailImage = thumbImage;
        if (mounted) setState(() {});
      }
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // 📝 Page background chooser
  // ---------------------------------------------------------------------------

  /// Show a bottom sheet to pick the page background pattern and document title,
  /// then create a blank PDF document.
  void _showBackgroundChooser(BuildContext ctx) {
    showModalBottomSheet<(PdfPageBackground, String)>(
      context: ctx,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder:
          (sheetCtx) => _PdfCreateSheet(
            onDone: (bg, title) {
              Navigator.of(sheetCtx).pop((bg, title));
            },
          ),
    ).then((result) {
      if (result != null) {
        final (bg, title) = result;
        createBlankPdfDocument(background: bg);
        // Update document name if user entered a title
        if (title.trim().isNotEmpty && _activePdfDocumentId != null) {
          final doc = _findPdfDocumentNode(_activePdfDocumentId!);
          if (doc != null) {
            doc.name = title.trim();
            if (doc is PdfPreviewCardNode) {
              doc.documentModel = doc.documentModel.copyWith(
                fileName: title.trim(),
              );
            } else if (doc is PdfDocumentNode) {
              doc.documentModel = doc.documentModel.copyWith(
                fileName: title.trim(),
              );
            }
            _realtimeEngine?.broadcastPdfUpdated(
              documentId: doc.id.toString(),
              subAction: 'documentRenamed',
              data: {'fileName': title.trim()},
            );
            if (mounted) setState(() {});
          }
        }
      }
    });
  }

  /// Find a PDF node (preview card or legacy document) by its document ID across all layers.
  CanvasNode? _findPdfDocumentNode(String documentId) {
    for (final layer in _layerController.layers) {
      for (final child in layer.node.children) {
        if (child is PdfPreviewCardNode && child.documentId == documentId) {
          return child;
        }
        if (child is PdfDocumentNode && child.id.toString() == documentId) {
          return child;
        }
      }
    }
    return null;
  }

  /// 🗑️ Remove an entire PDF document from the canvas.
  ///
  /// Cleans up: native provider, painter, annotations, scene graph node,
  /// annotation controller, active selection, and broadcasts to collaborators.
  void removePdfDocument(String documentId, {bool broadcast = true}) {
    final docNode = _findPdfDocumentNode(documentId);
    if (docNode == null) {
      return;
    }

    // 1️⃣ Close native provider (releases platform resources)
    final provider = _pdfProviders.remove(documentId);
    provider?.dispose();

    // 2️⃣ Remove painter
    _pdfPainters.remove(documentId);

    // 3️⃣ Remove from scene graph
    for (final layer in _layerController.layers) {
      layer.node.children.removeWhere(
        (child) =>
            (child is PdfPreviewCardNode && child.documentId == documentId) ||
            (child is PdfDocumentNode && child.id.toString() == documentId),
      );
    }

    // 4️⃣ Reset active PDF if this was selected
    if (_activePdfDocumentId == documentId) {
      _activePdfDocumentId = null;
      _pdfAnnotationController?.dispose();
      _pdfAnnotationController = null;
    }

    // 6️⃣ Cancel any active upload for this PDF
    _activePdfUploads.remove(documentId);
    _offlinePdfUploadQueue.remove(documentId);

    // 🗑️ Cloud: delete orphaned PDF + thumbnail from Supabase Storage
    if (_syncEngine != null) {
      Future(() async {
        try {
          await _syncEngine!.adapter.deleteAsset(_canvasId, documentId);
          await _syncEngine!.adapter.deleteAsset(_canvasId, '${documentId}_thumb');
        } catch (_) {} // Best-effort cleanup
      });
    }

    // 7️⃣ Broadcast to collaborators
    if (broadcast && _realtimeEngine != null) {
      _realtimeEngine!.broadcastPdfRemoved(documentId: documentId);
    }

    // 8️⃣ Auto-save + rebuild UI
    _autoSaveCanvas();
    if (mounted) setState(() {});
  }

  /// 🗑️ Show confirmation dialog before deleting a PDF document.
  void showDeletePdfConfirmation(BuildContext context, String documentId) {
    final docNode = _findPdfDocumentNode(documentId);
    String? fileName;
    int pageCount = 0;
    if (docNode is PdfPreviewCardNode) {
      fileName = docNode.documentModel.fileName;
      pageCount = docNode.documentModel.totalPages;
    } else if (docNode is PdfDocumentNode) {
      fileName = docNode.documentModel.fileName;
      pageCount = docNode.documentModel.totalPages;
    }
    fileName ??= 'this document';

    showDialog(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          icon: Icon(Icons.delete_forever_rounded, color: cs.error, size: 32),
          title: const Text('Delete PDF'),
          content: Text(
            'Delete "$fileName" ($pageCount pages)?\n\n'
            'All annotations on this document will be unlinked. '
            'This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                removePdfDocument(documentId);
                HapticFeedback.mediumImpact();
              },
              style: FilledButton.styleFrom(
                backgroundColor: cs.error,
                foregroundColor: cs.onError,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }
}

/// 📶 Queued PDF upload entry for offline retry.
class _OfflinePdfUploadEntry {
  final String docId;
  final Uint8List bytes;
  final NativeFlueraPdfProvider provider;
  final Size pageSize;

  const _OfflinePdfUploadEntry({
    required this.docId,
    required this.bytes,
    required this.provider,
    required this.pageSize,
  });
}
