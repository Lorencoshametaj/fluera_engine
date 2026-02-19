part of '../../nebula_canvas_screen.dart';

/// 📦 Drawing Handlers — pointer-down start & cancel
extension on _NebulaCanvasScreenState {
  void _onDrawStart(
    Offset canvasPosition,
    double pressure,
    double tiltX,
    double tiltY,
  ) {
    // 🔒 VIEWER GUARD: Prevent all editing on shared canvas if viewer
    if (_checkViewerGuard()) return;

    // 👁️ Stop follow mode on manual interaction
    if (_followingUserId != null) {
      setState(() => _followingUserId = null);
    }

    // Indica che l'utente sta disegnando (per opacity layer panel)
    _isDrawingNotifier.value = true;

    // ✏️ PRESENCE: Phase 2 — real-time collaboration
    // if (_isSharedCanvas) {
    //   _presenceService.updateDrawingState(true);
    // }

    // 🎤 Traccia tempo inizio (per recording esterno)
    _lastStrokeStartTime = DateTime.now();

    // 🎨 PRIORITÀ 1: Se siamo in editing mode immagine
    if (_imageInEditMode != null) {
      final image = _loadedImages[_imageInEditMode!.imagePath];
      if (image != null) {
        // Check if the point is inside the image
        if (_isPointInsideImage(canvasPosition, _imageInEditMode!, image)) {
          // If gomma attiva, cancella invece di disegnare
          if (_effectiveIsEraser) {
            _eraseFromImageEditingStrokes(canvasPosition);
            return;
          }

          // ⚠️ Azzera lo stroke of the canvas normale to avoid duplicazioni
          _currentStrokeNotifier.clear();

          // Start drawing on top of the image
          _drawingHandler.startStroke(
            position: canvasPosition,
            pressure: pressure,
            tiltX: tiltX,
            tiltY: tiltY,
            orientation: 0.0,
          );

          // 🚀 Fix 1: incremental conversion — init accumulator with first point
          _editingConvertedPoints.clear();
          _editingStrokeCreatedAt = DateTime.now();
          if (_drawingHandler.currentStroke.isNotEmpty) {
            _editingConvertedPoints.add(
              _convertSinglePointToImageSpace(
                _drawingHandler.currentStroke.last,
                _imageInEditMode!,
              ),
            );
          }
          _currentEditingStrokeNotifier.value = ProStroke(
            id: 'temp',
            points: _editingConvertedPoints,
            color: _effectiveColor,
            baseWidth: _effectiveWidth,
            penType: _effectivePenType,
            createdAt: _editingStrokeCreatedAt,
            settings: _brushSettings,
          );
          return;
        } else {
          // Touch outside the image -> exit editing mode
          _exitImageEditMode();
          return;
        }
      }
    } // 🖼️ ALWAYS check interaction with images (max priority)
    if (_imageTool.selectedImage != null) {
      // Check resize handle
      final imageSize =
          _loadedImages[_imageTool.selectedImage!.imagePath]?.width != null
              ? Size(
                _loadedImages[_imageTool.selectedImage!.imagePath]!.width
                    .toDouble(),
                _loadedImages[_imageTool.selectedImage!.imagePath]!.height
                    .toDouble(),
              )
              : Size.zero;

      final handle = _imageTool.hitTestResizeHandle(canvasPosition, imageSize);
      if (handle != null) {
        _imageTool.startResize(handle, canvasPosition);
        // 🔒 SYNC: Lock this image for remote collaborators
        if (_isSharedCanvas && _imageTool.selectedImage != null) {
          _realtimeSyncManager?.setActiveElement(_imageTool.selectedImage!.id);
        }
        setState(() {});
        return;
      }
    }

    // Check hit test su immagini
    for (final imageElement in _imageElements.reversed) {
      final image = _loadedImages[imageElement.imagePath];
      if (image != null) {
        final imageSize = Size(image.width.toDouble(), image.height.toDouble());

        if (_imageTool.hitTest(imageElement, canvasPosition, imageSize)) {
          // Select the image but do NOT start dragging yet
          _imageTool.selectImage(imageElement);

          // 📍 Save initial position to detect movement
          _initialTapPosition = canvasPosition;

          setState(() {});
          return; // 🛑 Block other tools when touching image
        }
      }
    } // If tocco area vuota con selected image, deseleziona
    if (_imageTool.selectedImage != null) {
      _imageTool.clearSelection();
      setState(() {});
      // Do not return - continua con gli altri tool
    }

    // 🎯 Always check text element interaction (regardless of active tool)
    // First check resize handles (only if there's a selection)
    if (_digitalTextTool.hasSelection) {
      final handleIndex = _digitalTextTool.hitTestResizeHandles(
        canvasPosition,
        _digitalTextTool.selectedElement!,
      );

      if (handleIndex != null) {
        // Start resize
        _digitalTextTool.startResize(handleIndex, canvasPosition);
        setState(() {});
        return;
      }
    }

    // 🎯 Always hit-test text elements (even if no text tool is active)
    final hitElement = _digitalTextTool.hitTest(
      canvasPosition,
      _digitalTextElements,
    );

    if (hitElement != null) {
      // Select the element and start drag
      _digitalTextTool.selectElement(hitElement);
      _digitalTextTool.startDrag(canvasPosition);
      setState(() {});
      return; // 🛑 Block other tools when touching text
    }

    // If tapped on empty area, deselect (if there was a selection)
    if (_digitalTextTool.hasSelection) {
      _digitalTextTool.deselectElement();
      setState(() {});
      // Do not return — continue with other tools
    }

    // If digital text mode is active and no text was hit, return (don't draw)
    if (_effectiveIsDigitalText) {
      return;
    }

    // 🔧 FIX: When lasso tool is active with a selection, CHECK DRAG FIRST
    // This must run BEFORE image/text hit-tests, otherwise those intercept
    // the touch and the lasso drag is never reached.
    if (_effectiveIsLasso && _lassoTool.hasSelection) {
      if (_lassoTool.isPointInSelection(canvasPosition)) {
        _lassoTool.startDrag(canvasPosition);
        setState(() {});
        return;
      }
    }

    // If lasso mode is active (but no selection or tapped outside), start new lasso
    if (_effectiveIsLasso) {
      // 🔒 Backup selection before starting new lasso — if a zoom gesture
      // interrupts (2nd finger → _onDrawCancel), we restore the selection.
      if (_lassoTool.hasSelection) {
        _lassoSelectionBackup = (
          strokeIds: Set<String>.from(_lassoTool.selectedStrokeIds),
          shapeIds: Set<String>.from(_lassoTool.selectedShapeIds),
          textIds: Set<String>.from(_lassoTool.selectedTextIds),
          imageIds: Set<String>.from(_lassoTool.selectedImageIds),
        );
      } else {
        _lassoSelectionBackup = null;
      }
      _lassoTool.startLasso(canvasPosition);
      setState(() {});
      return;
    }
    // ✒️ PEN TOOL: route events to vector path editor
    if (_toolController.isPenToolMode) {
      final screenPos = _canvasController.canvasToScreen(canvasPosition);
      _penTool.onPointerDown(
        _penToolContext,
        PointerDownEvent(position: screenPos),
      );
      setState(() {});
      return;
    }

    // If l'eraser is active, cancella at the point
    if (_effectiveIsEraser) {
      final now = DateTime.now().millisecondsSinceEpoch;

      // 🎯 V8: Auto-enable layer preview when eraser activates on multi-layer canvas
      if (_layerController.layers.length > 1 && !_eraserTool.layerPreviewMode) {
        _eraserTool.layerPreviewMode = true;
        _showLayerPreview = true;
      }

      // 🎯 V3/V8/V10: Multi-tap detection — double-tap = undo, triple-tap = redo
      if (now - _lastEraserPointerDownTime < 500) {
        _eraserTapCount++;

        if (_eraserTapCount == 2) {
          // Double-tap → UNDO
          if (_eraserTool.canUndo) {
            final ghosts = _eraserTool.startUndoGhostReplay();
            if (ghosts.isNotEmpty) {
              _showUndoGhostReplay = true;
              Future.delayed(const Duration(milliseconds: 50), () {
                _eraserTool.undoGhostProgress = 0.3;
                if (mounted) setState(() {});
              });
              Future.delayed(const Duration(milliseconds: 150), () {
                _eraserTool.undoGhostProgress = 0.6;
                if (mounted) setState(() {});
              });
              Future.delayed(const Duration(milliseconds: 300), () {
                _eraserTool.undoGhostProgress = 1.0;
                if (mounted) setState(() {});
              });
              Future.delayed(const Duration(milliseconds: 400), () {
                _eraserTool.finishUndoGhostReplay();
                _showUndoGhostReplay = false;
                DrawingPainter.invalidateAllTiles();
                if (mounted) setState(() {});
              });
            } else {
              _eraserTool.undo();
            }
            HapticFeedback.mediumImpact();
          }
          _lastEraserPointerDownTime = now; // Keep time for potential triple
          setState(() {});
          return;
        } else if (_eraserTapCount >= 3) {
          // Triple-tap → REDO
          if (_eraserTool.canRedo) {
            _eraserTool.redo();
            DrawingPainter.invalidateAllTiles();
            HapticFeedback.lightImpact();
          }
          _eraserTapCount = 0; // Reset after triple
          _lastEraserPointerDownTime = 0;
          setState(() {});
          return;
        }
      } else {
        _eraserTapCount = 1; // First tap in new sequence
      }
      _lastEraserPointerDownTime = now;

      // 🏗️ Traccia position per cursore overlay
      _eraserCursorPosition = canvasPosition;

      // 🎯 Clear trail and reset count for new gesture
      _eraserTrail.clear();
      _eraserGestureEraseCount = 0;

      // 🎯 V3: Reset tracking state
      _lastEraserCanvasPosition = canvasPosition;
      _lastEraserMoveTime = now;
      _eraserSmoothedRadius = _eraserTool.eraserRadius;

      // 🎯 V4: Reset lasso points for new gesture
      _eraserLassoPoints.clear();

      // 🎯 V8: Clear prediction buffer for new gesture
      _eraserTool.clearPredictionBuffer();

      // 🎯 Begin erase gesture (tracks erased strokes for undo)
      _eraserTool.beginGesture();

      // 🎯 V4: Lasso mode — just collect points, don't erase yet
      if (_eraserLassoMode) {
        _eraserLassoPoints.add(canvasPosition);
        setState(() {});
        return;
      }

      // 🎯 V4: Magnetic snap
      final snappedPos = _eraserTool.getNearestStrokePosition(canvasPosition);

      // 🎯 Compute preview (highlight strokes under eraser)
      _eraserPreviewIds = _eraserTool.getPreviewStrokeIds(snappedPos);

      // In mode editing immagine, cancella dagli strokes of the image
      if (_imageInEditMode != null) {
        _eraseFromImageEditingStrokes(snappedPos);
      } else {
        final didErase = _eraserTool.eraseAt(snappedPos);
        if (didErase) {
          _eraserGestureEraseCount = _eraserTool.currentGestureEraseCount;
          _eraserPulseController.forward(from: 0);
          _spawnEraserParticles(snappedPos, now);
        }
      }
      setState(() {}); // 🏗️ Forza rebuild per eraser cursor overlay
      return;
    }

    // 🖐️ If Pan mode is active, do not draw
    if (_effectiveIsPanMode) {
      return;
    }

    // 🪣 Phase 3D: Fill mode — execute flood fill at tap point
    if (_effectiveIsFill) {
      _executeFloodFill(canvasPosition);
      return;
    }

    // If is selezionata a geometric shape
    if (_effectiveShapeType != ShapeType.freehand) {
      // 📏 Phase 3C: Snap to guides for precision shapes
      final snappedPos =
          _showRulers && _rulerGuideSystem.snapEnabled
              ? _rulerGuideSystem.snapPoint(
                canvasPosition,
                _canvasController.scale,
              )
              : canvasPosition;
      _currentShapeNotifier.value = GeometricShape(
        id: const Uuid().v4(),
        type: _effectiveShapeType,
        startPoint: snappedPos,
        endPoint: snappedPos,
        color: _effectiveColor,
        strokeWidth: _effectiveWidth,
        filled: false,
        createdAt: DateTime.now(),
      );
      return;
    }

    // 🆕 Disegno a mano libera - usa processor appropriato
    if (_is120HzMode && _rawInputProcessor120Hz != null) {
      // 🚀 120Hz MODE: Raw processor for thetenza minima
      // Buildi ProDrawingPoint direttamente (zero processing)
      final point = ProDrawingPoint(
        position: canvasPosition,
        pressure: pressure.clamp(0.0, 1.0),
        timestamp: DateTime.now().millisecondsSinceEpoch,
        tiltX: tiltX,
        tiltY: tiltY,
        orientation: 0.0,
      );

      // 🚀 FIX #1: Initialize with MUTABLE list that will be reused
      _rawInputProcessor120Hz!.reset();
      _currentStrokeNotifier.setStroke([point]);
    } else {
      // ✅ 60Hz MODE: DrawingInputHandler con smoothing
      _drawingHandler.startStroke(
        position: canvasPosition,
        pressure: pressure,
        tiltX: tiltX,
        tiltY: tiltY,
        orientation: 0.0,
      );
    }

    // 🎤 Se stiamo registrando con tratti, salva timestamp inizio stroke
    if (_isRecordingAudio && _recordingWithStrokes) {
      _currentStrokeStartTime = DateTime.now();
    }
  }

