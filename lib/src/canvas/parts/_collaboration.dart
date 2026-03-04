part of '../fluera_canvas_screen.dart';

/// 📦 Collaboration & Sync — generic SDK implementation.
///
/// Checks permissions and presence via [FlueraCanvasConfig] providers.
/// Initializes the [FlueraRealtimeEngine] when a [FlueraRealtimeAdapter]
/// is provided, connecting remote events to canvas state and feeding
/// the cursor overlay.
extension CollaborationExtension on _FlueraCanvasScreenState {
  /// 🔄 Initialize collaboration features (permissions + presence + realtime).
  ///
  /// Checks if canvas is shared and sets viewer mode accordingly.
  /// Uses `_config.permissions` to check access, `_config.presence` for
  /// user presence, and `_config.realtimeAdapter` for live collaboration.
  Future<void> _initRealtimeCollaboration() async {
    final userId = await _config.getUserId();
    if (userId == null) return;

    try {
      // Check permissions via config provider
      if (_config.permissions != null) {
        final permissionCheckId = widget.infiniteCanvasId ?? _canvasId;
        final canEdit = await _config.permissions!.canEdit(permissionCheckId);

        if (mounted) {
          setState(() {
            _isSharedCanvas =
                true; // If permissions provider is set, canvas is shared
            _isViewerMode = !canEdit;
          });
        }
      }

      // Start presence tracking if configured
      if (_isSharedCanvas && _config.presence != null) {
        final permissionCheckId = widget.infiniteCanvasId ?? _canvasId;
        _config.presence!.joinCanvas(permissionCheckId);
      }

      // 🔴 Initialize real-time engine if adapter is available
      if (_hasRealtimeCollab && _config.realtimeAdapter != null) {
        _realtimeEngine = FlueraRealtimeEngine(
          adapter: _config.realtimeAdapter!,
          localUserId: userId,
          conflictResolver: ConflictResolver(
            onUnresolved: (conflict) {
              // Show conflict resolution dialog when auto-resolve fails
              if (mounted) {
                showConflictDialog(
                  context,
                  conflict,
                  resolver: _realtimeEngine?.conflictResolver,
                );
              }
            },
          ),
        );

        // Subscribe to incoming events
        _realtimeEventSub = _realtimeEngine!.incomingEvents.listen(
          _onRemoteRealtimeEvent,
        );

        // Connect cursor stream → CanvasPresenceOverlay ValueNotifier
        _realtimeEngine!.remoteCursors.addListener(_onRemoteCursorsChanged);

        // Connect to canvas channel
        await _realtimeEngine!.connect(_canvasId);

        // 🔄 #2 Auto-retry pending recording downloads on reconnect
        // 📡 #8 Auto-upload queued offline recordings
        _realtimeEngine!.connectionState.addListener(() {
          if (_realtimeEngine!.connectionState.value ==
              RealtimeConnectionState.connected) {
            _retryPendingRecordingDownloads();
            _syncOfflineUploads();
          }
        });

      }
    } catch (e) {
      // Non-blocking: collaboration features are optional
    }
  }

  // ─── Remote Event Dispatch ─────────────────────────────────────────

