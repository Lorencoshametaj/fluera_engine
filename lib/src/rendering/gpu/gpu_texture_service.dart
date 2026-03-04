import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

/// 🎯 GPU TEXTURE SERVICE — dart:gpu render pass for texture overlay
///
/// ⚠️ flutter_gpu is NOT yet available on Flutter stable channel.
/// This service provides the API surface and will be connected to the
/// real dart:gpu implementation when flutter_gpu lands in stable.
///
/// Currently returns isAvailable = false, causing BrushEngine to fall
/// through to the ImageShader CPU path for texture overlay.
class GpuTextureService {
  GpuTextureService._();

  static GpuTextureService? _instance;
  static GpuTextureService get instance {
    _instance ??= GpuTextureService._();
    return _instance!;
  }

  bool _initialized = false;

  /// Whether dart:gpu texture overlay is available.
  /// Currently always false — flutter_gpu not in stable SDK.
  bool get isAvailable => false;

  /// Initialize — call once at startup (idempotent).
  ///
  /// When flutter_gpu lands in stable, this will:
  /// 1. Load the shader bundle (gpu_shaders.shaderbundle)
  /// 2. Create the render pipeline (vertex + fragment shaders)
  /// 3. Set _available = true
  void initialize() {
    if (_initialized) return;
    _initialized = true;

    // flutter_gpu is not available on Flutter stable (3.38.x).
    // The shader bundle and GLSL sources are ready in:
    //   - shaders/gpu_texture_overlay.vert
    //   - shaders/gpu_texture_overlay.frag
    //   - gpu_shaders.shaderbundle.json
    //   - hook/build.dart
    // When flutter_gpu is added to stable, import 'package:flutter_gpu/gpu.dart'
    // and wire the render pipeline here.
  }

  /// Generate a procedural erosion mask using a single GPU render pass.
  ///
  /// Returns null (GPU unavailable). BrushEngine falls through to CPU path.
  ///
  /// When flutter_gpu is available, this will:
  /// - Create an output texture (stroke bounds size)
  /// - Bind uniform buffer (intensity, grainScale, rotation, noiseType)
  /// - Draw a full-screen quad with procedural grain fragment shader
  /// - Return texture.asImage() for Canvas compositing
  ui.Image? renderErosionMask({
    required int width,
    required int height,
    required double intensity,
    double grainScale = 50.0,
    double rotation = 0.0,
    int noiseType = 0,
    int? seed,
  }) {
    return null; // GPU unavailable
  }
}
