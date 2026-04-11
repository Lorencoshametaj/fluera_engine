// ============================================================================
// 🎬 CANVAS RASTERIZER — Capture canvas frames for P2P Visit mode (7a)
//
// Provides a frame stream of the canvas viewport for real-time sharing.
//
// Design:
//   - Uses RepaintBoundary.toImage() at configurable resolution/fps
//   - Change detection: skips capture when canvas hasn't changed
//   - Privacy: can mask hidden areas via P2PPrivacyGuard
//   - Frame sink abstraction: WebRTC video track, file recorder, etc.
//
// Performance targets:
//   - 720p @ 10fps = ~7.2 Mpx/sec
//   - ~100ms budget per frame (well within 16ms toImage + 50ms encode)
//   - Skip-on-idle: 0 GPU cost when canvas is static
// ============================================================================

import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/rendering.dart';

/// 🎬 Frame data from a canvas rasterization pass.
class RasterFrame {
  /// RGBA pixel data (width * height * 4 bytes).
  final Uint8List rgba;

  /// Frame width in pixels.
  final int width;

  /// Frame height in pixels.
  final int height;

  /// Monotonic timestamp (microseconds since epoch).
  final int timestampUs;

  const RasterFrame({
    required this.rgba,
    required this.width,
    required this.height,
    required this.timestampUs,
  });

  /// Total bytes in this frame.
  int get byteLength => rgba.length;
}

/// 🔌 Abstract sink for consuming raster frames.
///
/// The host app implements this to feed frames into WebRTC video tracks,
/// file recorders, or preview displays.
///
/// ```dart
/// class WebRtcFrameSink extends RasterFrameSink {
///   final RTCVideoRenderer renderer;
///   void onFrame(RasterFrame frame) {
///     renderer.addFrame(frame.rgba, frame.width, frame.height);
///   }
///   void onError(Object error) => debugPrint('Raster error: $error');
///   void onStop() => renderer.dispose();
/// }
/// ```
abstract class RasterFrameSink {
  /// Called for each captured frame.
  void onFrame(RasterFrame frame);

  /// Called on capture error (non-fatal, will retry next tick).
  void onError(Object error) {}

  /// Called when rasterization stops.
  void onStop() {}
}

/// ⚙️ Configuration for the rasterizer.
class RasterConfig {
  /// Target resolution (width in pixels). Height is derived from aspect ratio.
  final int targetWidth;

  /// Target frames per second.
  final double targetFps;

  /// Output format: RGBA (raw) or PNG (compressed).
  final RasterFormat format;

  /// Whether to skip frames when the canvas hasn't changed.
  final bool skipOnIdle;

  const RasterConfig({
    this.targetWidth = 1280,
    this.targetFps = 10.0,
    this.format = RasterFormat.rgba,
    this.skipOnIdle = true,
  });

  /// Low-bandwidth preset: 480p @ 5fps.
  static const lowBandwidth = RasterConfig(
    targetWidth: 854,
    targetFps: 5.0,
  );

  /// Standard preset: 720p @ 10fps.
  static const standard = RasterConfig(
    targetWidth: 1280,
    targetFps: 10.0,
  );

  /// High quality preset: 1080p @ 15fps.
  static const highQuality = RasterConfig(
    targetWidth: 1920,
    targetFps: 15.0,
  );
}

/// Output format for raster frames.
enum RasterFormat {
  /// Raw RGBA pixels (fastest, no compression).
  rgba,

  /// PNG encoded (compressed, slower).
  png,
}

/// 🎬 Canvas Rasterizer.
///
/// Captures the canvas RepaintBoundary at a target resolution and frame rate,
/// emitting frames to one or more [RasterFrameSink]s.
///
/// Usage:
/// ```dart
/// final rasterizer = CanvasRasterizer(
///   boundaryKey: _canvasRepaintBoundaryKey,
///   config: RasterConfig.standard,
/// );
/// rasterizer.addSink(myWebRtcSink);
/// rasterizer.start();
/// // ...later...
/// rasterizer.stop();
/// ```
class CanvasRasterizer {
  /// The GlobalKey of the RepaintBoundary wrapping the canvas.
  final GlobalKey boundaryKey;

