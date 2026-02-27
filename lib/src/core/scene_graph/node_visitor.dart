// Imports from concrete node types for visitor dispatch.
import '../nodes/group_node.dart';
import '../nodes/layer_node.dart';
import '../nodes/shape_node.dart';
import '../nodes/stroke_node.dart';
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

/// Double-dispatch visitor for type-safe scene graph traversal.
///
/// Implement this to handle each node type without `is` checks:
///
/// ```dart
/// class NodeCounter implements NodeVisitor<int> {
///   int visitShape(ShapeNode node) => 1;
///   int visitGroup(GroupNode node) =>
///       node.children.fold(0, (sum, c) => sum + c.accept(this));
///   // ...
/// }
/// ```
///
/// This pattern ensures compile-time safety: when a new node type is
/// added, all visitors get a compile error until they handle it.
abstract class NodeVisitor<R> {
  R visitGroup(GroupNode node);
  R visitLayer(LayerNode node);
  R visitShape(ShapeNode node);
  R visitStroke(StrokeNode node);
  R visitText(TextNode node);
  R visitImage(ImageNode node);
  R visitClipGroup(ClipGroupNode node);
  R visitPath(PathNode node);
  R visitRichText(RichTextNode node);
  R visitSymbolInstance(SymbolInstanceNode node);
  R visitFrame(FrameNode node);
  R visitAdvancedMask(AdvancedMaskNode node);
  R visitBooleanGroup(BooleanGroupNode node);
  R visitShader(ShaderNode node);
  R visitPdfPage(PdfPageNode node);
  R visitPdfDocument(PdfDocumentNode node);
  R visitVectorNetwork(VectorNetworkNode node);
  R visitLatex(LatexNode node);
  R visitTabular(TabularNode node);
  R visitMaterialZone(MaterialZoneNode node);
  R visitSection(SectionNode node);
}

/// Default implementation that returns a fallback value for every node type.
///
/// Extend this instead of [NodeVisitor] when you only care about a few
/// node types and want no-ops for the rest.
///
/// ```dart
/// class ShapeCollector extends DefaultNodeVisitor<void> {
///   final shapes = <ShapeNode>[];
///
///   @override
///   void visitShape(ShapeNode node) => shapes.add(node);
/// }
/// ```
class DefaultNodeVisitor<R> implements NodeVisitor<R> {
  /// Value returned for unhandled node types.
  final R defaultValue;

  DefaultNodeVisitor(this.defaultValue);

  @override
  R visitGroup(GroupNode node) => defaultValue;
  @override
  R visitLayer(LayerNode node) => defaultValue;
  @override
  R visitShape(ShapeNode node) => defaultValue;
  @override
  R visitStroke(StrokeNode node) => defaultValue;
  @override
  R visitText(TextNode node) => defaultValue;
  @override
  R visitImage(ImageNode node) => defaultValue;
  @override
  R visitClipGroup(ClipGroupNode node) => defaultValue;
  @override
  R visitPath(PathNode node) => defaultValue;
  @override
  R visitRichText(RichTextNode node) => defaultValue;
  @override
  R visitSymbolInstance(SymbolInstanceNode node) => defaultValue;
  @override
  R visitFrame(FrameNode node) => defaultValue;
  @override
  R visitAdvancedMask(AdvancedMaskNode node) => defaultValue;
  @override
  R visitBooleanGroup(BooleanGroupNode node) => defaultValue;
  @override
  R visitShader(ShaderNode node) => defaultValue;
  @override
  R visitPdfPage(PdfPageNode node) => defaultValue;
  @override
  R visitPdfDocument(PdfDocumentNode node) => defaultValue;
  @override
  R visitVectorNetwork(VectorNetworkNode node) => defaultValue;
  @override
  R visitLatex(LatexNode node) => defaultValue;
  @override
  R visitTabular(TabularNode node) => defaultValue;
  @override
  R visitMaterialZone(MaterialZoneNode node) => defaultValue;
  @override
  R visitSection(SectionNode node) => defaultValue;
}
