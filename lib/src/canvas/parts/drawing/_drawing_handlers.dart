part of '../../fluera_canvas_screen.dart';

/// 📦 Drawing Handlers — pointer-down start & cancel
extension on _FlueraCanvasScreenState {
  void _onDrawStart(
    Offset canvasPosition,
    double pressure,
    double tiltX,
    double tiltY,
  ) {
    // 🎚️ SLIDER GUARD: If touching the parameter slider panel, skip canvas processing entirely
    if (_isDraggingGraphSlider) return;

    // 🧠 SEMANTIC VIEW GUARD: Block drawing when zoomed out to semantic nodes.
    // Taps in semantic view are handled by onSingleTap → _handleSemanticNodeTap.
    if (_semanticMorphController != null && _semanticMorphController!.isActive) {
      return;
    }

    // ✍️ SMART INK: Auto-dismiss overlay on any new touch interaction
    if (isSmartInkActive) dismissSmartInk();

    // 🔍 OVERVIEW GUARD: Block drawing when zoomed out below 50%.
    // At this scale strokes would be tiny and unreadable; the user is in
    // overview/navigation mode, not writing mode.
    if (_canvasController.scale <= 0.5) return;

    // 🔒 INLINE EDITING GUARD: If the user taps the canvas while inline text
    // editing is active, finish/cancel the current edit and return.
    // This handles: (1) Back button dismissing keyboard without Flutter unfocus,
    // (2) Canvas Listener firing alongside overlay GestureDetector on same tap.
    if (_isInlineEditing) {
      final currentText = _inlineOverlayKey.currentState?.currentText ?? '';
      if (currentText.trim().isNotEmpty) {
        _finishInlineText(currentText);
      } else {
        _cancelInlineText();
      }
      return;
    }

    // 🔍 ECHO SEARCH INTERCEPT: Route strokes to Query Pen instead of canvas
    if (_echoSearchActive) {
      _echoSearchOnDrawStart(canvasPosition, pressure);
      return;
    }

    // 🧹 KNOWLEDGE FLOW OVERLAY CLEANUP: Clear any active preview/label
    // overlays on new touch. Prevents ghost Positioned.fill GestureDetector
    // from blocking canvas input after tool switches or zoom changes.
    if (_previewingClusterId != null || _editingLabelConnectionId != null) {
      _previewingClusterId = null;
      _previewOverlayScreenPosition = null;
      _editingLabelConnectionId = null;
      _labelOverlayScreenPosition = null;
    }

    // 🌟 RADIAL EXPANSION: Intercept draw-start during bubble presentation
    // Start bubble drag (Minority Report drag-to-confirm) or dismiss on empty tap
    if (_handleRadialExpansionDrawStart(canvasPosition)) return;

    // 🔒 VIEWER GUARD: Prevent all editing on shared canvas if viewer
    if (_checkViewerGuard()) return;

    // 📌 PIN PLACEMENT MODE: Single tap places pin, then exit
    if (_isPinPlacementMode) {
      _completePinPlacement(_canvasController.canvasToScreen(canvasPosition));
      return;
    }

    // 📐 SECTION MODE: Resize / Drag / Create
    if (_isSectionActive) {
      final scale = _canvasController.scale;
      final hitRadius = 20.0 / scale; // 20px in screen space

      // 1. Check corner resize handles on existing sections
      final resizeHit = _findSectionCornerAtPoint(canvasPosition, hitRadius);
      if (resizeHit != null && !resizeHit.$1.isLocked) {
        _resizingSectionNode = resizeHit.$1;
        _resizeAnchorCorner = resizeHit.$2;
        HapticFeedback.selectionClick();
        return;
      }

      // 2. Check if tapping on an existing section → drag mode (skip locked)
      final hitSection = _findSectionAtPoint(canvasPosition);
      if (hitSection != null && !hitSection.isLocked) {
        _draggingSectionNode = hitSection;
        final sectionPos = Offset(
          hitSection.worldTransform.getTranslation().x,
          hitSection.worldTransform.getTranslation().y,
        );
        _sectionDragGrabOffset = canvasPosition - sectionPos;
        HapticFeedback.selectionClick();
        return;
      }

      // 3. Otherwise, start drawing a new section
      _sectionStartPoint = canvasPosition;
      _sectionCurrentEndPoint = canvasPosition;
      _uiRebuildNotifier.value++;
      return;
    }

    // 📌 PIN DRAG: In pan mode, try to start dragging a pin
    if (_effectiveIsPanMode && _recordingPins.isNotEmpty) {
      if (_handleRecordingPinDragStart(canvasPosition)) {
        return;
      }
    }

    // 🐛 FIX: _isDrawingNotifier is set AFTER image interaction checks.
    //    Setting it here hid the Image Actions toolbar during selection.
    //    It's now deferred to after the image/text/PDF handling sections.
    _pushConsciousContext(); // 🧠 Notify intelligence subsystems

    // ☁️ PRESENCE: Broadcast drawing state to collaborators
    if (_isSharedCanvas && _realtimeEngine != null) {
      _broadcastCursorPosition(canvasPosition, isDrawing: true);
    }

    // 🎤 Traccia tempo inizio (per recording esterno)
    _lastStrokeStartTime = DateTime.now();

    // 🌀 ROTATION HANDLE: Check BEFORE auto-deselect so it works in ANY mode.
    // If an image is selected and the user touches the rotation handle, start
    // handle rotation regardless of the current tool.
    if (_imageTool.selectedImage != null) {
      final rawImage = _loadedImages[_imageTool.selectedImage!.imagePath];
      if (rawImage != null) {
        final crop = _imageTool.selectedImage!.cropRect;
        final w = rawImage.width.toDouble();
        final h = rawImage.height.toDouble();
        final imageSize = crop != null
            ? Size((crop.right - crop.left) * w, (crop.bottom - crop.top) * h)
            : Size(w, h);
        if (_imageTool.hitTestRotationHandle(canvasPosition, imageSize)) {
          _imageTool.startHandleRotation(canvasPosition);
          _uiRebuildNotifier.value++;
          return;
        }
      }
    }

    // 🖼️ AUTO-DESELECT IMAGE: When starting any draw action (pen, eraser, etc.)
    // outside pan mode, clear the image selection so the blue outline disappears.
    // 🐛 FIX: setState is required to hide the 'Image Actions' menu button
    //    which is in the main build tree (not reactive via notifiers).
    if (!_effectiveIsPanMode && _imageTool.selectedImage != null) {
      setState(() {
        _imageTool.clearSelection();
      });
      _imageRepaintNotifier.value++;
      _gestureRebuildNotifier.value++; // 🌀 Rebuild gesture layer so image rotation callbacks update
      _uiRebuildNotifier.value++;
    }

    // 🖼️ Image interaction only when PAN (hand) tool is active
    if (_effectiveIsPanMode) {
      if (_imageTool.selectedImage != null) {
        // Check resize handle
        final rawImage = _loadedImages[_imageTool.selectedImage!.imagePath];
        final imageSize =
            rawImage != null
                ? () {
                  final crop = _imageTool.selectedImage!.cropRect;
                  final w = rawImage.width.toDouble();
                  final h = rawImage.height.toDouble();
                  return crop != null
                      ? Size(
                        (crop.right - crop.left) * w,
                        (crop.bottom - crop.top) * h,
                      )
                      : Size(w, h);
                }()
                : Size.zero;

        final handle = _imageTool.hitTestResizeHandle(
          canvasPosition,
          imageSize,
        );
        if (handle != null) {
          _imageTool.startResize(handle, canvasPosition);
          _uiRebuildNotifier.value++;
          return;
        }
      }

      // Check hit test su immagini
      for (final imageElement in _imageElements.reversed) {
        final image = _loadedImages[imageElement.imagePath];
        if (image != null) {
          final imageSize = Size(
            image.width.toDouble(),
            image.height.toDouble(),
          );

          if (_imageTool.hitTest(imageElement, canvasPosition, imageSize)) {
            // 🌀 DOUBLE-TAP RESET: If tapping already-selected image quickly, reset rotation
            final now = DateTime.now().millisecondsSinceEpoch;
            if (_imageTool.selectedImage?.id == imageElement.id &&
                imageElement.rotation != 0.0 &&
                now - _lastImageTapTime < 350) {
              // Reset rotation
              final resetImage = imageElement.copyWith(rotation: 0.0);
              _imageTool.selectImage(resetImage);
              final idx = _imageElements.indexWhere(
                (e) => e.id == resetImage.id,
              );
              if (idx != -1) _imageElements[idx] = resetImage;
              _layerController.updateImage(resetImage);
              _imageVersion++;
              _imageRepaintNotifier.value++;
              HapticFeedback.mediumImpact();
              // 🔴 RT: Broadcast rotation reset to collaborators
              _broadcastImageUpdate(resetImage);
              _lastImageTapTime = 0; // Prevent triple-tap
              _gestureRebuildNotifier.value++; // 🌀 Rebuild gesture layer
              _uiRebuildNotifier.value++;
              return;
            }
            _lastImageTapTime = now;

            // Select the image but do NOT start dragging yet
            // 🐛 FIX: setState needed to show 'Image Actions' menu button
            setState(() {
              _imageTool.selectImage(imageElement);
            });

            // 📍 Save initial position to detect movement
            _initialTapPosition = canvasPosition;

            _gestureRebuildNotifier.value++; // 🌀 Rebuild gesture layer so onImageScaleStart becomes non-null
            _uiRebuildNotifier.value++;
            return; // 🛑 Block other tools when touching image in pan mode
          }
        }
      } // If tocco area vuota con selected image, deseleziona
      if (_imageTool.selectedImage != null) {
        setState(() {
          _imageTool.clearSelection();
        });
        _gestureRebuildNotifier.value++; // 🌀 Rebuild gesture layer so onImageScaleStart becomes null
        _uiRebuildNotifier.value++;
        // Do not return - continua con gli altri tool
      }
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
        _uiRebuildNotifier.value++;
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
      _uiRebuildNotifier.value++;
      return; // 🛑 Block other tools when touching text
    }

    // If tapped on empty area, deselect (if there was a selection)
    if (_digitalTextTool.hasSelection) {
      _digitalTextTool.deselectElement();
      _uiRebuildNotifier.value++;
      // In digital text mode, just deselect — don't create new text on same tap
      if (_effectiveIsDigitalText) return;
      // Do not return — continue with other tools
    }

    // 📊 TabularNode hit-test (after text, before lasso)
    final hitTabular = _tabularTool.hitTest(
      canvasPosition,
      _layerController.sceneGraph,
    );
    if (hitTabular != null) {
      if (_tabularTool.selectedTabular == hitTabular) {
        // Already selected — check border resize FIRST
        final border = _tabularTool.hitTestBorder(canvasPosition);
        if (border != null) {
          _tabularTool.startResize(
            border.isColumn,
            border.index,
            canvasPosition,
          );
          _uiRebuildNotifier.value++;
          return;
        }
        // No border — detect which cell was tapped
        final cell = _tabularTool.hitTestCell(canvasPosition);
        if (cell != null) {
          // If tapping the SAME cell again, enter in-cell editing
          if (cell.$1 == _tabularTool.selectedCol &&
              cell.$2 == _tabularTool.selectedRow) {
            _editingInCell = true;
          } else {
            _editingInCell = false;
            _tabularTool.selectCell(cell.$1, cell.$2);
          }
        } else {
          _editingInCell = false;
          _tabularTool.deselectCell();
        }
        _uiRebuildNotifier.value++;
        return;
      }
      // New table selected
      _tabularTool.selectTabular(hitTabular);
      _tabularTool.startDrag(canvasPosition);
      _uiRebuildNotifier.value++;
      return;
    }
    // Deselect tabular if tapped empty area
    if (_tabularTool.hasSelection) {
      _tabularTool.deselectTabular();
      _uiRebuildNotifier.value++;
    }

    // 🧮 LatexNode hit-test (tap to select/drag, tap away to deselect)
    final hitLatex = _hitTestLatexNode(canvasPosition);
    if (hitLatex != null) {
      _selectedLatexNode = hitLatex;
      _isDraggingLatex = true;
      _latexDragStart = canvasPosition;
      _uiRebuildNotifier.value++;
      return;
    }
    // Deselect LatexNode if tapped empty area
    if (_selectedLatexNode != null) {
      _selectedLatexNode = null;
      _isDraggingLatex = false;
      _uiRebuildNotifier.value++;
    }

    // 📈 FunctionGraphNode: check resize corners FIRST (only if already selected)
    if (_selectedGraphNode != null) {
      final gn = _selectedGraphNode!;
      final gPos = gn.localTransform.getTranslation();
      final gBounds = gn.localBounds.translate(gPos.x, gPos.y);
      final hitRadius = 20.0 / _canvasController.scale;
      final corners = [
        gBounds.topLeft,     // 0=TL
        gBounds.topRight,    // 1=TR
        gBounds.bottomLeft,  // 2=BL
        gBounds.bottomRight, // 3=BR
      ];
      for (int i = 0; i < corners.length; i++) {
        if ((canvasPosition - corners[i]).distance < hitRadius) {
          // Opposite corner is the anchor
          _isResizingGraph = true;
          _graphResizeCorner = i;
          _graphResizeAnchor = corners[3 - i]; // TL↔BR, TR↔BL
          HapticFeedback.selectionClick();
          return;
        }
      }
    }

    // 📈 FunctionGraphNode hit-test (tap to select/drag, double-tap to edit)
    final hitGraph = _hitTestGraphNode(canvasPosition);
    if (hitGraph != null) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (_selectedGraphNode == hitGraph && now - _lastGraphTapTime < 400) {
        // Double-tap → open editor
        _openGraphEditor(hitGraph);
        _lastGraphTapTime = 0;
        return;
      }
      _lastGraphTapTime = now;
      _selectedGraphNode = hitGraph;
      _isDraggingGraph = true;
      _graphPinchStarted = false; // Fresh capture for next pinch
      _graphDragStart = canvasPosition;
      _uiRebuildNotifier.value++;
      return;
    }
    // Deselect FunctionGraphNode if tapped empty area
    if (_selectedGraphNode != null) {
      _selectedGraphNode = null;
      _isDraggingGraph = false;
      _uiRebuildNotifier.value++;
    }

