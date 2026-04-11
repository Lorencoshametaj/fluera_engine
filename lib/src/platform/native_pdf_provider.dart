import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import '../canvas/fluera_canvas_config.dart';
import '../core/models/ocr_result.dart';
import '../core/models/pdf_text_rect.dart';
import '../rendering/canvas/pdf_texture_tile.dart';

/// 📄 Native PDF rendering provider — zero third-party dependencies.
///
/// Uses platform method channels to call:
/// - **iOS**: `PDFKit` (Apple native)
/// - **Android**: `android.graphics.pdf.PdfRenderer`
///
/// Supports two rendering paths:
/// 1. **Texture path (zero-copy)**: Uses TextureRegistry to share GPU textures
///    directly between native and Flutter. No pixel data crosses the
///    MethodChannel. ~5-8ms faster per tile.
/// 2. **Pixel path (legacy fallback)**: Transfers raw RGBA `Uint8List` via
///    MethodChannel and decodes into `ui.Image` using `decodeImageFromPixels`.
///
/// Supports multiple simultaneous documents via `documentId`. Each instance
/// of this class manages a single document; the native side stores multiple
/// documents keyed by ID.
///
/// Usage:
/// ```dart
/// final provider = NativeFlueraPdfProvider(documentId: 'doc_123');
/// final config = FlueraCanvasConfig(
///   pdfProvider: provider,
///   // ...
/// );
/// ```
class NativeFlueraPdfProvider implements FlueraPdfProvider {
  static const MethodChannel _channel = MethodChannel(
    'com.flueraengine/pdf_renderer',
  );

  /// Unique identifier for this document on the native side.
  final String documentId;

  int _pageCount = 0;
  final Map<int, Size> _pageSizeCache = {};
  bool _isDisposed = false;

  /// Whether the texture path is available on this platform.
  /// Set after the first attempt — avoids repeated failures.
  bool? _texturePathAvailable;

  NativeFlueraPdfProvider({required this.documentId});

  // ===========================================================================
  // Load Document
  // ===========================================================================

  @override
  Future<bool> loadDocument(List<int> bytes) async {
    if (_isDisposed) return false;

    try {
      final result = await _channel.invokeMethod<Map>('loadDocument', {
        'documentId': documentId,
        'bytes': Uint8List.fromList(bytes),
      });

      if (result == null) return false;

      final success = result['success'] as bool? ?? false;
      _pageCount = result['pageCount'] as int? ?? 0;
      _pageSizeCache.clear();

      // Pre-cache all page sizes from native response
      final pageSizes = result['pageSizes'] as List?;
      if (pageSizes != null) {
        for (int i = 0; i < pageSizes.length; i++) {
          final sizeMap = pageSizes[i] as Map;
          final w = (sizeMap['width'] as num?)?.toDouble() ?? 0.0;
          final h = (sizeMap['height'] as num?)?.toDouble() ?? 0.0;
          _pageSizeCache[i] = Size(w, h);
        }
      }

      return success && _pageCount > 0;
    } catch (e) {
      return false;
    }
  }

  // ===========================================================================
  // Page Info
  // ===========================================================================

  @override
  int get pageCount => _pageCount;

  @override
  Size pageSize(int pageIndex) {
    if (pageIndex < 0 || pageIndex >= _pageCount) return Size.zero;
    return _pageSizeCache[pageIndex] ?? Size.zero;
  }

  /// Async version that fetches page size from native side.
  Future<Size> pageSizeAsync(int pageIndex) async {
    if (_isDisposed || pageIndex < 0 || pageIndex >= _pageCount) {
      return Size.zero;
    }

    if (_pageSizeCache.containsKey(pageIndex)) {
      return _pageSizeCache[pageIndex]!;
    }

    try {
      final result = await _channel.invokeMethod<Map>('getPageSize', {
        'documentId': documentId,
        'pageIndex': pageIndex,
      });

      if (result == null) return Size.zero;

      final width = (result['width'] as num?)?.toDouble() ?? 0.0;
      final height = (result['height'] as num?)?.toDouble() ?? 0.0;
      final size = Size(width, height);

      _pageSizeCache[pageIndex] = size;
      return size;
    } catch (e) {
      return Size.zero;
    }
  }

