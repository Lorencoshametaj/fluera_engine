part of '../../fluera_canvas_screen.dart';

/// 📦 Drawing End — pointer-up finalization, stroke save, symmetry mirror
extension on _FlueraCanvasScreenState {
  void _onDrawEnd(Offset canvasPosition) {
    // 🔒 INLINE EDITING GUARD
    if (_isInlineEditing) return;

    // 🔍 ECHO SEARCH INTERCEPT: Commit query stroke
    if (_echoSearchActive) {
      _echoSearchOnDrawEnd();
      return;
    }

    // 🎨 KNOWLEDGE FLOW: Finalize curve drag (control point adjustment)
    if (_isCurveDragging && _knowledgeFlowController != null) {
      setState(() {
        _isCurveDragging = false;
        _curveDragConnectionId = null;
        _pendingLabelConnectionId = null;
        _pendingLabelScreenPos = null;
      });
      _knowledgeFlowController!.version.value++;
      _autoSaveCanvas();
      return;
    }

    // 🏷️ KNOWLEDGE FLOW: Deferred label editor open (tap, not long-press)
    // If a connection was hit on touch-down and no curve drag started,
    // open the label editor now.
    if (_pendingLabelConnectionId != null && _pendingLabelScreenPos != null) {
      final pendingId = _pendingLabelConnectionId!;
      final pendingPos = _pendingLabelScreenPos!;
      _pendingLabelConnectionId = null;
      _pendingLabelScreenPos = null;

      // 📋 MULTI-SELECT MODE: If already selecting, toggle this connection
      if (_knowledgeFlowController != null && _knowledgeFlowController!.isMultiSelecting) {
        _knowledgeFlowController!.toggleMultiSelect(pendingId);
        HapticFeedback.selectionClick();
        return;
      }

      // 👆 DOUBLE-TAP DETECTION: If same connection tapped within 300ms,
      // highlight the connected graph instead of opening the label editor.
      final now = DateTime.now().millisecondsSinceEpoch;
      if (_lastConnectionTapId == pendingId &&
          (now - _lastConnectionTapMs) < 300 &&
          _knowledgeFlowController != null) {
        // 🌐 Double-tap → select, highlight graph, path trace
        _knowledgeFlowController!.selectConnection(pendingId);
        _knowledgeFlowController!.startPathTrace(pendingId);
        HapticFeedback.mediumImpact();
        _lastConnectionTapId = null;
        _lastConnectionTapMs = 0;
        return;
      }

      // Record this tap for double-tap detection
      _lastConnectionTapId = pendingId;
      _lastConnectionTapMs = now;

      setState(() {
        _editingLabelConnectionId = pendingId;
        _labelOverlayScreenPosition = pendingPos;
      });
      HapticFeedback.selectionClick();
      return;
    }

    // 📋 MULTI-SELECT: Tap on empty space → clear multi-selection
    if (_knowledgeFlowController != null && _knowledgeFlowController!.isMultiSelecting) {
      _knowledgeFlowController!.clearMultiSelect();
    }

    // 🧠 KNOWLEDGE FLOW: Finalize connection drag
    if (_isConnectionDragging && _knowledgeFlowController != null) {
      if (_connectionSnapTargetClusterId != null &&
          _connectionDragSourceClusterId != null) {
        // Create the connection with frozen anchor points!
        final srcCluster = _clusterCache
            .where((c) => c.id == _connectionDragSourceClusterId)
            .firstOrNull;
        final tgtCluster = _clusterCache
            .where((c) => c.id == _connectionSnapTargetClusterId)
            .firstOrNull;
        final conn = _knowledgeFlowController!.addConnection(
          sourceClusterId: _connectionDragSourceClusterId!,
          targetClusterId: _connectionSnapTargetClusterId!,
          sourceAnchor: srcCluster?.centroid,
          targetAnchor: tgtCluster?.centroid,
        );

        if (conn != null) {
          HapticFeedback.heavyImpact(); // Success!

          // 🏷️ Auto-populate label from recognized cluster text
          final srcText = _clusterTextCache[_connectionDragSourceClusterId!] ?? '';
          final tgtText = _clusterTextCache[_connectionSnapTargetClusterId!] ?? '';
          if (srcText.isNotEmpty && tgtText.isNotEmpty) {
            final truncSrc = srcText.length > 12 ? '${srcText.substring(0, 10)}…' : srcText;
            final truncTgt = tgtText.length > 12 ? '${tgtText.substring(0, 10)}…' : tgtText;
            conn.label = '$truncSrc → $truncTgt';
          } else if (srcText.isNotEmpty) {
            conn.label = srcText.length > 20 ? '${srcText.substring(0, 18)}…' : srcText;
          } else if (tgtText.isNotEmpty) {
            conn.label = tgtText.length > 20 ? '${tgtText.substring(0, 18)}…' : tgtText;
          }

          // Start particle animation if not already running
          if (_knowledgeParticleTicker != null &&
              !_knowledgeParticleTicker!.isActive) {
            _knowledgeParticleTicker!.start();
          }
          // 💾 Auto-save after creating connection
          _autoSaveCanvas();
          // Label editor NOT opened automatically.
          // User taps connection with gesture tool to edit label.
        }
      } else {
        // No snap target — just clean up silently (drag cancelled).
        // Cluster preview is only shown on simple long-press (no drag).
      }

      // Reset drag state — must use setState to force rebuild
      // so the KnowledgeFlowPainter gets null drag points and repaints
      setState(() {
        _isConnectionDragging = false;
        _connectionDragSourcePoint = null;
        _connectionDragCurrentPoint = null;
        _connectionDragSourceClusterId = null;
        _connectionSnapTargetClusterId = null;
      });
      _knowledgeFlowController!.version.value++;

      return;
    }

    // Indica che l'utente ha finito di disegnare
    _isDrawingNotifier.value = false;
    CanvasPerformanceMonitor.instance.notifyDrawingEnded(); // 🚀 Resume overlay
    _pushConsciousContext(); // 🧠 Notify intelligence subsystems

    // 📌 PIN DRAG END: Finalize pin position
    if (_draggingPinId != null) {
      _handleRecordingPinDragEnd(canvasPosition);
      return;
    }
    // 📐 SECTION RESIZE END: Finalize section size
    if (_resizingSectionNode != null) {
      _resizingSectionNode = null;
      _resizeAnchorCorner = null;
      _resizeEdgeAxis = null;
      HapticFeedback.mediumImpact();
      _autoSaveCanvas();
      return;
    }
    // 📐 SECTION DRAG END: Finalize section position
    if (_draggingSectionNode != null) {
      _draggingSectionNode = null;
      _sectionDragGrabOffset = null;
      HapticFeedback.mediumImpact();
      _autoSaveCanvas();
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
      _uiRebuildNotifier.value++;

      // Minimum size check — if large enough, create new section
      if (sectionRect.width >= 20 && sectionRect.height >= 20) {
        _showSectionCustomizationSheet(sectionRect);
      } else {
        // Small gesture = tap — try to select an existing section
        final tappedSection = _findSectionAtPoint(canvasPosition);
        if (tappedSection != null) {
          final now = DateTime.now();
          final isDoubleTap =
              _lastTappedSection == tappedSection &&
              _lastTapTime != null &&
              now.difference(_lastTapTime!).inMilliseconds < 400;

          if (isDoubleTap) {
            // Double-tap → zoom-to-fit section
            _lastTappedSection = null;
            _lastTapTime = null;
            HapticFeedback.mediumImpact();
            final tx = tappedSection.worldTransform.getTranslation();
            final sectionRect = Rect.fromLTWH(
              tx.x,
              tx.y,
              tappedSection.sectionSize.width,
              tappedSection.sectionSize.height,
            );
            final viewportSize = MediaQuery.of(context).size;
            CameraActions.zoomToRect(
              _canvasController,
              sectionRect,
              viewportSize,
            );
          } else {
            // Single tap → edit sheet
            _lastTappedSection = tappedSection;
            _lastTapTime = now;
            HapticFeedback.selectionClick();
            _showSectionEditSheet(tappedSection);
          }
        }
      }
      return;
    }

    // ✏️ SECTION NAME TAP: Tap on any section's name label → edit sheet
    // (works from ANY tool — the name label is always visible)
    if (!_isDrawingNotifier.value) {
      final hitSection = _findSectionByNameLabel(canvasPosition);
      if (hitSection != null) {
        HapticFeedback.selectionClick();
        _showSectionEditSheet(hitSection);
        return;
      }
    }

    // ☁️ PRESENCE: Clear drawing state for collaborators
    if (_isSharedCanvas && _realtimeEngine != null) {
      _broadcastCursorPosition(canvasPosition, isDrawing: false);
    }

    // 📄 PDF DOCUMENT DRAG: End whole-document drag
    if (_pdfPageDragController.isDraggingDocument) {
      final parentDoc = _pdfPageDragController.parentDocument;
      // 🚀 Translate annotation strokes ONCE by total drag delta
      if (parentDoc != null) {
        final totalDelta =
            parentDoc.documentModel.gridOrigin -
            _pdfPageDragController.dragStartDocOrigin;
        if (totalDelta != Offset.zero) {
          final ids = _pdfPageDragController.allDocumentAnnotationIds;
          if (ids.isNotEmpty) {
            _translateAnnotationStrokes(ids.toSet(), totalDelta);
          }
        }
      }
      final activeLayer = _layerController.layers.firstWhere(
        (l) => l.id == _layerController.activeLayerId,
        orElse: () => _layerController.layers.first,
      );
      _pdfPageDragController.endDocumentDrag(layerNode: activeLayer.node);
      // 🚀 Clear lightweight drag mode + full invalidation
      DrawingPainter.isDraggingPdf = false;
      DrawingPainter.draggedPageRects = const [];
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

      _uiRebuildNotifier.value++;
      _autoSaveCanvas();
      return;
    }

    // 📄 PDF PAGE DRAG: End drag and save position
    // 🚀 Strokes are translated ONCE here by total delta (not per frame).
    if (_pdfPageDragController.isDragging) {
      final draggedPage = _pdfPageDragController.draggingPage;
      // Translate annotation strokes by total drag delta
      if (draggedPage != null) {
        final totalDelta =
            draggedPage.position - _pdfPageDragController.dragStartPosition;
        if (totalDelta != Offset.zero) {
          final ids = _pdfPageDragController.linkedAnnotationIds;
          if (ids.isNotEmpty) {
            _translateAnnotationStrokes(ids.toSet(), totalDelta);
          }
        }
      }
      _pdfPageDragController.endDrag();
      // 🚀 Clear lightweight drag mode + full invalidation
      DrawingPainter.isDraggingPdf = false;
      DrawingPainter.draggedPageRects = const [];
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

      _uiRebuildNotifier.value++;
      _autoSaveCanvas();
      return;
    }

    // 🪣 Fill mode — no stroke finalization needed
    if (_effectiveIsFill) {
      _isDrawingNotifier.value = false;
      return;
    }

    // 🌀 End single-finger handle rotation (pan mode only)
    if (_imageTool.isHandleRotating) {
      _imageTool.endHandleRotation();
      _imageVersion++;
      _rebuildImageSpatialIndex();
      if (_imageTool.selectedImage != null) {
        _layerController.updateImage(_imageTool.selectedImage!);
        // 🔴 RT: Broadcast image rotation to collaborators
        _broadcastImageUpdate(_imageTool.selectedImage!);
      }
      _uiRebuildNotifier.value++;
      _autoSaveCanvas(); // 💾 Persist handle rotation to disk
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
      _uiRebuildNotifier.value++;
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
      _uiRebuildNotifier.value++;
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
      _uiRebuildNotifier.value++;

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
      _uiRebuildNotifier.value++;

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
      _uiRebuildNotifier.value++;
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
      _uiRebuildNotifier.value++;
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
      _uiRebuildNotifier.value++;
      _autoSaveCanvas();
      return;
    }

    // 📈 FunctionGraphNode resize end
    if (_isResizingGraph) {
      _isResizingGraph = false;
      _graphResizeCorner = -1;
      _graphResizeAnchor = null;
      HapticFeedback.mediumImpact();
      _layerController.sceneGraph.bumpVersion();
      DrawingPainter.invalidateAllTiles();
      _uiRebuildNotifier.value++;
      _autoSaveCanvas();
      return;
    }

    // 📈 FunctionGraphNode drag end
    if (_isDraggingGraph) {
      _isDraggingGraph = false;
      _isMovingGraph = false;
      _graphPinchStarted = false;
      _graphDragStart = null;
      // T1: Clear trace cursor
      if (_selectedGraphNode != null) _selectedGraphNode!.traceX = null;
      HapticFeedback.lightImpact();
      _layerController.sceneGraph.bumpVersion();
      DrawingPainter.invalidateAllTiles();
      _uiRebuildNotifier.value++;
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
        // If gestural lasso is active and this was a simple tap (no new lasso
        // path was started because _onDrawStart returned early), clear the
        // existing selection and return to the drawing tool.
        if (_wasGesturalLassoActivated &&
            _lassoTool.hasSelection &&
            _lassoTool.lassoPath.isEmpty) {
          _lassoTool.clearSelection();
          _autoReturnFromGesturalLasso();
          HapticFeedback.lightImpact();
          _uiRebuildNotifier.value++;
          return;
        }

        // Enable additive mode if gestural lasso has a previous selection backup
        final useAdditive = _wasGesturalLassoActivated &&
            _lassoSelectionBackup != null &&
            _lassoSelectionBackup!.isNotEmpty;
        if (useAdditive) {
          _lassoTool.additiveMode = true;
        }

        // Mode-aware completion
        switch (_lassoTool.selectionMode) {
          case SelectionMode.marquee:
            _lassoTool.completeMarquee();
            break;
          case SelectionMode.ellipse:
            _lassoTool.completeEllipse();
            break;
          case SelectionMode.lasso:
            _lassoTool.completeLasso();
            break;
        }

        // Restore additive mode
        if (useAdditive) {
          _lassoTool.additiveMode = false;
        }

        // Feedback tattile e visivo per selezione completata
        if (_lassoTool.hasSelection) {
          HapticFeedback.mediumImpact();
        } else {
          HapticFeedback.lightImpact();
          // #1: Auto-return to previous tool if lasso was activated gesturally
          if (_wasGesturalLassoActivated) {
            _lassoTool.clearSelection(); // clear any previous selection
            _autoReturnFromGesturalLasso();
          }
        }
      }

      _uiRebuildNotifier.value++; // Update per mostrare selected elements
      return;
    }

