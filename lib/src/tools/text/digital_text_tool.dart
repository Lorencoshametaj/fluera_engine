import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/models/digital_text_element.dart';
import '../base/tool_interface.dart';
import '../base/tool_context.dart';

/// 🔧 Digital Text Tool
///
/// Handles interaction with digital text elements on the canvas:
/// - Selection on tap
/// - Dragging (with auto-scroll at edges)
/// - Resizing via corner handles
/// - Deselection on tap in empty area
///
/// Implements [DrawingTool] for integration with the unified tool system
/// while preserving the existing API used by canvas part files.
class DigitalTextTool implements DrawingTool {
  // ============================================================================
  // DRAWING TOOL IDENTITY
  // ============================================================================

  @override
  String get toolId => 'digital_text';

  @override
  IconData get icon => Icons.text_fields;

  @override
  String get label => 'Text';

  @override
  String get description => 'Add and edit digital text elements';

  // ============================================================================
  // DRAWING TOOL STATE
  // ============================================================================

  @override
  ToolOperationState get state {
    if (isResizing || isDragging) return ToolOperationState.active;
    if (hasSelection) return ToolOperationState.started;
    return ToolOperationState.idle;
  }

  @override
  bool get hasOverlay => true;

  @override
  bool get supportsUndo => true;

  @override
  bool get requiresExclusiveGesture => false;

  // ============================================================================
  // DRAWING TOOL LIFECYCLE
  // ============================================================================

  @override
  void onActivate(ToolContext context) {
    // Text tool activation — no special setup needed
  }

  @override
  void onDeactivate(ToolContext context) {
    // Clear selection when switching away from text tool
    deselectElement();
  }

  // ============================================================================
  // DRAWING TOOL POINTER EVENTS
  // ============================================================================
  // These handlers are invoked when DigitalTextTool is the ACTIVE tool in the
  // ToolRegistry. They use ToolContext for text element access and updates.
  //
  // NOTE: Text elements are also interactive when OTHER tools are active
  // (always-on hit-testing). That path still flows through the canvas part
  // files' direct API (hitTest, startDrag, etc.) for backward compatibility.

  @override
  void onPointerDown(ToolContext context, PointerDownEvent event) {
    final canvasPosition = context.screenToCanvas(event.localPosition);
    final elements = context.getTextElements();

    // 1. Check resize handles first (if there's a selection)
    if (hasSelection) {
      final handleIndex = hitTestResizeHandles(
        canvasPosition,
        _selectedElement!,
      );
      if (handleIndex != null) {
        startResize(handleIndex, canvasPosition);
        return;
      }
    }

    // 2. Hit-test text elements
    final hitElement = hitTest(canvasPosition, elements);
    if (hitElement != null) {
      selectElement(hitElement);
      startDrag(canvasPosition);
      return;
    }

    // 3. Tapped on empty area — deselect
    if (hasSelection) {
      deselectElement();
    }
  }

  @override
  void onPointerMove(ToolContext context, PointerMoveEvent event) {
    final canvasPosition = context.screenToCanvas(event.localPosition);

    // Handle resize
    if (isResizing) {
      final updated = updateResize(canvasPosition);
      if (updated != null) {
        context.updateTextElement(updated);
      }
      return;
    }

    // Handle drag
    if (isDragging) {
      final updated = updateDrag(canvasPosition);
      if (updated != null) {
        context.updateTextElement(updated);
      }
      return;
    }
  }

  @override
  void onPointerUp(ToolContext context, PointerUpEvent event) {
    if (isResizing) {
      endResize();
      if (_selectedElement != null) {
        context.updateTextElement(_selectedElement!);
      }
      context.notifyOperationComplete();
      return;
    }

    if (isDragging) {
      endDrag();
      if (_selectedElement != null) {
        context.updateTextElement(_selectedElement!);
      }
      context.notifyOperationComplete();
      return;
    }
  }

  @override
  void onPointerCancel(ToolContext context) {
    // Cancel any in-progress drag or resize
    if (isDragging) endDrag();
    if (isResizing) endResize();
  }

