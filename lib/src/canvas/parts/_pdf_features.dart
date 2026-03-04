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

    // ☁️ Cloud upload moved to AFTER local import — see below.
    // PDF is shown locally first for instant feedback.

    // Create a native provider for this document
    final provider = NativeFlueraPdfProvider(documentId: docId);

    // Import via PdfImportController
    final controller = PdfImportController(provider: provider);

    // Use sender's position (remote sync) or calculate from viewport center
    final insertPosition =
        position ??
        _canvasController.screenToCanvas(
          Offset(
            MediaQuery.of(context).size.width / 2,
            MediaQuery.of(context).size.height / 2,
          ),
        );

    final docNode = await controller.importDocument(
      documentId: docId,
      bytes: bytes,
      insertPosition: insertPosition,
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

    // 💾 Store file path and name in document model for persistence
    docNode.documentModel = docNode.documentModel.copyWith(
      filePath: pdfFile.path,
      fileName: fileName,
    );

    // 📄 Set node name for toolbar display
    if (fileName != null && fileName.isNotEmpty) {
      docNode.name = fileName;
    }

    // 📄 Store provider and create LOD-aware painter for this document
    _pdfProviders[docId] = provider;
    _pdfPainters[docId] = PdfPagePainter(
      provider: provider,
      memoryBudget: PdfMemoryBudget(),
      documentId: docId,
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

    // 📄 Initialize annotation controller for toolbar
    _pdfAnnotationController?.dispose();
    _pdfAnnotationController = PdfAnnotationController();
    _pdfAnnotationController!.attach(docNode);

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
      activeLayer.node.add(docNode);

      // 📄 Retroactively link strokes that arrived before this PDF (race condition)
      if (!broadcast) _retroactiveLinkStrokesToPdf(docNode);
    }

    // 📄 Auto-select newly imported PDF in toolbar
    _activePdfDocumentId = docId;

    // Trigger rebuild + auto-save
    if (mounted) setState(() {});
    _autoSaveCanvas();

    if (broadcast) HapticFeedback.mediumImpact();

    // 🔥 Background warm-up: pre-render all pages at low LOD
    final painter = _pdfPainters[docId];
    if (painter != null) {
      painter.warmUpAllPages(
        docNode.pageNodes,
        onNeedRepaint: () {
          if (mounted) {
            _pdfLayoutVersion++;
            setState(() {});
          }
        },
      );
    }

    // 📄 Auto-scroll to center on first page (LOCAL imports only —
    // never shift the other device's viewport on remote sync)
    if (broadcast) {
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
    }


    // 📡 Broadcast to collaborators — two-phase:
    // Phase 1: Immediately broadcast pdfLoading (placeholder on remote)
    // Phase 2: Background upload + broadcast pdfAdded (with gzip bytes)
    if (broadcast && _realtimeEngine != null) {
      // Get first page size for placeholder
      final firstPageSize =
          docNode.pageNodes.firstOrNull?.pageModel.originalSize ??
          const Size(595, 842);

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
      } catch (e) {
      }

      // 🛡️ RTDB payload guard: drop thumbnail if too large (>50KB base64)
      if (thumbnailBase64 != null && thumbnailBase64.length > 50000) {
        thumbnailBase64 = null;
      }

      // Phase 1: Immediate placeholder notification (with thumbnail)
      _realtimeEngine!.broadcastPdfLoading(
        documentId: docId,
        pageCount: docNode.documentModel.totalPages,
        pageWidth: firstPageSize.width,
        pageHeight: firstPageSize.height,
        positionX: insertPosition.dx,
        positionY: insertPosition.dy,
        fileName: fileName,
        thumbnailBase64: thumbnailBase64,
      );

      // Phase 2: Background upload + gzip broadcast (fire-and-forget)
      final uploadFuture = Future(() async {
        bool uploadOk = false;

        // Upload to cloud storage with REAL progress from Firebase
        if (_syncEngine != null) {
          try {
            await _syncEngine!.adapter.uploadAsset(
              _canvasId,
              docId,
              bytes,
              mimeType: 'application/pdf',
              onProgress: (p) {
                // Scale upload progress to 0–70% of total
                _realtimeEngine?.broadcastPdfProgress(
                  documentId: docId,
                  progress: p * 0.7,
                );
              },
            );
            uploadOk = true;
          } catch (e) {
          }
        }

        // Broadcast pdfAdded — skip inline bytes for large PDFs (>10MB)
        // RTDB has ~16MB write limit, gzip+base64 can exceed this for large files.
        // Receivers will download from Cloud Storage instead.
        try {
          String? b64;
          if (bytes.length <= 10 * 1024 * 1024) {
            // Small PDF: include inline gzip+base64 as fallback
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
          } else {
            // Large PDF: cloud-only transfer, no inline bytes
          }

          _realtimeEngine?.broadcastPdfAdded(
            documentId: docId,
            fileName: fileName,
            pageCount: docNode.documentModel.totalPages,
            positionX: insertPosition.dx,
            positionY: insertPosition.dy,
            pdfBytesBase64: b64,
          );
        } catch (e) {
          if (!uploadOk) {
            _realtimeEngine?.broadcastPdfLoadingFailed(documentId: docId);
          }
        }

        // Remove from active uploads
        _activePdfUploads.remove(docId);
      });

      // Track active upload for cancel support
      _activePdfUploads[docId] = uploadFuture;
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

      } catch (e) {
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
            if (mounted) {
              _pdfLayoutVersion++;
              setState(() {});
            }
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
    if (linked > 0) {
    }
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
            doc.documentModel = doc.documentModel.copyWith(
              fileName: title.trim(),
            );
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

  /// Find a PdfDocumentNode by its document ID across all layers.
  PdfDocumentNode? _findPdfDocumentNode(String documentId) {
    for (final layer in _layerController.layers) {
      for (final child in layer.node.children) {
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
            child is PdfDocumentNode && child.id.toString() == documentId,
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
    final fileName = docNode?.documentModel.fileName ?? 'this document';
    final pageCount = docNode?.documentModel.totalPages ?? 0;

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

// =============================================================================
// 📝 PDF Create Sheet — Stateful bottom sheet with MD3 design
// =============================================================================

class _PdfCreateSheet extends StatefulWidget {
  final void Function(PdfPageBackground bg, String title) onDone;

  const _PdfCreateSheet({required this.onDone});

  @override
  State<_PdfCreateSheet> createState() => _PdfCreateSheetState();
}

class _PdfCreateSheetState extends State<_PdfCreateSheet> {
  PdfPageBackground _selected = PdfPageBackground.blank;
  final _titleController = TextEditingController(text: 'Untitled Document');

  @override
  void initState() {
    super.initState();
    // Auto-select title text for quick replacement
    _titleController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _titleController.text.length,
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 12,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Handle bar ──
                Container(
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),

                // ── Title ──
                Text(
                  'New Document',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 20),

                // ── Document title field ──
                TextField(
                  controller: _titleController,
                  autofocus: true,
                  style: TextStyle(
                    fontSize: 16,
                    color: cs.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Document title',
                    labelStyle: TextStyle(color: cs.onSurfaceVariant),
                    prefixIcon: Icon(
                      Icons.edit_document,
                      color: cs.primary,
                      size: 20,
                    ),
                    filled: true,
                    fillColor: cs.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: cs.primary, width: 2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _create(),
                ),
                const SizedBox(height: 24),

                // ── Section label ──
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Page style',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // ── Pattern grid with previews ──
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.72,
                  children:
                      PdfPageBackground.values.map((bg) {
                        final isSelected = _selected == bg;
                        return _PatternCard(
                          background: bg,
                          isSelected: isSelected,
                          colorScheme: cs,
                          onTap: () => setState(() => _selected = bg),
                        );
                      }).toList(),
                ),
                const SizedBox(height: 24),

                // ── Create button ──
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: _create,
                    icon: const Icon(Icons.add_rounded, size: 20),
                    label: const Text(
                      'Create',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _create() {
    widget.onDone(_selected, _titleController.text);
  }
}

// =============================================================================
// 📝 Pattern preview card
// =============================================================================

class _PatternCard extends StatelessWidget {
  final PdfPageBackground background;
  final bool isSelected;
  final ColorScheme colorScheme;
  final VoidCallback onTap;

  const _PatternCard({
    required this.background,
    required this.isSelected,
    required this.colorScheme,
    required this.onTap,
  });

  String get _label {
    switch (background) {
      case PdfPageBackground.blank:
        return 'Blank';
      case PdfPageBackground.ruled:
        return 'Ruled';
      case PdfPageBackground.grid:
        return 'Grid';
      case PdfPageBackground.dotted:
        return 'Dotted';
      case PdfPageBackground.music:
        return 'Music';
      case PdfPageBackground.cornell:
        return 'Cornell';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? cs.primary : cs.outlineVariant,
            width: isSelected ? 2.5 : 1.0,
          ),
          color:
              isSelected
                  ? cs.primaryContainer.withValues(alpha: 0.3)
                  : cs.surfaceContainerLow,
        ),
        child: Column(
          children: [
            // ── Mini page preview ──
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: cs.outlineVariant.withValues(alpha: 0.4),
                      width: 0.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: CustomPaint(
                    painter: _PatternPreviewPainter(background),
                    size: Size.infinite,
                  ),
                ),
              ),
            ),
            // ── Label ──
            Padding(
              padding: const EdgeInsets.only(bottom: 8, top: 2),
              child: Text(
                _label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? cs.primary : cs.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// 📝 Pattern preview painter — mini version of page background
// =============================================================================

class _PatternPreviewPainter extends CustomPainter {
  final PdfPageBackground background;

  _PatternPreviewPainter(this.background);

  static final Paint _linePaint =
      Paint()
        ..color = const Color(0xFFB3D5F5)
        ..strokeWidth = 0.5
        ..style = PaintingStyle.stroke;

  static final Paint _dotPaint =
      Paint()
        ..color = const Color(0xFFB0BEC5)
        ..style = PaintingStyle.fill;

  static final Paint _heavyPaint =
      Paint()
        ..color = const Color(0xFF90A4AE)
        ..strokeWidth = 0.8
        ..style = PaintingStyle.stroke;

  static final Paint _marginPaint =
      Paint()
        ..color = const Color(0x40E57373)
        ..strokeWidth = 0.6
        ..style = PaintingStyle.stroke;

  @override
  void paint(Canvas canvas, Size size) {
    switch (background) {
      case PdfPageBackground.blank:
        return;

      case PdfPageBackground.ruled:
        final mx = size.width * 0.18;
        canvas.drawLine(Offset(mx, 0), Offset(mx, size.height), _marginPaint);
        const spacing = 8.0;
        for (double y = spacing * 2; y < size.height - 4; y += spacing) {
          canvas.drawLine(Offset(4, y), Offset(size.width - 4, y), _linePaint);
        }

      case PdfPageBackground.grid:
        const spacing = 7.0;
        for (double x = 3; x <= size.width - 3; x += spacing) {
          canvas.drawLine(Offset(x, 3), Offset(x, size.height - 3), _linePaint);
        }
        for (double y = 3; y <= size.height - 3; y += spacing) {
          canvas.drawLine(Offset(3, y), Offset(size.width - 3, y), _linePaint);
        }

      case PdfPageBackground.dotted:
        const spacing = 7.0;
        for (double x = 4; x <= size.width - 4; x += spacing) {
          for (double y = 4; y <= size.height - 4; y += spacing) {
            canvas.drawCircle(Offset(x, y), 0.7, _dotPaint);
          }
        }

      case PdfPageBackground.music:
        const staffSpacing = 3.0;
        const groupGap = 14.0;
        double y = 10.0;
        while (y + staffSpacing * 4 < size.height - 8) {
          for (int i = 0; i < 5; i++) {
            canvas.drawLine(
              Offset(4, y + i * staffSpacing),
              Offset(size.width - 4, y + i * staffSpacing),
              _heavyPaint,
            );
          }
          y += staffSpacing * 4 + groupGap;
        }

      case PdfPageBackground.cornell:
        final cueX = size.width * 0.30;
        final summaryY = size.height * 0.80;
        final topLine = size.height * 0.12;
        canvas.drawLine(
          Offset(3, topLine),
          Offset(size.width - 3, topLine),
          _heavyPaint,
        );
        canvas.drawLine(
          Offset(cueX, topLine),
          Offset(cueX, summaryY),
          _heavyPaint,
        );
        canvas.drawLine(
          Offset(3, summaryY),
          Offset(size.width - 3, summaryY),
          _heavyPaint,
        );
        for (double y = topLine + 8; y < summaryY - 3; y += 8) {
          canvas.drawLine(
            Offset(cueX + 3, y),
            Offset(size.width - 4, y),
            _linePaint,
          );
        }
    }
  }

  @override
  bool shouldRepaint(_PatternPreviewPainter old) =>
      old.background != background;
}