    // If digital text mode is active and no text was hit, create new inline text
    if (_effectiveIsDigitalText) {
      _startInlineTextCreation(canvasPosition);
      return;
    }

    // 🔧 FIX: When lasso tool is active with a selection, CHECK DRAG FIRST
    // This must run BEFORE image/text hit-tests, otherwise those intercept
    // the touch and the lasso drag is never reached.
    if (_effectiveIsLasso && _lassoTool.hasSelection) {
      if (_lassoTool.isPointInSelection(canvasPosition)) {
        _lassoTool.startDrag(canvasPosition);
        _uiRebuildNotifier.value++;
        return;
      }
    }

    // If lasso mode is active (but no selection or tapped outside), start new lasso
    if (_effectiveIsLasso) {
      // #1/#3: If lasso was activated via gestural tap+drag, DON'T start a new
      // lasso here — that would call clearSelection() and destroy the previous
      // selection before a second tap+drag can add to it. Just return early.
      // If this was a single tap (no second tap comes), _onDrawEnd will fire
      // and auto-return to the previous tool.
      if (_wasGesturalLassoActivated) {
        // Save current selection so _onGesturalLassoEnd can use additive mode
        if (_lassoTool.hasSelection) {
          _lassoSelectionBackup = Set<String>.from(_lassoTool.selectedIds);
        }
        _uiRebuildNotifier.value++;
        return;
      }
      // 🔒 Backup selection before starting new lasso — if a zoom gesture
      // interrupts (2nd finger → _onDrawCancel), we restore the selection.
      if (_lassoTool.hasSelection) {
        _lassoSelectionBackup = Set<String>.from(_lassoTool.selectedIds);
      } else {
        _lassoSelectionBackup = null;
      }
      // Mode-aware start: marquee, ellipse, or freehand lasso
      switch (_lassoTool.selectionMode) {
        case SelectionMode.marquee:
          _lassoTool.startMarquee(canvasPosition);
          break;
        case SelectionMode.ellipse:
          _lassoTool.startEllipse(canvasPosition);
          break;
        case SelectionMode.lasso:
          _lassoTool.startLasso(canvasPosition);
          break;
      }
      _uiRebuildNotifier.value++;
      return;
    }
    // ✒️ PEN TOOL: route events to vector path editor
    if (_toolController.isPenToolMode) {
      final screenPos = _canvasController.canvasToScreen(canvasPosition);
      _penTool.onPointerDown(
        _penToolContext,
        PointerDownEvent(position: screenPos),
      );
      _uiRebuildNotifier.value++;
      return;
    }

