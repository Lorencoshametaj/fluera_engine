import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_quick_video_encoder/flutter_quick_video_encoder.dart';
import 'package:image/image.dart' as img;
import 'package:image/image.dart' show GifEncoder;

import '../models/canvas_layer.dart';
import '../models/pro_drawing_point.dart';
import '../models/timelapse_export_config.dart';
import '../brushes/brushes.dart';
import '../canvas_renderers/shape_painter.dart';
import 'time_travel_playback_engine.dart';

/// 🎬 Timelapse Export Service
///
/// Esporta il replay Time Travel come video timelapse per social media.
///
/// **Pipeline di export:**
/// 1. Calcola frame plan (quali eventi renderizzare per ogni frame)
/// 2. Per ogni frame: ricostruisci stato canvas → render offscreen → RGBA bytes
/// 3. MP4: Feed RGBA direttamente a FlutterQuickVideoEncoder (native H.264)
///    GIF: Accumula frame nel `image` package → encode GIF
/// 4. Ritorna file risultante
///
/// **Encoding backends:**
/// - **MP4**: `flutter_quick_video_encoder` — usa MediaCodec (Android) / AVFoundation (iOS)
/// - **GIF**: `image` package (pure Dart) — palette ottimizzata + dithering
class TimeTravelExportService {
  /// Massima dimensione frame (evita crash memoria)
  static const int _maxFrameDimension = 4096;

  // ============================================================================
  // EXPORT
  // ============================================================================

  /// 🎬 Esporta timelapse video
  ///
  /// [engine] — PlaybackEngine con gli eventi caricati
  /// [exportArea] — Area del canvas da catturare (null = auto da contenuto)
  /// [config] — Configurazione export (risoluzione, velocità, formato, etc.)
  /// [onProgress] — Callback con progresso 0.0-1.0 e messaggio stato
  ///
  /// Ritorna il [File] del video esportato, o null se cancellato/fallito.
  Future<File?> exportTimelapse({
    required TimeTravelPlaybackEngine engine,
    required TimelapseExportConfig config,
    Rect? exportArea,
    void Function(double progress, String status)? onProgress,
    bool Function()? isCancelled,
  }) async {
    try {
      onProgress?.call(0.0, 'Preparing...');

      // 1. Calcola area di export
      final area = exportArea ?? _calculateContentBounds(engine);
      if (area == null || area.isEmpty) {
        debugPrint('🎬 [TimelapseExport] No content to export');
        return null;
      }

      // 2. Calcola dimensioni frame
      final aspectRatio = area.width / area.height;
      final rawWidth = config.resolution.width.clamp(2, _maxFrameDimension);
      final rawHeight = config.resolution
          .heightForAspectRatio(aspectRatio)
          .clamp(2, _maxFrameDimension);
      // H.264 richiede dimensioni pari
      final frameWidth = _makeEven(rawWidth);
      final frameHeight = _makeEven(rawHeight);

      // 3. Calcola frame plan
      final framePlan = _calculateFramePlan(
        eventCount: engine.totalEventCount,
        config: config,
      );

      debugPrint(
        '🎬 [TimelapseExport] Plan: ${framePlan.length} frames, '
        '${frameWidth}x$frameHeight, ${config.format.extension}',
      );

      // 4. Dispatch al backend appropriato
      if (config.format == TimelapseFormat.mp4) {
        return _exportMp4(
          engine: engine,
          config: config,
          area: area,
          frameWidth: frameWidth,
          frameHeight: frameHeight,
          framePlan: framePlan,
          onProgress: onProgress,
          isCancelled: isCancelled,
        );
      } else {
        return _exportGif(
          engine: engine,
          config: config,
          area: area,
          frameWidth: frameWidth,
          frameHeight: frameHeight,
          framePlan: framePlan,
          onProgress: onProgress,
          isCancelled: isCancelled,
        );
      }
    } catch (e, stack) {
      debugPrint('🎬 [TimelapseExport] Error: $e\n$stack');
      return null;
    }
  }

  // ============================================================================
  // MP4 EXPORT (flutter_quick_video_encoder)
  // ============================================================================