  /// Rasterization configuration.
  final RasterConfig config;

  CanvasRasterizer({
    required this.boundaryKey,
    this.config = const RasterConfig(),
  });

  final List<RasterFrameSink> _sinks = [];
  Timer? _timer;
  bool _isRunning = false;
  bool _isCapturing = false;
  int _frameCount = 0;
  int _skipCount = 0;

  // Change detection: compare boundary's paint generation.
  int _lastPaintGeneration = -1;

  /// Whether the rasterizer is currently running.
  bool get isRunning => _isRunning;

  /// Total frames captured since last start.
  int get frameCount => _frameCount;

  /// Total frames skipped (idle) since last start.
  int get skipCount => _skipCount;

  // ── Sink Management ─────────────────────────────────────────────────

  /// Add a frame sink.
  void addSink(RasterFrameSink sink) => _sinks.add(sink);

  /// Remove a frame sink.
  void removeSink(RasterFrameSink sink) => _sinks.remove(sink);

  // ── Lifecycle ───────────────────────────────────────────────────────

  /// Start rasterizing at the configured frame rate.
  void start() {
    if (_isRunning) return;
    _isRunning = true;
    _frameCount = 0;
    _skipCount = 0;

    final intervalMs = (1000.0 / config.targetFps).round();
    _timer = Timer.periodic(
      Duration(milliseconds: intervalMs),
      (_) => _captureFrame(),
    );

    debugPrint('🎬 CanvasRasterizer: started '
        '(${config.targetWidth}px @ ${config.targetFps}fps)');
  }

  /// Stop rasterizing.
  void stop() {
    if (!_isRunning) return;
    _isRunning = false;
    _timer?.cancel();
    _timer = null;

    for (final sink in _sinks) {
      sink.onStop();
    }

    debugPrint('🎬 CanvasRasterizer: stopped '
        '(frames=$_frameCount, skipped=$_skipCount)');
  }

  /// Dispose all resources.
  void dispose() {
    stop();
    _sinks.clear();
  }

  // ── Frame Capture ───────────────────────────────────────────────────

  Future<void> _captureFrame() async {
    // Prevent overlapping captures.
    if (_isCapturing || !_isRunning) return;
    _isCapturing = true;

    try {
      final boundary = boundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null || !boundary.hasSize) return;

      // Change detection: skip if nothing repainted.
      if (config.skipOnIdle) {
        final gen = boundary.debugNeedsPaint ? -1 : boundary.hashCode;
        if (gen == _lastPaintGeneration) {
          _skipCount++;
          return;
        }
        _lastPaintGeneration = gen;
      }

      // Calculate pixel ratio for target width.
      final logicalSize = boundary.size;
      if (logicalSize.width <= 0) return;
      final pixelRatio = config.targetWidth / logicalSize.width;

      // Capture.
      final image = await boundary.toImage(pixelRatio: pixelRatio);

      Uint8List bytes;
      int width = image.width;
      int height = image.height;

      if (config.format == RasterFormat.png) {
        final byteData = await image.toByteData(
          format: ui.ImageByteFormat.png,
        );
        image.dispose();
        if (byteData == null) return;
        bytes = byteData.buffer.asUint8List();
      } else {
        final byteData = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        image.dispose();
        if (byteData == null) return;
        bytes = byteData.buffer.asUint8List();
      }

      _frameCount++;

      final frame = RasterFrame(
        rgba: bytes,
        width: width,
        height: height,
        timestampUs: DateTime.now().microsecondsSinceEpoch,
      );

      // Dispatch to all sinks.
      for (final sink in _sinks) {
        try {
          sink.onFrame(frame);
        } catch (e) {
          sink.onError(e);
        }
      }
    } catch (e) {
      for (final sink in _sinks) {
        sink.onError(e);
      }
    } finally {
      _isCapturing = false;
    }
  }
}
