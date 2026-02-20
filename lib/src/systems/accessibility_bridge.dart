import 'package:flutter/rendering.dart';

import 'accessibility_tree.dart';
import '../core/engine_event.dart';
import '../core/engine_event_bus.dart';
import '../core/scene_graph/canvas_node.dart';
import '../core/scene_graph/scene_graph.dart';

// ---------------------------------------------------------------------------
// CanvasAccessibilityBridge
// ---------------------------------------------------------------------------

/// Bridges the Dart-side [AccessibilityTreeBuilder] to Flutter's semantics
/// system, making canvas content accessible to VoiceOver (iOS) and
/// TalkBack (Android).
///
/// This is the **missing link**: the engine already has `AccessibilityInfo`
/// on each `CanvasNode` and an `AccessibilityTreeBuilder` that generates
/// a parallel tree — but nothing fed that tree into Flutter's `SemanticsNode`
/// system. This class closes that gap.
///
/// ## Usage
///
/// ```dart
/// final bridge = CanvasAccessibilityBridge(
///   sceneGraph: sceneGraph,
/// );
///
/// // In a CustomPainter:
/// @override
/// SemanticsBuilderCallback? get semanticsBuilder =>
///     bridge.semanticsBuilder;
///
/// // After scene graph changes:
/// bridge.rebuild();
/// ```
class CanvasAccessibilityBridge {
  /// The scene graph to build semantics from.
  final SceneGraph sceneGraph;

  /// Optional event bus for emitting accessibility events.
  final EngineEventBus? _eventBus;

  /// The tree builder used internally.
  final AccessibilityTreeBuilder _builder = AccessibilityTreeBuilder();

  /// Cached semantics list (invalidated by [rebuild]).
  List<CustomPainterSemantics>? _cachedSemantics;

  /// Callback for custom action handling.
  void Function(String nodeId, String actionId)? onCustomAction;

  /// Callback for delivering announcements to screen readers.
  ///
  /// The UI layer should set this to call platform semantics APIs
  /// (e.g., `SemanticsService.sendAnnouncement`) with the correct
  /// `FlutterView`.
  void Function(String message)? onAnnounce;

  /// Currently focused node ID (for keyboard navigation).
  String? _focusedNodeId;

  /// Get the currently focused node ID.
  String? get focusedNodeId => _focusedNodeId;

  /// Whether high-contrast mode is enabled.
  bool _highContrastEnabled = false;

  /// Get high-contrast mode state.
  bool get highContrastEnabled => _highContrastEnabled;

  /// Enable or disable high-contrast mode.
  set highContrastEnabled(bool value) => _highContrastEnabled = value;

  /// Pending announcements for screen readers.
  final List<String> _pendingAnnouncements = [];

  CanvasAccessibilityBridge({
    required this.sceneGraph,
    EngineEventBus? eventBus,
  }) : _eventBus = eventBus;

  // -------------------------------------------------------------------------
  // Semantics builder
  // -------------------------------------------------------------------------

  /// Returns the semantics builder callback for use with [CustomPainter].
  ///
  /// Each call evaluates the current a11y tree and produces a flat
  /// list of [CustomPainterSemantics] for Flutter's rendering pipeline.
  List<CustomPainterSemantics> Function(Size) get semanticsBuilder {
    return _buildSemantics;
  }

  /// Build the semantics list for the given canvas size.
  List<CustomPainterSemantics> _buildSemantics(Size canvasSize) {
    if (_cachedSemantics != null) return _cachedSemantics!;

    final tree = _builder.buildTree(sceneGraph.rootNode);
    if (tree == null) return const [];

    final flat = tree.flatten();
    final result = <CustomPainterSemantics>[];

    for (final node in flat) {
      result.add(_treeNodeToSemantics(node));
    }

    _cachedSemantics = result;
    return result;
  }

  /// Invalidate cached semantics. Call after scene graph mutations.
  ///
  /// Emits [AccessibilityTreeChangedEvent] via the event bus and
  /// flushes any pending announcements.
  void rebuild() {
    _cachedSemantics = null;

    // Emit event.
    final count = accessibleNodeCount;
    _eventBus?.emit(AccessibilityTreeChangedEvent(nodeCount: count));

    // Flush pending announcements.
    for (final message in _pendingAnnouncements) {
      onAnnounce?.call(message);
    }
    _pendingAnnouncements.clear();
  }

