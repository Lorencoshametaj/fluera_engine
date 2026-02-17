import 'dart:ui' as ui;
import 'package:flutter/services.dart';

/// 🎨 Type of texture applicabile ai pennelli
enum TextureType {
  none, // None texture
  pencilGrain, // Grana matita su carta ruvida
  charcoal, // Carboncino grosso
  watercolor, // Macchie acquerello
  canvas, // Trama tela pittura
  kraft, // Carta kraft con fibre
}

/// 🎨 Sistema Texture per Pennelli Professionali
///
/// Loads e cache texture grayscale tileable come `ui.Image`.
/// Le texture vengono applicate ai tratti via `ImageShader` con `BlendMode.modulate`.
///
/// Cache singleton: ogni texture viene caricata una sola volta in memoria.
class BrushTexture {
  BrushTexture._();

  // Cache singleton delle texture caricate
  static final Map<TextureType, ui.Image?> _cache = {};
  static final Map<TextureType, bool> _loading = {};

  /// Path dell'asset per ogni type of texture
  static const Map<TextureType, String> _assetPaths = {
    TextureType.pencilGrain: 'assets/textures/pencil_grain.png',
    TextureType.charcoal: 'assets/textures/charcoal.png',
    TextureType.watercolor: 'assets/textures/watercolor.png',
    TextureType.canvas: 'assets/textures/canvas_weave.png',
    TextureType.kraft: 'assets/textures/kraft_paper.png',
  };

  /// Loads una texture (async, con cache)
  /// Returns `null` if the tipo is `none` o if the caricamento fallisce.
  static Future<ui.Image?> load(TextureType type) async {
    if (type == TextureType.none) return null;

    // Cache hit
    if (_cache.containsKey(type)) return _cache[type];

    // Prevent duplicate loads
    if (_loading[type] == true) return null;
    _loading[type] = true;

    try {
      final path = _assetPaths[type];
      if (path == null) return null;

      final data = await rootBundle.load(path);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      _cache[type] = frame.image;
      return frame.image;
    } catch (e) {
      _cache[type] = null;
      return null;
    } finally {
      _loading[type] = false;
    }
  }

  /// Get texture from the cache (sincrono, null if not caricata)
  static ui.Image? getCached(TextureType type) {
    return _cache[type];
  }

  /// Pre-carica tutte le texture (da chiamare all'avvio of the canvas)
  static Future<void> preloadAll() async {
    final futures = TextureType.values
        .where((t) => t != TextureType.none)
        .map((t) => load(t));
    await Future.wait(futures);
  }

  /// Creates un Paint con ImageShader for the texture
  ///
  /// [textureImage] L'immagine texture caricata
  /// [intensity] Intensità of the texture (0.0 = nessun effetto, 1.0 = pieno)
  /// [scale] Scala of the texture (1.0 = size originale)
  static ui.Paint? createTexturePaint({
    required ui.Image textureImage,
    double intensity = 1.0,
    double scale = 1.0,
  }) {
    final matrix = Matrix4.diagonal3Values(scale, scale, 1.0);

    final shader = ui.ImageShader(
      textureImage,
      ui.TileMode.repeated,
      ui.TileMode.repeated,
      matrix.storage,
    );

    return ui.Paint()
      ..shader = shader
      ..blendMode = ui.BlendMode.modulate
      ..color = ui.Color.fromARGB((intensity * 255).round(), 255, 255, 255);
  }

  /// Applica texture a un canvas sopra un path already disegnato.
  ///
  /// Use `saveLayer` + `BlendMode.modulate` to mask the stroke
  /// with the texture grayscale.
  static void applyTextureToPath({
    required ui.Canvas canvas,
    required ui.Path path,
    required ui.Image textureImage,
    double intensity = 1.0,
    double scale = 1.0,
  }) {
    if (intensity <= 0.0) return;

    final texturePaint = createTexturePaint(
      textureImage: textureImage,
      intensity: intensity,
      scale: scale,
    );
    if (texturePaint == null) return;

    // The path is il bounds of the area su cui applicare la texture
    final bounds = path.getBounds();

    // Save layer per compositing
    canvas.saveLayer(bounds, ui.Paint());
    canvas.drawPath(path, texturePaint);
    canvas.restore();
  }

  /// Libera tutte le texture from the cache
  static void dispose() {
    for (final img in _cache.values) {
      img?.dispose();
    }
    _cache.clear();
  }
}