  /// Handle incoming real-time events from other collaborators.
  void _onRemoteRealtimeEvent(CanvasRealtimeEvent event) {
    if (!mounted) return;

    // 🚀 SELF-ECHO SUPPRESSION: Skip events originating from THIS device.
    // Firebase RTDB echoes all writes back to all listeners, including
    // the sender. Without this guard, every local stroke was fully
    // re-processed (deep cast + JSON deser + addStroke + invalidateAllTiles
    // + setState) — causing 50-100ms UI thread spikes with 300+ strokes.
    final isSelfEcho =
        _realtimeEngine != null &&
        event.senderId == _realtimeEngine!.localUserId;
    if (isSelfEcho) {
      // Only skip data-mutation events; UI-only events (cursor, presence)
      // are handled internally by the engine and don't reach here.
      switch (event.type) {
        case RealtimeEventType.strokeAdded:
        case RealtimeEventType.strokeRemoved:
        case RealtimeEventType.strokePointsStreamed:
        case RealtimeEventType.imageAdded:
        case RealtimeEventType.imageUpdated:
        case RealtimeEventType.imageRemoved:
        case RealtimeEventType.textChanged:
        case RealtimeEventType.textRemoved:
        case RealtimeEventType.layerChanged:
        case RealtimeEventType.canvasSettingsChanged:
        case RealtimeEventType.pdfAdded:
        case RealtimeEventType.pdfBlankCreated:
        case RealtimeEventType.pdfUpdated:
        case RealtimeEventType.pdfRemoved:
        case RealtimeEventType.pdfLoading:
        case RealtimeEventType.pdfProgress:
        case RealtimeEventType.pdfLoadingFailed:
        case RealtimeEventType.recordingAdded:
        case RealtimeEventType.recordingRemoved:
        case RealtimeEventType.recordingRenamed:
        case RealtimeEventType.recordingPinAdded:
        case RealtimeEventType.recordingPinRemoved:
          return; // Skip — already applied locally
        case RealtimeEventType.elementLocked:
        case RealtimeEventType.elementUnlocked:
          break; // Process normally (lock table needs sync)
      }
    }

    switch (event.type) {
      case RealtimeEventType.strokeAdded:
        _applyRemoteStroke(event.payload);
        // 🎨 Clear ALL live stroke previews when a final stroke arrives
        _remoteLiveStrokes.clear();
        _remoteLiveStrokeColors.clear();
        _remoteLiveStrokeWidths.clear();
        _remoteLiveStrokeTimestamps.clear();

        // 🐛 FIX: Suppress live points from this sender for 2s
        //    (late-arriving network packets would re-populate the cleared map)
        _suppressedLiveStrokeSenders[event.senderId] =
            DateTime.now().millisecondsSinceEpoch + 2000;

        setState(() {}); // Force repaint AFTER clearing live strokes
        break;

      case RealtimeEventType.strokeRemoved:
        _applyRemoteStrokeRemoval(event.payload);
        break;

      case RealtimeEventType.imageAdded:
      case RealtimeEventType.imageUpdated:
        _applyRemoteImageUpdate(event.payload);
        break;

      case RealtimeEventType.imageRemoved:
        _applyRemoteImageRemoval(event.payload);
        break;

      case RealtimeEventType.textChanged:
        _applyRemoteTextChange(event.payload);
        break;

      case RealtimeEventType.textRemoved:
        _applyRemoteTextRemoval(event.payload);
        break;

      case RealtimeEventType.layerChanged:
        _applyRemoteLayerChange(event.payload);
        break;

      case RealtimeEventType.canvasSettingsChanged:
        _applyRemoteSettingsChange(event.payload);
        break;

      case RealtimeEventType.elementLocked:
      case RealtimeEventType.elementUnlocked:
        // Handled internally by FlueraRealtimeEngine (lock table)
        break;

      case RealtimeEventType.strokePointsStreamed:
        // 🐛 FIX: Skip live points from senders who just finished a stroke
        final now = DateTime.now().millisecondsSinceEpoch;
        final suppressUntil = _suppressedLiveStrokeSenders[event.senderId] ?? 0;
        if (now < suppressUntil) {
          break; // Discard late-arriving live points
        }
        _suppressedLiveStrokeSenders.remove(event.senderId);
        _applyRemoteLiveStroke(event.payload);
        break;

      case RealtimeEventType.pdfLoading:
        _applyRemotePdfLoading(event.payload);
        break;

      case RealtimeEventType.pdfProgress:
        _applyRemotePdfProgress(event.payload);
        break;

      case RealtimeEventType.pdfLoadingFailed:
        _applyRemotePdfLoadingFailed(event.payload);
        break;

      case RealtimeEventType.pdfAdded:
        _applyRemotePdf(event.payload);
        break;

      case RealtimeEventType.pdfBlankCreated:
        _applyRemoteBlankPdf(event.payload);
        break;

      case RealtimeEventType.pdfUpdated:
        _applyRemotePdfUpdate(event.payload);
        break;

      case RealtimeEventType.pdfRemoved:
        _applyRemotePdfRemoved(event.payload);
        break;

      case RealtimeEventType.recordingAdded:
        _applyRemoteRecordingAdded(event.payload);
        break;

      case RealtimeEventType.recordingRemoved:
        _applyRemoteRecordingRemoved(event.payload);
        break;

      case RealtimeEventType.recordingRenamed:
        _applyRemoteRecordingRenamed(event.payload);
        break;

      case RealtimeEventType.recordingPinAdded:
        _applyRemoteRecordingPinAdded(event.payload);
        break;

      case RealtimeEventType.recordingPinRemoved:
        _applyRemoteRecordingPinRemoved(event.payload);
        break;
    }
  }

  // ─── Remote Event Handlers ─────────────────────────────────────────

  void _applyRemoteStroke(Map<String, dynamic> payload) {
    try {
      // Firebase RTDB returns Map<Object?, Object?> — deep cast needed
      final safePayload = _deepCastMap(payload);
      final stroke = ProStroke.fromJson(safePayload);
      // Disable delta tracking during remote apply to avoid re-broadcasting
      final wasTracking = _layerController.enableDeltaTracking;
      _layerController.enableDeltaTracking = false;
      _layerController.addStroke(stroke);
      _layerController.enableDeltaTracking = wasTracking;

      // 📄 Link stroke to overlapping PDF page (same as local draw pipeline)
      _linkStrokeToPdfPage(stroke);

      // 🚀 PERF #6: Invalidate only tiles overlapping this stroke's bounds
      // instead of ALL tiles. With 300+ strokes spread across many tiles,
      // invalidateAllTiles() repaints everything; this repaints only ~1-4 tiles.
      DrawingPainter.invalidateTilesForStroke(stroke);
      // 🖼️ Trigger ImagePainter repaint so strokes on images appear on top
      _imageVersion++;
      _imageRepaintNotifier.value++;
      // 🚀 PERF: setState() removed — redundant. DrawingPainter repaints via
      // ListenableBuilder(listenable: _layerController) when addStroke fires.
    } catch (e) {
    }
  }

  /// Deep-cast a Firebase RTDB map to Map<String, dynamic>
  static Map<String, dynamic> _deepCastMap(Map map) {
    return map.map((key, value) {
      final k = key.toString();
      if (value is Map) {
        return MapEntry(k, _deepCastMap(value));
      } else if (value is List) {
        return MapEntry(k, _deepCastList(value));
      }
      return MapEntry(k, value);
    });
  }

