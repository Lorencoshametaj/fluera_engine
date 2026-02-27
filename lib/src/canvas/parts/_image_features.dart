part of '../fluera_canvas_screen.dart';

/// 📦 Image Features — extracted from _FlueraCanvasScreenState
extension on _FlueraCanvasScreenState {
  /// 🖼️ Pick an image from gallery and add it to the canvas.
  ///
  /// **Optimized sync flow:**
  /// - Single file read (bytes used for both decode and upload)
  /// - Non-blocking upload (image appears instantly, cloud sync in background)
  /// - Upload progress tracking via onProgress callback
  /// - Retry with backoff (3 attempts)
  Future<void> pickAndAddImage() async {
    // 🔒 VIEWER GUARD
    if (_checkViewerGuard()) return;

    try {
      // Seleziona immagine from the galleria
      final imagePath = await ImageService.pickImageFromGallery(context);

      if (imagePath == null) return; // Utente ha annullato

      // 🚀 FIX #2: Read bytes ONCE — used for both decode and upload
      final imageBytes = await ImageMemoryManager.readFileOnIsolate(imagePath);
      if (imageBytes == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error loading image'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Decode image from the already-read bytes
      final image = await _decodeImageCapped(imageBytes);
      if (image == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error decoding image'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // 💾 Cache compressed bytes for instant reload after eviction
      _imageMemoryManager.cacheCompressedBytes(imagePath, imageBytes);

      // Calculate position centrale of the viewport in canvas coordinates
      final screenCenter = Offset(
        MediaQuery.of(context).size.width / 2,
        MediaQuery.of(context).size.height / 2,
      );
      final viewportCenter = _canvasController.screenToCanvas(screenCenter);

      // 📏 Calculate initial scale to have reasonable size on screen.
      final screenWidth = MediaQuery.of(context).size.width;
      final targetScreenWidth = screenWidth * 0.45;
      final imageWidth = image.width.toDouble();
      final canvasZoom = _canvasController.scale;
      double initialScale = (targetScreenWidth / canvasZoom) / imageWidth;
      initialScale = initialScale.clamp(0.05, 3.0);

      final imageId = generateUid();

      // Create image element IMMEDIATELY (no blocking on upload)
      final newImage = ImageElement(
        id: imageId,
        imagePath: imagePath,
        storageUrl: null, // Will be updated after background upload
        thumbnailUrl: null,
        position: viewportCenter,
        scale: initialScale,
        rotation: 0.0,
        createdAt: DateTime.now(),
        pageIndex: 0,
      );

      setState(() {
        _imageElements.add(newImage);
        _loadedImages[imagePath] = image;
        _imageTool.selectImage(newImage);
        _imageVersion++;
        _rebuildImageSpatialIndex();
      });

      // 🔄 Sync: notify delta tracker for synchronization
      _layerController.addImage(newImage);

      // 💾 Auto-save locally (instant — before cloud upload)
      _autoSaveCanvas();

      HapticFeedback.mediumImpact();

      // 🚀 FIX #3: Non-blocking upload — runs in background after local add
      if (_syncEngine != null) {
        _uploadImageInBackground(
          imageId: imageId,
          imagePath: imagePath,
          imageBytes: imageBytes,
        );
      } else {
        // No cloud — just broadcast locally with no storageUrl
        _broadcastImageUpdate(newImage, isNew: true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 🚀 Upload image to cloud in background with retry, cancellation, and offline queue.
  ///
  /// Features:
  /// - **Cancellation**: checks `_pendingUploads` at each retry; if image is deleted, bails.
  /// - **Offline queue**: failed uploads queued in `_offlineUploadQueue` for later retry.
  /// - **MIME detection**: correct Content-Type from magic bytes.
  /// - **Resize**: caps at 4096px before upload.
  Future<void> _uploadImageInBackground({
    required String imageId,
    required String imagePath,
    required Uint8List imageBytes,
  }) async {
    // #7: Track pending upload for cancellation
    _pendingUploads.add(imageId);
    String? storageUrl;

    // 🔍 Detect actual MIME type (JPEG vs PNG vs WebP)
    final mimeType = ImageMemoryManager.detectMimeType(imageBytes);

    // 📐 Resize large images before upload (max 4096px)
    final uploadBytes = await ImageMemoryManager.resizeForUpload(imageBytes);

    // 🔄 Retry with exponential backoff (3 attempts)
    for (int attempt = 1; attempt <= 3; attempt++) {
      // #7: Check if image was deleted during upload
      if (!_pendingUploads.contains(imageId)) {
        debugPrint('[☁️ UPLOAD] 🛑 Cancelled (image deleted): $imageId');
        return;
      }

      try {
        storageUrl = await _syncEngine!.adapter.uploadAsset(
          _canvasId,
          imageId,
          uploadBytes,
          mimeType: mimeType,
          onProgress: (progress) {
            debugPrint('[☁️ UPLOAD] $imageId: ${(progress * 100).toInt()}%');
          },
        );
        debugPrint(
          '[☁️ UPLOAD] ✅ Success on attempt $attempt: $imageId ($mimeType, ${uploadBytes.length ~/ 1024}KB)',
        );
        break;
      } catch (e) {
        debugPrint('[☁️ UPLOAD] ❌ Attempt $attempt/3 failed: $e');
        if (attempt < 3) {
          await Future.delayed(Duration(seconds: attempt));
        }
      }
    }

    // #7: Remove from pending set
    _pendingUploads.remove(imageId);

    if (!mounted) return;

    if (storageUrl == null) {
      // #4: Queue for offline retry
      _offlineUploadQueue[imageId] = _OfflineUploadEntry(
        imageId: imageId,
        imagePath: imagePath,
        bytes: uploadBytes,
        mimeType: mimeType,
      );
      debugPrint(
        '[☁️ OFFLINE] Queued $imageId for retry (${_offlineUploadQueue.length} pending)',
      );
      return;
    }

    // Update the ImageElement with the storageUrl
    final idx = _imageElements.indexWhere((e) => e.id == imageId);
    if (idx != -1) {
      final updated = _imageElements[idx].copyWith(storageUrl: storageUrl);
      setState(() {
        _imageElements[idx] = updated;
      });
      _layerController.updateImage(updated);

      // 🔴 RT: Broadcast to collaborators WITH storageUrl
      _broadcastImageUpdate(updated, isNew: true);

      // 💾 Re-save with storageUrl
      _autoSaveCanvas();
    }

    // #4: Try draining offline queue on successful upload (connection is good)
    _drainOfflineUploadQueue();
  }

  /// #7: Set of image IDs currently being uploaded (for cancellation).
  static final Set<String> _pendingUploads = {};

  /// #4: Offline upload queue — failed uploads queued for retry.
  static final Map<String, _OfflineUploadEntry> _offlineUploadQueue = {};

  /// #4: Drain the offline retry queue (called after a successful upload).
  Future<void> _drainOfflineUploadQueue() async {
    if (_offlineUploadQueue.isEmpty || _syncEngine == null) return;

    final entries = Map.of(_offlineUploadQueue);
    _offlineUploadQueue.clear();
    debugPrint('[☁️ OFFLINE] Retrying ${entries.length} queued uploads');

    for (final entry in entries.values) {
      if (!mounted) break;
      // Check if image still exists on canvas
      if (!_imageElements.any((e) => e.id == entry.imageId)) {
        debugPrint('[☁️ OFFLINE] Skipped (deleted): ${entry.imageId}');
        continue;
      }
      await _uploadImageInBackground(
        imageId: entry.imageId,
        imagePath: entry.imagePath,
        imageBytes: entry.bytes,
      );
    }
  }

  /// 🎨 Apre editor professionale per modificare immagine (mantenuto per compatibility)
  void _openImageEditor(
    ImageElement imageElement,
    ui.Image image, {
    int initialTab = 0,
  }) {
    // Cancel timer
    _imageLongPressTimer?.cancel();
    _imageLongPressEditorTimer?.cancel();

    // 🎨 Prepara elemento with all gli strokes aggiornati
    ImageElement elementToEdit = imageElement;

    // Ferma drag se attivo
    if (_imageTool.isDragging) {
      _imageTool.endDrag();
    }

    // Feedback haptic
    HapticFeedback.mediumImpact();

    // #1: Acquire element lock for this image (prevents concurrent edits)
    final hasLock = _realtimeEngine?.lockElement(imageElement.id) ?? true;
    if (hasLock == false) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Image is being edited by another collaborator'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Open dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => ImageEditorDialog(
            imageElement: elementToEdit,
            image: image,
            initialTab: initialTab,
            onSave: (updated) {
              // Update element in the list
              final index = _imageElements.indexWhere(
                (e) => e.id == updated.id,
              );
              if (index != -1) {
                setState(() {
                  _imageElements[index] = updated;
                  _imageTool.selectImage(updated);
                  _imageVersion++;
                  _rebuildImageSpatialIndex();
                });

                // 🔄 Sync: notify delta tracker for synchronization
                _layerController.updateImage(updated);

                // 🔴 RT: Broadcast image changes to collaborators
                _broadcastImageUpdate(updated);

                // 💾 Auto-save after image modification
                _autoSaveCanvas();
              }
              HapticFeedback.lightImpact();
            },
            onDelete: () {
              // Use centralized removal with broadcast
              removeImage(imageElement.id);
            },
          ),
    ).then((_) {
      // #1: Release element lock when dialog closes
      _realtimeEngine?.unlockElement(imageElement.id);
    });
  }

  // ---------------------------------------------------------------------------
  // 🗑️ Image Removal — centralized cleanup with collaboration broadcast
  // ---------------------------------------------------------------------------

  /// 🗑️ Remove an image from the canvas.
  ///
  /// Cleans up: selection, spatial index, layer controller, and broadcasts
  /// to collaborators. Set [broadcast] to false for remote-triggered removals.
  void removeImage(String imageId, {bool broadcast = true}) {
    // #7: Cancel any pending upload for this image
    _pendingUploads.remove(imageId);
    _offlineUploadQueue.remove(imageId);

    // Clear selection if this image is selected
    if (_imageTool.selectedImage?.id == imageId) {
      _imageTool.clearSelection();
    }

    setState(() {
      _imageElements.removeWhere((e) => e.id == imageId);
      _imageVersion++;
      _rebuildImageSpatialIndex();
    });

    // 🔄 Sync: notify delta tracker
    _layerController.removeImage(imageId);

    // 🔴 RT: Broadcast removal to collaborators
    if (broadcast) {
      _broadcastImageRemoved(imageId);
    }

    // 💾 Auto-save
    _autoSaveCanvas();

    HapticFeedback.mediumImpact();
  }

  /// 🗑️ Show confirmation dialog before deleting an image.
  void showDeleteImageConfirmation(BuildContext context, String imageId) {
    final cs = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            backgroundColor: cs.surface,
            icon: Icon(Icons.delete_forever_rounded, color: cs.error, size: 36),
            title: Text(
              'Delete Image?',
              style: TextStyle(
                color: cs.onSurface,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
            content: Text(
              'This action cannot be undone. The image and all '
              'drawings on it will be permanently removed.',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(
                  'Cancel',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  removeImage(imageId);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: cs.error,
                  foregroundColor: cs.onError,
                ),
                child: const Text('Delete'),
              ),
            ],
          ),
    );
  }
}

/// #4: Data class for queued offline uploads.
class _OfflineUploadEntry {
  final String imageId;
  final String imagePath;
  final Uint8List bytes;
  final String mimeType;

  const _OfflineUploadEntry({
    required this.imageId,
    required this.imagePath,
    required this.bytes,
    required this.mimeType,
  });
}
