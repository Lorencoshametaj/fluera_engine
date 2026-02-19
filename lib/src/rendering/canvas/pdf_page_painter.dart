import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../core/nodes/pdf_page_node.dart';
import '../../canvas/nebula_canvas_config.dart';
import './pdf_memory_budget.dart';

/// 🎨 Painter responsible for rendering PDF pages with LOD-aware caching.
///
/// Works with [PdfPageNode] to manage the lifecycle of raster tiles:
/// 1. Check if a cached image exists at the required LOD
/// 2. If YES → draw it directly
/// 3. If NO → draw a placeholder + schedule async decode
///
/// Memory usage is governed by [PdfMemoryBudget] to adapt to device capabilities.
///
/// This painter does NOT extend CustomPainter — it provides static methods
/// called from [SceneGraphRenderer._renderPdfPage]. This avoids extra
/// widget rebuilds and keeps the rendering pipeline flat.
class PdfPagePainter {
  final NebulaPdfProvider? _provider;
  final PdfMemoryBudget _memoryBudget;

  /// Currently pending decode operations (prevent duplicate requests).
  final Set<String> _pendingDecodes = {};

  /// Total cached bytes across all managed pages.
  int _totalCachedBytes = 0;

  // Reusable Paint objects to avoid per-frame allocations.
  static final Paint _imagePaint = Paint()..filterQuality = FilterQuality.low;
  static final Paint _placeholderPaint =
      Paint()..color = const Color(0xFFF5F5F5);
  static final Paint _borderPaint =
      Paint()
        ..color = const Color(0xFFE0E0E0)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;

  PdfPagePainter({
    required NebulaPdfProvider? provider,
    required PdfMemoryBudget memoryBudget,
  }) : _provider = provider,
       _memoryBudget = memoryBudget;

  // ---------------------------------------------------------------------------
  // Core rendering
  // ---------------------------------------------------------------------------

  /// Paint a [PdfPageNode] onto [canvas].
  ///
  /// If the node has a valid cached image, draws it. Otherwise draws
  /// a placeholder and schedules an async decode.
  ///
  /// [currentZoom] is the current canvas zoom level, used to determine
  /// the target LOD scale.
  void paintPage(
    Canvas canvas,
    PdfPageNode node, {
    required double currentZoom,
    VoidCallback? onNeedRepaint,
  }) {
    final pageSize = node.pageModel.originalSize;
    final pageRect = Rect.fromLTWH(0, 0, pageSize.width, pageSize.height);

    // Determine target LOD scale
    final baseLod = PdfMemoryBudget.lodScaleForZoom(currentZoom);
    final targetScale = _memoryBudget.clampScale(baseLod);

    if (node.hasCacheAtScale(targetScale) && node.cachedImage != null) {
      // Fast path: draw cached raster tile
      _drawCachedImage(canvas, node, pageRect);
    } else {
      // Slow path: draw placeholder + schedule decode
      _drawPlaceholder(canvas, node, pageRect);
      _scheduleDecodeIfNeeded(node, targetScale, pageRect, onNeedRepaint);
    }
  }

  // ---------------------------------------------------------------------------
  // Image drawing
  // ---------------------------------------------------------------------------

  /// Draw the cached raster image, scaled to fill the page bounds.
  void _drawCachedImage(Canvas canvas, PdfPageNode node, Rect pageRect) {
    final img = node.cachedImage!;
    final srcRect = Rect.fromLTWH(
      0,
      0,
      img.width.toDouble(),
      img.height.toDouble(),
    );
    canvas.drawImageRect(img, srcRect, pageRect, _imagePaint);
  }

  // ---------------------------------------------------------------------------
  // Placeholder
  // ---------------------------------------------------------------------------

  /// Draw a lightweight placeholder while the page is decoding.
  void _drawPlaceholder(Canvas canvas, PdfPageNode node, Rect pageRect) {
    // Background
    canvas.drawRect(pageRect, _placeholderPaint);

    // Border
    canvas.drawRect(pageRect, _borderPaint);

    // Page number centered
    final pageNum = '${node.pageModel.pageIndex + 1}';
    final tp = TextPainter(
      text: TextSpan(
        text: pageNum,
        style: const TextStyle(
          color: Color(0xFFBBBBBB),
          fontSize: 28,
          fontWeight: FontWeight.w300,
          letterSpacing: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    tp.paint(
      canvas,
      Offset(
        (pageRect.width - tp.width) / 2,
        (pageRect.height - tp.height) / 2,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Async decode
  // ---------------------------------------------------------------------------

  /// Schedule an asynchronous page decode if not already pending.
  void _scheduleDecodeIfNeeded(
    PdfPageNode node,
    double targetScale,
    Rect pageRect,
    VoidCallback? onNeedRepaint,
  ) {
    if (_provider == null) return;

    final key = '${node.id}-$targetScale';
    if (_pendingDecodes.contains(key)) return;

    // Check if we have enough memory budget
    final estimatedBytes =
        (pageRect.width * targetScale).toInt() *
        (pageRect.height * targetScale).toInt() *
        4; // RGBA
    if (_totalCachedBytes + estimatedBytes > _memoryBudget.currentBudgetBytes) {
      // Over budget — skip this decode, keep placeholder
      return;
    }

    _pendingDecodes.add(key);

    _provider
        .renderPage(
          pageIndex: node.pageModel.pageIndex,
          scale: targetScale,
          targetSize: Size(
            pageRect.width * targetScale,
            pageRect.height * targetScale,
          ),
        )
        .then((ui.Image? image) {
          _pendingDecodes.remove(key);

          if (image != null) {
            // Dispose old cache if present
            final oldBytes = node.estimatedMemoryBytes;
            node.disposeCachedImage();
            _totalCachedBytes -= oldBytes;

            // Install new cache
            node.cachedImage = image;
            node.cachedScale = targetScale;
            _totalCachedBytes += node.estimatedMemoryBytes;

            // Request repaint
            onNeedRepaint?.call();
          }
        })
        .catchError((_) {
          _pendingDecodes.remove(key);
        });
  }

  // ---------------------------------------------------------------------------
  // Cache management
  // ---------------------------------------------------------------------------

  /// Evict cached images from pages that are outside the viewport.
  ///
  /// Called by the rendering pipeline when memory pressure is detected
  /// or when the viewport changes significantly.
  void evictOffViewport(List<PdfPageNode> allPages, Rect viewport) {
    for (final page in allPages) {
      if (page.cachedImage == null) continue;

      final pageBounds = page.worldBounds;
      if (!pageBounds.overlaps(viewport)) {
        _totalCachedBytes -= page.estimatedMemoryBytes;
        page.disposeCachedImage();
      }
    }
  }

  /// Dispose all cached images (call during cleanup or memory crisis).
  void disposeAll(List<PdfPageNode> allPages) {
    for (final page in allPages) {
      page.disposeCachedImage();
    }
    _totalCachedBytes = 0;
    _pendingDecodes.clear();
  }

  /// Current total cached bytes.
  int get totalCachedBytes => _totalCachedBytes;
}
