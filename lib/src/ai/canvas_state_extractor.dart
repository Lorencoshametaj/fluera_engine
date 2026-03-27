import 'dart:ui';
import '../systems/selection_manager.dart';
import '../core/scene_graph/canvas_node.dart';
import '../core/nodes/text_node.dart';
import '../core/nodes/rich_text_node.dart';
import '../core/nodes/image_node.dart';
import '../core/nodes/stroke_node.dart';
import '../core/nodes/shape_node.dart';
import '../core/nodes/pdf_document_node.dart';
import '../core/nodes/group_node.dart';

/// Extracts a structured JSON representation of canvas nodes
/// for consumption by the Atlas AI provider.
///
/// This is the "Spatial Translator" — it converts the live scene graph
/// into a compact, text-based map that the LLM can reason about.
///
/// The extractor is intentionally stateless and operates on snapshots
/// of the selection or viewport.
class CanvasStateExtractor {
  /// Optional map of strokeId → recognized handwriting text.
  /// When provided, StrokeNodes will include the recognized text
  /// instead of just "Tratto disegnato (X punti)".
  final Map<String, String> recognizedTexts;

  const CanvasStateExtractor({this.recognizedTexts = const {}});

  /// Extract structured data from the currently selected nodes.
  ///
  /// Returns a list of JSON-serializable maps, one per selected node,
  /// containing [id], [type], [position], [bounds], and [content].
  List<Map<String, dynamic>> extractFromSelection(SelectionManager selection) {
    return selection.selectedNodes.map(_nodeToMap).toList();
  }

  /// Extract structured data for all nodes within a spatial [queryRect]
  /// (in world/canvas coordinates).
  ///
  /// Recursively walks the scene graph starting from [root],
  /// collecting visible, non-locked leaf nodes whose [worldBounds]
  /// intersect the query rectangle.
  List<Map<String, dynamic>> extractFromViewport(
    GroupNode root,
    Rect queryRect,
  ) {
    final results = <Map<String, dynamic>>[];
    _collectInRect(root, queryRect, results);
    return results;
  }

  // ---------------------------------------------------------------------------
  // Private
  // ---------------------------------------------------------------------------

  void _collectInRect(
    GroupNode group,
    Rect queryRect,
    List<Map<String, dynamic>> results,
  ) {
    for (final child in group.children) {
      if (!child.isVisible) continue;

      if (child is GroupNode) {
        // Recurse into groups (but DON'T recurse into PdfDocumentNode pages)
        if (child is PdfDocumentNode) {
          // Treat the whole PDF doc as a single node
          if (child.worldBounds.overlaps(queryRect)) {
            results.add(_nodeToMap(child));
          }
        } else {
          _collectInRect(child, queryRect, results);
        }
      } else {
        if (child.worldBounds.isFinite && queryRect.overlaps(child.worldBounds)) {
          results.add(_nodeToMap(child));
        }
      }
    }
  }

  /// Convert a single [CanvasNode] into a structured map for the AI.
  Map<String, dynamic> _nodeToMap(CanvasNode node) {
    final bounds = node.worldBounds;
    final pos = node.position;

    final map = <String, dynamic>{
      'id': node.id.toString(),
      'tipo': _nodeTypeName(node),
      'nome': node.name.isNotEmpty ? node.name : null,
      'posizione': {'x': pos.dx.roundToDouble(), 'y': pos.dy.roundToDouble()},
      'dimensioni': {
        'larghezza': bounds.width.roundToDouble(),
        'altezza': bounds.height.roundToDouble(),
      },
    };

    // Extract content based on node type
    final content = _extractContent(node);
    if (content != null && content.isNotEmpty) {
      map['contenuto'] = content;
    }

    return map;
  }

  String _nodeTypeName(CanvasNode node) {
    if (node is TextNode) return 'testo';
    if (node is RichTextNode) return 'testo_ricco';
    if (node is ImageNode) return 'immagine';
    if (node is StrokeNode) {
      // If we have recognized text, call it 'scrittura' (handwriting)
      final recognized = recognizedTexts[node.id.toString()];
      if (recognized != null && recognized.isNotEmpty) return 'scrittura';
      return 'tratto';
    }
    if (node is ShapeNode) return 'forma';
    if (node is PdfDocumentNode) return 'pdf';
    if (node is GroupNode) return 'gruppo';
    return 'sconosciuto';
  }

  String? _extractContent(CanvasNode node) {
    if (node is TextNode) {
      return node.textElement.text;
    }
    if (node is RichTextNode) {
      return node.plainText;
    }
    if (node is ImageNode) {
      // For images, return the file path as context
      return node.imageElement.imagePath;
    }
    if (node is ShapeNode) {
      return 'Forma: ${node.shape.type.name}';
    }
    if (node is PdfDocumentNode) {
      return 'PDF: ${node.documentModel.totalPages} pagine';
    }
    if (node is StrokeNode) {
      // Use recognized handwriting text if available
      final recognized = recognizedTexts[node.id.toString()];
      if (recognized != null && recognized.isNotEmpty) {
        return 'Testo scritto a mano: "$recognized"';
      }
      return 'Tratto disegnato (${node.stroke.points.length} punti)';
    }
    return null;
  }
}