    // 🐛 FIX: Set drawing flag ONLY when actual drawing/erasing starts,
    // not during image/text/table selection — keeps Image Actions visible.
    _isDrawingNotifier.value = true;
    CanvasPerformanceMonitor.instance.notifyDrawingStarted(); // 🚀 Pause overlay

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
                if (mounted) _uiRebuildNotifier.value++;
              });
              Future.delayed(const Duration(milliseconds: 150), () {
                _eraserTool.undoGhostProgress = 0.6;
                if (mounted) _uiRebuildNotifier.value++;
              });
              Future.delayed(const Duration(milliseconds: 300), () {
                _eraserTool.undoGhostProgress = 1.0;
                if (mounted) _uiRebuildNotifier.value++;
              });
              Future.delayed(const Duration(milliseconds: 400), () {
                _eraserTool.finishUndoGhostReplay();
                _showUndoGhostReplay = false;
                DrawingPainter.invalidateAllTiles();
                if (mounted) _uiRebuildNotifier.value++;
              });
            } else {
              _eraserTool.undo();
            }
            HapticFeedback.mediumImpact();
          }
          _lastEraserPointerDownTime = now; // Keep time for potential triple
          _uiRebuildNotifier.value++;
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
          _uiRebuildNotifier.value++;
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
        _uiRebuildNotifier.value++;
        return;
      }

      // 🎯 V4: Magnetic snap
      final snappedPos = _eraserTool.getNearestStrokePosition(canvasPosition);

      // 🎯 Compute preview (highlight strokes under eraser)
      _eraserPreviewIds = _eraserTool.getPreviewStrokeIds(snappedPos);

      final didErase = _eraserTool.eraseAt(snappedPos);
      if (didErase) {
        _eraserGestureEraseCount = _eraserTool.currentGestureEraseCount;
        _eraserPulseController.forward(from: 0);
        _spawnEraserParticles(snappedPos, now);
      }
      _uiRebuildNotifier.value++; // 🏗️ Forza rebuild per eraser cursor overlay
      return;
    }

    // 📄 PDF PAGE SELECTION: Update toolbar selection when touching any page
    // ✂️ Also track the effective page rect for live stroke clipping.
    _activePdfClipRect = null; // Reset — set below if a page is hit
    for (final layer in _layerController.sceneGraph.layers) {
      for (final child in layer.children) {
        if (child is PdfDocumentNode) {
          final pageIdx = child.hitTestPageIndex(canvasPosition);
          if (pageIdx >= 0) {
            // Auto-select this document in the toolbar
            if (_activePdfDocumentId != child.id) {
              _activePdfDocumentId = child.id;
            }
            if (pageIdx != _pdfSelectedPageIndex) {
              _pdfSelectedPageIndex = pageIdx;
            }
            // ✂️ Compute effective page rect for stroke clipping
            final hitPage = child.pageAt(pageIdx);
            if (hitPage != null) {
              _activePdfClipRect = child.pageRectFor(hitPage);
            }
            // No return — continue to drag check or drawing
          }
        }
      }
    }

    // 📄 PDF PAGE DRAG: Check if touch hits an unlocked PDF page
    if (!_effectiveIsEraser && !_effectiveIsLasso && !_effectiveIsPanMode) {
      for (final layer in _layerController.sceneGraph.layers) {
        for (final child in layer.children) {
          if (child is PdfDocumentNode) {
            final hitPage = child.hitTestUnlockedPage(canvasPosition);
            if (hitPage != null) {
              _pdfPageDragController.startDrag(hitPage, child, canvasPosition);
              DrawingPainter.isDraggingPdf = true;
              _pdfLayoutVersion++;
              _uiRebuildNotifier.value++;
              return;
            }
          }
        }
      }
    }

    // 🖐️ If Pan mode is active, check for document drag first
    if (_effectiveIsPanMode) {
      // 📄 DOCUMENT DRAG: Pan mode + touch on any page → drag entire document
      for (final layer in _layerController.sceneGraph.layers) {
        for (final child in layer.children) {
          if (child is PdfDocumentNode) {
            final pageIdx = child.hitTestPageIndex(canvasPosition);
            if (pageIdx >= 0) {
              _pdfPageDragController.startDocumentDrag(child, canvasPosition);
              DrawingPainter.isDraggingPdf = true;
              _pdfLayoutVersion++;
              _uiRebuildNotifier.value++;
              return;
            }
          }
        }
      }
      // 🧠 KNOWLEDGE FLOW: Tap connection with gesture tool → DEFER to touch-up
      // Don't open label editor on touch-down — long-press may start curve drag.
      // Store as pending; _onDrawEnd will open the editor if no drag happened.
      if (_knowledgeFlowController != null && _clusterCache.isNotEmpty) {
        final scale = _canvasController.scale;
        final hitConn = _knowledgeFlowController!.hitTestConnection(
          canvasPosition, _clusterCache, maxDistance: 20.0 / scale,
        );
        if (hitConn != null) {
          final midCanvas = _knowledgeFlowController!.getConnectionMidpoint(
            hitConn, _clusterCache,
          );
          if (midCanvas != null) {
            final screenPos = _canvasController.canvasToScreen(midCanvas);
            _pendingLabelConnectionId = hitConn.id;
            _pendingLabelScreenPos = screenPos;
            // Don't return — let canvas pan handle the touch normally.
            // The pending state is resolved in _onDrawEnd.
          }
        }
      }
      // ✍️ SMART INK: Tap stroke with gesture tool → DEFER to touch-up
      // Don't open overlay on touch-down — might be a pan gesture.
      // Store as pending; _onDrawEnd will open the overlay if no drag happened.
      final strokeHit = _hitTestStroke(canvasPosition);
      if (strokeHit != null) {
        FlueraSmartInkExtension._pendingSmartInkStroke = strokeHit.stroke;
        FlueraSmartInkExtension._pendingSmartInkScreenPos =
            _canvasController.canvasToScreen(canvasPosition);
        // Don't return — let canvas pan handle the touch normally.
      }
      return; // Pan mode, no page hit — let canvas pan handle it
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
        id: generateUid(),
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
    // 🎯 Reset rendered count to prevent stale values from previous stroke
    // being used for trimming when strokes arrive in the same event batch.
    CurrentStrokePainter.resetForNewStroke();
    _drawWasCancelled = false;

    // 🧹 SCRATCH-OUT v5: Reset accumulator for real-time detection
    _scratchOutAccumulator.reset();
    _scratchOutPreviewIds = const {};
    _scratchOutPreviewArmed = false;
    _scratchOutLastReversalCount = 0;

    // 🚀 ZOOM CHURN FIX: If _onDrawCancel just fired (< 300ms ago),
    // skip all heavy init (Vulkan overlay, WebGPU, findRenderObject, etc.).
    // During zoom, the first finger always triggers _onDrawStart, then
    // the second finger immediately triggers _onDrawCancel. This cycle
    // repeats on every re-pinch and the heavy init/teardown is the
    // root cause of zoom jank.
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastDrawCancelMs < 300) {
      return;
    }

    // 🧠 P1-05: VIRGIN ZONE HAPTIC — subtle feedback on first stroke in empty area.
    // During Step 1, if the user starts drawing in a zone with no nearby content,
    // fire a light haptic to confirm the canvas is alive and ready.
    if (_learningStepController.currentStep == LearningStep.step1Notes) {
      final activeLayer = _layerController.activeLayer;
      if (activeLayer != null) {
        final zoneRadius = 200.0 / _canvasController.scale; // 200px in screen space
        final hasNearbyContent = activeLayer.strokes.any((s) {
          if (s.bounds.isEmpty) return false;
          return s.bounds.inflate(zoneRadius).contains(canvasPosition);
        });
        if (!hasNearbyContent) {
          HapticFeedback.lightImpact();
        }
      }
    }
    // 🔥 VULKAN: Initialize native overlay on first freehand stroke
    if (!_vulkanOverlayActive) {
      _initVulkanOverlayIfNeeded();
    }
    if (_vulkanOverlayActive) {
      // 🔥 Set per-brush opacity: controls Vulkan texture visibility.
      // Highlighter: 0.0 → Vulkan invisible, Flutter stroke shows.
      // Marker: 0.7 → partial opacity for MSAA blending.
      // Others (incl. fountain pen): 1.0 → fully opaque Vulkan rendering.
      final brushOpacity =
          _effectivePenType == ProPenType.highlighter ? 0.0
          : _effectivePenType == ProPenType.marker ? 0.7
          : 1.0;
      _vulkanTextureOpacity.value = brushOpacity;

      // 🚀 DIRECT OVERLAY: Enable CAMetalLayer bypass (iOS only).
      // Renders strokes directly to display, skipping Impeller compositing.
      // Highlighter stays on Flutter path (opacity=0.0 hides native overlay).
      if (brushOpacity > 0.0) {
        _vulkanStrokeOverlay.enableDirectOverlay(opacity: brushOpacity);
      }

      if (kIsWeb && _webGpuOverlayActive) {
        // 🌐 WEB: Initialize WebGPU pipeline if needed, then clear + transform
        if (!_webGpuStrokeOverlay.isInitialized) {
          final rb =
              _canvasAreaKey.currentContext?.findRenderObject() as RenderBox?;
          final canvasSize = rb?.size ?? MediaQuery.of(context).size;
          final dpr = MediaQuery.of(context).devicePixelRatio;
          _webGpuStrokeOverlay.init(
            (canvasSize.width * dpr).toInt(),
            (canvasSize.height * dpr).toInt(),
          );
        }
        _webGpuStrokeOverlay.clear();
        final rb =
            _canvasAreaKey.currentContext?.findRenderObject() as RenderBox?;
        final canvasSize = rb?.size ?? MediaQuery.of(context).size;
        final dpr = MediaQuery.of(context).devicePixelRatio;
        _webGpuStrokeOverlay.setTransform(
          _canvasController,
          (canvasSize.width * dpr).toInt(),
          (canvasSize.height * dpr).toInt(),
          dpr,
        );
      } else {
        // 🔥 NATIVE: Vulkan/Metal clear + transform
        _vulkanStrokeOverlay.clear(); // Clear previous stroke
        final rb =
            _canvasAreaKey.currentContext?.findRenderObject() as RenderBox?;
        final canvasSize = rb?.size ?? MediaQuery.of(context).size;
        final dpr = MediaQuery.of(context).devicePixelRatio;
        _vulkanStrokeOverlay.setTransform(
          _canvasController,
          (canvasSize.width * dpr).toInt(),
          (canvasSize.height * dpr).toInt(),
          dpr,
        );
      }
    }

    if (_is120HzMode && _rawInputProcessor120Hz != null) {
      // 🚀 120Hz MODE: Raw processor per latenza minima
      // 🎯 Reset stabilizer for the new stroke (avoids connecting to previous)
      _drawingHandler.resetStabilizer();
      final stabilizedPos =
          _drawingHandler.stabilizerLevel > 0
              ? _drawingHandler.applyStabilizer(canvasPosition)
              : canvasPosition;
      final point = ProDrawingPoint(
        position: stabilizedPos,
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
    CanvasPerformanceMonitor.instance.notifyDrawingEnded(); // 🚀 Resume overlay

    // 🔥 VULKAN: Clear the GPU overlay so the interrupted stroke doesn't
    // remain visible at the old transform during/after a pan gesture.
    // Without this, the Vulkan texture shows a "ghost" stroke at the
    // pre-pan position while the new stroke draws at the post-pan position.
    if (_vulkanOverlayActive) {
      _vulkanTextureOpacity.value = 0.0;
      _vulkanStrokeOverlay.clear();
      // 🚀 DIRECT OVERLAY: Disable CAMetalLayer bypass on cancel
      _vulkanStrokeOverlay.disableDirectOverlay();
    }

    // 📝 INLINE TEXT CANCEL: If inline text creation was triggered by the
    // first finger, cancel it when a second finger arrives (pinch-zoom).
    if (_isInlineEditing && _inlineEditingElement != null &&
        _inlineEditingElement!.text.isEmpty) {
      _cancelInlineText();
    }

    // 📐 SECTION RESIZE CANCEL: Cancel resize on multi-touch interrupt
    if (_resizingSectionNode != null) {
      _resizingSectionNode = null;
      _resizeAnchorCorner = null;
      _uiRebuildNotifier.value++;
      return;
    }

    // 📐 SECTION DRAG CANCEL: Cancel section drag on multi-touch interrupt
    if (_draggingSectionNode != null) {
      _draggingSectionNode = null;
      _sectionDragGrabOffset = null;
      _uiRebuildNotifier.value++;
      return;
    }

    // 📐 SECTION MODE: Cancel section drawing on multi-touch interrupt
    if (_isSectionActive && _sectionStartPoint != null) {
      _sectionStartPoint = null;
      _sectionCurrentEndPoint = null;
      _uiRebuildNotifier.value++;
      return;
    }

    // 📌 PIN DRAG CANCEL: Cancel pin drag on multi-touch interrupt
    if (_draggingPinId != null) {
      _draggingPinId = null;
      _draggingPinOffset = null;
      _pinDragStartCanvasPos = null;
      _uiRebuildNotifier.value++;
      return;
    }

    // 🤏 LASSO DRAG: Cancel selection drag so two-finger gesture can
    // cleanly transition to pinch-to-transform (rotate/scale).
    // Without this, _lassoTool.isDragging stays true → blockPanZoom()
    // blocks the pinch gesture from routing to selection transform.
    if (_lassoTool.isDragging) {
      _lassoTool.endDrag(skipReflow: true);
    }

    // 🖼️ IMAGE TOOL: Cancel any image drag/resize/handle-rotation so that
    // the two-finger gesture can cleanly transition to image rotation.
    if (_imageTool.isDragging) {
      _imageTool.endDrag();
    }
    if (_imageTool.isResizing) {
      _imageTool.endResize();
    }
    if (_imageTool.isHandleRotating) {
      _imageTool.endHandleRotation();
    }
    // Clear deferred drag start so _onDrawUpdate doesn't re-start drag
    _initialTapPosition = null;
    // Cancel long-press timers (editor dialog etc.)
    _imageLongPressTimer?.cancel();
    _imageLongPressEditorTimer?.cancel();

    // ✂️ Clear PDF clip rect on cancel
    _activePdfClipRect = null;

    // ✍️ SMART INK: Clear deferred tap on multi-touch interrupt
    clearPendingSmartInk();

    // 📊 TabularNode: Cancel any drag/resize so pinch-to-zoom works
    if (_tabularTool.isDragging) {
      _tabularTool.endDrag();
    }
    if (_tabularTool.isResizing) {
      _tabularTool.endResize();
    }

    // 🧮 LatexNode drag cancel (pinch-to-zoom interrupt)
    if (_isDraggingLatex) {
      _isDraggingLatex = false;
      _latexDragStart = null;
    }

    // 📈 FunctionGraphNode drag cancel (pinch-to-zoom interrupt)
    // NOTE: Do NOT reset _isDraggingGraph/_isResizingGraph here!
    // They must stay true during multi-touch so blockPanZoom() blocks
    // canvas pan/zoom while the user is interacting with the graph.
    // They are properly reset in _onDrawEnd when all fingers lift.
    if (_isDraggingGraph) {
      _graphDragStart = null;
    }
    if (_isResizingGraph) {
      _graphResizeCorner = -1;
      _graphResizeAnchor = null;
    }

    // 📄 PDF DOCUMENT DRAG: Cancel document drag on multi-touch interrupt
    if (_pdfPageDragController.isDraggingDocument) {
      // Rollback all document annotation strokes
      final reverseDelta =
          _pdfPageDragController.previousPosition -
          _pdfPageDragController.previousPosition;
      // Strokes were translated incrementally — cancelDrag restores gridOrigin
      // and performGridLayout, but we need to manually reverse stroke translations.
      // Pre-cancel: compute total translation since start
      // Note: cancelDrag handles page positions via gridOrigin reset.
      _pdfPageDragController.cancelDrag();
      DrawingPainter.invalidateAllTiles();
      _pdfLayoutVersion++;
      _uiRebuildNotifier.value++;
      return;
    }

    // 📄 PDF PAGE DRAG: Cancel drag on multi-touch interrupt
    // Strokes were translated in real-time, so roll them back.
    if (_pdfPageDragController.isDragging) {
      // Compute reverse delta: strokes moved (previousPos - startPos),
      // so we need to move them back by -(previousPos - startPos).
      final reverseDelta =
          _pdfPageDragController.dragStartPosition -
          _pdfPageDragController.previousPosition;
      if (reverseDelta != Offset.zero) {
        final ids = _pdfPageDragController.linkedAnnotationIds;
        if (ids.isNotEmpty) {
          final idSet = Set<String>.of(ids);
          for (final layer in _layerController.layers) {
            for (final strokeNode in layer.node.strokeNodes) {
              if (idSet.contains(strokeNode.stroke.id)) {
                final old = strokeNode.stroke;
                final translatedPoints =
                    old.points.map((p) {
                      return p.copyWith(position: p.position + reverseDelta);
                    }).toList();
                strokeNode.stroke = old.copyWith(points: translatedPoints);
              }
            }
          }
        }
      }
      _pdfPageDragController.cancelDrag();
      DrawingPainter.invalidateAllTiles();
      _pdfLayoutVersion++;
      _uiRebuildNotifier.value++;
      return;
    }

    // 🔒 LASSO DRAG CANCEL: If a second finger interrupts an active lasso drag,
    // cancel the drag and restore strokes to pre-drag positions (undo snapshot).
    if (_effectiveIsLasso && _lassoTool.isDragging) {
      _lassoTool.restoreUndo();
      _lassoTool.endDrag();
      _stopAutoScroll();
      DrawingPainter.invalidateAllTiles();
      _lassoSelectionBackup = null;
      _uiRebuildNotifier.value++;
      return;
    }

    // 🔒 Restore lasso selection if a zoom gesture interrupted a new lasso
    if (_effectiveIsLasso && _lassoSelectionBackup != null) {
      _lassoTool.clearLassoPath();
      _lassoTool.restoreSelectionFromIds(_lassoSelectionBackup!);
      _lassoSelectionBackup = null;
      _uiRebuildNotifier.value++;
      return;
    }
    _lassoSelectionBackup = null;

    // Erase the in-progress stroke from the notifier (don't save anything)
    _currentStrokeNotifier.clear();

    // 🧹 SCRATCH-OUT: Set cancelled flag to suppress scratch-out on finger-up
    _drawWasCancelled = true;
    _lastDrawCancelMs = DateTime.now().millisecondsSinceEpoch;


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

  // ===========================================================================
  // 🌀 IMAGE ROTATION — Two-finger rotate on selected image
  // ===========================================================================

  /// Called once when two-finger gesture starts on a selected image
  void _onImageScaleStart() {
    _imageTool.startRotation();
  }

  /// Called continuously with rotation + scale + drag during two-finger gesture
  void _onImageTransform(double rotationDelta, double scaleRatio, Offset focalDelta) {
    final (updated, didSnap) = _imageTool.updateRotation(rotationDelta, scaleRatio);
    if (updated != null) {
      // 🖐️ Apply simultaneous drag: convert screen-space delta to canvas-space.
      // Must un-rotate by canvas rotation AND divide by scale.
      final rot = _canvasController.rotation;
      final scale = _canvasController.scale;
      final cosR = math.cos(-rot);
      final sinR = math.sin(-rot);
      final unrotated = Offset(
        focalDelta.dx * cosR - focalDelta.dy * sinR,
        focalDelta.dx * sinR + focalDelta.dy * cosR,
      );
      final canvasDelta = unrotated / scale;
      final dragged = updated.copyWith(
        position: updated.position + canvasDelta,
      );
      _imageTool.selectImage(dragged); // Keep _selectedImage in sync
      final index = _imageElements.indexWhere((e) => e.id == dragged.id);
      if (index != -1) {
        _imageElements[index] = dragged;
      }
      _imageVersion++;
      _imageRepaintNotifier.value++;
    }
  }

  /// Called when two-finger gesture ends — persist the rotation
  void _onImageScaleEnd() {
    if (_imageTool.selectedImage != null) {
      _layerController.updateImage(_imageTool.selectedImage!);
      // 🔴 RT: Broadcast two-finger scale/rotate to collaborators
      _broadcastImageUpdate(_imageTool.selectedImage!);
      _imageTool.endRotation();
      // 🖼️ Rebuild R-tree + invalidate cache so the standard paint path
      // picks up the new rotation (without this, the old cached picture
      // with pre-rotation angle is drawn → image snaps back visually).
      _imageVersion++;
      _rebuildImageSpatialIndex();
      _uiRebuildNotifier.value++;
      _autoSaveCanvas(); // 💾 Persist rotation to disk
      // 🐛 FIX: setState needed to show 'Image Actions' menu button
      // after auto-selection during two-finger gesture.
      setState(() {});
    }
  }

  // ===========================================================================
  // 🤏 Selection Pinch Transform — two-finger rotate + scale on lasso selection
  // ===========================================================================

  static const double _snapAngleStep = math.pi / 4; // 45°
  static const double _snapTolerance = 0.05; // ~3° in radians
  static const double _minSelectionScale = 0.10; // 10%
  static const double _maxSelectionScale = 5.0;  // 500%

  void _onSelectionScaleStart() {
    _isSelectionPinching = true;
    _selectionPrevRotation = 0.0;
    _selectionPrevScale = 1.0;
    _selectionAccumRotation = 0.0;
    _selectionAccumScale = 1.0;
    _selectionLastSnapAngle = null;
    // Save undo snapshot before transform
    _lassoTool.saveUndoSnapshot();
    // 📳 Haptic on start
    HapticFeedback.mediumImpact();
  }

  void _onSelectionTransform(double rotation, double scaleRatio, Offset focalDelta) {
    if (!_lassoTool.hasSelection) return;

    // 🌀 Rotation delta (gesture gives cumulative rotation)
    final rotDelta = rotation - _selectionPrevRotation;
    _selectionPrevRotation = rotation;

    // Track accumulated rotation for indicator + snap
    _selectionAccumRotation += rotDelta;

    // 🤏 Scale delta (gesture gives cumulative ratio)
    var scaleDelta = scaleRatio / _selectionPrevScale;
    _selectionPrevScale = scaleRatio;

    // 🔒 Scale limits: clamp accumulated scale to 10%–500%
    final projectedScale = _selectionAccumScale * scaleDelta;
    if (projectedScale < _minSelectionScale) {
      scaleDelta = _minSelectionScale / _selectionAccumScale;
    } else if (projectedScale > _maxSelectionScale) {
      scaleDelta = _maxSelectionScale / _selectionAccumScale;
    }
    _selectionAccumScale *= scaleDelta;

    // 🔄 Snap to 45° increments with haptic
    double effectiveRotDelta = rotDelta;
    if (rotDelta.abs() > 0.001) {
      final nearestSnap = (_selectionAccumRotation / _snapAngleStep).round() * _snapAngleStep;
      final distToSnap = (_selectionAccumRotation - nearestSnap).abs();
      if (distToSnap < _snapTolerance) {
        final snappedAccum = nearestSnap;
        effectiveRotDelta = rotDelta + (snappedAccum - _selectionAccumRotation);
        _selectionAccumRotation = snappedAccum;
        if (_selectionLastSnapAngle == null || (_selectionLastSnapAngle! - nearestSnap).abs() > 0.01) {
          _selectionLastSnapAngle = nearestSnap;
          HapticFeedback.lightImpact();
        }
      } else {
        _selectionLastSnapAngle = null;
      }
    }

    // 🚀 Combined single-pass rotate + scale (avoids double iteration)
    _lassoTool.rotateAndScaleSelected(effectiveRotDelta, scaleDelta);

    // 🖐️ Apply drag: convert screen-space focal delta to canvas-space
    if (focalDelta.distance > 0.1) {
      final rot = _canvasController.rotation;
      final scale = _canvasController.scale;
      final cosR = math.cos(-rot);
      final sinR = math.sin(-rot);
      final unrotated = Offset(
        focalDelta.dx * cosR - focalDelta.dy * sinR,
        focalDelta.dx * sinR + focalDelta.dy * cosR,
      );
      final canvasDelta = unrotated / scale;
      _lassoTool.moveSelected(canvasDelta);
    }

    // 🚀 PERF: Only triggerRepaint — skip invalidateAllTiles during active pinch.
    DrawingPainter.triggerRepaint();
    _uiRebuildNotifier.value++;
  }

  void _onSelectionScaleEnd() {
    _isSelectionPinching = false;
    _selectionPrevRotation = 0.0;
    _selectionPrevScale = 1.0;
    _selectionAccumRotation = 0.0;
    _selectionAccumScale = 1.0;
    _selectionLastSnapAngle = null;

    // 📳 Haptic on end
    HapticFeedback.lightImpact();

    // Persist changes — invalidate active layer stroke cache
    final activeLayer = _layerController.layers.firstWhere(
      (l) => l.id == _layerController.activeLayerId,
      orElse: () => _layerController.layers.first,
    );
    activeLayer.node.invalidateStrokeCache();
    DrawingPainter.invalidateAllTiles();
    DrawingPainter.triggerRepaint();
    _uiRebuildNotifier.value++;
    _autoSaveCanvas();
  }

  /// 🚫 Cancel selection pinch and restore undo snapshot
  void _cancelSelectionPinch() {
    if (!_isSelectionPinching) return;
    _isSelectionPinching = false;
    _selectionPrevRotation = 0.0;
    _selectionPrevScale = 1.0;
    _selectionAccumRotation = 0.0;
    _selectionAccumScale = 1.0;
    _selectionLastSnapAngle = null;

    // Restore from undo snapshot
    _lassoTool.restoreUndo();
    HapticFeedback.heavyImpact();

    // Repaint with restored state
    final activeLayer = _layerController.layers.firstWhere(
      (l) => l.id == _layerController.activeLayerId,
      orElse: () => _layerController.layers.first,
    );
    activeLayer.node.invalidateStrokeCache();
    DrawingPainter.invalidateAllTiles();
    DrawingPainter.triggerRepaint();
    _uiRebuildNotifier.value++;
  }

  // ===========================================================================
  // 🧮 LatexNode — hit-test, delete
  // ===========================================================================

  /// Hit-test all LatexNodes on the canvas. Returns the first LatexNode
  /// whose world-space bounds contain [canvasPosition], or null.
  LatexNode? _hitTestLatexNode(Offset canvasPosition) {
    for (final layer in _layerController.layers) {
      for (final child in layer.node.children) {
        if (child is LatexNode && child.isVisible) {
          final pos = child.localTransform.getTranslation();
          final bounds = child.localBounds.translate(pos.x, pos.y);
          if (bounds.contains(canvasPosition)) {
            return child;
          }
        }
      }
    }
    return null;
  }

  /// 📈 Hit-test all FunctionGraphNodes on the canvas.
  FunctionGraphNode? _hitTestGraphNode(Offset canvasPosition) {
    for (final layer in _layerController.layers) {
      for (final child in layer.node.children) {
        if (child is FunctionGraphNode && child.isVisible) {
          final pos = child.localTransform.getTranslation();
          final bounds = child.localBounds.translate(pos.x, pos.y);
          if (bounds.contains(canvasPosition)) {
            return child;
          }
        }
      }
    }
    return null;
  }

  /// 📈 Open graph editor for a FunctionGraphNode (double-tap-to-edit).
  void _openGraphEditor(FunctionGraphNode graphNode) {
    // A5: Save old viewport for smooth transition later
    final oldXMin = graphNode.xMin, oldXMax = graphNode.xMax;
    final oldYMin = graphNode.yMin, oldYMax = graphNode.yMax;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: LatexFunctionGraph(
          latexSource: graphNode.latexSource,
          accentColor: graphNode.curveColor,
          onInsertToCanvas: (latexSource, xMin, xMax, yMin, yMax, curveColor) {
            // Update existing node instead of creating new
            graphNode.latexSource = latexSource;
            graphNode.curveColorValue = curveColor;

            // A5: Smooth viewport transition (animate old → new over 300ms)
            final viewportChanged =
                xMin != oldXMin || xMax != oldXMax ||
                yMin != oldYMin || yMax != oldYMax;

            if (viewportChanged) {
              final startMs = DateTime.now().millisecondsSinceEpoch;
              const durationMs = 300;
              void _animateViewport() {
                if (!mounted) return;
                final elapsed = DateTime.now().millisecondsSinceEpoch - startMs;
                final t = (elapsed / durationMs).clamp(0.0, 1.0);
                // Ease-out cubic
                final ease = 1.0 - (1.0 - t) * (1.0 - t) * (1.0 - t);

                graphNode.xMin = oldXMin + (xMin - oldXMin) * ease;
                graphNode.xMax = oldXMax + (xMax - oldXMax) * ease;
                graphNode.yMin = oldYMin + (yMin - oldYMin) * ease;
                graphNode.yMax = oldYMax + (yMax - oldYMax) * ease;
                graphNode.invalidateCache();
                _layerController.sceneGraph.bumpVersion();
                DrawingPainter.invalidateAllTiles();
                DrawingPainter.triggerRepaint();
                _uiRebuildNotifier.value++;

                if (t < 1.0) {
                  WidgetsBinding.instance.addPostFrameCallback((_) => _animateViewport());
                }
              }
              WidgetsBinding.instance.addPostFrameCallback((_) => _animateViewport());
            } else {
              graphNode.xMin = xMin;
              graphNode.xMax = xMax;
              graphNode.yMin = yMin;
              graphNode.yMax = yMax;
              graphNode.invalidateCache();
            }
            _layerController.sceneGraph.bumpVersion();
            setState(() {});
            _autoSaveCanvas();
          },
        ),
      ),
    );
  }

  /// 📈 A3: Long-press context menu for a FunctionGraphNode.
  void _showGraphContextMenu(FunctionGraphNode graphNode, Offset screenPos) {
    HapticFeedback.mediumImpact();
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(screenPos.dx, screenPos.dy, screenPos.dx, screenPos.dy),
      items: [
        const PopupMenuItem(value: 'edit',  child: ListTile(leading: Icon(Icons.edit, size: 20), title: Text('Modifica'), dense: true)),
        const PopupMenuItem(value: 'table', child: ListTile(leading: Icon(Icons.table_chart, size: 20), title: Text('Tabella Valori'), dense: true)),
        const PopupMenuItem(value: 'duplicate', child: ListTile(leading: Icon(Icons.copy, size: 20), title: Text('Duplica'), dense: true)),
        const PopupMenuItem(value: 'reset', child: ListTile(leading: Icon(Icons.refresh, size: 20), title: Text('Reset Viewport'), dense: true)),
        const PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline, size: 20, color: Colors.red), title: Text('Elimina', style: TextStyle(color: Colors.red)), dense: true)),
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'edit':
          _openGraphEditor(graphNode);
          break;
        case 'table':
          _showGraphValueTable(graphNode);
          break;
        case 'duplicate':
          final clone = graphNode.cloneInternal() as FunctionGraphNode;
          final t = clone.localTransform;
          final p = t.getTranslation();
          t.setTranslationRaw(p.x + 30, p.y + 30, 0);
          // Add to active layer, NOT rootNode
          _layerController.sceneGraph.layers.first.add(clone);
          _selectedGraphNode = clone;
          _layerController.sceneGraph.bumpVersion();
          DrawingPainter.invalidateAllTiles();
          DrawingPainter.triggerRepaint();
          _uiRebuildNotifier.value++;
          _autoSaveCanvas();
          break;
        case 'reset':
          graphNode.xMin = -10; graphNode.xMax = 10;
          graphNode.yMin = -10; graphNode.yMax = 10;
          graphNode.invalidateCache();
          _layerController.sceneGraph.bumpVersion();
          DrawingPainter.invalidateAllTiles();
          DrawingPainter.triggerRepaint();
          _uiRebuildNotifier.value++;
          _autoSaveCanvas();
          break;
        case 'delete':
          for (final layer in _layerController.layers) {
            final children = layer.node.children.toList();
            if (children.contains(graphNode)) {
              layer.node.remove(graphNode);
              break;
            }
          }
          _selectedGraphNode = null;
          _isDraggingGraph = false;
          _layerController.sceneGraph.bumpVersion();
          DrawingPainter.invalidateAllTiles();
          DrawingPainter.triggerRepaint();
          _uiRebuildNotifier.value++;
          _autoSaveCanvas();
          break;
      }
    });
  }

  /// 📊 Show a value table for the selected graph function.
  void _showGraphValueTable(FunctionGraphNode node) {
    final fns = node.functions;
    if (fns.isEmpty) return;
    final step = (node.xMax - node.xMin) / 10;
    final rows = <TableRow>[];

    // Header
    rows.add(TableRow(
      decoration: BoxDecoration(
        color: node.curveColor.withValues(alpha: 0.15),
      ),
      children: [
        Padding(padding: const EdgeInsets.all(8), child: Text('x', style: TextStyle(fontWeight: FontWeight.w700, fontFamily: 'monospace', fontSize: 13))),
        Padding(padding: const EdgeInsets.all(8), child: Text('f(x)', style: TextStyle(fontWeight: FontWeight.w700, fontFamily: 'monospace', fontSize: 13))),
      ],
    ));

    for (int i = 0; i <= 10; i++) {
      final x = node.xMin + step * i;
      final y = node.evaluateAt(x);
      final yStr = y != null && y.isFinite ? y.toStringAsFixed(4) : '—';
      rows.add(TableRow(
        decoration: BoxDecoration(
          color: i.isEven ? Colors.transparent : Colors.grey.withValues(alpha: 0.06),
        ),
        children: [
          Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), child: Text(x.toStringAsFixed(2), style: const TextStyle(fontFamily: 'monospace', fontSize: 12))),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), child: Text(yStr, style: const TextStyle(fontFamily: 'monospace', fontSize: 12))),
        ],
      ));
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('f(x) = ${fns.first}', style: const TextStyle(fontSize: 14, fontFamily: 'monospace')),
        content: SingleChildScrollView(
          child: Table(
            columnWidths: const {
              0: FlexColumnWidth(1),
              1: FlexColumnWidth(1.5),
            },
            border: TableBorder.all(color: Colors.grey.withValues(alpha: 0.2), width: 0.5),
            children: rows,
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Chiudi'))],
      ),
    );
  }

  /// Delete the currently selected LatexNode from the scene graph.
  void _deleteSelectedLatexNode() {
    final node = _selectedLatexNode;
    if (node == null) return;

    // Find and remove from the layer
    for (final layer in _layerController.layers) {
      final children = layer.node.children.toList();
      if (children.contains(node)) {
        layer.node.remove(node);
        break;
      }
    }

    _selectedLatexNode = null;
    _isDraggingLatex = false;
    _latexDragStart = null;
    _layerController.sceneGraph.bumpVersion();
    DrawingPainter.invalidateAllTiles();
    HapticFeedback.mediumImpact();
    _uiRebuildNotifier.value++;
    _autoSaveCanvas();
  }

  void _showChartSettingsDialog(BuildContext context, LatexNode node) {
    final titleCtrl = TextEditingController(text: node.chartTitle ?? node.name);
    bool showLegend = node.chartShowLegend;
    bool showAvg = node.chartShowAvg;
    bool showTrend = node.chartShowTrend;
    bool showValues = node.chartShowValues;
    String valueDisplay = node.chartValueDisplay;
    int? bgColor = node.chartBgColor;
    String chartType = node.chartType ?? 'bar';
    int palette = node.chartColorPalette;
    String sizePreset = node.chartSizePreset;
    int? axisColor = node.chartAxisColor;

    // Background presets.
    const bgPresets = <int?>[
      null, // default gradient
      0xF01E1E2E, // deep navy
      0xF02D1B3D, // dark purple
      0xF01B2D2D, // dark teal
      0xF02D2D1B, // dark olive
      0xF02D1B1B, // dark red
      0xF01A1A1A, // pure dark
      0xF0FFFFFF, // white
      0x00000000, // transparent
    ];
    const bgPresetLabels = [
      'Default',
      'Navy',
      'Purple',
      'Teal',
      'Olive',
      'Red',
      'Dark',
      'White',
      'Transparent',
    ];

    // Color palette preview data.
    const palNames = ['Neon', 'Pastel', 'Earth', 'Ocean', 'Sunset'];
    const palColors = <List<Color>>[
      [
        Color(0xFF7C4DFF),
        Color(0xFF00E5FF),
        Color(0xFFFF6D00),
        Color(0xFF00E676),
      ],
      [
        Color(0xFFA78BFA),
        Color(0xFF93C5FD),
        Color(0xFFFCA5A5),
        Color(0xFF86EFAC),
      ],
      [
        Color(0xFFD97706),
        Color(0xFF059669),
        Color(0xFF92400E),
        Color(0xFF065F46),
      ],
      [
        Color(0xFF0EA5E9),
        Color(0xFF06B6D4),
        Color(0xFF3B82F6),
        Color(0xFF14B8A6),
      ],
      [
        Color(0xFFF43F5E),
        Color(0xFFF97316),
        Color(0xFFEAB308),
        Color(0xFFEC4899),
      ],
    ];

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            Widget toggleRow(
              String label,
              bool value,
              void Function(bool) onChanged,
            ) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: const TextStyle(
                          color: Color(0x99FFFFFF),
                          fontSize: 12,
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 28,
                      child: Switch(
                        value: value,
                        activeTrackColor: const Color(0xFF7C4DFF),
                        onChanged: (v) => setDialogState(() => onChanged(v)),
                      ),
                    ),
                  ],
                ),
              );
            }

            return AlertDialog(
              backgroundColor: const Color(0xFF1E1E2E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text(
                'Chart Settings',
                style: TextStyle(
                  color: Color(0xFFF0F0FF),
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              content: SizedBox(
                width: 340,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Title ──
                      const Text(
                        'Title',
                        style: TextStyle(
                          color: Color(0x99FFFFFF),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: titleCtrl,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: const Color(0xFF2A2A3A),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          hintText: 'Chart title…',
                          hintStyle: const TextStyle(color: Color(0x50FFFFFF)),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ── Chart Type ──
                      const Text(
                        'Chart Type',
                        style: TextStyle(
                          color: Color(0x99FFFFFF),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _typeChip(
                            ctx,
                            setDialogState,
                            'bar',
                            Icons.bar_chart,
                            chartType,
                            (t) => chartType = t,
                          ),
                          _typeChip(
                            ctx,
                            setDialogState,
                            'line',
                            Icons.show_chart,
                            chartType,
                            (t) => chartType = t,
                          ),
                          _typeChip(
                            ctx,
                            setDialogState,
                            'scatter',
                            Icons.scatter_plot,
                            chartType,
                            (t) => chartType = t,
                          ),
                          _typeChip(
                            ctx,
                            setDialogState,
                            'pie',
                            Icons.pie_chart,
                            chartType,
                            (t) => chartType = t,
                          ),
                          _typeChip(
                            ctx,
                            setDialogState,
                            'area',
                            Icons.area_chart,
                            chartType,
                            (t) => chartType = t,
                          ),
                          _typeChip(
                            ctx,
                            setDialogState,
                            'stacked_bar',
                            Icons.stacked_bar_chart,
                            chartType,
                            (t) => chartType = t,
                          ),
                          _typeChip(
                            ctx,
                            setDialogState,
                            'hbar',
                            Icons.align_horizontal_left,
                            chartType,
                            (t) => chartType = t,
                          ),
                          _typeChip(
                            ctx,
                            setDialogState,
                            'radar',
                            Icons.hexagon_outlined,
                            chartType,
                            (t) => chartType = t,
                          ),
                          _typeChip(
                            ctx,
                            setDialogState,
                            'waterfall',
                            Icons.waterfall_chart,
                            chartType,
                            (t) => chartType = t,
                          ),
                          _typeChip(
                            ctx,
                            setDialogState,
                            'bubble',
                            Icons.bubble_chart,
                            chartType,
                            (t) => chartType = t,
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // ── Background ──
                      const Text(
                        'Background',
                        style: TextStyle(
                          color: Color(0x99FFFFFF),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: List.generate(bgPresets.length, (i) {
                          final preset = bgPresets[i];
                          final isTransparent = preset == 0x00000000;
                          final isSelected = bgColor == preset;
                          final displayColor =
                              isTransparent
                                  ? const Color(0xFF252530)
                                  : preset != null
                                  ? Color(preset)
                                  : const Color(0xFF252530);
                          return Tooltip(
                            message: bgPresetLabels[i],
                            child: GestureDetector(
                              onTap:
                                  () => setDialogState(() => bgColor = preset),
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: displayColor,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color:
                                        isSelected
                                            ? const Color(0xFF7C4DFF)
                                            : const Color(0x30FFFFFF),
                                    width: isSelected ? 2.5 : 1,
                                  ),
                                ),
                                child:
                                    isSelected
                                        ? const Icon(
                                          Icons.check,
                                          color: Color(0xFF7C4DFF),
                                          size: 16,
                                        )
                                        : null,
                              ),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 16),

                      // ── Axis Color ──
                      const Text(
                        'Axis Color',
                        style: TextStyle(
                          color: Color(0x99FFFFFF),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final entry in <MapEntry<String, int?>>[
                            const MapEntry('Default', null),
                            const MapEntry('White', 0xFFFFFFFF),
                            const MapEntry('Yellow', 0xFFFFD740),
                            const MapEntry('Cyan', 0xFF00E5FF),
                            const MapEntry('Green', 0xFF00E676),
                            const MapEntry('Orange', 0xFFFF6D00),
                            const MapEntry('Red', 0xFFFF5252),
                          ])
                            Tooltip(
                              message: entry.key,
                              child: GestureDetector(
                                onTap:
                                    () => setDialogState(
                                      () => axisColor = entry.value,
                                    ),
                                child: Container(
                                  width: 30,
                                  height: 30,
                                  decoration: BoxDecoration(
                                    color:
                                        entry.value != null
                                            ? Color(entry.value!)
                                            : const Color(0xFF2A2A3A),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color:
                                          axisColor == entry.value
                                              ? const Color(0xFF7C4DFF)
                                              : const Color(0x30FFFFFF),
                                      width: axisColor == entry.value ? 2.5 : 1,
                                    ),
                                  ),
                                  child:
                                      axisColor == entry.value
                                          ? const Icon(
                                            Icons.check,
                                            color: Color(0xFF7C4DFF),
                                            size: 14,
                                          )
                                          : entry.value == null
                                          ? const Icon(
                                            Icons.auto_awesome,
                                            color: Color(0x60FFFFFF),
                                            size: 14,
                                          )
                                          : null,
                                ),
                              ),
                            ),
                        ],
                      ),

                      // ── Color Palette ──
                      const Text(
                        'Color Palette',
                        style: TextStyle(
                          color: Color(0x99FFFFFF),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: List.generate(palNames.length, (i) {
                          final isSelected = palette == i;
                          return Tooltip(
                            message: palNames[i],
                            child: GestureDetector(
                              onTap: () => setDialogState(() => palette = i),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      isSelected
                                          ? const Color(0xFF2A2A4A)
                                          : const Color(0xFF2A2A3A),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color:
                                        isSelected
                                            ? const Color(0xFF7C4DFF)
                                            : const Color(0x30FFFFFF),
                                    width: isSelected ? 2 : 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    for (int c = 0; c < 4; c++)
                                      Container(
                                        width: 10,
                                        height: 10,
                                        margin: const EdgeInsets.only(right: 2),
                                        decoration: BoxDecoration(
                                          color: palColors[i][c],
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    const SizedBox(width: 2),
                                    Text(
                                      palNames[i],
                                      style: TextStyle(
                                        color:
                                            isSelected
                                                ? Colors.white
                                                : const Color(0x80FFFFFF),
                                        fontSize: 10,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 16),

                      // ── Chart Size ──
                      const Text(
                        'Chart Size',
                        style: TextStyle(
                          color: Color(0x99FFFFFF),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children:
                            ['small', 'medium', 'large'].map((s) {
                              final label = s[0].toUpperCase() + s.substring(1);
                              final isSelected = sizePreset == s;
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: GestureDetector(
                                  onTap:
                                      () =>
                                          setDialogState(() => sizePreset = s),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          isSelected
                                              ? const Color(0xFF7C4DFF)
                                              : const Color(0xFF2A2A3A),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color:
                                            isSelected
                                                ? const Color(0xFF7C4DFF)
                                                : const Color(0x30FFFFFF),
                                      ),
                                    ),
                                    child: Text(
                                      label,
                                      style: TextStyle(
                                        color:
                                            isSelected
                                                ? Colors.white
                                                : const Color(0x70FFFFFF),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                      ),

                      // ── Display Options ──
                      const Text(
                        'Display Options',
                        style: TextStyle(
                          color: Color(0x99FFFFFF),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      toggleRow(
                        'Show Legend',
                        showLegend,
                        (v) => showLegend = v,
                      ),
                      toggleRow(
                        'Show Average Line',
                        showAvg,
                        (v) => showAvg = v,
                      ),
                      toggleRow(
                        'Show Value Labels',
                        showValues,
                        (v) => showValues = v,
                      ),
                      if (showValues) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Text(
                              'Format:  ',
                              style: TextStyle(
                                color: Color(0x70FFFFFF),
                                fontSize: 11,
                              ),
                            ),
                            for (final entry in <MapEntry<String, String>>[
                              const MapEntry('value', 'Value'),
                              const MapEntry('percent', '%'),
                              const MapEntry('both', 'Both'),
                            ])
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: GestureDetector(
                                  onTap:
                                      () => setDialogState(
                                        () => valueDisplay = entry.key,
                                      ),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          valueDisplay == entry.key
                                              ? const Color(0xFF7C4DFF)
                                              : const Color(0xFF2A2A3A),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color:
                                            valueDisplay == entry.key
                                                ? const Color(0xFF7C4DFF)
                                                : const Color(0x30FFFFFF),
                                        width: 1,
                                      ),
                                    ),
                                    child: Text(
                                      entry.value,
                                      style: TextStyle(
                                        color:
                                            valueDisplay == entry.key
                                                ? Colors.white
                                                : const Color(0x70FFFFFF),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                      if (chartType == 'scatter')
                        toggleRow(
                          'Show Trend Line',
                          showTrend,
                          (v) => showTrend = v,
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Color(0x80FFFFFF)),
                  ),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF7C4DFF),
                  ),
                  onPressed: () {
                    final newTitle = titleCtrl.text.trim();
                    node.chartTitle = newTitle.isNotEmpty ? newTitle : null;
                    node.chartBgColor = bgColor;
                    node.chartShowLegend = showLegend;
                    node.chartShowAvg = showAvg;
                    node.chartShowTrend = showTrend;
                    node.chartShowValues = showValues;
                    node.chartValueDisplay = valueDisplay;
                    node.chartColorPalette = palette;
                    node.chartAxisColor = axisColor;
                    node.chartSizePreset = sizePreset;
                    node.chartType = chartType;
                    node.cachedLayout = null;
                    _layerController.sceneGraph.bumpVersion();
                    DrawingPainter.invalidateAllTiles();
                    _uiRebuildNotifier.value++;
                    _autoSaveCanvas();
                    Navigator.pop(ctx);
                  },
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Helper: chart type selection chip.
  Widget _typeChip(
    BuildContext ctx,
    StateSetter setDialogState,
    String type,
    IconData icon,
    String currentType,
    void Function(String) onSelect,
  ) {
    final isSelected = currentType == type;
    return GestureDetector(
      onTap: () => setDialogState(() => onSelect(type)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF7C4DFF) : const Color(0xFF2A2A3A),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color:
                isSelected ? const Color(0xFF7C4DFF) : const Color(0x30FFFFFF),
          ),
        ),
        child: Icon(
          icon,
          color: isSelected ? Colors.white : const Color(0x70FFFFFF),
          size: 20,
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // 🔥 VULKAN: Lazy GPU overlay initialization
  // ═══════════════════════════════════════════════════════════════════

  /// Initialize the Vulkan stroke overlay on first use.
  /// Falls back silently if Vulkan is not available.
  void _initVulkanOverlayIfNeeded() {
    // 🐧🪟 DESKTOP: Skip native overlay (GL/D3D11) — use Dart CurrentStrokePainter.
    // This ensures live strokes look identical to committed strokes (same
    // BrushEngine code path). Native tessellation produces visually different
    // output from Skia's path rendering.
    if (PlatformGuard.isLinux || PlatformGuard.isWindows) return;

    // 🌐 WEB: Use WebGPU overlay instead of Vulkan/Metal
    if (kIsWeb) {
      if (_webGpuOverlayActive || _vulkanOverlayActive) return;
      // WebGPU init is async — register view factory and set active
      // The actual WebGPU pipeline is initialized in JS when the canvas
      // element becomes available in the DOM.
      WebGpuOverlayView.registerViewFactory();
      setState(() {
        _webGpuOverlayActive = true;
        _vulkanOverlayActive = true; // Reuse same flag to skip Dart rendering
      });
      return;
    }

    if (_vulkanOverlayActive || _vulkanTextureId != null) {
      _vulkanOverlayActive = true;
      return;
    }
    _vulkanStrokeOverlay.isAvailable.then((available) {
      if (!available || !mounted) return;
      final rb =
          _canvasAreaKey.currentContext?.findRenderObject() as RenderBox?;
      final canvasSize = rb?.size ?? MediaQuery.of(context).size;
      final dpr = MediaQuery.of(context).devicePixelRatio;
      _vulkanStrokeOverlay
          .init(
            (canvasSize.width * dpr).toInt(),
            (canvasSize.height * dpr).toInt(),
          )
          .then((textureId) {
            if (textureId != null && mounted) {
              setState(() {
                _vulkanTextureId = textureId;
                _vulkanOverlayActive = true;
              });
            }
          });
    });
  }

  // =========================================================================
  // 🔲 GESTURAL LASSO: Tap + Drag → temporary lasso selection
  // =========================================================================

  // NOTE: _isGesturalLassoActive field is declared in fluera_canvas_screen.dart

  /// Called when tap + drag gesture is confirmed (finger moved > threshold after
  /// second tap). Activates the lasso tool for the duration of the gesture
  /// WITHOUT switching the active tool in UnifiedToolController.
  void _onGesturalLassoStart(Offset canvasPosition) {
    _isGesturalLassoActive = true;

    // Silently remove the dot stroke created by the first tap —
    // but ONLY if we were in drawing mode (pen/pencil). If the tool
    // was already 'lasso', the first tap didn't create a dot.
    if (_toolController.activeToolId != 'lasso') {
      _layerController.discardLastAction();
    }

    // #1: Save current tool so we can auto-return after deselect
    _previousToolBeforeGesturalLasso = _toolController.activeToolId;
    _wasGesturalLassoActivated = true;

    // #3: Additive selection — backup existing selection IDs.
    // If the user already has elements selected, the new lasso will ADD
    // to that selection instead of replacing it.
    if (_lassoTool.hasSelection) {
      _lassoSelectionBackup = Set<String>.from(_lassoTool.selectedIds);
    } else {
      _lassoSelectionBackup = null;
    }

    // #3: Start lasso WITHOUT clearing existing selection.
    // We manually init the path instead of calling startLasso() which clears.
    _lassoTool.lassoPath.clear();
    _lassoTool.lassoPath.add(canvasPosition);
    _lassoTool.lassoPathNotifier.value++;

    // #10: Reset velocity tracking
    _gesturalLassoLastPoint = canvasPosition;
    _gesturalLassoLastTime = DateTime.now().millisecondsSinceEpoch;

    HapticFeedback.selectionClick();
    _uiRebuildNotifier.value++;
  }

  /// #4: Simple smoothing buffer for gestural lasso path points.
  /// Averages the last N points to reduce jitter.
  // NOTE: _gesturalLassoSmoothBuffer is declared in fluera_canvas_screen.dart
  static const int _gesturalLassoSmoothWindow = 3;

  Offset _smoothLassoPoint(Offset raw) {
    _gesturalLassoSmoothBuffer.add(raw);
    if (_gesturalLassoSmoothBuffer.length > _gesturalLassoSmoothWindow) {
      _gesturalLassoSmoothBuffer.removeAt(0);
    }
    double sx = 0, sy = 0;
    for (final p in _gesturalLassoSmoothBuffer) {
      sx += p.dx;
      sy += p.dy;
    }
    final n = _gesturalLassoSmoothBuffer.length;
    return Offset(sx / n, sy / n);
  }

  // #10: Velocity tracking for path simplification\n  // NOTE: _gesturalLassoLastPoint and _gesturalLassoLastTime are declared\n  // in fluera_canvas_screen.dart

  /// Called on every pointer move while gestural lasso is active.
  void _onGesturalLassoUpdate(Offset canvasPosition) {
    if (!_isGesturalLassoActive) return;

    // #10: Velocity-based path simplification
    // Fast drag → skip close points. Slow drag → keep all.
    final now = DateTime.now().millisecondsSinceEpoch;
    final dt = (now - _gesturalLassoLastTime).clamp(1, 1000);
    final dist = (canvasPosition - _gesturalLassoLastPoint).distance;
    final velocity = dist / dt * 1000; // px/sec
    if (velocity > 2000 && dist < 3.0) return; // Skip redundant point

    _gesturalLassoLastPoint = canvasPosition;
    _gesturalLassoLastTime = now;

    // #4: Apply path smoothing
    final smoothed = _smoothLassoPoint(canvasPosition);
    _lassoTool.updateLasso(smoothed);
    // 🚀 PERF: No setState needed — lassoPathNotifier triggers targeted repaint
  }

  /// Called when the finger lifts, completing the gestural lasso selection.
  void _onGesturalLassoEnd(Offset canvasPosition) {
    if (!_isGesturalLassoActive) return;
    _isGesturalLassoActive = false;
    _gesturalLassoSmoothBuffer.clear(); // #4: Reset smooth buffer

    final path = _lassoTool.lassoPath;

    // #9: Minimum area safety — ignore micro-drags
    if (path.length < 5) {
      _lassoTool.lassoPath.clear();
      _lassoTool.lassoPathNotifier.value++;
      _autoReturnFromGesturalLasso();
      _uiRebuildNotifier.value++;
      return;
    }

    // #9: Check bounding box area — too small = accidental
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final p in path) {
      if (p.dx < minX) minX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy > maxY) maxY = p.dy;
    }
    final area = (maxX - minX) * (maxY - minY);
    // Scale threshold by zoom: 400px² at 1x
    final scale = _canvasController.scale;
    final minArea = 400.0 / (scale * scale);
    if (area < minArea) {
      _lassoTool.lassoPath.clear();
      _lassoTool.lassoPathNotifier.value++;
      _autoReturnFromGesturalLasso();
      _uiRebuildNotifier.value++;
      return;
    }

    // #11: Cancel on return to start — thin line back and forth
    final startToEnd = (path.first - path.last).distance;
    if (startToEnd < 15.0 && area < minArea * 3) {
      _lassoTool.lassoPath.clear();
      _lassoTool.lassoPathNotifier.value++;
      _autoReturnFromGesturalLasso();
      _uiRebuildNotifier.value++;
      return;
    }

    // #3: Enable additive mode if there was a previous selection
    final hadPreviousSelection = _lassoSelectionBackup != null &&
        _lassoSelectionBackup!.isNotEmpty;
    if (hadPreviousSelection) {
      _lassoTool.additiveMode = true;
    }

    _lassoTool.completeLasso();

    // #3: Restore additive mode
    if (hadPreviousSelection) {
      _lassoTool.additiveMode = false;
    }

    if (_lassoTool.hasSelection) {
      HapticFeedback.mediumImpact();
      _toolController.selectTool('lasso');

      // #4 (visual): Trigger closing ripple at selection center
      final bounds = _lassoTool.getSelectionBounds();
      if (bounds != null) {
        _lassoRippleCenter = _canvasController.canvasToScreen(bounds.center);
        _lassoRippleController?.forward(from: 0);
      }
      // #8: Toast selection count via ActionFlashOverlay
      final count = _lassoTool.selectedIds.length;
      final label = count == 1 ? '1 elemento selezionato' : '$count elementi selezionati';
      _actionFlashKey.currentState?.showText(label);
    } else {
      // #1: No selection found — auto-return to previous tool
      _autoReturnFromGesturalLasso();
    }
    _uiRebuildNotifier.value++;
  }

  /// #1: Auto-return to the tool that was active before the gestural lasso.
  /// Called when the user deselects (taps outside) or when no elements are found.
  void _autoReturnFromGesturalLasso() {
    final prev = _previousToolBeforeGesturalLasso;
    _previousToolBeforeGesturalLasso = null;
    _wasGesturalLassoActivated = false;
    // Only return if we're currently in lasso mode (from gestural activation)
    if (_toolController.isLassoMode) {
      _toolController.selectTool(prev); // null = drawing mode
    }
  }
}

