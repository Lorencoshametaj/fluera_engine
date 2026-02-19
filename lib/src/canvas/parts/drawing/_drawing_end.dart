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
        _drawingHandler.endStroke();

        // 🚀 Fix 1: use pre-accumulated converted points (O(1) instead of O(n))
        // These are the exact points the user saw during drawing.
        final relativePoints = List<ProDrawingPoint>.from(
          _editingConvertedPoints,
        );

        final stroke = ProStroke(
          id: const Uuid().v4(),
          points: relativePoints,
          color: _effectiveColor,
          baseWidth: _effectiveWidth,
          penType: _effectivePenType,
          createdAt: _editingStrokeCreatedAt,
          settings: _brushSettings,
        );

        setState(() {
          _imageEditingStrokes.add(stroke);
          // 🧠 Fix 7: new stroke invalidates redo history
          _imageEditingUndoStack.clear();
        });

        // Clean up accumulator
        _editingConvertedPoints.clear();
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

    // 🖼️ ALWAYS handle end of resize/drag of images (max priority)
    if (_imageTool.isResizing) {
      _imageTool.endResize();
      _stopAutoScroll();
      HapticFeedback.lightImpact();
      // 🧠 Cache coherency: bump version + rebuild R-tree after resize
      _imageVersion++;
      _rebuildImageSpatialIndex();
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
      _clearSmartGuides();
      HapticFeedback.lightImpact();
      // 🧠 Cache coherency: bump version + rebuild R-tree after drag
      _imageVersion++;
      _rebuildImageSpatialIndex();
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

    // 🖼️ If we have an initial position but never started drag,
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

    // Reset initial tap position
    if (_initialTapPosition != null) {
      _initialTapPosition = null;
    }
    // 🎯 Always handle digital text resize/drag end (regardless of active tool)
    if (_digitalTextTool.isResizing) {
      _digitalTextTool.endResize();
      HapticFeedback.lightImpact();

      // Sync updated element to list + layer controller
      if (_digitalTextTool.selectedElement != null) {
        _syncTextElementFromTool(_digitalTextTool.selectedElement!);
      }
      setState(() {});

      // 💾 Auto-save after resizing digital text
      _autoSaveCanvas();
      return;
    } else if (_digitalTextTool.isDragging) {
      _digitalTextTool.endDrag();
      _clearSmartGuides();
      _stopAutoScroll();

      // Sync updated element to list + layer controller
      if (_digitalTextTool.selectedElement != null) {
        _syncTextElementFromTool(_digitalTextTool.selectedElement!);
      }
      setState(() {});

      // 💾 Auto-save after dragging digital text
      _autoSaveCanvas();
      return;
    }

    // If il lasso is active, completa il lasso o termina il drag
    if (_effectiveIsLasso) {
      if (_lassoTool.isDragging) {
        _lassoTool.endDrag();
        _clearSmartGuides();
        _stopAutoScroll(); // Stop auto-scroll when drag ends

        // 🔧 FIX: Invalidate tile cache so final position is rendered correctly
        DrawingPainter.invalidateAllTiles();

        // 💾 Persist the moved elements
        _autoSaveCanvas();
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
      // 🎯 V5: Invalidate spatial index after mutations
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

      // 💾 AUTO-SAVE after adding shape
      _autoSaveCanvas();
      return;
    }

    // 🆕 Disegno a mano libera - finalizza con processor appropriato
    List<ProDrawingPoint> finalPoints;

    if (_is120HzMode && _rawInputProcessor120Hz != null) {
      // 🚀 120Hz MODE: Use points directly from notifier (already built)
      if (_currentStrokeNotifier.value.isEmpty) return;

      finalPoints = List.unmodifiable(_currentStrokeNotifier.value);
      _rawInputProcessor120Hz!.reset(); // Reset per prossimo stroke
    } else {
      // ✅ 60Hz MODE: Usa DrawingInputHandler
      if (!_drawingHandler.hasStroke) return;

      finalPoints = _drawingHandler.endStroke();
    }

    // 🎯 NOTE: Point trimming to rendered count disabled.
    // When PointerMoveEvent and PointerUpEvent arrive in the same event batch,
    // the last point(s) may not be visible. Re-enable if needed in the future.

    // 🔷 Shape Recognition: check if freehand stroke matches a geometric shape
    if (_toolController.shapeRecognitionEnabled) {
      final positions = finalPoints.map((p) => p.position).toList();
      final sensitivity = _toolController.shapeRecognitionSensitivity;

      // Try single-stroke recognition first
      var result = ShapeRecognizer.recognize(
        positions,
        sensitivity: sensitivity,
      );

      // 🔀 Multi-stroke: if single stroke didn't match,
      // buffer it and try combining with recent strokes
      if (!result.recognizedAt(sensitivity.threshold)) {
        _toolController.bufferStroke(positions);
        final combined = _toolController.getMultiStrokePoints();
        if (combined != null) {
          result = ShapeRecognizer.recognize(
            combined,
            sensitivity: sensitivity,
          );
        }
      }

      if (result.recognizedAt(sensitivity.threshold)) {
        final shape = GeometricShape(
          id: const Uuid().v4(),
          type: result.type!,
          startPoint: result.boundingBox.topLeft,
          endPoint: result.boundingBox.bottomRight,
          color: _effectiveColor,
          strokeWidth: _effectiveWidth,
          filled: false,
          createdAt: DateTime.now(),
          rotation: result.rotationAngle,
        );

        // 👻 Ghost mode: show preview before committing
        if (_toolController.ghostSuggestionMode) {
          _currentStrokeNotifier.clear();
          _showGhostSuggestion(shape, result);
          return;
        }

        // Immediate commit
        _currentStrokeNotifier.clear();
        _layerController.addShape(shape);
        _toolController.clearMultiStrokeBuffer();
        HapticFeedback.mediumImpact();
        DrawingPainter.invalidateAllTiles();
        _showShapeRecognitionToast(result);
        _autoSaveCanvas();
        return;
      }
    }

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

    // 🌊 REFLOW: Incrementally update cluster cache with new stroke
    if (_clusterDetector != null) {
      final activeLayer = _layerController.layers.firstWhere(
        (l) => l.id == _layerController.activeLayerId,
        orElse: () => _layerController.layers.first,
      );
      _clusterCache = _clusterDetector!.addStroke(
        _clusterCache,
        stroke,
        activeLayer.strokes,
      );
      _lassoTool.updateClusterCache(_clusterCache);
    }

    // 🚀 Incremental tile cache update: only re-rasterize affected tiles
    // instead of invalidating the entire tile cache.
    final dpr = MediaQuery.of(context).devicePixelRatio;
    DrawingPainter.incrementalUpdateForStroke(stroke, dpr);

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

    // 📊 Notify stroke completed for adaptive debounce
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
      // _currentStrokeStartTime is reset after
    }
    _currentStrokeStartTime = null;

    // 💾 Auto-save
    _autoSaveCanvas();
  }

  // ---------------------------------------------------------------------------
  // Chaikin subdivision — one-pass corner-cutting for smoother curves
  // ---------------------------------------------------------------------------

  /// Apply one pass of Chaikin's corner-cutting algorithm to smooth a stroke.
  ///
  /// For each pair of adjacent points, generates two new points at 25% and 75%
  /// of the segment. Pressure, tilt, and orientation are linearly interpolated.
  /// First and last points are preserved to maintain stroke endpoints.
  List<ProDrawingPoint> _chaikinSmooth(List<ProDrawingPoint> points) {
    if (points.length < 3) return points;

    final result = <ProDrawingPoint>[points.first];

    for (int i = 0; i < points.length - 1; i++) {
      final p0 = points[i];
      final p1 = points[i + 1];

      // Q = 0.75 * P0 + 0.25 * P1
      result.add(
        ProDrawingPoint(
          position: Offset(
            p0.position.dx * 0.75 + p1.position.dx * 0.25,
            p0.position.dy * 0.75 + p1.position.dy * 0.25,
          ),
          pressure: p0.pressure * 0.75 + p1.pressure * 0.25,
          tiltX: p0.tiltX * 0.75 + p1.tiltX * 0.25,
          tiltY: p0.tiltY * 0.75 + p1.tiltY * 0.25,
          orientation: p0.orientation * 0.75 + p1.orientation * 0.25,
          timestamp:
              p0.timestamp + ((p1.timestamp - p0.timestamp) * 0.25).round(),
        ),
      );

      // R = 0.25 * P0 + 0.75 * P1
      result.add(
        ProDrawingPoint(
          position: Offset(
            p0.position.dx * 0.25 + p1.position.dx * 0.75,
            p0.position.dy * 0.25 + p1.position.dy * 0.75,
          ),
          pressure: p0.pressure * 0.25 + p1.pressure * 0.75,
          tiltX: p0.tiltX * 0.25 + p1.tiltX * 0.75,
          tiltY: p0.tiltY * 0.25 + p1.tiltY * 0.75,
          orientation: p0.orientation * 0.25 + p1.orientation * 0.75,
          timestamp:
              p0.timestamp + ((p1.timestamp - p0.timestamp) * 0.75).round(),
        ),
      );
    }

    result.add(points.last);
    return List.unmodifiable(result);
  }
}
