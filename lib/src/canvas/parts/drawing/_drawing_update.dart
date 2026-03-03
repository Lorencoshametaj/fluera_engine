part of '../../fluera_canvas_screen.dart';

/// 📦 Drawing Update — continuous pointer-move handling during draw
extension on _FlueraCanvasScreenState {
  void _onDrawUpdate(
    Offset canvasPosition,
    double pressure,
    double tiltX,
    double tiltY,
  ) {
    //  PRESENCE: Feed cursor + tool info to remote users (Phase 2)

    // 📌 PIN DRAG: Route drag updates to pin handler
    if (_draggingPinId != null) {
      _handleRecordingPinDragUpdate(canvasPosition);
      return;
    }

    // 📐 SECTION RESIZE: Resize from corner (aspect-ratio locked) or edge (single axis)
    if (_resizingSectionNode != null && _resizeAnchorCorner != null) {
      final section = _resizingSectionNode!;
      final anchor = _resizeAnchorCorner!;
      final tx = section.worldTransform.getTranslation();

      Rect newRect;

      if (_resizeEdgeAxis == 'h') {
        // Horizontal edge → only change width (left or right edge)
        final curLeft = tx.x;
        final curTop = tx.y;
        final curH = section.sectionSize.height;
        // anchor.dx is the fixed edge x
        final fixedX = anchor.dx;
        final movingX = canvasPosition.dx;
        final left = math.min(fixedX, movingX);
        final right = math.max(fixedX, movingX);
        newRect = Rect.fromLTWH(left, curTop, right - left, curH);
      } else if (_resizeEdgeAxis == 'v') {
        // Vertical edge → only change height (top or bottom edge)
        final curLeft = tx.x;
        final curW = section.sectionSize.width;
        final fixedY = anchor.dy;
        final movingY = canvasPosition.dy;
        final top = math.min(fixedY, movingY);
        final bottom = math.max(fixedY, movingY);
        newRect = Rect.fromLTWH(curLeft, top, curW, bottom - top);
      } else {
        // Corner → aspect-ratio locked resize
        final aspectRatio =
            section.sectionSize.width / section.sectionSize.height;
        var rawRect = Rect.fromPoints(anchor, canvasPosition);
        if (aspectRatio > 0 && rawRect.width >= 20 && rawRect.height >= 20) {
          final w = rawRect.width;
          final h = w / aspectRatio;
          final left =
              canvasPosition.dx >= anchor.dx ? anchor.dx : anchor.dx - w;
          final top =
              canvasPosition.dy >= anchor.dy ? anchor.dy : anchor.dy - h;
          rawRect = Rect.fromLTWH(left, top, w, h);
        }
        newRect = rawRect;
      }

      if (newRect.width >= 20 && newRect.height >= 20) {
        section.setPosition(newRect.left, newRect.top);
        section.sectionSize = Size(newRect.width, newRect.height);
        _layerController.sceneGraph.bumpVersion();
        DrawingPainter.invalidateAllTiles();
        _layerController.notifyListeners();
        setState(() {});
      }
      return;
    }

    // 📐 SECTION DRAG: Move an existing section with edge snapping
    if (_draggingSectionNode != null && _sectionDragGrabOffset != null) {
      var newPos = canvasPosition - _sectionDragGrabOffset!;
      final dragW = _draggingSectionNode!.sectionSize.width;
      final dragH = _draggingSectionNode!.sectionSize.height;
      final snapThreshold = 10.0 / _canvasController.scale;

      // Snap to other sections' edges
      final sceneGraph = _layerController.sceneGraph;
      for (final layer in sceneGraph.layers) {
        for (final child in layer.children) {
          if (child is! SectionNode ||
              child == _draggingSectionNode ||
              !child.isVisible)
            continue;
          final otherTx = child.worldTransform.getTranslation();
          final otherLeft = otherTx.x;
          final otherTop = otherTx.y;
          final otherRight = otherLeft + child.sectionSize.width;
          final otherBottom = otherTop + child.sectionSize.height;

          // Horizontal snaps
          if ((newPos.dx - otherLeft).abs() < snapThreshold) {
            newPos = Offset(otherLeft, newPos.dy);
          } else if ((newPos.dx + dragW - otherRight).abs() < snapThreshold) {
            newPos = Offset(otherRight - dragW, newPos.dy);
          } else if ((newPos.dx - otherRight).abs() < snapThreshold) {
            newPos = Offset(otherRight, newPos.dy);
          } else if ((newPos.dx + dragW - otherLeft).abs() < snapThreshold) {
            newPos = Offset(otherLeft - dragW, newPos.dy);
          }

          // Vertical snaps
          if ((newPos.dy - otherTop).abs() < snapThreshold) {
            newPos = Offset(newPos.dx, otherTop);
          } else if ((newPos.dy + dragH - otherBottom).abs() < snapThreshold) {
            newPos = Offset(newPos.dx, otherBottom - dragH);
          } else if ((newPos.dy - otherBottom).abs() < snapThreshold) {
            newPos = Offset(newPos.dx, otherBottom);
          } else if ((newPos.dy + dragH - otherTop).abs() < snapThreshold) {
            newPos = Offset(newPos.dx, otherTop - dragH);
          }
        }
      }

      _draggingSectionNode!.setPosition(newPos.dx, newPos.dy);
      _layerController.sceneGraph.bumpVersion();
      DrawingPainter.invalidateAllTiles();
      _layerController.notifyListeners();
      setState(() {});
      return;
    }

    // 📐 SECTION MODE: Update section rectangle end point
    if (_isSectionActive && _sectionStartPoint != null) {
      _sectionCurrentEndPoint = canvasPosition;
      setState(() {});
      return;
    }

    // 📄 PDF DOCUMENT DRAG: Move entire document block
    // 🚀 LIGHTWEIGHT MODE: only update page positions + set drag rects.
    // Strokes are translated once at drag end, not per frame.
    if (_pdfPageDragController.isDraggingDocument) {
      if (_pdfPageDragController.updateDocumentDrag(canvasPosition)) {
        // Set page rects for lightweight rendering
        final doc = _pdfPageDragController.parentDocument;
        if (doc != null) {
          DrawingPainter.draggedPageRects =
              doc.pageNodes.map((p) => doc.pageRectFor(p)).toList();
        }
        _pdfLayoutVersion++;
        _canvasController.markNeedsPaint();
        setState(() {});
      }
      return;
    }

    // 📄 PDF PAGE DRAG: Update drag position
    // 🚀 LIGHTWEIGHT MODE: only update page position + set drag rect.
    if (_pdfPageDragController.isDragging) {
      if (_pdfPageDragController.updateDrag(canvasPosition)) {
        // Set page rect for lightweight rendering
        final page = _pdfPageDragController.draggingPage;
        final doc = _pdfPageDragController.parentDocument;
        if (page != null && doc != null) {
          DrawingPainter.draggedPageRects = [doc.pageRectFor(page)];
        }
        _pdfLayoutVersion++;
        _canvasController.markNeedsPaint();
        setState(() {});
      }
      return;
    }

    // 🖼️ If there is a saved initial position (tap on image in pan mode), check movement
    if (_effectiveIsPanMode &&
        _initialTapPosition != null &&
        _imageTool.selectedImage != null) {
      final distance = (canvasPosition - _initialTapPosition!).distance;

      if (distance > _FlueraCanvasScreenState._dragThreshold) {
        // Movement detected! Clear timer and start drag
        _imageLongPressTimer?.cancel();
        _imageLongPressEditorTimer?.cancel();

        // Start drag from the initial position
        _imageTool.startDrag(_initialTapPosition!);
        _initialTapPosition = null;
        // 🚀 PERF: Immediately process first drag frame (don't wait for next event)
        final firstUpdate = _imageTool.updateDrag(canvasPosition);
        if (firstUpdate != null) {
          final idx = _imageElements.indexWhere((e) => e.id == firstUpdate.id);
          if (idx != -1) _imageElements[idx] = firstUpdate;
          _imageVersion++;
          _imageRepaintNotifier.value++;
        }
        return;
      } else {
        // Movement too small, wait for timer
        return;
      }
    } // 🌀 Handle single-finger rotation via rotation handle (pan mode only)
    if (_effectiveIsPanMode && _imageTool.isHandleRotating) {
      final updated = _imageTool.updateHandleRotation(canvasPosition);
      if (updated != null) {
        final index = _imageElements.indexWhere((e) => e.id == updated.id);
        if (index != -1) _imageElements[index] = updated;
        _imageVersion++;
        _imageRepaintNotifier.value++;
        // 🔴 RT: Throttled rotation broadcast for live collaboration
        if (_isSharedCanvas) {
          final now = DateTime.now().millisecondsSinceEpoch;
          if (now - _lastDragSyncTime >=
              _FlueraCanvasScreenState._dragSyncThrottleMs) {
            _lastDragSyncTime = now;
            _broadcastImageUpdate(updated);
          }
        }
      }
      return;
    }

    // 🖼️ Handle resize/drag of images (pan mode only)
    if (_effectiveIsPanMode && _imageTool.isResizing) {
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
        // 🚀 PERF: repaint-only path — no full widget rebuild needed.
        // ImagePainter reads _imageElements directly and repaints via controller.
        _imageVersion++;
        _imageRepaintNotifier.value++;
        // 🔴 RT: Throttled resize broadcast for live collaboration
        if (_isSharedCanvas) {
          final now = DateTime.now().millisecondsSinceEpoch;
          if (now - _lastDragSyncTime >=
              _FlueraCanvasScreenState._dragSyncThrottleMs) {
            _lastDragSyncTime = now;
            _broadcastImageUpdate(updated);
          }
        }
      }
      return;
    }

