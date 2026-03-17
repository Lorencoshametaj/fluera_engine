// MetalStrokeOverlayPlugin.swift — Flutter plugin bridge for Metal live stroke rendering
// Equivalent to VulkanStrokeOverlayPlugin.kt on Android
//
// Uses the same MethodChannel ('fluera_engine/vulkan_stroke') so the Dart
// VulkanStrokeOverlayService works unchanged on both platforms.

import Flutter
import UIKit
import CoreVideo

/// 🎨 MetalStrokeOverlayPlugin — Flutter TextureRegistry bridge for Metal stroke renderer.
///
/// Uses CVPixelBuffer + FlutterTextureRegistry for zero-copy GPU→Flutter texture sharing.
/// The Metal renderer draws into a CVPixelBuffer-backed MTLTexture, and Flutter composites
/// it via the Texture widget.
public class MetalStrokeOverlayPlugin: NSObject, FlutterPlugin, FlutterTexture {
    
    private var textureRegistry: FlutterTextureRegistry?
    private var textureId: Int64 = -1
    private var renderer: MetalStrokeRenderer?
    private var channel: FlutterMethodChannel?
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "fluera_engine/vulkan_stroke",
            binaryMessenger: registrar.messenger()
        )
        let instance = MetalStrokeOverlayPlugin()
        instance.channel = channel
        instance.textureRegistry = registrar.textures()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    // ─── FlutterTexture protocol ────────────────────────────────
    
    public func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        guard let pb = renderer?.outputPixelBuffer else { return nil }
        return Unmanaged.passRetained(pb)
    }
    
    // ─── Method call handler ────────────────────────────────────
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
            
        case "isAvailable":
            // Metal is available on all iOS devices since iPhone 5s / iOS 8
            result(true)
            
        case "init":
            guard let args = call.arguments as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing arguments", details: nil))
                return
            }
            let width = args["width"] as? Int ?? 1080
            let height = args["height"] as? Int ?? 1920
            
            // Clean up previous
            destroyTexture()
            
            // Create Metal renderer
            guard let newRenderer = MetalStrokeRenderer() else {
                result(FlutterError(code: "METAL_INIT_FAILED", message: "Failed to create Metal device", details: nil))
                return
            }
            
            guard newRenderer.initialize(width: width, height: height) else {
                result(FlutterError(code: "METAL_INIT_FAILED", message: "Failed to initialize renderer", details: nil))
                return
            }
            
            renderer = newRenderer
            
            // 🚀 FFI: Set global refs for direct Dart→Swift hot path
            flueraMetalRenderer = newRenderer
            
            // Register texture with Flutter
            if let registry = textureRegistry {
                textureId = registry.register(self)
                flueraTextureRegistry = registry  // 🚀 FFI
                flueraTextureId = textureId        // 🚀 FFI
                NSLog("[FlueraMtl] Renderer initialized, textureId=%lld", textureId)
                result(textureId)
            } else {
                result(FlutterError(code: "NO_REGISTRY", message: "TextureRegistry not available", details: nil))
            }
            
        case "updateAndRender":
            guard let args = call.arguments as? [String: Any],
                  let pointsList = args["points"] as? [Double] else {
                result(nil)
                return
            }
            
            let color = (args["color"] as? Int) ?? Int(0xFF000000)
            let width = (args["width"] as? Double) ?? 2.0
            let totalPoints = (args["totalPoints"] as? Int) ?? 0
            let brushType = (args["brushType"] as? Int) ?? 0
            let pencilBaseOpacity = Float((args["pencilBaseOpacity"] as? Double) ?? 0.4)
            let pencilMaxOpacity = Float((args["pencilMaxOpacity"] as? Double) ?? 0.8)
            let pencilMinPressure = Float((args["pencilMinPressure"] as? Double) ?? 0.5)
            let pencilMaxPressure = Float((args["pencilMaxPressure"] as? Double) ?? 1.2)
            let fountainThinning = Float((args["fountainThinning"] as? Double) ?? 0.5)
            let fountainNibAngleDeg = Float((args["fountainNibAngleDeg"] as? Double) ?? 30.0)
            let fountainNibStrength = Float((args["fountainNibStrength"] as? Double) ?? 0.35)
            let fountainPressureRate = Float((args["fountainPressureRate"] as? Double) ?? 0.275)
            let fountainTaperEntry = (args["fountainTaperEntry"] as? Int) ?? 6
            
            // Convert Double array to Float array
            if pointsList.count >= 10 {
                let floatPoints = pointsList.map { Float($0) }
                renderer?.updateAndRender(
                    points: floatPoints,
                    color: UInt32(bitPattern: Int32(truncatingIfNeeded: color)),
                    strokeWidth: Float(width),
                    totalPoints: totalPoints,
                    brushType: brushType,
                    pencilBaseOpacity: pencilBaseOpacity,
                    pencilMaxOpacity: pencilMaxOpacity,
                    pencilMinPressure: pencilMinPressure,
                    pencilMaxPressure: pencilMaxPressure,
                    fountainThinning: fountainThinning,
                    fountainNibAngleDeg: fountainNibAngleDeg,
                    fountainNibStrength: fountainNibStrength,
                    fountainPressureRate: fountainPressureRate,
                    fountainTaperEntry: fountainTaperEntry
                )
                
                // Notify Flutter that texture has new content
                textureRegistry?.textureFrameAvailable(textureId)
            }
            result(nil)
            
        case "setTransform":
            guard let args = call.arguments as? [String: Any],
                  let matrixList = args["matrix"] as? [Double],
                  matrixList.count == 16 else {
                result(nil)
                return
            }
            renderer?.setTransform(matrixList.map { Float($0) })
            // 🚀 Adaptive LOD: extract zoom level from args
            if let zoom = args["zoomLevel"] as? Double {
                renderer?.setZoomLevel(Float(zoom))
            }
            result(nil)
            
        case "trimMemory":
            let level = (call.arguments as? [String: Any])?["level"] as? Int ?? 1
            renderer?.trimMemory(level: level)
            result(nil)
            
        case "clear":
            renderer?.clearFrame()
            textureRegistry?.textureFrameAvailable(textureId)
            result(nil)
            
        case "resize":
            guard let args = call.arguments as? [String: Any] else {
                result(false)
                return
            }
            let w = args["width"] as? Int ?? 1080
            let h = args["height"] as? Int ?? 1920
            let success = renderer?.resize(width: w, height: h) ?? false
            if success {
                // Re-register texture since CVPixelBuffer changed
                if let registry = textureRegistry {
                    registry.unregisterTexture(textureId)
                    textureId = registry.register(self)
                }
            }
            result(success)
            
        case "destroy":
            renderer?.destroy()
            destroyTexture()
            result(nil)
            
        case "getStats":
            if let stats = renderer?.getStats() {
                result([
                    "p50us": Double(stats.frameTimeP50Us),
                    "p90us": Double(stats.frameTimeP90Us),
                    "p99us": Double(stats.frameTimeP99Us),
                    "vertexCount": Int(stats.vertexCount),
                    "drawCalls": Int(stats.drawCalls),
                    "swapchainImages": 1, // No swapchain in Metal path
                    "totalFrames": Int(stats.totalFrames),
                    "active": stats.active,
                    "apiMajor": 0, // Metal doesn't have API versioning like Vulkan
                    "apiMinor": 0,
                    "apiPatch": 0,
                    "deviceName": stats.deviceName
                ] as [String: Any])
            } else {
                result(nil)
            }
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func destroyTexture() {
        if textureId >= 0, let registry = textureRegistry {
            registry.unregisterTexture(textureId)
        }
        textureId = -1
        renderer = nil
    }
}

