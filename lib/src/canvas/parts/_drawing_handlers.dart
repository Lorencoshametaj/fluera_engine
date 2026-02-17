part of '../nebula_canvas_screen.dart';

/// 📦 Drawing Handlers — extracted from _NebulaCanvasScreenState
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
        // Check if the punto is dentro l'immagine
        if (_isPointInsideImage(canvasPosition, _imageInEditMode!, image)) {
          // If gomma attiva, cancella invece di disegnare
          if (_effectiveIsEraser) {
            _eraseFromImageEditingStrokes(canvasPosition);
            return;
          }

          // ⚠️ Azzera lo stroke of the canvas normale to avoid duplicazioni
          _currentStrokeNotifier.clear();

          // Start disegno sopra l'immagine
          _drawingHandler.startStroke(
            position: canvasPosition,
            pressure: pressure, // 🚀 Usa real pressure
            tiltX: tiltX, // 🖊️ Usa tilt reale
            tiltY: tiltY,
            orientation: 0.0,
          );

          // Update il notifier with ao stroke temporaneo completo (con colore!)
          final relativePoints = _convertPointsToImageSpace(
            _drawingHandler.currentStroke,
            _imageInEditMode!,
          );
          _currentEditingStrokeNotifier.value = ProStroke(
            id: 'temp',
            points: relativePoints,
            color: _effectiveColor,
            baseWidth: _effectiveWidth,
            penType: _effectivePenType,
            createdAt: DateTime.now(),
            settings: _brushSettings, // 🎛️ Passa settings
          );
          return;
        } else {
          // Tocco fuori dall'immagine -> esci da mode editing
          _exitImageEditMode();
          return;
        }
      }
    } // 🖼️ SEMPRE controlla interazione con immagini (priority massima)
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
          // Seleziona l'immagine ma NON iniziare il drag ancora
          _imageTool.selectImage(imageElement);

          // 📍 Save position iniziale per rilevare movimento
          _initialTapPosition = canvasPosition;

          setState(() {});
          return; // 🛑 Blocca altri tool when tocca un'immagine
        }
      }
    } // If tocco area vuota con selected image, deseleziona
    if (_imageTool.selectedImage != null) {
      _imageTool.clearSelection();
      setState(() {});
      // Do not return - continua con gli altri tool
    }

    // 🎯 SEMPRE controlla interazione con text elements (indipendentemente dal tool attivo)
    // Prima controlla se si tocca un handle di resize (only if c'è una selezione)
    if (_digitalTextTool.hasSelection) {
      final handleIndex = _digitalTextTool.hitTestResizeHandles(
        canvasPosition,
        _digitalTextTool.selectedElement!,
        context,
      );

      if (handleIndex != null) {
        // Start resize
        _digitalTextTool.startResize(handleIndex, canvasPosition, context);
        setState(() {});
        return;
      }
    }

    // 🎯 SEMPRE fa hit test su text elements (even if nessun tool testo attivo)
    final hitElement = _digitalTextTool.hitTest(
      canvasPosition,
      _digitalTextElements,
      context,
    );

    if (hitElement != null) {
      // Seleziona l'elemento
      _digitalTextTool.selectElement(hitElement);
      // Start drag
      _digitalTextTool.startDrag(canvasPosition);
      setState(() {});
      return; // 🛑 Blocca altri tool when tocca un testo
    }

    // If tocco area vuota, deseleziona (se c'era una selezione)
    if (_digitalTextTool.hasSelection) {
      _digitalTextTool.deselectElement();
      setState(() {});
      // Do not return - continua con gli altri tool
    }

    // If il digital text is active E non ho toccato nessun testo, return (non disegnare)
    if (_effectiveIsDigitalText) {
      return;
    }

    // If il lasso is active, controlla se inizio drag o nuovo lasso
    if (_effectiveIsLasso) {
      // If c'è una selezione e il punto is dentro la selezione, inizia drag
      if (_lassoTool.hasSelection &&
          _lassoTool.isPointInSelection(canvasPosition)) {
        _lassoTool.startDrag(canvasPosition);
        setState(() {});
        return;
      }

      // Altrimenti, nuovo lasso
      _lassoTool.startLasso(canvasPosition);
      setState(() {}); // Update per visualizzare il path
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

    // 🖐️ Se is attiva la mode Pan, non disegnare
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

      // 🚀 FIX #1: Initialize con lista MUTABILE che will come riutilizzata
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

    // Eraif the stroke corrente dal notifier (non salvare nulla)
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

  void _onDrawUpdate(
    Offset canvasPosition,
    double pressure,
    double tiltX,
    double tiltY,
  ) {
    // 🔵 PRESENCE: Feed cursor + tool info to remote users via RTDB (throttled 250ms)
    if (_isSharedCanvas) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastCursorFeedTime > 200) {
        _lastCursorFeedTime = now;
        final syncId = widget.infiniteCanvasId ?? _canvasId;
        final user = null /* auth via _config */;
        if (user != null) {
          final colorIndex = user.uid.hashCode.abs() % 8;
          const cursorColors = [
            0xFF42A5F5,
            0xFFEF5350,
            0xFF66BB6A,
            0xFFAB47BC,
            0xFFFF7043,
            0xFF26C6DA,
            0xFFEC407A,
            0xFFFFA726,
          ];
          // RtdbDeltaSyncService.instance.pushCursorPosition( // Phase 2: collaboration
          //   canvasId: syncId,
          //   userId: user.uid,
          //   x: canvasPosition.dx,
          //   y: canvasPosition.dy,
          //   isDrawing: true,
          //   displayName: user.displayName ?? 'User',
          //   cursorColor: cursorColors[colorIndex],
          //   penType: _effectivePenType.name,
          //   penColor: _effectiveSelectedColor.toARGB32(),
          //   isTyping: _digitalTextTool.hasSelection,
          //   viewportX: _canvasController.offset.dx,
          //   viewportY: _canvasController.offset.dy,
          //   viewportScale: _canvasController.scale,
          //   lockedElementId: _getActiveElementId(),
          // );
        }
      }
    }

    // 🎨 PRIORITÀ 1: Se siamo in editing mode immagine
    if (_imageInEditMode != null) {
      final image = _loadedImages[_imageInEditMode!.imagePath];
      if (image != null) {
        // Check if the point is still inside the image
        if (_isPointInsideImage(canvasPosition, _imageInEditMode!, image)) {
          // If gomma attiva, continua a cancellare
          if (_effectiveIsEraser) {
            _eraseFromImageEditingStrokes(canvasPosition);
            return;
          }

          // ⚠️ Azzera lo stroke of the canvas normale to avoid duplicazioni
          _currentStrokeNotifier.clear();

          // Continua disegno sopra l'immagine only if stiamo disegnando
          if (_drawingHandler.hasStroke) {
            _drawingHandler.updateStroke(
              position: canvasPosition,
              pressure: pressure, // 🚀 Usa real pressure
              tiltX: tiltX, // 🖊️ Usa tilt reale
              tiltY: tiltY,
              orientation: 0.0,
            );

            // Update il notifier with ao stroke temporaneo completo (con colore!)
            final relativePoints = _convertPointsToImageSpace(
              _drawingHandler.currentStroke,
              _imageInEditMode!,
            );
            _currentEditingStrokeNotifier.value = ProStroke(
              id: 'temp',
              points: relativePoints,
              color: _effectiveColor,
              baseWidth: _effectiveWidth,
              penType: _effectivePenType,
              createdAt: DateTime.now(),
              settings: _brushSettings, // 🎛️ Passa settings
            );
          }
          return;
        } else {
          // If esce dai confini, termina il current stroke
          if (_drawingHandler.hasStroke) {
            _onDrawEnd(canvasPosition);
          }
          return;
        }
      }
    }

    // 🖼️ Se c'è una position iniziale salvata (tap su immagine), controlla movimento
    if (_initialTapPosition != null && _imageTool.selectedImage != null) {
      final distance = (canvasPosition - _initialTapPosition!).distance;

      if (distance > _NebulaCanvasScreenState._dragThreshold) {
        // Movimento rilevato! Clear timer e inizia drag
        _imageLongPressTimer?.cancel();
        _imageLongPressEditorTimer?.cancel();

        // Start il drag from the position iniziale
        _imageTool.startDrag(_initialTapPosition!);
        _initialTapPosition = null; // Reset
        // 🔒 SYNC: Lock this image for remote collaborators
        if (_isSharedCanvas && _imageTool.selectedImage != null) {
          _realtimeSyncManager?.setActiveElement(_imageTool.selectedImage!.id);
        }
      } else {
        // Movimento troppo piccolo, ignora (aspetta timer)
        return;
      }
    } // 🖼️ SEMPRE gestisci resize/drag di immagini (priority massima)
    if (_imageTool.isResizing) {
      final updated = _imageTool.updateResize(canvasPosition);
      if (updated != null) {
        // Find and update in the list
        final index = _imageElements.indexWhere((e) => e.id == updated.id);
        if (index != -1) {
          _imageElements[index] = updated;
        }

        // Auto-scroll ai bordi
        final screenPosition = _canvasController.canvasToScreen(canvasPosition);
        final RenderBox? renderBox =
            _canvasAreaKey.currentContext?.findRenderObject() as RenderBox?;
        if (renderBox != null) {
          final canvasSize = renderBox.size;
          _startAutoScrollIfNeeded(screenPosition, canvasSize);
        }
        setState(() {});
      }
      return;
    }

    if (_imageTool.isDragging) {
      final updated = _imageTool.updateDrag(canvasPosition);
      if (updated != null) {
        // Find and update in the list
        final index = _imageElements.indexWhere((e) => e.id == updated.id);
        if (index != -1) {
          _imageElements[index] = updated;
        }

        // 🔄 SYNC: Lightweight position update during drag (no RTDB delta push)
        // Full delta sync happens at drag end to avoid OOM from serializing
        // entire ImageElement (including drawingStrokes) every frame.
        if (_isSharedCanvas) {
          final now = DateTime.now().millisecondsSinceEpoch;
          if (now - _lastDragSyncTime >=
              _NebulaCanvasScreenState._dragSyncThrottleMs) {
            _lastDragSyncTime = now;
            // Update layer state only (no delta recording)
            final wasTracking = _layerController.enableDeltaTracking;
            _layerController.enableDeltaTracking = false;
            _layerController.updateImage(updated);
            _layerController.enableDeltaTracking = wasTracking;
          }
        }

        // Auto-scroll ai bordi
        final screenPosition = _canvasController.canvasToScreen(canvasPosition);
        final RenderBox? renderBox =
            _canvasAreaKey.currentContext?.findRenderObject() as RenderBox?;
        if (renderBox != null) {
          final canvasSize = renderBox.size;
          _startAutoScrollIfNeeded(screenPosition, canvasSize);
        }
        setState(() {});
      }
      return;
    }

    // 🎯 SEMPRE gestisci resize/drag di digital text (indipendentemente dal tool attivo)
    // If sta facendo resize
    if (_digitalTextTool.isResizing) {
      final updated = _digitalTextTool.updateResize(canvasPosition, context);
      if (updated != null) {
        // Update the element in the list
        final index = _digitalTextElements.indexWhere(
          (e) => e.id == updated.id,
        );
        if (index != -1) {
          _digitalTextElements[index] = updated;
        }

        // Auto-scroll ai bordi (come for the drag)
        final screenPosition = _canvasController.canvasToScreen(canvasPosition);
        final RenderBox? renderBox =
            _canvasAreaKey.currentContext?.findRenderObject() as RenderBox?;
        if (renderBox != null) {
          final canvasSize = renderBox.size;
          _startAutoScrollIfNeeded(screenPosition, canvasSize);
        }

        setState(() {});
      }
      return;
    }

    // If sta draggando
    if (_digitalTextTool.isDragging) {
      // Update drag - updateDrag moves the position in canvas coordinates
      final updated = _digitalTextTool.updateDrag(canvasPosition);
      if (updated != null) {
        // Update the element in the list
        final index = _digitalTextElements.indexWhere(
          (e) => e.id == updated.id,
        );
        if (index != -1) {
          _digitalTextElements[index] = updated;
        }

        // Auto-scroll ai bordi
        final screenPosition = _canvasController.canvasToScreen(canvasPosition);
        final RenderBox? renderBox =
            _canvasAreaKey.currentContext?.findRenderObject() as RenderBox?;
        if (renderBox != null) {
          final canvasSize = renderBox.size;
          _startAutoScrollIfNeeded(screenPosition, canvasSize);
        }

        setState(() {});
      }
      return;
    }

    // If il lasso is active, controlla se drag o disegno
    // 🪣 Fill mode — no continuous drawing, fill is single-tap only
    if (_effectiveIsFill) {
      return;
    }

    if (_effectiveIsLasso) {
      // If sta draggando, aggiorna la position e auto-scroll
      if (_lassoTool.isDragging) {
        _lassoTool.updateDrag(canvasPosition);

        // Convert canvasPosition in screenPosition per auto-scroll
        final screenPosition = _canvasController.canvasToScreen(canvasPosition);

        // Get size del widget canvas
        final RenderBox? renderBox =
            _canvasAreaKey.currentContext?.findRenderObject() as RenderBox?;
        if (renderBox != null) {
          final canvasSize = renderBox.size;
          _startAutoScrollIfNeeded(screenPosition, canvasSize);
        }

        setState(() {});
        return;
      }

      // Altrimenti aggiorna il lasso path
      _lassoTool.updateLasso(canvasPosition);
      setState(() {}); // Update per visualizzare il path
      return;
    }

    // ✒️ PEN TOOL: route move events
    if (_toolController.isPenToolMode) {
      final screenPos = _canvasController.canvasToScreen(canvasPosition);
      _penTool.onPointerMove(
        _penToolContext,
        PointerMoveEvent(position: screenPos),
      );
      setState(() {});
      return;
    }

    // If l'eraser is active, cancella at the point
    if (_effectiveIsEraser) {
      final now = DateTime.now().millisecondsSinceEpoch;

      // 🎯 V4: Lasso mode — collect path points, don't erase
      if (_eraserLassoMode) {
        _eraserLassoPoints.add(canvasPosition);
        _eraserCursorPosition = canvasPosition;
        setState(() {});
        return;
      }

      // 🎯 V4: Magnetic snap
      final snappedCanvasPos = _eraserTool.getNearestStrokePosition(
        canvasPosition,
      );

      // 🎯 Smooth cursor interpolation (anti-jitter)
      if (_eraserCursorPosition != null) {
        _eraserCursorPosition = Offset.lerp(
          _eraserCursorPosition!,
          snappedCanvasPos,
          0.7,
        );
      } else {
        _eraserCursorPosition = snappedCanvasPos;
      }
      // 🎯 V5: Track tilt for ellipse cursor
      _eraserTiltX = tiltX;
      _eraserTiltY = tiltY;

      // 🎯 V8: Stylus tilt → shape rotation (natural angle from pen tilt)
      _eraserTool.updateShapeAngleFromTilt(tiltX, tiltY);

      // 🎯 Track trail (max 20 points)
      _eraserTrail.add(_EraserTrailPoint(canvasPosition, now));
      _eraserTrail.removeWhere((p) => now - p.timestamp > 300);
      if (_eraserTrail.length > 20) {
        _eraserTrail.removeRange(0, _eraserTrail.length - 20);
      }

      // 🎯 V3/V8: Speed-based radius scaling + velocity-adaptive radius
      double speedMultiplier = 1.0;
      double currentSpeed = 0.0;
      if (_lastEraserCanvasPosition != null && _lastEraserMoveTime > 0) {
        final dt = (now - _lastEraserMoveTime).clamp(1, 1000);
        final distance = (canvasPosition - _lastEraserCanvasPosition!).distance;
        currentSpeed = distance / dt; // px per ms
        // V8: Use velocity-adaptive multiplier if enabled, else V3 legacy
        speedMultiplier = _eraserTool.getVelocityRadiusMultiplier(currentSpeed);
        if (speedMultiplier == 1.0) {
          // Fallback to V3 scaling if velocity-adaptive is off
          speedMultiplier = (1.0 + (currentSpeed / 4.0).clamp(0.0, 0.5));
        }
      }

      // 🎯 V3: Smooth pressure lerp (instead of jumping)
      // V5: Apply pressure curve before scaling
      if (pressure > 0.0 && pressure < 1.0) {
        final curvedPressure = _eraserTool.applyPressureCurve(pressure);
        final baseRadius = _eraserTool.eraserRadius;
        final scale = 0.5 + (curvedPressure * 0.5);
        final targetRadius = (baseRadius * scale * speedMultiplier).clamp(
          EraserTool.minRadius,
          EraserTool.maxRadius,
        );
        // Lerp 30% per frame for smooth transition
        _eraserSmoothedRadius =
            _eraserSmoothedRadius +
            (targetRadius - _eraserSmoothedRadius) * 0.3;
        _eraserTool.eraserRadius = _eraserSmoothedRadius.clamp(
          EraserTool.minRadius,
          EraserTool.maxRadius,
        );
      } else if (speedMultiplier > 1.0) {
        // Apply speed scaling even without pressure
        final targetRadius = (_eraserTool.eraserRadius * speedMultiplier).clamp(
          EraserTool.minRadius,
          EraserTool.maxRadius,
        );
        _eraserSmoothedRadius =
            _eraserSmoothedRadius +
            (targetRadius - _eraserSmoothedRadius) * 0.3;
      }

      // 🎯 V5: Speed-based haptic friction — REMOVED (too noisy, vibrated every frame)

      // 🎯 Update preview IDs (skip during active erase — saves a full stroke scan)
      if (!_eraserTool.isGestureActive) {
        _eraserPreviewIds = _eraserTool.getPreviewStrokeIds(canvasPosition);
      }

      // 🎯 V3: Continuous path interpolation — erase along the entire path
      if (_imageInEditMode != null) {
        _eraseFromImageEditingStrokes(canvasPosition);
      } else {
        // V6: Ruler-guided eraser — constrain position to nearest guide line
        var erasePosition = canvasPosition;
        if (_rulerGuideSystem.horizontalGuides.isNotEmpty ||
            _rulerGuideSystem.verticalGuides.isNotEmpty) {
          double bestGuideDist = 20.0; // Max snap distance to ruler
          Offset? snappedToGuide;

          // Check horizontal guides (y positions)
          for (final gy in _rulerGuideSystem.horizontalGuides) {
            final d = (canvasPosition.dy - gy).abs();
            if (d < bestGuideDist) {
              bestGuideDist = d;
              snappedToGuide = Offset(canvasPosition.dx, gy);
            }
          }
          // Check vertical guides (x positions)
          for (final gx in _rulerGuideSystem.verticalGuides) {
            final d = (canvasPosition.dx - gx).abs();
            if (d < bestGuideDist) {
              bestGuideDist = d;
              snappedToGuide = Offset(gx, canvasPosition.dy);
            }
          }
          if (snappedToGuide != null) {
            erasePosition = snappedToGuide;
          }
        }

        // V6: Stroke-by-stroke mode — tap to erase individual strokes
        if (_eraserTool.strokeByStrokeMode) {
          final strokeId = _eraserTool.getStrokeAtPoint(erasePosition);
          if (strokeId != null) {
            _eraserTool.eraseStrokeById(strokeId);
            _eraserGestureEraseCount = _eraserTool.currentGestureEraseCount;
            _spawnEraserParticles(erasePosition, now);
            // V5: Invalidatete spatial index after erase
            _eraserTool.invalidateSpatialIndex();
            DrawingPainter.invalidateAllTiles();
          }
        } else {
          bool didEraseAny = false;

          if (_lastEraserCanvasPosition != null) {
            final from = _lastEraserCanvasPosition!;
            final to = erasePosition;
            final dist = (to - from).distance;
            final step = _eraserTool.eraserRadius * 0.5;
            final steps = (dist / step).ceil().clamp(1, 30); // Capped at 30

            // Linear interpolation only (Catmull-Rom removed: marginal quality
            // gain didn't justify the allocation + O(n²) contains check cost)
            for (int i = 0; i <= steps; i++) {
              final t = i / steps;
              final interpPos = Offset.lerp(from, to, t)!;
              final didErase = _eraserTool.eraseAt(interpPos);
              if (didErase) {
                didEraseAny = true;
                // Throttle particles: spawn every 3rd erase point max
                if (i % 3 == 0) _spawnEraserParticles(interpPos, now);
              }
            }

            // V8: Path-predictive erasing
            final predicted = _eraserTool.getPredictedPosition(to);
            if (predicted != null) {
              final didErasePred = _eraserTool.eraseAt(predicted);
              if (didErasePred) didEraseAny = true;
            }
          } else {
            // First point — no interpolation needed
            final didErase = _eraserTool.eraseAt(erasePosition);
            if (didErase) {
              didEraseAny = true;
              _spawnEraserParticles(erasePosition, now);
            }
          }

          if (didEraseAny) {
            _eraserGestureEraseCount = _eraserTool.currentGestureEraseCount;
            _eraserPulseController.forward(from: 0);
            _eraserTool.lastEraseBounds = null;
            DrawingPainter.invalidateAllTiles();
          }
        }
      } // close outer image-edit else

      // 🎯 V3: Update particle positions (gravity + decay)
      _updateEraserParticles(now);

      // Track position and time for next frame
      _lastEraserCanvasPosition = canvasPosition;
      _lastEraserMoveTime = now;

      setState(() {}); // 🏗️ Forza rebuild per eraser cursor overlay
      return;
    }

    // If stiamo disegnando a geometric shape
    if (_effectiveShapeType != ShapeType.freehand &&
        _currentShapeNotifier.value != null) {
      // 📏 Phase 3C: Snap to guides for precision shapes
      final snappedPos =
          _showRulers && _rulerGuideSystem.snapEnabled
              ? _rulerGuideSystem.snapPoint(
                canvasPosition,
                _canvasController.scale,
              )
              : canvasPosition;
      _currentShapeNotifier.value = _currentShapeNotifier.value!.copyWith(
        endPoint: snappedPos,
      );
      return;
    }

    // 🆕 Disegno a mano libera - usa processor appropriato
    if (_is120HzMode && _rawInputProcessor120Hz != null) {
      // 🚀 120Hz MODE: Aggiungi punto direttamente (zero processing)
      final point = ProDrawingPoint(
        position: canvasPosition,
        pressure: pressure.clamp(0.0, 1.0),
        timestamp: DateTime.now().millisecondsSinceEpoch,
        tiltX: tiltX,
        tiltY: tiltY,
        orientation: 0.0,
      );

      // 🚀 FIX #1: Mutazione in-place (zero copie!) + forza repaint
      _currentStrokeNotifier.value.add(point);
      _currentStrokeNotifier.forceRepaint();
    } else {
      // ✅ 60Hz MODE: DrawingInputHandler con smoothing
      _drawingHandler.updateStroke(
        position: canvasPosition,
        pressure: pressure,
        tiltX: tiltX,
        tiltY: tiltY,
        orientation: 0.0,
      );
    }
  }

  void _onDrawEnd(Offset canvasPosition) {
    // Indica che l'utente ha finito di disegnare
    _isDrawingNotifier.value = false;

    // ✏️ PRESENCE: Phase 2 — real-time collaboration
    // if (_isSharedCanvas) {
    //   _presenceService.updateDrawingState(false);
    // }

    // 🪣 Fill mode — no stroke finalization needed
    if (_effectiveIsFill) {
      _isDrawingNotifier.value = false;
      return;
    }

    // 🎨 PRIORITÀ 1: Se siamo in editing mode immagine
    if (_imageInEditMode != null) {
      // ⚠️ Azzera lo stroke of the canvas normale to avoid duplicazioni
      _currentStrokeNotifier.clear();

      // If gomma attiva, non fare nulla (abbiamo already cancellato in Start/Update)
      if (_effectiveIsEraser) {
        return;
      }

      // Only if we have a stroke to save
      if (_drawingHandler.hasStroke) {
        // Complete the stroke on the image
        final finalPoints = _drawingHandler.endStroke();

        // 🔄 FIX: Use LIVE image element to handle resize/move during edit
        // _imageInEditMode is a snapshot - we need the current state from _imageElements
        var activeImage = _imageInEditMode!;
        try {
          activeImage = _imageElements.firstWhere(
            (e) => e.id == _imageInEditMode!.id,
            orElse: () => _imageInEditMode!,
          );
        } catch (_) {}

        // 🔄 Converti le coordinate da assolute a relative all'immagine
        final relativePoints = _convertPointsToImageSpace(
          finalPoints,
          activeImage,
        );

        final stroke = ProStroke(
          id: const Uuid().v4(),
          points: relativePoints,
          color: _effectiveColor,
          baseWidth: _effectiveWidth,
          penType: _effectivePenType,
          createdAt: DateTime.now(),
          settings: _brushSettings, // 🎛️ Passa settings
        );

        setState(() {
          _imageEditingStrokes.add(stroke);
        });

        _currentEditingStrokeNotifier.value = null;

        // 🎤 NOTIFICA ESTERNA (per Sync Recording)
        if (widget.onExternalStrokeAdded != null) {
          final endTime = DateTime.now();
          final startTime = _lastStrokeStartTime ?? endTime;
          widget.onExternalStrokeAdded!(stroke, startTime, endTime);
        }

        // Do not fare auto-save qui, lo faremo when esce from the mode editing
      }
      return;
    }

    // 🖼️ SEMPRE gestisci fine resize/drag di immagini (priority massima)
    if (_imageTool.isResizing) {
      _imageTool.endResize();
      _stopAutoScroll();
      HapticFeedback.lightImpact();
      // 🔄 Sync: notify delta tracker of image update
      if (_imageTool.selectedImage != null) {
        _layerController.updateImage(_imageTool.selectedImage!);
        if (_isSharedCanvas) _snapshotAndPushCloudDeltas();
      }
      // 🔓 SYNC: Unlock element for remote collaborators
      if (_isSharedCanvas) _realtimeSyncManager?.setActiveElement(null);
      setState(() {});
      _autoSaveCanvas();
      return;
    } else if (_imageTool.isDragging) {
      _imageTool.endDrag();
      _stopAutoScroll();
      HapticFeedback.lightImpact();
      // 🔄 Sync: notify delta tracker of image update
      if (_imageTool.selectedImage != null) {
        _layerController.updateImage(_imageTool.selectedImage!);
        if (_isSharedCanvas) _snapshotAndPushCloudDeltas();
      }
      // 🔓 SYNC: Unlock element for remote collaborators
      if (_isSharedCanvas) _realtimeSyncManager?.setActiveElement(null);
      setState(() {});
      _autoSaveCanvas();
      return;
    }

    // 🖼️ Se abbiamo una position iniziale ma non abbiamo mai iniziato il drag,
    // significa che was un tap → enamong then editing mode
    if (_initialTapPosition != null &&
        !_imageTool.isDragging &&
        _imageTool.selectedImage != null) {
      // Find l'selected image
      final selectedImage = _imageTool.selectedImage!;
      final image = _loadedImages[selectedImage.imagePath];

      if (image != null) {
        _enterImageEditMode(selectedImage);
        _initialTapPosition = null;
        return;
      }
    }

    // Reset position iniziale
    if (_initialTapPosition != null) {
      _initialTapPosition = null;
    } // 🎯 SEMPRE gestisci fine resize/drag di digital text (indipendentemente dal tool attivo)
    if (_digitalTextTool.isResizing) {
      _digitalTextTool.endResize();
      HapticFeedback.lightImpact();

      // 🔄 Sync: notifica delta tracker dopo resize
      if (_digitalTextTool.selectedElement != null) {
        _layerController.updateText(_digitalTextTool.selectedElement!);
      }
      setState(() {});

      // 💾 Auto-save dopo resize testo digitale
      _autoSaveCanvas();
      return;
    } else if (_digitalTextTool.isDragging) {
      _digitalTextTool.endDrag();
      _stopAutoScroll();

      // 🔄 Sync: notifica delta tracker dopo drag
      if (_digitalTextTool.selectedElement != null) {
        _layerController.updateText(_digitalTextTool.selectedElement!);
      }
      setState(() {});

      // 💾 Auto-save dopo drag testo digitale
      _autoSaveCanvas();
      return;
    }

    // If il lasso is active, completa il lasso o termina il drag
    if (_effectiveIsLasso) {
      if (_lassoTool.isDragging) {
        _lassoTool.endDrag();
        _stopAutoScroll(); // Ferma l'auto-scroll quando termina il drag
      } else {
        _lassoTool.completeLasso();

        // Feedback tattile e visivo per selezione completata
        if (_lassoTool.hasSelection) {
          HapticFeedback.mediumImpact();
        } else {
          HapticFeedback.lightImpact();
        }
      }

      setState(() {}); // Update per mostrare selected elements
      return;
    }

    // ✒️ PEN TOOL: route pointer-up event
    if (_toolController.isPenToolMode) {
      final screenPos = _canvasController.canvasToScreen(canvasPosition);
      _penTool.onPointerUp(
        _penToolContext,
        PointerUpEvent(position: screenPos),
      );
      setState(() {});
      return;
    }

    // If l'eraser era attivo, finalizza gesture e salva
    if (_effectiveIsEraser) {
      // 🎯 V4: Lasso mode — finalize by erasing everything inside the path
      if (_eraserLassoMode && _eraserLassoPoints.length >= 3) {
        // V5: Animated lasso close — set flag and delay erase for visual feedback
        _eraserLassoAnimating = true;
        _eraserCursorPosition = null;
        _eraserTrail.clear();
        _eraserPreviewIds = {};
        setState(() {});

        // FIX: Entire cleanup chain inside delayed callback to avoid race condition.
        // Previously endGesture() ran synchronously, orphaning undo operations.
        Future.delayed(const Duration(milliseconds: 150), () {
          final eraseCount = _eraserTool.eraseLasso(_eraserLassoPoints);
          if (eraseCount > 0) {
            _eraserGestureEraseCount = eraseCount;
            _eraserPulseController.forward(from: 0);
          }
          _eraserLassoAnimating = false;
          _eraserLassoPoints.clear();
          _eraserGestureEraseCount = 0;
          // Finalize gesture AFTER erase so undo ops are captured
          _eraserTool.endGesture();
          _eraserTool.invalidateSpatialIndex();
          _eraserTool.mergeAdjacentFragments();
          _eraserTool.persistRadius();
          DrawingPainter.invalidateAllTiles();
          _autoSaveCanvas();
          if (mounted) setState(() {});
        });
        return;
      } else if (_eraserLassoMode) {
        _eraserLassoPoints.clear();
      }

      _eraserCursorPosition = null;
      _eraserTrail.clear();
      _eraserPreviewIds = {};
      _eraserGestureEraseCount = 0;
      _eraserTool.endGesture();
      // 🎯 V5: Invalidatete spatial index after mutations
      _eraserTool.invalidateSpatialIndex();
      // 🎯 Persist radius preference on gesture end
      _eraserTool.persistRadius();
      setState(() {}); // 🏗️ Nascondi cursore overlay

      // 🚀 ANR FIX: Defer heavy work off pointer-up frame.
      // mergeAdjacentFragments (O(N) but still allocates) + tile invalidation
      // + SQLite save were running synchronously and blocking >5s → ANR.
      Future.microtask(() {
        _eraserTool.mergeAdjacentFragments();
        DrawingPainter.invalidateAllTiles();
        _autoSaveCanvas();
      });
      return;
    }

    // If abbiamo completato a geometric shape
    if (_effectiveShapeType != ShapeType.freehand &&
        _currentShapeNotifier.value != null) {
      _layerController.addShape(_currentShapeNotifier.value!);
      _currentShapeNotifier.value = null;

      // 💾 AUTO-SAVE dopo aggiunta shape
      _autoSaveCanvas();
      return;
    }

    // 🆕 Disegno a mano libera - finalizza con processor appropriato
    List<ProDrawingPoint> finalPoints;

    if (_is120HzMode && _rawInputProcessor120Hz != null) {
      // 🚀 120Hz MODE: Usa punti direttamente dal notifier (already costruiti)
      if (_currentStrokeNotifier.value.isEmpty) return;

      finalPoints = List.unmodifiable(_currentStrokeNotifier.value);
      _rawInputProcessor120Hz!.reset(); // Reset per prossimo stroke
    } else {
      // ✅ 60Hz MODE: Usa DrawingInputHandler
      if (!_drawingHandler.hasStroke) return;

      finalPoints = _drawingHandler.endStroke();
    }

    // 🎯 FIX: Trim to only the points that were actually rendered on-screen.
    // When PointerMoveEvent and PointerUpEvent arrive in the same event batch,
    // updateStroke() adds a point and schedules forceRepaint(), but _onDrawEnd's
    // clear() cancels that repaint. The last point(s) are never visible to the
    // user but would appear in the finalized stroke → visible "extension".
    // Phase 2: re-enable when using canvas_renderers CurrentStrokePainter
    // final renderedCount = CurrentStrokePainter.lastRenderedCount;
    // if (renderedCount > 0 && renderedCount < finalPoints.length) {
    //   finalPoints = List.unmodifiable(finalPoints.sublist(0, renderedCount));
    // }

    // 🎤 NOTIFICA ESTERNA (per Sync Recording) - PRE-CREATION
    // Salviamo i tempi prima che vengano persi/resetati
    final strokeEndTime = DateTime.now();
    final strokeStartTime = _lastStrokeStartTime ?? strokeEndTime;
    _lastStrokeStartTime = null; // Reset

    // Create stroke completo con valori immutabili
    final stroke = ProStroke(
      id: const Uuid().v4(),
      points: finalPoints,
      color: _effectiveColor,
      baseWidth: _effectiveWidth,
      penType: _effectivePenType,
      createdAt: DateTime.now(),
      settings: _brushSettings, // 🎛️ Passa settings
    );

    // 🎤 NOTIFICA ESTERNA EFFETTIVA
    if (widget.onExternalStrokeAdded != null) {
      widget.onExternalStrokeAdded!(stroke, strokeStartTime, strokeEndTime);
    }

    // 🎯 FIX: Clear live stroke FIRST, then add completed.
    // Previous order caused 1-frame overlap where both live (with ghost trail)
    // and completed strokes rendered simultaneously → visual "pop" on release.
    _currentStrokeNotifier.clear();
    _layerController.addStroke(stroke);

    // 🪞 Phase 5: Symmetry mode — mirror/kaleidoscope stroke
    if (_showRulers && _rulerGuideSystem.symmetryEnabled) {
      // Gather all mirrored point-sets (1 for simple mirror, N-1 for kaleidoscope)
      final mirrorSets = <List<ProDrawingPoint>>[];

      if (_rulerGuideSystem.symmetrySegments <= 2) {
        // Simple single mirror
        final mp = <ProDrawingPoint>[];
        for (final p in finalPoints) {
          final m = _rulerGuideSystem.mirrorPoint(p.position);
          if (m == null) continue;
          mp.add(
            ProDrawingPoint(
              position: m,
              pressure: p.pressure,
              timestamp: p.timestamp,
              tiltX: p.tiltX,
              tiltY: p.tiltY,
              orientation: p.orientation,
            ),
          );
        }
        if (mp.isNotEmpty) mirrorSets.add(mp);
      } else {
        // Kaleidoscope: N-1 reflections
        final segCount = _rulerGuideSystem.symmetrySegments;
        for (int seg = 1; seg < segCount; seg++) {
          final mp = <ProDrawingPoint>[];
          for (final p in finalPoints) {
            final allMirrors = _rulerGuideSystem.mirrorPointMulti(p.position);
            if (seg - 1 < allMirrors.length) {
              mp.add(
                ProDrawingPoint(
                  position: allMirrors[seg - 1],
                  pressure: p.pressure,
                  timestamp: p.timestamp,
                  tiltX: p.tiltX,
                  tiltY: p.tiltY,
                  orientation: p.orientation,
                ),
              );
            }
          }
          if (mp.isNotEmpty) mirrorSets.add(mp);
        }
      }

      for (final pts in mirrorSets) {
        final mirroredStroke = ProStroke(
          id: const Uuid().v4(),
          points: pts,
          color: stroke.color,
          baseWidth: stroke.baseWidth,
          penType: stroke.penType,
          createdAt: stroke.createdAt,
          settings: stroke.settings,
        );
        _layerController.addStroke(mirroredStroke);
      }
    }

    // 💾 Defer persistence to microtask (non blocca pen-up frame)
    Future.microtask(() {
      StrokePersistenceService.instance.saveStroke(stroke).then((_) {
        final tier = StrokePersistenceService.instance.currentTier;
        if (tier == 'TIER 4 (DISK)') {}
      });
    });

    // 📊 Notifica stroke completato per debounce adattivo
    AdaptiveDebouncerService.instance.notifyStrokeCompleted();

    // 🎤 Se stiamo registrando con tratti (interno), aggiungi stroke al builder
    if (_isRecordingAudio &&
        _recordingWithStrokes &&
        _syncRecordingBuilder != null) {
      // 🐛 FIX: Set esplicitamente tipo 'note' per nascondere etichetta "Page X"
      _syncRecordingBuilder!.setRecordingType('note');

      _syncRecordingBuilder!.addStroke(
        stroke,
        _currentStrokeStartTime ?? strokeEndTime,
        strokeEndTime,
      );
      // _currentStrokeStartTime viene resettato dopo
    }
    _currentStrokeStartTime = null;

    // 💾 Auto-save
    _autoSaveCanvas();
  }

  // ============================================================================
  // AUTO-SCROLL DURANTE IL DRAG
  // ============================================================================

  /// Start l'auto-scroll se necessario (vicino ai bordi)
  void _startAutoScrollIfNeeded(Offset screenPosition, Size screenSize) {
    // Ferma timer esistente
    _autoScrollTimer?.cancel();

    // Calculate distanza dai bordi
    final distanceFromLeft = screenPosition.dx;
    final distanceFromRight = screenSize.width - screenPosition.dx;
    final distanceFromTop = screenPosition.dy;
    final distanceFromBottom = screenSize.height - screenPosition.dy;

    // Determina direzione dello scroll
    double scrollX = 0.0;
    double scrollY = 0.0;

    if (distanceFromLeft < _NebulaCanvasScreenState._edgeScrollThreshold) {
      scrollX =
          _NebulaCanvasScreenState
              ._scrollSpeed; // Scroll verso destra (offset positivo)
    } else if (distanceFromRight <
        _NebulaCanvasScreenState._edgeScrollThreshold) {
      scrollX =
          -_NebulaCanvasScreenState
              ._scrollSpeed; // Scroll verso sinistra (offset negativo)
    }

    if (distanceFromTop < _NebulaCanvasScreenState._edgeScrollThreshold) {
      scrollY =
          _NebulaCanvasScreenState
              ._scrollSpeed; // Scroll verso il basso (offset positivo)
    } else if (distanceFromBottom <
        _NebulaCanvasScreenState._edgeScrollThreshold) {
      scrollY =
          -_NebulaCanvasScreenState
              ._scrollSpeed; // Scroll verso l'alto (offset negativo)
    }

    // If c'è scroll, avvia il timer
    if (scrollX != 0.0 || scrollY != 0.0) {
      _autoScrollTimer = Timer.periodic(const Duration(milliseconds: 16), (
        timer,
      ) {
        // Muovi il canvas
        final currentOffset = _canvasController.offset;
        final newOffset = Offset(
          currentOffset.dx + scrollX,
          currentOffset.dy + scrollY,
        );
        _canvasController.setOffset(newOffset);

        // Compensatete the scroll muovendo gli elementi in the direction OPPOSTA
        // Quando il canvas scorre a destra (+scrollX), gli elementi devono andare a sinistra (-scrollX)
        // to remain visivamente nella stessa position sullo schermo
        final compensation = Offset(-scrollX, -scrollY);

        if (_lassoTool.isDragging) {
          _lassoTool.compensateScroll(compensation);
        }

        // Digital text: compensa nel tool E aggiorna la lista
        if (_digitalTextTool.isDragging || _digitalTextTool.isResizing) {
          _digitalTextTool.compensateScroll(compensation);

          // Update element in the list to synchronize
          if (_digitalTextTool.selectedElement != null) {
            final index = _digitalTextElements.indexWhere(
              (e) => e.id == _digitalTextTool.selectedElement!.id,
            );
            if (index != -1) {
              _digitalTextElements[index] = _digitalTextTool.selectedElement!;
            }
          }
        }

        // 🖼️ Image: compensa nel tool E aggiorna la lista
        if (_imageTool.isDragging || _imageTool.isResizing) {
          _imageTool.compensateScroll(compensation);

          // Update element in the list to synchronize
          if (_imageTool.selectedImage != null) {
            final index = _imageElements.indexWhere(
              (e) => e.id == _imageTool.selectedImage!.id,
            );
            if (index != -1) {
              _imageElements[index] = _imageTool.selectedImage!;
            }
          }
        }

        setState(() {}); // Forza rebuild per aggiornare position
      });
    }
  }

  /// Ferma l'auto-scroll
  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
  }

  /// 🪣 Phase 3D: Execute flood fill at the given canvas position
  Future<void> _executeFloodFill(Offset canvasPosition) async {
    // Get the current canvas size from context
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final viewportSize = renderBox.size;
    final rasterWidth = viewportSize.width.toInt();
    final rasterHeight = viewportSize.height.toInt();

    if (rasterWidth <= 0 || rasterHeight <= 0) return;

    // Rasterize visible canvas to an image using PictureRecorder
    final recorder = ui.PictureRecorder();
    final recordCanvas = ui.Canvas(recorder);

    // Apply canvas transform (offset + scale)
    final canvasScale = _canvasController.scale;
    final canvasOffset = _canvasController.offset;
    recordCanvas.scale(canvasScale);
    recordCanvas.translate(canvasOffset.dx, canvasOffset.dy);

    // Draw all strokes from the active layer
    final activeLayer = _layerController.activeLayer;
    if (activeLayer != null) {
      for (final stroke in activeLayer.strokes) {
        _drawStrokeForRasterization(recordCanvas, stroke);
      }
    }

    final picture = recorder.endRecording();
    final rasterImage = await picture.toImage(rasterWidth, rasterHeight);

    // Convert canvas position to screen/raster coordinates
    final screenPos = _canvasController.canvasToScreen(canvasPosition);
    final rasterPoint = Offset(
      screenPos.dx.clamp(0.0, rasterWidth - 1.0),
      screenPos.dy.clamp(0.0, rasterHeight - 1.0),
    );

    // Update fill color from current selected color
    final fillColor = _effectiveColor;
    _floodFillTool.fillColor = fillColor;

    // Execute flood fill
    final mask = await _floodFillTool.executeFloodFill(
      rasterImage,
      rasterPoint,
    );
    if (mask == null) {
      rasterImage.dispose();
      return;
    }

    // Generate filled image
    final fillImage = await _floodFillTool.generateFillImage(
      mask,
      rasterWidth,
      rasterHeight,
      fillColor,
    );
    if (fillImage == null) {
      rasterImage.dispose();
      return;
    }

    // Calculate canvas-space bounds for the fill overlay
    // The fill image is in screen space; we need to know where it maps in canvas space
    // Screen → Canvas: canvasPos = screenPos / scale - offset
    final canvasBounds = Rect.fromLTWH(
      -canvasOffset.dx,
      -canvasOffset.dy,
      rasterWidth / canvasScale,
      rasterHeight / canvasScale,
    );

    // Create a fill stroke with the overlay attached
    final fillStroke = ProStroke(
      id: const Uuid().v4(),
      points: [
        ProDrawingPoint(
          position: canvasPosition,
          pressure: 1.0,
          tiltX: 0.0,
          tiltY: 0.0,
          orientation: 0.0,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ),
      ],
      color: fillColor,
      baseWidth: 1.0,
      penType: ProPenType.ballpoint,
      createdAt: DateTime.now(),
      fillOverlay: fillImage, // 🪣 Attach the fill raster overlay
      fillBounds: canvasBounds, // 🪣 Canvas-space position for rendering
    );

    // Add the fill stroke to the active layer
    _layerController.addStroke(fillStroke);

    setState(() {});

    // Dispose only the rasterized source image (the fill overlay stays alive on the stroke)
    rasterImage.dispose();
  }

  /// Helper: Draw a stroke on a ui.Canvas for rasterization purposes
  void _drawStrokeForRasterization(ui.Canvas canvas, ProStroke stroke) {
    if (stroke.points.isEmpty) return;

    final paint =
        Paint()
          ..color = stroke.color
          ..strokeWidth = stroke.baseWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke;

    if (stroke.points.length == 1) {
      final pos = stroke.points.first.position;
      canvas.drawCircle(
        pos,
        stroke.baseWidth / 2,
        paint..style = PaintingStyle.fill,
      );
      return;
    }

    final path = Path();
    path.moveTo(
      stroke.points.first.position.dx,
      stroke.points.first.position.dy,
    );
    for (int i = 1; i < stroke.points.length; i++) {
      final prev = stroke.points[i - 1].position;
      final curr = stroke.points[i].position;
      final mid = Offset((prev.dx + curr.dx) / 2, (prev.dy + curr.dy) / 2);
      path.quadraticBezierTo(prev.dx, prev.dy, mid.dx, mid.dy);
    }
    path.lineTo(stroke.points.last.position.dx, stroke.points.last.position.dy);
    canvas.drawPath(path, paint);
  }

  // ─── V3: Eraser Particle System ──────────────────────────────────

  /// Spawn particles at the erase intersection point
  void _spawnEraserParticles(Offset position, int now) {
    final random = DateTime.now().microsecond;
    for (int i = 0; i < 6; i++) {
      // Pseudo-random velocity using microsecond seed
      final angle = (random + i * 60) * 0.0174533; // Convert to radians
      final speed = 0.5 + (((random + i * 37) % 100) / 100.0) * 1.5;
      _eraserParticles.add(
        _EraserParticle(
          position: position,
          velocity: Offset(
            speed * (angle.isNaN ? 1.0 : (i.isEven ? 1 : -1) * speed * 0.7),
            -speed * 0.5 - (((random + i * 13) % 100) / 100.0) * 1.0,
          ),
          createdAt: now,
          size: 1.5 + (((random + i * 23) % 100) / 100.0) * 2.5,
        ),
      );
    }
    // Cap total particles
    if (_eraserParticles.length > 60) {
      _eraserParticles.removeRange(0, _eraserParticles.length - 60);
    }
  }

  /// Update particle positions: gravity, decay, and cleanup
  void _updateEraserParticles(int now) {
    _eraserParticles.removeWhere((p) {
      final age = now - p.createdAt;
      if (age > 500) return true; // Remove after 500ms
      // Update position with velocity + gravity
      p.position = Offset(
        p.position.dx + p.velocity.dx,
        p.position.dy + p.velocity.dy + (age * 0.003), // Gravity
      );
      p.opacity = (1.0 - (age / 500.0)).clamp(0.0, 1.0);
      return false;
    });
  }

  // ═════════════════════════════════════════════════════════════════════
  // V4: PINCH-TO-RESIZE ERASER
  // ═════════════════════════════════════════════════════════════════════

  /// Call when a scale gesture starts while eraser is active
  void _onEraserPinchStart() {
    _eraserPinchBaseRadius = _eraserTool.eraserRadius;
  }

  /// Call with scale factor during pinch — resizes eraser radius
  void _onEraserPinchUpdate(double scale) {
    if (_eraserPinchBaseRadius == null) return;
    final newRadius = (_eraserPinchBaseRadius! * scale).clamp(
      EraserTool.minRadius,
      EraserTool.maxRadius,
    );
    _eraserTool.eraserRadius = newRadius;
    _eraserSmoothedRadius = newRadius;
    setState(() {});
  }

  /// Call when scale gesture ends — persist the new radius
  void _onEraserPinchEnd() {
    _eraserPinchBaseRadius = null;
    _eraserTool.persistRadius();
  }
}
