import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/models/image_element.dart';
import '../../drawing/models/pro_drawing_point.dart';
import '../../tools/image/image_tool.dart';
import '../../drawing/brushes/brushes.dart';
import '../../canvas/infinite_canvas_controller.dart';
import '../optimization/spatial_index.dart';
import 'image_memory_manager.dart';

// =============================================================================
// 🖼️ ENTERPRISE IMAGE PAINTER — Viewport-level image renderer
//
// Performance Architecture:
// 1. R-tree spatial index → O(log n) viewport culling
// 2. Per-image ui.Picture cache → only re-render changed images
// 3. LOD (Level of Detail) → FilterQuality adapts to effective size
// 4. DPR-aware → optimal quality per display density
// 5. LRU memory integration → marks images as accessed for eviction tracking
// 6. Controller-based repaint → auto-repaints on pan/zoom
// =============================================================================

/// Per-image cache entry: the cached render and the data version
/// that was current when the cache was created.
class _ImageCacheEntry {
  final ui.Picture picture;
  final int version;

  _ImageCacheEntry(this.picture, this.version);

  void dispose() {
    picture.dispose();
  }
}

class ImagePainter extends CustomPainter {
  final List<ImageElement> images;
  final Map<String, ui.Image> loadedImages;
  final ImageElement? selectedImage;
  final ImageTool imageTool;

  // 🎨 Editing mode
  final ImageElement? imageInEditMode;
  final List<ProStroke> imageEditingStrokes;
  final ProStroke? currentEditingStroke;

  // 🔄 Loading animation value (0.0 - 1.0 for pulse effect)
  final double loadingPulse;

  // 🚀 Viewport-level controller
  final InfiniteCanvasController? controller;

  // 🧠 Version counter for shouldRepaint + cache invalidation
  final int imageVersion;

  // 📐 Device pixel ratio for LOD calculation
  final double devicePixelRatio;

  // 🌐 R-tree spatial index for O(log n) culling
  final RTree<ImageElement>? spatialIndex;

  // 🧠 LRU memory manager for access tracking
  final ImageMemoryManager? memoryManager;

  // 🖼️ Per-image Picture cache (static, persists across frames)
  static final Map<String, _ImageCacheEntry> _perImageCache = {};

