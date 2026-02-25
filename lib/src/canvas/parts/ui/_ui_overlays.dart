part of '../../nebula_canvas_screen.dart';

/// 🛠️ Standard Overlays — lasso, selection, pen tool, ruler, digital text,
/// remote viewports / presence.
/// Extracted from _NebulaCanvasScreenState._buildImpl
extension NebulaCanvasOverlaysUI on _NebulaCanvasScreenState {
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
      if (_effectiveIsLasso)
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
                    repaint: _lassoTool.lassoPathNotifier,
                  ),
                  size: Size.infinite,
                );
              },
            ),
          ),
        ),

      // Selection Overlay — DENTRO l'area canvas (non more nello Stack principale)
      if (_lassoTool.hasSelection)
        Positioned.fill(
          child: IgnorePointer(
            child: LassoSelectionOverlay(
              selectedIds: _lassoTool.selectedIds,
              layerController: _layerController,
              canvasController: _canvasController,
              isDragging: _lassoTool.isDragging,
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
                  if (NebulaCanvasTabularFillHandle
                          ._lastFilledAddresses
                          .isNotEmpty &&
                      NebulaCanvasTabularFillHandle._lastFillTime != null)
                    Builder(
                      builder: (ctx) {
                        final elapsed =
                            DateTime.now()
                                .difference(
                                  NebulaCanvasTabularFillHandle._lastFillTime!,
                                )
                                .inMilliseconds;
                        if (elapsed > 600) {
                          // Animation complete — clear.
                          NebulaCanvasTabularFillHandle._lastFilledAddresses =
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
                                in NebulaCanvasTabularFillHandle
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

  /// Tool overlays: ruler, digital text, text selection, recorded playback.
  /// Ordered AFTER eraser overlays in the Z-stack.
  List<Widget> _buildToolOverlays(BuildContext context) {
    return [
      // 📏 Phase 3C: Interactive Ruler & Guide Overlay
      // Always present so the corner menu remains accessible
      Positioned.fill(
        child: RulerInteractiveOverlay(
          guideSystem: _rulerGuideSystem,
          canvasController: _canvasController,
          isDark: Theme.of(context).brightness == Brightness.dark,
          onChanged: () => setState(() {}),
        ),
      ),

      // Digital Text Elements - Rendering dei testi
      ..._digitalTextElements.map((textElement) {
        // Durante drag/resize, salta l'selected element
        if (_digitalTextTool.hasSelection &&
            _digitalTextTool.selectedElement!.id == textElement.id) {
          return const SizedBox.shrink();
        }

        final screenPos = _canvasController.canvasToScreen(
          textElement.position,
        );

        return Positioned(
          left: screenPos.dx,
          top: screenPos.dy,
          child: IgnorePointer(
            child: Text(
              textElement.text,
              style: TextStyle(
                fontSize:
                    textElement.fontSize *
                    textElement.scale *
                    _canvasController.scale,
                color: textElement.color,
                fontWeight: textElement.fontWeight,
                fontFamily: textElement.fontFamily,
              ),
            ),
          ),
        );
      }),

      // Rendering dell'selected element dal TOOL
      if (_digitalTextTool.hasSelection)
        Positioned.fill(
          child: Builder(
            builder: (context) {
              final textElement = _digitalTextTool.selectedElement!;
              final screenPos = _canvasController.canvasToScreen(
                textElement.position,
              );

              return Stack(
                children: [
                  Positioned(
                    left: screenPos.dx,
                    top: screenPos.dy,
                    child: IgnorePointer(
                      child: Text(
                        textElement.text,
                        style: TextStyle(
                          fontSize:
                              textElement.fontSize *
                              textElement.scale *
                              _canvasController.scale,
                          color: textElement.color,
                          fontWeight: textElement.fontWeight,
                          fontFamily: textElement.fontFamily,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),

      // Rettangolo di selezione per l'selected element
      if (_digitalTextTool.hasSelection)
        Positioned.fill(
          child: Builder(
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

              return Stack(
                children: [
                  Positioned(
                    left: screenPos.dx,
                    top: screenPos.dy,
                    width: width,
                    height: height,
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Colors.deepPurple.withValues(alpha: 0.3),
                            width: 2.0,
                          ),
                          color: Colors.deepPurple.withValues(alpha: 0.05),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),

      // Handle di resize - 4 cerchietti agli angoli
      if (_digitalTextTool.hasSelection)
        Positioned.fill(
          child: Builder(
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
        ),
    ];
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
