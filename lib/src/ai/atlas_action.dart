/// Sealed hierarchy of actions that Atlas can request on the canvas.
///
/// Each action maps to a specific mutation of the scene graph.
/// The [AtlasActionExecutor] interprets these and applies them
/// with Minority Report visual effects and undo/redo support.
sealed class AtlasAction {
  const AtlasAction();

  /// Parse a single action from a JSON map (from AI response).
  factory AtlasAction.fromJson(Map<String, dynamic> json) {
    final type = json['tipo'] as String? ?? json['type'] as String? ?? '';
    switch (type) {
      case 'crea_nodo':
      case 'create_node':
        return CreateNodeAction(
          x: (json['x'] as num?)?.toDouble() ?? 0,
          y: (json['y'] as num?)?.toDouble() ?? 0,
          content: json['contenuto'] as String? ?? json['content'] as String? ?? '',
          nodeType: json['tipo_nodo'] as String? ?? json['node_type'] as String? ?? 'text',
          color: json['colore'] as String? ?? json['color'] as String?,
          label: json['etichetta'] as String? ?? json['label'] as String?,
        );

      case 'connetti_nodi':
      case 'connect_nodes':
        return ConnectNodesAction(
          fromId: json['da'] as String? ?? json['from'] as String? ?? '',
          toId: json['a'] as String? ?? json['to'] as String? ?? '',
          label: json['etichetta'] as String? ?? json['label'] as String?,
        );

      case 'raggruppa':
      case 'group_nodes':
        final ids = (json['nodi'] as List<dynamic>? ?? json['node_ids'] as List<dynamic>? ?? [])
            .cast<String>();
        return GroupNodesAction(nodeIds: ids);

      case 'riassumi':
      case 'summarize':
        return SummarizeAction(
          targetNodeId: json['nodo_target'] as String? ?? json['target_node_id'] as String?,
          summary: json['riassunto'] as String? ?? json['summary'] as String? ?? '',
          x: (json['x'] as num?)?.toDouble(),
          y: (json['y'] as num?)?.toDouble(),
        );

      case 'allinea':
      case 'align_nodes':
        final ids = (json['nodi'] as List<dynamic>? ?? json['node_ids'] as List<dynamic>? ?? [])
            .cast<String>();
        return AlignNodesAction(
          nodeIds: ids,
          alignment: json['allineamento'] as String? ?? json['alignment'] as String? ?? 'center_h',
        );

      case 'sposta_nodo':
      case 'move_node':
        return MoveNodeAction(
          nodeId: json['nodo_id'] as String? ?? json['node_id'] as String? ?? '',
          x: (json['x'] as num?)?.toDouble() ?? 0,
          y: (json['y'] as num?)?.toDouble() ?? 0,
        );

      default:
        return UnknownAction(type: type, rawJson: json);
    }
  }

  /// Parse a list of actions from the AI's full JSON response.
  static List<AtlasAction> parseAll(Map<String, dynamic> json) {
    final actionsList = json['azioni'] as List<dynamic>?
        ?? json['actions'] as List<dynamic>?
        ?? [];
    return actionsList
        .whereType<Map<String, dynamic>>()
        .map(AtlasAction.fromJson)
        .toList();
  }
}

/// Create a new text/shape node on the canvas.
class CreateNodeAction extends AtlasAction {
  final double x, y;
  final String content;
  final String nodeType; // 'text', 'shape', 'richText'
  final String? color;   // Hex or named color
  final String? label;   // Optional label/title

  const CreateNodeAction({
    required this.x,
    required this.y,
    required this.content,
    this.nodeType = 'text',
    this.color,
    this.label,
  });

  @override
  String toString() => 'CreateNodeAction($x, $y, "$content")';
}

/// Draw a visual connection (line/arrow) between two existing nodes.
class ConnectNodesAction extends AtlasAction {
  final String fromId;
  final String toId;
  final String? label;

  const ConnectNodesAction({
    required this.fromId,
    required this.toId,
    this.label,
  });

  @override
  String toString() => 'ConnectNodesAction($fromId → $toId)';
}

/// Group several nodes into a visual cluster.
class GroupNodesAction extends AtlasAction {
  final List<String> nodeIds;

  const GroupNodesAction({required this.nodeIds});

  @override
  String toString() => 'GroupNodesAction(${nodeIds.length} nodes)';
}

/// Create a summary node, optionally linked to an existing node.
class SummarizeAction extends AtlasAction {
  final String? targetNodeId;
  final String summary;
  final double? x, y;

  const SummarizeAction({
    this.targetNodeId,
    required this.summary,
    this.x,
    this.y,
  });

  @override
  String toString() => 'SummarizeAction("${summary.length > 30 ? summary.substring(0, 30) : summary}...")';
}

/// Align selected nodes to a specific pattern.
class AlignNodesAction extends AtlasAction {
  final List<String> nodeIds;
  final String alignment; // 'left', 'right', 'top', 'bottom', 'center_h', 'center_v', 'distribute_h', 'distribute_v'

  const AlignNodesAction({
    required this.nodeIds,
    required this.alignment,
  });

  @override
  String toString() => 'AlignNodesAction($alignment, ${nodeIds.length} nodes)';
}

/// Move an existing node to a new position.
class MoveNodeAction extends AtlasAction {
  final String nodeId;
  final double x, y;

  const MoveNodeAction({
    required this.nodeId,
    required this.x,
    required this.y,
  });

  @override
  String toString() => 'MoveNodeAction($nodeId → $x, $y)';
}

/// Fallback for unrecognized action types (forward-compatible).
class UnknownAction extends AtlasAction {
  final String type;
  final Map<String, dynamic> rawJson;

  const UnknownAction({required this.type, required this.rawJson});

  @override
  String toString() => 'UnknownAction($type)';
}
