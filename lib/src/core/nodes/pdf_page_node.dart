import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../scene_graph/canvas_node.dart';
import '../scene_graph/node_id.dart';
import '../scene_graph/node_visitor.dart';
import '../models/pdf_page_model.dart';
import '../models/pdf_text_rect.dart';

/// 📄 Scene graph node representing a single PDF page on the canvas.
///
/// Wraps a [PdfPageModel] and holds the rasterized [ui.Image] cache.
/// The actual PDF decoding is handled externally via [FlueraPdfProvider];
/// this node simply draws the cached image or a placeholder.
///
/// DESIGN PRINCIPLES:
/// - One node per PDF page — each page is an independent canvas element
/// - Raster cache managed by the rendering pipeline (LOD-aware)
/// - Text geometry rects loaded lazily for selection support
/// - Annotations (strokes, shapes) are sibling nodes, not children
class PdfPageNode extends CanvasNode {
  /// Page metadata (index, size, lock state, timestamps).
  PdfPageModel pageModel;

  /// Cached rasterized page image (set by the rendering pipeline).
  ui.Image? cachedImage;

  /// LOD scale at which [cachedImage] was rendered.
  double cachedScale;

  /// Lazily loaded text geometry for text selection.
  List<PdfTextRect>? textRects;

  /// Estimated memory usage of [cachedImage] in bytes.
  int get estimatedMemoryBytes {
    if (cachedImage == null) return 0;
    return cachedImage!.width * cachedImage!.height * 4; // RGBA
  }

  /// Timestamp of last paint call — used for LRU eviction ordering.
  int lastDrawnTimestamp = 0;

  /// Stopwatch time when cached image was last updated — for fade-in animation.
  int cacheUpdatedAt = 0;

  PdfPageNode({
    required super.id,
    required this.pageModel,
    this.cachedImage,
    this.cachedScale = 0.0,
    this.textRects,
    super.name = '',
    super.localTransform,
    super.opacity,
    super.blendMode,
    super.isVisible,
    super.isLocked,
  });

  // ---------------------------------------------------------------------------
  // Bounds
  // ---------------------------------------------------------------------------

  @override
  Rect get localBounds {
    final pos = position;
    final w = pageModel.originalSize.width;
    final h = pageModel.originalSize.height;
    return Rect.fromLTWH(pos.dx, pos.dy, w, h);
  }

  // ---------------------------------------------------------------------------
  // Cache management
  // ---------------------------------------------------------------------------

  /// Dispose the cached raster image and free GPU memory.
  void disposeCachedImage() {
    cachedImage?.dispose();
    cachedImage = null;
    cachedScale = 0.0;
  }

  /// Whether this page has a valid cached image at the given [targetScale].
  bool hasCacheAtScale(double targetScale) {
    if (cachedImage == null) return false;
    if (targetScale <= 0) return false; // E7: guard division by zero
    // Allow ±25% tolerance before re-render
    final ratio = cachedScale / targetScale;
    return ratio > 0.75 && ratio < 1.5;
  }

  // ---------------------------------------------------------------------------
  // Text geometry
  // ---------------------------------------------------------------------------

  /// Whether text geometry has been loaded for this page.
  bool get hasTextGeometry => textRects != null;

  /// Find the text rect at [localPoint], or null if none.
  ///
  /// Converts [localPoint] from page-local pixels to normalized 0.0–1.0
  /// space before comparison against normalized text rects.
  PdfTextRect? hitTestText(Offset localPoint) {
    if (textRects == null) return null;
    final nx = localPoint.dx / pageModel.originalSize.width;
    final ny = localPoint.dy / pageModel.originalSize.height;
    final normalizedPoint = Offset(nx, ny);
    for (final rect in textRects!) {
      if (rect.containsPoint(normalizedPoint)) return rect;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  @override
  Map<String, dynamic> toJson() {
    final json = baseToJson();
    json['nodeType'] = 'pdfPage';
    json['pageModel'] = pageModel.toJson();
    if (textRects != null) {
      json['textRects'] = textRects!.map((r) => r.toJson()).toList();
    }
    return json;
  }

  factory PdfPageNode.fromJson(Map<String, dynamic> json) {
    // D1: Defensive fallback if pageModel is missing or malformed
    PdfPageModel pageModel;
    if (json['pageModel'] is Map<String, dynamic>) {
      pageModel = PdfPageModel.fromJson(
        json['pageModel'] as Map<String, dynamic>,
      );
    } else {
      pageModel = const PdfPageModel(
        pageIndex: 0,
        originalSize: Size(612, 792),
      );
    }

    final node = PdfPageNode(
      id: NodeId((json['id'] as String?) ?? 'unknown'),
      pageModel: pageModel,
    );
    CanvasNode.applyBaseFromJson(node, json);

    // Restore cached text geometry if present.
    // Backward compat: old data has absolute PDF-point coords (values > 1.0).
    // Detect and discard — re-extraction will normalize.
    if (json['textRects'] is List<dynamic>) {
      final parsed =
          (json['textRects'] as List<dynamic>)
              .whereType<Map<String, dynamic>>()
              .map((r) => PdfTextRect.fromJson(r))
              .toList();
      // If any rect has coords > 1.0, it's pre-normalization data
      final isNormalized =
          parsed.isEmpty ||
          parsed.every(
            (r) =>
                r.rect.left <= 1.0 &&
                r.rect.right <= 1.0 &&
                r.rect.top <= 1.0 &&
                r.rect.bottom <= 1.0,
          );
      node.textRects = isNormalized ? parsed : null;
    }

    return node;
  }

  // ---------------------------------------------------------------------------
  // Visitor
  // ---------------------------------------------------------------------------

  @override
  R accept<R>(NodeVisitor<R> visitor) => visitor.visitPdfPage(this);

  @override
  String toString() =>
      'PdfPageNode(id: $id, page: ${pageModel.pageIndex}, '
      '${pageModel.isLocked ? "locked" : "unlocked"})';
}
