package com.flueraengine.fluera_engine

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding

/**
 * 🚀 NebulEnginePlugin - Main entry point for Fluera Engine's native capabilities
 *
 * Registers all native platform channel handlers:
 * - PredictedTouchPlugin: Low-latency predicted/coalesced touches
 * - StylusInputPlugin: Advanced stylus metadata (hover, tilt, palm rejection)
 * - DisplayRefreshRateManager: Force 120Hz on supported devices
 * - VibrationPlugin: Advanced haptic feedback
 * - PrintPlugin: Native PDF printing (requires Activity context)
 */
class FlueraEnginePlugin : FlutterPlugin, ActivityAware {

    private var predictedTouchPlugin: PredictedTouchPlugin? = null
    private var stylusInputPlugin: StylusInputPlugin? = null
    private var vibrationPlugin: VibrationPlugin? = null
    private var performanceMonitorPlugin: PerformanceMonitorPlugin? = null
    private var audioRecorderPlugin: AudioRecorderPlugin? = null
    private var audioPlayerPlugin: AudioPlayerPlugin? = null
    private var pdfRendererPlugin: PdfRendererPlugin? = null
    private var latexRecognizerPlugin: LatexRecognizerPlugin? = null
    private var sharePlugin: SharePlugin? = null
    private var printPlugin: PrintPlugin? = null
    private var vulkanStrokePlugin: VulkanStrokeOverlayPlugin? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        // Register predicted touch plugin
        predictedTouchPlugin = PredictedTouchPlugin()
        predictedTouchPlugin?.onAttachedToEngine(binding)

        // Register stylus input plugin (hover, tilt, palm rejection)
        stylusInputPlugin = StylusInputPlugin()
        stylusInputPlugin?.onAttachedToEngine(binding)

        // Register vibration plugin
        vibrationPlugin = VibrationPlugin()
        vibrationPlugin?.onAttachedToEngine(binding)

        // Register performance monitor plugin
        performanceMonitorPlugin = PerformanceMonitorPlugin()
        performanceMonitorPlugin?.onAttachedToEngine(binding)

        // Register audio recorder plugin
        audioRecorderPlugin = AudioRecorderPlugin()
        audioRecorderPlugin?.onAttachedToEngine(binding)

        // Register audio player plugin
        audioPlayerPlugin = AudioPlayerPlugin()
        audioPlayerPlugin?.onAttachedToEngine(binding)

        // Register PDF renderer plugin
        pdfRendererPlugin = PdfRendererPlugin()
        pdfRendererPlugin?.onAttachedToEngine(binding)

        // Register LaTeX recognizer plugin (PyTorch Mobile)
        latexRecognizerPlugin = LatexRecognizerPlugin()
        latexRecognizerPlugin?.onAttachedToEngine(binding)

        // Register share plugin
        sharePlugin = SharePlugin()
        sharePlugin?.onAttachedToEngine(binding)

        // Register print plugin
        printPlugin = PrintPlugin()
        printPlugin?.onAttachedToEngine(binding)

        // Register Vulkan stroke overlay plugin (GPU live stroke renderer)
        vulkanStrokePlugin = VulkanStrokeOverlayPlugin()
        vulkanStrokePlugin?.onAttachedToEngine(binding)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        predictedTouchPlugin?.onDetachedFromEngine(binding)
        predictedTouchPlugin = null

        stylusInputPlugin?.onDetachedFromEngine(binding)
        stylusInputPlugin = null

        vibrationPlugin?.onDetachedFromEngine(binding)
        vibrationPlugin = null

        performanceMonitorPlugin?.onDetachedFromEngine(binding)
        performanceMonitorPlugin = null

        audioRecorderPlugin?.onDetachedFromEngine(binding)
        audioRecorderPlugin = null

        audioPlayerPlugin?.onDetachedFromEngine(binding)
        audioPlayerPlugin = null

        pdfRendererPlugin?.onDetachedFromEngine(binding)
        pdfRendererPlugin = null

        latexRecognizerPlugin?.onDetachedFromEngine(binding)
        latexRecognizerPlugin = null

        sharePlugin?.onDetachedFromEngine(binding)
        sharePlugin = null

        printPlugin?.onDetachedFromEngine(binding)
        printPlugin = null

        vulkanStrokePlugin?.onDetachedFromEngine(binding)
        vulkanStrokePlugin = null
    }

    // ─── ActivityAware — forward to plugins needing Activity ──────────
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        printPlugin?.onAttachedToActivity(binding)
        audioRecorderPlugin?.onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        printPlugin?.onDetachedFromActivityForConfigChanges()
        audioRecorderPlugin?.onDetachedFromActivityForConfigChanges()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        printPlugin?.onReattachedToActivityForConfigChanges(binding)
        audioRecorderPlugin?.onReattachedToActivityForConfigChanges(binding)
    }

    override fun onDetachedFromActivity() {
        printPlugin?.onDetachedFromActivity()
        audioRecorderPlugin?.onDetachedFromActivity()
    }
}
