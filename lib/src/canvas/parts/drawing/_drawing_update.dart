part of '../../fluera_canvas_screen.dart';

/// 📦 Drawing Update — continuous pointer-move handling during draw
extension on _FlueraCanvasScreenState {
  void _onDrawUpdate(
    Offset canvasPosition,
    double pressure,
    double tiltX,
    double tiltY,
  ) {
    // 🔒 INLINE EDITING GUARD
    if (_isInlineEditing) return;

    // 🧠 KNOWLEDGE FLOW: Update connection drag position + snap detection
    if (_isConnectionDragging && _knowledgeFlowController != null) {
      _connectionDragCurrentPoint = canvasPosition;

      // Detect magnetic snap to nearest cluster
      final snap = _knowledgeFlowController!.findNearestCluster(
        canvasPosition,
        _clusterCache,
        maxDistance: 60.0 / _canvasController.scale,
        excludeClusterId: _connectionDragSourceClusterId,
      );

      final prevSnap = _connectionSnapTargetClusterId;
      _connectionSnapTargetClusterId = snap?.id;

      // Haptic feedback on new snap
      if (snap != null && snap.id != prevSnap) {
        HapticFeedback.lightImpact();
      }

      _knowledgeFlowController!.version.value++;
      _uiRebuildNotifier.value++;
      return;
    }

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
        _uiRebuildNotifier.value++;
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
      _uiRebuildNotifier.value++;
      return;
    }

    // 📐 SECTION MODE: Update section rectangle end point
    if (_isSectionActive && _sectionStartPoint != null) {
      _sectionCurrentEndPoint = canvasPosition;
      _uiRebuildNotifier.value++;
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
        _uiRebuildNotifier.value++;
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
        _uiRebuildNotifier.value++;
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
    if (_imageTool.isHandleRotating) {
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

        _uiRebuildNotifier.value++;
      }
      return;
    }

    // Handle drag
    if (_digitalTextTool.isDragging) {
      final updated = _digitalTextTool.updateDrag(canvasPosition);
      if (updated != null) {
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

        _uiRebuildNotifier.value++;
      }
      return;
    }

    // 📊 TabularNode drag (move)
    if (_tabularTool.isDragging) {
      if (_tabularTool.updateDrag(canvasPosition)) {
        _layerController.sceneGraph.bumpVersion();
        DrawingPainter.invalidateAllTiles();
        _uiRebuildNotifier.value++;
      }
      return;
    }

