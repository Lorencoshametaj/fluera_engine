part of '../fluera_canvas_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// 📄 Collaboration — PDF Sync Handlers
// ═══════════════════════════════════════════════════════════════════════════

extension _CollaborationPdfSync on _FlueraCanvasScreenState {

  // ─── PDF Sync ─────────────────────────────────────────────────────

  /// 📄 Apply a remotely-signaled PDF loading placeholder.
  void _applyRemotePdfLoading(Map<String, dynamic> payload) {
    final docId = payload['documentId'] as String?;
    if (docId == null) return;

    final pageCount = (payload['pageCount'] as num?)?.toInt() ?? 1;
    final pageWidth = (payload['pageWidth'] as num?)?.toDouble() ?? 595.0;
    final pageHeight = (payload['pageHeight'] as num?)?.toDouble() ?? 842.0;
    final posX = (payload['positionX'] as num?)?.toDouble() ?? 0;
    final posY = (payload['positionY'] as num?)?.toDouble() ?? 0;
    final fileName = payload['fileName'] as String?;
    final thumbnailBase64 = payload['thumbnail'] as String?;

    // Cancel any existing timeout for this doc
    CollaborationExtension._pdfLoadingTimeouts[docId]?.cancel();

    CollaborationExtension._pdfLoadingPlaceholders[docId] = _PdfLoadingPlaceholder(
      documentId: docId,
      fileName: fileName,
      pageCount: pageCount,
      pageWidth: pageWidth,
      pageHeight: pageHeight,
      position: Offset(posX, posY),
      thumbnailBase64: thumbnailBase64,
    );

    // ⏰ Auto-remove after 60s (safety net if sender goes offline)
    CollaborationExtension._pdfLoadingTimeouts[docId] = Timer(const Duration(seconds: 60), () {
      _cleanupPlaceholder(docId);
      if (mounted) setState(() {});
    });

    // 🔄 Start pulse animation for placeholder shimmer
    _startLoadingPulse();

    if (mounted) setState(() {});
  }

  /// 📄 Update progress on a PDF loading placeholder.
  void _applyRemotePdfProgress(Map<String, dynamic> payload) {
    final docId = payload['documentId'] as String?;
    if (docId == null) return;
    final progress = (payload['progress'] as num?)?.toDouble() ?? 0;
    final placeholder = CollaborationExtension._pdfLoadingPlaceholders[docId];
    if (placeholder != null) {
      CollaborationExtension._pdfLoadingPlaceholders[docId] = placeholder.copyWith(progress: progress);
      if (mounted) setState(() {});
    }
  }

  /// 📄 Remove placeholder when loading fails on sender.
  void _applyRemotePdfLoadingFailed(Map<String, dynamic> payload) {
    final docId = payload['documentId'] as String?;
    if (docId == null) return;
    _cleanupPlaceholder(docId);
    if (mounted) setState(() {});
  }

