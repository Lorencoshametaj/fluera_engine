import 'package:flutter/material.dart';
import './tool_interface.dart';
import './tool_context.dart';

/// 🔧 Base implementation for tools with shared logic
///
/// Provides default implementations for:
/// - Operation state management
/// - Pointer position tracking
/// - Lifecycle (activate/deactivate)
///
/// Concrete tools only need to implement their specific logic.
abstract class BaseTool implements DrawingTool {
  // ============================================================================
  // STATE
  // ============================================================================

  @override
  ToolOperationState state = ToolOperationState.idle;

  /// Current pointer position (in CANVAS coordinates)
  Offset? currentCanvasPosition;

  /// Starting position of the operation (in CANVAS coordinates)
  Offset? startCanvasPosition;

  /// Last pointer position (in SCREEN coordinates) for delta calculations
  Offset? lastScreenPosition;

  // ============================================================================
  // DEFAULT IMPLEMENTATIONS
  // ============================================================================

  @override
  bool get hasOverlay => false;

  @override
  bool get supportsUndo => true;

  @override
  bool get requiresExclusiveGesture => true;

  @override
  void onActivate(ToolContext context) {
    state = ToolOperationState.idle;
    _resetPositions();
  }

  @override
  void onDeactivate(ToolContext context) {
    state = ToolOperationState.idle;
    _resetPositions();
  }

  @override
  void onPointerCancel(ToolContext context) {
    state = ToolOperationState.idle;
    _resetPositions();
  }

  @override
  Widget? buildOverlay(ToolContext context) => null;

  @override
  Widget? buildToolOptions(BuildContext context) => null;

  @override
  Map<String, dynamic> saveConfig() => {};

  @override
  void loadConfig(Map<String, dynamic> config) {}

  // ============================================================================
  // HELPER METHODS
  // ============================================================================

  /// Resets all tracked positions
  void _resetPositions() {
    currentCanvasPosition = null;
    startCanvasPosition = null;
    lastScreenPosition = null;
  }

  /// Updates current position from a PointerEvent
  void updatePosition(ToolContext context, Offset screenPosition) {
    lastScreenPosition = screenPosition;
    currentCanvasPosition = context.screenToCanvas(screenPosition);
  }

  /// Calculates delta from last position (in SCREEN coordinates)
  Offset? getDelta(Offset currentScreenPosition) {
    if (lastScreenPosition == null) return null;
    return currentScreenPosition - lastScreenPosition!;
  }

  /// Checks if the pointer has moved significantly
  bool hasMovedSignificantly(Offset currentPosition, {double threshold = 5.0}) {
    if (startCanvasPosition == null) return false;
    return (currentPosition - startCanvasPosition!).distance > threshold;
  }

  /// Helper to begin an operation
  @protected
  void beginOperation(ToolContext context, Offset screenPosition) {
    state = ToolOperationState.started;
    lastScreenPosition = screenPosition;
    startCanvasPosition = context.screenToCanvas(screenPosition);
    currentCanvasPosition = startCanvasPosition;
  }

  /// Helper to continue an operation
  @protected
  void continueOperation(ToolContext context, Offset screenPosition) {
    if (state == ToolOperationState.idle) return;
    state = ToolOperationState.active;
    updatePosition(context, screenPosition);
  }

  /// Helper to complete an operation
  @protected
  void completeOperation(ToolContext context) {
    if (state != ToolOperationState.idle) {
      state = ToolOperationState.completed;
      context.notifyOperationComplete();
    }
    _resetPositions();
    state = ToolOperationState.idle;
  }
}

/// 🖌️ Base for continuous drawing tools (pen, highlighter, etc.)
abstract class ContinuousDrawingTool extends BaseTool {
  /// Points accumulated during drawing (in CANVAS coordinates)
  final List<Offset> accumulatedPoints = [];

  @override
  void onActivate(ToolContext context) {
    super.onActivate(context);
    accumulatedPoints.clear();
  }

  @override
  void onDeactivate(ToolContext context) {
    super.onDeactivate(context);
    accumulatedPoints.clear();
  }

  @override
  void onPointerCancel(ToolContext context) {
    super.onPointerCancel(context);
    accumulatedPoints.clear();
  }

  /// Adds a point to the path
  void addPoint(Offset canvasPoint) {
    accumulatedPoints.add(canvasPoint);
  }

  /// Clears accumulated points
  void clearPoints() {
    accumulatedPoints.clear();
  }
}

/// 🎯 Base for selection tools (lasso, rectangle select, etc.)
abstract class SelectionTool extends BaseTool {
  /// IDs of selected elements
  final Set<String> selectedIds = {};

  /// Calculatated selection bounds
  Rect? selectionBounds;

  /// Checks if there is an active selection
  bool get hasSelection => selectedIds.isNotEmpty;

  /// Clears the selection
  void clearSelection() {
    selectedIds.clear();
    selectionBounds = null;
  }

  /// Checks if a point is inside the selection
  bool isPointInSelection(Offset point) {
    if (selectionBounds == null) return false;
    return selectionBounds!.contains(point);
  }

  /// Adds an element to the selection
  void addToSelection(String id) {
    selectedIds.add(id);
  }

  /// Removes an element from the selection
  void removeFromSelection(String id) {
    selectedIds.remove(id);
  }
}
