part of '../../fluera_canvas_screen.dart';

/// 📦 Drawing End — pointer-up finalization, stroke save, symmetry mirror
extension on _FlueraCanvasScreenState {
  void _onDrawEnd(Offset canvasPosition) {
    // Indica che l'utente ha finito di disegnare
    _isDrawingNotifier.value = false;
    _pushConsciousContext(); // 🧠 Notify intelligence subsystems

    // 📌 PIN DRAG END: Finalize pin position
    if (_draggingPinId != null) {
      _handleRecordingPinDragEnd(canvasPosition);
      return;
    }

    // 📐 SECTION MODE: Show customization dialog then commit
    if (_isSectionActive && _sectionStartPoint != null) {
      final start = _sectionStartPoint!;
      final end = _sectionCurrentEndPoint ?? canvasPosition;
      final sectionRect = Rect.fromPoints(start, end);

      // Clear preview immediately
      _sectionStartPoint = null;
      _sectionCurrentEndPoint = null;
      setState(() {});

      // Minimum size check — if large enough, create new section
      if (sectionRect.width >= 20 && sectionRect.height >= 20) {
        _showSectionCustomizationSheet(sectionRect);
      } else {
        // Small gesture = tap — try to select an existing section
        final tappedSection = _findSectionAtPoint(canvasPosition);
        if (tappedSection != null) {
          HapticFeedback.selectionClick();
          _showSectionEditSheet(tappedSection);
        }
      }
      return;
    }

    // ☁️ PRESENCE: Clear drawing state for collaborators
    if (_isSharedCanvas && _realtimeEngine != null) {
      _broadcastCursorPosition(canvasPosition, isDrawing: false);
    }

    // 📄 PDF DOCUMENT DRAG: End whole-document drag
    if (_pdfPageDragController.isDraggingDocument) {
      final parentDoc = _pdfPageDragController.parentDocument;
      final activeLayer = _layerController.layers.firstWhere(
        (l) => l.id == _layerController.activeLayerId,
        orElse: () => _layerController.layers.first,
      );
      _pdfPageDragController.endDocumentDrag(layerNode: activeLayer.node);
      DrawingPainter.invalidateAllTiles();
      _pdfLayoutVersion++;
      _isDrawingNotifier.value = false;

      // 📡 Broadcast document move to collaborators
      if (_realtimeEngine != null && parentDoc != null) {
        final origin = parentDoc.documentModel.gridOrigin;
        _realtimeEngine!.broadcastPdfUpdated(
          documentId: parentDoc.id.toString(),
          subAction: 'documentMoved',
          data: {'originX': origin.dx, 'originY': origin.dy},
        );
      }

      setState(() {});
      _autoSaveCanvas();
      return;
    }

    // 📄 PDF PAGE DRAG: End drag and save position
    // Strokes were already translated in real-time during _onDrawUpdate,
    // so we only need to finalize the page position and invalidate caches.
    if (_pdfPageDragController.isDragging) {
      final draggedPage = _pdfPageDragController.draggingPage;
      _pdfPageDragController.endDrag();
      // Invalidate tile cache to prevent ghost copies (stale tiles showing
      // the page at its pre-drag position after re-lock).
      DrawingPainter.invalidateAllTiles();
      _pdfLayoutVersion++;
      _isDrawingNotifier.value = false;

      // 📡 Broadcast page move to collaborators
      if (_realtimeEngine != null && draggedPage != null) {
        final pos = draggedPage.position;
        _realtimeEngine!.broadcastPdfUpdated(
          documentId:
              (draggedPage.parent as PdfDocumentNode?)?.id.toString() ?? '',
          subAction: 'pageMoved',
          data: {
            'pageIndex': draggedPage.pageModel.pageIndex,
            'dx': pos.dx,
            'dy': pos.dy,
          },
        );
      }

      setState(() {});
      _autoSaveCanvas();
      return;
    }

    // 🪣 Fill mode — no stroke finalization needed
    if (_effectiveIsFill) {
      _isDrawingNotifier.value = false;
      return;
    }

    // 🌀 End single-finger handle rotation (pan mode only)
    if (_effectiveIsPanMode && _imageTool.isHandleRotating) {
      _imageTool.endHandleRotation();
      _imageVersion++;
      _rebuildImageSpatialIndex();
      if (_imageTool.selectedImage != null) {
        _layerController.updateImage(_imageTool.selectedImage!);
        // 🔴 RT: Broadcast image rotation to collaborators
        _broadcastImageUpdate(_imageTool.selectedImage!);
      }
      setState(() {});
      return;
    }

    // 🖼️ ALWAYS handle end of resize/drag of images (pan mode only)
    if (_effectiveIsPanMode && _imageTool.isResizing) {
      _imageTool.endResize();
      _stopAutoScroll();
      HapticFeedback.lightImpact();
      _imageVersion++;
      _rebuildImageSpatialIndex();
      if (_imageTool.selectedImage != null) {
        _layerController.updateImage(_imageTool.selectedImage!);
        _broadcastImageUpdate(_imageTool.selectedImage!);
      }
      setState(() {});
      _autoSaveCanvas();
      return;
    } else if (_effectiveIsPanMode && _imageTool.isDragging) {
      _imageTool.endDrag();
      _stopAutoScroll();
      _clearSmartGuides();
      HapticFeedback.lightImpact();
      _imageVersion++;
      _rebuildImageSpatialIndex();
      if (_imageTool.selectedImage != null) {
        _layerController.updateImage(_imageTool.selectedImage!);
        _broadcastImageUpdate(_imageTool.selectedImage!);
      }
      setState(() {});
      _autoSaveCanvas();
      return;
    }

    // 🖼️ If we have an initial position but never started drag (pan mode),
    // it was a tap — clear and reset
    if (_effectiveIsPanMode &&
        _initialTapPosition != null &&
        !_imageTool.isDragging &&
        _imageTool.selectedImage != null) {
      _initialTapPosition = null;
      return;
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

    // 📊 TabularNode drag end
    if (_tabularTool.isDragging) {
      _tabularTool.endDrag();
      _layerController.sceneGraph.bumpVersion();
      DrawingPainter.invalidateAllTiles();
      HapticFeedback.lightImpact();
      setState(() {});
      _autoSaveCanvas();
      return;
    }

    // 📊 TabularNode resize end
    if (_tabularTool.isResizing) {
      final result = _tabularTool.endResize();
      if (result != null && _tabularTool.selectedTabular != null) {
        final node = _tabularTool.selectedTabular!;
        if (result.isColumn) {
          _commandHistory.execute(
            SetColumnWidthCommand(
              node: node,
              column: result.index,
              newWidth: result.newSize,
            ),
          );
        } else {
          _commandHistory.execute(
            SetRowHeightCommand(
              node: node,
              row: result.index,
              newHeight: result.newSize,
            ),
          );
        }
      }
      _layerController.sceneGraph.bumpVersion();
      DrawingPainter.invalidateAllTiles();
      HapticFeedback.lightImpact();
      setState(() {});
      _autoSaveCanvas();
      return;
    }

    // 🧮 LatexNode drag end
    if (_isDraggingLatex) {
      _isDraggingLatex = false;
      _latexDragStart = null;
      HapticFeedback.lightImpact();
      _layerController.sceneGraph.bumpVersion();
      DrawingPainter.invalidateAllTiles();
      setState(() {});
      _autoSaveCanvas();
      return;
    }

    // If il lasso is active, completa il lasso o termina il drag
    if (_effectiveIsLasso) {
      if (_lassoTool.isDragging) {
        _lassoTool.endDrag();
        _clearSmartGuides();
        _stopAutoScroll(); // Stop auto-scroll when drag ends

        // 📄 Re-link moved strokes to their new PDF pages
        _relinkStrokesToPdfPages(_lassoTool.selectedIds);

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
          // 📄 Clean up orphaned PDF annotation IDs
          _reconcilePdfAnnotations();
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
        // 📄 Clean up orphaned PDF annotation IDs after erase
        _reconcilePdfAnnotations();
        DrawingPainter.invalidateAllTiles();
        _autoSaveCanvas();
      });
      return;
    }

    // If abbiamo completato a geometric shape
    if (_effectiveShapeType != ShapeType.freehand &&
        _currentShapeNotifier.value != null) {
      final shape = _currentShapeNotifier.value!;
      _layerController.addShape(shape);
      _currentShapeNotifier.value = null;

      // 🎨 Style Coherence: learn shape style
      EngineScope.current.styleCoherenceEngine.recordStyleUsage(
        'shape',
        color: shape.color,
        strokeWidth: shape.strokeWidth,
        opacity: _effectiveOpacity,
      );

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

    // 🎯 SNAP FIX: Trim finalPoints to the count actually rendered on-screen.
    // This prevents "forward snap" from unrendered tail points that arrived
    // in the same event batch as pointer-up (never visible to the user).
    final renderedCount = CurrentStrokePainter.lastRenderedCount;
    if (renderedCount > 2 && renderedCount < finalPoints.length) {
      finalPoints = List.unmodifiable(finalPoints.sublist(0, renderedCount));
    }

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
          id: generateUid(),
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
      id: generateUid(),
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

    // 🎯 SNAP FIX: Add finalized stroke and update tile cache BEFORE
    // clearing the live stroke. Previous order (clear → add → tiles)
    // caused a 1-frame gap where neither live nor finalized was visible.
    // New order: add → tiles → clear ensures seamless handoff.
    // The SNAP FIX (trim to renderedCount above) prevents elongation
    // from unrendered tail points.

    // 🖼️ IMAGE STROKE ROUTING: If stroke started on an image, attach it
    // to the image's drawingStrokes instead of the canvas layer.
    ImageElement? targetImage;
    if (stroke.points.isNotEmpty) {
      final firstPoint = stroke.points.first.position;
      for (int i = 0; i < _imageElements.length; i++) {
        final img = _imageElements[i];
        final loadedImg = _loadedImages[img.imagePath];
        if (loadedImg == null) continue;
        final w = loadedImg.width.toDouble();
        final h = loadedImg.height.toDouble();
        final halfW = w * img.scale / 2;
        final halfH = h * img.scale / 2;
        // position is CENTER of the image (matches ImagePainter)
        final imageRect = Rect.fromCenter(
          center: img.position,
          width: halfW * 2,
          height: halfH * 2,
        );
        if (imageRect.contains(firstPoint)) {
          targetImage = img;
          break;
        }
      }
    }

    if (targetImage != null) {
      // 🖼️ Stroke belongs to the image — convert to image-local coordinates
      final idx = _imageElements.indexWhere((e) => e.id == targetImage!.id);
      if (idx != -1) {
        final img = _imageElements[idx];
        // Transform: canvas → image-local
        // 🐛 FIX: Only un-translate + un-rotate, do NOT apply invScale!
        //    Velocity-based brushes (fountain pen) compute width from
        //    inter-point distances. Multiplying positions by invScale
        //    inflates distances (e.g., 8.6× for scale=0.116), causing
        //    the brush to over-thin the stroke. Strokes are stored in
        //    un-translated, un-rotated canvas space and rendered with
        //    translate + rotate only (no canvas.scale for strokes).
        final cosR = math.cos(-img.rotation);
        final sinR = math.sin(-img.rotation);

        debugPrint(
          '[🐛 IMG-STROKE] canvas baseWidth=${stroke.baseWidth}, imgScale=${img.scale}',
        );

        final localPoints =
            stroke.points.map((p) {
              // 1. Un-translate
              final dx = p.position.dx - img.position.dx;
              final dy = p.position.dy - img.position.dy;
              // 2. Un-rotate
              final rx = dx * cosR - dy * sinR;
              final ry = dx * sinR + dy * cosR;
              // 3. NO invScale — preserve canvas-space distances
              return p.copyWith(position: Offset(rx, ry));
            }).toList();

        final localStroke = stroke.copyWith(
          points: localPoints,
          baseWidth: stroke.baseWidth, // NO invScale
          referenceScale: img.scale, // 🖼️ Store image scale at draw time
        );
        final updated = _imageElements[idx].copyWith(
          drawingStrokes: [..._imageElements[idx].drawingStrokes, localStroke],
        );
        _imageElements[idx] = updated;
        _layerController.updateImage(updated);
        _imageVersion++;
        _imageRepaintNotifier.value++;
        // 🔴 RT: Broadcast as image update (includes drawingStrokes)
        _broadcastImageUpdate(updated);
      }
    } else {
      // Regular canvas stroke
      _layerController.addStroke(stroke);
      // 🔴 RT: Broadcast completed stroke to collaborators
      _broadcastStrokeAdded(stroke);
    }

    // 🚀 Incremental tile cache update: ensure tiles contain the stroke
    // BEFORE clearing the live version.
    final dpr = MediaQuery.of(context).devicePixelRatio;
    DrawingPainter.incrementalUpdateForStroke(stroke, dpr);

    // NOW safe to clear the live stroke — finalized is already painted
    _currentStrokeNotifier.clear();

    // 🎨 Style Coherence: learn freehand stroke style
    EngineScope.current.styleCoherenceEngine.recordStyleUsage(
      _consciousToolName(),
      color: stroke.color,
      strokeWidth: stroke.baseWidth,
      opacity: _effectiveOpacity,
    );

    // 📄 PDF Annotation Linking: if stroke overlaps a PDF page, link it
    _linkStrokeToPdfPage(stroke);

    // ✂️ Clear PDF clip rect now that the stroke is finalized
    _activePdfClipRect = null;

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
      _lassoTool.reflowController?.updateClusters(_clusterCache);
    }

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
          id: generateUid(),
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
      final strokeSvc =
          EngineScope.current.drawingModule?.strokePersistenceService;
      strokeSvc?.saveStroke(stroke).then((_) {
        final tier = strokeSvc.currentTier;
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

  /// 📄 Translate all annotation strokes matching [annotationIds] by [delta].
  ///
  /// Creates new ProStroke instances with translated point positions and
  /// replaces them on their StrokeNode. This ensures strokes follow
  /// their linked PDF page when it's dragged to a new position.
  void _translateAnnotationStrokes(Set<String> annotationIds, Offset delta) {
    if (annotationIds.isEmpty || delta == Offset.zero) return;

    for (final layer in _layerController.layers) {
      for (final strokeNode in layer.node.strokeNodes) {
        if (annotationIds.contains(strokeNode.stroke.id)) {
          final old = strokeNode.stroke;
          // Create translated points
          final translatedPoints =
              old.points.map((p) {
                return p.copyWith(position: p.position + delta);
              }).toList();
          // Replace stroke data on the node (new ProStroke = fresh bounds cache)
          strokeNode.stroke = old.copyWith(points: translatedPoints);
        }
      }
    }
  }

  // ===========================================================================
  // 📐 SECTION SELECTION — Find and edit existing sections
  // ===========================================================================

  /// Walk the scene graph and return the first SectionNode whose world bounds
  /// contain [canvasPoint], or null.
  SectionNode? _findSectionAtPoint(Offset canvasPoint) {
    final sceneGraph = _layerController.sceneGraph;
    for (final layer in sceneGraph.layers) {
      for (final child in layer.children.reversed) {
        if (child is SectionNode && child.isVisible) {
          final inverse = Matrix4.tryInvert(child.worldTransform);
          if (inverse == null) continue;
          final local = MatrixUtils.transformPoint(inverse, canvasPoint);
          if (child.localBounds.contains(local)) return child;
        }
      }
    }
    return null;
  }

  /// Show an edit sheet for an existing section.
  void _showSectionEditSheet(SectionNode section) {
    final nameController = TextEditingController(text: section.sectionName);

    // Same color presets as creation
    const colorPresets = <Color?>[
      null,
      Color(0xFFFFFFFF),
      Color(0xFFF5F5F5),
      Color(0xFF1E1E2E),
      Color(0x1A2196F3),
      Color(0x1AFF9800),
      Color(0x1A4CAF50),
      Color(0x1AE91E63),
      Color(0x1A9C27B0),
      Color(0x1A00BCD4),
    ];

    Color? selectedColor = section.backgroundColor;
    bool showGrid = section.showGrid;
    bool clipContent = section.clipContent;
    int subdivRows = section.subdivisionRows;
    int subdivColumns = section.subdivisionColumns;
    int sectionCornerRadius = section.cornerRadius.round();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final cs = Theme.of(ctx).colorScheme;
            final isDark = cs.brightness == Brightness.dark;
            final bgColor =
                isDark ? const Color(0xFF1E1E2E) : const Color(0xFFF5F5F5);
            final textColor = isDark ? Colors.white : Colors.black87;
            final muted = textColor.withValues(alpha: 0.4);

            Widget sectionLabel(String text) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                text,
                style: TextStyle(
                  color: muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
            );

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.75,
                ),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Drag handle
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 8),
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: textColor.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),

                    // Scrollable content
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ── Header ──
                            Row(
                              children: [
                                const Icon(
                                  Icons.edit_outlined,
                                  color: Color(0xFF2196F3),
                                  size: 22,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  'Edit Section',
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: textColor.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '${section.sectionSize.width.round()} × ${section.sectionSize.height.round()}',
                                    style: TextStyle(
                                      color: textColor.withValues(alpha: 0.5),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),

                            // ── Name ──
                            sectionLabel('NAME'),
                            TextField(
                              controller: nameController,
                              autofocus: false,
                              style: TextStyle(color: textColor, fontSize: 15),
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: textColor.withValues(alpha: 0.06),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // ── Background Color ──
                            sectionLabel('BACKGROUND'),
                            SizedBox(
                              height: 40,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: colorPresets.length,
                                separatorBuilder:
                                    (_, __) => const SizedBox(width: 8),
                                itemBuilder: (_, i) {
                                  final color = colorPresets[i];
                                  final isSelected = selectedColor == color;
                                  final isTransparent = color == null;

                                  return GestureDetector(
                                    onTap: () {
                                      setSheetState(
                                        () => selectedColor = color,
                                      );
                                      HapticFeedback.selectionClick();
                                    },
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 150,
                                      ),
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color:
                                            isTransparent
                                                ? Colors.transparent
                                                : color,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color:
                                              isSelected
                                                  ? const Color(0xFF2196F3)
                                                  : textColor.withValues(
                                                    alpha: 0.15,
                                                  ),
                                          width: isSelected ? 2.5 : 1.0,
                                        ),
                                      ),
                                      child:
                                          isTransparent
                                              ? Icon(
                                                Icons.block_rounded,
                                                size: 18,
                                                color: textColor.withValues(
                                                  alpha: 0.3,
                                                ),
                                              )
                                              : null,
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 16),

                            // ── Options ──
                            sectionLabel('OPTIONS'),
                            _sectionOptionRow(
                              icon: Icons.grid_4x4_rounded,
                              label: 'Show Grid',
                              value: showGrid,
                              textColor: textColor,
                              onChanged:
                                  (v) => setSheetState(() => showGrid = v),
                            ),
                            const SizedBox(height: 4),
                            _sectionOptionRow(
                              icon: Icons.content_cut_rounded,
                              label: 'Clip Content',
                              value: clipContent,
                              textColor: textColor,
                              onChanged:
                                  (v) => setSheetState(() => clipContent = v),
                            ),
                            const SizedBox(height: 16),

                            // ── Subdivisions ──
                            sectionLabel('SUBDIVISIONS'),
                            _sectionStepperRow(
                              icon: Icons.table_rows_outlined,
                              label: 'Rows',
                              value: subdivRows,
                              textColor: textColor,
                              onChanged:
                                  (v) => setSheetState(() => subdivRows = v),
                            ),
                            const SizedBox(height: 4),
                            _sectionStepperRow(
                              icon: Icons.view_column_outlined,
                              label: 'Columns',
                              value: subdivColumns,
                              textColor: textColor,
                              onChanged:
                                  (v) => setSheetState(() => subdivColumns = v),
                            ),
                            const SizedBox(height: 4),
                            _sectionStepperRow(
                              icon: Icons.rounded_corner_rounded,
                              label: 'Corner Radius',
                              value: sectionCornerRadius,
                              min: 0,
                              max: 32,
                              textColor: textColor,
                              onChanged:
                                  (v) => setSheetState(
                                    () => sectionCornerRadius = v,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // ── Action buttons ──
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      child: Row(
                        children: [
                          // Delete button
                          IconButton(
                            onPressed: () {
                              Navigator.of(ctx).pop();
                              _deleteSection(section);
                            },
                            icon: const Icon(Icons.delete_outline_rounded),
                            color: const Color(0xFFE53935),
                            style: IconButton.styleFrom(
                              backgroundColor: const Color(
                                0xFFE53935,
                              ).withValues(alpha: 0.1),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Cancel
                          Expanded(
                            child: TextButton(
                              onPressed: () => Navigator.of(ctx).pop(),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                'Cancel',
                                style: TextStyle(
                                  color: textColor.withValues(alpha: 0.5),
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Apply
                          Expanded(
                            flex: 2,
                            child: FilledButton(
                              onPressed: () {
                                Navigator.of(ctx).pop();
                                _applySectionEdits(
                                  section: section,
                                  name:
                                      nameController.text.trim().isEmpty
                                          ? section.sectionName
                                          : nameController.text.trim(),
                                  backgroundColor: selectedColor,
                                  showGrid: showGrid,
                                  clipContent: clipContent,
                                  subdivisionRows: subdivRows,
                                  subdivisionColumns: subdivColumns,
                                  cornerRadius: sectionCornerRadius.toDouble(),
                                );
                              },
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF2196F3),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text(
                                'Apply Changes',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Apply edits to an existing section.
  void _applySectionEdits({
    required SectionNode section,
    required String name,
    Color? backgroundColor,
    bool showGrid = false,
    bool clipContent = false,
    int subdivisionRows = 1,
    int subdivisionColumns = 1,
    double cornerRadius = 0,
  }) {
    section.sectionName = name;
    section.name = name;
    section.backgroundColor = backgroundColor;
    section.showGrid = showGrid;
    section.clipContent = clipContent;
    section.subdivisionRows = subdivisionRows;
    section.subdivisionColumns = subdivisionColumns;
    section.cornerRadius = cornerRadius;

    _layerController.sceneGraph.bumpVersion();
    DrawingPainter.invalidateAllTiles();
    HapticFeedback.mediumImpact();
    setState(() {});
    _autoSaveCanvas();
  }

  /// Delete a section from the scene graph.
  void _deleteSection(SectionNode section) {
    final sceneGraph = _layerController.sceneGraph;
    for (final layer in sceneGraph.layers) {
      if (layer.children.contains(section)) {
        layer.remove(section);
        break;
      }
    }
    sceneGraph.bumpVersion();
    DrawingPainter.invalidateAllTiles();
    HapticFeedback.heavyImpact();
    setState(() {});
    _autoSaveCanvas();
  }

  // ===========================================================================
  // 📐 SECTION CUSTOMIZATION — Bottom sheet for name & color

  /// Show a bottom sheet to let the user name the section, pick a color,
  /// select a preset, and toggle grid/clip options.
  void _showSectionCustomizationSheet(Rect sectionRect) {
    final defaultName = 'Section ${_sectionCounter}';
    final nameController = TextEditingController(text: defaultName);

    // Curated color presets (null = transparent / no background)
    const colorPresets = <Color?>[
      null, // transparent
      Color(0xFFFFFFFF), // white
      Color(0xFFF5F5F5), // light grey
      Color(0xFF1E1E2E), // dark navy
      Color(0x1A2196F3), // blue tint
      Color(0x1AFF9800), // orange tint
      Color(0x1A4CAF50), // green tint
      Color(0x1AE91E63), // pink tint
      Color(0x1A9C27B0), // purple tint
      Color(0x1A00BCD4), // cyan tint
    ];

    // Preset categories for organized display
    const presetCategories = <String, List<SectionPreset>>{
      '📱 Devices': [
        SectionPreset.iphone16,
        SectionPreset.iphone16Pro,
        SectionPreset.iphone16ProMax,
        SectionPreset.ipadPro11,
        SectionPreset.ipadPro13,
      ],
      '🖥 Desktop': [
        SectionPreset.macbook14,
        SectionPreset.desktop1080p,
        SectionPreset.desktop4k,
      ],
      '📄 Paper': [
        SectionPreset.a4Portrait,
        SectionPreset.a4Landscape,
        SectionPreset.a3Portrait,
        SectionPreset.letterPortrait,
        SectionPreset.letterLandscape,
      ],
      '📸 Social': [
        SectionPreset.instagramPost,
        SectionPreset.instagramStory,
        SectionPreset.twitterPost,
      ],
      '🎬 Presentation': [
        SectionPreset.presentation16x9,
        SectionPreset.presentation4x3,
      ],
    };

    Color? selectedColor;
    SectionPreset? selectedPreset;
    bool showGrid = false;
    bool clipContent = false;
    int subdivRows = 1;
    int subdivColumns = 1;
    int sectionCornerRadius = 0;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final cs = Theme.of(ctx).colorScheme;
            final isDark = cs.brightness == Brightness.dark;
            final bgColor =
                isDark ? const Color(0xFF1E1E2E) : const Color(0xFFF5F5F5);
            final textColor = isDark ? Colors.white : Colors.black87;
            final muted = textColor.withValues(alpha: 0.4);

            // Current effective size
            final effectiveSize =
                selectedPreset != null
                    ? selectedPreset!.size
                    : sectionRect.size;

            Widget sectionLabel(String text) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                text,
                style: TextStyle(
                  color: muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
            );

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.75,
                ),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Drag handle
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 8),
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: textColor.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),

                    // Scrollable content
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ── Header ──
                            Row(
                              children: [
                                const Icon(
                                  Icons.dashboard_outlined,
                                  color: Color(0xFF2196F3),
                                  size: 22,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  'New Section',
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const Spacer(),
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 200),
                                  child: Container(
                                    key: ValueKey(effectiveSize),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: textColor.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '${effectiveSize.width.round()} × ${effectiveSize.height.round()}',
                                      style: TextStyle(
                                        color: textColor.withValues(alpha: 0.5),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),

                            // ── Name ──
                            sectionLabel('NAME'),
                            TextField(
                              controller: nameController,
                              autofocus: true,
                              style: TextStyle(color: textColor, fontSize: 15),
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: textColor.withValues(alpha: 0.06),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                hintText: 'Section name...',
                                hintStyle: TextStyle(
                                  color: textColor.withValues(alpha: 0.3),
                                ),
                              ),
                              onSubmitted: (_) {
                                Navigator.of(ctx).pop();
                                _commitSectionWithOptions(
                                  sectionRect: sectionRect,
                                  name:
                                      nameController.text.trim().isEmpty
                                          ? defaultName
                                          : nameController.text.trim(),
                                  backgroundColor: selectedColor,
                                  showGrid: showGrid,
                                  clipContent: clipContent,
                                  preset: selectedPreset,
                                  subdivisionRows: subdivRows,
                                  subdivisionColumns: subdivColumns,
                                  cornerRadius: sectionCornerRadius.toDouble(),
                                );
                              },
                            ),
                            const SizedBox(height: 16),

                            // ── Presets ──
                            sectionLabel('PRESET SIZE'),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                // Custom (freehand) chip
                                _sectionPresetChip(
                                  label: '✏️ Custom',
                                  isSelected: selectedPreset == null,
                                  textColor: textColor,
                                  onTap: () {
                                    setSheetState(() => selectedPreset = null);
                                    HapticFeedback.selectionClick();
                                  },
                                ),
                                // All presets
                                for (final entry in presetCategories.entries)
                                  for (final preset in entry.value)
                                    _sectionPresetChip(
                                      label: preset.label,
                                      isSelected: selectedPreset == preset,
                                      textColor: textColor,
                                      subtitle:
                                          '${preset.width.round()}×${preset.height.round()}',
                                      onTap: () {
                                        setSheetState(() {
                                          selectedPreset = preset;
                                          nameController.text = preset.label;
                                        });
                                        HapticFeedback.selectionClick();
                                      },
                                    ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // ── Background Color ──
                            sectionLabel('BACKGROUND'),
                            SizedBox(
                              height: 40,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: colorPresets.length,
                                separatorBuilder:
                                    (_, __) => const SizedBox(width: 8),
                                itemBuilder: (_, i) {
                                  final color = colorPresets[i];
                                  final isSelected = selectedColor == color;
                                  final isTransparent = color == null;

                                  return GestureDetector(
                                    onTap: () {
                                      setSheetState(
                                        () => selectedColor = color,
                                      );
                                      HapticFeedback.selectionClick();
                                    },
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 150,
                                      ),
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color:
                                            isTransparent
                                                ? Colors.transparent
                                                : color,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color:
                                              isSelected
                                                  ? const Color(0xFF2196F3)
                                                  : textColor.withValues(
                                                    alpha: 0.15,
                                                  ),
                                          width: isSelected ? 2.5 : 1.0,
                                        ),
                                      ),
                                      child:
                                          isTransparent
                                              ? Icon(
                                                Icons.block_rounded,
                                                size: 18,
                                                color: textColor.withValues(
                                                  alpha: 0.3,
                                                ),
                                              )
                                              : null,
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 16),

                            // ── Options ──
                            sectionLabel('OPTIONS'),
                            _sectionOptionRow(
                              icon: Icons.grid_4x4_rounded,
                              label: 'Show Grid',
                              value: showGrid,
                              textColor: textColor,
                              onChanged:
                                  (v) => setSheetState(() => showGrid = v),
                            ),
                            const SizedBox(height: 4),
                            _sectionOptionRow(
                              icon: Icons.content_cut_rounded,
                              label: 'Clip Content',
                              value: clipContent,
                              textColor: textColor,
                              onChanged:
                                  (v) => setSheetState(() => clipContent = v),
                            ),
                            const SizedBox(height: 16),

                            // ── Subdivisions ──
                            sectionLabel('SUBDIVISIONS'),
                            _sectionStepperRow(
                              icon: Icons.table_rows_outlined,
                              label: 'Rows',
                              value: subdivRows,
                              textColor: textColor,
                              onChanged:
                                  (v) => setSheetState(() => subdivRows = v),
                            ),
                            const SizedBox(height: 4),
                            _sectionStepperRow(
                              icon: Icons.view_column_outlined,
                              label: 'Columns',
                              value: subdivColumns,
                              textColor: textColor,
                              onChanged:
                                  (v) => setSheetState(() => subdivColumns = v),
                            ),
                            const SizedBox(height: 4),
                            _sectionStepperRow(
                              icon: Icons.rounded_corner_rounded,
                              label: 'Corner Radius',
                              value: sectionCornerRadius,
                              min: 0,
                              max: 32,
                              textColor: textColor,
                              onChanged:
                                  (v) => setSheetState(
                                    () => sectionCornerRadius = v,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // ── Action buttons (pinned at bottom) ──
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () => Navigator.of(ctx).pop(),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                'Cancel',
                                style: TextStyle(
                                  color: textColor.withValues(alpha: 0.5),
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: FilledButton(
                              onPressed: () {
                                Navigator.of(ctx).pop();
                                _commitSectionWithOptions(
                                  sectionRect: sectionRect,
                                  name:
                                      nameController.text.trim().isEmpty
                                          ? defaultName
                                          : nameController.text.trim(),
                                  backgroundColor: selectedColor,
                                  showGrid: showGrid,
                                  clipContent: clipContent,
                                  preset: selectedPreset,
                                  subdivisionRows: subdivRows,
                                  subdivisionColumns: subdivColumns,
                                  cornerRadius: sectionCornerRadius.toDouble(),
                                );
                              },
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF2196F3),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text(
                                'Create Section',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Selectable preset chip widget.
  Widget _sectionPresetChip({
    required String label,
    required bool isSelected,
    required Color textColor,
    required VoidCallback onTap,
    String? subtitle,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color:
              isSelected
                  ? const Color(0xFF2196F3).withValues(alpha: 0.15)
                  : textColor.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color:
                isSelected
                    ? const Color(0xFF2196F3)
                    : textColor.withValues(alpha: 0.1),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color:
                    isSelected
                        ? const Color(0xFF2196F3)
                        : textColor.withValues(alpha: 0.7),
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(width: 4),
              Text(
                subtitle,
                style: TextStyle(
                  color: textColor.withValues(alpha: 0.3),
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Toggle row for grid/clip options.
  Widget _sectionOptionRow({
    required IconData icon,
    required String label,
    required bool value,
    required Color textColor,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: textColor.withValues(alpha: 0.4)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: textColor.withValues(alpha: 0.7),
              fontSize: 14,
            ),
          ),
        ),
        SizedBox(
          height: 28,
          child: Switch.adaptive(
            value: value,
            onChanged: (v) {
              onChanged(v);
              HapticFeedback.selectionClick();
            },
            activeColor: const Color(0xFF2196F3),
          ),
        ),
      ],
    );
  }

  /// Commit the SectionNode with all user-chosen options.
  /// Stepper row for numeric values (rows/columns).
  Widget _sectionStepperRow({
    required IconData icon,
    required String label,
    required int value,
    required Color textColor,
    required ValueChanged<int> onChanged,
    int min = 1,
    int max = 12,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: textColor.withValues(alpha: 0.4)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: textColor.withValues(alpha: 0.7),
              fontSize: 14,
            ),
          ),
        ),
        // Minus button
        GestureDetector(
          onTap:
              value > min
                  ? () {
                    onChanged(value - 1);
                    HapticFeedback.selectionClick();
                  }
                  : null,
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: textColor.withValues(alpha: value > min ? 0.1 : 0.04),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              Icons.remove_rounded,
              size: 16,
              color: textColor.withValues(alpha: value > min ? 0.6 : 0.2),
            ),
          ),
        ),
        // Value
        SizedBox(
          width: 32,
          child: Center(
            child: Text(
              '$value',
              style: TextStyle(
                color: textColor,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        // Plus button
        GestureDetector(
          onTap:
              value < max
                  ? () {
                    onChanged(value + 1);
                    HapticFeedback.selectionClick();
                  }
                  : null,
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: textColor.withValues(alpha: value < max ? 0.1 : 0.04),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              Icons.add_rounded,
              size: 16,
              color: textColor.withValues(alpha: value < max ? 0.6 : 0.2),
            ),
          ),
        ),
      ],
    );
  }

  /// Commit the SectionNode with all user-chosen options.
  void _commitSectionWithOptions({
    required Rect sectionRect,
    required String name,
    Color? backgroundColor,
    bool showGrid = false,
    bool clipContent = false,
    SectionPreset? preset,
    int subdivisionRows = 1,
    int subdivisionColumns = 1,
    double cornerRadius = 0,
  }) {
    final effectiveSize =
        preset != null
            ? preset.size
            : Size(sectionRect.width, sectionRect.height);

    final section = SectionNode(
      id: NodeId(generateUid()),
      sectionName: name,
      sectionSize: effectiveSize,
      backgroundColor: backgroundColor,
      showGrid: showGrid,
      clipContent: clipContent,
      preset: preset,
      subdivisionRows: subdivisionRows,
      subdivisionColumns: subdivisionColumns,
      cornerRadius: cornerRadius,
    );
    section.setPosition(sectionRect.left, sectionRect.top);

    final sceneGraph = _layerController.sceneGraph;
    final activeLayer =
        sceneGraph.layers.isNotEmpty ? sceneGraph.layers.first : null;
    if (activeLayer != null) {
      activeLayer.add(section);
      sceneGraph.bumpVersion();
    }

    _sectionCounter++;
    DrawingPainter.invalidateAllTiles();
    HapticFeedback.mediumImpact();
    setState(() {});
    _autoSaveCanvas();
  }
}
