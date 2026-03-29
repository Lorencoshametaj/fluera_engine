import 'dart:ui';

import '../../core/models/shape_type.dart';

import 'package:flutter/foundation.dart';

import '../../core/models/canvas_layer.dart';
import '../../core/nodes/tabular_node.dart';
import '../../core/nodes/pdf_document_node.dart';
import '../../core/scene_graph/canvas_node.dart';
import '../../layers/layer_controller.dart';
import '../../rendering/optimization/viewport_culler.dart';

/// 🧭 Tracks the bounding rectangle of all visible content on the canvas.
///
/// DESIGN PRINCIPLES:
/// - Uses [LayerController.layers] as source of truth for strokes, shapes,
///   texts, and images (same coordinate space as [ViewportCuller]).
/// - Traverses [SceneGraph.allNodes] for [TabularNode] and [PdfDocumentNode]
///   which live in the scene graph only.
/// - Always recalculates when [update] is called (max once per frame via
///   `postFrameCallback`).
/// - Emits changes via [ValueNotifier] for reactive consumers.
///
/// MINIMAP PATH DATA:
/// - For strokes, emits a decimated polyline (max [_kMaxMinimapPoints] points)
///   alongside the bounding rect for richer minimap rendering.
class ContentBoundsTracker {
  final LayerController layerController;

  /// Cached content bounds, updated on each [update] call.
  final ValueNotifier<Rect> bounds = ValueNotifier<Rect>(Rect.zero);

  /// Per-element regions for minimap rendering.
  final ValueNotifier<List<ContentRegion>> regions =
      ValueNotifier<List<ContentRegion>>(const []);

  /// Maximum points kept per stroke for minimap polyline.
  /// Higher = more detail but more memory; 8 is enough for a good silhouette.
  static const int _kMaxMinimapPoints = 12;

  /// Hash of the last content state — used to skip redundant rebuilds.
  /// Computed from element counts (strokes, shapes, texts, images, nodes).
  int _lastContentHash = 0;

  ContentBoundsTracker({required this.layerController});

  /// Recalculate bounds from the current layer content.
  ///
  /// Called at most once per frame (via `addPostFrameCallback`).
  /// Uses a fast hash to skip full rebuilds when nothing changed.
  bool update() {
    // ── Fast dirty check: compute content hash from element counts ──────
    final contentHash = _computeContentHash();
    if (contentHash == _lastContentHash) return false;
    _lastContentHash = contentHash;

    Rect? combined;
    final regionList = <ContentRegion>[];

    // ── Layer content (strokes, shapes, texts, images) ─────────────────────
    for (final layer in layerController.layers) {
      if (!layer.isVisible) continue;

      for (final stroke in layer.strokes) {
        final b = stroke.bounds;
        if (b == Rect.zero || !b.isFinite) continue;
        combined = combined == null ? b : combined.expandToInclude(b);

        // Build decimated polyline for minimap rendering.
        final polyline = _decimatePoints(stroke.points, _kMaxMinimapPoints);
        regionList.add(
          ContentRegion(
            bounds: b,
            nodeType: ContentNodeType.stroke,
            minimapPolyline: polyline,
            strokeColor: stroke.color,
          ),
        );
      }

      for (final shape in layer.shapes) {
        final b = ViewportCuller.getShapeBounds(shape);
        if (b.isEmpty || !b.isFinite) continue;
        combined = combined == null ? b : combined.expandToInclude(b);
        regionList.add(
          ContentRegion(
            bounds: b,
            nodeType: ContentNodeType.shape,
            shapeType: shape.type,
          ),
        );
      }

      for (final text in layer.texts) {
        final b = text.getBounds();
        if (b.isEmpty || !b.isFinite) continue;
        combined = combined == null ? b : combined.expandToInclude(b);
        // Approximate line count from height / fontSize for text glyph.
        final fontSize = text.fontSize > 0 ? text.fontSize : 16.0;
        final approxLines = (b.height / (fontSize * 1.4)).round().clamp(1, 8);
        regionList.add(
          ContentRegion(
            bounds: b,
            nodeType: ContentNodeType.text,
            approxLineCount: approxLines,
          ),
        );
      }

      for (final image in layer.images) {
        const defaultImageSize = 200.0;
        final w = defaultImageSize * image.scale;
        final h = defaultImageSize * image.scale;
        final b = Rect.fromLTWH(image.position.dx, image.position.dy, w, h);
        if (b.isEmpty || !b.isFinite) continue;
        combined = combined == null ? b : combined.expandToInclude(b);
        regionList.add(
          ContentRegion(bounds: b, nodeType: ContentNodeType.image),
        );
      }
    }

    // ── Scene graph nodes (TabularNode, PdfDocumentNode) ───────────────────
    try {
      for (final node in layerController.sceneGraph.allNodes) {
        if (!node.isVisible) continue;

        if (node is TabularNode) {
          final b = node.worldBounds;
          if (b.isEmpty || !b.isFinite) continue;
          combined = combined == null ? b : combined.expandToInclude(b);
          regionList.add(
            ContentRegion(bounds: b, nodeType: ContentNodeType.other),
          );
        } else if (node is PdfDocumentNode) {
          final b = node.worldBounds;
          if (b.isEmpty || !b.isFinite) continue;
          combined = combined == null ? b : combined.expandToInclude(b);
          regionList.add(
            ContentRegion(bounds: b, nodeType: ContentNodeType.pdf),
          );
        }
      }
    } catch (_) {
      // Scene graph might not be ready yet — skip silently.
    }

    final newBounds = combined ?? Rect.zero;
    bounds.value = newBounds;
    regions.value = regionList;
    return true;
  }

