import '../scene_graph/canvas_node.dart';
import '../scene_graph/node_id.dart';
import '../scene_graph/node_visitor.dart';
import './group_node.dart';
import '../scene_graph/canvas_node_factory.dart';

/// How the clip mask is applied.
enum ClipMode {
  /// Shape clipping — children are clipped to the first child's path.
  clip,

  /// Alpha/luminance mask — first child's alpha channel masks remaining children.
  alphaMask,
}

/// A group node that clips its children using a mask.
///
/// The **first child** acts as the clip/mask source.
/// All subsequent children are the masked content.
///
/// ```
/// ClipGroupNode (mode: clip)
/// ├── ShapeNode (star)      ← mask source
/// └── ImageNode (photo)     ← clipped to star shape
/// ```
class ClipGroupNode extends GroupNode {
  ClipMode clipMode;

  ClipGroupNode({
    required super.id,
    super.name = '',
    super.localTransform,
    super.opacity,
    super.blendMode,
    super.isVisible,
    super.isLocked,
    this.clipMode = ClipMode.clip,
  });

  /// The mask source (first child), or null if empty.
  CanvasNode? get maskSource => children.isNotEmpty ? children.first : null;

  /// The masked content (all children except the first).
  List<CanvasNode> get maskedContent =>
      children.length > 1 ? children.sublist(1) : [];

  @override
  Map<String, dynamic> toJson() {
    final json = baseToJson();
    json['nodeType'] = 'clipGroup';
    json['clipMode'] = clipMode.name;
    json['children'] = children.map((c) => c.toJson()).toList();
    return json;
  }

  factory ClipGroupNode.fromJson(Map<String, dynamic> json) {
    final node = ClipGroupNode(
      id: NodeId(json['id'] as String),
      name: (json['name'] as String?) ?? '',
      clipMode: ClipMode.values.firstWhere(
        (m) => m.name == json['clipMode'],
        orElse: () => ClipMode.clip,
      ),
    );
    CanvasNode.applyBaseFromJson(node, json);

    // Deserialize children
    if (json['children'] != null) {
      node.loadChildrenFromJson(
        json['children'] as List<dynamic>,
        CanvasNodeFactory.fromJson,
      );
    }

    return node;
  }

  @override
  R accept<R>(NodeVisitor<R> visitor) => visitor.visitClipGroup(this);
}
