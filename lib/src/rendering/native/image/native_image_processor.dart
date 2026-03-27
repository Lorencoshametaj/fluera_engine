import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'image_filter_params.dart';

/// 🎯 NativeImageProcessor — GPU-accelerated image filter pipeline
///
/// Platform dispatch:
/// - iOS: Metal compute/render shaders via `MetalImageProcessorPlugin`
/// - Android: Vulkan render pipeline via `VulkanImageProcessorPlugin`
///
/// Uses FlutterTextureRegistry to composite GPU-rendered output
/// back into the Flutter widget tree.
///
/// Architecture:
///   Dart (filter params) → MethodChannel → native GPU pipeline
///   → offscreen texture → FlutterTexture → widget tree
class NativeImageProcessor {
  NativeImageProcessor._();

  static NativeImageProcessor? _instance;
  static NativeImageProcessor get instance {
    _instance ??= NativeImageProcessor._();
    return _instance!;
  }

  static const _channel = MethodChannel(
    'com.flueraengine/native_image_processor',
  );

  bool _initialized = false;
  bool _available = false;

  /// Whether native GPU image processing is available on this device.
  bool get isAvailable => _available;

  /// Active texture IDs mapped by image path (for cache management).
  final Map<String, int> _activeTextures = {};

  /// Last applied filter params per image (for dirty checking).
  final Map<String, ImageFilterParams> _lastParams = {};

  /// Last dispatched effect keys per image+effect (for dedup).
  /// Key format: "imageId:effectName" → "paramValue"
  final Map<String, String> _lastEffectKeys = {};

  /// Initialize the native GPU pipeline.
  ///
  /// Must be called once at startup (idempotent).
  /// Returns true if GPU image processing is available.
  Future<bool> initialize() async {
    if (_initialized) return _available;
    _initialized = true;

    // Only available on mobile platforms
    if (kIsWeb) return false;

    try {
      final result = await _channel.invokeMethod<bool>('initialize');
      _available = result ?? false;
      if (_available) {
        debugPrint('🎨 NativeImageProcessor: GPU pipeline active');
      } else {
        debugPrint('⚠️ NativeImageProcessor: GPU not available, CPU fallback');
      }
    } catch (e) {
      debugPrint('⚠️ NativeImageProcessor: init failed ($e), CPU fallback');
      _available = false;
    }

    return _available;
  }

  /// Upload an image to the GPU and create a FlutterTexture for it.
  ///
  /// Returns the Flutter texture ID (>= 0) or -1 if failed.
  /// The image bytes must be RGBA format (4 bytes per pixel).
  Future<int> uploadImage(
    String imageId,
    Uint8List rgbaBytes,
    int width,
    int height,
  ) async {
    if (!_available) return -1;

    try {
      final textureId = await _channel.invokeMethod<int>('uploadImage', {
        'imageId': imageId,
        'imageBytes': rgbaBytes,
        'width': width,
        'height': height,
      });

      if (textureId != null && textureId >= 0) {
        _activeTextures[imageId] = textureId;
        debugPrint(
          '🎨 GPU image uploaded: $imageId → texture=$textureId (${width}x$height)',
        );
        return textureId;
      }
    } catch (e) {
      debugPrint('⚠️ GPU image upload failed for $imageId: $e');
    }

    return -1;
  }

  /// Apply filter chain to an uploaded image.
  ///
  /// This is designed for real-time slider interaction — call it on every
  /// slider value change and the GPU will re-render at native speed.
  ///
  /// Returns true if filters were applied successfully.
  Future<bool> applyFilters(String imageId, ImageFilterParams params) async {
    if (!_available) return false;

    final textureId = _activeTextures[imageId];
    if (textureId == null) return false;

    // Skip if params haven't changed (avoid redundant GPU work)
    if (_lastParams[imageId] == params) return true;

    try {
      await _channel.invokeMethod('applyFilters', {
        'imageId': imageId,
        'textureId': textureId,
        ...params.toMap(),
      });
      _lastParams[imageId] = params;
      return true;
    } catch (e) {
      debugPrint('⚠️ GPU applyFilters failed for $imageId: $e');
      return false;
    }
  }