    // ✒️ PEN TOOL: route pointer-up event
    if (_toolController.isPenToolMode) {
      final screenPos = _canvasController.canvasToScreen(canvasPosition);
      _penTool.onPointerUp(
        _penToolContext,
        PointerUpEvent(position: screenPos),
      );
      _uiRebuildNotifier.value++;
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
        _uiRebuildNotifier.value++;

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
          // 🔍 Fix 3: Reconcile search index after erasing
          _reconcileSearchIndex();
          DrawingPainter.invalidateAllTiles();
          _autoSaveCanvas();
          if (mounted) _uiRebuildNotifier.value++;
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
      _uiRebuildNotifier.value++; // 🏗️ Nascondi cursore overlay

      // 🚀 ANR FIX: Defer heavy work off pointer-up frame.
      // mergeAdjacentFragments (O(N) but still allocates) + tile invalidation
      // + SQLite save were running synchronously and blocking >5s → ANR.
      Future.microtask(() {
        _eraserTool.mergeAdjacentFragments();
        // 📄 Clean up orphaned PDF annotation IDs after erase
        _reconcilePdfAnnotations();
        // 🔍 Fix 3: Reconcile search index after erasing
        _reconcileSearchIndex();
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

      // 🆕 Catch-up: append stabilizer lag closure points
      final pts = _currentStrokeNotifier.value;
      if (_drawingHandler.stabilizerLevel > 0 && pts.isNotEmpty) {
        final lastPos = pts.last.position;
        final catchUp = _drawingHandler.finalizeStabilizer(lastPos);
        final lastP = pts.last.pressure;
        final lastTs = pts.last.timestamp;
        for (int i = 0; i < catchUp.length; i++) {
          pts.add(
            ProDrawingPoint(
              position: catchUp[i],
              pressure: lastP,
              timestamp: lastTs + i + 1,
            ),
          );
        }
      }

      finalPoints = List.unmodifiable(pts);
      _rawInputProcessor120Hz!.reset();
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

    // 🧹 SCRATCH-OUT (v2): Detect zigzag scribble → delete strokes underneath
    // Enhanced: PCA diagonal support, undo, particles, confirmation, sound.
    // 🔒 GUARD: Skip if draw was cancelled by zoom (finger-up after pinch)
    if (!_drawWasCancelled &&
        !_effectiveIsEraser && _effectivePenType != ProPenType.technicalPen) {
      final scratchResult = ScratchOutDetector.analyze(finalPoints);
      if (scratchResult.recognized) {
        // 🔥 Clear native GPU overlay (Vulkan/Metal/WebGPU) FIRST
        if (_vulkanOverlayActive) {
          _vulkanTextureOpacity.value = 0.0;
          if (kIsWeb && _webGpuOverlayActive) {
            _webGpuStrokeOverlay.clear();
          } else {
            _vulkanStrokeOverlay.clear();
            _vulkanStrokeOverlay.disableDirectOverlay();
          }
        }

        // Clear Flutter live stroke
        _currentStrokeNotifier.clear();

        // Find all strokes in the active layer whose bounds overlap
        final activeLayer = _layerController.layers.firstWhere(
          (l) => l.id == _layerController.activeLayerId,
          orElse: () => _layerController.layers.first,
        );
        final strokesToDelete = <ProStroke>[];
        for (final stroke in activeLayer.strokes) {
          if (stroke.bounds.overlaps(scratchResult.scratchBounds)) {
            strokesToDelete.add(stroke);
          }
        }

        if (strokesToDelete.isNotEmpty) {
          final deleteCount = strokesToDelete.length;

          // ↩️ UNDO: Save strokes before deletion for undo support
          final deletedStrokesCopy = List<ProStroke>.of(strokesToDelete);

          // Batch-delete overlapping strokes
          _layerController.beginBatch();
          for (final stroke in strokesToDelete) {
            _layerController.removeStroke(stroke.id);
          }
          _layerController.endBatch();

          // ↩️ Push undo command (deletion already executed)
          _commandHistory.pushWithoutExecute(ScratchOutCommand(
            deletedStrokes: deletedStrokesCopy,
            layerController: _layerController,
          ));

          // ⚡ CONFIRMATION: Progressive haptics for large deletions
          if (deleteCount > 5) {
            HapticFeedback.lightImpact();
            Future.delayed(const Duration(milliseconds: 50), () {
              HapticFeedback.mediumImpact();
              Future.delayed(const Duration(milliseconds: 50), () {
                HapticFeedback.heavyImpact();
              });
            });
          } else {
            HapticFeedback.heavyImpact();
          }

          // 🔊 SOUND: Subtle confirmation click
          SystemSound.play(SystemSoundType.click);

          // 💥 PARTICLE DISSOLVE: Generate particles (max 80 total)
          final particles = <_ScratchOutParticle>[];
          final rng = math.Random();
          const maxParticles = 80;
          final perStroke = (maxParticles / deletedStrokesCopy.length)
              .ceil()
              .clamp(2, 12);
          for (final stroke in deletedStrokesCopy) {
            if (particles.length >= maxParticles) break;
            final bounds = stroke.bounds;
            for (int i = 0; i < perStroke; i++) {
              final x = bounds.left + rng.nextDouble() * bounds.width;
              final y = bounds.top + rng.nextDouble() * bounds.height;
              particles.add(_ScratchOutParticle(
                position: Offset(x, y),
                velocity: Offset(
                  (rng.nextDouble() - 0.5) * 200,
                  -50 - rng.nextDouble() * 150,
                ),
                color: stroke.color,
                size: stroke.baseWidth.clamp(2.0, 6.0),
              ));
            }
          }
          _scratchOutParticles = particles;
          _scratchOutBounds = scratchResult.scratchBounds;
          _scratchOutAnimating = true;
          _uiRebuildNotifier.value++;

          // Clean up after animation (500ms)
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              _scratchOutAnimating = false;
              _scratchOutBounds = null;
              _scratchOutParticles = [];
              _uiRebuildNotifier.value++;
            }
          });

          // Invalidate tiles + save
          DrawingPainter.invalidateAllTiles();
          _reconcilePdfAnnotations();
          _reconcileSearchIndex();
          _autoSaveCanvas();
        } else {
          // No overlapping strokes — just discard the scratch stroke
          _currentStrokeNotifier.clear();
        }

        return;
      }
    }