  static List<dynamic> _deepCastList(List list) {
    return list.map((item) {
      if (item is Map) return _deepCastMap(item);
      if (item is List) return _deepCastList(item);
      return item;
    }).toList();
  }

  void _applyRemoteStrokeRemoval(Map<String, dynamic> payload) {
    try {
      final strokeId = payload['strokeId'] as String?;
      if (strokeId == null) return;

      // 🚀 PERF #6: Capture stroke bounds BEFORE removal for selective
      // tile invalidation (stroke won't exist after removeStroke).
      Rect? strokeBounds;
      final activeLayer = _layerController.activeLayer;
      if (activeLayer != null) {
        for (final s in activeLayer.strokes) {
          if (s.id == strokeId) {
            strokeBounds = s.bounds;
            break;
          }
        }
      }

      final wasTracking = _layerController.enableDeltaTracking;
      _layerController.enableDeltaTracking = false;
      _layerController.removeStroke(strokeId);
      _layerController.enableDeltaTracking = wasTracking;

      // Invalidate only affected tiles (or all if bounds unknown)
      if (strokeBounds != null) {
        DrawingPainter.invalidateTilesInBounds(strokeBounds);
      } else {
        DrawingPainter.invalidateAllTiles();
      }
      _imageVersion++;
      _imageRepaintNotifier.value++;
      // 🚀 PERF: setState() removed — redundant. DrawingPainter repaints via
      // ListenableBuilder(listenable: _layerController) when removeStroke fires.
    } catch (e) {
    }
  }

  void _applyRemoteImageUpdate(Map<String, dynamic> payload) {
    try {
      // 🔧 Firebase RTDB returns Map<Object?, Object?> — deep-cast to
      // Map<String, dynamic> so ImageElement.fromJson type casts succeed
      // (especially nested maps like position, drawingStrokes, etc.)
      final safePayload = _deepCastMap(payload);
      final image = ImageElement.fromJson(safePayload);
      final wasTracking = _layerController.enableDeltaTracking;
      _layerController.enableDeltaTracking = false;

      // 🔧 Use updateImage for existing images to avoid duplicate child
      // assertion; addImage only for genuinely new images.
      final idx = _imageElements.indexWhere((e) => e.id == image.id);
      if (idx != -1) {
        _imageElements[idx] = image;
        _layerController.updateImage(image);
      } else {
        _imageElements.add(image);
        _layerController.addImage(image);
      }
      _layerController.enableDeltaTracking = wasTracking;

      _imageVersion++;
      _rebuildImageSpatialIndex();
      // 🐛 FIX #3: Only preload if image is NOT already in memory
      if (!_loadedImages.containsKey(image.imagePath)) {
        _preloadImage(
          image.imagePath,
          storageUrl: image.storageUrl,
          thumbnailUrl: image.thumbnailUrl,
        );
      }
      // 💾 Trigger auto-save so storageUrl persists to local storage
      _autoSaveCanvas();
      setState(() {});
    } catch (e) {
    }
  }

  void _applyRemoteImageRemoval(Map<String, dynamic> payload) {
    try {
      final imageId = payload['id'] as String?;
      if (imageId == null) return;
      // 🐛 FIX #1: Notify layer controller to keep layer data in sync
      final wasTracking = _layerController.enableDeltaTracking;
      _layerController.enableDeltaTracking = false;
      _layerController.removeImage(imageId);
      _layerController.enableDeltaTracking = wasTracking;

      // 🐛 FIX E: Clean up memory manager + dispose loaded texture
      final removed = _imageElements.where((e) => e.id == imageId).toList();
      for (final img in removed) {
        _imageMemoryManager.remove(img.imagePath);
        _loadedImages.remove(img.imagePath)?.dispose();
      }
      _imageElements.removeWhere((e) => e.id == imageId);
      _imageVersion++;
      _rebuildImageSpatialIndex();
      // 💾 Auto-save to persist removal
      _autoSaveCanvas();
      setState(() {});
    } catch (e) {
    }
  }

  void _applyRemoteTextChange(Map<String, dynamic> payload) {
    try {
      final text = DigitalTextElement.fromJson(payload);
      final idx = _digitalTextElements.indexWhere((e) => e.id == text.id);
      setState(() {
        if (idx != -1) {
          _digitalTextElements[idx] = text;
        } else {
          _digitalTextElements.add(text);
        }
      });
      final wasTracking = _layerController.enableDeltaTracking;
      _layerController.enableDeltaTracking = false;
      _layerController.updateText(text);
      _layerController.enableDeltaTracking = wasTracking;
      // 🐛 FIX #4: Auto-save so remote text persists across restart
      _autoSaveCanvas();
    } catch (e) {
    }
  }

  void _applyRemoteTextRemoval(Map<String, dynamic> payload) {
    try {
      final textId = payload['id'] as String?;
      if (textId == null) return;
      // 🐛 FIX: Notify layer controller (same pattern as image removal)
      final wasTracking = _layerController.enableDeltaTracking;
      _layerController.enableDeltaTracking = false;
      _layerController.removeText(textId);
      _layerController.enableDeltaTracking = wasTracking;

      setState(() {
        _digitalTextElements.removeWhere((e) => e.id == textId);
      });
      // 💾 Auto-save to persist removal
      _autoSaveCanvas();
    } catch (e) {
    }
  }

