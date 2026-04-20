import 'dart:ui';
import 'package:flutter/foundation.dart' show debugPrint;
import '../core/scene_graph/canvas_node.dart';
import '../core/scene_graph/node_id.dart';
import '../core/nodes/text_node.dart';
import '../core/nodes/group_node.dart';
import '../core/models/digital_text_element.dart';
import '../systems/selection_manager.dart';
import '../utils/uid.dart';
import 'atlas_action.dart';

/// Executes [AtlasAction]s on the scene graph.
///
/// This is Atlas's "hands" — it translates the AI's JSON commands
/// into concrete canvas mutations (creating nodes, drawing connections,
/// grouping, aligning, etc.).
///
/// Each action is designed to be wrapped in an undo/redo [Command]
/// by the caller for full history support.
class AtlasActionExecutor {
  /// The scene root node where new nodes are added.
  final GroupNode sceneRoot;

  /// Selection manager for group/align operations.
  final SelectionManager selectionManager;

  /// Callback to resolve a node by ID from the scene graph.
  final CanvasNode? Function(String id) nodeResolver;

  /// Callback fired when new nodes are created (for animation triggers).
  final void Function(CanvasNode node)? onNodeCreated;

  /// Callback fired when a connection is created between two nodes.
  final void Function(String fromId, String toId, String? label)? onConnectionCreated;

  const AtlasActionExecutor({
    required this.sceneRoot,
    required this.selectionManager,
    required this.nodeResolver,
    this.onNodeCreated,
    this.onConnectionCreated,
  });

  /// Execute a list of actions in order.
  ///
  /// Returns the list of created/modified nodes (for undo batching).
  List<CanvasNode> executeAll(List<AtlasAction> actions) {
    final createdNodes = <CanvasNode>[];

    for (final action in actions) {
      switch (action) {
        case CreateNodeAction():
          final node = _executeCreateNode(action);
          if (node != null) createdNodes.add(node);

        case ConnectNodesAction():
          _executeConnect(action);

        case GroupNodesAction():
          _executeGroup(action);

        case SummarizeAction():
          final node = _executeSummarize(action);
          if (node != null) createdNodes.add(node);

        case AlignNodesAction():
          _executeAlign(action);

        case MoveNodeAction():
          _executeMove(action);

        case UnknownAction():
          debugPrint('⚠️ Atlas: azione sconosciuta ignorata: ${action.type}');
      }
    }

    return createdNodes;
  }

  // ---------------------------------------------------------------------------
  // Action implementations
  // ---------------------------------------------------------------------------

  TextNode? _executeCreateNode(CreateNodeAction action) {
    final id = generateUid();
    final textElement = DigitalTextElement(
      id: 'atlas_text_$id',
      text: action.content,
      position: Offset(action.x, action.y),
      fontSize: 18.0,
      color: _parseNeonColor(action.color),
      createdAt: DateTime.now(),
    );

    final node = TextNode(
      id: NodeId(id),
      textElement: textElement,
      name: action.label ?? 'Atlas: ${action.content.length > 20 ? action.content.substring(0, 20) : action.content}',
    );

    // Set the position via localTransform
    node.setPosition(action.x, action.y);

    sceneRoot.add(node);
    onNodeCreated?.call(node);

    debugPrint('✨ Atlas ha creato un nodo: "${action.content.length > 30 ? '${action.content.substring(0, 30)}...' : action.content}"');
    return node;
  }

  void _executeConnect(ConnectNodesAction action) {
    // Verify both nodes exist
    final fromNode = nodeResolver(action.fromId);
    final toNode = nodeResolver(action.toId);

    if (fromNode == null || toNode == null) {
      debugPrint('⚠️ Atlas: impossibile connettere ${action.fromId} → ${action.toId} (nodo non trovato)');
      return;
    }

    onConnectionCreated?.call(action.fromId, action.toId, action.label);
    debugPrint('🔗 Atlas ha connesso: ${action.fromId} → ${action.toId}');
  }

  void _executeGroup(GroupNodesAction action) {
    final nodes = <CanvasNode>[];
    for (final id in action.nodeIds) {
      final node = nodeResolver(id);
      if (node != null) nodes.add(node);
    }

    if (nodes.length >= 2) {
      selectionManager.selectAll(nodes);
      debugPrint('📦 Atlas ha raggruppato ${nodes.length} nodi');
    }
  }

  TextNode? _executeSummarize(SummarizeAction action) {
    // Determine position: near the target node or at specified coordinates
    double x = action.x ?? 0;
    double y = action.y ?? 0;

    if (action.targetNodeId != null) {
      final targetNode = nodeResolver(action.targetNodeId!);
      if (targetNode != null) {
        final bounds = targetNode.worldBounds;
        x = action.x ?? bounds.center.dx;
        y = action.y ?? (bounds.top - 80); // Place summary above the target
      }
    }

    // Create summary as a CreateNodeAction
    return _executeCreateNode(CreateNodeAction(
      x: x,
      y: y,
      content: action.summary,
      nodeType: 'text',
      color: 'neon_cyan',
      label: '📋 Riassunto di Atlas',
    ));
  }

  void _executeAlign(AlignNodesAction action) {
    final nodes = <CanvasNode>[];
    for (final id in action.nodeIds) {
      final node = nodeResolver(id);
      if (node != null) nodes.add(node);
    }

    if (nodes.length < 2) return;

    selectionManager.selectAll(nodes);

    switch (action.alignment) {
      case 'left':
        selectionManager.alignLeft();
      case 'right':
        selectionManager.alignRight();
      case 'top':
        selectionManager.alignTop();
      case 'bottom':
        selectionManager.alignBottom();
      case 'center_h':
        selectionManager.alignCenterH();
      case 'center_v':
        selectionManager.alignCenterV();
      case 'distribute_h':
        selectionManager.distributeHorizontally();
      case 'distribute_v':
        selectionManager.distributeVertically();
    }

    debugPrint('📐 Atlas ha allineato ${nodes.length} nodi (${ action.alignment })');
  }

  void _executeMove(MoveNodeAction action) {
    final node = nodeResolver(action.nodeId);
    if (node == null) {
      debugPrint('⚠️ Atlas: nodo ${action.nodeId} non trovato per lo spostamento');
      return;
    }

    node.setPosition(action.x, action.y);
    node.invalidateTransformCache();
    debugPrint('🚀 Atlas ha spostato il nodo ${action.nodeId} a (${action.x}, ${action.y})');
  }

  // ---------------------------------------------------------------------------
  // Color parsing
  // ---------------------------------------------------------------------------

  Color _parseNeonColor(String? colorName) {
    switch (colorName) {
      case 'neon_blue':
        return const Color(0xFF448AFF);
      case 'neon_cyan':
        return const Color(0xFF00E5FF);
      case 'neon_green':
        return const Color(0xFF69F0AE);
      case 'neon_orange':
        return const Color(0xFFFF9100);
      case 'neon_purple':
        return const Color(0xFFEA80FC);
      case 'neon_red':
        return const Color(0xFFFF5252);
      case 'neon_yellow':
        return const Color(0xFFFFFF00);
      default:
        return const Color(0xFF00E5FF); // Default neon cyan — Atlas's signature color
    }
  }
}