    // 🎤 NOTIFICA ESTERNA (per Sync Recording) - PRE-CREATION
    // Salviamo i tempi prima che vengano persi/resetati
    final strokeEndTime = DateTime.now();
    final strokeStartTime = _lastStrokeStartTime ?? strokeEndTime;
    _lastStrokeStartTime = null; // Reset

    // 🔗 TECHNICAL PEN: Endpoint snap — close shape if end is near start
    if (_effectivePenType == ProPenType.technicalPen &&
        _brushSettings.techEndpointSnap &&
        finalPoints.length >= 3) {
      final start = finalPoints.first.position;
      final end = finalPoints.last.position;
      final dist = (end - start).distance;
      final snapThreshold = math.max(_effectiveWidth * 10.0, 30.0);
      if (dist < snapThreshold && dist > 0.1) {
        // Create new list with closing point (finalPoints is unmodifiable)
        finalPoints = List.unmodifiable([
          ...finalPoints,
          ProDrawingPoint(
            position: start,
            pressure: finalPoints.last.pressure,
            timestamp: DateTime.now().millisecondsSinceEpoch,
            tiltX: finalPoints.last.tiltX,
            tiltY: finalPoints.last.tiltY,
          ),
        ]);
      }
    }

    // 📐 TECHNICAL PEN: No post-processing needed — state machine guarantees
    // exact angle alignment during drawing. The old "right angle lock" is removed
    // because it corrupted the already-straight lines.

