package com.nebulaengine.nebula_engine

import io.flutter.embedding.engine.plugins.FlutterPlugin

/**
 * 🚀 NebulEnginePlugin - Main entry point for Nebula Engine's native capabilities
 *
 * Registers all native platform channel handlers:
 * - PredictedTouchPlugin: Low-latency predicted/coalesced touches
 * - StylusInputPlugin: Advanced stylus metadata (hover, tilt, palm rejection)
 * - DisplayRefreshRateManager: Force 120Hz on supported devices
 * - VibrationPlugin: Advanced haptic feedback
 */
class NebulaEnginePlugin : FlutterPlugin {

    private var predictedTouchPlugin: PredictedTouchPlugin? = null
    private var stylusInputPlugin: StylusInputPlugin? = null
    private var vibrationPlugin: VibrationPlugin? = null
    private var performanceMonitorPlugin: PerformanceMonitorPlugin? = null
    private var audioRecorderPlugin: AudioRecorderPlugin? = null
    private var pdfRendererPlugin: PdfRendererPlugin? = null

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

        // Register PDF renderer plugin
        pdfRendererPlugin = PdfRendererPlugin()
        pdfRendererPlugin?.onAttachedToEngine(binding)
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

        pdfRendererPlugin?.onDetachedFromEngine(binding)
        pdfRendererPlugin = null
    }
}