  /// Fast content fingerprint: combines element counts per layer +
  /// the bounding corners of first/last stroke to detect changes.
  /// O(L) where L = number of layers (NOT strokes).
  int _computeContentHash() {
    int hash = 0;
    for (final layer in layerController.layers) {
      if (!layer.isVisible) continue;
      hash = Object.hash(
        hash,
        layer.strokes.length,
        layer.shapes.length,
        layer.texts.length,
        layer.images.length,
      );
      // Include boundary corners of first/last stroke for position changes.
      if (layer.strokes.isNotEmpty) {
        hash = Object.hash(
          hash,
          layer.strokes.first.bounds,
          layer.strokes.last.bounds,
        );
      }
    }
    return hash;
  }

  /// Decimate a list of drawing points to at most [maxPoints] offsets.
  ///
  /// Uses uniform sampling (every Nth point) for O(n) performance.
  /// Returns world-space offsets suitable for minimap polyline rendering.
  static List<Offset> _decimatePoints(List<dynamic> points, int maxPoints) {
    if (points.isEmpty) return const [];
    if (points.length <= maxPoints) {
      return points.map<Offset>((p) => p.position as Offset).toList();
    }

    final result = <Offset>[];
    final step = points.length / maxPoints;
    for (int i = 0; i < maxPoints; i++) {
      final idx = (i * step).floor().clamp(0, points.length - 1);
      result.add(points[idx].position as Offset);
    }
    // Always include the last point for continuity.
    result.add(points.last.position as Offset);
    return result;
  }

  /// Force a full recalculation on the next [update] call.
  void invalidate() {
    _lastContentHash = 0; // Reset hash → forces rebuild.
  }

  void dispose() {
    bounds.dispose();
    regions.dispose();
  }
}

/// Classification of a node for minimap/radar rendering.
enum ContentNodeType { stroke, shape, text, image, pdf, other }

/// A single content region for minimap rendering.
class ContentRegion {
  final Rect bounds;
  final ContentNodeType nodeType;

  /// Decimated polyline for stroke preview on the minimap.
  /// Null for non-stroke regions. Contains world-space offsets.
  final List<Offset>? minimapPolyline;

  /// Original stroke color (used for minimap stroke rendering).
  /// Null for non-stroke regions.
  final Color? strokeColor;

  /// Shape type for shape regions (line, rect, circle, etc.).
  /// Null for non-shape regions.
  final ShapeType? shapeType;

  /// Approximate number of text lines (for text glyph rendering).
  /// Null for non-text regions.
  final int? approxLineCount;

  const ContentRegion({
    required this.bounds,
    required this.nodeType,
    this.minimapPolyline,
    this.strokeColor,
    this.shapeType,
    this.approxLineCount,
  });
}
