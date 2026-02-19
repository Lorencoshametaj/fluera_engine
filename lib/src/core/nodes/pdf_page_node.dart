import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../scene_graph/canvas_node.dart';
import '../scene_graph/node_visitor.dart';
import '../models/pdf_page_model.dart';
import '../models/pdf_text_rect.dart';

/// 📄 Scene graph node representing a single PDF page on the canvas.
///
/// Wraps a [PdfPageModel] and holds the rasterized [ui.Image] cache.
/// The actual PDF decoding is handled externally via [NebulaPdfProvider];
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
  PdfTextRect? hitTestText(Offset localPoint) {
    if (textRects == null) return null;
    for (final rect in textRects!) {
      if (rect.containsPoint(localPoint)) return rect;
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
    final node = PdfPageNode(
      id: json['id'] as String,
      pageModel: PdfPageModel.fromJson(
        json['pageModel'] as Map<String, dynamic>,
      ),
    );
    CanvasNode.applyBaseFromJson(node, json);

    // Restore cached text geometry if present
    if (json['textRects'] != null) {
      node.textRects =
          (json['textRects'] as List<dynamic>)
              .map((r) => PdfTextRect.fromJson(r as Map<String, dynamic>))
              .toList();
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
