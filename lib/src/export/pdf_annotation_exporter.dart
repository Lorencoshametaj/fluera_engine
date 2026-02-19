import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import '../core/nodes/pdf_document_node.dart';
import '../core/nodes/pdf_page_node.dart';
import '../core/models/canvas_layer.dart';
import '../drawing/brushes/brush_engine.dart';

// =============================================================================
// 📤 PDF ANNOTATION EXPORTER — Renders PDF pages with annotations flattened
// =============================================================================

/// Result of exporting a single annotated page.
class AnnotatedPageResult {
  /// The page index (0-based).
  final int pageIndex;

  /// PNG bytes of the rendered page with annotations.
  final Uint8List bytes;

  /// Pixel dimensions of the output image.
  final ui.Size pixelSize;

  const AnnotatedPageResult({
    required this.pageIndex,
    required this.bytes,
    required this.pixelSize,
  });
}

/// Result of exporting an entire annotated PDF document.
class AnnotatedPdfExportResult {
  /// Per-page export results, ordered by page index.
  final List<AnnotatedPageResult> pages;

  /// Total export time in milliseconds.
  final int elapsedMs;

  /// Number of pages that had annotations.
  final int annotatedPageCount;

  /// Page indices that failed to render (GPU OOM, etc).
  final List<int> failedPageIndices;

  /// Whether the export was cancelled via [isCancelled].
  final bool wasCancelled;

  const AnnotatedPdfExportResult({
    required this.pages,
    required this.elapsedMs,
    required this.annotatedPageCount,
    this.failedPageIndices = const [],
    this.wasCancelled = false,
  });

  /// Whether the export was successful (at least one page).
  bool get isSuccess => pages.isNotEmpty;

  /// Whether any pages failed to render.
  bool get hasFailures => failedPageIndices.isNotEmpty;
}

/// Exports PDF pages with annotations flattened into raster images.
///
/// For each page:
/// 1. Draws the cached PDF page image as background
/// 2. Overlays annotation strokes clipped to the page bounds
/// 3. Exports as PNG at the specified pixel ratio
///
/// DESIGN: Annotations are "flattened" — they become part of the page
/// image and can no longer be edited. This is ideal for sharing/printing.
class PdfAnnotationExporter {
  /// Pixel ratio for export quality (2.0 = retina, 3.0 = high-DPI).
  final double pixelRatio;

  /// Effective pixel ratio, clamped to [0.5, 8.0] to prevent zero/negative
  /// values causing crashes in `toImage`.
  double get effectivePixelRatio => pixelRatio.clamp(0.5, 8.0);

  /// Optional progress callback: (currentPage, totalPages).
  final void Function(int current, int total)? onProgress;

  /// Whether to include annotations even if page has showAnnotations=false.
  /// Default true — for export, all annotations should be flattened.
  final bool includeHiddenAnnotations;

  const PdfAnnotationExporter({
    this.pixelRatio = 2.0,
    this.onProgress,
    this.includeHiddenAnnotations = true,
  });

  // G3: Pre-allocated paints for export (avoid per-call alloc)
  static final ui.Paint _whiteBgPaint =
      ui.Paint()..color = const ui.Color(0xFFFFFFFF);
  static final ui.Paint _imagePaint = ui.Paint();

  // ---------------------------------------------------------------------------
  // Export entire document
  // ---------------------------------------------------------------------------

  /// Export all pages of a PDF document with annotations flattened.
  ///
  /// Returns [AnnotatedPdfExportResult] with PNG bytes per page.
  /// Pages without annotations still get exported (as clean page images).
  Future<AnnotatedPdfExportResult> exportDocument(
    PdfDocumentNode doc, {
    List<CanvasLayer>? layers,
    bool onlyAnnotatedPages = false,

    /// Optional cancellation check — return true to abort export.
    bool Function()? isCancelled,
  }) async {
    final sw = Stopwatch()..start();
    final results = <AnnotatedPageResult>[];
    final failedIndices = <int>[];
    int annotatedCount = 0;
    bool cancelled = false;

    final pages = doc.pageNodes;
    final total = pages.length;

    for (int i = 0; i < total; i++) {
      // Check for cancellation before each page
      if (isCancelled != null && isCancelled()) {
        debugPrint('[PDF Export] Cancelled after $i/$total pages');
        cancelled = true;
        break;
      }

      final page = pages[i];
      final hasAnnotations = page.pageModel.annotations.isNotEmpty;

      if (onlyAnnotatedPages && !hasAnnotations) {
        onProgress?.call(i + 1, total);
        continue;
      }

      if (hasAnnotations) annotatedCount++;

      final result = await exportPage(page, doc: doc, layers: layers);
      if (result != null) {
        results.add(result);
      } else {
        failedIndices.add(page.pageModel.pageIndex);
      }

      onProgress?.call(i + 1, total);
    }

    sw.stop();
    debugPrint(
      '[PDF Export] ${results.length} pages in ${sw.elapsedMilliseconds}ms '
      '($annotatedCount with annotations, ${failedIndices.length} failed)',
    );

    return AnnotatedPdfExportResult(
      pages: results,
      elapsedMs: sw.elapsedMilliseconds,
      annotatedPageCount: annotatedCount,
      failedPageIndices: failedIndices,
      wasCancelled: cancelled,
    );
  }

