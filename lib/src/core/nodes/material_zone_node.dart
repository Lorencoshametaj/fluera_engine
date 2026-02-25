import '../scene_graph/canvas_node.dart';
import '../scene_graph/node_id.dart';
import '../scene_graph/node_visitor.dart';
import '../scene_graph/canvas_node_factory.dart';
import './group_node.dart';
import '../../drawing/models/surface_material.dart';

/// 🧬 A group node that assigns a [SurfaceMaterial] to its children.
///
/// All strokes rendered inside this node inherit the surface's physical
/// properties (roughness, absorption, grain texture). This enables
/// different regions of the canvas to have different "paper" types.
///
/// ```
/// MaterialZoneNode (surface: watercolorPaper)
/// ├── StrokeNode (pencil)      ← rendered with watercolor paper grain
/// └── StrokeNode (watercolor)  ← spread amplified by absorption
/// ```
///
/// Follows the same pattern as [ClipGroupNode]: extends [GroupNode],
/// carries domain-specific properties, serializes to/from JSON.
class MaterialZoneNode extends GroupNode {
  /// The surface material applied to all children in this zone.
  SurfaceMaterial surface;

  MaterialZoneNode({
    required super.id,
    super.name = '',
    super.localTransform,
    super.opacity,
    super.blendMode,
    super.isVisible,
    super.isLocked,
    SurfaceMaterial? surface,
  }) : surface = surface ?? const SurfaceMaterial();

  @override
  Map<String, dynamic> toJson() {
    final json = baseToJson();
    json['nodeType'] = 'materialZone';
    json['surface'] = surface.toJson();
    json['children'] = children.map((c) => c.toJson()).toList();
    return json;
  }

  factory MaterialZoneNode.fromJson(Map<String, dynamic> json) {
    final node = MaterialZoneNode(
      id: NodeId(json['id'] as String),
      name: (json['name'] as String?) ?? '',
      surface: SurfaceMaterial.fromJson(
        json['surface'] as Map<String, dynamic>?,
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
  R accept<R>(NodeVisitor<R> visitor) => visitor.visitMaterialZone(this);
}