  /// 🚫 Clear lo in-progress stroke without salvarlo
  /// Called when a 2° dito interrompe il disegno (pan/zoom)
  void _onDrawCancel() {
    // Reset drawing state flag
    _isDrawingNotifier.value = false;

    // 🔒 Restore lasso selection if a zoom gesture interrupted a new lasso
    if (_effectiveIsLasso && _lassoSelectionBackup != null) {
      _lassoTool.clearLassoPath();
      _lassoTool.selectedStrokeIds.addAll(_lassoSelectionBackup!.strokeIds);
      _lassoTool.selectedShapeIds.addAll(_lassoSelectionBackup!.shapeIds);
      _lassoTool.selectedTextIds.addAll(_lassoSelectionBackup!.textIds);
      _lassoTool.selectedImageIds.addAll(_lassoSelectionBackup!.imageIds);
      _lassoSelectionBackup = null;
      setState(() {});
      return;
    }
    _lassoSelectionBackup = null;

    // Erase the in-progress stroke from the notifier (don't save anything)
    _currentStrokeNotifier.clear();

    // Reset del drawing handler se ha uno stroke in corso
    if (_drawingHandler.hasStroke) {
      _drawingHandler.endStroke(); // Svuota lo stroke, scarta i punti
    }

    // Reset del raw processor 120Hz se attivo
    if (_is120HzMode && _rawInputProcessor120Hz != null) {
      _rawInputProcessor120Hz!.reset();
    }

    // Reset timestamp registrazione
    _currentStrokeStartTime = null;
  }
}
