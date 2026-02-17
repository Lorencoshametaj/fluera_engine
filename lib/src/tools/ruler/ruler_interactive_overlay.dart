import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../rendering/canvas/ruler_painter.dart';
import './ruler_guide_system.dart';
import '../../canvas/infinite_canvas_controller.dart';

part 'ruler_overlay_menu.dart';
part 'ruler_overlay_actions.dart';
part 'ruler_overlay_gestures.dart';
part 'ruler_overlay_dialogs.dart';

/// 📐 Interactive ruler overlay
///
/// Full interaction layer for guides, measurement, perspective VPs, and menus.
class RulerInteractiveOverlay extends StatefulWidget {
  final RulerGuideSystem guideSystem;
  final InfiniteCanvasController canvasController;
  final bool isDark;
  final VoidCallback onChanged;
  final ValueNotifier<Offset?>? cursorNotifier;

  const RulerInteractiveOverlay({
    super.key,
    required this.guideSystem,
    required this.canvasController,
    required this.isDark,
    required this.onChanged,
    this.cursorNotifier,
  });

  @override
  State<RulerInteractiveOverlay> createState() =>
      _RulerInteractiveOverlayState();
}

class _RulerInteractiveOverlayState extends State<RulerInteractiveOverlay> {
  bool _isDragging = false;
  bool _isHorizontalGuide = false;
  int? _dragGuideIndex;
  Offset? _cursorPosition;

  /// For multi-select drag
  bool _isDraggingSelected = false;
  Offset? _multiDragStart;

  /// For draggable ruler origin
  bool _isDraggingOrigin = false;

  /// For diagonal guide gesture (long-press + drag from ruler)
  bool _isDraggingDiagonal = false;
  Offset? _diagonalStart;

  /// Focus for keyboard shortcuts
  final FocusNode _focusNode = FocusNode();

  static const double rulerSize = RulerPainter.rulerSize;
  static const double _stripW = 24.0;

  @override
  void initState() {
    super.initState();
    widget.canvasController.addListener(_rebuild);
    widget.cursorNotifier?.addListener(_onCursor);
  }

  @override
  void dispose() {
    widget.canvasController.removeListener(_rebuild);
    widget.cursorNotifier?.removeListener(_onCursor);
    _focusNode.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _onCursor() {
    if (mounted) setState(() => _cursorPosition = widget.cursorNotifier?.value);
  }

  // ─── Keyboard Shortcuts ──────────────────────────────────────────

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final gs = widget.guideSystem;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final key = event.logicalKey;

    // G = toggle guides
    if (key == LogicalKeyboardKey.keyG && !ctrl && !shift) {
      setState(() => gs.guidesVisible = !gs.guidesVisible);
      widget.onChanged();
      return KeyEventResult.handled;
    }
    // R = toggle rulers
    if (key == LogicalKeyboardKey.keyR && !ctrl && !shift) {
      setState(() => gs.rulersVisible = !gs.rulersVisible);
      widget.onChanged();
      return KeyEventResult.handled;
    }
    // Ctrl+; = toggle snap
    if (key == LogicalKeyboardKey.semicolon && ctrl && !shift) {
      setState(() => gs.snapEnabled = !gs.snapEnabled);
      widget.onChanged();
      return KeyEventResult.handled;
    }
    // Ctrl+Shift+G = toggle grid
    if (key == LogicalKeyboardKey.keyG && ctrl && shift) {
      setState(() => gs.gridVisible = !gs.gridVisible);
      widget.onChanged();
      return KeyEventResult.handled;
    }
    // Ctrl+' = toggle golden spiral
    if (key == LogicalKeyboardKey.quoteSingle && ctrl) {
      setState(() => gs.showGoldenSpiral = !gs.showGoldenSpiral);
      widget.onChanged();
      return KeyEventResult.handled;
    }
    // ; = cycle grid style
    if (key == LogicalKeyboardKey.semicolon && !ctrl) {
      gs.cycleGridStyle();
      widget.onChanged();
      setState(() {});
      return KeyEventResult.handled;
    }
    // X = toggle crosshair
    if (key == LogicalKeyboardKey.keyX && !ctrl && !shift) {
      setState(() => gs.crosshairEnabled = !gs.crosshairEnabled);
      widget.onChanged();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  Rect _viewportRect() {
    final sz = context.size ?? const Size(800, 600);
    final s = widget.canvasController.scale;
    final o = widget.canvasController.offset;
    return Rect.fromLTWH(-o.dx / s, -o.dy / s, sz.width / s, sz.height / s);
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.canvasController.scale;
    final offset = widget.canvasController.offset;
    final gs = widget.guideSystem;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => _focusNode.requestFocus(),
        child: Stack(
          children: [
            // Paint layer
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: RulerPainter(
                    guideSystem: gs,
                    canvasOffset: offset,
                    zoom: scale,
                    isDark: widget.isDark,
                    cursorPosition: _cursorPosition,
                    activeGuideIndex: _dragGuideIndex,
                    activeGuideIsHorizontal:
                        _isDragging ? _isHorizontalGuide : null,
                  ),
                ),
              ),
            ),

            // Measurement mode
            if (gs.isMeasuring)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: onMeasureStart,
                  onPanUpdate: onMeasureUpdate,
                  onPanEnd: (_) => onMeasureEnd(),
                  onTap: () {
                    setState(() => gs.clearMeasurement());
                    widget.onChanged();
                  },
                ),
              ),

