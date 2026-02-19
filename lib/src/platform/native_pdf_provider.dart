import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import '../canvas/nebula_canvas_config.dart';
import '../core/models/pdf_text_rect.dart';

/// 📄 Native PDF rendering provider — zero third-party dependencies.
///
/// Uses platform method channels to call:
/// - **iOS**: `PDFKit` (Apple native)
/// - **Android**: `android.graphics.pdf.PdfRenderer`
///
/// Pixel data is transferred as raw RGBA `Uint8List` and decoded into
/// `ui.Image` using `decodeImageFromPixels` — no PNG encode/decode overhead.
///
/// Usage:
/// ```dart
/// final config = NebulaCanvasConfig(
///   pdfProvider: NativeNebulaPdfProvider(),
///   // ...
/// );
/// ```
class NativeNebulaPdfProvider implements NebulaPdfProvider {
  static const MethodChannel _channel = MethodChannel(
    'com.nebulaengine/pdf_renderer',
  );

  int _pageCount = 0;
  final Map<int, Size> _pageSizeCache = {};

  // ===========================================================================
  // Load Document
  // ===========================================================================

  @override
  Future<bool> loadDocument(List<int> bytes) async {
    try {
      final result = await _channel.invokeMethod<Map>('loadDocument', {
        'bytes': Uint8List.fromList(bytes),
      });

      if (result == null) return false;

      final success = result['success'] as bool? ?? false;
      _pageCount = result['pageCount'] as int? ?? 0;
      _pageSizeCache.clear();

      return success && _pageCount > 0;
    } catch (e) {
      debugPrint('[NativePdfProvider] loadDocument error: $e');
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

    // Return cached size if available
    if (_pageSizeCache.containsKey(pageIndex)) {
      return _pageSizeCache[pageIndex]!;
    }

    // Otherwise return zero — caller should use pageSizeAsync
    return Size.zero;
  }

  /// Async version that fetches page size from native side.
  Future<Size> pageSizeAsync(int pageIndex) async {
    if (pageIndex < 0 || pageIndex >= _pageCount) return Size.zero;

    if (_pageSizeCache.containsKey(pageIndex)) {
      return _pageSizeCache[pageIndex]!;
    }

    try {
      final result = await _channel.invokeMethod<Map>('getPageSize', {
        'pageIndex': pageIndex,
      });

      if (result == null) return Size.zero;

      final width = (result['width'] as num?)?.toDouble() ?? 0.0;
      final height = (result['height'] as num?)?.toDouble() ?? 0.0;
      final size = Size(width, height);

      _pageSizeCache[pageIndex] = size;
      return size;
    } catch (e) {
      debugPrint('[NativePdfProvider] getPageSize error: $e');
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
    if (pageIndex < 0 || pageIndex >= _pageCount) return null;

    final targetWidth = targetSize.width.toInt();
    final targetHeight = targetSize.height.toInt();

    if (targetWidth <= 0 || targetHeight <= 0) return null;

    try {
      final result = await _channel.invokeMethod<Map>('renderPage', {
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
      debugPrint('[NativePdfProvider] renderPage error: $e');
      return null;
    }
  }

  /// Decode raw RGBA pixel buffer into a `ui.Image`.
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
    if (pageIndex < 0 || pageIndex >= _pageCount) return [];

    try {
      final result = await _channel.invokeMethod<List>('extractText', {
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
      debugPrint('[NativePdfProvider] extractText error: $e');
      return [];
    }
  }

  @override
  Future<String> getPageText(int pageIndex) async {
    if (pageIndex < 0 || pageIndex >= _pageCount) return '';

    try {
      final result = await _channel.invokeMethod<String>('getPageText', {
        'pageIndex': pageIndex,
      });
      return result ?? '';
    } catch (e) {
      debugPrint('[NativePdfProvider] getPageText error: $e');
      return '';
    }
  }

  // ===========================================================================
  // Dispose
  // ===========================================================================

  @override
  void dispose() {
    _channel.invokeMethod('dispose');
    _pageCount = 0;
    _pageSizeCache.clear();
  }
}