  // -------------------------------------------------------------------------
  // Focus management
  // -------------------------------------------------------------------------

  /// Get the ordered list of focusable nodes.
  List<AccessibilityTreeNode> get focusOrder {
    return _builder.getFocusOrder(sceneGraph.rootNode);
  }

  /// Move focus to the next focusable node.
  ///
  /// Returns the newly focused node ID, or null if no focusable nodes.
  String? focusNext() {
    final order = focusOrder;
    if (order.isEmpty) return null;

    if (_focusedNodeId == null) {
      _focusedNodeId = order.first.nodeId;
      return _focusedNodeId;
    }

    final idx = order.indexWhere((n) => n.nodeId == _focusedNodeId);
    final next = (idx + 1) % order.length;
    _focusedNodeId = order[next].nodeId;
    return _focusedNodeId;
  }

  /// Move focus to the previous focusable node.
  String? focusPrevious() {
    final order = focusOrder;
    if (order.isEmpty) return null;

    if (_focusedNodeId == null) {
      _focusedNodeId = order.last.nodeId;
      return _focusedNodeId;
    }

    final idx = order.indexWhere((n) => n.nodeId == _focusedNodeId);
    final prev = (idx - 1 + order.length) % order.length;
    _focusedNodeId = order[prev].nodeId;
    return _focusedNodeId;
  }

  /// Set focus to a specific node.
  void focusNode(String nodeId) {
    _focusedNodeId = nodeId;
  }

  /// Clear focus.
  void clearFocus() {
    _focusedNodeId = null;
  }

  // -------------------------------------------------------------------------
  // Private: mapping AccessibilityTreeNode → CustomPainterSemantics
  // -------------------------------------------------------------------------

  CustomPainterSemantics _treeNodeToSemantics(AccessibilityTreeNode node) {
    final properties = _buildProperties(node);
    return CustomPainterSemantics(
      rect: node.worldBounds,
      properties: properties,
    );
  }

  SemanticsProperties _buildProperties(AccessibilityTreeNode node) {
    final info = node.info;

    return SemanticsProperties(
      label: info.label,
      value: info.value,
      hint: info.hint,
      // Role mapping.
      button: info.role == AccessibilityRole.button,
      link: info.role == AccessibilityRole.link,
      header: info.role == AccessibilityRole.heading,
      image: info.role == AccessibilityRole.image,
      slider: info.role == AccessibilityRole.slider,
      toggled:
          info.role == AccessibilityRole.toggle ? info.value == 'true' : null,
      textField: info.role == AccessibilityRole.input,
      focused: node.nodeId == _focusedNodeId,
      // Custom actions.
      customSemanticsActions: _buildCustomActions(node),
    );
  }

  Map<CustomSemanticsAction, VoidCallback>? _buildCustomActions(
    AccessibilityTreeNode node,
  ) {
    if (node.info.customActions.isEmpty) return null;

    final actions = <CustomSemanticsAction, VoidCallback>{};
    for (final action in node.info.customActions) {
      actions[CustomSemanticsAction(label: action.label)] = () {
        onCustomAction?.call(node.nodeId, action.id);
      };
    }
    return actions;
  }

  // -------------------------------------------------------------------------
  // Debug / inspection
  // -------------------------------------------------------------------------

  /// Generate a debug summary of the current accessibility tree.
  String get debugSummary => _builder.generateSummary(sceneGraph.rootNode);

  /// Number of accessible nodes in the current tree.
  int get accessibleNodeCount {
    final tree = _builder.buildTree(sceneGraph.rootNode);
    return tree?.flatten().length ?? 0;
  }

  // -------------------------------------------------------------------------
  // Announcements
  // -------------------------------------------------------------------------

  /// Queue a live announcement for screen readers.
  ///
  /// Announcements are flushed on the next [rebuild] call, or can be
  /// sent immediately with [announceNow].
  void announce(String message) => _pendingAnnouncements.add(message);

  /// Send an announcement to screen readers immediately.
  void announceNow(String message) {
    onAnnounce?.call(message);
  }

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  /// Dispose the bridge (clears caches and focus state).
  void dispose() {
    _cachedSemantics = null;
    _focusedNodeId = null;
    _pendingAnnouncements.clear();
  }
}