  /// 📄 Handle remote PDF document removal.
  void _applyRemotePdfRemoved(Map<String, dynamic> payload) {
    final docId = payload['documentId'] as String?;
    if (docId == null) return;

    // Also cleanup any loading placeholder
    _cleanupPlaceholder(docId);

    // Use the same cleanup logic but don't re-broadcast
    removePdfDocument(docId, broadcast: false);

    // Notify user
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('📄 A collaborator removed a PDF document'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

  }

  /// 📄 Apply a remotely-added PDF document.
  ///
  /// Tries to download PDF bytes from cloud storage first. If that fails,
  /// falls back to base64-encoded bytes embedded in the RTDB payload.
  void _applyRemotePdf(Map<String, dynamic> payload) async {
    try {
      final documentId = payload['documentId'] as String?;
      if (documentId == null) return;

      // Remove loading placeholder now that real PDF data is arriving
      _cleanupPlaceholder(documentId);

      if (_pdfProviders.containsKey(documentId)) {
        if (mounted) setState(() {});
        return;
      }

      Uint8List? bytes;

      // Strategy 1: Download from cloud storage (with retry + backoff)
      if (_syncEngine != null) {
        for (int attempt = 1; attempt <= 3; attempt++) {
          try {
            bytes = await _syncEngine!.adapter.downloadAsset(
              _canvasId,
              documentId,
            );
            if (bytes != null && bytes.isNotEmpty) break;
          } catch (e) {
            if (attempt < 3) {
              await Future<void>.delayed(Duration(seconds: 1 << (attempt - 1)));
            }
          }
        }
      }

      // Strategy 2: Decode gzip+base64 bytes from payload (fallback)
      if (bytes == null || bytes.isEmpty) {
        final base64Str = payload['pdfBytesBase64'] as String?;
        if (base64Str != null && base64Str.isNotEmpty) {
          final compressed = base64Decode(base64Str);
          bytes = Uint8List.fromList(GZipCodec().decode(compressed));
        }
      }

      if (bytes == null || bytes.isEmpty) {
        return;
      }

      final fileName = payload['fileName'] as String?;
      final positionX = (payload['positionX'] as num?)?.toDouble();
      final positionY = (payload['positionY'] as num?)?.toDouble();
      final remotePosition =
          (positionX != null && positionY != null)
              ? Offset(positionX, positionY)
              : null;

      // Import using existing pipeline (skip re-broadcasting to prevent loop)
      await _importPdfBytes(
        bytes,
        fileName: fileName,
        broadcast: false,
        documentId: documentId,
        position: remotePosition,
      );


      // 📳 Haptic feedback for remote PDF loaded
      HapticFeedback.lightImpact();

      // 📢 SnackBar notification
      if (mounted) {
        final label = fileName ?? 'PDF';
        final pages = (payload['pageCount'] as num?)?.toInt();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '📄 $label loaded${pages != null ? ' ($pages pages)' : ''}',
            ),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
    }
  }

  /// 📄 Apply a remotely-created blank PDF document.
  ///
  /// Recreates the blank document from metadata — no bytes download needed.
  void _applyRemoteBlankPdf(Map<String, dynamic> payload) {
    try {
      final documentId = payload['documentId'] as String?;
      if (documentId == null) return;

      // Check if this document is already loaded
      if (_pdfPainters.containsKey(documentId)) {
        return;
      }

      final pageCount = (payload['pageCount'] as num?)?.toInt() ?? 1;
      final pageWidth = (payload['pageWidth'] as num?)?.toDouble() ?? 595.0;
      final pageHeight = (payload['pageHeight'] as num?)?.toDouble() ?? 842.0;
      final backgroundName = payload['background'] as String? ?? 'blank';

      final background = PdfPageBackground.values.firstWhere(
        (b) => b.name == backgroundName,
        orElse: () => PdfPageBackground.blank,
      );

      final positionX = (payload['positionX'] as num?)?.toDouble();
      final positionY = (payload['positionY'] as num?)?.toDouble();
      final remotePosition =
          (positionX != null && positionY != null)
              ? Offset(positionX, positionY)
              : null;

      // Create locally (without re-broadcasting), using sender's ID and position
      createBlankPdfDocument(
        pageCount: pageCount,
        pageSize: Size(pageWidth, pageHeight),
        background: background,
        broadcast: false,
        position: remotePosition,
        documentId: documentId,
      );

    } catch (e) {
    }
  }

  /// 📄 Apply a remote PDF update (generic sub-action handler).
  void _applyRemotePdfUpdate(Map<String, dynamic> payload) {
    try {
      final documentId = payload['documentId'] as String?;
      final subAction = payload['subAction'] as String?;
      if (documentId == null || subAction == null) return;

      // Find the document node
      PdfDocumentNode? doc;
      for (final layer in _layerController.layers) {
        for (final child in layer.node.children) {
          if (child is PdfDocumentNode && child.id.toString() == documentId) {
            doc = child;
            break;
          }
        }
        if (doc != null) break;
      }
      if (doc == null) {
        return;
      }

      // 🛡️ CRITICAL: Disable onMutation to prevent infinite broadcast loop.
      // Remote → _applyRemotePdfUpdate → doc.rotatePage() → onMutation → broadcast → remote...
      final savedCallback = doc.onMutation;
      doc.onMutation = null;

      try {
        switch (subAction) {
          case 'pageMoved':
            final pageIndex = (payload['pageIndex'] as num?)?.toInt();
            final dx = (payload['dx'] as num?)?.toDouble();
            final dy = (payload['dy'] as num?)?.toDouble();
            if (pageIndex != null && dx != null && dy != null) {
              final page = doc.pageAt(pageIndex);
              if (page != null) {
                // Calculate translation delta for linked strokes
                final oldPos = page.position;
                final newPos = Offset(dx, dy);
                final delta = newPos - oldPos;

                page.pageModel = page.pageModel.copyWith(
                  customOffset: Offset(dx, dy),
                  isLocked: false,
                );
                page.setPosition(dx, dy);
                page.invalidateTransformCache();
                doc.invalidateBoundsCache();

                // 📄 Translate linked strokes to follow the page
                if (delta != Offset.zero) {
                  final ids = page.pageModel.annotations;
                  if (ids.isNotEmpty) {
                    _translateAnnotationStrokes(ids.toSet(), delta);
                  }
                }
              }
            }

          case 'pageRotated':
            final pageIndex = (payload['pageIndex'] as num?)?.toInt();
            final angleDeg = (payload['angleDegrees'] as num?)?.toDouble();
            if (pageIndex != null && angleDeg != null) {
              doc.rotatePage(pageIndex, angleDegrees: angleDeg);
              // 🔄 Consume pending stroke rotation so linked strokes
              // rotate with the page on the remote device.
              _consumePendingStrokeRotation(doc);
            }

          case 'pageLocked':
            final pageIndex = (payload['pageIndex'] as num?)?.toInt();
            final locked = payload['locked'] as bool?;
            if (pageIndex != null && locked != null) {
              final page = doc.pageAt(pageIndex);
              if (page != null && page.pageModel.isLocked != locked) {
                doc.togglePageLock(pageIndex);
              }
            }

          case 'pageRemoved':
            final pageIndex = (payload['pageIndex'] as num?)?.toInt();
            if (pageIndex != null) {
              doc.removePage(pageIndex);
            }

          case 'pageDuplicated':
            final pageIndex = (payload['pageIndex'] as num?)?.toInt();
            if (pageIndex != null) {
              doc.duplicatePage(pageIndex);
            }

          case 'pageReordered':
            final fromIndex = (payload['fromIndex'] as num?)?.toInt();
            final toIndex = (payload['toIndex'] as num?)?.toInt();
            if (fromIndex != null && toIndex != null) {
              doc.reorderPage(fromIndex, toIndex);
              // 📄 Consume pending stroke translations from grid re-layout
              _consumePendingStrokeTranslations(doc);
            }

          case 'pageBackgroundChanged':
            final pageIndex = (payload['pageIndex'] as num?)?.toInt();
            final bgName = payload['background'] as String?;
            if (pageIndex != null && bgName != null) {
              final page = doc.pageAt(pageIndex);
              if (page != null) {
                final bg = PdfPageBackground.values.firstWhere(
                  (b) => b.name == bgName,
                  orElse: () => PdfPageBackground.blank,
                );
                page.pageModel = page.pageModel.copyWith(background: bg);
              }
            }

          case 'documentRenamed':
            final fileName = payload['fileName'] as String?;
            if (fileName != null) {
              doc.name = fileName;
              doc.documentModel = doc.documentModel.copyWith(
                fileName: fileName,
              );
            }

          case 'pageAdded':
            final afterIndex = (payload['afterIndex'] as num?)?.toInt();
            final pageWidth = (payload['pageWidth'] as num?)?.toDouble();
            final pageHeight = (payload['pageHeight'] as num?)?.toDouble();
            final bgName = payload['background'] as String? ?? 'blank';
            final bg = PdfPageBackground.values.firstWhere(
              (b) => b.name == bgName,
              orElse: () => PdfPageBackground.blank,
            );
            final size =
                (pageWidth != null && pageHeight != null)
                    ? Size(pageWidth, pageHeight)
                    : null;
            doc.insertBlankPage(afterIndex: afterIndex, size: size);
            // Update the new page's background
            final pages = doc.pageNodes;
            final newIdx =
                afterIndex != null
                    ? (afterIndex + 1).clamp(0, pages.length - 1)
                    : pages.length - 1;
            if (newIdx < pages.length) {
              pages[newIdx].pageModel = pages[newIdx].pageModel.copyWith(
                background: bg,
              );
            }

          case 'nightModeToggled':
            final enabled = payload['enabled'] as bool?;
            if (enabled != null) {
              doc.documentModel = doc.documentModel.copyWith(
                nightMode: enabled,
              );
            }

          case 'bookmarkToggled':
            final pageIndex = (payload['pageIndex'] as num?)?.toInt();
            final isBookmarked = payload['isBookmarked'] as bool?;
            if (pageIndex != null && isBookmarked != null) {
              final page = doc.pageAt(pageIndex);
              if (page != null) {
                page.pageModel = page.pageModel.copyWith(
                  isBookmarked: isBookmarked,
                );
              }
            }

          case 'watermarkChanged':
            final text = payload['watermarkText'] as String?;
            final clear = payload['clear'] as bool? ?? false;
            if (clear) {
              doc.documentModel = doc.documentModel.copyWith(
                clearWatermarkText: true,
              );
            } else if (text != null) {
              doc.documentModel = doc.documentModel.copyWith(
                watermarkText: text,
              );
            }

          case 'documentMoved':
            final originX = (payload['originX'] as num?)?.toDouble();
            final originY = (payload['originY'] as num?)?.toDouble();
            if (originX != null && originY != null) {
              doc.documentModel = doc.documentModel.copyWith(
                gridOrigin: Offset(originX, originY),
              );
              doc.performGridLayout();
              doc.invalidateBoundsCache();

              // 📄 performGridLayout() already computed per-page deltas
              // into pendingStrokeTranslations — just consume them.
              _consumePendingStrokeTranslations(doc);
            }

          case 'annotationsToggled':
            final pageIndex = (payload['pageIndex'] as num?)?.toInt();
            final visible = payload['visible'] as bool?;
            if (pageIndex != null && visible != null) {
              final page = doc.pageAt(pageIndex);
              if (page != null && page.pageModel.showAnnotations != visible) {
                doc.togglePageAnnotations(pageIndex);
              }
            }

          case 'returnedToGrid':
            final pageIndex = (payload['pageIndex'] as num?)?.toInt();
            if (pageIndex != null) {
              final result = doc.returnPageToGrid(pageIndex);
              // 📄 Translate strokes if page moved back to grid
              if (result != null && result.annotationIds.isNotEmpty) {
                _translateAnnotationStrokes(
                  result.annotationIds.toSet(),
                  result.delta,
                );
              }
              _consumePendingStrokeTranslations(doc);
            }

          case 'layoutModeChanged':
            final modeName = payload['layoutMode'] as String?;
            if (modeName != null) {
              final mode = PdfLayoutMode.values.firstWhere(
                (m) => m.name == modeName,
                orElse: () => PdfLayoutMode.grid,
              );
              doc.documentModel = doc.documentModel.copyWith(layoutMode: mode);
              doc.performGridLayout();
              doc.invalidateBoundsCache();
              // 📄 Consume pending stroke translations from layout change
              _consumePendingStrokeTranslations(doc);
            }

          default:
        }
      } finally {
        // 🛡️ Always restore callback, even if an exception occurred
        doc.onMutation = savedCallback;
      }

      // 🎨 Invalidate tile cache so visual changes are rendered
      DrawingPainter.invalidateAllTiles();

      // Refresh UI
      if (mounted) setState(() {});
      _autoSaveCanvas();

    } catch (e) {
    }
  }

  /// 📄 Drain `pendingStrokeTranslations` from a [PdfDocumentNode] and apply
  /// each (delta, annotationIds) pair. Called after remote operations that
  /// trigger `performGridLayout()`.
  void _consumePendingStrokeTranslations(PdfDocumentNode doc) {
    if (doc.pendingStrokeTranslations.isEmpty) return;
    final translations = doc.pendingStrokeTranslations.toList();
    doc.pendingStrokeTranslations.clear();
    for (final t in translations) {
      if (t.annotationIds.isNotEmpty && t.delta != Offset.zero) {
        _translateAnnotationStrokes(t.annotationIds.toSet(), t.delta);
      }
    }
  }

  /// 🔄 Consume pending stroke rotation from [PdfDocumentNode.rotatePage].
  /// Rotates all linked annotation strokes around the page center.
  void _consumePendingStrokeRotation(PdfDocumentNode doc) {
    final rot = doc.pendingStrokeRotation;
    if (rot == null) return;
    doc.pendingStrokeRotation = null; // Consume

    if (rot.annotationIds.isEmpty) return;
    final idSet = Set<String>.of(rot.annotationIds);
    final cosA = math.cos(rot.angleRadians);
    final sinA = math.sin(rot.angleRadians);
    final cx = rot.center.dx;
    final cy = rot.center.dy;

    for (final layer in _layerController.layers) {
      for (final strokeNode in layer.node.strokeNodes) {
        if (idSet.contains(strokeNode.stroke.id)) {
          final old = strokeNode.stroke;
          final rotated =
              old.points.map((p) {
                final dx = p.position.dx - cx;
                final dy = p.position.dy - cy;
                return p.copyWith(
                  position: Offset(
                    cx + dx * cosA - dy * sinA,
                    cy + dx * sinA + dy * cosA,
                  ),
                );
              }).toList();
          strokeNode.stroke = old.copyWith(points: rotated);
        }
      }
    }
  }
}