  void _applyRemoteLayerChange(Map<String, dynamic> payload) {
    try {
      final layer = CanvasLayer.fromJson(payload);
      final wasTracking = _layerController.enableDeltaTracking;
      _layerController.enableDeltaTracking = false;
      // Replace matching layer in the current layer list
      final updatedLayers =
          _layerController.layers.map((existing) {
            return existing.id == layer.id ? layer : existing;
          }).toList();
      _layerController.clearAllAndLoadLayers(updatedLayers);
      _layerController.enableDeltaTracking = wasTracking;
      setState(() {});
    } catch (e) {
    }
  }

  void _applyRemoteSettingsChange(Map<String, dynamic> payload) {
    try {
      setState(() {
        final bgColor = payload['backgroundColor'];
        if (bgColor != null) {
          _canvasBackgroundColor = Color(bgColor as int);
        }
        final paperType = payload['paperType'] as String?;
        if (paperType != null) {
          _paperType = paperType;
        }
      });
    } catch (e) {
    }
  }

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
    _pdfLoadingTimeouts[docId]?.cancel();

    _pdfLoadingPlaceholders[docId] = _PdfLoadingPlaceholder(
      documentId: docId,
      fileName: fileName,
      pageCount: pageCount,
      pageWidth: pageWidth,
      pageHeight: pageHeight,
      position: Offset(posX, posY),
      thumbnailBase64: thumbnailBase64,
    );

    // ⏰ Auto-remove after 60s (safety net if sender goes offline)
    _pdfLoadingTimeouts[docId] = Timer(const Duration(seconds: 60), () {
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
    final placeholder = _pdfLoadingPlaceholders[docId];
    if (placeholder != null) {
      _pdfLoadingPlaceholders[docId] = placeholder.copyWith(progress: progress);
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

  // ─── Live Stroke Streaming ─────────────────────────────────────────

  /// 🎨 In-progress strokes from remote collaborators.
  /// Key: strokeId, Value: list of (x, y) points.
  static final Map<String, List<Offset>> _remoteLiveStrokes = {};
  static final Map<String, int> _remoteLiveStrokeColors = {};
  static final Map<String, double> _remoteLiveStrokeWidths = {};

  /// 🐛 FIX: Suppress live stroke points from senders who just finalized.
  /// Key: senderId, Value: suppress-until timestamp (ms since epoch).
  static final Map<String, int> _suppressedLiveStrokeSenders = {};

  // ─── PDF Loading Placeholders ──────────────────────────────────────

  /// 📄 PDF documents that are being uploaded by a collaborator.
  /// Shown as loading placeholders until the real PDF data arrives.
  static final Map<String, _PdfLoadingPlaceholder> _pdfLoadingPlaceholders = {};
  static final Map<String, Timer> _pdfLoadingTimeouts = {};

  /// Get current PDF loading placeholders for rendering.
  static Map<String, _PdfLoadingPlaceholder> get pdfLoadingPlaceholders =>
      _pdfLoadingPlaceholders;

  /// 🔄 Stop loading pulse if no more placeholders are pending.
  void _stopPdfPlaceholderPulseIfDone() {
    if (_pdfLoadingPlaceholders.isEmpty) {
      _stopLoadingPulseIfDone();
    }
  }

  /// 🧹 Centralized placeholder cleanup: removes state, timeout, pulse, and thumbnail cache.
  void _cleanupPlaceholder(String docId) {
    _pdfLoadingPlaceholders.remove(docId);
    _pdfLoadingTimeouts[docId]?.cancel();
    _pdfLoadingTimeouts.remove(docId);
    _stopPdfPlaceholderPulseIfDone();
    // 🧹 Cleanup decoded thumbnail from painter cache
    _PdfLoadingPlaceholderPainter._decodedThumbnails.remove(docId);
    _PdfLoadingPlaceholderPainter._thumbnailDecodeRequested.remove(docId);
    _PdfLoadingPlaceholderPainter._animatedProgress.remove(docId);
  }

  /// 🐛 FIX: Timestamp each live stroke for stale cleanup.
  static final Map<String, int> _remoteLiveStrokeTimestamps = {};

  void _applyRemoteLiveStroke(Map<String, dynamic> payload) {
    try {
      final strokeId = payload['strokeId'] as String?;
      if (strokeId == null) return;

      final points = payload['points'] as List?;
      if (points == null || points.isEmpty) return;

      final color = payload['color'] as int? ?? 0xFF000000;
      final strokeWidth = (payload['strokeWidth'] as num?)?.toDouble() ?? 2.0;

      _remoteLiveStrokes.putIfAbsent(strokeId, () => []);
      for (final pt in points) {
        // Firebase RTDB returns Map<Object?, Object?> — safe cast
        final map = Map<String, dynamic>.from(pt as Map);
        _remoteLiveStrokes[strokeId]!.add(
          Offset((map['x'] as num).toDouble(), (map['y'] as num).toDouble()),
        );
      }
      _remoteLiveStrokeColors[strokeId] = color;
      _remoteLiveStrokeWidths[strokeId] = strokeWidth;
      _remoteLiveStrokeTimestamps[strokeId] =
          DateTime.now().millisecondsSinceEpoch;

      // 🐛 FIX: Clean stale live strokes (>5s old — strokeAdded was lost)
      _cleanStaleLiveStrokes();

      setState(() {}); // Trigger repaint
    } catch (e) {
    }
  }

  /// 🐛 FIX: Remove live strokes that are older than 5 seconds.
  /// This catches cases where the strokeAdded event was lost or delayed.
  void _cleanStaleLiveStrokes() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final staleIds = <String>[];
    for (final entry in _remoteLiveStrokeTimestamps.entries) {
      if (now - entry.value > 5000) {
        staleIds.add(entry.key);
      }
    }
    for (final id in staleIds) {
      _remoteLiveStrokes.remove(id);
      _remoteLiveStrokeColors.remove(id);
      _remoteLiveStrokeWidths.remove(id);
      _remoteLiveStrokeTimestamps.remove(id);
    }
    if (staleIds.isNotEmpty) {
    }
  }

  /// Clear a live stroke when the final strokeAdded event arrives.
  void _clearRemoteLiveStroke(String strokeId) {
    _remoteLiveStrokes.remove(strokeId);
    _remoteLiveStrokeColors.remove(strokeId);
    _remoteLiveStrokeWidths.remove(strokeId);
  }

  /// Get current live strokes for rendering.
  static Map<String, List<Offset>> get remoteLiveStrokes => _remoteLiveStrokes;
  static Map<String, int> get remoteLiveStrokeColors => _remoteLiveStrokeColors;
  static Map<String, double> get remoteLiveStrokeWidths =>
      _remoteLiveStrokeWidths;

  // ─── Follow Mode ──────────────────────────────────────────────────

  /// ID of the user we're following (static map: extensions can't have fields).
  static final Map<int, String?> _followingUserIds = {};

  /// Start following a user's viewport.
  void _startFollowing(String userId) {
    _followingUserIds[hashCode] = userId;
    setState(() {});
  }

  /// Stop following.
  void _stopFollowing() {
    _followingUserIds.remove(hashCode);
    setState(() {});
  }

  /// Called when remote cursors change — apply follow mode viewport.
  void _onRemoteCursorsChanged() {
    final followingId = _followingUserIds[hashCode];
    if (followingId == null || _realtimeEngine == null) return;

    final cursors = _realtimeEngine!.remoteCursors.value;
    final followed = cursors[followingId];
    if (followed == null) {
      _stopFollowing();
      return;
    }

    // Follow mode: log viewport data for host app to handle.
    // The host app can subscribe to connectionState or a follow-mode callback.
    final vx = followed['vx'] as num?;
    final vy = followed['vy'] as num?;
    final vs = followed['vs'] as num?;
    if (vx != null && vy != null && vs != null) {
    }
  }

  // ─── Typing Indicator ─────────────────────────────────────────────

  // ─── Viewer Guard ──────────────────────────────────────────────────

  /// 🔒 Viewer guard — blocks editing and shows toast if viewer.
  /// Returns true if editing should be blocked.
  bool _checkViewerGuard() {
    if (!_isSharedCanvas || !_isViewerMode) return false;
    HapticFeedback.heavyImpact();
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.visibility, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text('View-only mode — you can\'t edit this canvas'),
          ],
        ),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return true;
  }