  // ============================================================================
  // DRAWING TOOL UI
  // ============================================================================

  @override
  Widget? buildOverlay(ToolContext context) => null;

  @override
  Widget? buildToolOptions(BuildContext context) => null;

  // ============================================================================
  // DRAWING TOOL SERIALIZATION
  // ============================================================================

  @override
  Map<String, dynamic> saveConfig() => {};

  @override
  void loadConfig(Map<String, dynamic> config) {}

  // ============================================================================
  // TEXT TOOL STATE (existing API — preserved for backward compatibility)
  // ============================================================================

  /// Currently selected element
  DigitalTextElement? _selectedElement;

  /// 🔀 Multi-select: set of selected element IDs
  final Set<String> _selectedElementIds = {};

  /// Drag start position (for calculating delta)
  Offset? _dragStartCanvasPosition;

  /// Resize handle being dragged (null = none, 0-3 = corner index)
  int? _resizeHandleIndex;

  /// Previous position during resize (for incremental delta)
  Offset? _previousResizePosition;

  /// Getter for selected element
  DigitalTextElement? get selectedElement => _selectedElement;

  /// Whether an element is currently selected
  bool get hasSelection => _selectedElement != null;

  /// 🔀 Whether multiple elements are selected
  bool get hasMultiSelection => _selectedElementIds.length > 1;

  /// 🔀 Get all selected element IDs
  Set<String> get selectedElementIds => Set.unmodifiable(_selectedElementIds);

  /// 🔀 Get selected elements from list
  List<DigitalTextElement> selectedElements(
    List<DigitalTextElement> allElements,
  ) {
    return allElements
        .where((e) => _selectedElementIds.contains(e.id))
        .toList();
  }

  /// Full reset of tool state
  void reset() {
    _selectedElement = null;
    _selectedElementIds.clear();
    _dragStartCanvasPosition = null;
    _resizeHandleIndex = null;
    _previousResizePosition = null;
  }

  /// Select an element
  void selectElement(DigitalTextElement element) {
    _selectedElement = element;
    _selectedElementIds
      ..clear()
      ..add(element.id);
  }

  /// 🔀 Toggle element in multi-selection (shift-tap)
  void toggleMultiSelect(DigitalTextElement element) {
    if (_selectedElementIds.contains(element.id)) {
      _selectedElementIds.remove(element.id);
      // If removed the primary, pick another or clear
      if (_selectedElement?.id == element.id) {
        _selectedElement = null;
      }
    } else {
      _selectedElementIds.add(element.id);
      _selectedElement ??= element;
    }
  }

  /// 🔀 Move all multi-selected elements by delta
  List<DigitalTextElement> moveMultiSelection(
    List<DigitalTextElement> allElements,
    Offset delta,
  ) {
    final updated = <DigitalTextElement>[];
    for (int i = 0; i < allElements.length; i++) {
      if (_selectedElementIds.contains(allElements[i].id)) {
        allElements[i] = allElements[i].copyWith(
          position: allElements[i].position + delta,
          modifiedAt: DateTime.now(),
        );
        updated.add(allElements[i]);
      }
    }
    return updated;
  }

  /// Deselect current element
  void deselectElement() {
    _selectedElement = null;
    _selectedElementIds.clear();
    _dragStartCanvasPosition = null;
    _resizeHandleIndex = null;
    _previousResizePosition = null;
  }

  /// 🔍 Search text elements by query (case-insensitive)
  List<DigitalTextElement> searchText(
    List<DigitalTextElement> elements,
    String query,
  ) {
    if (query.isEmpty) return [];
    final lower = query.toLowerCase();
    return elements.where((e) => e.text.toLowerCase().contains(lower)).toList();
  }

  // ============================================================================
  // HIT TESTING
  // ============================================================================

  /// Hit test: find element touched at a canvas point
  DigitalTextElement? hitTest(
    Offset canvasPosition,
    List<DigitalTextElement> elements,
  ) {
    // Check from last to first (topmost elements have priority)
    for (int i = elements.length - 1; i >= 0; i--) {
      if (elements[i].containsPoint(canvasPosition)) {
        return elements[i];
      }
    }
    return null;
  }

