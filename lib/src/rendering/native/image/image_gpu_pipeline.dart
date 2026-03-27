import '../../../core/models/color_adjustments.dart';

// =============================================================================
// 🎮 IMAGE GPU PIPELINE — Cross-Platform Abstraction
//
// Abstract interface for GPU-accelerated image processing.
// Concrete implementations:
//   - VulkanImagePipeline (Android) — uses Vulkan compute shaders
//   - MetalImagePipeline (iOS)     — uses Metal compute shaders
//
// The CPU fallback (ImageAdjustmentEngine + ColorFilter.matrix) is always
// available. GPU pipeline adds:
//   - Real HSL per-channel adjustments (requires pixel shader)
//   - True bilateral noise reduction (edge-preserving)
//   - Hardware-accelerated color grading
//   - Lens distortion correction
// =============================================================================

/// Abstract interface for GPU image processing.
/// Implementations handle platform-specific GPU dispatch (Vulkan/Metal).
abstract class ImageGpuPipeline {
  /// Apply per-channel HSL adjustments using a fragment shader.
  /// This can't be done with a 5×4 color matrix — requires
  /// RGB→HSL→adjust→HSL→RGB per pixel.
  Future<void> applyHslPerChannel(String imageId, List<double> hslAdjustments);

  /// Apply bilateral filter for edge-preserving noise reduction.
  Future<void> applyBilateralDenoise(String imageId, double strength);

  /// Apply full color grading pipeline in one GPU pass.
  Future<void> applyColorGrading(String imageId, ColorAdjustments adj);

  /// Apply lens distortion correction (barrel/pincushion).
  Future<void> applyLensCorrection(
    String imageId, {
    required double k1,
    required double k2,
  });

  /// Check if the GPU pipeline is available on this device.
  bool get isAvailable;

  /// Platform identifier for debugging.
  String get platformName;
}