  /// 🔒 Get the currently-active element ID for locking broadcast.
  String? _getActiveElementId() {
    if (_lassoTool.hasSelection) {
      return _lassoTool.selectedIds.first;
    }
    if (_digitalTextTool.hasSelection) {
      return _digitalTextTool.selectedElement?.id;
    }
    return null;
  }

  // ─── Broadcast Helpers (called from drawing handlers) ──────────────

  /// Broadcast cursor position during drawing (throttled by engine).
  void _broadcastCursorPosition(
    Offset canvasPosition, {
    bool isDrawing = false,
    bool isTyping = false,
    bool isRecording = false,
    bool isListening = false,
  }) {
    if (_realtimeEngine == null) return;

    _realtimeEngine!.updateCursor(
      CursorPresenceData(
        userId: '', // Set by engine
        displayName: '', // Set by engine
        cursorColor: 0xFF42A5F5,
        x: canvasPosition.dx,
        y: canvasPosition.dy,
        isDrawing: isDrawing,
        isTyping: isTyping,
        isRecording: isRecording,
        isListening: isListening,
        penType: _effectivePenType.name,
        penColor: _effectiveColor.toARGB32(),
      ),
    );
  }

  /// Broadcast a completed stroke to all collaborators.
  void _broadcastStrokeAdded(ProStroke stroke) {
    _realtimeEngine?.broadcastStroke(stroke.toJson());
  }

  /// Broadcast a stroke removal to all collaborators.
  void _broadcastStrokeRemoved(String strokeId) {
    _realtimeEngine?.broadcastStrokeRemoved(strokeId);
  }

  /// Broadcast an image update to all collaborators.
  void _broadcastImageUpdate(ImageElement image, {bool isNew = false}) {
    _realtimeEngine?.broadcastImageUpdate(image.toJson(), isNew: isNew);
  }

  /// Broadcast an image removal to all collaborators.
  void _broadcastImageRemoved(String imageId) {
    _realtimeEngine?.broadcastImageRemoved(imageId);
  }