  /// Hit test on resize handles (returns handle index or null).
  /// Rotation-aware: un-rotates the test point before checking.
  int? hitTestResizeHandles(Offset canvasPosition, DigitalTextElement element) {
    final bounds = element.getBounds();
    final handles = _getResizeHandles(bounds);

    // Un-rotate test point for rotated elements
    Offset testPoint = canvasPosition;
    if (element.rotation != 0.0) {
      final cosR = math.cos(-element.rotation);
      final sinR = math.sin(-element.rotation);
      final dx = canvasPosition.dx - element.position.dx;
      final dy = canvasPosition.dy - element.position.dy;
      testPoint = Offset(
        element.position.dx + dx * cosR - dy * sinR,
        element.position.dy + dx * sinR + dy * cosR,
      );
    }

    for (int i = 0; i < handles.length; i++) {
      final handleRect = Rect.fromCenter(
        center: handles[i],
        width: 40,
        height: 40,
      );
      if (handleRect.contains(testPoint)) {
        return i;
      }
    }
    return null;
  }

  /// Gets positions of the 4 resize corner handles
  List<Offset> _getResizeHandles(Rect bounds) {
    return [
      bounds.topLeft, // 0: top-left
      bounds.topRight, // 1: top-right
      bounds.bottomLeft, // 2: bottom-left
      bounds.bottomRight, // 3: bottom-right
    ];
  }

  /// Gets resize handles for element (public method)
  List<Offset> getResizeHandles(DigitalTextElement element) {
    final bounds = element.getBounds();
    return _getResizeHandles(bounds);
  }

  // ============================================================================
  // DRAG
  // ============================================================================

  /// Start drag of selected element
  void startDrag(Offset canvasPosition) {
    if (_selectedElement == null) return;
    _dragStartCanvasPosition = canvasPosition;
  }

  /// Whether snap-to-grid is enabled during drag.
  bool snapToGrid = false;

  /// Grid size for snap (canvas units).
  double gridSize = 10.0;

  /// Update drag position
  DigitalTextElement? updateDrag(Offset canvasPosition) {
    if (_selectedElement == null || _dragStartCanvasPosition == null) {
      return null;
    }

    // Calculate delta from the previous point (not the initial point!)
    final delta = canvasPosition - _dragStartCanvasPosition!;

    var newPosition = _selectedElement!.position + delta;

    // 🧲 Snap-to-grid: snap position to nearest grid point
    if (snapToGrid && gridSize > 0) {
      newPosition = Offset(
        (newPosition.dx / gridSize).round() * gridSize,
        (newPosition.dy / gridSize).round() * gridSize,
      );
    }

    _selectedElement = _selectedElement!.copyWith(
      position: newPosition,
      modifiedAt: DateTime.now(),
    );

    // Update drag start for next frame
    _dragStartCanvasPosition = canvasPosition;

    return _selectedElement;
  }

  /// End drag
  void endDrag() {
    _dragStartCanvasPosition = null;
  }

  /// Compensate canvas scroll during drag (for smooth auto-scroll)
  void compensateScroll(Offset scrollDelta) {
    if (_selectedElement == null) return;

    _selectedElement = _selectedElement!.copyWith(
      position: _selectedElement!.position + scrollDelta,
      modifiedAt: DateTime.now(),
    );

    // Compensate reference points to maintain correct delta
    if (isDragging && _dragStartCanvasPosition != null) {
      _dragStartCanvasPosition = _dragStartCanvasPosition! + scrollDelta;
    }

    if (isResizing && _previousResizePosition != null) {
      _previousResizePosition = _previousResizePosition! + scrollDelta;
    }
  }

  // ============================================================================
  // RESIZE
  // ============================================================================

  /// Start resize from a specific handle
  void startResize(int handleIndex, Offset canvasPosition) {
    if (_selectedElement == null) return;
    _resizeHandleIndex = handleIndex;
    _dragStartCanvasPosition = canvasPosition;
    _previousResizePosition = canvasPosition;
  }

