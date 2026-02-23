import 'dart:ui';

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
class ContentBoundsTracker {
  final LayerController layerController;

  /// Cached content bounds, updated on each [update] call.
  final ValueNotifier<Rect> bounds = ValueNotifier<Rect>(Rect.zero);

  /// Per-element regions for minimap rendering.
  final ValueNotifier<List<ContentRegion>> regions =
      ValueNotifier<List<ContentRegion>>(const []);

  ContentBoundsTracker({required this.layerController});

  /// Recalculate bounds from the current layer content.
  ///
  /// Called at most once per frame (via `addPostFrameCallback`).
  bool update() {
    Rect? combined;
    final regionList = <ContentRegion>[];

    // ── Layer content (strokes, shapes, texts, images) ─────────────────────
    for (final layer in layerController.layers) {
      if (!layer.isVisible) continue;

      for (final stroke in layer.strokes) {
        final b = stroke.bounds;
        if (b == Rect.zero || !b.isFinite) continue;
        combined = combined == null ? b : combined.expandToInclude(b);
        regionList.add(
          ContentRegion(bounds: b, nodeType: ContentNodeType.stroke),
        );
      }

      for (final shape in layer.shapes) {
        final b = ViewportCuller.getShapeBounds(shape);
        if (b.isEmpty || !b.isFinite) continue;
        combined = combined == null ? b : combined.expandToInclude(b);
        regionList.add(
          ContentRegion(bounds: b, nodeType: ContentNodeType.shape),
        );
      }

      for (final text in layer.texts) {
        final b = text.getBounds();
        if (b.isEmpty || !b.isFinite) continue;
        combined = combined == null ? b : combined.expandToInclude(b);
        regionList.add(
          ContentRegion(bounds: b, nodeType: ContentNodeType.text),
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
    // These live in the scene graph, not in CanvasLayer lists.
    // Use worldBounds which applies localTransform (position) to localBounds.
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
    final changed =
        bounds.value != newBounds || regions.value.length != regionList.length;
    bounds.value = newBounds;
    regions.value = regionList;
    return changed;
  }

  /// Force a full recalculation on the next [update] call.
  void invalidate() {
    // No-op now since we always recalculate, but kept for API compatibility.
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

  const ContentRegion({required this.bounds, required this.nodeType});
}
