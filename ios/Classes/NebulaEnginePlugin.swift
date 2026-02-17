import Flutter
import UIKit

/// 🚀 NebulaEnginePlugin - Main entry point for Nebula Engine's native capabilities on iOS
///
/// Registers all native platform channel handlers:
/// - PredictedTouchPlugin: Low-latency predicted/coalesced touches + Apple Pencil hover
/// - DisplayLinkPlugin: CADisplayLink 120Hz ProMotion sync
/// - VibrationPlugin: Core Haptics feedback
public class NebulaEnginePlugin: NSObject, FlutterPlugin {
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        // Register all sub-plugins
        PredictedTouchPlugin.register(with: registrar)
        DisplayLinkPlugin.register(with: registrar)
        VibrationPlugin.register(with: registrar)
        PerformanceMonitorPlugin.register(with: registrar)
    }
}
