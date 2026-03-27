/*
 * JNI bridge for RNNoise — exposes create/processFrame/destroy to Kotlin.
 *
 * RNNoise processes frames of exactly 480 samples at 48kHz (10ms windows).
 * Input/output are float arrays in [-32768, 32767] range.
 * Returns VAD (voice activity detection) probability [0, 1].
 */

#include "rnnoise.h"
#include <jni.h>

JNIEXPORT jlong JNICALL
Java_com_flueraengine_fluera_1engine_RNNoise_nativeCreate(JNIEnv *env,
                                                          jclass clazz) {
  DenoiseState *st = rnnoise_create(NULL);
  return (jlong)(intptr_t)st;
}

JNIEXPORT jfloat JNICALL
Java_com_flueraengine_fluera_1engine_RNNoise_nativeProcessFrame(
    JNIEnv *env, jclass clazz, jlong state, jfloatArray frame) {

  DenoiseState *st = (DenoiseState *)(intptr_t)state;
  if (st == NULL)
    return 0.0f;

  jfloat *data = (*env)->GetFloatArrayElements(env, frame, NULL);
  if (data == NULL)
    return 0.0f;

  /* rnnoise_process_frame works in-place: output overwrites input */
  float vad = rnnoise_process_frame(st, data, data);

  (*env)->ReleaseFloatArrayElements(env, frame, data, 0);
  return vad;
}

JNIEXPORT void JNICALL
Java_com_flueraengine_fluera_1engine_RNNoise_nativeDestroy(JNIEnv *env,
                                                           jclass clazz,
                                                           jlong state) {
  DenoiseState *st = (DenoiseState *)(intptr_t)state;
  if (st != NULL) {
    rnnoise_destroy(st);
  }
}

JNIEXPORT jint JNICALL
Java_com_flueraengine_fluera_1engine_RNNoise_nativeGetFrameSize(JNIEnv *env,
                                                                jclass clazz) {
  return (jint)rnnoise_get_frame_size();
}
