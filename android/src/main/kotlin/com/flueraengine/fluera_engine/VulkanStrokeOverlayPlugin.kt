package com.flueraengine.fluera_engine

import android.os.Build
import android.view.Surface
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry

/**
 * 🎨 VulkanStrokeOverlayPlugin — Flutter TextureRegistry bridge for C++ Vulkan stroke renderer.
 *
 * Uses SurfaceProducer (Impeller-compatible) for zero-copy GPU texture sharing.
 * Falls back to SurfaceTexture on older Flutter versions.
 */
class VulkanStrokeOverlayPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    private var channel: MethodChannel? = null
    private var textureRegistry: TextureRegistry? = null
    private var reusableFloatBuffer: FloatArray? = null  // Reused to avoid GC pressure

    // SurfaceProducer path (Impeller-compatible)
    private var surfaceProducer: TextureRegistry.SurfaceProducer? = null
    private var surface: Surface? = null
    private var currentTextureId: Long = -1

    companion object {
        private var nativeLibLoaded = false

        fun isVulkanAvailable(): Boolean {
            return Build.VERSION.SDK_INT >= 24
        }

        private fun ensureNativeLib() {
            if (!nativeLibLoaded) {
                try {
                    System.loadLibrary("fluera_vk_stroke")
                    nativeLibLoaded = true
                } catch (e: UnsatisfiedLinkError) {
                    android.util.Log.e("FlueraVk", "Failed to load fluera_vk_stroke: ${e.message}")
                }
            }
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        textureRegistry = binding.textureRegistry
        channel = MethodChannel(binding.binaryMessenger, "fluera_engine/vulkan_stroke")
        channel?.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        destroyTexture()
        textureRegistry = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> {
                result.success(isVulkanAvailable() && ensureAndCheckNative())
            }

            "init" -> {
                val width = (call.argument<Number>("width") ?: 1080).toInt()
                val height = (call.argument<Number>("height") ?: 1920).toInt()

                if (!isVulkanAvailable()) {
                    result.error("VULKAN_UNSUPPORTED", "Vulkan requires API 24+", null)
                    return
                }
                ensureNativeLib()
                if (!nativeLibLoaded) {
                    result.error("NATIVE_LIB_MISSING", "fluera_vk_stroke not loaded", null)
                    return
                }

                // Clean up previous
                destroyTexture()

                try {
                    // Use SurfaceProducer (Impeller-compatible, Flutter 3.22+)
                    val producer = textureRegistry?.createSurfaceProducer()
                    if (producer == null) {
                        result.error("TEXTURE_FAILED", "createSurfaceProducer returned null", null)
                        return
                    }

                    surfaceProducer = producer
                    producer.setSize(width, height)
                    currentTextureId = producer.id()

                    val producerSurface = producer.surface
                    surface = producerSurface

                    // Initialize Vulkan renderer with the Surface
                    val success = nativeInit(producerSurface, width, height)
                    if (success) {
                        android.util.Log.i("FlueraVk", "Vulkan renderer initialized, textureId=$currentTextureId")
                        result.success(currentTextureId)
                    } else {
                        destroyTexture()
                        result.error("VK_INIT_FAILED", "Vulkan init failed", null)
                    }
                } catch (e: Exception) {
                    android.util.Log.e("FlueraVk", "Init error: ${e.message}")
                    destroyTexture()
                    result.error("INIT_EXCEPTION", e.message, null)
                }
            }

            "updateAndRender" -> {
                val points = call.argument<List<Number>>("points")
                val color = (call.argument<Number>("color") ?: 0xFF000000L).toInt()
                val width = (call.argument<Number>("width") ?: 2.0).toDouble()
                val totalPoints = (call.argument<Number>("totalPoints") ?: 0).toInt()
                val brushType = (call.argument<Number>("brushType") ?: 0).toInt()
                val pencilBaseOpacity = (call.argument<Number>("pencilBaseOpacity") ?: 0.4).toFloat()
                val pencilMaxOpacity = (call.argument<Number>("pencilMaxOpacity") ?: 0.8).toFloat()
                val pencilMinPressure = (call.argument<Number>("pencilMinPressure") ?: 0.5).toFloat()
                val pencilMaxPressure = (call.argument<Number>("pencilMaxPressure") ?: 1.2).toFloat()
                val fountainThinning = (call.argument<Number>("fountainThinning") ?: 0.5).toFloat()
                val fountainNibAngleDeg = (call.argument<Number>("fountainNibAngleDeg") ?: 30.0).toFloat()
                val fountainNibStrength = (call.argument<Number>("fountainNibStrength") ?: 0.35).toFloat()
                val fountainPressureRate = (call.argument<Number>("fountainPressureRate") ?: 0.275).toFloat()
                val fountainTaperEntry = (call.argument<Number>("fountainTaperEntry") ?: 6).toInt()

                if (points != null && points.size >= 10) {
                    val needed = points.size
                    // Reuse buffer when exact size matches, otherwise create new
                    if (reusableFloatBuffer == null || reusableFloatBuffer!!.size != needed) {
                        reusableFloatBuffer = FloatArray(needed)
                    }
                    val buf = reusableFloatBuffer!!
                    for (i in 0 until needed) {
                        buf[i] = points[i].toFloat()
                    }
                    nativeUpdateAndRender(buf, color, width.toFloat(), totalPoints, brushType,
                        pencilBaseOpacity, pencilMaxOpacity, pencilMinPressure, pencilMaxPressure,
                        fountainThinning, fountainNibAngleDeg, fountainNibStrength, fountainPressureRate, fountainTaperEntry)
                }
                result.success(null)
            }

            "setTransform" -> {
                val matrix = call.argument<List<Number>>("matrix")
                if (matrix != null && matrix.size == 16) {
                    val floatArray = FloatArray(16) { matrix[it].toFloat() }
                    nativeSetTransform(floatArray)
                }
                result.success(null)
            }

            "clear" -> {
                nativeClear()
                result.success(null)
            }

            "resize" -> {
                val w = (call.argument<Number>("width") ?: 1080).toInt()
                val h = (call.argument<Number>("height") ?: 1920).toInt()

                // Resize SurfaceProducer
                surfaceProducer?.setSize(w, h)

                val success = nativeResize(w, h)
                result.success(success)
            }

            "destroy" -> {
                nativeDestroy()
                destroyTexture()
                result.success(null)
            }

            "getStats" -> {
                try {
                    val stats = nativeGetStats()
                    val deviceName = nativeGetDeviceName()
                    if (stats != null && stats.size >= 11) {
                        result.success(mapOf(
                            "p50us" to stats[0].toDouble(),
                            "p90us" to stats[1].toDouble(),
                            "p99us" to stats[2].toDouble(),
                            "vertexCount" to stats[3].toInt(),
                            "drawCalls" to stats[4].toInt(),
                            "swapchainImages" to stats[5].toInt(),
                            "totalFrames" to stats[6].toInt(),
                            "active" to (stats[7] > 0.5f),
                            "apiMajor" to stats[8].toInt(),
                            "apiMinor" to stats[9].toInt(),
                            "apiPatch" to stats[10].toInt(),
                            "deviceName" to (deviceName ?: "N/A")
                        ))
                    } else {
                        result.success(null)
                    }
                } catch (e: Exception) {
                    result.success(null)
                }
            }

            else -> result.notImplemented()
        }
    }

    private fun ensureAndCheckNative(): Boolean {
        ensureNativeLib()
        return nativeLibLoaded
    }

    private fun destroyTexture() {
        surface = null
        surfaceProducer?.release()
        surfaceProducer = null
        currentTextureId = -1
        reusableFloatBuffer = null
    }

    // ─── JNI native methods ──────────────────────────────────────
    private external fun nativeInit(surface: Surface, width: Int, height: Int): Boolean
    private external fun nativeUpdateAndRender(points: FloatArray, color: Int, strokeWidth: Float, totalPoints: Int, brushType: Int, pencilBaseOpacity: Float, pencilMaxOpacity: Float, pencilMinPressure: Float, pencilMaxPressure: Float, fountainThinning: Float, fountainNibAngleDeg: Float, fountainNibStrength: Float, fountainPressureRate: Float, fountainTaperEntry: Int)
    private external fun nativeSetTransform(matrix: FloatArray)
    private external fun nativeClear()
    private external fun nativeResize(width: Int, height: Int): Boolean
    private external fun nativeDestroy()
    private external fun nativeIsInitialized(): Boolean
    private external fun nativeGetStats(): FloatArray?
    private external fun nativeGetDeviceName(): String?
}
