package com.nebula.engine

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * 🧮 LatexRecognizerPlugin — Android native module for LaTeX handwriting recognition.
 *
 * Integrates with Flutter via MethodChannel. This is currently a stub
 * implementation that reports ML recognition as unavailable until a
 * TensorFlow Lite model is bundled with the application.
 *
 * Channel: `nebula_engine/latex_recognition`
 *
 * Methods:
 * - `initialize` → reports availability (currently always false)
 * - `recognize` → returns NOT_AVAILABLE error
 * - `dispose` → no-op cleanup
 */
class LatexRecognizerPlugin : FlutterPlugin, MethodCallHandler {

    private lateinit var channel: MethodChannel

    companion object {
        private const val CHANNEL_NAME = "nebula_engine/latex_recognition"
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "initialize" -> {
                // Stub: ML model is not yet bundled
                android.util.Log.i("LatexRecognizer", "Stub plugin — ML model not available")
                result.success(mapOf("available" to false))
            }
            "recognize" -> {
                result.error(
                    "NOT_AVAILABLE",
                    "ML model not loaded — stub implementation",
                    null
                )
            }
            "dispose" -> {
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }
}