  /// 🎥 Esporta come MP4 usando native H.264 encoder
  Future<File?> _exportMp4({
    required TimeTravelPlaybackEngine engine,
    required TimelapseExportConfig config,
    required Rect area,
    required int frameWidth,
    required int frameHeight,
    required List<int> framePlan,
    void Function(double progress, String status)? onProgress,
    bool Function()? isCancelled,
  }) async {
    // Output path
    final outputDir = await getApplicationDocumentsDirectory();
    final exportDir = Directory('${outputDir.path}/exports');
    if (!await exportDir.exists()) {
      await exportDir.create(recursive: true);
    }
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final outputPath = '${exportDir.path}/timelapse_$timestamp.mp4';

    // Setup encoder
    await FlutterQuickVideoEncoder.setup(
      width: frameWidth,
      height: frameHeight,
      fps: config.fps,
      videoBitrate: _bitRateForResolution(frameWidth, frameHeight),
      profileLevel: ProfileLevel.baselineAutoLevel,
      audioChannels: 0,
      audioBitrate: 0,
      sampleRate: 0,
      filepath: outputPath,
    );

    onProgress?.call(0.05, 'Rendering frames...');

    // Salva posizione corrente
    final savedIndex = engine.currentEventIndex;

    try {
      for (int i = 0; i < framePlan.length; i++) {
        if (isCancelled?.call() == true) {
          await FlutterQuickVideoEncoder.finish();
          // Cleanup partial file
          final partial = File(outputPath);
          if (await partial.exists()) await partial.delete();
          await engine.seekToIndex(savedIndex);
          return null;
        }

        // Naviga all'evento target
        await engine.seekToIndex(framePlan[i]);

        // Renderizza frame come RGBA raw bytes
        final rgbaBytes = await _renderFrameRgba(
          layers: engine.currentLayers,
          exportArea: area,
          width: frameWidth,
          height: frameHeight,
          backgroundColor: config.backgroundColor,
          showWatermark: config.showWatermark,
        );

        // Append al video encoder
        await FlutterQuickVideoEncoder.appendVideoFrame(rgbaBytes);

        // Progress (rendering = 90% del totale)
        final progress = 0.05 + (i / framePlan.length) * 0.90;
        onProgress?.call(progress, 'Frame ${i + 1}/${framePlan.length}');
      }

      // Finalizza
      await FlutterQuickVideoEncoder.finish();
      await engine.seekToIndex(savedIndex);

      final outputFile = File(outputPath);
      if (await outputFile.exists()) {
        onProgress?.call(1.0, 'Done!');
        debugPrint(
          '🎬 [TimelapseExport] MP4 complete: ${outputFile.path} '
          '(${(await outputFile.length()) ~/ 1024} KB)',
        );
        return outputFile;
      }
    } catch (e) {
      debugPrint('🎬 [TimelapseExport] MP4 error: $e');
      await engine.seekToIndex(savedIndex);
    }

    return null;
  }

  // ============================================================================
  // GIF EXPORT (image package — pure Dart)
  // ============================================================================

  /// 🎞️ Esporta come GIF animato usando il package `image`
  Future<File?> _exportGif({
    required TimeTravelPlaybackEngine engine,
    required TimelapseExportConfig config,
    required Rect area,
    required int frameWidth,
    required int frameHeight,
    required List<int> framePlan,
    void Function(double progress, String status)? onProgress,
    bool Function()? isCancelled,
  }) async {
    onProgress?.call(0.05, 'Rendering frames...');

    // Per GIF dimezza la risoluzione (file size ragionevole)
    final gifWidth = (frameWidth / 2).round().clamp(2, 1080);
    final gifHeight = (frameHeight / 2).round().clamp(2, 1080);

    final savedIndex = engine.currentEventIndex;
    final frames = <_GifFrameData>[];

    // Delay tra frame in centesimi di secondo (GIF standard)
    final frameDelayCentis = (100 / (config.fps / 2)).round().clamp(2, 100);

    try {
      for (int i = 0; i < framePlan.length; i++) {
        if (isCancelled?.call() == true) {
          await engine.seekToIndex(savedIndex);
          return null;
        }

        await engine.seekToIndex(framePlan[i]);

        // Renderizza a RGBA
        final rgbaBytes = await _renderFrameRgba(
          layers: engine.currentLayers,
          exportArea: area,
          width: gifWidth,
          height: gifHeight,
          backgroundColor: config.backgroundColor,
          showWatermark: config.showWatermark,
        );

        frames.add(
          _GifFrameData(
            rgba: rgbaBytes,
            width: gifWidth,
            height: gifHeight,
            delayCentis: frameDelayCentis,
          ),
        );

        final progress = 0.05 + (i / framePlan.length) * 0.70;
        onProgress?.call(progress, 'Frame ${i + 1}/${framePlan.length}');
      }

      await engine.seekToIndex(savedIndex);

      onProgress?.call(0.80, 'Encoding GIF...');

      // Encode GIF (compute isolate per non bloccare UI)
      final gifBytes = await compute(_encodeGifIsolate, frames);

      // Scrivi file
      final outputDir = await getApplicationDocumentsDirectory();
      final exportDir = Directory('${outputDir.path}/exports');
      if (!await exportDir.exists()) {
        await exportDir.create(recursive: true);
      }
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outputPath = '${exportDir.path}/timelapse_$timestamp.gif';
      final outputFile = File(outputPath);
      await outputFile.writeAsBytes(gifBytes);

      onProgress?.call(1.0, 'Done!');
      debugPrint(
        '🎬 [TimelapseExport] GIF complete: ${outputFile.path} '
        '(${gifBytes.length ~/ 1024} KB)',
      );
      return outputFile;
    } catch (e) {
      debugPrint('🎬 [TimelapseExport] GIF error: $e');
      await engine.seekToIndex(savedIndex);
    }

    return null;
  }

