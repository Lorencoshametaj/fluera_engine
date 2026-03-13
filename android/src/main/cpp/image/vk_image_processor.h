/**
 * vk_image_processor.h — Fluera Engine Vulkan GPU Image Processing
 *
 * GPU-accelerated image filtering: color grading, blur, sharpen,
 * vignette, and hardware mipmapping via Vulkan render pipelines.
 *
 * Architecture:
 *   Upload RGBA → VkImage (source) → pipeline passes → VkImage (output)
 *   → VkSwapchain → Flutter SurfaceProducer
 *
 * Requirements: Android API 29+ (Vulkan 1.1)
 */

#ifndef FLUERA_VK_IMAGE_PROCESSOR_H
#define FLUERA_VK_IMAGE_PROCESSOR_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Filter parameters (matches Dart ImageFilterParams layout)
typedef struct {
  float brightness;  // -1..+1
  float contrast;    // -1..+1
  float saturation;  // -1..+1
  float hueShift;    // -1..+1 (maps to -π..+π)
  float temperature; // -1..+1
  float opacity;     // 0..1
  float vignette;    // 0..1
  float _pad;
} VkipFilterParams;

/// Blur parameters
typedef struct {
  float texelSize;
  float radius;
  float sigma;
  float _pad;
} VkipBlurParams;

/// Sharpen parameters
typedef struct {
  float texelSizeX;
  float texelSizeY;
  float amount;
  float _pad;
} VkipSharpenParams;

/**
 * Initialize the Vulkan image processing pipeline.
 *
 * @param width         Output texture width
 * @param height        Output texture height
 * @param nativeWindow  ANativeWindow* from SurfaceProducer
 * @return              1 on success, 0 on failure
 */
int vkip_init(int width, int height, void *nativeWindow);

/**
 * Upload RGBA image data to GPU source texture.
 *
 * @param rgba   RGBA pixel data (4 bytes per pixel)
 * @param w      Image width
 * @param h      Image height
 * @return       1 on success, 0 on failure
 */
int vkip_upload_image(const uint8_t *rgba, int w, int h);

/**
 * Apply color grading filter chain and present result.
 */
void vkip_apply_filters(const VkipFilterParams *params);

/**
 * Apply Gaussian blur and present result.
 *
 * @param radius  Blur radius in pixels
 */
void vkip_apply_blur(float radius);

/**
 * Apply unsharp mask (sharpen) and present result.
 *
 * @param amount  Sharpen strength (0..2)
 */
void vkip_apply_sharpen(float amount);

/**
 * Generate hardware mipmaps for the source texture.
 */
void vkip_generate_mipmaps(void);

/// HSL per-channel parameters (7 bands × 3 adjustments = 21 floats + 3 pad)
typedef struct {
  float adj[24]; // [band*3+0]=hue, [band*3+1]=sat, [band*3+2]=light
                 // Bands: Red, Orange, Yellow, Green, Cyan, Blue, Magenta
} VkipHslParams;

/// Bilateral denoise parameters
typedef struct {
  float texelSizeX; // 1.0 / width
  float texelSizeY; // 1.0 / height
  float strength;   // 0..1
  float rangeSigma; // color similarity threshold (~0.1)
} VkipBilateralParams;

/**
 * Apply per-channel HSL adjustments via GPU fragment shader.
 * True RGB→HSL→adjust→HSL→RGB per pixel — cannot be done with a matrix.
 */
void vkip_apply_hsl(const VkipHslParams *params);

/**
 * Apply edge-preserving bilateral denoise via GPU fragment shader.
 */
void vkip_apply_bilateral_denoise(float strength);

/// Tone curve parameters: 4 control points per curve × 4 curves (master + RGB)
/// Each curve: (x0,y0, x1,y1, x2,y2, x3,y3) packed as 2 vec4s = 128 bytes total
typedef struct {
  float masterPts[8]; // 4 control points for master luminance
  float redPts[8];    // 4 control points for red channel
  float greenPts[8];  // 4 control points for green channel
  float bluePts[8];   // 4 control points for blue channel
} VkipToneCurveParams;

/// Clarity/texture parameters (local contrast enhancement)
typedef struct {
  float texelSizeX;   // 1.0 / width
  float texelSizeY;   // 1.0 / height
  float clarity;      // -1..+1 mid-frequency local contrast
  float texturePower; // -1..+1 high-frequency fine detail
} VkipClarityParams;

/// Split toning parameters (highlight/shadow color grading)
typedef struct {
  float highlightR, highlightG, highlightB, highlightIntensity;
  float shadowR, shadowG, shadowB, shadowIntensity;
  float balance; // -1..+1 shifts crossover midpoint
  float pad0, pad1, pad2;
} VkipSplitToningParams;

/// Film grain parameters
typedef struct {
  float intensity;         // 0..1 grain strength
  float size;              // grain size (1.0 = finest)
  float seed;              // temporal variation seed
  float luminanceResponse; // 0..1 luminance-dependent grain
} VkipFilmGrainParams;

/**
 * Apply tone curve (cubic spline RGB curves) and present result.
 */
void vkip_apply_tone_curve(const VkipToneCurveParams *params);

/**
 * Apply clarity and texture enhancement (local contrast) and present result.
 */
void vkip_apply_clarity(const VkipClarityParams *params);

/**
 * Apply split toning (highlight/shadow color grading) and present result.
 */
void vkip_apply_split_toning(const VkipSplitToningParams *params);

/**
 * Apply film grain overlay and present result.
 */
void vkip_apply_film_grain(const VkipFilmGrainParams *params);

/**
 * Check if Vulkan image processing is available.
 */
int vkip_is_available(void);

/**
 * Clean up all Vulkan resources.
 */
void vkip_cleanup(void);

#ifdef __cplusplus
}
#endif

#endif // FLUERA_VK_IMAGE_PROCESSOR_H
