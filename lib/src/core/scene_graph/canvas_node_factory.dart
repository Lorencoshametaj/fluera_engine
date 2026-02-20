import './canvas_node.dart';
import './node_id.dart';
import '../nodes/group_node.dart';
import '../nodes/layer_node.dart';
import '../nodes/stroke_node.dart';
import '../nodes/shape_node.dart';
import '../nodes/text_node.dart';
import '../nodes/image_node.dart';
import '../nodes/clip_group_node.dart';
import '../nodes/path_node.dart';
import '../nodes/rich_text_node.dart';
import '../nodes/symbol_system.dart';
import '../nodes/frame_node.dart';
import '../nodes/advanced_mask_node.dart';
import '../nodes/boolean_group_node.dart';
import '../nodes/pdf_page_node.dart';
import '../nodes/pdf_document_node.dart';
import '../nodes/vector_network_node.dart';
import '../effects/shader_effect.dart';

/// Factory for deserializing [CanvasNode] subclasses from JSON.
///
/// The `nodeType` field in the JSON determines which concrete class
/// to instantiate. This centralizes the dispatch logic so that
/// [GroupNode.loadChildrenFromJson] and [SceneGraph.fromJson] don't
/// need to know about every node type.
class CanvasNodeFactory {
  /// Create a [CanvasNode] from its JSON representation.
  ///
  /// Throws [ArgumentError] if the `nodeType` is unknown.
  static CanvasNode fromJson(Map<String, dynamic> json) {
    final nodeType = json['nodeType'] as String?;

    switch (nodeType) {
      case 'stroke':
        return StrokeNode.fromJson(json);

      case 'shape':
        return ShapeNode.fromJson(json);

      case 'text':
        return TextNode.fromJson(json);

      case 'image':
        return ImageNode.fromJson(json);

      case 'group':
        final group = GroupNode(id: NodeId(json['id'] as String));
        CanvasNode.applyBaseFromJson(group, json);
        if (json['children'] != null) {
          group.loadChildrenFromJson(
            json['children'] as List<dynamic>,
            fromJson,
          );
        }
        return group;

      case 'layer':
        return layerFromJson(json);

      case 'clipGroup':
        return ClipGroupNode.fromJson(json);

      case 'path':
        return PathNode.fromJson(json);

      case 'richText':
        return RichTextNode.fromJson(json);

      case 'symbolInstance':
        return SymbolInstanceNode.fromJson(json);

      case 'frame':
        return FrameNode.fromJson(json);

      case 'advancedMask':
        return AdvancedMaskNode.fromJson(json);

      case 'shader':
        return ShaderNode.fromJson(json);

      case 'booleanGroup':
        final boolGroup = BooleanGroupNode.fromJson(json);
        if (json['children'] != null) {
          boolGroup.loadChildrenFromJson(
            json['children'] as List<dynamic>,
            fromJson,
          );
        }
        return boolGroup;

      case 'pdfPage':
        return PdfPageNode.fromJson(json);

      case 'pdfDocument':
        final doc = PdfDocumentNode.fromJson(json);
        if (json['children'] != null) {
          doc.loadChildrenFromJson(json['children'] as List<dynamic>, fromJson);
        }
        return doc;

      case 'vector_network':
        return VectorNetworkNode.fromJson(json);

      default:
        throw ArgumentError('Unknown nodeType: $nodeType');
    }
  }

  /// Create a [LayerNode] from JSON.
  static LayerNode layerFromJson(Map<String, dynamic> json) {
    final layer = LayerNode(id: NodeId(json['id'] as String));
    CanvasNode.applyBaseFromJson(layer, json);
    if (json['children'] != null) {
      layer.loadChildrenFromJson(json['children'] as List<dynamic>, fromJson);
    }
    return layer;
  }
}
