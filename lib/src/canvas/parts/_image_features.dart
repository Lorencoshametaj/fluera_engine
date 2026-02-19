part of '../nebula_canvas_screen.dart';

/// 📦 Image Features — extracted from _NebulaCanvasScreenState
extension on _NebulaCanvasScreenState {
  /// 🖼️ Apre la galleria e aggiunge un'immagine al canvas
  /// 🖼️ Seleziona immagine from the galleria e aggiungila al canvas (Pubblico per multiview)
  Future<void> pickAndAddImage() async {
    // 🔒 VIEWER GUARD
    if (_checkViewerGuard()) return;

    try {
      // Seleziona immagine from the galleria
      final imagePath = await ImageService.pickImageFromGallery(context);

      if (imagePath == null) return; // Utente ha annullato

      // Load l'immagine in memoria
      final image = await ImageService.loadImageFromPath(imagePath);

      if (image == null) {
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

      // Calculate position centrale of the viewport in canvas coordinates
      final screenCenter = Offset(
        MediaQuery.of(context).size.width / 2,
        MediaQuery.of(context).size.height / 2,
      );
      final viewportCenter = _canvasController.screenToCanvas(screenCenter);

      // 📏 Calculate initial scale to have reasonable size on screen.
      // Target: ~400px on screen, regardless of current canvas zoom.
      final screenWidth = MediaQuery.of(context).size.width;
      final targetScreenWidth = screenWidth * 0.45; // ~45% of screen width
      final imageWidth = image.width.toDouble();
      final canvasZoom = _canvasController.scale;

      // Convert from screen pixels to canvas units, then scale to image pixels
      double initialScale = (targetScreenWidth / canvasZoom) / imageWidth;

      // Clamp to sane range
      initialScale = initialScale.clamp(0.05, 3.0);

      // 🌐 Upload to Storage if on a shared canvas (so remote users can access it)
      String? storageUrl;
      String? thumbnailUrl;
      final imageId = generateUid();
      // Phase 2: upload to cloud storage for shared canvases
      // if (_isSharedCanvas) {
      //   final syncId = widget.infiniteCanvasId ?? _canvasId;
      //   final imageBytes = await File(imagePath).readAsBytes();
      //   ...
      // }

      // Create image element
      final newImage = ImageElement(
        id: imageId,
        imagePath: imagePath,
        storageUrl: storageUrl, // 📸 Cloud URL for remote access
        thumbnailUrl: thumbnailUrl, // 📸 Thumbnail for fast preview
        position: viewportCenter,
        scale: initialScale, // 📏 Scale calcolato
        rotation: 0.0,
        createdAt: DateTime.now(),
        pageIndex: 0, // Professional canvas non ha pagine multiple
      );

      setState(() {
        _imageElements.add(newImage);
        _loadedImages[imagePath] = image; // Add alla cache
        _imageTool.selectImage(newImage); // Seleziona automaticamente
        _imageVersion++;
        _rebuildImageSpatialIndex();
      });

      // 🔄 Sync: notify delta tracker for synchronization
      _layerController.addImage(newImage);

      // 💾 Auto-save after adding image
      _autoSaveCanvas();

      HapticFeedback.mediumImpact();
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

  /// 🎨 Enamong then mode editing for a'immagine
  void _enterImageEditMode(ImageElement imageElement) {
    // Cancel timer
    _imageLongPressTimer?.cancel();
    _imageLongPressEditorTimer?.cancel();

    // Ferma drag se attivo
    if (_imageTool.isDragging) {
      _imageTool.endDrag();
    }

    // 🔥 IMPORTANT: Clear any stroke in progress
    // (the long press might have started a stroke on the normal canvas)
    if (_drawingHandler.hasStroke) {
      _drawingHandler.cancelStroke();
    }

    // Feedback haptic
    HapticFeedback.mediumImpact();

    setState(() {
      _imageInEditMode = imageElement;
      _imageTool.clearSelection(); // Deseleziona to avoid handles

      // NON caricare gli strokes esistenti - verranno visualizzati automaticamente
      // _imageEditingStrokes contains ONLY the new strokes during this session
      _imageEditingStrokes.clear();
    });
  }

  /// 🎨 Esce from the mode editing immagine e salva gli strokes
  void _exitImageEditMode() {
    if (_imageInEditMode == null) return;

    // Update l'immagine con gli strokes disegnati
    final index = _imageElements.indexWhere(
      (e) => e.id == _imageInEditMode!.id,
    );
    if (index != -1) {
      // Combine gli strokes esistenti con quelli nuovi
      final allStrokes = [
        ..._imageInEditMode!.drawingStrokes,
        ..._imageEditingStrokes,
      ];

      final updatedImage = _imageInEditMode!.copyWith(
        drawingStrokes: allStrokes,
      );
      _imageElements[index] = updatedImage;
      _imageVersion++;
      _rebuildImageSpatialIndex();

      // 🔄 Sync: notify delta tracker for synchronization
      _layerController.updateImage(updatedImage);
    }

    setState(() {
      _imageInEditMode = null;
      _imageEditingStrokes.clear();
      _imageEditingUndoStack.clear();
      _currentEditingStrokeNotifier.value = null;
    });

    // Feedback haptic
    HapticFeedback.lightImpact();

    // 💾 Auto-save after image editing
    _autoSaveCanvas();
  }

  /// 🧹 Delete strokes dall'immagine in editing mode
  void _eraseFromImageEditingStrokes(Offset canvasPosition) {
    if (_imageInEditMode == null) return;

    final image = _loadedImages[_imageInEditMode!.imagePath];
    if (image == null) return;

    // Convert la position da canvas space a image space
    final imageSpacePos = _canvasToImageSpace(
      canvasPosition,
      _imageInEditMode!,
    );

    // Raggio gomma in image space
    const eraserRadius = 100.0;

    bool somethingErased = false;

    setState(() {
      // Processa strokes NUOVI — early-exit per stroke
      final strokesToRemove = <ProStroke>[];
      for (final stroke in _imageEditingStrokes) {
        for (final point in stroke.points) {
          if ((point.position - imageSpacePos).distance <= eraserRadius) {
            strokesToRemove.add(stroke);
            somethingErased = true;
            break; // ⚡ Early exit: no need to check remaining points
          }
        }
      }

      _imageEditingStrokes.removeWhere((s) => strokesToRemove.contains(s));

      // Processa strokes ESISTENTI — early-exit per stroke
      final index = _imageElements.indexWhere(
        (e) => e.id == _imageInEditMode!.id,
      );
      if (index != -1) {
        final existingStrokes = List<ProStroke>.from(
          _imageInEditMode!.drawingStrokes,
        );
        final existingStrokesToRemove = <ProStroke>[];

        for (final stroke in existingStrokes) {
          for (final point in stroke.points) {
            if ((point.position - imageSpacePos).distance <= eraserRadius) {
              existingStrokesToRemove.add(stroke);
              somethingErased = true;
              break; // ⚡ Early exit
            }
          }
        }

        if (existingStrokesToRemove.isNotEmpty) {
          existingStrokes.removeWhere(
            (s) => existingStrokesToRemove.contains(s),
          );

          _imageInEditMode = _imageInEditMode!.copyWith(
            drawingStrokes: existingStrokes,
          );
          _imageElements[index] = _imageInEditMode!;
          _imageVersion++;
          _rebuildImageSpatialIndex();
        }
      }

      // 🧠 Fix 8: erasing invalidates redo history
      if (somethingErased) {
        _imageEditingUndoStack.clear();
      }
    });

    if (somethingErased) {
      HapticFeedback.lightImpact();
    }
  }

  /// 🔄 Convert a single canvas-space point to image-space.
  /// Central method — all coordinate conversion goes through here.
  Offset _canvasToImageSpace(Offset canvasPoint, ImageElement imageElement) {
    // Translate relative to image center
    var p = canvasPoint - imageElement.position;

    // Inverse rotation
    if (imageElement.rotation != 0) {
      final cos = math.cos(-imageElement.rotation);
      final sin = math.sin(-imageElement.rotation);
      p = Offset(p.dx * cos - p.dy * sin, p.dx * sin + p.dy * cos);
    }

    // Inverse scale
    if (imageElement.scale != 1.0) {
      p = p / imageElement.scale;
    }

    // Inverse flip
    if (imageElement.flipHorizontal || imageElement.flipVertical) {
      p = Offset(
        imageElement.flipHorizontal ? -p.dx : p.dx,
        imageElement.flipVertical ? -p.dy : p.dy,
      );
    }

    return p;
  }

  /// 🔄 Batch-convert drawing points from canvas space to image space.
  List<ProDrawingPoint> _convertPointsToImageSpace(
    List<ProDrawingPoint> points,
    ImageElement imageElement,
  ) {
    return points.map((point) {
      final converted = _canvasToImageSpace(point.position, imageElement);
      return point.copyWith(position: converted);
    }).toList();
  }

  /// 🔄 Convert a single drawing point from canvas space to image space.
  ProDrawingPoint _convertSinglePointToImageSpace(
    ProDrawingPoint point,
    ImageElement imageElement,
  ) {
    final converted = _canvasToImageSpace(point.position, imageElement);
    return point.copyWith(position: converted);
  }

  /// ✔️ Check if a canvas-space point is inside the image bounds.
  bool _isPointInsideImage(
    Offset canvasPosition,
    ImageElement imageElement,
    ui.Image image,
  ) {
    // Uses unified conversion (includes flip — Fix 2)
    final p = _canvasToImageSpace(canvasPosition, imageElement);

    final halfWidth = image.width.toDouble() / 2;
    final halfHeight = image.height.toDouble() / 2;

    return p.dx >= -halfWidth &&
        p.dx <= halfWidth &&
        p.dy >= -halfHeight &&
        p.dy <= halfHeight;
  }

  /// �🎨 Apre editor professionale per modificare immagine (mantenuto per compatibility)
  void _openImageEditor(ImageElement imageElement, ui.Image image) {
    // Cancel timer
    _imageLongPressTimer?.cancel();
    _imageLongPressEditorTimer?.cancel();

    // 🎨 Prepara elemento with all gli strokes aggiornati
    ImageElement elementToEdit = imageElement;

    // If siamo in editing mode, combina gli strokes esistenti + nuovi
    if (_imageInEditMode != null && _imageInEditMode!.id == imageElement.id) {
      final allStrokes = [
        ..._imageInEditMode!.drawingStrokes,
        ..._imageEditingStrokes,
      ];

      elementToEdit = imageElement.copyWith(drawingStrokes: allStrokes);

      // Exit editing mode after saving strokes
      _exitImageEditMode();
    }

    // Ferma drag se attivo
    if (_imageTool.isDragging) {
      _imageTool.endDrag();
    }

    // Feedback haptic
    HapticFeedback.mediumImpact();

    // Open dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => ImageEditorDialog(
            imageElement: elementToEdit,
            image: image,
            onSave: (updated) {
              // 🎨 Debug: verifica strokes ricevuti

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

                // 💾 Auto-save after image modification
                _autoSaveCanvas();
              }
              HapticFeedback.lightImpact();
            },
            onDelete: () {
              // Elimina elemento
              setState(() {
                _imageElements.removeWhere((e) => e.id == imageElement.id);
                _imageTool.clearSelection();
                _imageVersion++;
                _rebuildImageSpatialIndex();
              });

              // 🔄 Sync: notify delta tracker for synchronization
              _layerController.removeImage(imageElement.id);
              if (_isSharedCanvas) _snapshotAndPushCloudDeltas();

              // 💾 Auto-save after image deletion
              _autoSaveCanvas();

              HapticFeedback.mediumImpact();
            },
          ),
    );
  }
}
