import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../drawing/models/pro_drawing_point.dart';
import '../../canvas/infinite_canvas_controller.dart';

/// 🎨 VulkanStrokeOverlayService — Dart bridge to the C++ Vulkan stroke renderer.
///
/// Manages the native texture lifecycle and sends stroke data to the GPU
/// renderer via MethodChannel. The Vulkan renderer draws into a
/// SurfaceTexture that Flutter composites via Texture(textureId:).
///
/// Usage:
///   final service = VulkanStrokeOverlayService();
///   final textureId = await service.init(width, height);
///   // Add Texture(textureId: textureId) to widget tree
///   service.updateAndRender(points, color, width);
///   service.clear(); // on pen-up
///   service.dispose();
class VulkanStrokeOverlayService {
  static const _channel = MethodChannel('fluera_engine/vulkan_stroke');

  int? _textureId;
  bool _initialized = false;
  bool? _available;
  int _lastSentCount = 0;
  int _lastSendTimeMs = 0;

  /// Flutter texture ID for use with Texture(textureId:) widget.
  int? get textureId => _textureId;

  /// Whether the Vulkan renderer is initialized and ready.
  bool get isInitialized => _initialized;

  /// Check if Vulkan stroke overlay is available on this device.
  /// Caches result after first call.
  Future<bool> get isAvailable async {
    if (_available != null) return _available!;
    try {
      _available = await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } catch (e) {
      _available = false;
    }
    return _available!;
  }

  /// Initialize the Vulkan renderer.
  /// Returns the Flutter texture ID, or null if initialization fails.
  Future<int?> init(int width, int height) async {
    try {
      final id = await _channel.invokeMethod<int>('init', {
        'width': width,
        'height': height,
      });
      if (id != null) {
        _textureId = id;
        _initialized = true;
      }
      return id;
    } catch (e) {
      debugPrint('[FlueraVk] init failed: $e');
      _initialized = false;
      return null;
    }
  }

  /// Send NEW stroke points to the Vulkan renderer and trigger a render.
  ///
  /// Only sends points added since the last call (incremental).
  /// The C++ renderer accumulates points internally.
  /// 🚀 Throttled to 60fps max to reduce MethodChannel overhead on long strokes.
  void updateAndRender(
    List<ProDrawingPoint> points,
    ui.Color color,
    double strokeWidth, {
    bool force = false,
    int brushType = 0,
    double pencilBaseOpacity = 0.4,
    double pencilMaxOpacity = 0.8,
    double pencilMinPressure = 0.5,
    double pencilMaxPressure = 1.2,
    double fountainThinning = 0.5,
    double fountainNibAngleDeg = 30.0,
    double fountainNibStrength = 0.35,
    double fountainPressureRate = 0.275,
    int fountainTaperEntry = 6,
  }) {
    if (!_initialized || points.length < 2) return;

    // 🚀 Throttle: skip if <16ms since last send (unless forced or first call)
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force && _lastSendTimeMs > 0 && (now - _lastSendTimeMs) < 16) {
      return; // Points accumulate, will be sent in next batch
    }

    // OPT-4: For ballpoint (brushType==0), send only NEW points incrementally.
    // C++ accumulates internally and only tessellates the delta.
    // Other brushes need ALL points for correct smoothing/tangents.
    int newStart;
    if (brushType == 0 && _lastSentCount > 0) {
      // 1-point overlap for segment continuity at the boundary
      newStart = (_lastSentCount - 1).clamp(0, points.length);
    } else {
      newStart = 0;
    }
    if (newStart >= points.length) return;

    final newCount = points.length - newStart;
    // Stride 5: x, y, pressure, tiltX, tiltY
    final flatPoints = List<double>.filled(newCount * 5, 0.0);
    for (int i = 0; i < newCount; i++) {
      final pt = points[newStart + i];
      flatPoints[i * 5] = pt.position.dx;
      flatPoints[i * 5 + 1] = pt.position.dy;
      flatPoints[i * 5 + 2] = pt.pressure;
      flatPoints[i * 5 + 3] = pt.tiltX;
      flatPoints[i * 5 + 4] = pt.tiltY;
    }
    _lastSentCount = points.length;
    _lastSendTimeMs = now;

