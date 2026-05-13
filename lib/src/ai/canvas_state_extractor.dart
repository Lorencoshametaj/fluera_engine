import 'dart:ui';
import '../canvas/ai/cluster_concept_index.dart';
import '../reflow/content_cluster.dart';
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

  // ===========================================================================
  // CLUSTER-LEVEL PAYLOAD (Atlas dual-mode dispatcher — F8)
  // ===========================================================================

  /// Hard cap on clusters sent to the AI in a single cluster-mode call.
  ///
  /// Tuned to keep input tokens ≈ 30k on Flash Lite (cap × ~150 tokens per
  /// cluster entry incl. ocr_breve). For larger canvases the extractor
  /// keeps the [maxClusters] closest to the viewport center.
  static const int _defaultClusterCap = 200;

  /// Inflate factor for the viewport when filtering clusters by overlap.
  /// Matches the heuristic used elsewhere (`_getVisibleClusterIds`).
  static const double _viewportInflate = 200.0;

  /// Build the JSON payload sent to the AI for cluster-mode commands.
  ///
  /// The payload mirrors the node-level `_invokeAtlas` shape (italian-first
  /// keys, english fallbacks in the parser) but operates on cluster ids
  /// instead of individual node ids. Every entry is small (no point arrays,
  /// no full OCR) so the prompt fits comfortably on Flash Lite even with
  /// a few hundred clusters.
  ///
  /// Returns a map shaped as:
  /// ```json
  /// {
  ///   "comando_utente": "...",
  ///   "viewport": {"x_min", "y_min", "x_max", "y_max"},
  ///   "cluster_nel_contesto": [
  ///     {"id", "titolo", "topic", "x", "y", "larghezza", "altezza",
  ///      "n_strokes", "ocr_breve"}
  ///   ]
  /// }
  /// ```
  static Map<String, dynamic> buildClusterContext({
    required String userPrompt,
    required List<ContentCluster> clusters,
    required ClusterConceptIndex index,
    required Rect viewport,
    int maxClusters = _defaultClusterCap,
  }) {
    final inflated = viewport.inflate(_viewportInflate);
    final viewportCenter = viewport.center;

    // Filter by viewport overlap; if everything fits under the cap we keep
    // them all, otherwise we keep the N closest to the viewport center so
    // the AI's working set is the user's current focus.
    var candidates =
        clusters.where((c) => c.bounds.overlaps(inflated)).toList();
    if (candidates.isEmpty) {
      // Edge case: viewport sits outside any cluster (zoomed out far) —
      // fall back to the full cache so the AI still has material to work
      // with, then rely on the cap.
      candidates = List.of(clusters);
    }

    if (candidates.length > maxClusters) {
      candidates.sort((a, b) {
        final da = (a.centroid - viewportCenter).distanceSquared;
        final db = (b.centroid - viewportCenter).distanceSquared;
        return da.compareTo(db);
      });
      candidates = candidates.sublist(0, maxClusters);
    }

    final entries = candidates.map((c) {
      final concept = index.peek(c.id);
      final ocr = concept?.cleanedOcr ?? '';
      final ocrShort = ocr.length > 120 ? ocr.substring(0, 120) : ocr;
      return <String, dynamic>{
        'id': c.id,
        'titolo': concept?.title ?? '',
        'topic': concept?.topic ?? '',
        'x': _r1(c.centroid.dx),
        'y': _r1(c.centroid.dy),
        'larghezza': _r1(c.bounds.width),
        'altezza': _r1(c.bounds.height),
        'n_strokes': c.strokeIds.length,
        'ocr_breve': ocrShort,
      };
    }).toList();

    return <String, dynamic>{
      'comando_utente': userPrompt,
      'viewport': {
        'x_min': _r1(viewport.left),
        'y_min': _r1(viewport.top),
        'x_max': _r1(viewport.right),
        'y_max': _r1(viewport.bottom),
        'centro_x': _r1(viewportCenter.dx),
        'centro_y': _r1(viewportCenter.dy),
      },
      'cluster_nel_contesto': entries,
    };
  }

  /// Round to 1 decimal — sub-pixel precision is irrelevant to the AI and
  /// wastes tokens.
  static double _r1(double v) => (v * 10).roundToDouble() / 10;
}