  /// Apply Gaussian blur to an image.
  ///
  /// [radius] is in pixels (0 = no blur, typical range 0..50).
  Future<bool> applyBlur(String imageId, double radius) async {
    if (!_available || radius <= 0) return false;

    final textureId = _activeTextures[imageId];
    if (textureId == null) return false;

    // Dedup: skip if same blur radius was already dispatched
    final key = '$imageId:blur';
    final val = radius.toStringAsFixed(2);
    if (_lastEffectKeys[key] == val) return true;

    try {
      await _channel.invokeMethod('applyBlur', {
        'imageId': imageId,
        'textureId': textureId,
        'radius': radius,
      });
      _lastEffectKeys[key] = val;
      return true;
    } catch (e) {
      debugPrint('⚠️ GPU blur failed for $imageId: $e');
      return false;
    }
  }

  /// Apply unsharp mask (sharpen) to an image.
  ///
  /// [amount] range: 0.0 (none) .. 2.0 (very strong).
  Future<bool> applySharpen(String imageId, double amount) async {
    if (!_available || amount <= 0) return false;

    final textureId = _activeTextures[imageId];
    if (textureId == null) return false;

    final key = '$imageId:sharpen';
    final val = amount.toStringAsFixed(2);
    if (_lastEffectKeys[key] == val) return true;

    try {
      await _channel.invokeMethod('applySharpen', {
        'imageId': imageId,
        'textureId': textureId,
        'amount': amount,
      });
      _lastEffectKeys[key] = val;
      return true;
    } catch (e) {
      debugPrint('⚠️ GPU sharpen failed for $imageId: $e');
      return false;
    }
  }

  /// Generate hardware mipmaps for an uploaded image.
  ///
  /// This enables automatic LOD selection during zoom — the GPU selects
  /// the optimal mip level based on screen coverage.
  Future<bool> generateMipmaps(String imageId) async {
    if (!_available) return false;

    final textureId = _activeTextures[imageId];
    if (textureId == null) return false;

    try {
      await _channel.invokeMethod('generateMipmaps', {
        'imageId': imageId,
        'textureId': textureId,
      });
      return true;
    } catch (e) {
      debugPrint('⚠️ GPU mipmap generation failed for $imageId: $e');
      return false;
    }
  }

  /// Apply Sobel edge detection to an image.
  ///
  /// [strength] 0.0 (original) to 1.0 (full edges).
  /// [invert] if true, white edges on black background.
  Future<bool> applyEdgeDetect(
    String imageId,
    double strength, {
    bool invert = false,
  }) async {
    if (!_available || strength <= 0) return false;

    final textureId = _activeTextures[imageId];
    if (textureId == null) return false;

    final key = '$imageId:edgeDetect';
    final val = '${strength.toStringAsFixed(2)}:$invert';
    if (_lastEffectKeys[key] == val) return true;

    try {
      await _channel.invokeMethod('applyEdgeDetect', {
        'imageId': imageId,
        'textureId': textureId,
        'strength': strength,
        'invert': invert,
      });
      _lastEffectKeys[key] = val;
      return true;
    } catch (e) {
      debugPrint('⚠️ GPU edge detect failed for $imageId: $e');
      return false;
    }
  }

  /// Compute RGB histogram of an uploaded image.
  ///
  /// Returns 768 integers (256 per channel: R, G, B) or empty on failure.
  Future<List<int>> computeHistogram(String imageId) async {
    if (!_available) return [];

    final textureId = _activeTextures[imageId];
    if (textureId == null) return [];

    try {
      final result = await _channel.invokeMethod<List>('computeHistogram', {
        'imageId': imageId,
        'textureId': textureId,
      });
      return result?.cast<int>() ?? [];
    } catch (e) {
      debugPrint('⚠️ GPU histogram failed for $imageId: $e');
      return [];
    }
  }