  // ===========================================================================
  // Render Page → ui.Image (legacy pixel path)
  // ===========================================================================

  @override
  Future<ui.Image?> renderPage({
    required int pageIndex,
    required double scale,
    required Size targetSize,
  }) async {
    if (_isDisposed || pageIndex < 0 || pageIndex >= _pageCount) return null;

    final targetWidth = targetSize.width.toInt();
    final targetHeight = targetSize.height.toInt();

    if (targetWidth <= 0 || targetHeight <= 0) return null;

    try {
      final result = await _channel.invokeMethod<Map>('renderPage', {
        'documentId': documentId,
        'pageIndex': pageIndex,
        'targetWidth': targetWidth,
        'targetHeight': targetHeight,
      });

      if (result == null) return null;

      final width = result['width'] as int;
      final height = result['height'] as int;
      final pixels = result['pixels'] as Uint8List;

      // Decode raw RGBA pixels into ui.Image
      return _decodePixels(pixels, width, height);
    } catch (e) {
      return null;
    }
  }

  /// Decode raw RGBA pixel buffer into a `ui.Image`.
  ///
  /// Pixels arrive as RGBA from the native side (Android's PdfRendererPlugin
  /// already performs the ARGB→RGBA swizzle in Kotlin).
  Future<ui.Image> _decodePixels(Uint8List pixels, int width, int height) {
    final completer = Completer<ui.Image>();

    ui.decodeImageFromPixels(pixels, width, height, ui.PixelFormat.rgba8888, (
      ui.Image image,
    ) {
      completer.complete(image);
    });

    return completer.future;
  }

  // ===========================================================================
  // Render Page → Texture (zero-copy fast path)
  // ===========================================================================

  /// 🚀 Zero-copy PDF page rendering via TextureRegistry.
  ///
  /// Returns a [PdfTextureTile] containing the Flutter texture ID.
  /// The texture is rendered natively (SurfaceProducer on Android,
  /// CVPixelBuffer on iOS) without any pixel data crossing the
  /// MethodChannel boundary.
  ///
  /// Returns `null` if:
  /// - The platform doesn't support TextureRegistry
  /// - The render failed
  /// - The provider is disposed
  ///
  /// The caller must call [releaseTexture] when the tile is no longer needed.
  @override
  Future<PdfTextureTile?> renderPageTexture({
    required int pageIndex,
    required double scale,
    required Size targetSize,
  }) async {
    if (_isDisposed || pageIndex < 0 || pageIndex >= _pageCount) return null;

    // If we already know the texture path isn't available, skip
    if (_texturePathAvailable == false) return null;

    final targetWidth = targetSize.width.toInt();
    final targetHeight = targetSize.height.toInt();

    if (targetWidth <= 0 || targetHeight <= 0) return null;

    try {
      final result = await _channel.invokeMethod<Map>('renderPageTexture', {
        'documentId': documentId,
        'pageIndex': pageIndex,
        'targetWidth': targetWidth,
        'targetHeight': targetHeight,
      });

      if (result == null) {
        // Mark texture path as unavailable on first failure
        _texturePathAvailable ??= false;
        return null;
      }

      _texturePathAvailable = true;

      final textureId = (result['textureId'] as num).toInt();
      final width = result['width'] as int;
      final height = result['height'] as int;

      return PdfTextureTile(
        textureId: textureId,
        width: width,
        height: height,
      );
    } catch (e) {
      _texturePathAvailable ??= false;
      return null;
    }
  }

