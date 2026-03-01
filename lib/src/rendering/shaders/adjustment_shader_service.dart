import 'dart:ui' as ui;
import 'package:flutter/painting.dart';
import '../../core/editing/adjustment_layer.dart';
import '../../core/engine_scope.dart';
import '../../core/engine_error.dart';

/// 🎨 ADJUSTMENT SHADER SERVICE — GPU-accelerated non-destructive color transforms.
///
/// Loads `adjustment.frag` and provides uniform binding from [AdjustmentStack].
/// Uses the same `FragmentProgram.fromAsset` pattern as [ShaderBrushService].
///
/// ```dart
/// await service.initialize();
/// if (service.isAvailable) {
///   final paint = service.createPaint(stack, width, height);
///   canvas.drawRect(rect, paint);
/// }
/// ```
class AdjustmentShaderService {
  ui.FragmentProgram? _program;
  ui.FragmentShader? _shader;
  bool _initialized = false;
  bool _initAttempted = false;

  /// Whether the GPU shader is loaded and ready.
  bool get isAvailable => _initialized;

  /// Load the shader from assets. Safe to call multiple times.
  Future<void> initialize() async {
    if (_initAttempted) return;
    _initAttempted = true;

    try {
      const prefix = 'packages/fluera_engine/shaders';
      _program = await ui.FragmentProgram.fromAsset('$prefix/adjustment.frag');
      _shader = _program!.fragmentShader();
      _initialized = true;
    } catch (e, stack) {
      _initialized = false;
      if (EngineScope.hasScope) {
        EngineScope.current.errorRecovery.reportError(
          EngineError(
            severity: ErrorSeverity.transient,
            domain: ErrorDomain.rendering,
            source:
                'AdjustmentShaderService: Failed to load adjustment shader. CPU fallback active.',
            original: e,
            stack: stack,
          ),
        );
      }
    }
  }

  /// Create a [Paint] with the shader bound to the given [stack].
  ///
  /// The [inputImage] is the captured content below the adjustment node.
  /// [width] and [height] are the viewport dimensions for UV computation.
  ///
  /// Returns null if the shader is not available (CPU fallback should be used).
  Paint? createPaint(
    AdjustmentStack stack,
    ui.Image inputImage,
    double width,
    double height,
  ) {
    if (!_initialized || _shader == null) return null;

    final shader = _shader!;
    int idx = 0;

    // Resolution
    shader.setFloat(idx++, width); // uResX
    shader.setFloat(idx++, height); // uResY

    // Flatten the stack into aggregated uniform values.
    // Multiple adjustments of the same type are composited by accumulation.
    double brightness = 0.0;
    double contrast = 1.0;
    double saturation = 1.0;
    double hueShift = 0.0;
    double exposure = 0.0;
    double gamma = 1.0;
    double levelsInBlack = 0.0;
    double levelsInWhite = 1.0;
    double levelsOutBlack = 0.0;
    double levelsOutWhite = 1.0;
    double levelsMidtone = 1.0;
    double invert = 0.0;
    double threshold = -1.0; // -1 = disabled
    double sepiaIntensity = 0.0;

    for (final layer in stack.layers) {
      if (!layer.enabled) continue;
      final op = layer.opacity;

      switch (layer.type) {
        case AdjustmentType.brightness:
          brightness += (layer.parameters['amount'] ?? 0.0) * op;
        case AdjustmentType.contrast:
          final f = layer.parameters['factor'] ?? 1.0;
          contrast *= 1.0 + (f - 1.0) * op;
        case AdjustmentType.saturation:
          final f = layer.parameters['factor'] ?? 1.0;
          saturation *= 1.0 + (f - 1.0) * op;
        case AdjustmentType.hueShift:
          hueShift += (layer.parameters['degrees'] ?? 0.0) * op;
        case AdjustmentType.exposure:
          exposure += (layer.parameters['stops'] ?? 0.0) * op;
        case AdjustmentType.gamma:
          final g = layer.parameters['gamma'] ?? 1.0;
          gamma *= 1.0 + (g - 1.0) * op;
        case AdjustmentType.levels:
          levelsInBlack = layer.parameters['inBlack'] ?? 0.0;
          levelsInWhite = layer.parameters['inWhite'] ?? 1.0;
          levelsOutBlack = layer.parameters['outBlack'] ?? 0.0;
          levelsOutWhite = layer.parameters['outWhite'] ?? 1.0;
          levelsMidtone = layer.parameters['midtone'] ?? 1.0;
        case AdjustmentType.invert:
          invert = op > 0.5 ? 1.0 : 0.0;
        case AdjustmentType.threshold:
          threshold = layer.parameters['threshold'] ?? 0.5;
        case AdjustmentType.sepia:
          sepiaIntensity += (layer.parameters['intensity'] ?? 1.0) * op;
      }
    }

    shader.setFloat(idx++, brightness);
    shader.setFloat(idx++, contrast);
    shader.setFloat(idx++, saturation);
    shader.setFloat(idx++, hueShift);
    shader.setFloat(idx++, exposure);
    shader.setFloat(idx++, gamma);
    shader.setFloat(idx++, levelsInBlack);
    shader.setFloat(idx++, levelsInWhite);
    shader.setFloat(idx++, levelsOutBlack);
    shader.setFloat(idx++, levelsOutWhite);
    shader.setFloat(idx++, levelsMidtone);
    shader.setFloat(idx++, invert);
    shader.setFloat(idx++, threshold);
    shader.setFloat(idx++, sepiaIntensity);

    // Input texture sampler
    shader.setImageSampler(0, inputImage);

    return Paint()..shader = shader;
  }

  /// Dispose the shader resources.
  void dispose() {
    _shader?.dispose();
    _shader = null;
    _program = null;
    _initialized = false;
  }
}
