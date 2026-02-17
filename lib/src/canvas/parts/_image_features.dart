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

      // 📏 Calculate scale iniziale per avere size ragionevole
      // Target: larghezza max 800px sullo schermo (size more grande per canvas 100k)
      const double targetScreenWidth = 800.0;
      final imageWidth = image.width.toDouble();

      // Scale per canvas (without considerare zoom)
      double initialScale = targetScreenWidth / imageWidth;

      // Limita lo scale tra 0.1 e 2.0 (permetti ingrandimento fino a 2x)
      initialScale = initialScale.clamp(0.1, 2.0);

      // 🌐 Upload to Storage if on a shared canvas (so remote users can access it)
      String? storageUrl;
      String? thumbnailUrl;
      final imageId = const Uuid().v4();
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
      });

      // 🔄 Sync: notifica delta tracker per sincronizzazione
      _layerController.addImage(newImage);

      // 💾 Auto-save dopo aggiunta immagine
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
    // Annulla timer
    _imageLongPressTimer?.cancel();
    _imageLongPressEditorTimer?.cancel();

    // Ferma drag se attivo
    if (_imageTool.isDragging) {
      _imageTool.endDrag();
    }

    // 🔥 IMPORTANTE: Clear qualsiasi stroke in progress
    // (il long press potrebbe aver iniziato un tratto on the canvas normale)
    if (_drawingHandler.hasStroke) {
      _drawingHandler.cancelStroke();
    }

    // Feedback haptic
    HapticFeedback.mediumImpact();


    setState(() {
      _imageInEditMode = imageElement;
      _imageTool.clearSelection(); // Deseleziona to avoid handles

      // NON caricare gli strokes esistenti - verranno visualizzati automaticamente
      // _imageEditingStrokes contiene SOLO i nuovi strokes durante questa sessione
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

      // 🔄 Sync: notifica delta tracker per sincronizzazione
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

    // 💾 Auto-save dopo editing immagine
    _autoSaveCanvas();
  }

  /// 🧹 Delete strokes dall'immagine in editing mode
  void _eraseFromImageEditingStrokes(Offset canvasPosition) {
    if (_imageInEditMode == null) return;

    final image = _loadedImages[_imageInEditMode!.imagePath];
    if (image == null) return;

    // Convert la position da canvas space a image space
    final imageSpacePos = _convertPointToImageSpace(
      canvasPosition,
      _imageInEditMode!,
      image,
    );

    // Raggio gomma MOLTO more grande per essere efficace
    // In image space le coordinate potrebbero essere more piccole
    const eraserRadius = 100.0;


    // DEBUG: mostra coordinate del primo punto di ogni stroke
    if (_imageEditingStrokes.isNotEmpty) {
      final firstStroke = _imageEditingStrokes.first;
      if (firstStroke.points.isNotEmpty) {
      }
    }
    if (_imageInEditMode!.drawingStrokes.isNotEmpty) {
      final firstExisting = _imageInEditMode!.drawingStrokes.first;
      if (firstExisting.points.isNotEmpty) {
      }
    }

    bool somethingErased = false;

    setState(() {
      // Processa strokes NUOVI - cancella l'INTERO stroke se toccato
      final strokesToRemove = <ProStroke>[];
      for (final stroke in _imageEditingStrokes) {
        // Check if ANY point of the stroke is within the eraser radius
        final hasPointInEraserRadius = stroke.points.any((point) {
          final distance = (point.position - imageSpacePos).distance;
          return distance <= eraserRadius;
        });

        if (hasPointInEraserRadius) {
          strokesToRemove.add(stroke);
          somethingErased = true;
        }
      }

      // Remove strokes cancellati
      _imageEditingStrokes.removeWhere((s) => strokesToRemove.contains(s));

      // Processa strokes ESISTENTI - cancella l'INTERO stroke se toccato
      final index = _imageElements.indexWhere(
        (e) => e.id == _imageInEditMode!.id,
      );
      if (index != -1) {
        final existingStrokes = List<ProStroke>.from(
          _imageInEditMode!.drawingStrokes,
        );
        final existingStrokesToRemove = <ProStroke>[];

        for (final stroke in existingStrokes) {
          // Check if ANY point of the stroke is within the eraser radius
          final hasPointInEraserRadius = stroke.points.any((point) {
            final distance = (point.position - imageSpacePos).distance;
            return distance <= eraserRadius;
          });

          if (hasPointInEraserRadius) {
            existingStrokesToRemove.add(stroke);
            somethingErased = true;
          }
        }

        if (existingStrokesToRemove.isNotEmpty) {
          // Remove strokes cancellati
          existingStrokes.removeWhere(
            (s) => existingStrokesToRemove.contains(s),
          );

          // Update l'immagine
          _imageInEditMode = _imageInEditMode!.copyWith(
            drawingStrokes: existingStrokes,
          );
          _imageElements[index] = _imageInEditMode!;
        }
      }
    });

    if (somethingErased) {
      HapticFeedback.lightImpact();
    } else {
    }
  }

  /// Convert un singolo punto da canvas space a image space
  /// USE THE SAME LOGIC as _convertPointsToImageSpace for consistency!
  Offset _convertPointToImageSpace(
    Offset canvasPoint,
    ImageElement imageElement,
    ui.Image image,
  ) {
    // Translate to the image coordinate system
    var relativePos = canvasPoint - imageElement.position;

    // Applica rotazione inversa
    if (imageElement.rotation != 0) {
      final cos = math.cos(-imageElement.rotation);
      final sin = math.sin(-imageElement.rotation);
      final x = relativePos.dx * cos - relativePos.dy * sin;
      final y = relativePos.dx * sin + relativePos.dy * cos;
      relativePos = Offset(x, y);
    }

    // Applica scala inversa
    if (imageElement.scale != 1.0) {
      relativePos = relativePos / imageElement.scale;
    }

    // Applica flip inverso
    if (imageElement.flipHorizontal || imageElement.flipVertical) {
      relativePos = Offset(
        imageElement.flipHorizontal ? -relativePos.dx : relativePos.dx,
        imageElement.flipVertical ? -relativePos.dy : relativePos.dy,
      );
    }

    return relativePos;
  }

  /// 🔄 Converte coordinate da spazio canvas a spazio immagine
  /// (coordinate relative all'immagine considerando position, rotazione, scala)
  List<ProDrawingPoint> _convertPointsToImageSpace(
    List<ProDrawingPoint> points,
    ImageElement imageElement,
  ) {
    return points.map((point) {
      // Translate to the image coordinate system
      var relativePos = point.position - imageElement.position;

      // Applica rotazione inversa
      if (imageElement.rotation != 0) {
        final cos = math.cos(-imageElement.rotation);
        final sin = math.sin(-imageElement.rotation);
        final x = relativePos.dx * cos - relativePos.dy * sin;
        final y = relativePos.dx * sin + relativePos.dy * cos;
        relativePos = Offset(x, y);
      }

      // Applica scala inversa
      if (imageElement.scale != 1.0) {
        relativePos = relativePos / imageElement.scale;
      }

      // Applica flip inverso
      if (imageElement.flipHorizontal || imageElement.flipVertical) {
        relativePos = Offset(
          imageElement.flipHorizontal ? -relativePos.dx : relativePos.dx,
          imageElement.flipVertical ? -relativePos.dy : relativePos.dy,
        );
      }

      return point.copyWith(position: relativePos);
    }).toList();
  }

  /// � Verify if a punto is dentro i confini of the image
  bool _isPointInsideImage(
    Offset canvasPosition,
    ImageElement imageElement,
    ui.Image image,
  ) {
    // Convert il punto in coordinate relative all'immagine
    var relativePos = canvasPosition - imageElement.position;

    // Applica rotazione inversa
    if (imageElement.rotation != 0) {
      final cos = math.cos(-imageElement.rotation);
      final sin = math.sin(-imageElement.rotation);
      final x = relativePos.dx * cos - relativePos.dy * sin;
      final y = relativePos.dx * sin + relativePos.dy * cos;
      relativePos = Offset(x, y);
    }

    // Applica scala inversa
    if (imageElement.scale != 1.0) {
      relativePos = relativePos / imageElement.scale;
    }

    // Check if it is dentro i confini of the image
    final imageWidth = image.width.toDouble();
    final imageHeight = image.height.toDouble();

    final halfWidth = imageWidth / 2;
    final halfHeight = imageHeight / 2;

    return relativePos.dx >= -halfWidth &&
        relativePos.dx <= halfWidth &&
        relativePos.dy >= -halfHeight &&
        relativePos.dy <= halfHeight;
  }

  /// �🎨 Apre editor professionale per modificare immagine (mantenuto per compatibility)
  void _openImageEditor(ImageElement imageElement, ui.Image image) {
    // Annulla timer
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


      // Esci da editing mode dopo aver salvato gli strokes
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
                });

                // 🔄 Sync: notifica delta tracker per sincronizzazione
                _layerController.updateImage(updated);

                // 💾 Auto-save dopo modifica immagine
                _autoSaveCanvas();
              }
              HapticFeedback.lightImpact();
            },
            onDelete: () {
              // Elimina elemento
              setState(() {
                _imageElements.removeWhere((e) => e.id == imageElement.id);
                _imageTool.clearSelection();
              });

              // 🔄 Sync: notifica delta tracker per sincronizzazione
              _layerController.removeImage(imageElement.id);
              if (_isSharedCanvas) _snapshotAndPushCloudDeltas();

              // 💾 Auto-save dopo eliminazione immagine
              _autoSaveCanvas();

              HapticFeedback.mediumImpact();
            },
          ),
    );
  }
}
