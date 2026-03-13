import 'dart:ui' as ui;

/// 🚀 Zero-copy PDF texture tile — holds a Flutter texture ID
/// instead of pixel data.
///
/// Created by [NativeFlueraPdfProvider.renderPageTexture] when the platform
/// supports TextureRegistry-based rendering. The texture ID is registered
/// natively (SurfaceProducer on Android, CVPixelBuffer on iOS) and can be
/// composited by Flutter without any pixel copy.
///
/// Call [dispose] when the tile is no longer needed to release the native
/// texture resource.
class PdfTextureTile {
  /// Flutter texture ID registered via TextureRegistry.
  final int textureId;

  /// Width of the rendered tile in pixels.
  final int width;

  /// Height of the rendered tile in pixels.
  final int height;

  /// Whether this tile has been disposed.
  bool _isDisposed = false;
  bool get isDisposed => _isDisposed;

  PdfTextureTile({
    required this.textureId,
    required this.width,
    required this.height,
  });

  /// Mark this tile as disposed. The actual native release is handled
  /// by calling [NativeFlueraPdfProvider.releaseTexture].
  void dispose() {
    _isDisposed = true;
  }

  @override
  String toString() =>
      'PdfTextureTile(id: $textureId, ${width}x$height, disposed: $_isDisposed)';
}