  // 🚀 Static paint + text objects for loading placeholder (avoid GC pressure)
  static final Paint _placeholderBgPaint = Paint()..style = PaintingStyle.fill;
  static final Paint _placeholderGlowPaint =
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 4);
  static final Paint _placeholderBorderPaint =
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
  static final Paint _placeholderArcPaint =
      Paint()
        ..color = const Color(0xFF6495ED)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;
  static final Paint _placeholderTrackPaint =
      Paint()
        ..color = Colors.white10
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
  static final TextPainter _placeholderTextPainter = TextPainter(
    text: const TextSpan(
      text: 'Downloading...',
      style: TextStyle(
        color: Color(0x99FFFFFF),
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.3,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  // 🖌️ Static Paint for selection overlays (avoid per-frame allocation)
  static final Paint _selectionShadowPaint =
      Paint()
        ..color = Colors.blue.withValues(alpha: 0.1)
        ..style = PaintingStyle.fill;
  static final Paint _selectionBorderPaint =
      Paint()
        ..color = Colors.blue.shade600
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
  static final Paint _handleFillPaint =
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
  static final Paint _handleBorderPaint =
      Paint()
        ..color = Colors.blue.shade600
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
  static final Paint _editingBorderPaint =
      Paint()
        ..color = Colors.green.shade500
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0;
  static final Paint _editingOverlayPaint =
      Paint()
        ..color = Colors.green.withValues(alpha: 0.08)
        ..style = PaintingStyle.fill;
  static final TextPainter _editingLabelPainter = TextPainter(
    text: TextSpan(
      text: 'EDITING',
      style: TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.bold,
        backgroundColor: Colors.green.shade600,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  // 🎨 Reusable color matrix buffer (avoids List<double> allocation per frame)
  static final Float64List _colorMatrixBuffer = Float64List(20);

  ImagePainter({
    required this.images,
    required this.loadedImages,
    required this.selectedImage,
    required this.imageTool,
    this.imageInEditMode,
    this.imageEditingStrokes = const [],
    this.currentEditingStroke,
    this.loadingPulse = 0.0,
    this.controller,
    this.imageVersion = 0,
    this.devicePixelRatio = 1.0,
    this.spatialIndex,
    this.memoryManager,
  }) : super(repaint: controller);

  @override
  void paint(Canvas canvas, Size size) {
    if (images.isEmpty) return;

    // 🚀 Viewport-level: apply canvas transform internally
    final hasController = controller != null;
    if (hasController) {
      canvas.save();
      canvas.translate(controller!.offset.dx, controller!.offset.dy);
      canvas.scale(controller!.scale);
      if (controller!.rotation != 0.0) {
        canvas.rotate(controller!.rotation);
      }
    }

    // 🎯 Calculate viewport rect in canvas coordinates for culling
    Rect? viewportRect;
    if (hasController) {
      final scale = controller!.scale;
      final offset = controller!.offset;
      // Base viewport (no extra margin — R-tree queryVisible adds its own)
      var vp = Rect.fromLTWH(
        -offset.dx / scale,
        -offset.dy / scale,
        size.width / scale,
        size.height / scale,
      );
      // 🔄 Bug 3 fix: when canvas is rotated, expand to bounding box of rotated rect
      if (controller!.rotation != 0.0) {
        final cx = vp.center.dx;
        final cy = vp.center.dy;
        final hw = vp.width / 2;
        final hh = vp.height / 2;
        final cosR = math.cos(controller!.rotation).abs();
        final sinR = math.sin(controller!.rotation).abs();
        final newHw = hw * cosR + hh * sinR;
        final newHh = hw * sinR + hh * cosR;
        vp = Rect.fromCenter(
          center: Offset(cx, cy),
          width: newHw * 2,
          height: newHh * 2,
        );
      }
      viewportRect = vp;
    }

    // 🌐 SPATIAL INDEX CULLING — O(log n) instead of O(n)
    // Margin of 200px (down from default 1000px — images have bounded size)
    final visibleImages = _getVisibleImages(viewportRect);

    // 🧠 LRU: mark visible images as accessed
    if (memoryManager != null) {
      memoryManager!.markAllAccessed(
        visibleImages
            .where((img) => loadedImages.containsKey(img.imagePath))
            .map((img) => img.imagePath),
      );
    }

    // 🎨 Global dynamic flags (editing mode affects all images)
    final globalDynamic =
        imageInEditMode != null || currentEditingStroke != null;

    // 🖼️ Per-image rendering with cache
    for (final imageElement in visibleImages) {
      final image = loadedImages[imageElement.imagePath];

      if (image == null) {
        // Only this image is dynamic (loading), others keep cache
        if (loadingPulse > 0.0) {
          _drawLoadingPlaceholder(canvas, imageElement);
        }
        continue;
      }

      // 🚀 Improvement 2: per-image dynamic check instead of global
      // Only the dragged/resized image needs re-render; others keep cache
      final isThisImageActive =
          selectedImage?.id == imageElement.id ||
          imageInEditMode?.id == imageElement.id;
      final isThisImageDynamic =
          isThisImageActive && (imageTool.isDragging || imageTool.isResizing);

      // Per-image hash — includes canvas scale for LOD (improvement 1)
      final imgHash = _computeImageHash(imageElement);

      // 🖼️ TRY PER-IMAGE CACHE (for static images)
      if (!globalDynamic && !isThisImageDynamic && !isThisImageActive) {
        final cached = _perImageCache[imageElement.id];
        if (cached != null && cached.version == imgHash) {
          // ⚡ Fast path: replay cached Picture
          canvas.drawPicture(cached.picture);
          continue;
        }
      }

      // 🎨 Slow path: render this image and cache it
      final recorder = ui.PictureRecorder();
      final recordCanvas = Canvas(recorder);

      _renderSingleImage(recordCanvas, imageElement, image);

      final picture = recorder.endRecording();

      // Cache if static (not being interacted with)
      if (!globalDynamic && !isThisImageDynamic && !isThisImageActive) {
        _perImageCache[imageElement.id]?.dispose();
        _perImageCache[imageElement.id] = _ImageCacheEntry(picture, imgHash);
        canvas.drawPicture(picture);
      } else {
        // Dynamic: draw and discard
        canvas.drawPicture(picture);
        picture.dispose();
      }
    }

    // 🚀 Viewport-level: restore canvas transform
    if (hasController) {
      canvas.restore();
    }
  }

  /// 🧠 Compute a lightweight hash for per-image cache invalidation.
  /// Only invalidates when image properties actually change.
  /// Includes canvas scale for LOD-aware invalidation (improvement 1).
  int _computeImageHash(ImageElement e) {
    // Combine position, scale, rotation, opacity, flip, crop, strokes count
    var h = e.position.dx.hashCode;
    h = h * 31 + e.position.dy.hashCode;
    h = h * 31 + e.scale.hashCode;
    h = h * 31 + e.rotation.hashCode;
    h = h * 31 + e.opacity.hashCode;
    h = h * 31 + e.brightness.hashCode;
    h = h * 31 + e.contrast.hashCode;
    h = h * 31 + e.saturation.hashCode;
    h = h * 31 + e.flipHorizontal.hashCode;
    h = h * 31 + e.flipVertical.hashCode;
    h = h * 31 + (e.cropRect?.hashCode ?? 0);
    h = h * 31 + e.drawingStrokes.length;
    // 🔍 LOD: include canvas zoom so FilterQuality changes on zoom
    h = h * 31 + (controller?.scale.hashCode ?? 0);
    return h;
  }

  /// 🌐 Get visible images using R-tree (O(log n)) or linear fallback (O(n))
  List<ImageElement> _getVisibleImages(Rect? viewportRect) {
    // R-tree fast path (margin already handled in viewport rect)
    if (spatialIndex != null && viewportRect != null) {
      return spatialIndex!.queryVisible(viewportRect, margin: 200.0);
    }

    // Linear fallback with manual culling
    if (viewportRect != null) {
      return images.where((img) {
        final imgWidth = loadedImages[img.imagePath]?.width.toDouble() ?? 200.0;
        final imgHeight =
            loadedImages[img.imagePath]?.height.toDouble() ?? 150.0;
        var halfW = imgWidth * img.scale * 0.5;
        var halfH = imgHeight * img.scale * 0.5;
        // Rotation-aware bounds (consistent with R-tree path)
        if (img.rotation != 0.0) {
          final cosR = math.cos(img.rotation).abs();
          final sinR = math.sin(img.rotation).abs();
          final rotHalfW = halfW * cosR + halfH * sinR;
          final rotHalfH = halfW * sinR + halfH * cosR;
          halfW = rotHalfW;
          halfH = rotHalfH;
        }
        final imageRect = Rect.fromCenter(
          center: img.position,
          width: halfW * 2,
          height: halfH * 2,
        );
        return viewportRect.overlaps(imageRect);
      }).toList();
    }

    return images;
  }

  /// 🎨 Render a single image element (with LOD, filters, strokes, overlays)
  void _renderSingleImage(
    Canvas canvas,
    ImageElement imageElement,
    ui.Image image,
  ) {
    // Save canvas state
    canvas.save();

    // Translate to position
    canvas.translate(imageElement.position.dx, imageElement.position.dy);

    // Apply rotation
    if (imageElement.rotation != 0) {
      canvas.rotate(imageElement.rotation);
    }

    // Apply flip
    if (imageElement.flipHorizontal || imageElement.flipVertical) {
      canvas.scale(
        imageElement.flipHorizontal ? -1.0 : 1.0,
        imageElement.flipVertical ? -1.0 : 1.0,
      );
    }

    // Apply scale
    if (imageElement.scale != 1.0) {
      canvas.scale(imageElement.scale);
    }

    // Calculate dimensions (considering crop)
    final imageWidth = image.width.toDouble();
    final imageHeight = image.height.toDouble();

    Rect srcRect;
    Rect dstRect;

    if (imageElement.cropRect != null) {
      final crop = imageElement.cropRect!;
      srcRect = Rect.fromLTRB(
        crop.left * imageWidth,
        crop.top * imageHeight,
        crop.right * imageWidth,
        crop.bottom * imageHeight,
      );
      dstRect = Rect.fromCenter(
        center: Offset.zero,
        width: srcRect.width,
        height: srcRect.height,
      );
    } else {
      srcRect = Rect.fromLTWH(0, 0, imageWidth, imageHeight);
      dstRect = Rect.fromCenter(
        center: Offset.zero,
        width: imageWidth,
        height: imageHeight,
      );
    }

    // 🎨 Create paint with LOD-adaptive FilterQuality
    final paint = Paint()..filterQuality = _calculateLOD(imageElement, image);

    // Apply opacity (Bug 2 fix: removed BlendMode.dstIn which made images invisible)
    if (imageElement.opacity < 1.0) {
      paint.color = Color.fromRGBO(255, 255, 255, imageElement.opacity);
    }

    // Apply color filter if there are modifications
    if (imageElement.brightness != 0 ||
        imageElement.contrast != 0 ||
        imageElement.saturation != 0) {
      paint.colorFilter = ColorFilter.matrix(_getColorMatrix(imageElement));
    }

    // Draw the image
    canvas.drawImageRect(image, srcRect, dstRect, paint);

    // 🎨 Always draw saved strokes on the image
    if (imageElement.drawingStrokes.isNotEmpty) {
      for (final stroke in imageElement.drawingStrokes) {
        _drawStroke(canvas, stroke, imageElement.scale);
      }
    }

    // 🎨 If this image is in editing mode, draw temporary strokes
    if (imageInEditMode?.id == imageElement.id) {
      for (final stroke in imageEditingStrokes) {
        _drawStroke(canvas, stroke, imageElement.scale);
      }
      if (currentEditingStroke != null) {
        _drawStroke(canvas, currentEditingStroke!, imageElement.scale);
      }
    }

    // Restore state
    canvas.restore();

    // 🎨 Editing overlay (absolute coordinates)
    if (imageInEditMode?.id == imageElement.id) {
      _drawEditingOverlayBorder(canvas, imageElement, image);
    }

    // Selection border (only if NOT editing)
    if (selectedImage?.id == imageElement.id && imageInEditMode == null) {
      _drawSelection(canvas, imageElement, image);
    }
  }

  // ===========================================================================
  // 🔍 LOD (Level of Detail) — Adaptive FilterQuality
  // ===========================================================================

  /// Calculate the optimal FilterQuality based on effective screen size
  /// vs native image resolution, adjusted by device pixel ratio.
  FilterQuality _calculateLOD(ImageElement element, ui.Image image) {
    if (controller == null) return FilterQuality.high;

    final canvasScale = controller!.scale;
    final effectiveScale = element.scale * canvasScale;

    // Effective screen pixels vs native pixels
    final nativePixels = image.width * image.height;
    final effectivePixels =
        (image.width * effectiveScale * devicePixelRatio) *
        (image.height * effectiveScale * devicePixelRatio);

    final ratio = effectivePixels / nativePixels;

    // LOD thresholds (DPR-adjusted):
    // < 6.25% effective → low quality (zoomed very far out)
    // < 56.25% effective → medium quality
    // ≥ 56.25% effective → high quality (close up)
    if (ratio < 0.0625) return FilterQuality.low;
    if (ratio < 0.5625) return FilterQuality.medium;
    return FilterQuality.high;
  }

  // ===========================================================================
  // 🎨 Color Matrix
  // ===========================================================================

  List<double> _getColorMatrix(ImageElement element) {
    final b = element.brightness * 255;
    final c = element.contrast + 1.0;
    final t = (1.0 - c) / 2.0 * 255;
    final s = element.saturation + 1.0;
    final sr = (1.0 - s) * 0.3086;
    final sg = (1.0 - s) * 0.6094;
    final sb = (1.0 - s) * 0.0820;

    // Fill static buffer in-place (no allocation)
    _colorMatrixBuffer[0] = sr + s;
    _colorMatrixBuffer[1] = sg;
    _colorMatrixBuffer[2] = sb;
    _colorMatrixBuffer[3] = 0;
    _colorMatrixBuffer[4] = b + t;
    _colorMatrixBuffer[5] = sr;
    _colorMatrixBuffer[6] = sg + s;
    _colorMatrixBuffer[7] = sb;
    _colorMatrixBuffer[8] = 0;
    _colorMatrixBuffer[9] = b + t;
    _colorMatrixBuffer[10] = sr;
    _colorMatrixBuffer[11] = sg;
    _colorMatrixBuffer[12] = sb + s;
    _colorMatrixBuffer[13] = 0;
    _colorMatrixBuffer[14] = b + t;
    _colorMatrixBuffer[15] = 0;
    _colorMatrixBuffer[16] = 0;
    _colorMatrixBuffer[17] = 0;
    _colorMatrixBuffer[18] = 1;
    _colorMatrixBuffer[19] = 0;

    return _colorMatrixBuffer;
  }

  // ===========================================================================
  // 🖌️ Selection & Editing Overlays
  // ===========================================================================

  void _drawSelection(
    Canvas canvas,
    ImageElement imageElement,
    ui.Image image,
  ) {
    canvas.save();
    canvas.translate(imageElement.position.dx, imageElement.position.dy);
    canvas.rotate(imageElement.rotation);

    final scaledWidth = image.width.toDouble() * imageElement.scale;
    final scaledHeight = image.height.toDouble() * imageElement.scale;

    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: scaledWidth,
      height: scaledHeight,
    );

    // Subtle shadow (static paint)
    canvas.drawRect(rect.inflate(4), _selectionShadowPaint);

    // Selection border (static paint)
    canvas.drawRect(rect, _selectionBorderPaint);

    // Resize handles (4 corners, static paints)
    for (final pos in [
      rect.topLeft,
      rect.topRight,
      rect.bottomLeft,
      rect.bottomRight,
    ]) {
      canvas.drawCircle(pos, 5.0, _handleFillPaint);
      canvas.drawCircle(pos, 5.0, _handleBorderPaint);
    }

    canvas.restore();
  }

  void _drawEditingOverlayBorder(
    Canvas canvas,
    ImageElement imageElement,
    ui.Image image,
  ) {
    canvas.save();
    canvas.translate(imageElement.position.dx, imageElement.position.dy);
    canvas.rotate(imageElement.rotation);

    final scaledWidth = image.width.toDouble() * imageElement.scale;
    final scaledHeight = image.height.toDouble() * imageElement.scale;

    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: scaledWidth,
      height: scaledHeight,
    );

    // Green editing border (static paint)
    canvas.drawRect(rect, _editingBorderPaint);

    // Semi-transparent overlay (static paint)
    canvas.drawRect(rect, _editingOverlayPaint);

    // "EDITING" label (static, pre-laid-out)
    _editingLabelPainter.paint(canvas, rect.topLeft + const Offset(8, 8));

    canvas.restore();
  }

  // ===========================================================================
  // 🖌️ Stroke Rendering
  // ===========================================================================

  void _drawStroke(Canvas canvas, ProStroke stroke, [double scale = 1.0]) {
    if (stroke.points.isEmpty) return;

    final scaledBaseWidth = stroke.baseWidth / scale;

    switch (stroke.penType) {
      case ProPenType.ballpoint:
        BallpointBrush.drawStroke(
          canvas,
          stroke.points,
          stroke.color,
          scaledBaseWidth,
        );
        break;
      case ProPenType.fountain:
        FountainPenBrush.drawStroke(
          canvas,
          stroke.points,
          stroke.color,
          scaledBaseWidth,
        );
        break;
      case ProPenType.pencil:
        PencilBrush.drawStroke(
          canvas,
          stroke.points,
          stroke.color,
          scaledBaseWidth,
        );
        break;
      case ProPenType.highlighter:
        HighlighterBrush.drawStroke(
          canvas,
          stroke.points,
          stroke.color,
          scaledBaseWidth,
        );
        break;
      case ProPenType.watercolor:
      case ProPenType.marker:
      case ProPenType.charcoal:
      case ProPenType.oilPaint:
      case ProPenType.sprayPaint:
      case ProPenType.neonGlow:
      case ProPenType.inkWash:
        BallpointBrush.drawStroke(
          canvas,
          stroke.points,
          stroke.color,
          scaledBaseWidth,
        );
        break;
    }
  }

  // ===========================================================================
  // 🔄 Loading Placeholder
  // ===========================================================================

  void _drawLoadingPlaceholder(Canvas canvas, ImageElement imageElement) {
    canvas.save();
    canvas.translate(imageElement.position.dx, imageElement.position.dy);

    if (imageElement.rotation != 0) {
      canvas.rotate(imageElement.rotation);
    }
    if (imageElement.scale != 1.0) {
      canvas.scale(imageElement.scale);
    }

    const placeholderWidth = 200.0;
    const placeholderHeight = 150.0;
    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: placeholderWidth,
      height: placeholderHeight,
    );

    final pulseOpacity = 0.7 + 0.3 * math.sin(loadingPulse * math.pi * 2);

    // Background (reuse static paint, only update color)
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(12));
    _placeholderBgPaint.color = Color.fromRGBO(42, 42, 46, pulseOpacity);
    canvas.drawRRect(rrect, _placeholderBgPaint);

    // Glow border
    _placeholderGlowPaint.color = Color.fromRGBO(
      100,
      149,
      237,
      0.15 + 0.2 * pulseOpacity,
    );
    canvas.drawRRect(rrect, _placeholderGlowPaint);

    // Inner border
    _placeholderBorderPaint.color = Color.fromRGBO(
      100,
      149,
      237,
      0.3 + 0.2 * pulseOpacity,
    );
    canvas.drawRRect(rrect, _placeholderBorderPaint);

    // Spinning arc
    final arcCenter = const Offset(0, -8);
    const arcRadius = 16.0;
    canvas.drawArc(
      Rect.fromCircle(center: arcCenter, radius: arcRadius),
      loadingPulse * math.pi * 2,
      math.pi * 1.2,
      false,
      _placeholderArcPaint,
    );

    // Track ring
    canvas.drawCircle(arcCenter, arcRadius, _placeholderTrackPaint);

    // "Downloading..." text (static, pre-laid-out)
    _placeholderTextPainter.paint(
      canvas,
      Offset(-_placeholderTextPainter.width / 2, 18),
    );

    canvas.restore();
  }

  // ===========================================================================
  // ⚡ Cache Management
  // ===========================================================================

  /// Invalidate all cached Pictures (call on dispose or hot reload).
  static void invalidateCache() {
    for (final entry in _perImageCache.values) {
      entry.dispose();
    }
    _perImageCache.clear();
  }

  /// Invalidate cache for a specific image (e.g., after editing).
  static void invalidateImageCache(String imageId) {
    _perImageCache[imageId]?.dispose();
    _perImageCache.remove(imageId);
  }

  /// Remove cached entries for images no longer on the canvas.
  static void pruneCache(Set<String> activeImageIds) {
    final staleIds =
        _perImageCache.keys
            .where((id) => !activeImageIds.contains(id))
            .toList();
    for (final id in staleIds) {
      _perImageCache[id]?.dispose();
      _perImageCache.remove(id);
    }
  }

  // ===========================================================================
  // ⚡ shouldRepaint
  // ===========================================================================

  @override
  bool shouldRepaint(ImagePainter oldDelegate) {
    // Always repaint during interactive operations
    if (imageTool.isDragging || imageTool.isResizing) return true;

    // Always repaint in editing mode
    if (imageInEditMode != null || oldDelegate.imageInEditMode != null) {
      return true;
    }

    // Version counter: single integer comparison replaces expensive list checks
    if (imageVersion != oldDelegate.imageVersion) return true;

    // 🚀 Improvement 5: identity check detects new image loads (same count, different map)
    return selectedImage != oldDelegate.selectedImage ||
        !identical(loadedImages, oldDelegate.loadedImages) ||
        currentEditingStroke != oldDelegate.currentEditingStroke ||
        loadingPulse != oldDelegate.loadingPulse;
  }
}
