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

    // Indica che l'utente sta disegnando (per opacity layer panel)
    _isDrawingNotifier.value = true;

    // ☁️ PRESENCE: Broadcast drawing state to collaborators
    if (_isSharedCanvas && _realtimeEngine != null) {
      _broadcastCursorPosition(canvasPosition, isDrawing: true);
    }

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

      // 🌀 Check rotation handle first (above the image)
      if (_imageTool.hitTestRotationHandle(canvasPosition, imageSize)) {
        _imageTool.startHandleRotation(canvasPosition);
        setState(() {});
        return;
      }

      final handle = _imageTool.hitTestResizeHandle(canvasPosition, imageSize);
      if (handle != null) {
        _imageTool.startResize(handle, canvasPosition);
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
          // 🌀 DOUBLE-TAP RESET: If tapping already-selected image quickly, reset rotation
          final now = DateTime.now().millisecondsSinceEpoch;
          if (_imageTool.selectedImage?.id == imageElement.id &&
              imageElement.rotation != 0.0 &&
              now - _lastImageTapTime < 350) {
            // Reset rotation
            final resetImage = imageElement.copyWith(rotation: 0.0);
            _imageTool.selectImage(resetImage);
            final idx = _imageElements.indexWhere((e) => e.id == resetImage.id);
            if (idx != -1) _imageElements[idx] = resetImage;
            _layerController.updateImage(resetImage);
            _imageVersion++;
            _imageRepaintNotifier.value++;
            HapticFeedback.mediumImpact();
            _lastImageTapTime = 0; // Prevent triple-tap
            setState(() {});
            return;
          }
          _lastImageTapTime = now;

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
          setState(() {});
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
        setState(() {});
        return;
      }
      // New table selected
      _tabularTool.selectTabular(hitTabular);
      _tabularTool.startDrag(canvasPosition);
      setState(() {});
      return;
    }
    // Deselect tabular if tapped empty area
    if (_tabularTool.hasSelection) {
      _tabularTool.deselectTabular();
      setState(() {});
    }

    // 🧮 LatexNode hit-test (tap to select/drag, tap away to deselect)
    final hitLatex = _hitTestLatexNode(canvasPosition);
    if (hitLatex != null) {
      _selectedLatexNode = hitLatex;
      _isDraggingLatex = true;
      _latexDragStart = canvasPosition;
      setState(() {});
      return;
    }
    // Deselect LatexNode if tapped empty area
    if (_selectedLatexNode != null) {
      _selectedLatexNode = null;
      _isDraggingLatex = false;
      setState(() {});
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
        _lassoSelectionBackup = Set<String>.from(_lassoTool.selectedIds);
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

    // 📄 PDF PAGE DRAG: Check if touch hits an unlocked PDF page
    if (!_effectiveIsEraser && !_effectiveIsLasso && !_effectiveIsPanMode) {
      for (final layer in _layerController.sceneGraph.layers) {
        for (final child in layer.children) {
          if (child is PdfDocumentNode) {
            final hitPage = child.hitTestUnlockedPage(canvasPosition);
            if (hitPage != null) {
              _pdfPageDragController.startDrag(hitPage, child, canvasPosition);
              _pdfLayoutVersion++;
              setState(() {});
              return;
            }
          }
        }
      }
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
      setState(() {});
      return;
    }

    // 🔒 Restore lasso selection if a zoom gesture interrupted a new lasso
    if (_effectiveIsLasso && _lassoSelectionBackup != null) {
      _lassoTool.clearLassoPath();
      _lassoTool.restoreSelectionFromIds(_lassoSelectionBackup!);
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

  // ===========================================================================
  // 🌀 IMAGE ROTATION — Two-finger rotate on selected image
  // ===========================================================================

  /// Called once when two-finger gesture starts on a selected image
  void _onImageScaleStart() {
    _imageTool.startRotation();
  }

  /// Called continuously with rotation + scale during two-finger gesture
  void _onImageTransform(double rotationDelta, double scaleRatio) {
    final updated = _imageTool.updateRotation(rotationDelta, scaleRatio);
    if (updated != null) {
      final index = _imageElements.indexWhere((e) => e.id == updated.id);
      if (index != -1) {
        _imageElements[index] = updated;
      }
      _imageVersion++;
      _imageRepaintNotifier.value++;
    }
  }

  /// Called when two-finger gesture ends — persist the rotation
  void _onImageScaleEnd() {
    if (_imageTool.selectedImage != null) {
      _layerController.updateImage(_imageTool.selectedImage!);
      _imageTool.endRotation();
    }
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
    setState(() {});
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
                    setState(() {});
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
}