// ═══════════════════════════════════════════════════════════════════
// 🚀 FFI EXPORT — Direct Dart→Swift hot path (replaces MethodChannel)
//
// Buffer layout — mirrors fluera_stroke_ffi.h
// Called from Dart via dart:ffi (DynamicLibrary.process() on Apple)
// ═══════════════════════════════════════════════════════════════════

/// Module-level reference for FFI access (set during plugin init)
var flueraMetalRenderer: MetalStrokeRenderer?
var flueraTextureRegistry: FlutterTextureRegistry?
var flueraTextureId: Int64 = -1

@_cdecl("fluera_stroke_execute")
public func flueraStrokeExecute(_ buf: UnsafeMutablePointer<Float>) {
    guard let renderer = flueraMetalRenderer else { return }

    let cmd = buf[0]

    // CLEAR
    if cmd == 3.0 {
        renderer.clearFrame()
        if flueraTextureId >= 0 {
            flueraTextureRegistry?.textureFrameAvailable(flueraTextureId)
        }
        return
    }

    // SET TRANSFORM
    if cmd == 2.0 {
        let matrix = (0..<16).map { buf[20 + $0] }
        renderer.setTransform(matrix)
        return
    }

    // UPDATE AND RENDER
    if cmd == 1.0 {
        let pointCount = Int(buf[1])
        if pointCount < 2 { return }

        let colorR = buf[2]
        let colorG = buf[3]
        let colorB = buf[4]
        let colorA = buf[5]
        let colorArgb = UInt32(
            (UInt32(colorA * 255) << 24) |
            (UInt32(colorR * 255) << 16) |
            (UInt32(colorG * 255) << 8) |
            UInt32(colorB * 255)
        )

        // Extract points directly from buffer (zero-copy pointer)
        let pointsPtr = buf + 36
        let floatCount = pointCount * 5
        let floatPoints = Array(UnsafeBufferPointer(start: pointsPtr, count: floatCount))

        renderer.updateAndRender(
            points: floatPoints,
            color: colorArgb,
            strokeWidth: buf[6],
            totalPoints: Int(buf[7]),
            brushType: Int(buf[8]),
            pencilBaseOpacity: buf[9],
            pencilMaxOpacity: buf[10],
            pencilMinPressure: buf[11],
            pencilMaxPressure: buf[12],
            fountainThinning: buf[13],
            fountainNibAngleDeg: buf[14],
            fountainNibStrength: buf[15],
            fountainPressureRate: buf[16],
            fountainTaperEntry: Int(buf[17])
        )

        if flueraTextureId >= 0 {
            flueraTextureRegistry?.textureFrameAvailable(flueraTextureId)
        }
    }
}
