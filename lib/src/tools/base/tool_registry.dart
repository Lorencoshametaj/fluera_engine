import 'package:flutter/material.dart';
import './tool_interface.dart';
import './tool_context.dart';
import '../../core/engine_scope.dart';

/// 🗂️ Singleton registry for all tools
///
/// Manages tool registration, selection, and lifecycle.
///
/// USAGE:
/// ```dart
/// // Register tools at startup
/// ToolRegistry.instance.registerAll([
///   EraserTool(),
///   LassoTool(),
///   TextTool(),
///   ...
/// ]);
///
/// // Select tool
/// ToolRegistry.instance.selectTool('eraser', context);
///
/// // Use active tool
/// ToolRegistry.instance.activeTool?.onPointerDown(context, event);
/// ```
class ToolRegistry extends ChangeNotifier {
  // ============================================================================
  // SINGLETON
  // ============================================================================
  /// Legacy singleton accessor — delegates to [EngineScope.current].
  static ToolRegistry get instance => EngineScope.current.toolRegistry;

  /// Creates a new instance (used by [EngineScope]).
  ToolRegistry.create();

  // ============================================================================
  // STATE
  // ============================================================================

  final Map<String, DrawingTool> _tools = {};
  String? _activeToolId;

  /// Current active tool
  DrawingTool? get activeTool =>
      _activeToolId != null ? _tools[_activeToolId] : null;

  /// Active tool ID
  String? get activeToolId => _activeToolId;

  /// List of all registered tools
  List<DrawingTool> get allTools => _tools.values.toList();

  /// Check if a tool is registered
  bool isRegistered(String toolId) => _tools.containsKey(toolId);

  /// Number of registered tools
  int get toolCount => _tools.length;

  // ============================================================================
  // REGISTRATION
  // ============================================================================

  /// Register a single tool
  ///
  /// If a tool with the same ID already exists, it is overwritten.
  void register(DrawingTool tool) {
    _tools[tool.toolId] = tool;
  }

  /// Register multiple tools
  void registerAll(List<DrawingTool> tools) {
    for (final tool in tools) {
      register(tool);
    }
  }

  /// Remove a tool from the registry
  void unregister(String toolId) {
    if (_activeToolId == toolId) {
      _activeToolId = null;
    }
    _tools.remove(toolId);
    notifyListeners();
  }

  /// Get tool by ID
  DrawingTool? getTool(String toolId) => _tools[toolId];

  /// Get tool by ID with cast to specific type
  T? getToolAs<T extends DrawingTool>(String toolId) {
    final tool = _tools[toolId];
    return tool is T ? tool : null;
  }

  // ============================================================================
  // SELECTION
  // ============================================================================

  /// Select active tool
  ///
  /// Calls onDeactivate on the previous tool and onActivate on the new one.
  void selectTool(String? toolId, ToolContext context) {
    // Deactivate current tool
    if (_activeToolId != null && _tools.containsKey(_activeToolId)) {
      _tools[_activeToolId]!.onDeactivate(context);
    }

    _activeToolId = toolId;

    // Activate new tool
    if (toolId != null && _tools.containsKey(toolId)) {
      _tools[toolId]!.onActivate(context);
    }

    notifyListeners();
  }

  /// Deselect current tool (return to drawing mode)
  void deselectCurrentTool(ToolContext context) {
    selectTool(null, context);
  }

  /// Toggle tool (select if not active, deselect if active)
  void toggleTool(String toolId, ToolContext context) {
    if (_activeToolId == toolId) {
      deselectCurrentTool(context);
    } else {
      selectTool(toolId, context);
    }
  }

  // ============================================================================
  // POINTER EVENTS DISPATCH
  // ============================================================================

  /// Dispatch pointer down to the active tool
  ///
  /// Returns true if the event was handled.
  bool dispatchPointerDown(ToolContext context, PointerDownEvent event) {
    final tool = activeTool;
    if (tool != null) {
      tool.onPointerDown(context, event);
      return true;
    }
    return false;
  }

  /// Dispatch pointer move to the active tool
  bool dispatchPointerMove(ToolContext context, PointerMoveEvent event) {
    final tool = activeTool;
    if (tool != null) {
      tool.onPointerMove(context, event);
      return true;
    }
    return false;
  }

  /// Dispatch pointer up to the active tool
  bool dispatchPointerUp(ToolContext context, PointerUpEvent event) {
    final tool = activeTool;
    if (tool != null) {
      tool.onPointerUp(context, event);
      return true;
    }
    return false;
  }

  /// Dispatch pointer cancel to the active tool
  bool dispatchPointerCancel(ToolContext context) {
    final tool = activeTool;
    if (tool != null) {
      tool.onPointerCancel(context);
      return true;
    }
    return false;
  }

  // ============================================================================
  // OVERLAY
  // ============================================================================

  /// Build the active tool's overlay (if present)
  Widget? buildActiveToolOverlay(ToolContext context) {
    final tool = activeTool;
    if (tool != null && tool.hasOverlay) {
      return tool.buildOverlay(context);
    }
    return null;
  }

  // ============================================================================
  // UTILITY
  // ============================================================================

  /// Clear registry
  void clear() {
    _tools.clear();
    _activeToolId = null;
    notifyListeners();
  }

  /// Reset to initial state (keep tools but deselect)
  void reset(ToolContext context) {
    if (_activeToolId != null && _tools.containsKey(_activeToolId)) {
      _tools[_activeToolId]!.onDeactivate(context);
    }
    _activeToolId = null;
    notifyListeners();
  }

  /// Get debug info
  String get debugInfo {
    return 'ToolRegistry: ${_tools.length} tools, active=$_activeToolId\n'
        'Tools: ${_tools.keys.join(", ")}';
  }
}