  // ---------------------------------------------------------------------------
  // Export single page
  // ---------------------------------------------------------------------------

  /// Export a single PDF page with its annotations flattened.
  ///
  /// Returns null if the page has no cached image (not yet rendered).
  Future<AnnotatedPageResult?> exportPage(
    PdfPageNode page, {
    PdfDocumentNode? doc,
    List<CanvasLayer>? layers,
  }) async {
    final pageSize = page.pageModel.originalSize;
    final ratio = effectivePixelRatio;
    final pixelWidth = (pageSize.width * ratio).ceil();
    final pixelHeight = (pageSize.height * ratio).ceil();

    if (pixelWidth <= 0 || pixelHeight <= 0) return null;

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
      recorder,
      ui.Rect.fromLTWH(0, 0, pixelWidth.toDouble(), pixelHeight.toDouble()),
    );

    // Scale for pixel ratio
    canvas.scale(ratio);

    // 🔄 Apply page rotation around center (matches DrawingPainter)
    final rotation = page.pageModel.rotation;
    if (rotation != 0) {
      final cx = pageSize.width / 2;
      final cy = pageSize.height / 2;
      canvas.translate(cx, cy);
      canvas.rotate(rotation);
      canvas.translate(-cx, -cy);
    }

    // 1. White background
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, pageSize.width, pageSize.height),
      _whiteBgPaint,
    );

    // 2. Draw cached PDF page image (scaled to fill page)
    if (page.cachedImage != null) {
      final srcRect = ui.Rect.fromLTWH(
        0,
        0,
        page.cachedImage!.width.toDouble(),
        page.cachedImage!.height.toDouble(),
      );
      final dstRect = ui.Rect.fromLTWH(0, 0, pageSize.width, pageSize.height);
      canvas.drawImageRect(page.cachedImage!, srcRect, dstRect, _imagePaint);
    }

    // 3. Overlay annotations clipped to page bounds
    //    includeHiddenAnnotations=true → export ALL annotations, ignoring visibility
    final annotations = page.pageModel.annotations;
    final shouldRenderAnnotations =
        annotations.isNotEmpty &&
        layers != null &&
        (includeHiddenAnnotations || page.pageModel.showAnnotations);

    if (shouldRenderAnnotations) {
      final pagePos = page.position;
      canvas.save();
      canvas.clipRect(ui.Rect.fromLTWH(0, 0, pageSize.width, pageSize.height));

      // Translate strokes from canvas-space to page-local-space
      canvas.translate(-pagePos.dx, -pagePos.dy);

      final idSet = annotations.toSet();
      for (final layer in layers) {
        if (!layer.isVisible) continue;
        for (final stroke in layer.strokes) {
          if (idSet.contains(stroke.id)) {
            if (!stroke.isFill) {
              BrushEngine.renderStroke(
                canvas,
                stroke.points,
                stroke.color,
                stroke.baseWidth,
                stroke.penType,
                stroke.settings,
              );
            }
          }
        }
      }

      canvas.restore();
    }

    // 4. Encode to PNG (try/catch: toImage can fail on GPU OOM)
    try {
      final picture = recorder.endRecording();
      final image = await picture.toImage(pixelWidth, pixelHeight);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      picture.dispose();
      image.dispose();

      if (byteData == null) return null;

      return AnnotatedPageResult(
        pageIndex: page.pageModel.pageIndex,
        bytes: byteData.buffer.asUint8List(),
        pixelSize: ui.Size(pixelWidth.toDouble(), pixelHeight.toDouble()),
      );
    } catch (e) {
      debugPrint('[PDF Export] Page ${page.pageModel.pageIndex} failed: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Calculate inflated bounds for a rotated rect (for culling).
  static ui.Rect inflatedBoundsForRotation(ui.Rect rect, double rotation) {
    final cx = rect.center.dx;
    final cy = rect.center.dy;
    final cos = math.cos(rotation).abs();
    final sin = math.sin(rotation).abs();
    final newW = rect.width * cos + rect.height * sin;
    final newH = rect.width * sin + rect.height * cos;
    return ui.Rect.fromCenter(
      center: ui.Offset(cx, cy),
      width: newW,
      height: newH,
    );
  }
}