    _channel.invokeMethod('updateAndRender', {
      'points': flatPoints,
      'color': color.toARGB32(),
      'width': strokeWidth,
      'totalPoints': points.length,
      'brushType': brushType,
      'pencilBaseOpacity': pencilBaseOpacity,
      'pencilMaxOpacity': pencilMaxOpacity,
      'pencilMinPressure': pencilMinPressure,
      'pencilMaxPressure': pencilMaxPressure,
      'fountainThinning': fountainThinning,
      'fountainNibAngleDeg': fountainNibAngleDeg,
      'fountainNibStrength': fountainNibStrength,
      'fountainPressureRate': fountainPressureRate,
      'fountainTaperEntry': fountainTaperEntry,
    });
  }

  /// Set the canvas transform matrix (for pan/zoom/rotation sync).
  ///
  /// Builds a combined canvas-space → Vulkan NDC matrix.
  /// [width]/[height] are in physical pixels, [dpr] is devicePixelRatio.
  /// Canvas coordinates (logical) are scaled by dpr to match the physical
  /// pixel surface.
  void setTransform(
    InfiniteCanvasController controller,
    int width,
    int height, [
    double dpr = 1.0,
  ]) {
    if (!_initialized) return;

    final scale = controller.scale;
    final ox = controller.offset.dx;
    final oy = controller.offset.dy;

    final double w = width.toDouble();
    final double h = height.toDouble();

    // Canvas coordinates are in logical pixels.
    // The Vulkan surface is in physical pixels (width/height already scaled).
    // So we need to scale canvas coords by dpr before NDC conversion:
    //   ndcX = (canvasX * scale * dpr + ox * dpr) * (2/w) - 1
    final effectiveScale = scale * dpr;
    final effectiveOx = ox * dpr;
    final effectiveOy = oy * dpr;

    final sx = 2.0 * effectiveScale / w;
    final sy = 2.0 * effectiveScale / h;
    final tx = (2.0 * effectiveOx / w) - 1.0;
    final ty = (2.0 * effectiveOy / h) - 1.0;

    // Column-major 4x4 matrix (no rotation for now)
    final matrix = <double>[
      sx,
      0.0,
      0.0,
      0.0,
      0.0,
      sy,
      0.0,
      0.0,
      0.0,
      0.0,
      1.0,
      0.0,
      tx,
      ty,
      0.0,
      1.0,
    ];

    _channel.invokeMethod('setTransform', {'matrix': matrix});
  }

  /// Clear the render target (transparent). Call on pen-up.
  void clear() {
    if (!_initialized) return;
    _lastSentCount = 0;
    _lastSendTimeMs = 0;
    _channel.invokeMethod('clear');
  }

  /// Resize the render target.
  Future<bool> resize(int width, int height) async {
    if (!_initialized) return false;
    try {
      return await _channel.invokeMethod<bool>('resize', {
            'width': width,
            'height': height,
          }) ??
          false;
    } catch (e) {
      debugPrint('[FlueraVk] resize failed: $e');
      return false;
    }
  }

  /// Dispose all resources.
  Future<void> dispose() async {
    if (!_initialized) return;
    try {
      await _channel.invokeMethod('destroy');
    } catch (e) {
      debugPrint('[FlueraVk] destroy failed: $e');
    }
    _textureId = null;
    _initialized = false;
  }

  /// Get performance statistics from the Vulkan renderer.
  /// Returns null if the renderer is not initialized or stats unavailable.
  Future<VulkanStats?> getStats() async {
    if (!_initialized) return null;
    try {
      final result = await _channel.invokeMethod<Map>('getStats');
      if (result == null) return null;
      final m = Map<String, dynamic>.from(result);
      return VulkanStats(
        p50Us: (m['p50us'] as num?)?.toDouble() ?? 0,
        p90Us: (m['p90us'] as num?)?.toDouble() ?? 0,
        p99Us: (m['p99us'] as num?)?.toDouble() ?? 0,
        vertexCount: (m['vertexCount'] as num?)?.toInt() ?? 0,
        drawCalls: (m['drawCalls'] as num?)?.toInt() ?? 0,
        swapchainImages: (m['swapchainImages'] as num?)?.toInt() ?? 0,
        totalFrames: (m['totalFrames'] as num?)?.toInt() ?? 0,
        active: m['active'] as bool? ?? false,
        deviceName: m['deviceName'] as String? ?? 'N/A',
        apiVersion:
            '${m['apiMajor'] ?? 0}.${m['apiMinor'] ?? 0}.${m['apiPatch'] ?? 0}',
      );
    } catch (e) {
      debugPrint('[FlueraVk] getStats failed: $e');
      return null;
    }
  }
}

/// Performance statistics snapshot from the Vulkan renderer.
class VulkanStats {
  /// GPU frame time at the 50th percentile (microseconds).
  final double p50Us;

  /// GPU frame time at the 90th percentile (microseconds).
  final double p90Us;

  /// GPU frame time at the 99th percentile (microseconds).
  final double p99Us;

  /// Number of vertices rendered in the last frame.
  final int vertexCount;

  /// Number of draw calls in the last frame.
  final int drawCalls;

  /// Number of swapchain images.
  final int swapchainImages;

  /// Total number of frames rendered by the Vulkan pipeline.
  final int totalFrames;

  /// Whether the Vulkan renderer is actively drawing strokes.
  final bool active;

  /// GPU device name (e.g., "Adreno 730").
  final String deviceName;

  /// Vulkan API version string (e.g., "1.1.0").
  final String apiVersion;

  /// P50 frame time in milliseconds.
  double get p50Ms => p50Us / 1000.0;

  /// P90 frame time in milliseconds.
  double get p90Ms => p90Us / 1000.0;

  /// P99 frame time in milliseconds.
  double get p99Ms => p99Us / 1000.0;

  const VulkanStats({
    required this.p50Us,
    required this.p90Us,
    required this.p99Us,
    required this.vertexCount,
    required this.drawCalls,
    required this.swapchainImages,
    required this.totalFrames,
    required this.active,
    required this.deviceName,
    required this.apiVersion,
  });
}
