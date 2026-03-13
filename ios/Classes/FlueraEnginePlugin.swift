import Flutter
import UIKit

/// 🚀 FlueraEnginePlugin - Main entry point for Fluera Engine's native capabilities on iOS
///
/// Registers all native platform channel handlers:
/// - PredictedTouchPlugin: Low-latency predicted/coalesced touches + Apple Pencil hover
/// - DisplayLinkPlugin: CADisplayLink 120Hz ProMotion sync
/// - VibrationPlugin: Core Haptics feedback
public class FlueraEnginePlugin: NSObject, FlutterPlugin {
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        // Register all sub-plugins
        PredictedTouchPlugin.register(with: registrar)
        DisplayLinkPlugin.register(with: registrar)
        VibrationPlugin.register(with: registrar)
        PerformanceMonitorPlugin.register(with: registrar)
        AudioRecorderPlugin.register(with: registrar)
        AudioPlayerPlugin.register(with: registrar)
        PdfRendererPlugin.register(with: registrar)
        PrintPlugin.register(with: registrar)
        MetalStrokeOverlayPlugin.register(with: registrar)
    }
}