  /// Auto-adjust levels based on GPU histogram analysis.
  Future<bool> autoLevels(String imageId) async {
    if (!_available) return false;

    final textureId = _activeTextures[imageId];
    if (textureId == null) return false;

    try {
      await _channel.invokeMethod('autoLevels', {
        'imageId': imageId,
        'textureId': textureId,
      });
      return true;
    } catch (e) {
      debugPrint('⚠️ GPU autoLevels failed for $imageId: $e');
      return false;
    }
  }

  /// Apply LUT color grading to an image.
  ///
  /// [lutIndex] is the index into the built-in LUT presets list.
  Future<bool> applyLut(String imageId, int lutIndex) async {
    if (!_available || lutIndex <= 0) return false;

    final textureId = _activeTextures[imageId];
    if (textureId == null) return false;

    final key = '$imageId:lut';
    final val = '$lutIndex';
    if (_lastEffectKeys[key] == val) return true;

    try {
      await _channel.invokeMethod('applyLut', {
        'imageId': imageId,
        'textureId': textureId,
        'lutIndex': lutIndex,
      });
      _lastEffectKeys[key] = val;
      return true;
    } catch (e) {
      debugPrint('⚠️ GPU LUT failed for $imageId: $e');
      return false;
    }
  }

  /// Apply per-channel HSL adjustments via GPU fragment shader.
  ///
  /// [adjustments] is a list of 21 doubles: 7 bands × 3 (hue, sat, lightness).
  /// Band order: Red, Orange, Yellow, Green, Cyan, Blue, Magenta.
  /// Each value is typically in range -1..+1.
  ///
  /// This performs true RGB→HSL→adjust→HSL→RGB per pixel — it cannot be
  /// approximated by a color matrix.
  Future<bool> applyHslPerChannel(
    String imageId,
    List<double> adjustments,
  ) async {
    if (!_initialized) return false;
    try {
      final result = await _channel.invokeMethod('applyHslPerChannel', {
        'imageId': imageId,
        'adjustments': adjustments,
      });
      return result == true;
    } catch (e) {
      debugPrint('⚠️ NativeImageProcessor.applyHslPerChannel error: $e');
      return false;
    }
  }

  /// Apply edge-preserving bilateral denoise via GPU fragment shader.
  ///
  /// [strength] controls the spatial sigma (0.0 = off, 1.0 = maximum).
  /// The bilateral filter preserves edges while smoothing noise.
  Future<bool> applyBilateralDenoise(String imageId, double strength) async {
    if (!_initialized) return false;
    try {
      final result = await _channel.invokeMethod('applyBilateralDenoise', {
        'imageId': imageId,
        'strength': strength,
      });
      return result == true;
    } catch (e) {
      debugPrint('⚠️ NativeImageProcessor.applyBilateralDenoise error: $e');
      return false;
    }
  }

  /// Apply tone curve (cubic spline RGB curves) via GPU.
  ///
  /// [curveData] is 32 floats: 4 curves × 8 values each.
  /// Each curve has 4 control points: (x0,y0, x1,y1, x2,y2, x3,y3).
  /// Curve order: master, red, green, blue.
  /// Identity curve: (0,0, 0.33,0.33, 0.66,0.66, 1,1).
  Future<bool> applyToneCurve(String imageId, List<double> curveData) async {
    if (!_initialized || curveData.length < 32) return false;
    final key = '$imageId:toneCurve';
    final val = curveData.map((v) => v.toStringAsFixed(3)).join(',');
    if (_lastEffectKeys[key] == val) return true;
    try {
      final result = await _channel.invokeMethod('applyToneCurve', {
        'imageId': imageId,
        'curveData': curveData,
      });
      _lastEffectKeys[key] = val;
      return result == true;
    } catch (e) {
      debugPrint('⚠️ NativeImageProcessor.applyToneCurve error: $e');
      return false;
    }
  }