    // 📐 TECHNICAL PEN: Clear overlay state
    if (_effectivePenType == ProPenType.technicalPen) {
      // 🔀 Save angle that current stroke traveled for parallel/perp snap on next stroke
      if (finalPoints.length >= 2) {
        final first = finalPoints.first.position;
        final last = finalPoints.last.position;
        final d = last - first;
        if (d.distance > 10.0) {
          _techLastStrokeAngleRad = math.atan2(d.dy, d.dx);
        }
      }
      _techAnchor = null;
      _techLockedAngle = null;
      _techPrevRawAngle = null;
      _techSnapAnchor = null;
      _techSnapAngleDeg = null;
      _techSegmentLength = null;
      _techNearStartPoint = false;
      _techStraightGhostEnd = null;
      _techLastGridCell = null;
      _techIntersections = [];
      _uiRebuildNotifier.value++;
    }

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

    // 🖼️ IMAGE STROKE ROUTING: If stroke started on an image, clip it to
    // the image boundary. Segments inside → image.drawingStrokes,
    // segments outside → regular canvas layer.
    ImageElement? targetImage;
    Rect? targetImageRect;
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
          targetImageRect = imageRect;
          break;
        }
      }
    }

    if (targetImage != null && targetImageRect != null) {
      // 🖼️ Split stroke at image boundary crossings
      final idx = _imageElements.indexWhere((e) => e.id == targetImage!.id);
      if (idx != -1) {
        final img = _imageElements[idx];
        final cosR = math.cos(-img.rotation);
        final sinR = math.sin(-img.rotation);

        // Walk the stroke and split into inside/outside segments
        final insideSegments = <List<ProDrawingPoint>>[];
        final outsideSegments = <List<ProDrawingPoint>>[];

        var currentInside = <ProDrawingPoint>[];
        var currentOutside = <ProDrawingPoint>[];
        bool wasInside = true; // starts inside (first point confirmed)

        for (int pi = 0; pi < stroke.points.length; pi++) {
          final pt = stroke.points[pi];
          final isInside = targetImageRect.contains(pt.position);

          if (isInside) {
            if (!wasInside && currentOutside.isNotEmpty) {
              // Crossed back inside — finalize outside segment
              // Interpolate the crossing point
              if (pi > 0) {
                final edgePt = _interpolateEdgeCrossing(
                  stroke.points[pi - 1].position, pt.position, targetImageRect,
                );
                if (edgePt != null) {
                  final crossPt = pt.copyWith(position: edgePt);
                  currentOutside.add(crossPt);
                  currentInside.add(crossPt);
                }
              }
              outsideSegments.add(currentOutside);
              currentOutside = <ProDrawingPoint>[];
            }
            currentInside.add(pt);
            wasInside = true;
          } else {
            if (wasInside && currentInside.isNotEmpty) {
              // Crossed outside — finalize inside segment
              if (pi > 0) {
                final edgePt = _interpolateEdgeCrossing(
                  stroke.points[pi - 1].position, pt.position, targetImageRect,
                );
                if (edgePt != null) {
                  final crossPt = pt.copyWith(position: edgePt);
                  currentInside.add(crossPt);
                  currentOutside.add(crossPt);
                }
              }
              insideSegments.add(currentInside);
              currentInside = <ProDrawingPoint>[];
            }
            currentOutside.add(pt);
            wasInside = false;
          }
        }
        // Flush remaining segment
        if (currentInside.isNotEmpty) insideSegments.add(currentInside);
        if (currentOutside.isNotEmpty) outsideSegments.add(currentOutside);

        // ── Add inside segments to image ──
        final newDrawingStrokes = [..._imageElements[idx].drawingStrokes];
        for (final seg in insideSegments) {
          if (seg.length < 2) continue;
          // Transform: canvas → image-local
          final localPoints = seg.map((p) {
            final dx = p.position.dx - img.position.dx;
            final dy = p.position.dy - img.position.dy;
            final rx = dx * cosR - dy * sinR;
            final ry = dx * sinR + dy * cosR;
            return p.copyWith(position: Offset(rx, ry));
          }).toList();

          newDrawingStrokes.add(stroke.copyWith(
            id: insideSegments.length == 1 ? stroke.id : generateUid(),
            points: localPoints,
            baseWidth: stroke.baseWidth,
            referenceScale: img.scale,
          ));
        }
        final updated = _imageElements[idx].copyWith(
          drawingStrokes: newDrawingStrokes,
        );
        _imageElements[idx] = updated;
        _layerController.updateImage(updated);
        _imageVersion++;
        _rebuildImageSpatialIndex();
        _imageRepaintNotifier.value++;
        _broadcastImageUpdate(updated);

        // 🔥 FIX: Add outside segments to regular canvas layer
        // (previously discarded — strokes going outside the image were lost)
        for (final seg in outsideSegments) {
          if (seg.length < 2) continue;
          final outsideStroke = stroke.copyWith(
            id: generateUid(),
            points: seg,
          );
          _layerController.addStroke(outsideStroke);
          _broadcastStrokeAdded(outsideStroke);
        }

        // 🔥 FIX: Clear live stroke and invalidate tiles immediately
        // so the split is visible without needing a pan/zoom.
        _currentStrokeNotifier.clear();
        DrawingPainter.invalidateAllTiles();
      }
    } else {
      // Regular canvas stroke
      if (_vulkanOverlayActive) {
        // 🔥 GPU HANDOFF — Flash-free sequence:
        // 1. Instantly hide GPU texture (opacity 0 via ValueNotifier, synchronous)
        //    This prevents double-opacity overlap (GPU + committed both visible).
        // 2. addStroke normally — DrawingPainter paints on next frame.
        // 3. clear() GPU in background — texture content cleaned for next stroke.
        //    GPU texture is made visible again at next draw-start.
        _vulkanTextureOpacity.value = 0.0;
        if (kIsWeb && _webGpuOverlayActive) {
          _webGpuStrokeOverlay.clear();
        } else {
          _vulkanStrokeOverlay.clear();
          // 🚀 DIRECT OVERLAY: Disable CAMetalLayer bypass on pen-up
          _vulkanStrokeOverlay.disableDirectOverlay();
        }
      }
      _layerController.addStroke(stroke);
      DrawingPainter.invalidateTilesForStroke(stroke);
      _broadcastStrokeAdded(stroke);

      // 🔍 Auto-index stroke for handwriting search
      if (stroke.points.length >= 5) {
        HandwritingIndexService.instance.enqueueStroke(
          _canvasId,
          stroke.id,
          stroke.points,
          stroke.bounds,
        );
      }
    }

    _currentStrokeNotifier.clear();

    // 🚀 PERF: setState() was here but is COMPLETELY REDUNDANT.
    // DrawingPainter repaints via ListenableBuilder(listenable: _layerController)
    // when addStroke() fires notifyListeners(). The setState triggered a full
    // 343-line _buildImpl() widget tree rebuild (~80ms) for zero visual benefit.
    // Removing this single line fixes the P90=82ms UI thread spike.

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

      // 🖼️ THUMBNAIL: Generate/update thumbnails for changed clusters
      if (_thumbnailCache != null) {
        final strokes = activeLayer.strokes;
        for (final cluster in _clusterCache) {
          if (cluster.elementCount < 1) continue;
          if (!_thumbnailCache!.isStale(cluster.id, cluster.bounds)) continue;

          // Collect strokes for this cluster
          final clusterStrokes = <ProStroke>[];
          for (final sid in cluster.strokeIds) {
            final s = strokes.where((s) => s.id == sid);
            if (s.isNotEmpty) clusterStrokes.add(s.first);
          }

          if (clusterStrokes.isNotEmpty) {
            _thumbnailCache!.generateThumbnail(cluster, clusterStrokes);
          }
        }
      }
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
  /// 🌊 REFLOW: Apply incremental displacement deltas to strokes.
  ///
  /// Called by [AnimatedReflowController] on each animation frame.
  /// Translates stroke points by the given delta for each affected element.
  /// This follows the same pattern as [_translateAnnotationStrokes].
  void _applyReflowDeltas(Map<String, Offset> deltas) {
    if (deltas.isEmpty) return;

    final deltaIds = deltas.keys.toSet();
    bool anyModified = false;

    for (final layer in _layerController.layers) {
      bool layerModified = false;
      for (final strokeNode in layer.node.strokeNodes) {
        final delta = deltas[strokeNode.stroke.id];
        if (delta == null || delta == Offset.zero) continue;

        final old = strokeNode.stroke;
        final translatedPoints =
            old.points.map((p) {
              return p.copyWith(position: p.position + delta);
            }).toList();
        strokeNode.stroke = old.copyWith(points: translatedPoints);
        layerModified = true;
      }
      if (layerModified) {
        layer.node.invalidateTypedCaches();
        anyModified = true;
      }
    }

    // Also translate shapes, text, images if they were affected
    for (final entry in deltas.entries) {
      final delta = entry.value;
      if (delta == Offset.zero) continue;

      // Shapes
      for (int i = 0; i < _cachedAllShapes.length; i++) {
        if (_cachedAllShapes[i].id == entry.key) {
          _cachedAllShapes[i] = _cachedAllShapes[i].copyWith(
            startPoint: _cachedAllShapes[i].startPoint + delta,
            endPoint: _cachedAllShapes[i].endPoint + delta,
          );
          anyModified = true;
        }
      }

      // Digital text elements
      for (int i = 0; i < _digitalTextElements.length; i++) {
        if (_digitalTextElements[i].id == entry.key) {
          _digitalTextElements[i] = _digitalTextElements[i].copyWith(
            position: _digitalTextElements[i].position + delta,
          );
          anyModified = true;
        }
      }

      // Image elements
      for (int i = 0; i < _imageElements.length; i++) {
        if (_imageElements[i].id == entry.key) {
          _imageElements[i] = _imageElements[i].copyWith(
            position: _imageElements[i].position + delta,
          );
          anyModified = true;
        }
      }
    }

    if (anyModified) {
      _layerController.sceneGraph.bumpVersion();
      DrawingPainter.invalidateAllTiles();
    }
  }

  /// Creates new ProStroke instances with translated point positions and
  /// replaces them on their StrokeNode. This ensures strokes follow
  /// their linked PDF page when it's dragged to a new position.
  void _translateAnnotationStrokes(Set<String> annotationIds, Offset delta) {
    if (annotationIds.isEmpty || delta == Offset.zero) return;

    for (final layer in _layerController.layers) {
      bool modified = false;
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
          modified = true;
        }
      }
      // 🔑 Invalidate cached stroke lists so rendering picks up new positions
      if (modified) {
        layer.node.invalidateTypedCaches();
      }
    }
    // Bump version so caches (stroke cache, annotation cache) rebuild
    _layerController.sceneGraph.bumpVersion();
  }

  /// 🔍 Fix 3: Reconcile handwriting search index with actual strokes.
  ///
  /// Removes orphaned index entries for strokes that were erased.
  /// Fire-and-forget — runs asynchronously without blocking UI.
  void _reconcileSearchIndex() {
    if (!HandwritingIndexService.instance.isInitialized) return;
    final existingIds = <String>{};
    for (final layer in _layerController.layers) {
      for (final stroke in layer.strokes) {
        existingIds.add(stroke.id);
      }
    }
    HandwritingIndexService.instance.reconcileWithStrokes(
      _canvasId,
      existingIds,
    );
  }

  /// Finds the exact point where a line segment from→to crosses the rect edge.
  /// Returns null if no crossing is found (both inside or both outside on same side).
  Offset? _interpolateEdgeCrossing(Offset from, Offset to, Rect rect) {
    // Check intersection with each of the 4 rect edges
    double? bestT;
    Offset? bestPt;

    // Helper: intersect segment from→to with an axis-aligned line segment
    void checkEdge(Offset a, Offset b) {
      final dFrom = to - from;
      final dEdge = b - a;
      final cross = dFrom.dx * dEdge.dy - dFrom.dy * dEdge.dx;
      if (cross.abs() < 1e-10) return; // Parallel

      final t = ((a.dx - from.dx) * dEdge.dy - (a.dy - from.dy) * dEdge.dx) / cross;
      final u = ((a.dx - from.dx) * dFrom.dy - (a.dy - from.dy) * dFrom.dx) / cross;

      if (t >= 0 && t <= 1 && u >= 0 && u <= 1) {
        if (bestT == null || t < bestT!) {
          bestT = t;
          bestPt = Offset(
            from.dx + t * dFrom.dx,
            from.dy + t * dFrom.dy,
          );
        }
      }
    }

    // Top edge
    checkEdge(rect.topLeft, rect.topRight);
    // Bottom edge
    checkEdge(rect.bottomLeft, rect.bottomRight);
    // Left edge
    checkEdge(rect.topLeft, rect.bottomLeft);
    // Right edge
    checkEdge(rect.topRight, rect.bottomRight);

    return bestPt;
  }
}
