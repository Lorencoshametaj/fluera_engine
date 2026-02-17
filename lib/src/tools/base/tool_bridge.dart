import 'package:flutter/material.dart';
import './tool_interface.dart';
import './tool_context.dart';
import './tool_registry.dart';
import '../unified_tools.dart';
import '../../layers/nebula_layer_controller.dart';
// SDK: PDF controller — use abstract adapter
import '../unified_tool_controller.dart';
import '../../layers/adapters/canvas_adapter.dart';
import '../../layers/adapters/infinite_canvas_adapter.dart';
// SDK: PDF adapter — use abstract CanvasAdapter implementation

/// 🌉 TOOL SYSTEM BRIDGE
///
/// Bridge for integrating the new unified tool system with existing views.
/// Enables incremental migration without rewriting everything.
///
/// USAGE:
/// ```dart
/// // In initState
/// _toolBridge = ToolSystemBridge(
///   layerController: _layerController,
///   toolController: _toolController,
///   onOperationComplete: _scheduleAutoSave,
/// );
/// _toolBridge.registerDefaultTools();
///
/// // In gesture detector
/// _toolBridge.handlePointerDown(event, scale, offset, viewportSize);
/// ```
class ToolSystemBridge {
  /// Layer controller for strokes/shapes
  final NebulaLayerController layerController;

  /// Unified tool controller for state
  final UnifiedToolController toolController;

  /// Callback when an operation is completed
  final VoidCallback onOperationComplete;

  /// Callback to save undo state
  final VoidCallback? onSaveUndo;

  /// Tool registry
  final ToolRegistry _registry = ToolRegistry.instance;

  /// Current adapter (Canvas or PDF)
  CanvasAdapter? _currentAdapter;

  /// Current context for tool operations
  ToolContext? _currentContext;

  /// Listener for tool changes
  VoidCallback? _toolChangeListener;

  ToolSystemBridge({
    required this.layerController,
    required this.toolController,
    required this.onOperationComplete,
    this.onSaveUndo,
  }) {
    // Listen to tool controller changes
    _toolChangeListener = _onToolControllerChanged;
    toolController.addListener(_toolChangeListener!);

    // B2: Wire bidirectional sync between controller and registry.
    toolController.attachRegistry(_registry);
  }

  /// Clean up resources
  void dispose() {
    if (_toolChangeListener != null) {
      toolController.removeListener(_toolChangeListener!);
    }
    // B2: Detach registry sync.
    toolController.detachRegistry();
  }

  // ============================================================================
  // TOOL REGISTRATION
  // ============================================================================

  /// Register the default tools
  void registerDefaultTools() {
    _registry.registerAll([
      UnifiedEraserTool(),
      UnifiedLassoTool(),
      UnifiedDigitalTextTool(),
      UnifiedImageTool(),
      UnifiedShapeTool(),
    ]);
  }

  /// Register a custom tool
  void registerTool(DrawingTool tool) {
    _registry.register(tool);
  }

  // ============================================================================
  // CONTEXT MANAGEMENT
  // ============================================================================

  /// Create adapter for infinite canvas
  void setCanvasContext({
    required String canvasId,
    required double scale,
    required Offset viewOffset,
    required Size viewportSize,
  }) {
    _currentAdapter = InfiniteCanvasAdapter(
      canvasId: canvasId,
      onOperationComplete: onOperationComplete,
      onSaveUndo: onSaveUndo,
    );

    _updateContext(scale, viewOffset, viewportSize);
  }

  /// Set adapter for a PDF page context.
  ///
  /// The app provides a concrete [CanvasAdapter] implementation for PDF pages.
  /// The SDK does not depend on any PDF-specific types.
  void setPDFContext({
    required CanvasAdapter pdfAdapter,
    required double scale,
    required Offset viewOffset,
    required Size viewportSize,
  }) {
    _currentAdapter = pdfAdapter;

    _updateContext(scale, viewOffset, viewportSize);
  }

  /// Update context with new viewport parameters
  void updateViewport({
    required double scale,
    required Offset viewOffset,
    required Size viewportSize,
  }) {
    _updateContext(scale, viewOffset, viewportSize);
  }

  void _updateContext(double scale, Offset viewOffset, Size viewportSize) {
    if (_currentAdapter == null) return;

    _currentContext = ToolContext(
      adapter: _currentAdapter!,
      layerController: layerController,
      scale: scale,
      viewOffset: viewOffset,
      viewportSize: viewportSize,
      settings: toolController.toolSettings,
    );
  }

  // ============================================================================
  // TOOL SELECTION
  // ============================================================================

  /// Select a tool by ID
  void selectTool(String? toolId) {
    if (_currentContext == null) {
      return;
    }
    _registry.selectTool(toolId, _currentContext!);
    toolController.selectTool(toolId);
  }