  /// Apply clarity and texture enhancement (local contrast) via GPU.
  ///
  /// [clarity] -1..+1 mid-frequency local contrast boost.
  /// [texturePower] -1..+1 high-frequency fine detail boost.
  Future<bool> applyClarity(
    String imageId, {
    double clarity = 0.0,
    double texturePower = 0.0,
  }) async {
    if (!_initialized) return false;
    final key = '$imageId:clarity';
    final val =
        '${clarity.toStringAsFixed(2)}:${texturePower.toStringAsFixed(2)}';
    if (_lastEffectKeys[key] == val) return true;
    try {
      final result = await _channel.invokeMethod('applyClarity', {
        'imageId': imageId,
        'clarity': clarity,
        'texturePower': texturePower,
      });
      _lastEffectKeys[key] = val;
      return result == true;
    } catch (e) {
      debugPrint('⚠️ NativeImageProcessor.applyClarity error: $e');
      return false;
    }
  }

  /// Apply split toning (highlight/shadow color grading) via GPU.
  ///
  /// Colors are [r, g, b, intensity] with values 0..1.
  /// [balance] -1..+1 shifts the shadow/highlight crossover point.
  Future<bool> applySplitToning(
    String imageId, {
    required List<double> highlightColor,
    required List<double> shadowColor,
    double balance = 0.0,
  }) async {
    if (!_initialized) return false;
    if (highlightColor.length < 4 || shadowColor.length < 4) return false;
    final key = '$imageId:splitToning';
    final val = '${highlightColor.join(',')}|${shadowColor.join(',')}|$balance';
    if (_lastEffectKeys[key] == val) return true;
    try {
      final result = await _channel.invokeMethod('applySplitToning', {
        'imageId': imageId,
        'highlightColor': highlightColor,
        'shadowColor': shadowColor,
        'balance': balance,
      });
      _lastEffectKeys[key] = val;
      return result == true;
    } catch (e) {
      debugPrint('⚠️ NativeImageProcessor.applySplitToning error: $e');
      return false;
    }
  }

  /// Apply film grain overlay via GPU.
  ///
  /// [intensity] 0..1 grain strength.
  /// [size] grain size (1.0 = pixel-level, larger = coarser).
  /// [seed] random seed for temporal variation (change per frame for animation).
  /// [luminanceResponse] 0..1 how much grain varies with brightness.
  Future<bool> applyFilmGrain(
    String imageId, {
    double intensity = 0.3,
    double size = 1.0,
    double seed = 0.0,
    double luminanceResponse = 0.5,
  }) async {
    if (!_initialized) return false;
    final key = '$imageId:filmGrain';
    final val =
        '${intensity.toStringAsFixed(2)}:${size.toStringAsFixed(2)}:${seed.toStringAsFixed(2)}';
    if (_lastEffectKeys[key] == val) return true;
    try {
      final result = await _channel.invokeMethod('applyFilmGrain', {
        'imageId': imageId,
        'intensity': intensity,
        'size': size,
        'seed': seed,
        'luminanceResponse': luminanceResponse,
      });
      _lastEffectKeys[key] = val;
      return result == true;
    } catch (e) {
      debugPrint('⚠️ NativeImageProcessor.applyFilmGrain error: $e');
      return false;
    }
  }

  /// Get the Flutter texture ID for an image.
  ///
  /// Returns -1 if the image hasn't been uploaded to GPU.
  int getTextureId(String imageId) {
    return _activeTextures[imageId] ?? -1;
  }

  /// Release GPU resources for a specific image.
  Future<void> releaseImage(String imageId) async {
    final textureId = _activeTextures.remove(imageId);
    _lastParams.remove(imageId);

    if (textureId != null && _available) {
      try {
        await _channel.invokeMethod('releaseImage', {
          'imageId': imageId,
          'textureId': textureId,
        });
      } catch (e) {
        debugPrint('⚠️ GPU releaseImage failed for $imageId: $e');
      }
    }
  }

  /// Release all GPU resources.
  Future<void> dispose() async {
    if (!_available) return;

    try {
      await _channel.invokeMethod('dispose');
    } catch (e) {
      debugPrint('⚠️ NativeImageProcessor dispose failed: $e');
    }

    _activeTextures.clear();
    _lastParams.clear();
    _available = false;
    _initialized = false;
  }

  /// Invalidate filter cache for an image (e.g., after editing).
  void invalidateCache(String imageId) {
    _lastParams.remove(imageId);
    _lastEffectKeys.removeWhere((k, _) => k.startsWith('$imageId:'));
  }
}
