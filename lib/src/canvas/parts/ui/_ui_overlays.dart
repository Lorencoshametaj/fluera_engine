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
        Builder(
          builder: (context) {
            final bounds = _tabularTool.selectionBounds!;
            final screenTL = _canvasController.canvasToScreen(bounds.topLeft);
            final screenBR = _canvasController.canvasToScreen(
              bounds.bottomRight,
            );
            final screenRect = Rect.fromPoints(screenTL, screenBR);

            return Positioned(
              left: screenRect.left - 2,
              top: screenRect.top - 2,
              width: screenRect.width + 4,
              height: screenRect.height + 4,
              child: IgnorePointer(
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
            );
          },
        ),

      // 📊 Selected cell / range highlight
      if (_tabularTool.hasCellSelection)
        Builder(
          builder: (context) {
            final range = _tabularTool.selectedRange;
            if (range == null) return const SizedBox.shrink();

            // Get bounding rect of the entire range
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

            return Positioned(
              left: screenRect.left,
              top: screenRect.top,
              width: screenRect.width,
              height: screenRect.height,
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.blue, width: 2.5),
                    color: Colors.blue.withValues(alpha: 0.08),
                  ),
                ),
              ),
            );
          },
        ),

      // 📊 In-cell editing overlay
      if (_editingInCell && _tabularTool.hasCellSelection)
        Builder(
          builder: (context) {
            final cellRect = _tabularTool.getCellRect(
              _tabularTool.selectedCol!,
              _tabularTool.selectedRow!,
              _canvasController.offset,
              _canvasController.scale,
            );
            if (cellRect == null) return const SizedBox.shrink();

            final currentValue = _getSelectedCellDisplayValue() ?? '';

            return Positioned(
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
            );
          },
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
          },
        ),

      // Rettangolo di selezione per l'selected element
      if (_digitalTextTool.hasSelection)
        Builder(
          builder: (context) {
            final textElement = _digitalTextTool.selectedElement!;
            final screenPos = _canvasController.canvasToScreen(
              textElement.position,
            );

            // Calculate dimensioni del testo
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
                      color: Colors.deepPurple.withValues(alpha: 0.3),
                      width: 2.0,
                    ),
                    color: Colors.deepPurple.withValues(alpha: 0.05),
                  ),
                ),
              ),
            );
          },
        ),

      // Handle di resize - 4 cerchietti agli angoli
      if (_digitalTextTool.hasSelection)
        Builder(
          builder: (context) {
            final textElement = _digitalTextTool.selectedElement!;
            final screenPos = _canvasController.canvasToScreen(
              textElement.position,
            );

            // Calculate dimensioni del testo
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

            // Posizioni dei 4 handle agli angoli
            final handles = [
              Offset(screenPos.dx, screenPos.dy), // top-left
              Offset(screenPos.dx + width, screenPos.dy), // top-right
              Offset(screenPos.dx, screenPos.dy + height), // bottom-left
              Offset(
                screenPos.dx + width,
                screenPos.dy + height,
              ), // bottom-right
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
                            border: Border.all(color: Colors.white, width: 2.0),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
            );
          },
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