  /// Current active tool
  DrawingTool? get activeTool => _registry.activeTool;

  /// ID of the active tool
  String? get activeToolId => _registry.activeToolId;

  /// Check if a specific tool is active
  bool isToolActive(String toolId) => _registry.activeToolId == toolId;

  // ============================================================================
  // POINTER EVENT DISPATCH
  // ============================================================================

  /// Handle pointer down
  ///
  /// Returns true if the event was handled by a tool.
  bool handlePointerDown(
    PointerDownEvent event, {
    double scale = 1.0,
    Offset viewOffset = Offset.zero,
    Size viewportSize = Size.zero,
  }) {
    _ensureContext(scale, viewOffset, viewportSize);

    if (_currentContext != null && _registry.activeTool != null) {
      _registry.dispatchPointerDown(_currentContext!, event);
      return true;
    }
    return false;
  }

  /// Handle pointer move
  bool handlePointerMove(
    PointerMoveEvent event, {
    double scale = 1.0,
    Offset viewOffset = Offset.zero,
    Size viewportSize = Size.zero,
  }) {
    _ensureContext(scale, viewOffset, viewportSize);

    if (_currentContext != null && _registry.activeTool != null) {
      _registry.dispatchPointerMove(_currentContext!, event);
      return true;
    }
    return false;
  }

  /// Handle pointer up
  bool handlePointerUp(
    PointerUpEvent event, {
    double scale = 1.0,
    Offset viewOffset = Offset.zero,
    Size viewportSize = Size.zero,
  }) {
    _ensureContext(scale, viewOffset, viewportSize);

    if (_currentContext != null && _registry.activeTool != null) {
      _registry.dispatchPointerUp(_currentContext!, event);
      return true;
    }
    return false;
  }

  /// Handle pointer cancel
  bool handlePointerCancel() {
    if (_currentContext != null) {
      return _registry.dispatchPointerCancel(_currentContext!);
    }
    return false;
  }

  void _ensureContext(double scale, Offset viewOffset, Size viewportSize) {
    if (_currentAdapter != null) {
      _updateContext(scale, viewOffset, viewportSize);
    }
  }

  // ============================================================================
  // OVERLAY
  // ============================================================================

  /// Build the active tool's overlay
  Widget? buildToolOverlay() {
    if (_currentContext == null) return null;
    return _registry.buildActiveToolOverlay(_currentContext!);
  }

  // ============================================================================
  // TOOL-SPECIFIC OPERATIONS
  // ============================================================================

  /// Get eraser tool for configuration
  UnifiedEraserTool? get eraserTool =>
      _registry.getToolAs<UnifiedEraserTool>('eraser');

  /// Get lasso tool for operations
  UnifiedLassoTool? get lassoTool =>
      _registry.getToolAs<UnifiedLassoTool>('lasso');

  /// Configure eraser radius
  void setEraserRadius(double radius) {
    eraserTool?.radius = radius;
    toolController.setEraserRadius(radius);
  }

  /// Configure eraser mode
  void setEraseWholeStroke(bool value) {
    eraserTool?.eraseWholeStroke = value;
    toolController.setEraseWholeStroke(value);
  }

  /// Erase at specified point using the unified eraser
  void eraseAt(Offset canvasPosition) {
    if (_currentContext != null && eraserTool != null) {
      selectTool('eraser');
      eraserTool!.eraseAtPosition(_currentContext!, canvasPosition);
    }
  }

  /// Delete elements selected by lasso
  void deleteSelectedElements() {
    if (_currentContext != null && lassoTool != null) {
      lassoTool!.deleteSelected(_currentContext!);
    }
  }

  /// Clear lasso selection
  void clearLassoSelection() {
    lassoTool?.clearSelection();
  }

  /// Check if there are selected elements
  bool get hasSelection => lassoTool?.hasSelection ?? false;

  // ============================================================================
  // PRIVATE
  // ============================================================================

  void _onToolControllerChanged() {
    // B2: Sync tool selection from controller → registry.
    // The controller's internal _isSyncing guard prevents feedback loops
    // when the registry triggers _onRegistryChanged back on the controller.
    final toolId = toolController.activeToolId;
    if (_currentContext != null && _registry.activeToolId != toolId) {
      _registry.selectTool(toolId, _currentContext!);
    }

    // Keep the controller's context up-to-date.
    if (_currentContext != null) {
      toolController.attachContext(_currentContext!);
    }
  }
}

/// 🎛️ WIDGET WRAPPER for tool overlays
///
/// Wraps a child widget with the active tool's overlay.
class ToolOverlayWrapper extends StatelessWidget {
  final ToolSystemBridge bridge;
  final Widget child;

  const ToolOverlayWrapper({
    super.key,
    required this.bridge,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        // Tool overlay
        if (bridge.buildToolOverlay() != null) bridge.buildToolOverlay()!,
      ],
    );
  }
}