  /// Update resize
  DigitalTextElement? updateResize(Offset canvasPosition) {
    if (_selectedElement == null ||
        _resizeHandleIndex == null ||
        _previousResizePosition == null) {
      return null;
    }

    // Calculate delta from the previous position (not the initial!)
    final delta = canvasPosition - _previousResizePosition!;

    // 📦 Auto-fit textbox: adjust maxWidth with horizontal drag
    if (_selectedElement!.maxWidth != null) {
      // Right handles (1, 3) → increase width with positive dx
      // Left handles (0, 2) → increase width with negative dx
      final isRightHandle = _resizeHandleIndex == 1 || _resizeHandleIndex == 3;
      final widthDelta = isRightHandle ? delta.dx : -delta.dx;
      final newWidth = (_selectedElement!.maxWidth! + widthDelta).clamp(
        40.0,
        2000.0,
      );

      _selectedElement = _selectedElement!.copyWith(
        maxWidth: newWidth,
        modifiedAt: DateTime.now(),
      );
    } else {
      // Legacy scale-based resize
      final scaleDelta = (delta.dx.abs() + delta.dy.abs()) / 200.0;
      final isZoomIn =
          (_resizeHandleIndex == 3 && delta.dx > 0 && delta.dy > 0) ||
          (_resizeHandleIndex == 1 && delta.dx > 0 && delta.dy < 0) ||
          (_resizeHandleIndex == 2 && delta.dx < 0 && delta.dy > 0) ||
          (_resizeHandleIndex == 0 && delta.dx < 0 && delta.dy < 0);

      double newScale =
          _selectedElement!.scale + (isZoomIn ? scaleDelta : -scaleDelta);
      newScale = newScale.clamp(0.3, 3.0);

      _selectedElement = _selectedElement!.copyWith(
        scale: newScale,
        modifiedAt: DateTime.now(),
      );
    }

    // Update previous position for next frame
    _previousResizePosition = canvasPosition;

    return _selectedElement;
  }

  /// End resize
  void endResize() {
    _resizeHandleIndex = null;
    _dragStartCanvasPosition = null;
    _previousResizePosition = null;
  }

  /// Whether currently resizing
  bool get isResizing => _resizeHandleIndex != null;

  /// Whether currently dragging
  bool get isDragging => _dragStartCanvasPosition != null && !isResizing;

  // ============================================================================
  // PAINTING (Selection feedback)
  // ============================================================================

  /// Draws selection box and handles (currently disabled)
  void paintSelection(
    Canvas canvas,
    DigitalTextElement element,
    BuildContext context,
  ) {
    // Selection painting is handled by the overlay widgets
    return;
  }

  // ============================================================================
  // AUTO-SCROLL
  // ============================================================================

  /// Calculates auto-scroll delta when drag is near screen edges
  Offset? calculateAutoScrollDelta(
    Offset screenPosition,
    Size screenSize, {
    double edgeThreshold = 50.0,
    double scrollSpeed = 5.0,
  }) {
    double dx = 0.0;
    double dy = 0.0;

    // Left edge
    if (screenPosition.dx < edgeThreshold) {
      dx = -scrollSpeed * (1 - screenPosition.dx / edgeThreshold);
    }
    // Right edge
    else if (screenPosition.dx > screenSize.width - edgeThreshold) {
      dx =
          scrollSpeed *
          (1 - (screenSize.width - screenPosition.dx) / edgeThreshold);
    }

    // Top edge
    if (screenPosition.dy < edgeThreshold) {
      dy = -scrollSpeed * (1 - screenPosition.dy / edgeThreshold);
    }
    // Bottom edge
    else if (screenPosition.dy > screenSize.height - edgeThreshold) {
      dy =
          scrollSpeed *
          (1 - (screenSize.height - screenPosition.dy) / edgeThreshold);
    }

    if (dx != 0.0 || dy != 0.0) {
      return Offset(dx, dy);
    }
    return null;
  }
}