  /// Broadcast a text change to all collaborators.
  void _broadcastTextChange(DigitalTextElement text) {
    _realtimeEngine?.broadcastTextChange(text.toJson());
  }

  /// ⌨️ Broadcast typing state to show "typing..." on remote cursors.
  void _broadcastTypingState(bool isTyping, Offset position) {
    _broadcastCursorPosition(position, isTyping: isTyping);
  }

  /// 🎨 Stream stroke points during active drawing.
  void _broadcastStrokePoints({
    required String strokeId,
    required List<Map<String, dynamic>> newPoints,
    required String penType,
    required int color,
    double? strokeWidth,
  }) {
    _realtimeEngine?.streamStrokePoints(
      strokeId: strokeId,
      newPoints: newPoints,
      penType: penType,
      color: color,
      strokeWidth: strokeWidth,
    );
  }

  // ─── Cleanup ───────────────────────────────────────────────────────

  /// Disconnect and dispose real-time engine.
  Future<void> _disposeRealtimeCollaboration() async {
    _realtimeEventSub?.cancel();
    _realtimeEventSub = null;
    _realtimeEngine?.remoteCursors.removeListener(_onRemoteCursorsChanged);
    await _realtimeEngine?.disconnect();
    _realtimeEngine?.dispose();
    _realtimeEngine = null;
  }

  // ─── Recording Sync ────────────────────────────────────────────────

  /// 🎤 Apply a remotely-added voice recording.
  ///
  /// Downloads the audio file from cloud storage, persists it locally,
  /// and adds it to the recordings list.
  ///
  /// Improvements:
  ///   #2 — Download placeholder SnackBar with progress
  ///   #3 — Gzip decompression (if compressed flag is set)
  ///   #4 — Deduplication (skip if already downloaded)
  ///   #7 — Author name in notification
  void _applyRemoteRecordingAdded(Map<String, dynamic> payload) async {
    try {
      final recordingId = payload['recordingId'] as String?;
      final audioAssetKey = payload['audioAssetKey'] as String?;
      final noteTitle = payload['noteTitle'] as String?;
      final durationMs = (payload['durationMs'] as num?)?.toInt() ?? 0;
      final recordingType = payload['recordingType'] as String? ?? 'audio_only';
      final senderName = payload['senderName'] as String?;
      final isCompressed = payload['compressed'] as bool? ?? false;
      final fileSize = (payload['fileSize'] as num?)?.toInt();
      final waveform =
          (payload['waveform'] as List?)
              ?.cast<num>()
              .map((e) => e.toDouble())
              .toList();

      if (recordingId == null || audioAssetKey == null) return;

      // 🔒 #3 Validation — sanitize IDs to prevent path traversal / injection
      final idPattern = RegExp(r'^[a-zA-Z0-9_\-]+$');
      if (!idPattern.hasMatch(recordingId) ||
          !idPattern.hasMatch(audioAssetKey)) {
        return;
      }
      if (recordingId.length > 128 || audioAssetKey.length > 256) {
        return;
      }

      // 🔄 #4 Deduplication — skip if recording already exists locally
      final existingPath = _savedRecordings.where(
        (p) => p.contains('fluera_recording_$recordingId'),
      );
      if (existingPath.isNotEmpty) {
        return;
      }

      // 📥 #2 Show download placeholder notification
      final authorLabel = senderName ?? 'A collaborator';
      final titleLabel = noteTitle ?? 'recording';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '🎤 Downloading "$titleLabel" from $authorLabel'
                    '${fileSize != null ? ' (${(fileSize / 1024).toStringAsFixed(0)} KB)' : ''}...',
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 10),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

      // ⚡ Launch strokes download in parallel with audio (fire-and-forget Future)
      final strokesAssetKey = payload['strokesAssetKey'] as String?;
      Future<List<SyncedStroke>>? strokesFuture;
      if (strokesAssetKey != null && _syncEngine != null) {
        strokesFuture = _downloadSyncedStrokes(strokesAssetKey);
      }

      // Download audio bytes from cloud (#1 chunked, #3 exponential backoff, #8 progress)
      Uint8List? audioBytes;
      if (_syncEngine != null) {
        for (int attempt = 1; attempt <= 3; attempt++) {
          try {
            // #8 Show download progress
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('📥 Download attempt $attempt/3...'),
                  duration: const Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }

            audioBytes = await _syncEngine!.adapter.downloadAsset(
              _canvasId,
              audioAssetKey,
            );

            // #1 Chunked download — check if response is a manifest
            if (audioBytes != null && audioBytes.isNotEmpty) {
              try {
                final manifestStr = String.fromCharCodes(audioBytes);
                if (manifestStr.startsWith('{"chunks":')) {
                  final manifestJson = Map<String, dynamic>.from(
                    json.decode(manifestStr) as Map,
                  );
                  final totalChunks = manifestJson['chunks'] as int;

                  // Download and reassemble all chunks
                  final chunks = <Uint8List>[];
                  for (int i = 0; i < totalChunks; i++) {
                    final chunkKey = '${audioAssetKey}_chunk_$i';
                    final chunkData = await _syncEngine!.adapter.downloadAsset(
                      _canvasId,
                      chunkKey,
                    );
                    if (chunkData != null && chunkData.isNotEmpty) {
                      chunks.add(chunkData);
                    }
                  }

                  // Concatenate chunks into final audio
                  if (chunks.isNotEmpty) {
                    final totalSize = chunks.fold<int>(
                      0,
                      (sum, c) => sum + c.length,
                    );
                    final assembled = Uint8List(totalSize);
                    int offset = 0;
                    for (final chunk in chunks) {
                      assembled.setRange(offset, offset + chunk.length, chunk);
                      offset += chunk.length;
                    }
                    audioBytes = assembled;
                  }
                }
              } catch (_) {
                // Not a manifest — treat as normal audio data
              }
            }

            if (audioBytes != null && audioBytes.isNotEmpty) break;
          } catch (e) {
            if (attempt < 3) {
              // #3 Exponential backoff: 1s, 2s, 4s
              final delay = Duration(seconds: 1 << (attempt - 1));
              await Future<void>.delayed(delay);
            }
          }
        }
      }

