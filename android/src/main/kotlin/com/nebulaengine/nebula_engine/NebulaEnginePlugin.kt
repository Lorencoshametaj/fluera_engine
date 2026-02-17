package com.nebulaengine.nebula_engine

import io.flutter.embedding.engine.plugins.FlutterPlugin

/**
 * 🚀 NebulEnginePlugin - Main entry point for Nebula Engine's native capabilities
 *
 * Registers all native platform channel handlers:
 * - PredictedTouchPlugin: Low-latency predicted/coalesced touches
 * - DisplayRefreshRateManager: Force 120Hz on supported devices
 * - VibrationPlugin: Advanced haptic feedback
 */
class NebulaEnginePlugin : FlutterPlugin {

    private var predictedTouchPlugin: PredictedTouchPlugin? = null
    private var vibrationPlugin: VibrationPlugin? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        // Register predicted touch plugin
        predictedTouchPlugin = PredictedTouchPlugin()
        predictedTouchPlugin?.onAttachedToEngine(binding)

        // Register vibration plugin
        vibrationPlugin = VibrationPlugin()
        vibrationPlugin?.onAttachedToEngine(binding)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        predictedTouchPlugin?.onDetachedFromEngine(binding)
        predictedTouchPlugin = null

        vibrationPlugin?.onDetachedFromEngine(binding)
        vibrationPlugin = null
    }
}