  /// Encode GIF in isolate (CPU-intensive)
  static Uint8List _encodeGifIsolate(List<_GifFrameData> frames) {
    final encoder = GifEncoder();
    for (final frame in frames) {
      final image = img.Image.fromBytes(
        width: frame.width,
        height: frame.height,
        bytes: frame.rgba.buffer,
        numChannels: 4,
      );
      encoder.addFrame(image, duration: frame.delayCentis);
    }
    final bytes = encoder.finish();
    return bytes != null ? Uint8List.fromList(bytes) : Uint8List(0);
  }

  // ============================================================================
  // SHARE
  // ============================================================================

  /// 📤 Condividi video esportato
  static Future<void> shareVideo(File videoFile) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(videoFile.path)],
        subject: 'Canvas Timelapse',
        text: 'Created with Looponia ✨',
      ),
    );
  }

  // ============================================================================
  // FRAME RENDERING
  // ============================================================================

  /// 🎨 Renderizza un singolo frame come raw RGBA bytes
  ///
  /// Riusa la stessa pipeline di `CanvasExportService._renderAreaToImage`:
  /// PictureRecorder → Canvas → drawBackground → drawShapes → drawStrokes
  /// → ui.Image → rawRgba bytes
  Future<Uint8List> _renderFrameRgba({
    required List<CanvasLayer> layers,
    required Rect exportArea,
    required int width,
    required int height,
    required Color backgroundColor,
    required bool showWatermark,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Scala per adattare l'area di export alla dimensione frame
    final scaleX = width / exportArea.width;
    final scaleY = height / exportArea.height;

    canvas.translate(-exportArea.left * scaleX, -exportArea.top * scaleY);
    canvas.scale(scaleX, scaleY);

    // 1. Background
    final bgPaint = Paint()..color = backgroundColor;
    canvas.drawRect(exportArea, bgPaint);

    // 2. Renderizza layer visibili (bottom to top)
    for (final layer in layers) {
      if (!layer.isVisible) continue;

      // Applica opacità layer
      if (layer.opacity < 1.0) {
        canvas.saveLayer(
          exportArea,
          Paint()..color = Color.fromRGBO(0, 0, 0, layer.opacity),
        );
      }

      // Shapes
      for (final shape in layer.shapes) {
        final shapeBounds = Rect.fromPoints(shape.startPoint, shape.endPoint);
        if (shapeBounds.overlaps(exportArea)) {
          ShapePainter.drawShape(canvas, shape);
        }
      }

      // Strokes
      for (final stroke in layer.strokes) {
        if (stroke.bounds.overlaps(exportArea)) {
          _drawStroke(canvas, stroke);
        }
      }

      // Restore layer opacity
      if (layer.opacity < 1.0) {
        canvas.restore();
      }
    }

    // 3. Watermark "Made with Looponia"
    if (showWatermark) {
      _drawWatermark(canvas, exportArea, scaleX);
    }

    // Converti in immagine → RGBA raw bytes
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);

    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) {
      throw Exception('Failed to render frame to RGBA');
    }

    return byteData.buffer.asUint8List();
  }

  /// 🖌️ Disegna uno stroke usando il brush appropriato
  void _drawStroke(Canvas canvas, ProStroke stroke) {
    if (stroke.points.isEmpty) return;

    switch (stroke.penType) {
      case ProPenType.ballpoint:
        BallpointBrush.drawStroke(
          canvas,
          stroke.points,
          stroke.color,
          stroke.baseWidth,
        );
        break;
      case ProPenType.fountain:
        FountainPenBrush.drawStroke(
          canvas,
          stroke.points,
          stroke.color,
          stroke.baseWidth,
        );
        break;
      case ProPenType.pencil:
        PencilBrush.drawStroke(
          canvas,
          stroke.points,
          stroke.color,
          stroke.baseWidth,
        );
        break;
      case ProPenType.highlighter:
        HighlighterBrush.drawStroke(
          canvas,
          stroke.points,
          stroke.color,
          stroke.baseWidth,
        );
        break;
    }
  }

  /// 🏷️ Disegna watermark "Made with Looponia" in basso a destra
  void _drawWatermark(Canvas canvas, Rect exportArea, double scale) {
    final fontSize = 14.0 / scale;
    final padding = 12.0 / scale;

    final paragraphBuilder = ui.ParagraphBuilder(
      ui.ParagraphStyle(textAlign: TextAlign.right, fontSize: fontSize),
    );
    paragraphBuilder.pushStyle(
      ui.TextStyle(
        color: const Color(0x66000000),
        fontSize: fontSize,
        fontFamily: 'Roboto',
      ),
    );
    paragraphBuilder.addText('Made with Looponia ✨');
    paragraphBuilder.pop();

    final paragraph = paragraphBuilder.build();
    paragraph.layout(ui.ParagraphConstraints(width: exportArea.width));

    canvas.drawParagraph(
      paragraph,
      Offset(
        exportArea.right - paragraph.maxIntrinsicWidth - padding,
        exportArea.bottom - fontSize - padding,
      ),
    );
  }

  // ============================================================================
  // FRAME PLAN
  // ============================================================================

  /// 📋 Calcola il piano dei frame: quali eventi renderizzare
  List<int> _calculateFramePlan({
    required int eventCount,
    required TimelapseExportConfig config,
  }) {
    if (eventCount == 0) return [0];

    final frames = <int>[];
    final totalFrames = config.totalFrames(eventCount);

    for (int i = 0; i < totalFrames; i++) {
      final eventIndex = ((i / totalFrames) * eventCount).round().clamp(
        0,
        eventCount,
      );
      frames.add(eventIndex);
    }

    // Assicura che l'ultimo frame sia lo stato finale
    if (frames.last != eventCount) {
      frames.add(eventCount);
    }

    return frames;
  }

  // ============================================================================
  // UTILITY
  // ============================================================================

  /// Calcola bounds del contenuto da tutti gli eventi
  Rect? _calculateContentBounds(TimeTravelPlaybackEngine engine) {
    final layers = engine.currentLayers;
    if (layers.isEmpty) return null;

    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;

    for (final layer in layers) {
      for (final stroke in layer.strokes) {
        final bounds = stroke.bounds;
        if (bounds.left < minX) minX = bounds.left;
        if (bounds.top < minY) minY = bounds.top;
        if (bounds.right > maxX) maxX = bounds.right;
        if (bounds.bottom > maxY) maxY = bounds.bottom;
      }
      for (final shape in layer.shapes) {
        final bounds = Rect.fromPoints(shape.startPoint, shape.endPoint);
        if (bounds.left < minX) minX = bounds.left;
        if (bounds.top < minY) minY = bounds.top;
        if (bounds.right > maxX) maxX = bounds.right;
        if (bounds.bottom > maxY) maxY = bounds.bottom;
      }
    }

    if (minX == double.infinity) return null;

    const padding = 50.0;
    return Rect.fromLTRB(
      minX - padding,
      minY - padding,
      maxX + padding,
      maxY + padding,
    );
  }

  /// Arrotonda a numero pari (richiesto da H.264 codec)
  int _makeEven(int value) => value.isEven ? value : value + 1;

  /// Bitrate basato sulla risoluzione (qualità ragionevole)
  int _bitRateForResolution(int width, int height) {
    final pixels = width * height;
    if (pixels >= 3840 * 2160) return 8000000; // 4K → 8 Mbps
    if (pixels >= 1920 * 1080) return 4000000; // 1080p → 4 Mbps
    return 2500000; // 720p → 2.5 Mbps
  }
}

/// Dati frame per passaggio all'isolate GIF (tutti i tipi primitivi/transferibili)
class _GifFrameData {
  final Uint8List rgba;
  final int width;
  final int height;
  final int delayCentis;

  const _GifFrameData({
    required this.rgba,
    required this.width,
    required this.height,
    required this.delayCentis,
  });
}
