package com.flueraengine.fluera_engine

import android.os.Build
import android.util.Log
import android.view.Surface
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry

/**
 * 🎨 VulkanImageProcessorPlugin — GPU Image Filter Pipeline (Android)
 *
 * Real-time GPU color grading, blur, sharpen, vignette via Vulkan render pipelines.
 * Uses SurfaceProducer → VkSwapchain for Flutter texture integration.
 *
 * Channel: com.flueraengine/native_image_processor
 */
class VulkanImageProcessorPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    private var channel: MethodChannel? = null
    private var textureRegistry: TextureRegistry? = null
    private var surfaceProducer: TextureRegistry.SurfaceProducer? = null

    // JNI native methods
    private external fun nativeIsAvailable(): Int
    private external fun nativeInit(surface: Surface, width: Int, height: Int): Int
    private external fun nativeUploadImage(rgba: ByteArray, width: Int, height: Int): Int
    private external fun nativeApplyFilters(
        brightness: Float, contrast: Float, saturation: Float,
        hueShift: Float, temperature: Float, opacity: Float, vignette: Float
    )
    private external fun nativeApplyBlur(radius: Float)
    private external fun nativeApplySharpen(amount: Float)
    private external fun nativeGenerateMipmaps()
    private external fun nativeCleanup()

    companion object {
        private const val TAG = "VkImageProcessor"
        private var libraryLoaded = false

        init {
            try {
                System.loadLibrary("fluera_vk_image")
                libraryLoaded = true
            } catch (e: UnsatisfiedLinkError) {
                Log.w(TAG, "fluera_vk_image library not available: ${e.message}")
            }
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "com.flueraengine/native_image_processor")
        channel?.setMethodCallHandler(this)
        textureRegistry = binding.textureRegistry
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        cleanup()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {

            "initialize" -> {
                if (!libraryLoaded || Build.VERSION.SDK_INT < 29) {
                    result.success(false)
                    return
                }
                // Pipeline will be initialized on first uploadImage
                result.success(true)
            }

            "uploadImage" -> {
                val imageId = call.argument<String>("imageId")
                val imageBytes = call.argument<ByteArray>("imageBytes")
                val width = call.argument<Int>("width")
                val height = call.argument<Int>("height")

                if (imageId == null || imageBytes == null || width == null || height == null) {
                    result.error("INVALID_ARGS", "Missing required args", null)
                    return
                }

                // Create SurfaceProducer for Flutter texture
                val registry = textureRegistry ?: run {
                    result.success(-1)
                    return
                }

                val producer = registry.createSurfaceProducer()
                producer.setSize(width, height)
                surfaceProducer = producer

                val surface = producer.surface
                val initResult = nativeInit(surface, width, height)
                if (initResult == 0) {
                    result.success(-1)
                    return
                }

                // Upload image data
                val uploadResult = nativeUploadImage(imageBytes, width, height)
                if (uploadResult == 0) {
                    result.success(-1)
                    return
                }

                Log.i(TAG, "Image uploaded: ${width}x${height}, textureId=${producer.id()}")
                result.success(producer.id())
            }

            "applyFilters" -> {
                val brightness = (call.argument<Double>("brightness") ?: 0.0).toFloat()
                val contrast = (call.argument<Double>("contrast") ?: 0.0).toFloat()
                val saturation = (call.argument<Double>("saturation") ?: 0.0).toFloat()
                val hueShift = (call.argument<Double>("hueShift") ?: 0.0).toFloat()
                val temperature = (call.argument<Double>("temperature") ?: 0.0).toFloat()
                val opacity = (call.argument<Double>("opacity") ?: 1.0).toFloat()
                val vignette = (call.argument<Double>("vignette") ?: 0.0).toFloat()

                nativeApplyFilters(brightness, contrast, saturation, hueShift, temperature, opacity, vignette)
                result.success(true)
            }

            "applyBlur" -> {
                val radius = (call.argument<Double>("radius") ?: 5.0).toFloat()
                nativeApplyBlur(radius)
                result.success(true)
            }

            "applySharpen" -> {
                val amount = (call.argument<Double>("amount") ?: 0.5).toFloat()
                nativeApplySharpen(amount)
                result.success(true)
            }

            "generateMipmaps" -> {
                nativeGenerateMipmaps()
                result.success(true)
            }

            "releaseImage" -> {
                // For now, cleanup releases everything
                cleanup()
                result.success(null)
            }

            "dispose" -> {
                cleanup()
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    private fun cleanup() {
        if (libraryLoaded) {
            nativeCleanup()
        }
        surfaceProducer?.release()
        surfaceProducer = null
    }
}