    // 📊 TabularNode resize (column/row border drag)
    if (_tabularTool.isResizing) {
      final newSize = _tabularTool.updateResize(canvasPosition);
      if (newSize != null) {
        _layerController.sceneGraph.bumpVersion();
        DrawingPainter.invalidateAllTiles();
        _uiRebuildNotifier.value++;
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
        _uiRebuildNotifier.value++;
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
      _uiRebuildNotifier.value++;
      return;
    }

    // 📈 FunctionGraphNode resize (drag corner)
    if (_isResizingGraph &&
        _selectedGraphNode != null &&
        _graphResizeAnchor != null) {
      final anchor = _graphResizeAnchor!;
      final newRect = Rect.fromPoints(anchor, canvasPosition);
      // Enforce minimum size
      if (newRect.width >= 80 && newRect.height >= 60) {
        _selectedGraphNode!.graphWidth = newRect.width;
        _selectedGraphNode!.graphHeight = newRect.height;
        _selectedGraphNode!.localTransform.setTranslationRaw(
          newRect.left, newRect.top, 0,
        );
        _selectedGraphNode!.invalidateCache();
        _layerController.sceneGraph.bumpVersion();
        DrawingPainter.triggerRepaint();
        _uiRebuildNotifier.value++;
      }
      return;
    }

    // 📈 FunctionGraphNode interaction: trace cursor (default) or move (long-press)
    if (_isDraggingGraph &&
        _selectedGraphNode != null) {
      final node = _selectedGraphNode!;

      if (_isMovingGraph && _graphDragStart != null) {
        // 🔀 MOVE MODE (long-press initiated): reposition graph on canvas
        final delta = canvasPosition - _graphDragStart!;
        final t = node.localTransform;
        final pos = t.getTranslation();
        var newX = pos.x + delta.dx;
        var newY = pos.y + delta.dy;
        final dragW = node.graphWidth;
        final dragH = node.graphHeight;
        final snapThreshold = 10.0 / _canvasController.scale;

        // Snap to other sections and graph nodes
        for (final layer in _layerController.sceneGraph.layers) {
          for (final child in layer.children) {
            if (child == node || !child.isVisible) continue;
            final otherTx = child.worldTransform.getTranslation();
            final otherBounds = child.localBounds;
            final oL = otherTx.x, oT = otherTx.y;
            final oR = oL + otherBounds.width, oB = oT + otherBounds.height;

            if ((newX - oL).abs() < snapThreshold) newX = oL;
            else if ((newX + dragW - oR).abs() < snapThreshold) newX = oR - dragW;
            else if ((newX - oR).abs() < snapThreshold) newX = oR;
            else if ((newX + dragW - oL).abs() < snapThreshold) newX = oL - dragW;

            if ((newY - oT).abs() < snapThreshold) newY = oT;
            else if ((newY + dragH - oB).abs() < snapThreshold) newY = oB - dragH;
            else if ((newY - oB).abs() < snapThreshold) newY = oB;
            else if ((newY + dragH - oT).abs() < snapThreshold) newY = oT - dragH;
          }
        }

        t.setTranslationRaw(newX, newY, 0);
        _graphDragStart = canvasPosition;
      } else {
        // 📍 TRACE MODE (default): show coordinates along the curve
        final pos = node.localTransform.getTranslation();
        final localX = canvasPosition.dx - pos.x;
        final graphX = node.xMin +
            (localX / node.graphWidth) * (node.xMax - node.xMin);
        node.traceX = graphX;

        // 📍 Auto-scroll viewport: when trace nears edge, shift viewport
        final range = node.xMax - node.xMin;
        final margin = range * 0.05; // 5% edge margin
        if (graphX < node.xMin + margin) {
          final shift = margin * 2;
          node.xMin -= shift;
          node.xMax -= shift;
          node.invalidateCache();
        } else if (graphX > node.xMax - margin) {
          final shift = margin * 2;
          node.xMin += shift;
          node.xMax += shift;
          node.invalidateCache();
        }
      }

      _layerController.sceneGraph.bumpVersion();
      DrawingPainter.triggerRepaint();
      _uiRebuildNotifier.value++;
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

      // Altrimenti aggiorna il lasso path (mode-aware)
      switch (_lassoTool.selectionMode) {
        case SelectionMode.marquee:
          _lassoTool.updateMarquee(canvasPosition);
          break;
        case SelectionMode.ellipse:
          _lassoTool.updateEllipse(canvasPosition);
          break;
        case SelectionMode.lasso:
          _lassoTool.updateLasso(canvasPosition);
          break;
      }
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
      _uiRebuildNotifier.value++;
      return;
    }

    // If l'eraser is active, cancella at the point
    if (_effectiveIsEraser) {
      final now = DateTime.now().millisecondsSinceEpoch;

      // 🎯 V4: Lasso mode — collect path points, don't erase
      if (_eraserLassoMode) {
        _eraserLassoPoints.add(canvasPosition);
        _eraserCursorPosition = canvasPosition;
        _uiRebuildNotifier.value++;
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

      _uiRebuildNotifier.value++; // 🏗️ Forza rebuild per eraser cursor overlay
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
      // 🎯 Apply stabilizer even in 120Hz mode (user-controlled setting)
      final stabilizedPos =
          _drawingHandler.stabilizerLevel > 0
              ? _drawingHandler.applyStabilizer(canvasPosition)
              : canvasPosition;

      // 📐 TECHNICAL PEN: All smart features at input level
      // For angle snap: use raw position (stabilizer delays corners).
      // For non-angle-snap tech pen: use stabilized position.
      Offset drawPos = (_effectivePenType == ProPenType.technicalPen &&
              _brushSettings.techAngleSnap)
          ? canvasPosition
          : stabilizedPos;
      if (_effectivePenType == ProPenType.technicalPen) {
        final pts = _currentStrokeNotifier.value;

        // 🔲 Grid snap: quantize position to grid + haptic on cell change
        if (_brushSettings.techGridSnap) {
          final g = _brushSettings.techGridSize;
          drawPos = Offset(
            (drawPos.dx / g).round() * g,
            (drawPos.dy / g).round() * g,
          );
          if (_techLastGridCell != drawPos) {
            if (_techLastGridCell != null) HapticFeedback.selectionClick();
            _techLastGridCell = drawPos;
          }
        }

        // ═══════════════════════════════════════════════════════════════
        // 🧲 ANGLE SNAP STATE MACHINE (locked-angle projection)
        //
        // GUARANTEES:
        // - Every drawn point lies EXACTLY on a line from anchor at the
        //   locked angle. No intermediate/curved positions ever.
        // - Angle lock requires 20px from anchor to prevent tremor issues.
        // - Corner requires 3 consecutive frames with raw angle in new
        //   sector AND >25px from anchor, preventing false triggers.
        // - Projection uses dot product: only movement ALONG the locked
        //   direction extends the line. Perpendicular movement is ignored.
        // ═══════════════════════════════════════════════════════════════
        if (_brushSettings.techAngleSnap) {
          final snapRad = _brushSettings.techSnapAngleDeg * math.pi / 180.0;

          // Build candidate snap angles (grid angles + parallel/perp)
          List<double>? extraAngles;
          if (_techLastStrokeAngleRad != null) {
            extraAngles = [];
            if (_brushSettings.techParallelSnap) {
              extraAngles.add(_techLastStrokeAngleRad!);
              extraAngles.add(_techLastStrokeAngleRad! + math.pi);
            }
            if (_brushSettings.techPerpSnap) {
              extraAngles.add(_techLastStrokeAngleRad! + math.pi / 2);
              extraAngles.add(_techLastStrokeAngleRad! - math.pi / 2);
            }
          }

          if (_techAnchor == null) {
            // ── INIT: set anchor, no angle yet ──
            _techAnchor = drawPos;
            _techLockedAngle = null;
            _techPrevRawAngle = null;
          } else {
            final delta = drawPos - _techAnchor!;
            final dist = delta.distance;

            if (_techLockedAngle == null) {
              // ── UNLOCKED: waiting for user to move 8px to lock angle ──
              if (dist < 8.0) {
                drawPos = _techAnchor!; // Stay at anchor until direction clear
              } else {
                final rawAngle = math.atan2(delta.dy, delta.dx);
                _techLockedAngle = _bestSnapAngle(rawAngle, snapRad, extraAngles);
                _techPrevRawAngle = rawAngle;
                HapticFeedback.selectionClick();
                // Project immediately
                final projDist = delta.dx * math.cos(_techLockedAngle!) +
                    delta.dy * math.sin(_techLockedAngle!);
                drawPos = _techAnchor! + Offset(
                  projDist * math.cos(_techLockedAngle!),
                  projDist * math.sin(_techLockedAngle!),
                );
              }
            } else {
              // ── LOCKED: project onto line, check for corners ──
              if (dist < 3.0) {
                drawPos = _techAnchor!;
              } else {
                final rawAngle = math.atan2(delta.dy, delta.dx);
                final snappedAngle = _bestSnapAngle(rawAngle, snapRad, extraAngles);
                bool cornerFired = false;

                // Corner detection with hysteresis
                if (_angleDiff(snappedAngle, _techLockedAngle!).abs() > 0.01 && dist > 15.0) {
                  final diffToNew = _angleDiff(rawAngle, snappedAngle).abs();
                  final halfSector = snapRad / 2.0;
                  // Must be deep into new sector (>60% depth)
                  final deepEnough = diffToNew < halfSector * 0.4;
                  // Previous frame must also be in new sector
                  // (null after a corner → blocks cascade for 1 frame)
                  final prevSnapped = _techPrevRawAngle != null
                      ? _bestSnapAngle(_techPrevRawAngle!, snapRad, extraAngles)
                      : _techLockedAngle!;
                  final prevAlsoNew = _techPrevRawAngle != null &&
                      _angleDiff(prevSnapped, _techLockedAngle!).abs() > 0.01;

                  if (deepEnough && prevAlsoNew) {
                    // ── CORNER CONFIRMED ──
                    _techAnchor = pts.isNotEmpty ? pts.last.position : drawPos;
                    _techLockedAngle = snappedAngle;
                    _techPrevRawAngle = null; // ⚡ Cooldown: blocks next corner for 1 frame
                    cornerFired = true;
                    HapticFeedback.selectionClick();
                  }
                }

                if (!cornerFired) {
                  _techPrevRawAngle = rawAngle;
                }

                // ── PROJECT: recompute delta from CURRENT anchor ──
                final projDelta = drawPos - _techAnchor!;
                final dirX = math.cos(_techLockedAngle!);
                final dirY = math.sin(_techLockedAngle!);
                final projDist = projDelta.dx * dirX + projDelta.dy * dirY;
                drawPos = _techAnchor! + Offset(
                  projDist * dirX,
                  projDist * dirY,
                );
              }
            }

            // 📏 Update visual overlay — ONLY when angle is locked
            if (_techLockedAngle != null && _brushSettings.techShowGuides) {
              final guideDelta = drawPos - _techAnchor!;
              if (guideDelta.distance > 10.0) {
                _techSnapAnchor = _techAnchor;
                // Round to clean integer degrees (avoids 89.999° artifacts)
                final rawDeg = _techLockedAngle! * 180.0 / math.pi;
                _techSnapAngleDeg = rawDeg.roundToDouble();
                _techSegmentLength = guideDelta.distance;
              }
            } else {
              // Not locked yet → clear any stale guide data
              _techSnapAnchor = null;
              _techSnapAngleDeg = null;
              _techSegmentLength = null;
            }
          }
        }

        // 🔗 Close-shape proximity: detect when near start point
        if (_brushSettings.techEndpointSnap && pts.length >= 3) {
          final start = pts.first.position;
          final dist = (drawPos - start).distance;
          final threshold = math.max(_effectiveWidth * 10.0, 30.0);
          final wasNear = _techNearStartPoint;
          _techNearStartPoint = dist < threshold && dist > 0.1;
          if (_techNearStartPoint && !wasNear) HapticFeedback.mediumImpact();
        }

        // 📏 Straight line assist: SKIP when angle snap is active (already straight)
        if (_brushSettings.techStraightAssist &&
            !_brushSettings.techAngleSnap &&
            pts.length >= 5) {
          final recent = pts.sublist(math.max(0, pts.length - 8));
          final first = recent.first.position;
          final directDist = (drawPos - first).distance;
          double pathLen = 0;
          for (int i = 1; i < recent.length; i++) {
            pathLen += (recent[i].position - recent[i - 1].position).distance;
          }
          pathLen += (drawPos - recent.last.position).distance;
          if (pathLen > 10.0 && directDist / pathLen > 0.95) {
            final dir = (drawPos - first);
            final t = dir.distance;
            if (t > 1.0) {
              final norm = Offset(dir.dx / t, dir.dy / t);
              final proj = (drawPos - first).dx * norm.dx + (drawPos - first).dy * norm.dy;
              drawPos = first + norm * proj;
              _techStraightGhostEnd = drawPos;
            }
          } else {
            _techStraightGhostEnd = null;
          }
        }

        // 🔍 Intersection detection: check current segment against existing strokes
        if (_brushSettings.techShowGuides && pts.length >= 2) {
          final segStart = pts.last.position;
          final segEnd = drawPos;
          final intersections = <Offset>[];
          try {
            final activeLayer = _layerController.layers.firstWhere(
              (l) => l.id == _layerController.activeLayerId,
              orElse: () => _layerController.layers.first,
            );
            final layerStrokes = activeLayer.strokes;
            final checkCount = math.min(layerStrokes.length, 5);
            for (int s = layerStrokes.length - 1;
                s >= layerStrokes.length - checkCount && s >= 0; s--) {
              final strokePts = layerStrokes[s].points;
              final maxJ = math.min(strokePts.length, 200);
              for (int j = 1; j < maxJ; j++) {
                final ix = _lineIntersection(
                  segStart, segEnd,
                  strokePts[j - 1].position, strokePts[j].position,
                );
                if (ix != null) intersections.add(ix);
              }
            }
          } catch (_) {}
          _techIntersections = intersections;
        }

        // Trigger UI rebuild for overlays
        _uiRebuildNotifier.value++;
      }

      final smoothedPressure =
          _drawingHandler.stabilizerLevel > 0
              ? _drawingHandler.smoothPressure(pressure.clamp(0.0, 1.0))
              : pressure.clamp(0.0, 1.0);
      final point = ProDrawingPoint(
        position: drawPos,
        pressure: smoothedPressure,
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

      // 📐 TECHNICAL PEN: Same state machine as 120Hz
      Offset snapPos60 = canvasPosition;
      if (_effectivePenType == ProPenType.technicalPen) {
        if (_brushSettings.techGridSnap) {
          final g = _brushSettings.techGridSize;
          snapPos60 = Offset(
            (snapPos60.dx / g).round() * g,
            (snapPos60.dy / g).round() * g,
          );
        }
       // 🧲 Angle snap: FULL state machine (same logic as 120Hz)
        if (_brushSettings.techAngleSnap) {
          final snapRad = _brushSettings.techSnapAngleDeg * math.pi / 180.0;

          // Build candidate snap angles (grid angles + parallel/perp)
          List<double>? extraAngles;
          if (_techLastStrokeAngleRad != null) {
            extraAngles = [
              _techLastStrokeAngleRad!,
              _techLastStrokeAngleRad! + math.pi,
              _techLastStrokeAngleRad! + math.pi / 2,
              _techLastStrokeAngleRad! - math.pi / 2,
            ];
          }

          if (_techAnchor == null) {
            // ── INIT: set anchor on first point ──
            _techAnchor = snapPos60;
            _techLockedAngle = null;
            _techPrevRawAngle = null;
            snapPos60 = _techAnchor!;
          } else {
            final delta = snapPos60 - _techAnchor!;
            final dist = delta.distance;

            if (_techLockedAngle == null) {
              // ── UNLOCKED: waiting for 8px to lock angle ──
              if (dist < 8.0) {
                snapPos60 = _techAnchor!;
              } else {
                final rawAngle = math.atan2(delta.dy, delta.dx);
                _techLockedAngle = _bestSnapAngle(rawAngle, snapRad, extraAngles);
                _techPrevRawAngle = rawAngle;
                HapticFeedback.selectionClick();
                final projDist = delta.dx * math.cos(_techLockedAngle!) +
                    delta.dy * math.sin(_techLockedAngle!);
                snapPos60 = _techAnchor! + Offset(
                  projDist * math.cos(_techLockedAngle!),
                  projDist * math.sin(_techLockedAngle!),
                );
              }
            } else {
              // ── LOCKED: project onto line, check for corners ──
              if (dist < 3.0) {
                snapPos60 = _techAnchor!;
              } else {
                final rawAngle = math.atan2(delta.dy, delta.dx);
                final snappedAngle = _bestSnapAngle(rawAngle, snapRad, extraAngles);
                bool cornerFired = false;

                // Corner detection with hysteresis
                if (_angleDiff(snappedAngle, _techLockedAngle!).abs() > 0.01 && dist > 15.0) {
                  final diffToNew = _angleDiff(rawAngle, snappedAngle).abs();
                  final halfSector = snapRad / 2.0;
                  final deepEnough = diffToNew < halfSector * 0.4;
                  final prevSnapped = _techPrevRawAngle != null
                      ? _bestSnapAngle(_techPrevRawAngle!, snapRad, extraAngles)
                      : _techLockedAngle!;
                  final prevAlsoNew = _techPrevRawAngle != null &&
                      _angleDiff(prevSnapped, _techLockedAngle!).abs() > 0.01;

                  if (deepEnough && prevAlsoNew) {
                    final pts60 = _currentStrokeNotifier.value;
                    _techAnchor = pts60.isNotEmpty ? pts60.last.position : snapPos60;
                    _techLockedAngle = snappedAngle;
                    _techPrevRawAngle = null;
                    cornerFired = true;
                    HapticFeedback.selectionClick();
                  }
                }

                if (!cornerFired) {
                  _techPrevRawAngle = rawAngle;
                }

                // Project from CURRENT anchor
                final projDelta = snapPos60 - _techAnchor!;
                final dirX = math.cos(_techLockedAngle!);
                final dirY = math.sin(_techLockedAngle!);
                final projDist = projDelta.dx * dirX + projDelta.dy * dirY;
                snapPos60 = _techAnchor! + Offset(projDist * dirX, projDist * dirY);
              }
            }

            // ── OVERLAY: update guide display ──
            if (_techLockedAngle != null) {
              _techSnapAnchor = _techAnchor;
              _techSnapAngleDeg = ((_techLockedAngle! * 180.0 / math.pi) % 360).round().toDouble();
              _techSegmentLength = (snapPos60 - _techAnchor!).distance;
            } else {
              _techSnapAnchor = null;
              _techSnapAngleDeg = null;
              _techSegmentLength = null;
            }
          }
        }
      }
      _drawingHandler.updateStroke(
        position: snapPos60,
        pressure: pressure,
        tiltX: tiltX,
        tiltY: tiltY,
        orientation: 0.0,
      );
    }

    // 🔥 VULKAN: Forward points to native GPU renderer (parallel to Flutter path)
    // ⚡ Skip highlighter: Vulkan shaders don't support translucent triangle-strip
    // with multiply blend mode. The GPU would render an opaque ballpoint stroke
    // instead, overriding the Flutter translucent highlighter appearance.
    if (_vulkanOverlayActive && _effectivePenType != ProPenType.highlighter) {
      final brushType =
          _effectivePenType == ProPenType.marker
              ? 1
              : _effectivePenType == ProPenType.pencil
              ? 2
              : _effectivePenType == ProPenType.technicalPen
              ? 3
              : _effectivePenType == ProPenType.fountain
              ? 4
              : 0;

      if (kIsWeb && _webGpuOverlayActive) {
        // 🌐 WEB: Forward to WebGPU renderer
        _webGpuStrokeOverlay.updateAndRender(
          _currentStrokeNotifier.value,
          _effectiveColor,
          _effectiveWidth,
          brushType: brushType,
          pencilBaseOpacity: _brushSettings.pencilBaseOpacity,
          pencilMaxOpacity: _brushSettings.pencilMaxOpacity,
          pencilMinPressure: _effectivePenType == ProPenType.ballpoint
              ? _brushSettings.ballpointMinPressure
              : _brushSettings.pencilMinPressure,
          pencilMaxPressure: _effectivePenType == ProPenType.ballpoint
              ? _brushSettings.ballpointMaxPressure
              : _brushSettings.pencilMaxPressure,
          fountainThinning: _brushSettings.fountainThinning,
          fountainNibAngleDeg: _brushSettings.fountainNibAngleDeg,
          fountainNibStrength: _brushSettings.fountainNibStrength,
          fountainPressureRate: _brushSettings.fountainPressureRate,
          fountainTaperEntry: _brushSettings.fountainTaperEntry,
        );
      } else {
        // 🔥 NATIVE: Forward to Vulkan/Metal renderer
        _vulkanStrokeOverlay.updateAndRender(
          _currentStrokeNotifier.value,
          _effectiveColor,
          _effectiveWidth,
          brushType: brushType,
          pencilBaseOpacity: _brushSettings.pencilBaseOpacity,
          pencilMaxOpacity: _brushSettings.pencilMaxOpacity,
          pencilMinPressure: _effectivePenType == ProPenType.ballpoint
              ? _brushSettings.ballpointMinPressure
              : _brushSettings.pencilMinPressure,
          pencilMaxPressure: _effectivePenType == ProPenType.ballpoint
              ? _brushSettings.ballpointMaxPressure
              : _brushSettings.pencilMaxPressure,
          fountainThinning: _brushSettings.fountainThinning,
          fountainNibAngleDeg: _brushSettings.fountainNibAngleDeg,
          fountainNibStrength: _brushSettings.fountainNibStrength,
          fountainPressureRate: _brushSettings.fountainPressureRate,
          fountainTaperEntry: _brushSettings.fountainTaperEntry,
        );
      }
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
  /// Clear smart guides (called on drag end).
  void _clearSmartGuides() {
    if (_activeSmartGuides.isNotEmpty) {
      _activeSmartGuides = const [];
      _uiRebuildNotifier.value++;
    }
  }

  /// 📐 Signed angular difference, normalized to [-π, π].
  double _angleDiff(double a, double b) {
    var d = a - b;
    while (d > math.pi) d -= 2 * math.pi;
    while (d < -math.pi) d += 2 * math.pi;
    return d;
  }

  /// 📐 Find the best snap angle from grid angles + optional extra angles.
  /// Returns the candidate angle that is closest to [rawAngle].
  double _bestSnapAngle(double rawAngle, double snapRad, List<double>? extras) {
    // Grid snap: nearest multiple of snapRad
    double best = (rawAngle / snapRad).round() * snapRad;
    double bestDiff = _angleDiff(rawAngle, best).abs();
    // Check extras (parallel/perp angles from previous stroke)
    if (extras != null) {
      for (final ea in extras) {
        final diff = _angleDiff(rawAngle, ea).abs();
        if (diff < bestDiff) {
          bestDiff = diff;
          best = ea;
        }
      }
    }
    return best;
  }

  /// 🔍 2D line segment intersection — returns point if segments cross, null otherwise.
  Offset? _lineIntersection(Offset a1, Offset a2, Offset b1, Offset b2) {
    final d1 = a2 - a1;
    final d2 = b2 - b1;
    final cross = d1.dx * d2.dy - d1.dy * d2.dx;
    if (cross.abs() < 1e-10) return null; // Parallel

    final d = b1 - a1;
    final t = (d.dx * d2.dy - d.dy * d2.dx) / cross;
    final u = (d.dx * d1.dy - d.dy * d1.dx) / cross;

    if (t >= 0 && t <= 1 && u >= 0 && u <= 1) {
      return Offset(a1.dx + t * d1.dx, a1.dy + t * d1.dy);
    }
    return null;
  }
}
