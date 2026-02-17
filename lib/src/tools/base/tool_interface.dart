import 'package:flutter/material.dart';
import './tool_context.dart';

/// 🎨 State of a tool operation in progress
enum ToolOperationState {
  /// Tool not active
  idle,

  /// Pointer down - operation started
  started,

  /// Pointer move - operation in progress
  active,

  /// Pointer up - operation completed
  completed,
}

/// 🔧 Base interface for all canvas tools
///
/// Every tool implements this interface and works
/// on both Infinite Canvas and PDF thanks to ToolContext.
///
/// DESIGN PRINCIPLES:
/// - Tools are STATELESS with respect to context (Canvas vs PDF)
/// - All context-specific logic lives in ToolContext/Adapter
/// - A tool written once works everywhere
abstract class DrawingTool {
  // ============================================================================
  // IDENTITY
  // ============================================================================

  /// Unique tool ID (used for selection and serialization)
  String get toolId;

  /// Icon for the toolbar
  IconData get icon;

  /// Localizable label
  String get label;

  /// Description for tooltip
  String get description;

  // ============================================================================
  // STATE
  // ============================================================================

  /// Current operation state
  ToolOperationState get state;

  /// If true, the tool manages its own overlay (e.g., eraser cursor)
  bool get hasOverlay => false;

  /// If true, the tool supports undo/redo
  bool get supportsUndo => true;

  /// If true, the tool requires exclusive gesture (blocks pan/zoom)
  bool get requiresExclusiveGesture => true;

  // ============================================================================
  // LIFECYCLE
  // ============================================================================

  /// Called when the tool is activated
  void onActivate(ToolContext context);

  /// Called when the tool is deactivated
  void onDeactivate(ToolContext context);

  // ============================================================================
  // POINTER EVENTS (Abstract - each tool implements)
  // ============================================================================

  /// Pointer down - start operation
  void onPointerDown(ToolContext context, PointerDownEvent event);

  /// Pointer move - update operation
  void onPointerMove(ToolContext context, PointerMoveEvent event);

  /// Pointer up - complete operation
  void onPointerUp(ToolContext context, PointerUpEvent event);

  /// Pointer cancel - cancel operation (default: treat as up without saving)
  void onPointerCancel(ToolContext context) {
    // Default implementation - subclasses can override
  }

  // ============================================================================
  // UI OVERLAY (Optional)
  // ============================================================================

  /// Overlay widget to render above the canvas
  /// E.g.: eraser cursor, lasso selection, shape preview
  Widget? buildOverlay(ToolContext context) => null;

  /// Extra options widget for the toolbar
  /// E.g.: eraser radius, line type, etc.
  Widget? buildToolOptions(BuildContext context) => null;

  // ============================================================================
  // SERIALIZATION (Optional)
  // ============================================================================

  /// Save tool-specific configuration
  Map<String, dynamic> saveConfig() => {};

  /// Load tool-specific configuration
  void loadConfig(Map<String, dynamic> config) {}
}

/// 🎯 Mixin for tools that manage selections
mixin SelectionToolMixin on DrawingTool {
  /// Currently selected elements (IDs)
  Set<String> get selectedIds;

  /// Current selection bounds
  Rect? get selectionBounds;

  /// Clears the selection
  void clearSelection();

  /// Checks if a point is inside the selection
  bool isPointInSelection(Offset point);
}

/// 🖌️ Mixin for tools that draw continuous strokes
mixin ContinuousDrawingMixin on DrawingTool {
  /// Points accumulated during drawing
  List<Offset> get accumulatedPoints;

  /// Clear accumulated points
  void clearAccumulatedPoints();
}
