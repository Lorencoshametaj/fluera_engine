/**
 * vk_image_jni_bridge.cpp — JNI bridge for Vulkan image processing
 *
 * Exposes vk_image_processor.h C API to Kotlin via JNI.
 */

#include <android/native_window.h>
#include <android/native_window_jni.h>
#include <cstring>
#include <jni.h>

#include "vk_image_processor.h"

#define JNI_FUNC(name)                                                         \
  Java_com_flueraengine_fluera_1engine_VulkanImageProcessorPlugin_##name

extern "C" {

JNIEXPORT jint JNICALL JNI_FUNC(nativeIsAvailable)(JNIEnv *, jobject) {
  return vkip_is_available();
}

JNIEXPORT jint JNICALL JNI_FUNC(nativeInit)(JNIEnv *env, jobject,
                                            jobject surface, jint width,
                                            jint height) {
  ANativeWindow *window = ANativeWindow_fromSurface(env, surface);
  if (!window)
    return 0;
  int result = vkip_init(width, height, window);
  ANativeWindow_release(window);
  return result;
}

JNIEXPORT jint JNICALL JNI_FUNC(nativeUploadImage)(JNIEnv *env, jobject,
                                                   jbyteArray rgba, jint w,
                                                   jint h) {
  jbyte *data = env->GetByteArrayElements(rgba, nullptr);
  if (!data)
    return 0;
  int result = vkip_upload_image((const uint8_t *)data, w, h);
  env->ReleaseByteArrayElements(rgba, data, JNI_ABORT);
  return result;
}

JNIEXPORT void JNICALL JNI_FUNC(nativeApplyFilters)(
    JNIEnv *, jobject, jfloat brightness, jfloat contrast, jfloat saturation,
    jfloat hueShift, jfloat temperature, jfloat opacity, jfloat vignette) {
  VkipFilterParams params = {};
  params.brightness = brightness;
  params.contrast = contrast;
  params.saturation = saturation;
  params.hueShift = hueShift;
  params.temperature = temperature;
  params.opacity = opacity;
  params.vignette = vignette;
  vkip_apply_filters(&params);
}

JNIEXPORT void JNICALL JNI_FUNC(nativeApplyBlur)(JNIEnv *, jobject,
                                                 jfloat radius) {
  vkip_apply_blur(radius);
}

JNIEXPORT void JNICALL JNI_FUNC(nativeApplySharpen)(JNIEnv *, jobject,
                                                    jfloat amount) {
  vkip_apply_sharpen(amount);
}

JNIEXPORT void JNICALL JNI_FUNC(nativeGenerateMipmaps)(JNIEnv *, jobject) {
  vkip_generate_mipmaps();
}

JNIEXPORT void JNICALL JNI_FUNC(nativeCleanup)(JNIEnv *, jobject) {
  vkip_cleanup();
}

JNIEXPORT void JNICALL JNI_FUNC(nativeApplyHsl)(JNIEnv *env, jobject,
                                                jfloatArray adjustments) {
  jfloat *data = env->GetFloatArrayElements(adjustments, nullptr);
  if (!data)
    return;
  VkipHslParams params = {};
  int len = env->GetArrayLength(adjustments);
  if (len > 24)
    len = 24;
  for (int i = 0; i < len; i++)
    params.adj[i] = data[i];
  env->ReleaseFloatArrayElements(adjustments, data, JNI_ABORT);
  vkip_apply_hsl(&params);
}

JNIEXPORT void JNICALL JNI_FUNC(nativeApplyBilateralDenoise)(JNIEnv *, jobject,
                                                             jfloat strength) {
  vkip_apply_bilateral_denoise(strength);
}

JNIEXPORT void JNICALL JNI_FUNC(nativeApplyToneCurve)(JNIEnv *env, jobject,
                                                      jfloatArray curveData) {
  jfloat *data = env->GetFloatArrayElements(curveData, nullptr);
  if (!data)
    return;
  VkipToneCurveParams params = {};
  int len = env->GetArrayLength(curveData);
  if (len > 32)
    len = 32;
  memcpy(&params, data, len * sizeof(float));
  env->ReleaseFloatArrayElements(curveData, data, JNI_ABORT);
  vkip_apply_tone_curve(&params);
}

JNIEXPORT void JNICALL JNI_FUNC(nativeApplyClarity)(JNIEnv *, jobject,
                                                    jfloat clarity,
                                                    jfloat texturePower) {
  VkipClarityParams params = {};
  params.texelSizeX = 0; // filled by C API
  params.texelSizeY = 0;
  params.clarity = clarity;
  params.texturePower = texturePower;
  vkip_apply_clarity(&params);
}

JNIEXPORT void JNICALL JNI_FUNC(nativeApplySplitToning)(
    JNIEnv *, jobject, jfloat highR, jfloat highG, jfloat highB, jfloat highI,
    jfloat shadR, jfloat shadG, jfloat shadB, jfloat shadI, jfloat balance) {
  VkipSplitToningParams params = {};
  params.highlightR = highR;
  params.highlightG = highG;
  params.highlightB = highB;
  params.highlightIntensity = highI;
  params.shadowR = shadR;
  params.shadowG = shadG;
  params.shadowB = shadB;
  params.shadowIntensity = shadI;
  params.balance = balance;
  vkip_apply_split_toning(&params);
}

JNIEXPORT void JNICALL JNI_FUNC(nativeApplyFilmGrain)(JNIEnv *, jobject,
                                                      jfloat intensity,
                                                      jfloat size, jfloat seed,
                                                      jfloat lumResponse) {
  VkipFilmGrainParams params = {};
  params.intensity = intensity;
  params.size = size;
  params.seed = seed;
  params.luminanceResponse = lumResponse;
  vkip_apply_film_grain(&params);
}

} // extern "C"
