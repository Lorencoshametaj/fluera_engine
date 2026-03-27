import FlutterMacOS

/// 🚀 FlueraEnginePlugin — Main entry point for Fluera Engine's native macOS capabilities.
///
/// Registers the Metal stroke overlay plugin for low-latency GPU rendering.
public class FlueraEnginePlugin: NSObject, FlutterPlugin {
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        MetalStrokeOverlayPlugin.register(with: registrar)
    }
}