  /// Release a native texture by its ID.
  Future<void> releaseTexture(int textureId) async {
    if (_isDisposed) return;
    try {
      await _channel.invokeMethod('releaseTexture', {
        'textureId': textureId,
      });
    } catch (_) {
      // Fire-and-forget: native cleanup might fail if engine detached
    }
  }

  // ===========================================================================
  // Render Thumbnail — fast low-res preview
  // ===========================================================================

  /// 🖼️ Render a low-resolution thumbnail for instant page preview.
  ///
  /// Uses platform-optimized APIs:
  /// - **iOS**: `PDFPage.thumbnail(of:for:)` — ~10x faster than full render
  /// - **Android**: Low-res PdfRenderer render (~200px wide)
  ///
  /// Returns a small `ui.Image` suitable for placeholders while the
  /// full-LOD render is in progress.
  @override
  Future<ui.Image?> renderThumbnail(int pageIndex) async {
    if (_isDisposed || pageIndex < 0 || pageIndex >= _pageCount) return null;

    try {
      final result = await _channel.invokeMethod<Map>('renderThumbnail', {
        'documentId': documentId,
        'pageIndex': pageIndex,
      });

      if (result == null) return null;

      final width = result['width'] as int;
      final height = result['height'] as int;
      final pixels = result['pixels'] as Uint8List;

      // Thumbnails are small (~200x280), so pixel transfer is negligible
      return _decodePixels(pixels, width, height);
    } catch (e) {
      return null;
    }
  }

  // ===========================================================================
  // Text Extraction
  // ===========================================================================

  @override
  Future<List<PdfTextRect>> extractTextGeometry(int pageIndex) async {
    if (_isDisposed || pageIndex < 0 || pageIndex >= _pageCount) return [];

    try {
      final result = await _channel.invokeMethod<List>('extractText', {
        'documentId': documentId,
        'pageIndex': pageIndex,
      });

      if (result == null || result.isEmpty) return [];

      return result.map((item) {
        final map = Map<String, dynamic>.from(item as Map);
        return PdfTextRect(
          rect: Rect.fromLTWH(
            (map['x'] as num).toDouble(),
            (map['y'] as num).toDouble(),
            (map['width'] as num).toDouble(),
            (map['height'] as num).toDouble(),
          ),
          text: map['text'] as String? ?? '',
          charOffset: map['charOffset'] as int? ?? 0,
        );
      }).toList();
    } catch (e) {
      return [];
    }
  }

  @override
  Future<String> getPageText(int pageIndex) async {
    if (_isDisposed || pageIndex < 0 || pageIndex >= _pageCount) return '';

    try {
      final result = await _channel.invokeMethod<String>('getPageText', {
        'documentId': documentId,
        'pageIndex': pageIndex,
      });
      return result ?? '';
    } catch (e) {
      return '';
    }
  }

  // ===========================================================================
  // OCR — Native text recognition for scanned/image-based PDFs
  // ===========================================================================

  @override
  Future<OcrPageResult?> ocrPage(int pageIndex) async {
    if (_isDisposed || pageIndex < 0 || pageIndex >= _pageCount) return null;

    try {
      final result = await _channel.invokeMethod<Map>('ocrPage', {
        'documentId': documentId,
        'pageIndex': pageIndex,
      });

      if (result == null) return null;

      return OcrPageResult.fromMap(Map<String, dynamic>.from(result));
    } catch (e) {
      return null;
    }
  }

  // ===========================================================================
  // Dispose
  // ===========================================================================

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;

    _channel.invokeMethod('dispose', {'documentId': documentId}).catchError((
      _,
    ) {
      // Fire-and-forget: native cleanup might fail if engine detached
    });

    _pageCount = 0;
    _pageSizeCache.clear();
  }

  /// Dispose all documents on the native side.
  static Future<void> disposeAll() async {
    try {
      await _channel.invokeMethod('disposeAll');
    } catch (_) {
      // Swallow: native side may already be detached
    }
  }
}
