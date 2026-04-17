import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../canvas/fluera_canvas_config.dart';
import '../drawing/models/pro_drawing_point.dart';
import 'image_vectorizer.dart';
import 'pdf_ink_extractor.dart';
import 'svg_stroke_converter.dart';
import 'stroke_import_models.dart';

/// Orchestrates importing notes from external sources (PDF, SVG, image)
/// and converting them into [ProStroke] objects.
///
/// Usage:
/// ```dart
/// final controller = NoteImportController(pdfProvider: config.pdfProvider);
/// final result = await controller.importFromPdf(
///   bytes,
///   insertPosition: Offset(100, 100),
///   onProgress: (p) => print('${p.phase} (${p.currentPage}/${p.totalPages})'),
/// );
/// // result.strokes contains ProStroke objects ready for the scene graph
/// ```
class NoteImportController {
  final FlueraPdfProvider? _pdfProvider;

  NoteImportController({FlueraPdfProvider? pdfProvider})
      : _pdfProvider = pdfProvider;

  /// Import strokes from a PDF file.
  ///
  /// Pipeline:
  /// 1. Try to extract vector ink annotations (fast path, rare)
  /// 2. Render each page as an image
  /// 3. Vectorize the rasterized handwriting via [ImageVectorizer]
  ///
  /// Returns combined strokes from both ink annotations and raster vectorization.
  Future<NoteImportResult> importFromPdf(
    Uint8List bytes, {
    Offset insertPosition = Offset.zero,
    ImportProgressCallback? onProgress,
  }) async {
    final allStrokes = <ProStroke>[];

    // Level 1: Try PDF ink annotation extraction (best-effort)
    onProgress?.call(const ImportProgress(
      currentPage: 0,
      totalPages: 1,
      phase: 'Checking ink annotations...',
    ));

    final inkStrokes = PdfInkExtractor.extract(
      bytes,
      offset: insertPosition,
    );
    allStrokes.addAll(inkStrokes);

    // Level 3: Render pages and vectorize raster content
    if (_pdfProvider == null) {
      return NoteImportResult(
        strokes: allStrokes,
        sourceType:
            inkStrokes.isNotEmpty
                ? ImportSourceType.pdfInk
                : ImportSourceType.rasterized,
        pagesProcessed: 0,
      );
    }

    final loaded = await _pdfProvider.loadDocument(bytes);
    if (!loaded) {
      return NoteImportResult(
        strokes: allStrokes,
        sourceType: ImportSourceType.pdfInk,
      );
    }

    final pageCount = _pdfProvider.pageCount;

    for (int i = 0; i < pageCount; i++) {
      onProgress?.call(ImportProgress(
        currentPage: i + 1,
        totalPages: pageCount,
        phase: 'Vectorizing page ${i + 1}...',
      ));

      final pageSize = _pdfProvider.pageSize(i);
      if (pageSize == Size.zero) continue;

      // Render at 2x for quality (typical PDF is 72dpi, we want ~150dpi)
      const renderScale = 2.0;
      final targetSize = Size(
        pageSize.width * renderScale,
        pageSize.height * renderScale,
      );

      final uiImage = await _pdfProvider.renderPage(
        pageIndex: i,
        scale: renderScale,
        targetSize: targetSize,
      );
      if (uiImage == null) continue;

      // Convert ui.Image to raw RGBA bytes (avoid PNG encode/decode overhead)
      final rgbaData = await _uiImageToRgba(uiImage);
      if (rgbaData == null) continue;
      final imageBytes = rgbaData.bytes;
      final imageWidth = rgbaData.width;
      final imageHeight = rgbaData.height;

      // Stack pages vertically (single column — notes read top-to-bottom)
      const spacing = 20.0;
      final pageOffset = Offset(
        insertPosition.dx,
        insertPosition.dy + i * (pageSize.height + spacing),
      );

      // Run vectorization in isolate for performance
      final pageStrokes = await compute(
        _vectorizeInIsolate,
        _VectorizeParams(
          imageBytes: imageBytes,
          width: imageWidth,
          height: imageHeight,
          isRawRgba: true,
          offset: pageOffset,
          scale: 1.0 / renderScale, // Scale back to PDF points
        ),
      );

      allStrokes.addAll(pageStrokes);
    }

    return NoteImportResult(
      strokes: allStrokes,
      sourceType: ImportSourceType.rasterized,
      pagesProcessed: pageCount,
    );
  }

  /// Import strokes from a raster image (PNG, JPEG, WebP).
  Future<NoteImportResult> importFromImage(
    Uint8List bytes, {
    Offset insertPosition = Offset.zero,
    ImportProgressCallback? onProgress,
  }) async {
    onProgress?.call(const ImportProgress(
      currentPage: 1,
      totalPages: 1,
      phase: 'Vectorizing image...',
    ));

    final strokes = await compute(
      _vectorizeInIsolate,
      _VectorizeParams(
        imageBytes: bytes,
        offset: insertPosition,
        scale: 1.0,
      ),
    );

    return NoteImportResult(
      strokes: strokes,
      sourceType: ImportSourceType.rasterized,
    );
  }

  /// Import strokes from an SVG file.
  NoteImportResult importFromSvg(
    String svgContent, {
    Offset insertPosition = Offset.zero,
  }) {
    final strokes = SvgStrokeConverter.convert(
      svgContent,
      offset: insertPosition,
    );

    return NoteImportResult(
      strokes: strokes,
      sourceType: ImportSourceType.svgPath,
    );
  }

  /// Detect the source type from file extension.
  static ImportSourceType detectType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.pdf')) return ImportSourceType.rasterized;
    if (lower.endsWith('.svg')) return ImportSourceType.svgPath;
    return ImportSourceType.rasterized; // PNG, JPEG, etc.
  }

  /// Convert a [ui.Image] to raw RGBA bytes (no PNG encode overhead).
  static Future<_RgbaData?> _uiImageToRgba(ui.Image image) async {
    final byteData = await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    if (byteData == null) return null;
    return _RgbaData(
      bytes: byteData.buffer.asUint8List(),
      width: image.width,
      height: image.height,
    );
  }
}

class _RgbaData {
  final Uint8List bytes;
  final int width;
  final int height;
  const _RgbaData({required this.bytes, required this.width, required this.height});
}

/// Parameters for isolate-based vectorization.
class _VectorizeParams {
  final Uint8List imageBytes;
  final int width;
  final int height;
  final bool isRawRgba;
  final Offset offset;
  final double scale;

  const _VectorizeParams({
    required this.imageBytes,
    this.width = 0,
    this.height = 0,
    this.isRawRgba = false,
    required this.offset,
    required this.scale,
  });
}

/// Top-level function for compute() — runs ImageVectorizer in an isolate.
List<ProStroke> _vectorizeInIsolate(_VectorizeParams params) {
  final img.Image? image;

  if (params.isRawRgba && params.width > 0 && params.height > 0) {
    // Fast path: construct Image directly from raw RGBA — no decode needed
    image = img.Image.fromBytes(
      width: params.width,
      height: params.height,
      bytes: params.imageBytes.buffer,
      numChannels: 4,
    );
  } else {
    // Fallback: decode from encoded format (PNG/JPEG for direct image import)
    image = img.decodeImage(params.imageBytes);
  }
  if (image == null) return const [];

  return ImageVectorizer.vectorize(
    image,
    offset: params.offset,
    scale: params.scale,
  );
}