      if (audioBytes == null || audioBytes.isEmpty) {
        _pendingRecordingRetries.add(payload);
        return;
      }

      // Non-null from here on
      Uint8List finalBytes = audioBytes;

      // 🗄️ #3 Decompress gzip if sender flagged it as compressed
      //    #6 Offload to Isolate for non-blocking main thread
      if (isCompressed) {
        try {
          finalBytes = await Isolate.run(() {
            return Uint8List.fromList(GZipCodec().decode(finalBytes));
          });
        } catch (e) {
          // Fallback: use bytes as-is (might not be compressed)
        }
      }

      // 📊 #6 Log received waveform preview if present
      if (waveform != null && waveform.isNotEmpty) {
      }

      // Persist audio to local documents directory
      final docsDir = await getSafeDocumentsDirectory();
      if (docsDir == null) return;

      final recordingsDir = Directory('${docsDir.path}/recordings');
      if (!await recordingsDir.exists()) {
        await recordingsDir.create(recursive: true);
      }

      final localPath =
          '${recordingsDir.path}/fluera_recording_$recordingId.m4a';
      await File(localPath).writeAsBytes(finalBytes, flush: true);

      // Save to SQLite
      if (RecordingStorageService.instance.isInitialized) {
        // ⚡ Await strokes (likely already finished while audio was downloading)
        final syncedStrokes = await strokesFuture ?? const <SyncedStroke>[];

        final persistable = SynchronizedRecording(
          id: recordingId,
          audioPath: localPath,
          totalDuration: Duration(milliseconds: durationMs),
          startTime: DateTime.now(),
          syncedStrokes: syncedStrokes,
          canvasId: _canvasId,
          noteTitle: noteTitle,
          recordingType: recordingType,
        );
        await RecordingStorageService.instance.saveRecording(persistable);
      }

