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
        return;
      }

      try {
        storageUrl = await _syncEngine!.adapter.uploadAsset(
          _canvasId,
          imageId,
          uploadBytes,
          mimeType: mimeType,
          onProgress: (progress) {},
        );
        break;
      } catch (e) {
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

    for (final entry in entries.values) {
      if (!mounted) break;
      // Check if image still exists on canvas
      if (!_imageElements.any((e) => e.id == entry.imageId)) {
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
    _imageStubManager.removeEntry(imageId);

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

  // ---------------------------------------------------------------------------
  // 🖼️ Image Zoom-to-Enter — immersive image viewer
  // ---------------------------------------------------------------------------

  /// Called continuously during canvas transform changes.
  void _onImageZoomCheck() {
    if (!mounted) return;
    if (_imageZoomEnterCooldown) return;
    if (_canvasController.scale > 0.8) {
      _checkImageZoomToEnter();
    }
  }

  /// Check if any image fills enough of the viewport to trigger immersive entry.
  void _checkImageZoomToEnter() {
    if (_imageZoomEnterCooldown) return;

    final scale = _canvasController.scale;
    if (scale < 0.8) return; // Too zoomed out

    final viewportSize = MediaQuery.sizeOf(context);
    final viewportCenter = Offset(viewportSize.width / 2, viewportSize.height / 2);

    ImageElement? bestImage;
    double bestCoverage = 0;
    ui.Image? bestDecodedImage;

    for (final img in _imageElements) {
      final decodedImg = _loadedImages[img.imagePath];
      if (decodedImg == null) continue;

      // Compute world bounds of the image (position = CENTER point)
      // 🐛 FIX: Use cached ORIGINAL dimensions (same as ImagePainter)
      // not decoded texture size (which may be a LOD thumbnail).
      final cachedSize = _imageMemoryManager.getImageDimensions(img.imagePath);
      final origW = cachedSize?.width ?? decodedImg.width.toDouble();
      final origH = cachedSize?.height ?? decodedImg.height.toDouble();
      // Account for crop
      final crop = img.cropRect;
      final visW = crop != null ? (crop.right - crop.left) * origW : origW;
      final visH = crop != null ? (crop.bottom - crop.top) * origH : origH;
      final imgW = visW * img.scale;
      final imgH = visH * img.scale;
      final worldRect = Rect.fromCenter(
        center: img.position,
        width: imgW,
        height: imgH,
      );

      // Convert to screen coordinates
      final screenTL = _canvasController.canvasToScreen(worldRect.topLeft);
      final screenBR = _canvasController.canvasToScreen(worldRect.bottomRight);
      final screenRect = Rect.fromPoints(screenTL, screenBR);

      // Coverage: how much of the viewport width does this image fill?
      final widthCoverage = screenRect.width / viewportSize.width;

      // Distance from center
      final imgCenter = screenRect.center;
      final centerDistance = (imgCenter - viewportCenter).distance;
      final maxDistance = viewportSize.width * 0.5;

      if (widthCoverage > bestCoverage && centerDistance < maxDistance) {
        bestCoverage = widthCoverage;
        bestImage = img;
        bestDecodedImage = decodedImg;
      }
    }

    // Trigger at >75% coverage: enter image viewer directly.
    // 🐛 FIX: Previously there was a snap-center step that animated the canvas
    // offset to center the image before the transition. This caused a visible
    // 90px downward scroll. The expanding-clip animation handles the visual
    // transition smoothly without needing pre-centering.
    if (bestImage != null && bestDecodedImage != null && bestCoverage > 0.65) {
      _imageZoomEnterCooldown = true;
      _enterImageViewerWithZoomAnimation(bestImage, bestDecodedImage);
    }
  }

  /// Open the image viewer with a cinematic zoom-dive animation.
  void _enterImageViewerWithZoomAnimation(
    ImageElement imageElement,
    ui.Image image,
  ) {
    _imageZoomEnterCooldown = true;

    // Capture image's current screen rect (position = CENTER)
    // 🐛 FIX: Use cached ORIGINAL dimensions (same as ImagePainter)
    // not decoded texture size (which may be a LOD thumbnail).
    final cachedSize = _imageMemoryManager.getImageDimensions(imageElement.imagePath);
    final origW = cachedSize?.width ?? image.width.toDouble();
    final origH = cachedSize?.height ?? image.height.toDouble();
    // Account for crop
    final crop = imageElement.cropRect;
    final visW = crop != null ? (crop.right - crop.left) * origW : origW;
    final visH = crop != null ? (crop.bottom - crop.top) * origH : origH;
    final imgW = visW * imageElement.scale;
    final imgH = visH * imageElement.scale;
    final worldRect = Rect.fromCenter(
      center: imageElement.position,
      width: imgW,
      height: imgH,
    );
    // canvasToScreen returns coords relative to the canvas WIDGET area,
    // which sits below the toolbar. The animation overlay (Navigator route)
    // positions relative to the FULL SCREEN. Add canvas widget's global offset.
    final canvasRenderBox = _canvasRepaintBoundaryKey.currentContext
        ?.findRenderObject() as RenderBox?;
    final canvasGlobalOffset = canvasRenderBox?.localToGlobal(Offset.zero) ?? Offset.zero;
    final rawTL = _canvasController.canvasToScreen(worldRect.topLeft);
    final rawBR = _canvasController.canvasToScreen(worldRect.bottomRight);
    final screenTL = rawTL + canvasGlobalOffset;
    final screenBR = rawBR + canvasGlobalOffset;
    final cardRect = Rect.fromPoints(screenTL, screenBR);
    final vp = MediaQuery.sizeOf(context);
    final fullRect = Offset.zero & vp;



    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (context, animation, secondaryAnimation) {
          return ImageViewerScreen(
            imageElement: imageElement,
            image: image,
            onClose: () {
              if (mounted) setState(() {});
            },
            onEdit: (element) {
              // Open the existing ImageEditorDialog
              final decodedImage = _loadedImages[element.imagePath];
              if (decodedImage != null) {
                Navigator.of(context).pop(); // Close viewer first
                _openImageEditor(element, decodedImage);
              }
            },
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: const Cubic(0.16, 1.0, 0.3, 1.0),
            reverseCurve: Curves.easeInCubic,
          );

          return AnimatedBuilder(
            animation: curved,
            builder: (context, _) {
              final t = curved.value;

              // 🎨 Backdrop: real gaussian blur + dark scrim
              final blurSigma = t * 12.0;
              final scrimOpacity = (t * 0.85).clamp(0.0, 0.85);

              // 📐 Expanding clip rect with deceleration
              final clipT = Curves.easeOutQuint.transform(t);
              final clipRect = Rect.lerp(cardRect, fullRect, clipT)!;
              final borderRadius = 16.0 * (1.0 - clipT);

              // 🌑 Shadow: grows then fades as card approaches full screen
              final shadowT = t < 0.6
                  ? Curves.easeOut.transform((t / 0.6).clamp(0.0, 1.0))
                  : Curves.easeIn.transform(((1.0 - t) / 0.4).clamp(0.0, 1.0));

              return Stack(
                children: [
                  // Real gaussian blur backdrop
                  if (blurSigma > 0.1)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: BackdropFilter(
                          filter: ui.ImageFilter.blur(
                            sigmaX: blurSigma,
                            sigmaY: blurSigma,
                          ),
                          child: ColoredBox(
                            color: Color.fromARGB(
                              (scrimOpacity * 255).round().clamp(0, 255),
                              8, 10, 25,
                            ),
                          ),
                        ),
                      ),
                    ),

                  // Expanding image card → fullscreen
                  Positioned.fromRect(
                    rect: clipRect,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(borderRadius),
                        boxShadow: shadowT > 0.01 ? [
                          BoxShadow(
                            color: Color.fromARGB(
                              (shadowT * 100).round().clamp(0, 255),
                              0, 0, 0,
                            ),
                            blurRadius: 24 + shadowT * 48,
                            spreadRadius: shadowT * 4,
                            offset: Offset(0, shadowT * 8),
                          ),
                        ] : null,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(borderRadius),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // Bottom: ImageViewerScreen (always mounted)
                            child,
                            // Top: RawImage overlay (fades out t=0.80→1.0)
                            if (t < 1.0)
                              Opacity(
                                opacity: t < 0.80 ? 1.0 : ((1.0 - t) / 0.20).clamp(0.0, 1.0),
                                child: Container(
                                  color: const Color(0xFF080A19),
                                  child: Center(
                                    child: RawImage(
                                      image: image,
                                      fit: BoxFit.contain,
                                      width: clipRect.width,
                                      height: clipRect.height,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),

                ],
              );
            },
          );
        },
        transitionDuration: const Duration(milliseconds: 800),
        reverseTransitionDuration: const Duration(milliseconds: 400),
      ),
    ).then((_) {
      // Center the canvas on the image at a clean zoom level
      final targetScale = 1.0;
      final vp = MediaQuery.sizeOf(context);
      final imageCenter = imageElement.position;
      // Compute offset that places imageCenter at screen center at targetScale
      final targetOffset = Offset(
        vp.width / 2 - imageCenter.dx * targetScale,
        vp.height / 2 - imageCenter.dy * targetScale,
      );
      _canvasController.setScale(targetScale);
      _canvasController.setOffset(targetOffset);
      // Cooldown before re-entry is allowed
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) _imageZoomEnterCooldown = false;
      });
    });
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
