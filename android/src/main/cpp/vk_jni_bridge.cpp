// vk_jni_bridge.cpp — JNI bridge between Kotlin VulkanStrokeOverlayPlugin and
// C++ VkStrokeRenderer Exposes native functions for init, render, transform,
// clear, resize, destroy.

#include "vk_stroke_renderer.h"
#include <android/native_window_jni.h>
#include <jni.h>

static VkStrokeRenderer *g_renderer = nullptr;

extern "C" {

// ═══════════════════════════════════════════════════════════════════
// nativeInit — Initialize Vulkan renderer from a Surface
// ═══════════════════════════════════════════════════════════════════

JNIEXPORT jboolean JNICALL
Java_com_flueraengine_fluera_1engine_VulkanStrokeOverlayPlugin_nativeInit(
    JNIEnv *env, jobject /* this */, jobject surface, jint width, jint height) {
  if (g_renderer) {
    g_renderer->destroy();
    delete g_renderer;
  }

  ANativeWindow *window = ANativeWindow_fromSurface(env, surface);
  if (!window) {
    LOGE("ANativeWindow_fromSurface returned null");
    return JNI_FALSE;
  }

  // Set buffer geometry to match requested size
  ANativeWindow_setBuffersGeometry(window, width, height,
                                   AHARDWAREBUFFER_FORMAT_R8G8B8A8_UNORM);

  g_renderer = new VkStrokeRenderer();
  if (!g_renderer->init(window, width, height)) {
    LOGE("VkStrokeRenderer::init failed");
    delete g_renderer;
    g_renderer = nullptr;
    ANativeWindow_release(window);
    return JNI_FALSE;
  }

  return JNI_TRUE;
}

// ═══════════════════════════════════════════════════════════════════
// nativeUpdateAndRender — Tessellate + render stroke
// points: [x0, y0, x1, y1, ...], color: ARGB int, width: logical px
// ═══════════════════════════════════════════════════════════════════

JNIEXPORT void JNICALL
Java_com_flueraengine_fluera_1engine_VulkanStrokeOverlayPlugin_nativeUpdateAndRender(
    JNIEnv *env, jobject /* this */, jfloatArray pointsArray, jint colorArgb,
    jfloat strokeWidth, jint totalPoints, jint brushType,
    jfloat pencilBaseOpacity, jfloat pencilMaxOpacity,
    jfloat pencilMinPressure, jfloat pencilMaxPressure,
    jfloat fountainThinning, jfloat fountainNibAngleDeg,
    jfloat fountainNibStrength, jfloat fountainPressureRate,
    jint fountainTaperEntry) {
  if (!g_renderer || !g_renderer->isInitialized())
    return;

  jsize len = env->GetArrayLength(pointsArray);
  if (len < 10)
    return; // Need at least 2 points (10 floats: x,y,p,tx,ty × 2)

  jfloat *pts = env->GetFloatArrayElements(pointsArray, nullptr);
  if (!pts)
    return;

  int pointCount = len / 5; // Stride 5: x, y, pressure, tiltX, tiltY

  // Extract ARGB color
  float a = ((colorArgb >> 24) & 0xFF) / 255.0f;
  float r = ((colorArgb >> 16) & 0xFF) / 255.0f;
  float g = ((colorArgb >> 8) & 0xFF) / 255.0f;
  float b = (colorArgb & 0xFF) / 255.0f;

  g_renderer->updateAndRender(pts, pointCount, r, g, b, a, strokeWidth,
                              totalPoints, brushType,
                              pencilBaseOpacity, pencilMaxOpacity,
                              pencilMinPressure, pencilMaxPressure,
                                                            fountainThinning, fountainNibAngleDeg,
                              fountainNibStrength, fountainPressureRate,
                              fountainTaperEntry);

  env->ReleaseFloatArrayElements(pointsArray, pts, JNI_ABORT);
}

// ═══════════════════════════════════════════════════════════════════
// nativeSetTransform — Set 4x4 canvas transform matrix
// ═══════════════════════════════════════════════════════════════════

JNIEXPORT void JNICALL
Java_com_flueraengine_fluera_1engine_VulkanStrokeOverlayPlugin_nativeSetTransform(
    JNIEnv *env, jobject /* this */, jfloatArray matrixArray) {
  if (!g_renderer || !g_renderer->isInitialized())
    return;

  jfloat *m = env->GetFloatArrayElements(matrixArray, nullptr);
  if (!m)
    return;

  g_renderer->setTransform(m);

  env->ReleaseFloatArrayElements(matrixArray, m, JNI_ABORT);
}

// ═══════════════════════════════════════════════════════════════════
// nativeClear — Clear the render target (transparent)
// ═══════════════════════════════════════════════════════════════════

JNIEXPORT void JNICALL
Java_com_flueraengine_fluera_1engine_VulkanStrokeOverlayPlugin_nativeClear(
    JNIEnv * /* env */, jobject /* this */) {
  if (g_renderer && g_renderer->isInitialized()) {
    g_renderer->clearFrame();
  }
}

// ═══════════════════════════════════════════════════════════════════
// nativeResize — Resize the render target
// ═══════════════════════════════════════════════════════════════════

JNIEXPORT jboolean JNICALL
Java_com_flueraengine_fluera_1engine_VulkanStrokeOverlayPlugin_nativeResize(
    JNIEnv * /* env */, jobject /* this */, jint width, jint height) {
  if (!g_renderer || !g_renderer->isInitialized())
    return JNI_FALSE;
  return g_renderer->resize(width, height) ? JNI_TRUE : JNI_FALSE;
}

// ═══════════════════════════════════════════════════════════════════
// nativeDestroy — Cleanup all Vulkan resources
// ═══════════════════════════════════════════════════════════════════

JNIEXPORT void JNICALL
Java_com_flueraengine_fluera_1engine_VulkanStrokeOverlayPlugin_nativeDestroy(
    JNIEnv * /* env */, jobject /* this */) {
  if (g_renderer) {
    g_renderer->destroy();
    delete g_renderer;
    g_renderer = nullptr;
  }
}

// ═══════════════════════════════════════════════════════════════════
// nativeIsInitialized — Check if the renderer is ready
// ═══════════════════════════════════════════════════════════════════

JNIEXPORT jboolean JNICALL
Java_com_flueraengine_fluera_1engine_VulkanStrokeOverlayPlugin_nativeIsInitialized(
    JNIEnv * /* env */, jobject /* this */) {
  return (g_renderer && g_renderer->isInitialized()) ? JNI_TRUE : JNI_FALSE;
}

// ═══════════════════════════════════════════════════════════════════
// nativeGetStats — Get performance statistics snapshot
// Returns float[11]: [p50us, p90us, p99us, vertexCount, drawCalls,
//                     swapchainImages, totalFrames, active,
//                     apiMajor, apiMinor, apiPatch]
// ═══════════════════════════════════════════════════════════════════

JNIEXPORT jfloatArray JNICALL
Java_com_flueraengine_fluera_1engine_VulkanStrokeOverlayPlugin_nativeGetStats(
    JNIEnv *env, jobject /* this */) {
  jfloatArray result = env->NewFloatArray(11);
  if (!result)
    return nullptr;

  float data[11] = {0};
  if (g_renderer && g_renderer->isInitialized()) {
    VkStrokeStats s = g_renderer->getStats();
    data[0] = s.frameTimeP50Us;
    data[1] = s.frameTimeP90Us;
    data[2] = s.frameTimeP99Us;
    data[3] = (float)s.vertexCount;
    data[4] = (float)s.drawCalls;
    data[5] = (float)s.swapchainImages;
    data[6] = (float)s.totalFrames;
    data[7] = s.active ? 1.0f : 0.0f;
    data[8] = (float)s.apiVersionMajor;
    data[9] = (float)s.apiVersionMinor;
    data[10] = (float)s.apiVersionPatch;
  }

  env->SetFloatArrayRegion(result, 0, 11, data);
  return result;
}

// ═══════════════════════════════════════════════════════════════════
// nativeGetDeviceName — Get GPU device name
// ═══════════════════════════════════════════════════════════════════

JNIEXPORT jstring JNICALL
Java_com_flueraengine_fluera_1engine_VulkanStrokeOverlayPlugin_nativeGetDeviceName(
    JNIEnv *env, jobject /* this */) {
  if (g_renderer && g_renderer->isInitialized()) {
    VkStrokeStats s = g_renderer->getStats();
    return env->NewStringUTF(s.deviceName);
  }
  return env->NewStringUTF("N/A");
}

} // extern "C"