      // Add to UI
      if (mounted) {
        // Clear the download SnackBar
        ScaffoldMessenger.of(context).hideCurrentSnackBar();

        setState(() {
          if (!_savedRecordings.contains(localPath)) {
            _savedRecordings.add(localPath);
          }
        });

        // 👤 #7 Show author name in confirmation
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🎤 "$titleLabel" received from $authorLabel'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }


      // 📳 Haptic feedback
      HapticFeedback.lightImpact();

      // 🔔 #1 Increment badge counter for new recordings
      _newRecordingCount++;
    } catch (e) {
    }
  }

  /// 🎤 Handle remote recording removal.
  void _applyRemoteRecordingRemoved(Map<String, dynamic> payload) {
    try {
      final recordingId = payload['recordingId'] as String?;
      if (recordingId == null) return;

      // Find the recording by ID in synced recordings
      final matchIndex = _savedRecordings.indexWhere(
        (path) => path.contains('fluera_recording_$recordingId'),
      );

      if (matchIndex != -1) {
        final removedPath = _savedRecordings[matchIndex];
        setState(() {
          _savedRecordings.removeAt(matchIndex);
        });
        _syncedRecordings.removeWhere((r) => r.id == recordingId);

        // Delete from SQLite
        if (RecordingStorageService.instance.isInitialized) {
          RecordingStorageService.instance
              .deleteRecording(recordingId)
              .catchError((_) => 0);
        }

        // 🧹 Clean up cloud assets (audio + strokes)
        _syncEngine?.adapter
            .deleteAsset(_canvasId, 'recording_$recordingId')
            .catchError((_) {});
        _syncEngine?.adapter
            .deleteAsset(_canvasId, 'strokes_$recordingId')
            .catchError((_) {});

        // Delete local file
        File(removedPath).delete().catchError((_) => File(removedPath));
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('🎤 A collaborator removed a recording'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

    } catch (e) {
    }
  }

  /// 🎤 Handle remote recording rename (#4).
  void _applyRemoteRecordingRenamed(Map<String, dynamic> payload) {
    try {
      final recordingId = payload['recordingId'] as String?;
      final newTitle = payload['newTitle'] as String?;
      if (recordingId == null || newTitle == null) return;

      // Update in synced recordings
      final idx = _syncedRecordings.indexWhere((r) => r.id == recordingId);
      if (idx != -1) {
        // Update the recording's noteTitle
        final old = _syncedRecordings[idx];
        _syncedRecordings[idx] = SynchronizedRecording(
          id: old.id,
          audioPath: old.audioPath,
          totalDuration: old.totalDuration,
          startTime: old.startTime,
          syncedStrokes: old.syncedStrokes,
          canvasId: old.canvasId,
          noteTitle: newTitle,
          recordingType: old.recordingType,
        );

        // Persist rename to SQLite
        if (RecordingStorageService.instance.isInitialized) {
          RecordingStorageService.instance
              .saveRecording(_syncedRecordings[idx])
              .catchError((_) => null);
        }
      }

      if (mounted) {
        setState(() {}); // Refresh UI
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🎤 Recording renamed to "$newTitle"'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

    } catch (e) {
    }
  }

  // ─── Recording Pin Remote Handlers ──────────────────────────────────

  /// 📌 Apply a remote recording pin addition.
  void _applyRemoteRecordingPinAdded(Map<String, dynamic> payload) {
    try {
      final safePayload = _deepCastMap(payload);
      final pin = RecordingPin.fromJson(safePayload);

      // Avoid duplicates
      if (_recordingPins.any((p) => p.id == pin.id)) return;

      if (mounted) {
        setState(() {
          _recordingPins.add(pin);
        });
      }

    } catch (e) {
    }
  }

  /// 📌 Apply a remote recording pin removal.
  void _applyRemoteRecordingPinRemoved(Map<String, dynamic> payload) {
    try {
      final pinId = payload['id'] as String?;
      if (pinId == null) return;

      if (mounted) {
        setState(() {
          _recordingPins.removeWhere((p) => p.id == pinId);
        });
      }

    } catch (e) {
    }
  }

  /// 📌 Broadcast a recording pin addition to collaborators.
  void _broadcastPinAdded(RecordingPin pin) {
    _realtimeEngine?.broadcastRecordingPinAdded(pin.toJson());
  }

  /// 📌 Broadcast a recording pin removal to collaborators.
  void _broadcastPinRemoved(String pinId) {
    _realtimeEngine?.broadcastRecordingPinRemoved(pinId);
  }

  // ─── Recording Retry Queue (#5) ─────────────────────────────────────

  /// 🔄 Queue of failed recording downloads to retry on reconnect.
  /// 🔄 Queue of failed recording downloads to retry on reconnect.
  static final List<Map<String, dynamic>> _pendingRecordingRetries = [];

  /// 🔔 Badge counter for new recordings received from collaborators (#1).
  static int _newRecordingCount = 0;

  /// 🎨 Download and decompress synced strokes from cloud asset.
  /// Returns empty list on failure (graceful fallback to audio-only).
  Future<List<SyncedStroke>> _downloadSyncedStrokes(String assetKey) async {
    try {
      final bytes = await _syncEngine!.adapter.downloadAsset(
        _canvasId,
        assetKey,
      );
      if (bytes == null || bytes.isEmpty) return const [];

      // Decompress + parse in Isolate (non-blocking)
      final parsed = await Isolate.run(() {
        final decompressed = GZipCodec().decode(bytes);
        final jsonStr = utf8.decode(decompressed);
        return jsonDecode(jsonStr) as List;
      });

      final strokes = <SyncedStroke>[];
      for (final raw in parsed) {
        strokes.add(
          SyncedStroke.fromJson(Map<String, dynamic>.from(raw as Map)),
        );
      }
      return strokes;
    } catch (e) {
      return const [];
    }
  }

  /// 🔄 Retry all pending recording downloads with exponential backoff (#3).
  Future<void> _retryPendingRecordingDownloads() async {
    if (_pendingRecordingRetries.isEmpty) return;

    final pending = List<Map<String, dynamic>>.from(_pendingRecordingRetries);
    _pendingRecordingRetries.clear();

    for (int i = 0; i < pending.length; i++) {
      final payload = pending[i];
      // #3 Exponential backoff between retries: 500ms, 1s, 2s, 4s...
      if (i > 0) {
        final delay = Duration(milliseconds: 500 * (1 << i.clamp(0, 4)));
        await Future<void>.delayed(delay);
      }
      _applyRemoteRecordingAdded(payload);
    }
  }
}

/// 📄 Data class for a PDF loading placeholder shown on remote devices.
class _PdfLoadingPlaceholder {
  final String documentId;
  final String? fileName;
  final int pageCount;
  final double pageWidth;
  final double pageHeight;
  final Offset position;
  final double progress; // 0.0 - 1.0
  final DateTime createdAt;
  final String? thumbnailBase64;

  _PdfLoadingPlaceholder({
    required this.documentId,
    this.fileName,
    required this.pageCount,
    required this.pageWidth,
    required this.pageHeight,
    required this.position,
    this.progress = 0.0,
    this.thumbnailBase64,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Create a copy with updated progress.
  _PdfLoadingPlaceholder copyWith({double? progress}) {
    return _PdfLoadingPlaceholder(
      documentId: documentId,
      fileName: fileName,
      pageCount: pageCount,
      pageWidth: pageWidth,
      pageHeight: pageHeight,
      position: position,
      progress: progress ?? this.progress,
      thumbnailBase64: thumbnailBase64,
      createdAt: createdAt,
    );
  }

  /// Total height of the placeholder (all pages stacked vertically with spacing).
  double get totalHeight => pageCount * pageHeight + (pageCount - 1) * 20;

  /// Bounding rect in canvas coordinates.
  Rect get rect =>
      Rect.fromLTWH(position.dx, position.dy, pageWidth, totalHeight);
}