            // Multi-select drag layer
            if (gs.multiSelectMode && gs.selectedCount > 0 && !_isDragging)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onPanStart: onMultiDragStart,
                  onPanUpdate: onMultiDragUpdate,
                  onPanEnd: (_) => onMultiDragEnd(),
                ),
              ),

            // Guide grab strips
            if (!_isDragging &&
                !gs.isMeasuring &&
                !gs.multiSelectMode &&
                gs.guidesVisible)
              for (int i = 0; i < gs.horizontalGuides.length; i++)
                _buildHStrip(i, scale, offset),
            if (!_isDragging &&
                !gs.isMeasuring &&
                !gs.multiSelectMode &&
                gs.guidesVisible)
              for (int i = 0; i < gs.verticalGuides.length; i++)
                _buildVStrip(i, scale, offset),

            // Drag layer (single guide)
            if (_isDragging)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: onDragUpdate,
                  onPanEnd: (_) => onDragEnd(),
                  onPanCancel: onDragEnd,
                ),
              ),

            // Ruler strips
            if (!gs.isMeasuring) ...[
              Positioned(
                left: rulerSize,
                top: 0,
                right: 0,
                height: rulerSize,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (d) => onRulerDragStart(d, true),
                  onPanUpdate: onDragUpdate,
                  onPanEnd: (_) => onDragEnd(),
                  onLongPressStart: (d) => onRulerLongPress(d, true),
                ),
              ),
              Positioned(
                left: 0,
                top: rulerSize,
                width: rulerSize,
                bottom: 0,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (d) => onRulerDragStart(d, false),
                  onPanUpdate: onDragUpdate,
                  onPanEnd: (_) => onDragEnd(),
                  onLongPressStart: (d) => onRulerLongPress(d, false),
                ),
              ),
            ],

            // Corner box — tap = menu, drag = move origin
            Positioned(
              left: 0,
              top: 0,
              width: rulerSize,
              height: rulerSize,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: showCornerMenu,
                onPanStart: (_) {
                  setState(() => _isDraggingOrigin = true);
                },
                onPanUpdate: (d) {
                  final gs = widget.guideSystem;
                  final scale = widget.canvasController.scale;
                  gs.rulerOrigin = Offset(
                    gs.rulerOrigin.dx + d.delta.dx / scale,
                    gs.rulerOrigin.dy + d.delta.dy / scale,
                  );
                  widget.onChanged();
                  setState(() {});
                },
                onPanEnd: (_) {
                  setState(() => _isDraggingOrigin = false);
                },
                onPanCancel: () {
                  setState(() => _isDraggingOrigin = false);
                },
              ),
            ),

            // Mode indicators
            if (gs.isMeasuring)
              Positioned(
                left: rulerSize + 8,
                top: 4,
                child: _buildChip(
                  'Measure',
                  Icons.straighten,
                  const Color(0xFFF57F17),
                  () {
                    setState(() {
                      gs.isMeasuring = false;
                      gs.clearMeasurement();
                    });
                    widget.onChanged();
                  },
                ),
              ),
            if (gs.multiSelectMode)
              Positioned(
                left: rulerSize + 8,
                top: gs.isMeasuring ? 30 : 4,
                child: _buildChip(
                  'Select (${gs.selectedCount})',
                  Icons.select_all,
                  const Color(0xFF42A5F5),
                  () {
                    setState(() => gs.clearSelection());
                    widget.onChanged();
                  },
                ),
              ),
            if (gs.symmetryEnabled)
              Positioned(
                left: rulerSize + 8,
                top: (gs.isMeasuring ? 30 : 4) + (gs.multiSelectMode ? 26 : 0),
                child: _buildChip(
                  'Symmetry',
                  Icons.flip,
                  const Color(0xFF7C4DFF),
                  () {
                    setState(() => gs.clearSymmetry());
                    widget.onChanged();
                  },
                ),
              ),
            if (_isDraggingOrigin)
              Positioned(
                left: rulerSize + 8,
                top:
                    (gs.isMeasuring ? 30 : 4) +
                    (gs.multiSelectMode ? 26 : 0) +
                    (gs.symmetryEnabled ? 26 : 0),
                child: _buildChip(
                  'Origin',
                  Icons.my_location,
                  const Color(0xFFFF7043),
                  () {
                    setState(() {
                      widget.guideSystem.resetRulerOrigin();
                      _isDraggingOrigin = false;
                    });
                    widget.onChanged();
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ─── Mode Chip ────────────────────────────────────────────────────

  Widget _buildChip(
    String label,
    IconData icon,
    Color color,
    VoidCallback onClose,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: widget.isDark ? 0.2 : 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onClose,
            child: Icon(Icons.close, size: 12, color: color),
          ),
        ],
      ),
    );
  }

  // ─── Guide Strips ─────────────────────────────────────────────────

  Widget _buildHStrip(int i, double scale, Offset offset) {
    final sy = widget.guideSystem.horizontalGuides[i] * scale + offset.dy;
    if (sy < rulerSize - _stripW / 2 || sy > 4000) {
      return const SizedBox.shrink();
    }
    final locked = widget.guideSystem.isLocked(true, i);

    return Positioned(
      left: rulerSize,
      top: sy - _stripW / 2,
      right: 0,
      height: _stripW,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: locked ? null : (_) => onGrab(i, true),
        onPanUpdate: locked ? null : onDragUpdate,
        onPanEnd: locked ? null : (_) => onDragEnd(),
        onDoubleTap: () => onDoubleTap(i, true),
        onLongPress: () => onLongPress(i, true),
      ),
    );
  }

  Widget _buildVStrip(int i, double scale, Offset offset) {
    final sx = widget.guideSystem.verticalGuides[i] * scale + offset.dx;
    if (sx < rulerSize - _stripW / 2 || sx > 4000) {
      return const SizedBox.shrink();
    }
    final locked = widget.guideSystem.isLocked(false, i);

    return Positioned(
      left: sx - _stripW / 2,
      top: rulerSize,
      width: _stripW,
      bottom: 0,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: locked ? null : (_) => onGrab(i, false),
        onPanUpdate: locked ? null : onDragUpdate,
        onPanEnd: locked ? null : (_) => onDragEnd(),
        onDoubleTap: () => onDoubleTap(i, false),
        onLongPress: () => onLongPress(i, false),
      ),
    );
  }
}
