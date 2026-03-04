import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import '../canvas/fluera_canvas_config.dart';
import '../core/models/ocr_result.dart';
import '../core/models/pdf_text_rect.dart';

/// 📄 Native PDF rendering provider — zero third-party dependencies.
///
/// Uses platform method channels to call:
/// - **iOS**: `PDFKit` (Apple native)
/// - **Android**: `android.graphics.pdf.PdfRenderer`
///
/// Supports multiple simultaneous documents via `documentId`. Each instance
/// of this class manages a single document; the native side stores multiple
/// documents keyed by ID.
///
/// Pixel data is transferred as raw RGBA `Uint8List` and decoded into
/// `ui.Image` using `decodeImageFromPixels` — no PNG encode/decode overhead.
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
  // Render Page → ui.Image
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
