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
import '../nodes/latex_node.dart';
import '../nodes/tabular_node.dart';
import '../nodes/material_zone_node.dart';
import '../nodes/section_node.dart';
import '../engine_scope.dart';

/// Factory for deserializing [CanvasNode] subclasses from JSON.
///
/// Uses a two-tier lookup strategy:
/// 1. **Dynamic**: Delegates to [ModuleRegistry.createNodeFromJson] which
///    checks registered [NodeDescriptor]s from all active modules.
/// 2. **Hardcoded**: Falls back to the built-in switch for core node types
///    (group, layer, etc.) that aren't owned by any module.
///
/// This allows new modules to register custom node types without modifying
/// this file.
class CanvasNodeFactory {
  /// Create a [CanvasNode] from its JSON representation.
  ///
  /// Throws [ArgumentError] if the `nodeType` is unknown.
  static CanvasNode fromJson(Map<String, dynamic> json) {
    final nodeType = json['nodeType'] as String?;

    // ── Tier 1: Dynamic module lookup ──
    // If modules are initialized, try the module registry first.
    // This enables extensible deserialization without hardcoded cases.
    if (EngineScope.hasScope) {
      final moduleNode = EngineScope.current.moduleRegistry.createNodeFromJson(
        json,
      );
      if (moduleNode != null) return moduleNode;
    }

    // ── Tier 2: Built-in hardcoded fallback ──
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

      case 'latex':
        return LatexNode.fromJson(json);

      case 'tabular':
        return TabularNode.fromJson(json);

      case 'materialZone':
        return MaterialZoneNode.fromJson(json);

      case 'section':
        final section = SectionNode.fromJson(json);
        if (json['children'] != null) {
          section.loadChildrenFromJson(
            json['children'] as List<dynamic>,
            fromJson,
          );
        }
        return section;

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
