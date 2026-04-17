part of '../../fluera_canvas_screen.dart';

/// 🛠️ Standard Overlays — lasso, selection, pen tool, ruler, digital text,
/// remote viewports / presence.
/// Extracted from _FlueraCanvasScreenState._buildImpl
extension FlueraCanvasOverlaysUI on _FlueraCanvasScreenState {
  /// Remote overlays: viewport, presence (shared canvas only).
  /// Phase 2: will be re-implemented with new collaboration system.
  List<Widget> _buildRemoteOverlays(BuildContext context) {
    return const [];
  }

  /// Standard overlays: lasso, selection, pen tool.
  /// These are INSIDE the canvas Stack, between canvas layers and eraser overlays.
  List<Widget> _buildStandardOverlays(BuildContext context) {
    return [
      // Lasso Path Overlay — DENTRO l'area canvas
      // 🚀 PERF: ValueListenableBuilder isolates repaint to just this widget
      if (_effectiveIsLasso || _isGesturalLassoActive)
        Positioned.fill(
          child: IgnorePointer(
            child: ValueListenableBuilder<int>(
              valueListenable: _lassoTool.lassoPathNotifier,
              builder: (context, _, __) {
                if (_lassoTool.lassoPath.isEmpty) {
                  return const SizedBox.shrink();
                }
                return CustomPaint(
                  painter: LassoPathPainter(
                    path: _lassoTool.lassoPath,
                    color: Colors.blue,
                    canvasController: _canvasController,
                    selectionMode: _lassoTool.selectionMode,
                    marqueeRect:
                        _lassoTool.selectionMode == SelectionMode.marquee
                            ? _lassoTool.marqueeRect
                            : _lassoTool.selectionMode == SelectionMode.ellipse
                            ? _lassoTool.ellipseRect
                            : null,
                    repaint: _lassoTool.lassoPathNotifier,
                  ),
                  size: Size.infinite,
                );
              },
            ),
          ),
        ),

      // 🔲 Closing ripple — expanding gradient circle on lasso completion
      if (_lassoRippleCenter != null && _lassoRippleController != null)
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _lassoRippleController!,
              builder: (context, _) {
                final t = _lassoRippleController!.value;
                final center = _lassoRippleCenter;
                if (center == null || t >= 1.0) return const SizedBox.shrink();
                final radius = 20.0 + t * 60.0;
                final opacity = (1.0 - t) * 0.5;
                return CustomPaint(
                  painter: _LassoRipplePainter(
                    center: center,
                    radius: radius,
                    opacity: opacity,
                  ),
                  size: Size.infinite,
                );
              },
            ),
          ),
        ),

      // Selection Overlay — DENTRO l'area canvas (non more nello Stack principale)
      Positioned.fill(
        child: IgnorePointer(
          child: LassoSelectionOverlay(
            key: const ValueKey('lasso_selection_overlay'),
            selectedIds: _lassoTool.selectedIds,
            layerController: _layerController,
            canvasController: _canvasController,
            isDragging: _lassoTool.isDragging,
            featherRadius: _lassoTool.featherRadius,
            selectionBounds: _lassoTool.getSelectionBounds(),
            dragNotifier: _lassoTool.dragNotifier,
          ),
        ),
      ),

      // 🔲 Phase 3B: Selection Transform Handles
      if (_lassoTool.hasSelection)
        SelectionTransformOverlay(
          lassoTool: _lassoTool,
          canvasController: _canvasController,
          onTransformComplete: () {
            setState(() {});
            _autoSaveCanvas();
          },
          onEdgeAutoScroll: (screenPosition) {
            final RenderBox? renderBox =
                _canvasAreaKey.currentContext?.findRenderObject() as RenderBox?;
            if (renderBox != null) {
              final local = renderBox.globalToLocal(screenPosition);
              _startAutoScrollIfNeeded(local, renderBox.size);
            }
          },
          onEdgeAutoScrollEnd: _stopAutoScroll,
          isDark: Theme.of(context).brightness == Brightness.dark,
          onComputeSnap: _applySmartGuides,
        ),

      // 🎯 Selection Mode Toolbar — mode switching + feather slider
      if (_effectiveIsLasso && !_isDrawingNotifier.value)
        Positioned(
          top: 8,
          left: 0,
          right: 0,
          child: Center(
            child: _LassoModeToolbar(
              currentMode: _lassoTool.selectionMode,
              featherRadius: _lassoTool.featherRadius,
              onModeChanged: (mode) {
                setState(() {
                  _lassoTool.selectionMode = mode;
                });
                HapticFeedback.selectionClick();
              },
              onFeatherChanged: (value) {
                setState(() {
                  _lassoTool.featherRadius = value;
                });
              },
              onColorSelect: () {
                // Use current canvas position tap as color selection
                // (user taps the button then taps on canvas)
                setState(() {
                  _lassoTool.selectionMode = SelectionMode.lasso;
                });
                HapticFeedback.mediumImpact();
              },
              isDark: Theme.of(context).brightness == Brightness.dark,
            ),
          ),
        ),

      // ✒️ Pen Tool Overlay — anchors, handles, rubber-band
      if (_toolController.isPenToolMode)
        _penTool.buildOverlay(_penToolContext) ?? const SizedBox.shrink(),

      // ✒️ Pen Tool Options Panel — stroke width, fill toggle, action buttons
      if (_toolController.isPenToolMode)
        Positioned(
          bottom: 16,
          left: 0,
          right: 0,
          child: Center(
            child: Builder(
              builder: (ctx) {
                // Wire context + callback for touch buttons
                _penTool.toolOptionsContext = _penToolContext;
                _penTool.onToolOptionsChanged = () {
                  if (mounted) setState(() {});
                };
                return _penTool.buildToolOptions(ctx) ??
                    const SizedBox.shrink();
              },
            ),
          ),
        ),

      // 📐 Smart Guide alignment lines during drag
      if (_activeSmartGuides.isNotEmpty)
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: SmartGuidePainter(
                guides: _activeSmartGuides,
                controller: _canvasController,
              ),
              size: Size.infinite,
            ),
          ),
        ),

      // 📊 TabularNode selection overlay (border only — actions in toolbar)
      if (_tabularTool.hasSelection)
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _canvasController,
              builder: (context, _) {
                final bounds = _tabularTool.selectionBounds!;
                final screenTL = _canvasController.canvasToScreen(
                  bounds.topLeft,
                );
                final screenBR = _canvasController.canvasToScreen(
                  bounds.bottomRight,
                );
                final screenRect = Rect.fromPoints(screenTL, screenBR);

                return Stack(
                  children: [
                    Positioned(
                      left: screenRect.left - 2,
                      top: screenRect.top - 2,
                      width: screenRect.width + 4,
                      height: screenRect.height + 4,
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Colors.blue.withValues(alpha: 0.6),
                            width: 2,
                          ),
                          color: Colors.blue.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),

      // 🧮 LatexNode selection overlay — BORDER (non-interactive)
      if (_selectedLatexNode != null)
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _canvasController,
              builder: (context, _) {
                final node = _selectedLatexNode!;
                final pos = node.localTransform.getTranslation();
                final bounds = node.localBounds.translate(pos.x, pos.y);
                final screenTL = _canvasController.canvasToScreen(
                  bounds.topLeft,
                );
                final screenBR = _canvasController.canvasToScreen(
                  bounds.bottomRight,
                );
                final screenRect = Rect.fromPoints(screenTL, screenBR);
                return Stack(
                  children: [
                    Positioned(
                      left: screenRect.left - 2,
                      top: screenRect.top - 2,
                      width: screenRect.width + 4,
                      height: screenRect.height + 4,
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Colors.purple.withValues(alpha: 0.8),
                            width: 2,
                          ),
                          color: Colors.purple.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),

      // 🧮 LatexNode selection overlay — BUTTONS (interactive)
      if (_selectedLatexNode != null)
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _canvasController,
            builder: (context, _) {
              final node = _selectedLatexNode!;
              final pos = node.localTransform.getTranslation();
              final bounds = node.localBounds.translate(pos.x, pos.y);
              final screenTL = _canvasController.canvasToScreen(bounds.topLeft);
              final screenBR = _canvasController.canvasToScreen(
                bounds.bottomRight,
              );
              final screenRect = Rect.fromPoints(screenTL, screenBR);
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  // Delete button — Listener bypasses gesture arena
                  Positioned(
                    left: screenRect.right - 12,
                    top: screenRect.top - 16,
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: (_) => _deleteSelectedLatexNode(),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: const BoxDecoration(
                          color: Color(0xFFE53935),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Color(0x40000000),
                              blurRadius: 4,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  ),
                  // ⚙️ Settings button — Listener bypasses gesture arena
                  if (node.chartType != null)
                    Positioned(
                      left: screenRect.right - 44,
                      top: screenRect.top - 16,
                      child: Listener(
                        behavior: HitTestBehavior.opaque,
                        onPointerDown:
                            (_) => _showChartSettingsDialog(context, node),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: const BoxDecoration(
                            color: Color(0xFF7C4DFF),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Color(0x40000000),
                                blurRadius: 4,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.settings,
                            color: Colors.white,
                            size: 14,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),

      // 📈 FunctionGraphNode selection overlay — BORDER + RESIZE HANDLES
      if (_selectedGraphNode != null)
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _canvasController,
              builder: (context, _) {
                final node = _selectedGraphNode!;
                final pos = node.localTransform.getTranslation();
                final bounds = node.localBounds.translate(pos.x, pos.y);
                final screenTL = _canvasController.canvasToScreen(
                  bounds.topLeft,
                );
                final screenBR = _canvasController.canvasToScreen(
                  bounds.bottomRight,
                );
                final screenRect = Rect.fromPoints(screenTL, screenBR);
                const handleSize = 10.0;
                final corners = [
                  screenRect.topLeft,
                  screenRect.topRight,
                  screenRect.bottomLeft,
                  screenRect.bottomRight,
                ];
                return Stack(
                  children: [
                    // Dashed border
                    Positioned(
                      left: screenRect.left - 2,
                      top: screenRect.top - 2,
                      width: screenRect.width + 4,
                      height: screenRect.height + 4,
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: const Color(
                              0xFF4285F4,
                            ).withValues(alpha: 0.8),
                            width: 2,
                          ),
                          color: const Color(
                            0xFF4285F4,
                          ).withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    // Corner handles
                    for (final corner in corners)
                      Positioned(
                        left: corner.dx - handleSize / 2,
                        top: corner.dy - handleSize / 2,
                        width: handleSize,
                        height: handleSize,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(
                              color: const Color(0xFF4285F4),
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(3),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x30000000),
                                blurRadius: 3,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),

      // 📈 FunctionGraphNode selection overlay — BUTTONS (interactive)
      if (_selectedGraphNode != null)
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _canvasController,
            builder: (context, _) {
              final node = _selectedGraphNode!;
              final pos = node.localTransform.getTranslation();
              final bounds = node.localBounds.translate(pos.x, pos.y);
              final screenTL = _canvasController.canvasToScreen(bounds.topLeft);
              final screenBR = _canvasController.canvasToScreen(
                bounds.bottomRight,
              );
              final screenRect = Rect.fromPoints(screenTL, screenBR);
              final isDark = Theme.of(context).brightness == Brightness.dark;
              final btnY = screenRect.top - 20;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  // ✏️ Edit
                  Positioned(
                    left: screenRect.right - 12,
                    top: btnY,
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: (_) => _openGraphEditor(node),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: const BoxDecoration(
                          color: Color(0xFF4285F4),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Color(0x40000000),
                              blurRadius: 4,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.edit,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                    ),
                  ),
                  // 🗑️ Delete
                  Positioned(
                    left: screenRect.right - 44,
                    top: btnY,
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: (_) {
                        final graphNode = _selectedGraphNode;
                        if (graphNode == null) return;
                        for (final layer in _layerController.layers) {
                          layer.node.remove(graphNode);
                        }
                        _selectedGraphNode = null;
                        _isDraggingGraph = false;
                        _layerController.sceneGraph.bumpVersion();
                        DrawingPainter.invalidateAllTiles();
                        DrawingPainter.triggerRepaint();
                        _uiRebuildNotifier.value++;
                        _autoSaveCanvas();
                        HapticFeedback.mediumImpact();
                      },
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: const BoxDecoration(
                          color: Color(0xFFE53935),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Color(0x40000000),
                              blurRadius: 4,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.delete_outline,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                    ),
                  ),
                  // 📋 Duplicate
                  Positioned(
                    left: screenRect.right - 76,
                    top: btnY,
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: (_) {
                        final graphNode = _selectedGraphNode;
                        if (graphNode == null) return;
                        final clone =
                            graphNode.cloneInternal() as FunctionGraphNode;
                        final t = clone.localTransform;
                        final p = t.getTranslation();
                        t.setTranslationRaw(p.x + 30, p.y + 30, 0);
                        _layerController.sceneGraph.layers.first.add(clone);
                        _selectedGraphNode = clone;
                        _layerController.sceneGraph.bumpVersion();
                        DrawingPainter.invalidateAllTiles();
                        DrawingPainter.triggerRepaint();
                        _uiRebuildNotifier.value++;
                        _autoSaveCanvas();
                        HapticFeedback.mediumImpact();
                      },
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color:
                              isDark
                                  ? const Color(0xFF37474F)
                                  : const Color(0xFF78909C),
                          shape: BoxShape.circle,
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x40000000),
                              blurRadius: 4,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.copy,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                    ),
                  ),
                  // ⋮ More (context menu)
                  Positioned(
                    left: screenRect.right - 108,
                    top: btnY,
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown:
                          (event) =>
                              _showGraphContextMenu(node, event.position),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color:
                              isDark
                                  ? const Color(0xFF263238)
                                  : const Color(0xFF90A4AE),
                          shape: BoxShape.circle,
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x40000000),
                              blurRadius: 4,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.more_vert,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                    ),
                  ),
                  // 📍 A4: Viewport info strip below the graph — tappable to edit coordinates
                  Positioned(
                    left: screenRect.left,
                    top: screenRect.bottom + 6,
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: (_) {},
                      child: GestureDetector(
                        onTap: () {
                          final xMinC = TextEditingController(
                            text: node.xMin.toStringAsFixed(1),
                          );
                          final xMaxC = TextEditingController(
                            text: node.xMax.toStringAsFixed(1),
                          );
                          final yMinC = TextEditingController(
                            text: node.yMin.toStringAsFixed(1),
                          );
                          final yMaxC = TextEditingController(
                            text: node.yMax.toStringAsFixed(1),
                          );
                          showDialog(
                            context: context,
                            builder:
                                (ctx) => AlertDialog(
                                  title: const Text(
                                    'Coordinate Viewport',
                                    style: TextStyle(fontSize: 16),
                                  ),
                                  content: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Row(
                                        children: [
                                          const SizedBox(
                                            width: 24,
                                            child: Text(
                                              'x',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontFamily: 'serif',
                                                fontStyle: FontStyle.italic,
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            child: TextField(
                                              controller: xMinC,
                                              decoration: const InputDecoration(
                                                labelText: 'Min',
                                                isDense: true,
                                              ),
                                              keyboardType:
                                                  const TextInputType.numberWithOptions(
                                                    signed: true,
                                                    decimal: true,
                                                  ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: TextField(
                                              controller: xMaxC,
                                              decoration: const InputDecoration(
                                                labelText: 'Max',
                                                isDense: true,
                                              ),
                                              keyboardType:
                                                  const TextInputType.numberWithOptions(
                                                    signed: true,
                                                    decimal: true,
                                                  ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Row(
                                        children: [
                                          const SizedBox(
                                            width: 24,
                                            child: Text(
                                              'y',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontFamily: 'serif',
                                                fontStyle: FontStyle.italic,
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            child: TextField(
                                              controller: yMinC,
                                              decoration: const InputDecoration(
                                                labelText: 'Min',
                                                isDense: true,
                                              ),
                                              keyboardType:
                                                  const TextInputType.numberWithOptions(
                                                    signed: true,
                                                    decimal: true,
                                                  ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: TextField(
                                              controller: yMaxC,
                                              decoration: const InputDecoration(
                                                labelText: 'Max',
                                                isDense: true,
                                              ),
                                              keyboardType:
                                                  const TextInputType.numberWithOptions(
                                                    signed: true,
                                                    decimal: true,
                                                  ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx),
                                      child: const Text('Annulla'),
                                    ),
                                    FilledButton(
                                      onPressed: () {
                                        final x0 = double.tryParse(xMinC.text);
                                        final x1 = double.tryParse(xMaxC.text);
                                        final y0 = double.tryParse(yMinC.text);
                                        final y1 = double.tryParse(yMaxC.text);
                                        if (x0 != null &&
                                            x1 != null &&
                                            y0 != null &&
                                            y1 != null &&
                                            x0 < x1 &&
                                            y0 < y1) {
                                          node.xMin = x0;
                                          node.xMax = x1;
                                          node.yMin = y0;
                                          node.yMax = y1;
                                          node.invalidateCache();
                                          _layerController.sceneGraph
                                              .bumpVersion();
                                          DrawingPainter.invalidateAllTiles();
                                          DrawingPainter.triggerRepaint();
                                          _uiRebuildNotifier.value++;
                                          _autoSaveCanvas();
                                        }
                                        Navigator.pop(ctx);
                                      },
                                      child: const Text('OK'),
                                    ),
                                  ],
                                ),
                          );
                          HapticFeedback.selectionClick();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color:
                                isDark
                                    ? const Color(0xDD1E1E2E)
                                    : const Color(0xDDFFFFFF),
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x20000000),
                                blurRadius: 4,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'x: [${node.xMin.toStringAsFixed(1)}, ${node.xMax.toStringAsFixed(1)}]  '
                                'y: [${node.yMin.toStringAsFixed(1)}, ${node.yMax.toStringAsFixed(1)}]  '
                                '${node.graphWidth.round()}×${node.graphHeight.round()}',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontFamily: 'monospace',
                                  color:
                                      isDark
                                          ? const Color(0x99FFFFFF)
                                          : const Color(0x99000000),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.edit,
                                size: 10,
                                color:
                                    isDark
                                        ? const Color(0x66FFFFFF)
                                        : const Color(0x66000000),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // 🔍 T2: Zoom +/- buttons
                  Positioned(
                    right:
                        screenRect.right >
                                MediaQuery.of(context).size.width - 60
                            ? null
                            : MediaQuery.of(context).size.width -
                                screenRect.right -
                                4,
                    left:
                        screenRect.right >
                                MediaQuery.of(context).size.width - 60
                            ? screenRect.left - 40
                            : null,
                    top: screenRect.top + (screenRect.height - 90) / 2,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Zoom in
                        Listener(
                          behavior: HitTestBehavior.opaque,
                          onPointerDown: (_) {
                            final cx = (node.xMin + node.xMax) / 2;
                            final cy = (node.yMin + node.yMax) / 2;
                            final rw = (node.xMax - node.xMin) * 0.4;
                            final rh = (node.yMax - node.yMin) * 0.4;
                            node.xMin = cx - rw;
                            node.xMax = cx + rw;
                            node.yMin = cy - rh;
                            node.yMax = cy + rh;
                            node.invalidateCache();
                            _layerController.sceneGraph.bumpVersion();
                            DrawingPainter.invalidateAllTiles();
                            DrawingPainter.triggerRepaint();
                            _uiRebuildNotifier.value++;
                            _autoSaveCanvas();
                            HapticFeedback.selectionClick();
                          },
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color:
                                  isDark
                                      ? const Color(0xEE1E1E2E)
                                      : const Color(0xEEFFFFFF),
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(8),
                              ),
                              border: Border.all(
                                color:
                                    isDark
                                        ? const Color(0x33FFFFFF)
                                        : const Color(0x22000000),
                              ),
                            ),
                            child: Icon(
                              Icons.add,
                              size: 18,
                              color: isDark ? Colors.white70 : Colors.black54,
                            ),
                          ),
                        ),
                        // Zoom out
                        Listener(
                          behavior: HitTestBehavior.opaque,
                          onPointerDown: (_) {
                            final cx = (node.xMin + node.xMax) / 2;
                            final cy = (node.yMin + node.yMax) / 2;
                            final rw = (node.xMax - node.xMin) * 0.6;
                            final rh = (node.yMax - node.yMin) * 0.6;
                            node.xMin = cx - rw;
                            node.xMax = cx + rw;
                            node.yMin = cy - rh;
                            node.yMax = cy + rh;
                            node.invalidateCache();
                            _layerController.sceneGraph.bumpVersion();
                            DrawingPainter.invalidateAllTiles();
                            DrawingPainter.triggerRepaint();
                            _uiRebuildNotifier.value++;
                            _autoSaveCanvas();
                            HapticFeedback.selectionClick();
                          },
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color:
                                  isDark
                                      ? const Color(0xEE1E1E2E)
                                      : const Color(0xEEFFFFFF),
                              border: Border.all(
                                color:
                                    isDark
                                        ? const Color(0x33FFFFFF)
                                        : const Color(0x22000000),
                              ),
                            ),
                            child: Icon(
                              Icons.remove,
                              size: 18,
                              color: isDark ? Colors.white70 : Colors.black54,
                            ),
                          ),
                        ),
                        // Auto-fit viewport: compute optimal yMin/yMax from sampled data
                        Listener(
                          behavior: HitTestBehavior.opaque,
                          onPointerDown: (_) {
                            node.ensureSampled();
                            final pts = node.cachedPoints;
                            if (pts.isEmpty) return;
                            double minY = double.infinity,
                                maxY = double.negativeInfinity;
                            for (final pt in pts) {
                              if (pt.dy.isFinite && pt.dy.abs() < 1e8) {
                                if (pt.dy < minY) minY = pt.dy;
                                if (pt.dy > maxY) maxY = pt.dy;
                              }
                            }
                            // Also check extra functions
                            for (final extra in node.cachedExtraPoints) {
                              for (final pt in extra) {
                                if (pt.dy.isFinite && pt.dy.abs() < 1e8) {
                                  if (pt.dy < minY) minY = pt.dy;
                                  if (pt.dy > maxY) maxY = pt.dy;
                                }
                              }
                            }
                            if (minY.isFinite && maxY.isFinite && maxY > minY) {
                              final padding = (maxY - minY) * 0.1;
                              node.yMin = minY - padding;
                              node.yMax = maxY + padding;
                            } else {
                              node.yMin = -6;
                              node.yMax = 6;
                            }
                            node.invalidateCache();
                            _layerController.sceneGraph.bumpVersion();
                            DrawingPainter.invalidateAllTiles();
                            DrawingPainter.triggerRepaint();
                            _uiRebuildNotifier.value++;
                            _autoSaveCanvas();
                            HapticFeedback.selectionClick();
                          },
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color:
                                  isDark
                                      ? const Color(0xEE1E1E2E)
                                      : const Color(0xEEFFFFFF),
                              border: Border.all(
                                color:
                                    isDark
                                        ? const Color(0x33FFFFFF)
                                        : const Color(0x22000000),
                              ),
                            ),
                            child: Icon(
                              Icons.fit_screen,
                              size: 16,
                              color: isDark ? Colors.white70 : Colors.black54,
                            ),
                          ),
                        ),
                        // Reset zoom
                        Listener(
                          behavior: HitTestBehavior.opaque,
                          onPointerDown: (_) {
                            node.xMin = -10;
                            node.xMax = 10;
                            node.yMin = -6;
                            node.yMax = 6;
                            node.invalidateCache();
                            _layerController.sceneGraph.bumpVersion();
                            DrawingPainter.invalidateAllTiles();
                            DrawingPainter.triggerRepaint();
                            _uiRebuildNotifier.value++;
                            _autoSaveCanvas();
                            HapticFeedback.selectionClick();
                          },
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color:
                                  isDark
                                      ? const Color(0xEE1E1E2E)
                                      : const Color(0xEEFFFFFF),
                              borderRadius: const BorderRadius.vertical(
                                bottom: Radius.circular(8),
                              ),
                              border: Border.all(
                                color:
                                    isDark
                                        ? const Color(0x33FFFFFF)
                                        : const Color(0x22000000),
                              ),
                            ),
                            child: Icon(
                              Icons.center_focus_strong,
                              size: 16,
                              color: isDark ? Colors.white70 : Colors.black54,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),

      // 🎚️ Always-visible k/d + parameter sliders for graph functions
      if (_selectedGraphNode != null)
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _canvasController,
            builder: (context, _) {
              final node = _selectedGraphNode!;
              final params = node.detectedParams;
              final pos = node.localTransform.getTranslation();
              final bounds = node.localBounds.translate(pos.x, pos.y);
              final screenBL = _canvasController.canvasToScreen(
                bounds.bottomLeft,
              );
              final screenBR = _canvasController.canvasToScreen(
                bounds.bottomRight,
              );
              final isDark = Theme.of(context).brightness == Brightness.dark;
              final sliderWidth = (screenBR.dx - screenBL.dx).clamp(
                180.0,
                340.0,
              );
              final accentColor = node.curveColor;

              // Formula string
              final kStr =
                  node.coeffK == 1.0
                      ? ''
                      : '${node.coeffK.toStringAsFixed(1)}·';
              final dStr =
                  node.offsetD == 0.0
                      ? ''
                      : (node.offsetD > 0
                          ? ' + ${node.offsetD.toStringAsFixed(1)}'
                          : ' − ${(-node.offsetD).toStringAsFixed(1)}');
              final formulaStr = '${kStr}f(x)$dStr';

              Widget buildSliderRow(
                String label,
                Color color,
                double value,
                double min,
                double max,
                ValueChanged<double> onChanged,
              ) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 0),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 16,
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'serif',
                            fontStyle: FontStyle.italic,
                            color: color,
                          ),
                        ),
                      ),
                      Expanded(
                        child: SliderTheme(
                          data: SliderThemeData(
                            trackHeight: 3,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 6,
                            ),
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 12,
                            ),
                            activeTrackColor: color,
                            inactiveTrackColor: color.withValues(alpha: 0.2),
                            thumbColor: color,
                          ),
                          child: Slider(
                            min: min,
                            max: max,
                            value: value.clamp(min, max),
                            onChanged: onChanged,
                            onChangeEnd: (_) => _autoSaveCanvas(),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 34,
                        child: Text(
                          value.toStringAsFixed(1),
                          textAlign: TextAlign.end,
                          style: TextStyle(
                            fontSize: 10,
                            fontFamily: 'monospace',
                            color: isDark ? Colors.white54 : Colors.black45,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }

              return Stack(
                children: [
                  Positioned(
                    left: screenBL.dx,
                    top: screenBL.dy + 28,
                    width: sliderWidth,
                    // 🔒 Absorb pointer events
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: (_) {
                        _isDraggingGraphSlider = true;
                      },
                      onPointerMove: (_) {},
                      onPointerUp: (_) {
                        _isDraggingGraphSlider = false;
                      },
                      onPointerCancel: (_) {
                        _isDraggingGraphSlider = false;
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color:
                              isDark
                                  ? const Color(0xF01E1E2E)
                                  : const Color(0xF0FFFFFF),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x30000000),
                              blurRadius: 6,
                              offset: Offset(0, 2),
                            ),
                          ],
                          border: Border.all(
                            color:
                                isDark
                                    ? const Color(0x22FFFFFF)
                                    : const Color(0x18000000),
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Formula badge
                            Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: accentColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  formulaStr.isEmpty ? 'f(x)' : formulaStr,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.w600,
                                    color: accentColor,
                                  ),
                                ),
                              ),
                            ),
                            // k slider (coefficient)
                            buildSliderRow(
                              'k',
                              accentColor,
                              node.coeffK,
                              -5.0,
                              5.0,
                              (v) {
                                node.coeffK = double.parse(
                                  v.toStringAsFixed(2),
                                );
                                node.invalidateCache();
                                _layerController.sceneGraph.bumpVersion();
                                DrawingPainter.triggerRepaint();
                                _uiRebuildNotifier.value++;
                              },
                            ),
                            // d slider (vertical offset)
                            buildSliderRow(
                              'd',
                              isDark ? Colors.tealAccent : Colors.teal,
                              node.offsetD,
                              -10.0,
                              10.0,
                              (v) {
                                node.offsetD = double.parse(
                                  v.toStringAsFixed(2),
                                );
                                node.invalidateCache();
                                _layerController.sceneGraph.bumpVersion();
                                DrawingPainter.triggerRepaint();
                                _uiRebuildNotifier.value++;
                              },
                            ),
                            // Detected parameter sliders
                            for (final p in params)
                              buildSliderRow(
                                p,
                                isDark
                                    ? Colors.amberAccent
                                    : Colors.amber.shade800,
                                node.parameters[p] ?? 1.0,
                                -10.0,
                                10.0,
                                (v) {
                                  node.parameters[p] = double.parse(
                                    v.toStringAsFixed(2),
                                  );
                                  node.invalidateCache();
                                  _layerController.sceneGraph.bumpVersion();
                                  DrawingPainter.triggerRepaint();
                                  _uiRebuildNotifier.value++;
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),

      // 📊 Selected cell / range highlight
      if (_tabularTool.hasCellSelection)
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _canvasController,
              builder: (context, _) {
                final range = _tabularTool.selectedRange;
                if (range == null) return const SizedBox.shrink();

                final topLeft = _tabularTool.getCellRect(
                  range.startColumn,
                  range.startRow,
                  _canvasController.offset,
                  _canvasController.scale,
                );
                final bottomRight = _tabularTool.getCellRect(
                  range.endColumn,
                  range.endRow,
                  _canvasController.offset,
                  _canvasController.scale,
                );
                if (topLeft == null || bottomRight == null) {
                  return const SizedBox.shrink();
                }

                final screenRect = Rect.fromLTRB(
                  topLeft.left,
                  topLeft.top,
                  bottomRight.right,
                  bottomRight.bottom,
                );

                return Stack(
                  children: [
                    Positioned(
                      left: screenRect.left,
                      top: screenRect.top,
                      width: screenRect.width,
                      height: screenRect.height,
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.blue, width: 2.5),
                          color: Colors.blue.withValues(alpha: 0.08),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),

      // 📊 Fill handle — draggable square at bottom-right of selection
      if (_tabularTool.hasCellSelection && !_editingInCell)
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _canvasController,
            builder: (context, _) {
              final handleRect = _tabularTool.getFillHandleRect(
                _canvasController.offset,
                _canvasController.scale,
              );
              if (handleRect == null) return const SizedBox.shrink();

              return Stack(
                children: [
                  // Ripple flash on recently filled cells.
                  if (FlueraCanvasTabularFillHandle
                          ._lastFilledAddresses
                          .isNotEmpty &&
                      FlueraCanvasTabularFillHandle._lastFillTime != null)
                    Builder(
                      builder: (ctx) {
                        final elapsed =
                            DateTime.now()
                                .difference(
                                  FlueraCanvasTabularFillHandle._lastFillTime!,
                                )
                                .inMilliseconds;
                        if (elapsed > 600) {
                          // Animation complete — clear.
                          FlueraCanvasTabularFillHandle._lastFilledAddresses =
                              [];
                          return const SizedBox.shrink();
                        }
                        final opacity =
                            (1.0 - elapsed / 600.0).clamp(0.0, 1.0) * 0.25;
                        // Schedule repaint.
                        Future.microtask(() => setState(() {}));

                        return Stack(
                          children: [
                            for (final addr
                                in FlueraCanvasTabularFillHandle
                                    ._lastFilledAddresses)
                              Builder(
                                builder: (_) {
                                  final r = _tabularTool.getCellRect(
                                    addr.column,
                                    addr.row,
                                    _canvasController.offset,
                                    _canvasController.scale,
                                  );
                                  if (r == null) {
                                    return const SizedBox.shrink();
                                  }
                                  return Positioned(
                                    left: r.left,
                                    top: r.top,
                                    width: r.width,
                                    height: r.height,
                                    child: IgnorePointer(
                                      child: Container(
                                        color: Color.fromRGBO(
                                          67,
                                          160,
                                          71,
                                          opacity,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                          ],
                        );
                      },
                    ),

                  // Fill preview during drag — dashed border.
                  if (_tabularTool.isFillDragging)
                    Builder(
                      builder: (ctx) {
                        final previewRect = _tabularTool.getFillPreviewRect(
                          _canvasController.offset,
                          _canvasController.scale,
                        );
                        if (previewRect == null) {
                          return const SizedBox.shrink();
                        }

                        return Stack(
                          children: [
                            // Dashed border preview area.
                            Positioned(
                              left: previewRect.left,
                              top: previewRect.top,
                              width: previewRect.width,
                              height: previewRect.height,
                              child: IgnorePointer(
                                child: CustomPaint(
                                  painter: _DashedBorderPainter(
                                    color: const Color(0xFF43A047),
                                    strokeWidth: 2.0,
                                    dashLength: 6.0,
                                    gapLength: 4.0,
                                    fill: const Color(
                                      0xFF43A047,
                                    ).withValues(alpha: 0.06),
                                  ),
                                  size: Size(
                                    previewRect.width,
                                    previewRect.height,
                                  ),
                                ),
                              ),
                            ),

                            // Tooltip with computed value.
                            if (_tabularTool.fillDirection ==
                                    FillDirection.down &&
                                _tabularTool.fillTargetRow != null)
                              Builder(
                                builder: (_) {
                                  final range = _tabularTool.selectedRange;
                                  if (range == null) {
                                    return const SizedBox.shrink();
                                  }
                                  final previewVal = _computeFillPreviewValue(
                                    range.startColumn,
                                    _tabularTool.fillTargetRow!,
                                  );
                                  if (previewVal.isEmpty) {
                                    return const SizedBox.shrink();
                                  }
                                  return Positioned(
                                    left: previewRect.right + 8,
                                    top: previewRect.bottom - 28,
                                    child: IgnorePointer(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF1E1E1E),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                          boxShadow: const [
                                            BoxShadow(
                                              color: Color(0x40000000),
                                              blurRadius: 6,
                                              offset: Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: Text(
                                          previewVal,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                          ],
                        );
                      },
                    ),

                  // Fill handle square — with hover scale animation.
                  Positioned(
                    left: handleRect.left - 2,
                    top: handleRect.top - 2,
                    width: handleRect.width + 4,
                    height: handleRect.height + 4,
                    child: Center(
                      child: _FillHandleWidget(
                        size: handleRect.width,
                        onDown: () {
                          _tabularTool.startFillDrag();
                          _tabularTool.lastFillHandleDown = DateTime.now();
                          setState(() {});
                        },
                        onMove: (position) {
                          if (!_tabularTool.isFillDragging) return;
                          final canvasPos = _canvasController.screenToCanvas(
                            position,
                          );
                          final cell = _tabularTool.clampedHitTestCell(
                            canvasPos,
                          );
                          if (cell != null) {
                            _tabularTool.updateFillTarget(cell.$1, cell.$2);
                            setState(() {});
                          }
                        },
                        onUp: () {
                          if (!_tabularTool.isFillDragging) return;

                          final now = DateTime.now();
                          final isDoubleClick =
                              _tabularTool.lastFillHandleUp != null &&
                              now
                                      .difference(
                                        _tabularTool.lastFillHandleUp!,
                                      )
                                      .inMilliseconds <
                                  350;
                          _tabularTool.lastFillHandleUp = now;

                          final result = _tabularTool.endFillDrag();

                          if (isDoubleClick) {
                            final autoRow =
                                _tabularTool.computeAutoFillExtent();
                            if (autoRow != null) {
                              final range = _tabularTool.selectedRange;
                              if (range != null) {
                                _performFillDown(range.endRow + 1, autoRow);
                              }
                            }
                          } else if (result != null) {
                            _performFill(result);
                          }
                          setState(() {});
                        },
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),

      // 📊 In-cell editing overlay
      if (_editingInCell && _tabularTool.hasCellSelection)
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _canvasController,
            builder: (context, _) {
              final cellRect = _tabularTool.getCellRect(
                _tabularTool.selectedCol!,
                _tabularTool.selectedRow!,
                _canvasController.offset,
                _canvasController.scale,
              );
              if (cellRect == null) return const SizedBox.shrink();

              final currentValue = _getSelectedCellDisplayValue() ?? '';

              return Stack(
                children: [
                  Positioned(
                    left: cellRect.left,
                    top: cellRect.top,
                    width: cellRect.width,
                    height: cellRect.height,
                    child: Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(2),
                      child: _InCellEditor(
                        initialValue: currentValue,
                        onSubmit: (value) {
                          _setCellValue(
                            _tabularTool.selectedCol!,
                            _tabularTool.selectedRow!,
                            value,
                          );
                          _editingInCell = false;
                          setState(() {});
                        },
                        onCancel: () {
                          _editingInCell = false;
                          setState(() {});
                        },
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),

      // 🔗 Bidirectional Traceability: Latex <-> Tabular Provenance Highlight
      if (EngineScope.hasScope &&
          (_tabularTool.hasCellSelection || _lassoTool.selectedIds.length == 1))
        Positioned.fill(
          child: Builder(
            builder: (context) {
              return IgnorePointer(
                child: CustomPaint(
                  painter: LatexProvenanceOverlayPainter(
                    layerController: _layerController,
                    tabularTool: _tabularTool,
                    selectedNodeIds: _lassoTool.selectedIds,
                    canvasOffset: _canvasController.offset,
                    canvasScale: _canvasController.scale,
                  ),
                  size: Size.infinite,
                ),
              );
            },
          ),
        ),
    ];
  }

  /// 📝 Build a rich Text widget from a DigitalTextElement, applying ALL effects.
  /// Used by both the element loop and the selected element rendering block.
  Widget _buildDigitalTextWidget(DigitalTextElement textElement) {
    final scaledFontSize =
        textElement.fontSize * textElement.scale * _canvasController.scale;
    final baseStyle = TextStyle(
      fontSize: scaledFontSize,
      color: textElement.color.withValues(alpha: textElement.opacity),
      fontWeight: textElement.fontWeight,
      fontStyle: textElement.fontStyle,
      fontFamily: textElement.fontFamily,
      decoration: textElement.textDecoration,
      letterSpacing:
          textElement.letterSpacing != 0 ? textElement.letterSpacing : null,
      shadows: textElement.shadow != null ? [textElement.shadow!] : null,
    );

    Widget textWidget = Text(
      textElement.text,
      style: baseStyle,
      textAlign: textElement.textAlign,
    );

    // 🎨 Outline effect: render text twice — outline behind, fill in front
    if (textElement.outlineColor != null && textElement.outlineWidth > 0) {
      final outlineStyle = baseStyle.copyWith(
        foreground:
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = textElement.outlineWidth * _canvasController.scale
              ..color = textElement.outlineColor!,
        shadows: null, // outline doesn't need shadow
      );
      textWidget = Stack(
        children: [
          Text(
            textElement.text,
            style: outlineStyle,
            textAlign: textElement.textAlign,
          ),
          textWidget,
        ],
      );
    }

    // 🌈 Gradient effect: wrap in ShaderMask
    if (textElement.gradientColors != null &&
        textElement.gradientColors!.length >= 2) {
      textWidget = ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (bounds) {
          return LinearGradient(
            colors: textElement.gradientColors!,
          ).createShader(bounds);
        },
        child: textWidget,
      );
    }

    // 🎨 Background color (pill/label style)
    if (textElement.backgroundColor != null) {
      textWidget = Container(
        padding: EdgeInsets.symmetric(
          horizontal: 4 * _canvasController.scale,
          vertical: 2 * _canvasController.scale,
        ),
        decoration: BoxDecoration(
          color: textElement.backgroundColor,
          borderRadius: BorderRadius.circular(4 * _canvasController.scale),
        ),
        child: textWidget,
      );
    }

    // 🔄 Rotation
    if (textElement.rotation != 0) {
      textWidget = Transform.rotate(
        angle: textElement.rotation,
        alignment: Alignment.topLeft,
        child: textWidget,
      );
    }

    return textWidget;
  }

  /// Tool overlays: ruler, digital text, text selection, recorded playback.
  /// Ordered AFTER eraser overlays in the Z-stack.
  List<Widget> _buildToolOverlays(BuildContext context) {
    return [
      // 📏 Phase 3C: Interactive Ruler & Guide Overlay
      // Only shown when the user activates the ruler toggle
      if (_showRulers)
        Positioned.fill(
          child: RulerInteractiveOverlay(
            guideSystem: _rulerGuideSystem,
            canvasController: _canvasController,
            isDark: Theme.of(context).brightness == Brightness.dark,
            onChanged: () => setState(() {}),
          ),
        ),

      // 📝 Digital Text Elements — wrapped in AnimatedBuilder so text
      // positions update on every canvas pan/zoom/rotation.
      if (_digitalTextElements.isNotEmpty || _digitalTextTool.hasSelection)
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _canvasController,
            builder: (context, _) {
              return Stack(
                children: [
                  // Digital Text Elements - Rendering dei testi
                  ..._digitalTextElements.map((textElement) {
                    // Durante drag/resize, salta l'selected element
                    if (_digitalTextTool.hasSelection &&
                        _digitalTextTool.selectedElement!.id ==
                            textElement.id) {
                      return const SizedBox.shrink();
                    }
                    // Skip element being inline-edited (rendered by InlineTextOverlay)
                    if (_isInlineEditing &&
                        _inlineEditingElement != null &&
                        _inlineEditingElement!.id == textElement.id) {
                      return const SizedBox.shrink();
                    }

                    final screenPos = _canvasController.canvasToScreen(
                      textElement.position,
                    );

                    return Positioned(
                      left: screenPos.dx,
                      top: screenPos.dy,
                      child: IgnorePointer(
                        child: _buildDigitalTextWidget(textElement),
                      ),
                    );
                  }),

                  // Rendering dell'selected element dal TOOL
                  if (_digitalTextTool.hasSelection) ...[
                    // Selected element text
                    Builder(
                      builder: (context) {
                        final textElement = _digitalTextTool.selectedElement!;
                        final screenPos = _canvasController.canvasToScreen(
                          textElement.position,
                        );
                        return Positioned(
                          left: screenPos.dx,
                          top: screenPos.dy,
                          child: IgnorePointer(
                            child: _buildDigitalTextWidget(textElement),
                          ),
                        );
                      },
                    ),

                    // Selection rectangle
                    Builder(
                      builder: (context) {
                        final textElement = _digitalTextTool.selectedElement!;
                        final screenPos = _canvasController.canvasToScreen(
                          textElement.position,
                        );
                        final textPainter = TextPainter(
                          text: TextSpan(
                            text: textElement.text,
                            style: TextStyle(
                              fontSize:
                                  textElement.fontSize *
                                  textElement.scale *
                                  _canvasController.scale,
                              fontWeight: textElement.fontWeight,
                              fontFamily: textElement.fontFamily,
                            ),
                          ),
                          textDirection: TextDirection.ltr,
                        )..layout();
                        final width = textPainter.width;
                        final height = textPainter.height;

                        return Positioned(
                          left: screenPos.dx,
                          top: screenPos.dy,
                          width: width,
                          height: height,
                          child: IgnorePointer(
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Colors.deepPurple.withValues(
                                    alpha: 0.3,
                                  ),
                                  width: 2.0,
                                ),
                                color: Colors.deepPurple.withValues(
                                  alpha: 0.05,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),

                    // Resize handles - 4 circles at corners
                    Builder(
                      builder: (context) {
                        final textElement = _digitalTextTool.selectedElement!;
                        final screenPos = _canvasController.canvasToScreen(
                          textElement.position,
                        );
                        final textPainter = TextPainter(
                          text: TextSpan(
                            text: textElement.text,
                            style: TextStyle(
                              fontSize:
                                  textElement.fontSize *
                                  textElement.scale *
                                  _canvasController.scale,
                              fontWeight: textElement.fontWeight,
                              fontFamily: textElement.fontFamily,
                            ),
                          ),
                          textDirection: TextDirection.ltr,
                        )..layout();
                        final width = textPainter.width;
                        final height = textPainter.height;
                        final handles = [
                          Offset(screenPos.dx, screenPos.dy),
                          Offset(screenPos.dx + width, screenPos.dy),
                          Offset(screenPos.dx, screenPos.dy + height),
                          Offset(screenPos.dx + width, screenPos.dy + height),
                        ];

                        return Stack(
                          children:
                              handles.map((handlePos) {
                                return Positioned(
                                  left: handlePos.dx - 8,
                                  top: handlePos.dy - 8,
                                  child: IgnorePointer(
                                    child: Container(
                                      width: 16,
                                      height: 16,
                                      decoration: BoxDecoration(
                                        color: Colors.deepPurple,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.white,
                                          width: 2.0,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                        );
                      },
                    ),
                  ],
                ],
              );
            },
          ),
        ),

      // ── 🔍 Cluster Preview Overlay ──────────────────────────────────────
      if (_previewingClusterId != null &&
          _previewOverlayScreenPosition != null) ...[
        // Tap-outside to dismiss
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              setState(() {
                _previewingClusterId = null;
                _previewOverlayScreenPosition = null;
              });
            },
          ),
        ),
        Builder(
          builder: (context) {
            final cluster =
                _clusterCache
                    .where((c) => c.id == _previewingClusterId)
                    .firstOrNull;
            if (cluster == null) return const SizedBox.shrink();

            // 🔦 PATH TRACE: Illuminate connections from this cluster
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _knowledgeFlowController?.startPathTrace(cluster.id);
            });

            // 🖼️ ON-DEMAND THUMBNAIL: Generate if missing
            if (_thumbnailCache != null &&
                !_thumbnailCache!.hasThumbnail(cluster.id)) {
              final activeLayer = _layerController.activeLayer;
              if (activeLayer != null) {
                final clusterStrokes = <ProStroke>[];
                for (final sid in cluster.strokeIds) {
                  final s = activeLayer.strokes.where((s) => s.id == sid);
                  if (s.isNotEmpty) clusterStrokes.add(s.first);
                }
                if (clusterStrokes.isNotEmpty) {
                  _thumbnailCache!
                      .generateThumbnail(cluster, clusterStrokes)
                      .then((_) {
                        if (mounted) setState(() {});
                      });
                }
              }
            }

            // Compute accent color (same logic as painter)
            final hasStrokes = cluster.strokeIds.isNotEmpty;
            final hasShapes = cluster.shapeIds.isNotEmpty;
            final hasText = cluster.textIds.isNotEmpty;
            final hasImages = cluster.imageIds.isNotEmpty;
            final types =
                (hasStrokes ? 1 : 0) +
                (hasShapes ? 1 : 0) +
                (hasText ? 1 : 0) +
                (hasImages ? 1 : 0);
            Color accent;
            if (types > 1) {
              accent = const Color(0xFF7EC8E3);
            } else if (hasStrokes) {
              accent = const Color(0xFF5C9CE6);
            } else if (hasShapes) {
              accent = const Color(0xFF6BCB7F);
            } else if (hasText) {
              accent = const Color(0xFFA87FDB);
            } else if (hasImages) {
              accent = const Color(0xFFE8A84C);
            } else {
              accent = const Color(0xFF7EC8E3);
            }

            // Build element count label
            final parts = <String>[];
            if (cluster.strokeIds.isNotEmpty) {
              parts.add('${cluster.strokeIds.length} tratti');
            }
            if (cluster.shapeIds.isNotEmpty) {
              parts.add('${cluster.shapeIds.length} forme');
            }
            if (cluster.textIds.isNotEmpty) {
              parts.add('${cluster.textIds.length} testi');
            }
            if (cluster.imageIds.isNotEmpty) {
              parts.add('${cluster.imageIds.length} img');
            }
            final label = parts.isEmpty ? 'Cluster' : parts.join(' • ');

            return Positioned(
              left: (_previewOverlayScreenPosition!.dx - 100).clamp(
                8.0,
                MediaQuery.of(context).size.width - 220,
              ),
              top: (_previewOverlayScreenPosition!.dy - 180).clamp(
                8.0,
                MediaQuery.of(context).size.height - 220,
              ),
              child: ClusterPreviewOverlay(
                thumbnail:
                    _thumbnailCache?.hasThumbnail(cluster.id) == true
                        ? _thumbnailCache!.getThumbnail(cluster.id)
                        : null,
                label: label,
                elementCount: cluster.elementCount,
                connectionCount:
                    _knowledgeFlowController?.connections
                        .where(
                          (c) =>
                              c.sourceClusterId == cluster.id ||
                              c.targetClusterId == cluster.id,
                        )
                        .length ??
                    0,
                accentColor: accent,
                onDismiss: () {
                  setState(() {
                    _previewingClusterId = null;
                    _previewOverlayScreenPosition = null;
                  });
                },
                onZoomTo: () {
                  // Animate zoom to cluster bounds
                  final bounds = cluster.bounds.inflate(40);
                  final viewportSize = MediaQuery.of(context).size;
                  final targetScale =
                      (viewportSize.width / bounds.width)
                          .clamp(0.5, 2.0)
                          .toDouble();
                  final center = bounds.center;
                  final targetOffset = Offset(
                    viewportSize.width / 2 - center.dx * targetScale,
                    viewportSize.height / 2 - center.dy * targetScale,
                  );
                  // Use separate pan + zoom to avoid focal-point distortion
                  final screenCenter = Offset(
                    viewportSize.width / 2,
                    viewportSize.height / 2,
                  );
                  _canvasController.animateOffsetTo(targetOffset);
                  _canvasController.animateZoomTo(targetScale, screenCenter);
                  setState(() {
                    _previewingClusterId = null;
                    _previewOverlayScreenPosition = null;
                  });
                },
              ),
            );
          },
        ),
      ],

      // ── 🏷️ Connection Label Editing Overlay ──────────────────────────────
      if (_editingLabelConnectionId != null &&
          _labelOverlayScreenPosition != null) ...[
        // Tap-outside to dismiss
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              setState(() {
                _editingLabelConnectionId = null;
                _labelOverlayScreenPosition = null;
              });
            },
          ),
        ),
        Positioned(
          left: (_labelOverlayScreenPosition!.dx - 110).clamp(
            8.0,
            MediaQuery.of(context).size.width - 240,
          ),
          top: (_labelOverlayScreenPosition!.dy - 20).clamp(
            8.0,
            MediaQuery.of(context).size.height - 60,
          ),
          child: ConnectionLabelOverlay(
            initialText:
                _knowledgeFlowController?.connections
                    .where((c) => c.id == _editingLabelConnectionId)
                    .firstOrNull
                    ?.label ??
                '',
            accentColor:
                _knowledgeFlowController?.connections
                    .where((c) => c.id == _editingLabelConnectionId)
                    .firstOrNull
                    ?.color ??
                const Color(0xFF64B5F6),
            connectionType:
                _knowledgeFlowController?.connections
                    .where((c) => c.id == _editingLabelConnectionId)
                    .firstOrNull
                    ?.connectionType ??
                ConnectionType.association,
            connectionStyle:
                _knowledgeFlowController?.connections
                    .where((c) => c.id == _editingLabelConnectionId)
                    .firstOrNull
                    ?.connectionStyle ??
                ConnectionStyle.curved,
            isBidirectional:
                _knowledgeFlowController?.connections
                    .where((c) => c.id == _editingLabelConnectionId)
                    .firstOrNull
                    ?.isBidirectional ??
                false,
            onSubmit: (label) {
              final conn =
                  _knowledgeFlowController?.connections
                      .where((c) => c.id == _editingLabelConnectionId)
                      .firstOrNull;
              if (conn != null) {
                conn.label = label;
                _knowledgeFlowController!.version.value++;
                _autoSaveCanvas();
              }
              setState(() {
                _editingLabelConnectionId = null;
                _labelOverlayScreenPosition = null;
              });
            },
            onDismiss: () {
              setState(() {
                _editingLabelConnectionId = null;
                _labelOverlayScreenPosition = null;
              });
            },
            onDelete: () {
              if (_editingLabelConnectionId != null) {
                _knowledgeFlowController?.removeConnection(
                  _editingLabelConnectionId!,
                );
                _autoSaveCanvas();
              }
              setState(() {
                _editingLabelConnectionId = null;
                _labelOverlayScreenPosition = null;
              });
            },
            onMultiSelect: () {
              if (_editingLabelConnectionId != null &&
                  _knowledgeFlowController != null) {
                // Seleziona questa prima connessione per attivare la modalità
                _knowledgeFlowController!.toggleMultiSelect(
                  _editingLabelConnectionId!,
                );
              }
              setState(() {
                _editingLabelConnectionId = null;
                _labelOverlayScreenPosition = null;
              });
            },
            onColorChanged: (color) {
              final conn =
                  _knowledgeFlowController?.connections
                      .where((c) => c.id == _editingLabelConnectionId)
                      .firstOrNull;
              if (conn != null) {
                conn.color = color;
                _knowledgeFlowController!.version.value++;
                _autoSaveCanvas();
              }
            },
            onTypeChanged: (type) {
              final conn =
                  _knowledgeFlowController?.connections
                      .where((c) => c.id == _editingLabelConnectionId)
                      .firstOrNull;
              if (conn != null) {
                conn.connectionType = type;
                _knowledgeFlowController!.version.value++;
                _autoSaveCanvas();
              }
            },
            onBidirectionalToggled: (bidir) {
              final conn =
                  _knowledgeFlowController?.connections
                      .where((c) => c.id == _editingLabelConnectionId)
                      .firstOrNull;
              if (conn != null) {
                conn.isBidirectional = bidir;
                _knowledgeFlowController!.version.value++;
                _autoSaveCanvas();
              }
            },
            onStyleChanged: (style) {
              final conn =
                  _knowledgeFlowController?.connections
                      .where((c) => c.id == _editingLabelConnectionId)
                      .firstOrNull;
              if (conn != null) {
                conn.connectionStyle = style;
                _knowledgeFlowController!.version.value++;
                _autoSaveCanvas();
              }
            },
          ),
        ),
      ],

      // ── 💡 Suggestion Preview Card Overlay ──────────────────────────────
      if (_previewSuggestion != null && _previewSuggestionPosition != null) ...[
        // Tap-outside to dismiss
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap:
                () => setState(() {
                  _previewSuggestion = null;
                  _previewSuggestionPosition = null;
                }),
          ),
        ),
        Positioned(
          left: (_previewSuggestionPosition!.dx - 130).clamp(
            12.0,
            MediaQuery.of(context).size.width - 280,
          ),
          top: (_previewSuggestionPosition!.dy - 100).clamp(
            12.0,
            MediaQuery.of(context).size.height - 120,
          ),
          child: _buildSuggestionPreviewCard(context),
        ),
      ],

      // ── 🧠 Knowledge Map floating button (pan mode only) ─────────────────
      if (_effectiveIsPanMode &&
          _knowledgeFlowController != null &&
          _clusterCache.length >= 2 &&
          !_showKnowledgeMap)
        Positioned(
          bottom: MediaQuery.of(context).padding.bottom + 80,
          right: 16,
          child: GestureDetector(
            onTap: () {
              HapticFeedback.mediumImpact();
              setState(() => _showKnowledgeMap = true);
            },
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E).withValues(alpha: 0.85),
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFF64B5F6).withValues(alpha: 0.3),
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF64B5F6).withValues(alpha: 0.15),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Center(
                child: Text('🧠', style: TextStyle(fontSize: 22)),
              ),
            ),
          ),
        ),

      // ── 🧠 Knowledge Map fullscreen overlay ──────────────────────────────
      if (_showKnowledgeMap && _knowledgeFlowController != null)
        Positioned.fill(
          child: KnowledgeMapOverlay(
            controller: _knowledgeFlowController!,
            clusters: _clusterCache,
            clusterTexts: _clusterTextCache,
            onDismiss: () => setState(() => _showKnowledgeMap = false),
            onNavigateToCluster: (cluster) {
              // Animate canvas to center on the selected cluster
              final viewportSize = MediaQuery.of(context).size;
              final targetOffset = Offset(
                viewportSize.width / 2 -
                    cluster.centroid.dx * _canvasController.scale,
                viewportSize.height / 2 -
                    cluster.centroid.dy * _canvasController.scale,
              );
              _canvasController.animateOffsetTo(targetOffset);
            },
            onConnectionTapped: (sourceId, targetId, curveStrength) {
              // Find source and target clusters
              final srcCluster =
                  _clusterCache.where((c) => c.id == sourceId).firstOrNull;
              final tgtCluster =
                  _clusterCache.where((c) => c.id == targetId).firstOrNull;
              if (srcCluster == null || tgtCluster == null) return;

              // Dismiss the Knowledge Map overlay
              setState(() => _showKnowledgeMap = false);

              // 🎬 Trigger cinematic flight or hyper-jump
              final viewportSize = MediaQuery.of(context).size;
              CameraActions.flyAlongConnection(
                _canvasController,
                srcCluster.bounds,
                tgtCluster.bounds,
                viewportSize,
                curveStrength: curveStrength,
                sourceClusterId: sourceId,
                targetClusterId: targetId,
                onComplete: () {
                  // 🫧 Landing impact
                  HapticFeedback.mediumImpact();
                },
                onPhaseChanged: (phase) {
                  switch (phase) {
                    case 0: // Anticipation
                      HapticFeedback.lightImpact();
                      break;
                    case 1: // Ascent
                      HapticFeedback.lightImpact();
                      break;
                    case 2: // Transit
                      HapticFeedback.selectionClick();
                      break;
                    case 3: // Descent
                      HapticFeedback.lightImpact();
                      break;
                    case 4: // Bounce settle
                      HapticFeedback.mediumImpact();
                      break;
                  }
                },
              );
            },
          ),
        ),

      // ── 🎯 Radial Context Menu Overlay ──────────────────────────────────
      if (_showRadialMenu)
        Positioned.fill(
          child: CanvasRadialMenu(
            key: _radialMenuKey,
            center: _radialMenuCenter,
            recentColors: const [],
            currentBrushIndex: _toolController.penType.index,
            currentColor: _toolController.color,
            canUndo: _layerController.canUndo,
            canRedo: _layerController.canRedo,
            isPanMode: _effectiveIsPanMode,
            activeTool:
                _effectiveIsLasso
                    ? 2
                    : _effectiveIsDigitalText
                    ? 1
                    : _toolController.shapeRecognitionEnabled
                    ? 3
                    : 0,
            undoCount: 0,
            hasLastAction: _layerController.canUndo,
            onResult: (result) {
              setState(() => _showRadialMenu = false);

              // 7️⃣ Quick-repeat: replay last undo
              if (result.quickRepeat) {
                if (_layerController.canUndo) {
                  _layerController.undo();
                  HapticFeedback.mediumImpact();
                }
                return;
              }

              if (result.item == null && !result.eyedropper) return;

              if (result.eyedropper) {
                _launchEyedropperFromCanvas();
                return;
              }

              switch (result.item!) {
                case RadialMenuItem.undo:
                  if (_layerController.canUndo) {
                    _layerController.undo();
                  } else if (_layerController.canRedo) {
                    _layerController.redo();
                  }
                  HapticFeedback.mediumImpact();
                  break;
                case RadialMenuItem.knowledgeMap:
                  if (_knowledgeFlowController != null &&
                      _clusterCache.length >= 2) {
                    setState(() => _showKnowledgeMap = true);
                  }
                  HapticFeedback.selectionClick();
                  break;
                case RadialMenuItem.text:
                  _toolController.toggleDigitalTextMode();
                  HapticFeedback.selectionClick();
                  setState(() {});
                  break;
                case RadialMenuItem.shape:
                  _toolController.toggleShapeRecognition();
                  HapticFeedback.selectionClick();
                  setState(() {});
                  break;
                case RadialMenuItem.brush:
                  if (result.brushItem != null) {
                    final penType =
                        ProPenType.values[result.brushItem!.index.clamp(
                          0,
                          ProPenType.values.length - 1,
                        )];
                    _toolController.setPenType(penType);
                    _toolController.resetToDrawingMode();
                    HapticFeedback.selectionClick();
                    setState(() {});
                  } else if (result.selectedColor != null) {
                    // Color swatch selected from Brush sub-ring
                    _toolController.setColor(result.selectedColor!);
                    HapticFeedback.selectionClick();
                    setState(() {});
                  }
                  break;
                case RadialMenuItem.insert:
                  if (result.insertItem != null) {
                    switch (result.insertItem!) {
                      case RadialInsertItem.image:
                        pickAndAddImage();
                        break;
                      case RadialInsertItem.pdf:
                        pickAndAddPdf();
                        break;
                      case RadialInsertItem.latex:
                        _showLatexEditorSheet();
                        break;
                      case RadialInsertItem.audio:
                        if (_isRecordingAudio) {
                          _stopAudioRecording();
                        } else {
                          _showRecordingChoiceDialog();
                        }
                        break;
                      case RadialInsertItem.recordings:
                        _showSavedRecordingsDialog();
                        break;
                    }
                  }
                  break;
                case RadialMenuItem.tools:
                  if (result.toolItem != null) {
                    switch (result.toolItem!) {
                      case RadialToolItem.lasso:
                        _toolController.toggleLassoMode();
                        HapticFeedback.selectionClick();
                        setState(() {});
                        break;
                      case RadialToolItem.ruler:
                        setState(() => _showRulers = !_showRulers);
                        HapticFeedback.selectionClick();
                        break;
                      case RadialToolItem.search:
                        _activateEchoSearch();
                        HapticFeedback.mediumImpact();
                        break;
                      case RadialToolItem.export:
                        _enterExportMode();
                        HapticFeedback.mediumImpact();
                        break;
                      case RadialToolItem.multiview:
                        _launchAdvancedSplitView();
                        HapticFeedback.mediumImpact();
                        break;
                      case RadialToolItem.recall:
                        showRecallZoneSelector();
                        HapticFeedback.mediumImpact();
                        break;
                      case RadialToolItem.layers:
                        _layerPanelKey.currentState?.togglePanel();
                        HapticFeedback.selectionClick();
                        break;
                      case RadialToolItem.eraserToggle:
                        // Enable eraser mode and toggle between whole/partial
                        if (!_toolController.isErasing) {
                          _toolController.setEraserMode(true);
                        } else {
                          _eraserTool.eraseWholeStroke =
                              !_eraserTool.eraseWholeStroke;
                        }
                        HapticFeedback.mediumImpact();
                        setState(() {});
                        break;
                    }
                  }
                  break;
                case RadialMenuItem.atlas:
                  // 🌌 Atlas AI: Show quick action choice
                  HapticFeedback.mediumImpact();
                  showModalBottomSheet(
                    context: context,
                    backgroundColor: Colors.transparent,
                    barrierColor: Colors.black.withValues(alpha: 0.4),
                    builder: (_) => Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D0D1A),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                        border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.12)),
                      ),
                      child: SafeArea(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          const SizedBox(height: 8),
                          Container(width: 36, height: 4,
                            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(2))),
                          const SizedBox(height: 20),
                          ListTile(
                            leading: const Text('⚡', style: TextStyle(fontSize: 22)),
                            title: const Text('Chiedi ad Atlas', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                            subtitle: Text('Prompt libero o analisi selezione', style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12)),
                            onTap: () {
                              Navigator.pop(context);
                              setState(() { _showAtlasPrompt = true; _atlasIsLoading = false; _atlasResponseText = null; });
                            },
                          ),
                          if (V1FeatureGate.examSession)
                            ListTile(
                              leading: const Text('🎓', style: TextStyle(fontSize: 22)),
                              title: const Text('Interrogami', style: TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.w600)),
                              subtitle: Text('Esame interattivo sui tuoi appunti', style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12)),
                              onTap: () {
                                Navigator.pop(context);
                                _startExamSession();
                              },
                            ),
                          ListTile(
                            leading: const Text('💬', style: TextStyle(fontSize: 22)),
                            title: const Text('Chat with Notes', style: TextStyle(color: Color(0xFF69F0AE), fontWeight: FontWeight.w600)),
                            subtitle: Text('Chatta con Atlas sui tuoi appunti', style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12)),
                            onTap: () {
                              Navigator.pop(context);
                              _startChatWithNotes();
                            },
                          ),
                          const SizedBox(height: 8),
                        ]),
                      ),
                    ),
                  );
                  break;
              }
            },
          ),
        ),

      // ── 🌌 Atlas Prompt Overlay ──────────────────────────────────────────
      if (_showAtlasPrompt)
        Positioned(
          left: 0,
          right: 0,
          bottom: MediaQuery.of(context).viewInsets.bottom + 80,
          child: Center(
            child: AtlasPromptOverlay(
              hasSelection: _lassoTool.hasSelection,
              selectedNodeCount: _lassoTool.selectionCount,
              isLoading: _atlasIsLoading,
              loadingPhase: _atlasLoadingPhase,
              responseText: _atlasResponseText,
              selectedNodeTypes: _lassoTool.hasSelection
                  ? _lassoTool.selectionManager.selectedNodes
                      .map((n) {
                        if (n is StrokeNode) return 'stroke';
                        if (n is TextNode) return 'text';
                        if (n is LatexNode) return 'latex';
                        if (n is PdfPageNode) return 'pdf';
                        final typeName = n.runtimeType.toString();
                        if (typeName == 'ImageNode') return 'image';
                        if (typeName == 'ShapeNode') return 'shape';
                        return 'other';
                      })
                      .toSet()
                  : const <String>{},
              onDismiss: () {
                setState(() {
                  _showAtlasPrompt = false;
                  _atlasIsLoading = false;
                  _atlasResponseText = null;
                  _atlasLoadingPhase = null;
                });
              },
              onSubmit: (prompt) => _invokeAtlas(prompt),
            ),
          ),
        ),


      // ── 🌌 Atlas Scan Pulse (during loading) ────────────────────────────
      if (_atlasIsLoading && _lassoTool.hasSelection)
        Builder(
          builder: (context) {
            final bounds = _lassoTool.getSelectionBounds();
            if (bounds == null) return const SizedBox.shrink();
            // Convert selection bounds to screen coords
            final tl = _canvasController.canvasToScreen(bounds.topLeft);
            final br = _canvasController.canvasToScreen(bounds.bottomRight);
            final screenBounds = Rect.fromPoints(tl, br);
            return AtlasScanPulseOverlay(
              selectionBounds: screenBounds,
              isActive: _atlasIsLoading,
            );
          },
        ),

      // ── 🌌 Atlas Materialization VFX ────────────────────────────────────
      for (final vfx in _atlasVfxEntries)
        if (vfx.type == _AtlasVfxType.materialize)
          AtlasMaterializeEffect(
            key: vfx.key,
            position: vfx.position,
            onComplete: () {
              if (mounted) {
                setState(() {
                  _atlasVfxEntries.removeWhere((e) => e.key == vfx.key);
                });
              }
            },
          ),

      // 🔮 Atlas cards moved to _buildAtlasCards() — rendered above menus in _build_ui.dart

      // ── 📝 Inline Text Editing Overlay ──────────────────────────────────
      if (_isInlineEditing && _inlineEditingElement != null) ...[
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _canvasController,
            builder: (context, _) {
              final element = _inlineEditingElement!;
              final screenPos = _canvasController.canvasToScreen(
                element.position,
              );
              final scale = _canvasController.scale;
              final screenWidth = MediaQuery.of(context).size.width;
              return Stack(
                children: [
                  // Tap-outside detector to finish editing
                  // ⚠️ Must be OPAQUE to block tap from reaching canvas
                  // gesture detector (otherwise it triggers a new text creation)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        FocusManager.instance.primaryFocus?.unfocus();
                      },
                    ),
                  ),

                  // Formatting toolbar (above the text)
                  Positioned(
                    left: (screenPos.dx - 20).clamp(8.0, screenWidth - 350),
                    top: (screenPos.dy - 130).clamp(8.0, double.infinity),
                    child: InlineTextToolbar(
                      currentColor: _inlineTextColor,
                      currentFontWeight: _inlineTextFontWeight,
                      isItalic: _inlineTextFontStyle == FontStyle.italic,
                      currentFontSize: _inlineTextFontSize,
                      onColorChanged: (color) {
                        setState(() => _inlineTextColor = color);
                      },
                      onFontWeightChanged: (weight) {
                        setState(() => _inlineTextFontWeight = weight);
                      },
                      onItalicChanged: (italic) {
                        setState(
                          () =>
                              _inlineTextFontStyle =
                                  italic ? FontStyle.italic : FontStyle.normal,
                        );
                      },
                      textDecoration: _inlineTextDecoration,
                      onTextDecorationChanged: (decoration) {
                        setState(() => _inlineTextDecoration = decoration);
                      },
                      textAlign: _inlineTextAlign,
                      onTextAlignChanged: (align) {
                        setState(() => _inlineTextAlign = align);
                      },
                      onFontSizeChanged: (size) {
                        setState(() => _inlineTextFontSize = size);
                      },
                      currentFontFamily: _inlineTextFontFamily,
                      onFontFamilyChanged: (family) {
                        setState(() => _inlineTextFontFamily = family);
                      },
                      letterSpacing: _inlineTextLetterSpacing,
                      onLetterSpacingChanged: (spacing) {
                        setState(() => _inlineTextLetterSpacing = spacing);
                      },
                      opacity: _inlineTextOpacity,
                      onOpacityChanged: (opacity) {
                        setState(() => _inlineTextOpacity = opacity);
                      },
                      bgColor: _inlineTextBackgroundColor,
                      hasBackground: _inlineTextBackgroundColor != null,
                      onBackgroundChanged: (enabled) {
                        setState(() {
                          _inlineTextBackgroundColor =
                              enabled
                                  ? Colors.yellow.withValues(alpha: 0.3)
                                  : null;
                        });
                      },
                      onBackgroundColorChanged: (color) {
                        setState(() => _inlineTextBackgroundColor = color);
                      },
                      hasShadow: _inlineTextShadow != null,
                      onShadowChanged: (enabled) {
                        setState(() {
                          if (enabled) {
                            _inlineTextShadow = Shadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 16,
                              offset: Offset.zero,
                            );
                          } else {
                            _inlineTextShadow = null;
                          }
                        });
                      },
                      shadowColor: _inlineTextShadow?.color,
                      onShadowColorChanged: (color) {
                        setState(() {
                          _inlineTextShadow = Shadow(
                            color: color,
                            blurRadius: _inlineTextShadow?.blurRadius ?? 16,
                            offset: _inlineTextShadow?.offset ?? Offset.zero,
                          );
                        });
                      },
                      hasOutline: _inlineTextOutlineColor != null,
                      onOutlineChanged: (enabled) {
                        setState(() {
                          if (enabled) {
                            _inlineTextOutlineColor = Colors.black;
                            _inlineTextOutlineWidth = 1.5;
                          } else {
                            _inlineTextOutlineColor = null;
                            _inlineTextOutlineWidth = 0.0;
                          }
                        });
                      },
                      outlineColor: _inlineTextOutlineColor,
                      onOutlineColorChanged: (color) {
                        setState(() => _inlineTextOutlineColor = color);
                      },
                      hasGradient: _inlineTextGradientColors != null,
                      onGradientChanged: (enabled) {
                        setState(() {
                          if (enabled) {
                            _inlineTextGradientColors = [
                              Colors.blue,
                              Colors.purple,
                            ];
                          } else {
                            _inlineTextGradientColors = null;
                          }
                        });
                      },
                      hasGlow:
                          _inlineTextShadow != null &&
                          _inlineTextShadow!.blurRadius >= 10 &&
                          _inlineTextShadow!.color !=
                              Colors.black.withValues(alpha: 0.3),
                      onGlowChanged: (enabled) {
                        setState(() {
                          if (enabled) {
                            _inlineTextShadow = Shadow(
                              color: Colors.blue.withValues(alpha: 0.6),
                              blurRadius: 16,
                              offset: Offset.zero,
                            );
                          } else {
                            _inlineTextShadow = null;
                          }
                        });
                      },
                      glowColor: _inlineTextShadow?.color,
                      onGlowColorChanged: (color) {
                        setState(() {
                          _inlineTextShadow = Shadow(
                            color: color,
                            blurRadius: 16,
                            offset: Offset.zero,
                          );
                        });
                      },
                      onDuplicate:
                          _inlineEditingElement != null &&
                                  _digitalTextElements.any(
                                    (e) => e.id == _inlineEditingElement!.id,
                                  )
                              ? () {
                                _finishInlineText(_inlineEditingElement!.text);
                                final source = _digitalTextElements.lastWhere(
                                  (e) => e.id == _inlineEditingElement?.id,
                                  orElse: () => _digitalTextElements.last,
                                );
                                final copy = source.copyWith(
                                  id: generateUid(),
                                  position:
                                      source.position + const Offset(20, 20),
                                  createdAt: DateTime.now(),
                                );
                                setState(() {
                                  _digitalTextElements.add(copy);
                                });
                              }
                              : null,
                      onCopyStyle: () {
                        setState(() {
                          _copiedTextStyle = {
                            'fontWeight': _inlineTextFontWeight,
                            'fontStyle': _inlineTextFontStyle,
                            'color': _inlineTextColor,
                            'fontSize': _inlineTextFontSize,
                            'fontFamily': _inlineTextFontFamily,
                            'shadow': _inlineTextShadow,
                            'backgroundColor': _inlineTextBackgroundColor,
                            'textDecoration': _inlineTextDecoration,
                            'letterSpacing': _inlineTextLetterSpacing,
                            'opacity': _inlineTextOpacity,
                            'outlineColor': _inlineTextOutlineColor,
                            'outlineWidth': _inlineTextOutlineWidth,
                            'gradientColors': _inlineTextGradientColors,
                          };
                        });
                        HapticFeedback.lightImpact();
                      },
                      onPasteStyle:
                          _copiedTextStyle != null
                              ? () {
                                final s = _copiedTextStyle!;
                                setState(() {
                                  _inlineTextFontWeight =
                                      s['fontWeight'] as FontWeight;
                                  _inlineTextFontStyle =
                                      s['fontStyle'] as FontStyle;
                                  _inlineTextColor = s['color'] as Color;
                                  _inlineTextFontSize = s['fontSize'] as double;
                                  _inlineTextFontFamily =
                                      s['fontFamily'] as String;
                                  _inlineTextShadow = s['shadow'] as Shadow?;
                                  _inlineTextBackgroundColor =
                                      s['backgroundColor'] as Color?;
                                  _inlineTextDecoration =
                                      s['textDecoration'] as TextDecoration;
                                  _inlineTextLetterSpacing =
                                      s['letterSpacing'] as double;
                                  _inlineTextOpacity = s['opacity'] as double;
                                  _inlineTextOutlineColor =
                                      s['outlineColor'] as Color?;
                                  _inlineTextOutlineWidth =
                                      s['outlineWidth'] as double;
                                  _inlineTextGradientColors =
                                      s['gradientColors'] as List<Color>?;
                                });
                                HapticFeedback.lightImpact();
                              }
                              : null,
                      onTemplateApply: (template) {
                        setState(() {
                          _inlineTextFontSize = template['fontSize'] as double;
                          _inlineTextFontWeight =
                              template['fontWeight'] as FontWeight;
                          _inlineTextLetterSpacing =
                              template['letterSpacing'] as double;
                        });
                        HapticFeedback.lightImpact();
                      },
                      onDelete:
                          _inlineEditingElement != null &&
                                  _digitalTextElements.any(
                                    (e) => e.id == _inlineEditingElement!.id,
                                  )
                              ? _deleteInlineTextElement
                              : null,
                      onBeforeDialog: () {
                        _inlineOverlayKey.currentState?.suppressFocusLoss();
                      },
                    ),
                  ),

                  // The inline TextField
                  Positioned(
                    left: screenPos.dx,
                    top: screenPos.dy,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth:
                            element.maxWidth != null
                                ? element.maxWidth! * scale
                                : screenWidth - screenPos.dx - 16,
                        minWidth: 40,
                      ),
                      child: InlineTextOverlay(
                        key: _inlineOverlayKey,
                        initialText: element.text,
                        color: _inlineTextColor,
                        fontSize: _inlineTextFontSize,
                        fontWeight: _inlineTextFontWeight,
                        fontStyle: _inlineTextFontStyle,
                        fontFamily: _inlineTextFontFamily,
                        canvasScale: scale,
                        elementScale: element.scale,
                        shadow: _inlineTextShadow,
                        backgroundColor: _inlineTextBackgroundColor,
                        outlineColor: _inlineTextOutlineColor,
                        outlineWidth: _inlineTextOutlineWidth,
                        gradientColors: _inlineTextGradientColors,
                        opacity: _inlineTextOpacity,
                        letterSpacing: _inlineTextLetterSpacing,
                        textDecoration: _inlineTextDecoration,
                        onSubmit: _finishInlineText,
                        onCancel: _cancelInlineText,
                        onSelectionChanged: (selection) {
                          _inlineTextSelection = selection;
                        },
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ], // close spread for inline editing overlay
    ];
  }

  /// 💡 Build the suggestion preview card with recognized text + accept/dismiss
  Widget _buildSuggestionPreviewCard(BuildContext context) {
    final suggestion = _previewSuggestion!;
    final srcText = _previewClusterTexts[suggestion.sourceClusterId] ?? '?';
    final tgtText = _previewClusterTexts[suggestion.targetClusterId] ?? '?';

    String trunc(String s, int max) =>
        s.length > max ? '${s.substring(0, max)}…' : s;

    // 🏷️ Reason chip: icon + color based on reason type
    final reason = suggestion.reason.toLowerCase();
    String chipIcon;
    Color chipColor;
    if (reason.contains('color') || reason.contains('colori')) {
      chipIcon = '🎨';
      chipColor = const Color(0xFF9C27B0);
    } else if (reason.contains('near') ||
        reason.contains('vicin') ||
        reason.contains('proxim')) {
      chipIcon = '📍';
      chipColor = const Color(0xFFFF9800);
    } else if (reason.contains('keyword') ||
        reason.contains('word') ||
        reason.contains('parol')) {
      chipIcon = '🔤';
      chipColor = const Color(0xFF4CAF50);
    } else if (reason.contains('size') || reason.contains('dimens')) {
      chipIcon = '📐';
      chipColor = const Color(0xFF2196F3);
    } else {
      chipIcon = '✨';
      chipColor = const Color(0xFF64B5F6);
    }

    // ✨ ENTRANCE ANIMATION: Scale up + fade in
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) {
        return Transform.scale(
          scale: 0.85 + 0.15 * t,
          child: Opacity(opacity: t, child: child),
        );
      },
      child: Material(
        color: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              width: 260,
              decoration: BoxDecoration(
                color: const Color(0xBB1A1A2E),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.15),
                  width: 0.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Cluster texts ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            trunc(srcText, 20),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            '↔',
                            style: TextStyle(
                              color: Color(0xFF64B5F6),
                              fontSize: 16,
                              fontWeight: FontWeight.w300,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            trunc(tgtText, 20),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // ── Reason chip ──
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: chipColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: chipColor.withValues(alpha: 0.3),
                          width: 0.5,
                        ),
                      ),
                      child: Text(
                        '$chipIcon  ${suggestion.reason}',
                        style: TextStyle(
                          color: chipColor.withValues(alpha: 0.9),
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  // ── Buttons ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              HapticFeedback.lightImpact();
                              _knowledgeFlowController?.dismissSuggestion(
                                suggestion,
                              );
                              setState(() {
                                _previewSuggestion = null;
                                _previewSuggestionPosition = null;
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text(
                                '✗  Skip',
                                style: TextStyle(
                                  color: Color(0xFFEF9A9A),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              debugPrint('🔗 [Suggestion] Connect tapped');
                              HapticFeedback.mediumImpact();
                              final conn = _knowledgeFlowController
                                  ?.acceptSuggestion(suggestion);
                              debugPrint(
                                '🔗 [Suggestion] acceptSuggestion → $conn',
                              );
                              setState(() {
                                _previewSuggestion = null;
                                _previewSuggestionPosition = null;
                              });
                              if (conn != null) {
                                final cMap = <String, ContentCluster>{};
                                for (final c in _clusterCache) {
                                  cMap[c.id] = c;
                                }
                                final src = cMap[conn.sourceClusterId];
                                final tgt = cMap[conn.targetClusterId];
                                if (src != null && tgt != null) {
                                  final cp = _knowledgeFlowController!
                                      .getControlPoint(
                                        src.centroid,
                                        tgt.centroid,
                                        conn.curveStrength,
                                      );
                                  final midCanvas = _knowledgeFlowController!
                                      .pointOnQuadBezier(
                                        src.centroid,
                                        cp,
                                        tgt.centroid,
                                        0.5,
                                      );
                                  final screenPos = _canvasController
                                      .canvasToScreen(midCanvas);
                                  setState(() {
                                    _editingLabelConnectionId = conn.id;
                                    _labelOverlayScreenPosition = screenPos;
                                  });
                                }
                                _autoSaveCanvas();
                                // 🔔 UNDO TOAST: safely try SnackBar
                                try {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: const Text(
                                          '✓  Connected',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        backgroundColor: const Color(
                                          0xDD1A1A2E,
                                        ),
                                        behavior: SnackBarBehavior.floating,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        duration: const Duration(seconds: 3),
                                        action: SnackBarAction(
                                          label: '↩ Undo',
                                          textColor: const Color(0xFF64B5F6),
                                          onPressed: () {
                                            _knowledgeFlowController
                                                ?.removeConnection(conn.id);
                                            _autoSaveCanvas();
                                            setState(() {});
                                          },
                                        ),
                                      ),
                                    );
                                  }
                                } catch (_) {
                                  // No Scaffold ancestor — skip SnackBar
                                }
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF64B5F6,
                                ).withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: const Color(
                                    0xFF64B5F6,
                                  ).withValues(alpha: 0.3),
                                ),
                              ),
                              child: const Text(
                                '✓  Connect',
                                style: TextStyle(
                                  color: Color(0xFF64B5F6),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                                textAlign: TextAlign.center,
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
          ),
        ),
      ),
    );
  }
}

/// 📊 In-cell editor — compact TextField for direct cell editing.
class _InCellEditor extends StatefulWidget {
  final String initialValue;
  final ValueChanged<String> onSubmit;
  final VoidCallback onCancel;

  const _InCellEditor({
    required this.initialValue,
    required this.onSubmit,
    required this.onCancel,
  });

  @override
  State<_InCellEditor> createState() => _InCellEditorState();
}

class _InCellEditorState extends State<_InCellEditor> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _focusNode = FocusNode();

    // Auto-focus and select all
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    });

    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) {
        widget.onCancel();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return KeyboardListener(
      focusNode: FocusNode(),
      onKeyEvent: (event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          widget.onCancel();
        }
      },
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        style: TextStyle(fontSize: 13, color: cs.onSurface),
        decoration: InputDecoration(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(2),
            borderSide: BorderSide(color: Colors.blue, width: 2),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(2),
            borderSide: BorderSide(color: Colors.blue, width: 2),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(2),
            borderSide: BorderSide(color: Colors.blue, width: 2.5),
          ),
          filled: true,
          fillColor: cs.surface,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 6,
            vertical: 4,
          ),
          isDense: true,
        ),
        onSubmitted: widget.onSubmit,
      ),
    );
  }
}

// ── Fill handle helper widgets ────────────────────────────────────────────

/// Draws a dashed rectangular border with optional fill.
class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double dashLength;
  final double gapLength;
  final Color? fill;

  const _DashedBorderPainter({
    required this.color,
    this.strokeWidth = 2.0,
    this.dashLength = 6.0,
    this.gapLength = 4.0,
    this.fill,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (fill != null) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..color = fill!
          ..style = PaintingStyle.fill,
      );
    }

    final paint =
        Paint()
          ..color = color
          ..strokeWidth = strokeWidth
          ..style = PaintingStyle.stroke;

    final path = Path();
    final perimeter =
        2 * (size.width + size.height); // total length of rectangle
    final segment = dashLength + gapLength;
    double drawn = 0;

    // Walk around the rectangle perimeter.
    while (drawn < perimeter) {
      final start = _perimeterPoint(drawn, size);
      final end = _perimeterPoint(
        (drawn + dashLength).clamp(0, perimeter),
        size,
      );
      path.moveTo(start.dx, start.dy);
      path.lineTo(end.dx, end.dy);
      drawn += segment;
    }

    canvas.drawPath(path, paint);
  }

  Offset _perimeterPoint(double dist, Size size) {
    if (dist <= size.width) return Offset(dist, 0);
    dist -= size.width;
    if (dist <= size.height) return Offset(size.width, dist);
    dist -= size.height;
    if (dist <= size.width) return Offset(size.width - dist, size.height);
    dist -= size.width;
    return Offset(0, size.height - dist);
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter old) =>
      color != old.color ||
      strokeWidth != old.strokeWidth ||
      dashLength != old.dashLength ||
      fill != old.fill;
}

/// Fill handle with hover scale animation.
class _FillHandleWidget extends StatefulWidget {
  final double size;
  final VoidCallback onDown;
  final void Function(Offset position) onMove;
  final VoidCallback onUp;

  const _FillHandleWidget({
    required this.size,
    required this.onDown,
    required this.onMove,
    required this.onUp,
  });

  @override
  State<_FillHandleWidget> createState() => _FillHandleWidgetState();
}

class _FillHandleWidgetState extends State<_FillHandleWidget> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => widget.onDown(),
      onPointerMove: (e) => widget.onMove(e.position),
      onPointerUp: (_) => widget.onUp(),
      child: MouseRegion(
        cursor: SystemMouseCursors.precise,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedScale(
          scale: _hovered ? 1.4 : 1.0,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.blue,
                border: Border.all(color: Colors.white, width: 1.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 🎯 Floating toolbar for lasso selection mode switching + feather slider.
/// Appears at the top of the canvas when the lasso tool is active.
class _LassoModeToolbar extends StatefulWidget {
  final SelectionMode currentMode;
  final double featherRadius;
  final ValueChanged<SelectionMode> onModeChanged;
  final ValueChanged<double> onFeatherChanged;
  final VoidCallback onColorSelect;
  final bool isDark;

  const _LassoModeToolbar({
    required this.currentMode,
    required this.featherRadius,
    required this.onModeChanged,
    required this.onFeatherChanged,
    required this.onColorSelect,
    required this.isDark,
  });

  @override
  State<_LassoModeToolbar> createState() => _LassoModeToolbarState();
}

class _LassoModeToolbarState extends State<_LassoModeToolbar> {
  bool _showFeather = false;

  @override
  Widget build(BuildContext context) {
    final bg =
        widget.isDark ? const Color(0xDD1A1A2E) : const Color(0xDDFFFFFF);
    final accent = const Color(0xFF4A90D9);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Mode buttons row
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color:
                      widget.isDark
                          ? Colors.white.withValues(alpha: 0.12)
                          : Colors.black.withValues(alpha: 0.08),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildModeButton(
                    icon: Icons.gesture_rounded,
                    label: 'Lasso',
                    mode: SelectionMode.lasso,
                    accent: accent,
                  ),
                  _buildModeButton(
                    icon: Icons.crop_square_rounded,
                    label: 'Rect',
                    mode: SelectionMode.marquee,
                    accent: accent,
                  ),
                  _buildModeButton(
                    icon: Icons.circle_outlined,
                    label: 'Ellipse',
                    mode: SelectionMode.ellipse,
                    accent: accent,
                  ),

                  // Divider
                  Container(
                    width: 1,
                    height: 22,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    color:
                        widget.isDark
                            ? Colors.white.withValues(alpha: 0.15)
                            : Colors.black.withValues(alpha: 0.1),
                  ),

                  // Feather toggle
                  _buildIconButton(
                    icon: Icons.blur_on_rounded,
                    tooltip:
                        'Feather: ${widget.featherRadius.toStringAsFixed(0)}',
                    isActive: _showFeather,
                    color: Colors.purple,
                    onTap: () {
                      setState(() => _showFeather = !_showFeather);
                      HapticFeedback.selectionClick();
                    },
                  ),
                ],
              ),
            ),
          ),
        ),

        // Feather slider (expandable)
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child:
              _showFeather
                  ? Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: BackdropFilter(
                        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          width: 220,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: bg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.purple.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.blur_on,
                                size: 14,
                                color: Colors.purple.shade300,
                              ),
                              Expanded(
                                child: SliderTheme(
                                  data: SliderThemeData(
                                    trackHeight: 3,
                                    thumbShape: const RoundSliderThumbShape(
                                      enabledThumbRadius: 6,
                                    ),
                                    activeTrackColor: Colors.purple.shade400,
                                    inactiveTrackColor: Colors.purple
                                        .withValues(alpha: 0.2),
                                    thumbColor: Colors.purple.shade300,
                                  ),
                                  child: Slider(
                                    min: 0,
                                    max: 20,
                                    value: widget.featherRadius.clamp(0, 20),
                                    onChanged: widget.onFeatherChanged,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 28,
                                child: Text(
                                  widget.featherRadius.toStringAsFixed(0),
                                  textAlign: TextAlign.end,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontFamily: 'monospace',
                                    color:
                                        widget.isDark
                                            ? Colors.white54
                                            : Colors.black45,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                  : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildModeButton({
    required IconData icon,
    required String label,
    required SelectionMode mode,
    required Color accent,
  }) {
    final isActive = widget.currentMode == mode;
    return GestureDetector(
      onTap: () => widget.onModeChanged(mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? accent.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: isActive ? accent : Colors.grey),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color:
                    isActive
                        ? accent
                        : (widget.isDark ? Colors.white60 : Colors.black54),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required String tooltip,
    required bool isActive,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isActive ? color.withValues(alpha: 0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: isActive ? color : Colors.grey),
        ),
      ),
    );
  }
}

/// Paints an expanding, fading ripple circle at a given center.
/// Used for the gestural lasso closing animation.
class _LassoRipplePainter extends CustomPainter {
  final Offset center;
  final double radius;
  final double opacity;

  _LassoRipplePainter({
    required this.center,
    required this.radius,
    required this.opacity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Outer ring glow
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0xFF818CF8).withValues(alpha: opacity * 0.3)
        ..strokeWidth = 3.0
        ..style = PaintingStyle.stroke
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.15),
    );
    // Inner ring
    canvas.drawCircle(
      center,
      radius * 0.6,
      Paint()
        ..color = const Color(0xFF22D3EE).withValues(alpha: opacity * 0.2)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.1),
    );
    // Core flash
    canvas.drawCircle(
      center,
      radius * 0.2,
      Paint()
        ..color = Colors.white.withValues(alpha: opacity * 0.4)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.1),
    );
  }

  @override
  bool shouldRepaint(_LassoRipplePainter oldDelegate) =>
      center != oldDelegate.center ||
      radius != oldDelegate.radius ||
      opacity != oldDelegate.opacity;
}
