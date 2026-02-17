part of '../../nebula_canvas_screen.dart';

/// 📦 Drawing End — pointer-up finalization, stroke save, symmetry mirror
extension on _NebulaCanvasScreenState {
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
}