    if (_effectiveIsPanMode && _imageTool.isDragging) {
      final updated = _imageTool.updateDrag(canvasPosition);
      if (updated != null) {
        // 🚀 PERF: Direct list update + repaint — zero overhead path
        final index = _imageElements.indexWhere((e) => e.id == updated.id);
        if (index != -1) {
          _imageElements[index] = updated;
        }

        // 🔄 SYNC: Throttled position update for collaboration
        if (_isSharedCanvas) {
          final now = DateTime.now().millisecondsSinceEpoch;
          if (now - _lastDragSyncTime >=
              _FlueraCanvasScreenState._dragSyncThrottleMs) {
            _lastDragSyncTime = now;
            final wasTracking = _layerController.enableDeltaTracking;
            _layerController.enableDeltaTracking = false;
            _layerController.updateImage(updated);
            _layerController.enableDeltaTracking = wasTracking;
            // 🔴 RT: Live drag broadcast so collaborators see movement
            _broadcastImageUpdate(updated);
          }
        }

        // 🚀 PERF: repaint-only path — no widget rebuild, no smart guides.
        _imageVersion++;
        _imageRepaintNotifier.value++;
      }
      return;
    }

    // 🎯 Always handle digital text resize/drag (regardless of active tool)
    // Handle resize
    if (_digitalTextTool.isResizing) {
      final updated = _digitalTextTool.updateResize(canvasPosition);
      if (updated != null) {
        _syncTextElementFromTool(updated);

        // Auto-scroll at edges (same as drag)
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

    // Handle drag
    if (_digitalTextTool.isDragging) {
      final rawUpdated = _digitalTextTool.updateDrag(canvasPosition);
      if (rawUpdated != null) {
        var updated = rawUpdated;
        // 📐 Smart Guides for text element
        final approxW =
            updated.text.length * updated.fontSize * updated.scale * 0.6;
        final approxH = updated.fontSize * updated.scale * 1.4;
        final draggedBounds = Rect.fromLTWH(
          updated.position.dx,
          updated.position.dy,
          approxW.clamp(40.0, 2000.0),
          approxH.clamp(20.0, 500.0),
        );
        final snap = _applySmartGuides(draggedBounds, excludeId: updated.id);
        if (snap != Offset.zero) {
          updated = updated.copyWith(position: updated.position + snap);
          _digitalTextTool.selectElement(updated);
        }

        // Update the element via centralized sync
        _syncTextElementFromTool(updated);

        // Auto-scroll at edges
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

    // 📊 TabularNode drag (move)
    if (_tabularTool.isDragging) {
      if (_tabularTool.updateDrag(canvasPosition)) {
        _layerController.sceneGraph.bumpVersion();
        DrawingPainter.invalidateAllTiles();
        setState(() {});
      }
      return;
    }

    // 📊 TabularNode resize (column/row border drag)
    if (_tabularTool.isResizing) {
      final newSize = _tabularTool.updateResize(canvasPosition);
      if (newSize != null) {
        _layerController.sceneGraph.bumpVersion();
        DrawingPainter.invalidateAllTiles();
        setState(() {});
      }
      return;
    }

    // 📊 Drag-to-extend-selection (multi-cell range)
    if (_tabularTool.hasCellSelection &&
        _tabularTool.selectedTabular != null &&
        !_tabularTool.isDragging) {
      final cell = _tabularTool.hitTestCell(canvasPosition);
      if (cell != null) {
        _tabularTool.extendSelection(cell.$1, cell.$2);
        setState(() {});
        return;
      }
    }

    // 🧮 LatexNode drag (move)
    if (_isDraggingLatex &&
        _selectedLatexNode != null &&
        _latexDragStart != null) {
      final delta = canvasPosition - _latexDragStart!;
      final t = _selectedLatexNode!.localTransform;
      final pos = t.getTranslation();
      t.setTranslationRaw(pos.x + delta.dx, pos.y + delta.dy, 0);
      _latexDragStart = canvasPosition;
      _layerController.sceneGraph.bumpVersion();
      DrawingPainter.invalidateAllTiles();
      setState(() {});
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
        final dataChanged = _lassoTool.updateDrag(canvasPosition);

        if (dataChanged) {
          // 📐 Smart Guides — only compute when data actually changed
          final lassoBounds = _lassoTool.getSelectionBounds();
          if (lassoBounds != null) {
            final snap = _applySmartGuides(lassoBounds);
            if (snap != Offset.zero) {
              _lassoTool.moveSelected(snap);
            }
          }

          // 🚀 PERF: Only invalidate layer caches when stroke data changed
          DrawingPainter.invalidateLayerCaches();
        }

        // Convert canvasPosition in screenPosition per auto-scroll
        final screenPosition = _canvasController.canvasToScreen(canvasPosition);

        // Get size del widget canvas
        final RenderBox? renderBox =
            _canvasAreaKey.currentContext?.findRenderObject() as RenderBox?;
        if (renderBox != null) {
          final canvasSize = renderBox.size;
          _startAutoScrollIfNeeded(screenPosition, canvasSize);
        }

        // 🚀 PERF: No setState needed — both SelectionTransformOverlay and
        // LassoSelectionOverlay listen to dragNotifier for smooth repositioning.
        return;
      }

      // Altrimenti aggiorna il lasso path
      _lassoTool.updateLasso(canvasPosition);
      // 🚀 PERF: No setState needed — lassoPathNotifier triggers targeted repaint
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
      // 🚀 PERF: Front-trim instead of removeWhere (O(1) amortized vs O(n))
      while (_eraserTrail.isNotEmpty &&
          now - _eraserTrail.first.timestamp > 300) {
        _eraserTrail.removeAt(0);
      }
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
      {
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
            // V5: Invalidate spatial index after erase
            _eraserTool.invalidateSpatialIndex();
            DrawingPainter.invalidateAllTiles();
          }
        } else {
          bool didEraseAny = false;

          // 🚀 PERF: Single batch for the entire interpolation loop.
          // Previously each eraseAt() had its own batch → 30 version bumps/frame.
          // Now: 1 version bump for all removals in this frame.
          _layerController.beginBatch();

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

          // 🚀 Flush batch — single version bump for all removals
          _layerController.endBatch();

          if (didEraseAny) {
            _eraserGestureEraseCount = _eraserTool.currentGestureEraseCount;
            _eraserPulseController.forward(from: 0);

            // 🚀 PERF: Targeted tile invalidation instead of ALL tiles.
            // Only re-rasterize tiles that overlap the erased area.
            final eraseBounds = _eraserTool.lastEraseBounds;
            if (eraseBounds != null) {
              DrawingPainter.invalidateTilesInBounds(eraseBounds);
            } else {
              DrawingPainter.invalidateTileCacheOnly();
            }
            _eraserTool.lastEraseBounds = null;
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

      // 🚀 FIX #1: In-place mutation (zero copies!) + force repaint
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

    // ☁️ REALTIME: Stream live stroke points to collaborators (throttled)
    if (_realtimeEngine != null) {
      final points = _currentStrokeNotifier.value;
      // Throttle: broadcast every 10th point to avoid RTDB rate limiting
      if (points.isNotEmpty && points.length % 10 == 0) {
        final latest = points.sublist(
          (points.length - 5).clamp(0, points.length),
        );
        _broadcastStrokePoints(
          strokeId: 'live_${_canvasId}_${points.first.timestamp}',
          newPoints:
              latest
                  .map((p) => {'x': p.position.dx, 'y': p.position.dy})
                  .toList(),
          penType: _effectivePenType.name,
          color: _effectiveColor.toARGB32(),
          strokeWidth: _effectiveWidth,
        );
      }
    }
  }

  // ==========================================================================
  // 📐 Smart Guides helpers
  // ==========================================================================

  /// Collect bounds of all visible elements except [excludeId].
  List<Rect> _collectTargetBounds({String? excludeId}) {
    final targets = <Rect>[];

    // Images
    for (final img in _imageElements) {
      if (img.id == excludeId) continue;
      final loaded = _loadedImages[img.imagePath];
      if (loaded == null) continue;
      final w = loaded.width.toDouble() * img.scale;
      final h = loaded.height.toDouble() * img.scale;
      targets.add(Rect.fromCenter(center: img.position, width: w, height: h));
    }

    // Digital text elements
    for (final txt in _digitalTextElements) {
      if (txt.id == excludeId) continue;
      // Approximate bounds: position is top-left, estimate size from fontSize
      final approxWidth = txt.text.length * txt.fontSize * txt.scale * 0.6;
      final approxHeight = txt.fontSize * txt.scale * 1.4;
      targets.add(
        Rect.fromLTWH(
          txt.position.dx,
          txt.position.dy,
          approxWidth.clamp(40.0, 2000.0),
          approxHeight.clamp(20.0, 500.0),
        ),
      );
    }

    return targets;
  }

  /// Run smart guide engine and update state. Returns the snap offset to apply.
  Offset _applySmartGuides(Rect draggedBounds, {String? excludeId}) {
    final targets = _collectTargetBounds(excludeId: excludeId);
    final result = SmartGuideEngine.compute(
      draggedBounds: draggedBounds,
      targetBounds: targets,
    );

    // Haptic on first snap
    if (result.hasSnap && _activeSmartGuides.isEmpty) {
      HapticFeedback.selectionClick();
    }

    _activeSmartGuides = result.guides;
    return result.snapOffset;
  }

  /// Clear smart guides (called on drag end).
  void _clearSmartGuides() {
    if (_activeSmartGuides.isNotEmpty) {
      _activeSmartGuides = const [];
      setState(() {});
    }
  }
}
