import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/models/image_element.dart';
import '../../core/models/text_overlay.dart';
import '../../core/models/color_adjustments.dart';
import '../../core/models/gradient_filter.dart';
import '../../core/models/perspective_settings.dart';
import '../image_adjustment_engine.dart';
import '../../drawing/models/pro_drawing_point.dart';
import '../../tools/image/image_tool.dart';
import '../../drawing/brushes/brushes.dart';
import '../../drawing/brushes/brush_engine.dart';
import '../../canvas/infinite_canvas_controller.dart';
import '../optimization/spatial_index.dart';
import 'image_memory_manager.dart';
import '../native/image/native_image_processor.dart';
import '../native/image/image_filter_params.dart';

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

  // 🖊️ Canvas-space strokes: rendered on top of overlapping images (PDF-like z-order)
  final List<ProStroke> canvasStrokes;

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

  // 🖼️ Micro-thumbnails for stubbed images (64px, ~16KB each)
  final Map<String, ui.Image> microThumbnails;

  // 🖼️ Per-image Picture cache (static, persists across frames)
  static final Map<String, _ImageCacheEntry> _perImageCache = {};

  // 🚀 Drag-specific content cache: stores image appearance (sans position)
  // so drag only needs canvas.translate() + drawPicture() per frame.
  static final Map<String, _ImageCacheEntry> _dragContentCache = {};

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

  // 🚀 PERF: Pre-allocated Paint objects for hot path (zero GC pressure)
  static final Paint _lodThumbFillPaint =
      Paint()
        ..color = const Color(0x206B8E6B)
        ..style = PaintingStyle.fill;
  static final Paint _lodThumbBorderPaint =
      Paint()
        ..color = const Color(0x406B8E6B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
  static final Paint _imageRenderPaint = Paint(); // filterQuality set per-use
  static final Paint _badgePillPaint = Paint()..color = const Color(0xDD1565C0);
  static final Paint _vignettePaint = Paint(); // shader set per-use

  ImagePainter({
    required this.images,
    required this.loadedImages,
    required this.selectedImage,
    required this.imageTool,
    this.canvasStrokes = const [],

    this.loadingPulse = 0.0,
    this.controller,
    this.imageVersion = 0,
    this.devicePixelRatio = 1.0,
    this.spatialIndex,
    this.memoryManager,
    this.microThumbnails = const {},
    ValueNotifier<int>? imageRepaintNotifier,
  }) : super(
         // 🚀 PERF: Do NOT listen to controller here.
         // Pan/zoom is handled by the parent Transform widget (GPU compositing).
         // Only repaint when images themselves change (via imageRepaintNotifier).
         repaint: imageRepaintNotifier,
       );

  @override
  void paint(Canvas canvas, Size size) {
    if (images.isEmpty) return;

    // 🚀 NOTE: Canvas transform (translate/scale/rotate) is now applied
    // by the parent Transform widget in the widget tree. ImagePainter
    // renders in CANVAS COORDINATES directly. This avoids re-rasterization
    // on every pan/zoom frame — the GPU composites the cached layer.

    // 🎯 Calculate viewport rect in canvas coordinates for culling
    Rect? viewportRect;
    if (controller != null) {
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

    // 🚀 3-TIER LOD: at very low zoom, draw images as colored rectangles
    // (consistent with stroke Tier 1 behavior — saves image decode + filter cost)
    final canvasScale = controller?.scale ?? 1.0;
    if (canvasScale < 0.2) {
      for (final img in visibleImages) {
        final image = loadedImages[img.imagePath];
        final w = image?.width.toDouble() ?? 200.0;
        final h = image?.height.toDouble() ?? 150.0;
        final rect = Rect.fromCenter(
          center: img.position,
          width: w * img.scale,
          height: h * img.scale,
        );
        if (rect.longestSide * canvasScale < 3.0) continue; // too small
        final r = (rect.shortestSide * 0.04).clamp(2.0, 12.0);
        final rrect = RRect.fromRectAndRadius(rect, Radius.circular(r));
        canvas.drawRRect(rrect, _lodThumbFillPaint);
        canvas.drawRRect(rrect, _lodThumbBorderPaint);
      }
      return;
    }

    // 🎨 Global dynamic flags
    const globalDynamic = false;

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

      // 🚀 Per-image dynamic check
      // ⚡ Check BOTH the build-time selectedImage AND the live imageTool.selectedImage.
      // When auto-selection happens during a gesture (shouldRouteToImageRotation),
      // the widget isn't rebuilt, so selectedImage is null. But imageTool has the
      // up-to-date selection.
      final isThisImageActive =
          selectedImage?.id == imageElement.id ||
          imageTool.selectedImage?.id == imageElement.id;
      final isDragging = isThisImageActive && imageTool.isDragging;
      final isResizing = isThisImageActive && imageTool.isResizing;
      final isRotating = isThisImageActive && imageTool.isRotating;
      final isThisImageDynamic = isDragging || isResizing || isRotating;

      // Per-image hash — includes canvas scale for LOD
      final imgHash = _computeImageHash(imageElement);

      // ======================================================================
      // 🚀 FAST PATH A: Drag — replay cached content picture at new position
      // During drag, only position changes. We cache the image's rendered
      // content (sans position transform) and replay it with just translate.
      // ======================================================================
      if (isDragging) {
        // 🚀 CRITICAL: use imageTool.selectedImage (always current) instead
        // of imageElement (stale R-tree reference with old position!)
        final liveImage = imageTool.selectedImage!;

        // Build content cache key without position (content doesn't change)
        final contentHash = _computeContentHash(liveImage);
        final cached = _dragContentCache[liveImage.id];
        ui.Picture contentPicture;

        if (cached != null && cached.version == contentHash) {
          // ⚡ Cache hit — skip full re-render
          contentPicture = cached.picture;
        } else {
          // 🎨 First drag frame: render content and cache it
          final r = ui.PictureRecorder();
          final c = Canvas(r);
          _renderImageContent(c, liveImage, image);
          contentPicture = r.endRecording();
          _dragContentCache[liveImage.id]?.dispose();
          _dragContentCache[liveImage.id] = _ImageCacheEntry(
            contentPicture,
            contentHash,
          );
        }

        // Replay at current position (just a translate — near-zero cost)
        canvas.save();
        canvas.translate(liveImage.position.dx, liveImage.position.dy);
        canvas.drawPicture(contentPicture);
        canvas.restore();

        // Selection overlay (handles need to track position)
        if (selectedImage?.id == liveImage.id || imageTool.selectedImage?.id == liveImage.id) {
          _drawSelection(canvas, liveImage, image);
        }
        continue;
      }

      // ======================================================================
      // 🚀 FAST PATH B: Resize — low FilterQuality for instant GPU scaling
      // ======================================================================
      if (isResizing) {
        // 🚀 CRITICAL: use live image (same fix as drag)
        final liveImage = imageTool.selectedImage!;
        _renderSingleImage(
          canvas,
          liveImage,
          image,
          filterQualityOverride: FilterQuality.none,
        );
        continue;
      }

      // ======================================================================
      // 🚀 FAST PATH C: Rotation — live image with current rotation angle
      // ======================================================================
      if (isRotating) {
        final liveImage = imageTool.selectedImage!;
        _renderSingleImage(canvas, liveImage, image);
        if (selectedImage?.id == liveImage.id || imageTool.selectedImage?.id == liveImage.id) {
          _drawSelection(canvas, liveImage, image);
        }
        continue;
      }

      // ======================================================================
      // STANDARD PATH: static images with Picture cache
      // ======================================================================
      if (!globalDynamic && !isThisImageActive) {
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
      if (!globalDynamic && !isThisImageActive) {
        _perImageCache[imageElement.id]?.dispose();
        _perImageCache[imageElement.id] = _ImageCacheEntry(picture, imgHash);
        canvas.drawPicture(picture);
      } else {
        // Dynamic: draw and discard
        canvas.drawPicture(picture);
        picture.dispose();
      }

      // 🧹 Clean up drag cache when drag ends (image returns to static path)
      if (!isDragging && _dragContentCache.containsKey(imageElement.id)) {
        _dragContentCache[imageElement.id]?.dispose();
        _dragContentCache.remove(imageElement.id);
      }
    }
  }

  /// 🧠 Compute a lightweight hash for per-image cache invalidation.
  /// Only invalidates when image properties actually change.
  /// 🚀 NOTE: canvas scale is NOT included — ImagePainter is inside
  /// RepaintBoundary + Transform, so GPU compositing handles zoom.
  /// LOD (FilterQuality) is applied at render time, not cached.
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
    return h;
  }

  /// 🚀 Content hash — same as image hash but WITHOUT position.
  /// Used for drag content cache: content doesn't change during drag.
  int _computeContentHash(ImageElement e) {
    var h = e.scale.hashCode;
    h = h * 31 + e.rotation.hashCode;
    h = h * 31 + e.opacity.hashCode;
    h =
        h * 31 +
        (e.brightness.hashCode ^
            e.contrast.hashCode ^
            e.saturation.hashCode ^
            e.hueShift.hashCode ^
            e.temperature.hashCode ^
            e.highlights.hashCode ^
            e.shadows.hashCode ^
            e.fade.hashCode ^
            e.vignette.hashCode);
    h = h * 31 + e.flipHorizontal.hashCode;
    h = h * 31 + e.flipVertical.hashCode;
    h = h * 31 + (e.cropRect?.hashCode ?? 0);
    h = h * 31 + e.drawingStrokes.length;
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
    ui.Image image, {
    FilterQuality? filterQualityOverride,
  }) {
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
    // 🐛 FIX: Use cached ORIGINAL dimensions for dstRect so visual size
    //    stays consistent across LOD swaps (thumbnail → full-res).
    //    srcRect always covers the entire decoded texture.
    final decodedW = image.width.toDouble();
    final decodedH = image.height.toDouble();
    final cachedSize = memoryManager?.getImageDimensions(
      imageElement.imagePath,
    );
    final originalW = cachedSize?.width ?? decodedW;
    final originalH = cachedSize?.height ?? decodedH;

    Rect srcRect;
    Rect dstRect;

    if (imageElement.cropRect != null) {
      final crop = imageElement.cropRect!;
      srcRect = Rect.fromLTRB(
        crop.left * decodedW,
        crop.top * decodedH,
        crop.right * decodedW,
        crop.bottom * decodedH,
      );
      // Use original proportions for dst so size doesn't jump
      dstRect = Rect.fromCenter(
        center: Offset.zero,
        width: crop.right * originalW - crop.left * originalW,
        height: crop.bottom * originalH - crop.top * originalH,
      );
    } else {
      srcRect = Rect.fromLTWH(0, 0, decodedW, decodedH);
      dstRect = Rect.fromCenter(
        center: Offset.zero,
        width: originalW,
        height: originalH,
      );
    }

    // 🎨 Create paint with LOD-adaptive FilterQuality (reuse static paint)
    _imageRenderPaint
      ..filterQuality =
          filterQualityOverride ?? _calculateLOD(imageElement, image)
      ..color = const Color(0xFFFFFFFF)
      ..colorFilter = null
      ..shader = null;
    final paint = _imageRenderPaint;

    // Apply opacity (Bug 2 fix: removed BlendMode.dstIn which made images invisible)
    if (imageElement.opacity < 1.0) {
      paint.color = Color.fromRGBO(255, 255, 255, imageElement.opacity);
    }

    // Apply color filter if there are modifications
    if (ImageAdjustmentEngine.needsColorMatrix(
      imageElement.colorAdjustments,
      imageElement.toneCurve,
      imageElement.lutIndex,
    )) {
      paint.colorFilter = ColorFilter.matrix(
        ImageAdjustmentEngine.computeColorMatrix(
          imageElement.colorAdjustments,
          toneCurve: imageElement.toneCurve,
          lutIndex: imageElement.lutIndex,
        ),
      );

      // 🎯 GPU fast-path: dispatch to native pipeline for real-time adjustments
      _dispatchGpuFilters(imageElement);
    }

    // Draw the image
    canvas.drawImageRect(image, srcRect, dstRect, paint);

    // Draw vignette overlay if active
    if (imageElement.vignette > 0) {
      _drawVignette(
        canvas,
        dstRect,
        imageElement.vignette,
        Color(imageElement.vignetteColor),
      );
    }

    // 🔍 GPU blur/sharpen post-processing
    if (imageElement.blurRadius > 0) {
      _dispatchGpuBlur(imageElement);
    }
    if (imageElement.sharpenAmount > 0) {
      _dispatchGpuSharpen(imageElement);
    }
    if (imageElement.edgeDetectStrength > 0) {
      _dispatchGpuEdgeDetect(imageElement);
    }
    if (imageElement.lutIndex > 0) {
      _dispatchGpuLut(imageElement);
    }

    // Restore state (end of image transform: translate → rotate → scale)
    canvas.restore();

    // 🎨 Draw image-attached strokes in translate + rotate space (NO scale).
    // 🐛 FIX: Strokes are stored in un-translated, un-rotated canvas space
    //    (NOT un-scaled) to preserve inter-point distances for velocity-based
    //    brushes (fountain pen, etc.). Rendering applies only translate + rotate.
    // 🖼️ Scale ratio: strokes scale proportionally when image is resized.
    //    At draw time, referenceScale == imageElement.scale → ratio = 1.0.
    //    After resize, ratio ≠ 1.0 → strokes scale with the image.
    if (imageElement.drawingStrokes.isNotEmpty) {
      canvas.save();
      canvas.translate(imageElement.position.dx, imageElement.position.dy);
      if (imageElement.rotation != 0) {
        canvas.rotate(imageElement.rotation);
      }
      // ✂️ Clip strokes to image bounds so ink doesn't bleed past the edge
      final clipW = originalW * imageElement.scale;
      final clipH = originalH * imageElement.scale;
      canvas.clipRect(
        Rect.fromCenter(center: Offset.zero, width: clipW, height: clipH),
      );
      for (final stroke in imageElement.drawingStrokes) {
        final scaleRatio = imageElement.scale / stroke.referenceScale;
        if (scaleRatio != 1.0) {
          canvas.save();
          canvas.scale(scaleRatio);
        }
        _drawStroke(canvas, stroke, 1.0);
        if (scaleRatio != 1.0) {
          canvas.restore();
        }
      }
      canvas.restore();
    }

    // 📝 Render text overlays on the image
    if (imageElement.textOverlays.isNotEmpty) {
      final w = image.width.toDouble() * imageElement.scale;
      final h = image.height.toDouble() * imageElement.scale;
      for (final t in imageElement.textOverlays) {
        final tp = TextPainter(
          text: TextSpan(
            text: t.text,
            style: TextStyle(
              fontSize: t.fontSize,
              color: Color(t.color).withValues(alpha: t.opacity),
              fontFamily: t.fontFamily,
              fontWeight: t.bold ? FontWeight.bold : FontWeight.normal,
              fontStyle: t.italic ? FontStyle.italic : FontStyle.normal,
              shadows:
                  t.shadowColor != 0
                      ? [
                        Shadow(
                          color: Color(t.shadowColor),
                          blurRadius: 4,
                          offset: const Offset(1, 1),
                        ),
                      ]
                      : null,
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        tp.layout();
        final tx = imageElement.position.dx + t.x * w - w / 2 - tp.width / 2;
        final ty = imageElement.position.dy + t.y * h - h / 2 - tp.height / 2;
        if (t.rotation != 0) {
          canvas.save();
          canvas.translate(tx + tp.width / 2, ty + tp.height / 2);
          canvas.rotate(t.rotation);
          tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
          canvas.restore();
        } else {
          tp.paint(canvas, Offset(tx, ty));
        }
        tp.dispose();
      }
    }

    // 🐛 FIX Bug 1: REMOVED canvas-space stroke overlay.
    // Previously this block iterated ALL canvasStrokes and drew any stroke
    // whose first point was inside imageRect ON TOP of the image. This caused
    // pre-existing canvas strokes to falsely appear on top when the image was
    // moved to their location. Image-attached strokes are already stored in
    // imageElement.drawingStrokes and rendered above.

    // Selection border
    if (selectedImage?.id == imageElement.id) {
      _drawSelection(canvas, imageElement, image);
    }
  }

  /// 🚀 Render image content WITHOUT position translate.
  /// Used by drag cache: the output Picture is position-independent
  /// and can be replayed at any position via canvas.translate().
  void _renderImageContent(
    Canvas canvas,
    ImageElement imageElement,
    ui.Image image,
  ) {
    canvas.save();

    // Apply rotation (no position translate!)
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

    // Perspective correction (keystone)
    // Perspective correction (via shared engine)
    ImageAdjustmentEngine.applyPerspective(canvas, imageElement.perspective);

    // Calculate dimensions (considering crop)
    // 🐛 FIX: Use cached ORIGINAL dimensions for dstRect (same as primary path)
    final decodedW = image.width.toDouble();
    final decodedH = image.height.toDouble();
    final cachedSize = memoryManager?.getImageDimensions(
      imageElement.imagePath,
    );
    final originalW = cachedSize?.width ?? decodedW;
    final originalH = cachedSize?.height ?? decodedH;

    Rect srcRect;
    Rect dstRect;

    if (imageElement.cropRect != null) {
      final crop = imageElement.cropRect!;
      srcRect = Rect.fromLTRB(
        crop.left * decodedW,
        crop.top * decodedH,
        crop.right * decodedW,
        crop.bottom * decodedH,
      );
      dstRect = Rect.fromCenter(
        center: Offset.zero,
        width: crop.right * originalW - crop.left * originalW,
        height: crop.bottom * originalH - crop.top * originalH,
      );
    } else {
      srcRect = Rect.fromLTWH(0, 0, decodedW, decodedH);
      dstRect = Rect.fromCenter(
        center: Offset.zero,
        width: originalW,
        height: originalH,
      );
    }

    // Paint with LOD (reuse static paint)
    _imageRenderPaint
      ..filterQuality = _calculateLOD(imageElement, image)
      ..color = const Color(0xFFFFFFFF)
      ..colorFilter = null
      ..shader = null;
    final paint = _imageRenderPaint;

    if (imageElement.opacity < 1.0) {
      paint.color = Color.fromRGBO(255, 255, 255, imageElement.opacity);
    }

    if (ImageAdjustmentEngine.needsColorMatrix(
      imageElement.colorAdjustments,
      imageElement.toneCurve,
      imageElement.lutIndex,
    )) {
      paint.colorFilter = ColorFilter.matrix(
        ImageAdjustmentEngine.computeColorMatrix(
          imageElement.colorAdjustments,
          toneCurve: imageElement.toneCurve,
          lutIndex: imageElement.lutIndex,
        ),
      );
      _dispatchGpuFilters(imageElement);
    }

    canvas.drawImageRect(image, srcRect, dstRect, paint);

    if (imageElement.vignette > 0) {
      _drawVignette(
        canvas,
        dstRect,
        imageElement.vignette,
        Color(imageElement.vignetteColor),
      );
    }

    // Gradient filter overlay (via shared engine)
    ImageAdjustmentEngine.drawGradientOverlay(
      canvas,
      dstRect,
      imageElement.gradientFilter,
    );

    // Noise reduction (via shared engine)
    ImageAdjustmentEngine.drawNoiseReduction(
      canvas,
      image,
      srcRect,
      dstRect,
      imageElement.noiseReduction,
    );

    if (imageElement.blurRadius > 0) {
      _dispatchGpuBlur(imageElement);
    }
    if (imageElement.sharpenAmount > 0) {
      _dispatchGpuSharpen(imageElement);
    }
    if (imageElement.edgeDetectStrength > 0) {
      _dispatchGpuEdgeDetect(imageElement);
    }
    if (imageElement.lutIndex > 0) {
      _dispatchGpuLut(imageElement);
    }

    // Restore image transform (translate → rotate → scale)
    canvas.restore();

    // 🐛 FIX: Render strokes in translate + rotate space (NO scale)
    //    to match the un-scaled coordinate conversion.
    if (imageElement.drawingStrokes.isNotEmpty) {
      canvas.save();
      // Note: _renderImageContent is called with translate already removed
      // (content is rendered relative to origin, then replayed with translate).
      // So we only need rotate here.
      if (imageElement.rotation != 0) {
        canvas.rotate(imageElement.rotation);
      }
      // ✂️ Clip strokes to image bounds so ink doesn't bleed past the edge
      final clipW = originalW * imageElement.scale;
      final clipH = originalH * imageElement.scale;
      canvas.clipRect(
        Rect.fromCenter(center: Offset.zero, width: clipW, height: clipH),
      );
      for (final stroke in imageElement.drawingStrokes) {
        final scaleRatio = imageElement.scale / stroke.referenceScale;
        if (scaleRatio != 1.0) {
          canvas.save();
          canvas.scale(scaleRatio);
        }
        _drawStroke(canvas, stroke, 1.0);
        if (scaleRatio != 1.0) {
          canvas.restore();
        }
      }
      canvas.restore();
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

  /// Draw vignette as a radial gradient overlay.
  void _drawVignette(
    Canvas canvas,
    Rect rect,
    double strength, [
    Color color = const Color(0xFF000000),
  ]) {
    final gradient = RadialGradient(
      center: Alignment.center,
      radius: 0.85,
      colors: [
        Colors.transparent,
        color.withValues(alpha: 0.35 * strength),
        color.withValues(alpha: 0.7 * strength),
      ],
      stops: const [0.3, 0.75, 1.0],
    );
    _vignettePaint.shader = gradient.createShader(rect);
    canvas.drawRect(rect, _vignettePaint);
  }

  // ─── GPU Dispatch (fire-and-forget from paint) ────────────────────────

  /// Dispatch color grading filter params to native GPU pipeline.
  /// Fire-and-forget: schedules GPU work asynchronously, CPU fallback
  /// (ColorFilter.matrix) is already applied above for immediate display.
  void _dispatchGpuFilters(ImageElement element) {
    final processor = NativeImageProcessor.instance;
    if (!processor.isAvailable) return;

    final params = ImageFilterParams.fromImageElement(element);
    // Fire-and-forget — GPU will re-render the texture asynchronously
    processor.applyFilters(element.id, params);
  }

  /// Dispatch Gaussian blur to native GPU pipeline.
  void _dispatchGpuBlur(ImageElement element) {
    final processor = NativeImageProcessor.instance;
    if (!processor.isAvailable) return;

    processor.applyBlur(element.id, element.blurRadius);
  }

  /// Dispatch unsharp mask (sharpen) to native GPU pipeline.
  void _dispatchGpuSharpen(ImageElement element) {
    final processor = NativeImageProcessor.instance;
    if (!processor.isAvailable) return;

    processor.applySharpen(element.id, element.sharpenAmount);
  }

  /// Dispatch Sobel edge detection to native GPU pipeline.
  void _dispatchGpuEdgeDetect(ImageElement element) {
    final processor = NativeImageProcessor.instance;
    if (!processor.isAvailable) return;

    processor.applyEdgeDetect(element.id, element.edgeDetectStrength);
  }

  /// Dispatch LUT color grading to native GPU pipeline.
  void _dispatchGpuLut(ImageElement element) {
    final processor = NativeImageProcessor.instance;
    if (!processor.isAvailable) return;

    processor.applyLut(element.id, element.lutIndex);
  }

  static double _cos(double x) {
    // Taylor approximation - good enough for color matrix
    x = x % 6.28318530718;
    if (x < 0) x += 6.28318530718;
    final x2 = x * x;
    return 1 - x2 / 2 + x2 * x2 / 24 - x2 * x2 * x2 / 720;
  }

  static double _sin(double x) {
    return _cos(x - 1.57079632679);
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

    // 🐛 FIX: Use cached original dimensions so selection matches visual size
    //    (image is rendered at originalW×originalH, not decodedW×decodedH).
    final cachedSize = memoryManager?.getImageDimensions(
      imageElement.imagePath,
    );
    final imageWidth = cachedSize?.width ?? image.width.toDouble();
    final imageHeight = cachedSize?.height ?? image.height.toDouble();

    // 🔧 Use cropped dimensions when cropRect is set
    final visibleWidth =
        imageElement.cropRect != null
            ? (imageElement.cropRect!.right - imageElement.cropRect!.left) *
                imageWidth
            : imageWidth;
    final visibleHeight =
        imageElement.cropRect != null
            ? (imageElement.cropRect!.bottom - imageElement.cropRect!.top) *
                imageHeight
            : imageHeight;

    final scaledWidth = visibleWidth * imageElement.scale;
    final scaledHeight = visibleHeight * imageElement.scale;

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

    // 🌀 Rotation Handle (Stick + Circle)
    final topCenter = Offset(0, -scaledHeight / 2);
    final handleCenter =
        topCenter + const Offset(0, -ImageTool.rotationHandleDistance);

    canvas.drawLine(topCenter, handleCenter, _selectionBorderPaint);
    canvas.drawCircle(handleCenter, 6.0, _handleFillPaint);
    canvas.drawCircle(handleCenter, 6.0, _handleBorderPaint);

    // 📐 ANGLE INDICATOR: Show rotation angle badge during rotation
    if (imageTool.isRotating && imageElement.rotation != 0.0) {
      // Undo image rotation for the badge (keep it horizontal)
      canvas.rotate(-imageElement.rotation);

      final degrees = (imageElement.rotation * 180.0 / 3.141592653589793) % 360;
      final displayDegrees = degrees > 180 ? degrees - 360 : degrees;
      final angleText = '${displayDegrees.toStringAsFixed(1)}°';

      final tp = TextPainter(
        text: TextSpan(
          text: angleText,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      // Pill badge above the image
      final badgeWidth = tp.width + 16;
      final badgeHeight = tp.height + 8;
      final badgeRect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(0, rect.top - 28),
          width: badgeWidth,
          height: badgeHeight,
        ),
        const Radius.circular(12),
      );

      canvas.drawRRect(badgeRect, _badgePillPaint);
      tp.paint(canvas, Offset(-tp.width / 2, rect.top - 28 - tp.height / 2));
      tp.dispose();
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

    final imageWidth = image.width.toDouble();
    final imageHeight = image.height.toDouble();

    // 🔧 Use cropped dimensions when cropRect is set
    final visibleWidth =
        imageElement.cropRect != null
            ? (imageElement.cropRect!.right - imageElement.cropRect!.left) *
                imageWidth
            : imageWidth;
    final visibleHeight =
        imageElement.cropRect != null
            ? (imageElement.cropRect!.bottom - imageElement.cropRect!.top) *
                imageHeight
            : imageHeight;

    final scaledWidth = visibleWidth * imageElement.scale;
    final scaledHeight = visibleHeight * imageElement.scale;

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

    // 🎨 Use unified BrushEngine for consistent rendering with
    // DrawingPainter and CurrentStrokePainter — eliminates visual
    // mismatch between live and finalized strokes on images.
    // 🐛 FIX: Pass isLive: true so rendering matches CurrentStrokePainter
    //    (same saveLayer bounds, same point decimation, same texture path).
    //    Without this, finalized strokes use different quality settings
    //    that produce a visible "shrink" on pointer-up.
    BrushEngine.renderStroke(
      canvas,
      stroke.points,
      stroke.color,
      stroke.baseWidth / scale,
      stroke.penType,
      stroke.settings,
      isLive: true,
    );
  }

  /// 🖊️ Compute axis-aligned bounding box of image in canvas space.
  Rect _getImageCanvasBounds(ImageElement imageElement, ui.Image image) {
    final crop = imageElement.cropRect;
    final double w, h;
    if (crop != null) {
      w = (crop.right - crop.left) * image.width;
      h = (crop.bottom - crop.top) * image.height;
    } else {
      w = image.width.toDouble();
      h = image.height.toDouble();
    }
    final halfW = w * imageElement.scale / 2;
    final halfH = h * imageElement.scale / 2;
    return Rect.fromCenter(
      center: imageElement.position,
      width: halfW * 2,
      height: halfH * 2,
    );
  }

  /// 🖊️ Check if a stroke STARTED inside the image (intent-based).
  /// Only strokes that begin on the image appear on top — strokes drawn
  /// on blank canvas that happen to pass near the image stay below.
  bool _strokeStartedOnImage(ProStroke stroke, Rect imageRect) {
    if (stroke.points.isEmpty) return false;
    return imageRect.contains(stroke.points.first.position);
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

    // 🖼️ Try micro-thumbnail for stubbed images (Improvement 2)
    final microThumb = microThumbnails[imageElement.id];
    if (microThumb != null) {
      _drawMicroThumbnail(canvas, imageElement, microThumb);
      return;
    }

    // ✅ No micro-thumbnail — show generic placeholder
    final cachedSize = memoryManager?.getImageDimensions(
      imageElement.imagePath,
    );
    final placeholderWidth = cachedSize?.width ?? 200.0;
    final placeholderHeight = cachedSize?.height ?? 150.0;
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

  /// 🖼️ Draw a blurred micro-thumbnail for stubbed images.
  ///
  /// Instead of a generic "Downloading..." spinner, stubbed images show
  /// a tiny (64px) thumbnail scaled up with bilinear filtering.
  /// This keeps the canvas feeling populated — like Google Maps low-res tiles.
  void _drawMicroThumbnail(
    Canvas canvas,
    ImageElement imageElement,
    ui.Image thumbnail,
  ) {
    // Get target size from cached dimensions (or use thumbnail size × 4)
    final cachedSize = memoryManager?.getImageDimensions(
      imageElement.imagePath,
    );
    final targetW = cachedSize?.width ?? thumbnail.width * 4.0;
    final targetH = cachedSize?.height ?? thumbnail.height * 4.0;

    final destRect = Rect.fromCenter(
      center: Offset.zero,
      width: targetW,
      height: targetH,
    );
    final srcRect = Rect.fromLTWH(
      0,
      0,
      thumbnail.width.toDouble(),
      thumbnail.height.toDouble(),
    );

    // Draw thumbnail with low-quality filter (intentionally blurry — it's a preview)
    final paint =
        Paint()
          ..filterQuality = FilterQuality.low
          ..color = const Color(0xDDFFFFFF); // slightly faded

    // Clip to rounded rect
    final rrect = RRect.fromRectAndRadius(destRect, const Radius.circular(8));
    canvas.save();
    canvas.clipRRect(rrect);

    // Draw the scaled-up micro thumbnail
    canvas.drawImageRect(thumbnail, srcRect, destRect, paint);

    // Subtle dark overlay to signal "loading"
    canvas.drawRect(destRect, Paint()..color = const Color(0x20000000));

    canvas.restore();

    // Subtle border
    _placeholderBorderPaint.color = const Color(0x30FFFFFF);
    canvas.drawRRect(rrect, _placeholderBorderPaint);

    // Note: canvas.restore() for position/rotation/scale is done by the caller
    // (_drawLoadingPlaceholder's save/restore wraps both paths)
    canvas.restore(); // Match the save() from _drawLoadingPlaceholder
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

    // Version counter: single integer comparison replaces expensive list checks
    if (imageVersion != oldDelegate.imageVersion) return true;

    // 🚀 Improvement 5: identity check detects new image loads (same count, different map)
    return selectedImage != oldDelegate.selectedImage ||
        !identical(loadedImages, oldDelegate.loadedImages) ||
        !identical(canvasStrokes, oldDelegate.canvasStrokes) ||
        loadingPulse != oldDelegate.loadingPulse;
  }
}
