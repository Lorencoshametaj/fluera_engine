import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';

import '../../core/models/warp_mesh.dart';
import '../../../fluera_engine.dart';

// =============================================================================
// 🎛️ TRANSFORM GPU SERVICE — Platform channel bridge to native GPU compute
//
// Wraps the `fluera_engine/transform` MethodChannel connecting Dart tools
// (Liquify, Smudge, Warp) to native Metal (iOS) and Vulkan (Android)
// compute shaders.
// =============================================================================

/// Service for GPU-accelerated transform operations.
///
/// Manages the lifecycle of native resources and provides high-level methods
/// for applying Liquify, Smudge, and Warp deformations.
class TransformGpuService {
  static const _channel = MethodChannel('fluera_engine/transform');

  /// Singleton instance.
  static final TransformGpuService instance = TransformGpuService._();
  TransformGpuService._();

  /// The Flutter texture ID for the output texture.
  int? _textureId;

  /// Whether the native GPU service is available.
  bool _isAvailable = false;

  /// Current working dimensions.
  int _width = 0;
  int _height = 0;

  /// Whether the service is initialized.
  bool get isInitialized => _textureId != null;

  /// The Flutter texture ID for compositing.
  int? get textureId => _textureId;

  // ═══════════════════════════════════════════════════════════════
  // LIFECYCLE
  // ═══════════════════════════════════════════════════════════════

  /// Check if native GPU compute is available on this platform.
  Future<bool> checkAvailability() async {
    try {
      _isAvailable = await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } catch (e) {
      _isAvailable = false;
    }
    return _isAvailable;
  }

  /// Initialize the native GPU resources with the given dimensions.
  ///
  /// Returns the Flutter texture ID that can be used for compositing,
  /// or null if initialization failed.
  Future<int?> initialize(int width, int height) async {
    if (!_isAvailable) {
      await checkAvailability();
      if (!_isAvailable) return null;
    }

    try {
      final result = await _channel.invokeMethod<int>('init', {
        'width': width,
        'height': height,
      });
      _textureId = result;
      _width = width;
      _height = height;
      return result;
    } catch (e) {
      return null;
    }
  }

  /// Upload a source image to the GPU.
  Future<bool> setSourceImage(Uint8List rgbaData, int width, int height) async {
    if (!isInitialized) return false;
    try {
      return await _channel.invokeMethod<bool>('setSourceImage', {
            'imageData': rgbaData,
            'width': width,
            'height': height,
          }) ??
          false;
    } catch (e) {
      return false;
    }
  }

  /// Upload a source image from a ui.Image.
  Future<bool> setSourceFromImage(ui.Image image) async {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) return false;

    final data = byteData.buffer.asUint8List();
    return setSourceImage(data, image.width, image.height);
  }

  /// Destroy native resources.
  Future<void> destroy() async {
    try {
      await _channel.invokeMethod('destroy');
    } catch (_) {}
    _textureId = null;
    _width = 0;
    _height = 0;
  }

  // ═══════════════════════════════════════════════════════════════
  // TRANSFORM OPERATIONS
  // ═══════════════════════════════════════════════════════════════

  /// Apply liquify deformation using a [DisplacementField].
  ///
  /// The displacement field is uploaded as a Float32List of interleaved
  /// (dx, dy) pairs and applied via the GPU compute shader.
  Future<bool> applyLiquify(DisplacementField field) async {
    if (!isInitialized) return false;

    try {
      return await _channel.invokeMethod<bool>('applyLiquify', {
            'fieldData': Float32List.view(field.data.buffer),
            'fieldWidth': field.width,
            'fieldHeight': field.height,
          }) ??
          false;
    } catch (e) {
      return false;
    }
  }

  /// Apply smudge along a path of samples.
  ///
  /// Each sample is packed as 8 floats: {x, y, radius, strength, r, g, b, a}.
  Future<bool> applySmudge(List<SmudgeSampleData> samples) async {
    if (!isInitialized || samples.isEmpty) return false;

    // Pack samples into Float32List
    final data = Float32List(samples.length * 8);
    for (int i = 0; i < samples.length; i++) {
      final s = samples[i];
      final base = i * 8;
      data[base] = s.x;
      data[base + 1] = s.y;
      data[base + 2] = s.radius;
      data[base + 3] = s.strength;
      data[base + 4] = s.r;
      data[base + 5] = s.g;
      data[base + 6] = s.b;
      data[base + 7] = s.a;
    }

    try {
      return await _channel.invokeMethod<bool>('applySmudge', {
            'samples': data,
            'sampleCount': samples.length,
          }) ??
          false;
    } catch (e) {
      return false;
    }
  }

  /// Apply warp deformation using a [WarpMesh].
  ///
  /// The mesh control points are uploaded as a Float32List of
  /// (origX, origY, dispX, dispY) tuples.
  Future<bool> applyWarp(WarpMesh mesh) async {
    if (!isInitialized) return false;

    try {
      return await _channel.invokeMethod<bool>('applyWarp', {
            'meshData': mesh.toFloat32List(),
            'meshCols': mesh.columns,
            'meshRows': mesh.rows,
            'boundsLeft': mesh.bounds.left,
            'boundsTop': mesh.bounds.top,
            'boundsWidth': mesh.bounds.width,
            'boundsHeight': mesh.bounds.height,
          }) ??
          false;
    } catch (e) {
      return false;
    }
  }
}

// ═══════════════════════════════════════════════════════════════
// DATA TYPES
// ═══════════════════════════════════════════════════════════════

/// Packed smudge sample data for GPU upload.
class SmudgeSampleData {
  final double x, y;
  final double radius;
  final double strength;
  final double r, g, b, a;

  const SmudgeSampleData({
    required this.x,
    required this.y,
    required this.radius,
    required this.strength,
    required this.r,
    required this.g,
    required this.b,
    required this.a,
  });

  /// Create from a color and position.
  factory SmudgeSampleData.from({
    required double x,
    required double y,
    required double radius,
    required double strength,
    required ui.Color color,
  }) {
    return SmudgeSampleData(
      x: x,
      y: y,
      radius: radius,
      strength: strength,
      r: color.r,
      g: color.g,
      b: color.b,
      a: color.a,
    );
  }
}
