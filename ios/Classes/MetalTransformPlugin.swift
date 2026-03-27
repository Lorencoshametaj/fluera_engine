// MetalTransformPlugin.swift — Flutter plugin for GPU-accelerated Liquify, Smudge, and Warp
// Handles the 'fluera_engine/transform' MethodChannel.

import Flutter
import Metal

/// 🎨 MetalTransformPlugin — GPU compute pipeline for pixel manipulation tools.
///
/// Manages Metal compute kernels for Liquify (displacement field), Smudge (color blending),
/// and Warp (mesh deformation). Operates on textures shared with Flutter via TextureRegistry.
class MetalTransformPlugin: NSObject, FlutterPlugin {

    // ─── Metal Core ─────────────────────────────────────────────
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue

    // ─── Compute Pipelines ──────────────────────────────────────
    private var liquifyPipeline: MTLComputePipelineState?
    private var smudgePipeline: MTLComputePipelineState?
    private var warpPipeline: MTLComputePipelineState?

    // ─── Textures ───────────────────────────────────────────────
    private var sourceTexture: MTLTexture?
    private var outputTexture: MTLTexture?
    private var outputPixelBuffer: CVPixelBuffer?
    private var textureCache: CVMetalTextureCache?
    private var cvOutputTexture: CVMetalTexture?
    private var textureWidth: Int = 0
    private var textureHeight: Int = 0

    // ─── Flutter ────────────────────────────────────────────────
    private var textureRegistry: FlutterTextureRegistry?
    private var flutterTextureId: Int64?

    // ─── State ──────────────────────────────────────────────────
    private var isInitialized = false

    // ═══════════════════════════════════════════════════════════════
    // PLUGIN REGISTRATION
    // ═══════════════════════════════════════════════════════════════

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "fluera_engine/transform",
            binaryMessenger: registrar.messenger()
        )
        // Only register if Metal is available
        guard let plugin = MetalTransformPlugin() else {
            NSLog("[FlueraMtlTransform] Metal not available, skipping registration")
            return
        }
        plugin.textureRegistry = registrar.textures()
        registrar.addMethodCallDelegate(plugin, channel: channel)
    }

    init?() {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        self.device = device
        guard let queue = device.makeCommandQueue() else { return nil }
        self.commandQueue = queue

        super.init()

        // Build compute pipelines
        buildComputePipelines()

        // Create texture cache
        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
        self.textureCache = cache

        NSLog("[FlueraMtlTransform] Initialized with device: %@", device.name)
    }

    private func buildComputePipelines() {
        guard let library = try? device.makeDefaultLibrary(
            bundle: Bundle(for: MetalTransformPlugin.self)
        ) else {
            NSLog("[FlueraMtlTransform] Failed to load shader library")
            return
        }

        // Liquify
        if let fn = library.makeFunction(name: "liquify_kernel") {
            liquifyPipeline = try? device.makeComputePipelineState(function: fn)
        }
        // Smudge
        if let fn = library.makeFunction(name: "smudge_kernel") {
            smudgePipeline = try? device.makeComputePipelineState(function: fn)
        }
        // Warp
        if let fn = library.makeFunction(name: "warp_kernel") {
            warpPipeline = try? device.makeComputePipelineState(function: fn)
        }

        NSLog("[FlueraMtlTransform] Pipelines: liquify=%@, smudge=%@, warp=%@",
              liquifyPipeline != nil ? "OK" : "FAIL",
              smudgePipeline != nil ? "OK" : "FAIL",
              warpPipeline != nil ? "OK" : "FAIL")
    }

    // ═══════════════════════════════════════════════════════════════
    // FLUTTER METHOD CHANNEL
    // ═══════════════════════════════════════════════════════════════

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isAvailable":
            result(liquifyPipeline != nil)

        case "init":
            guard let args = call.arguments as? [String: Any],
                  let width = args["width"] as? Int,
                  let height = args["height"] as? Int else {
                result(FlutterError(code: "ARGS", message: "Missing width/height", details: nil))
                return
            }
            let textureId = initializeTextures(width: width, height: height)
            result(textureId)

        case "applyLiquify":
            guard let args = call.arguments as? [String: Any],
                  let fieldData = args["fieldData"] as? FlutterStandardTypedData,
                  let fieldWidth = args["fieldWidth"] as? Int,
                  let fieldHeight = args["fieldHeight"] as? Int else {
                result(FlutterError(code: "ARGS", message: "Missing field data", details: nil))
                return
            }
            applyLiquify(
                fieldData: fieldData.data,
                fieldWidth: fieldWidth,
                fieldHeight: fieldHeight
            )
            result(true)

        case "applySmudge":
            guard let args = call.arguments as? [String: Any],
                  let samplesData = args["samples"] as? FlutterStandardTypedData,
                  let sampleCount = args["sampleCount"] as? Int else {
                result(FlutterError(code: "ARGS", message: "Missing smudge data", details: nil))
                return
            }
            applySmudge(samplesData: samplesData.data, sampleCount: sampleCount)
            result(true)

        case "applyWarp":
            guard let args = call.arguments as? [String: Any],
                  let meshData = args["meshData"] as? FlutterStandardTypedData,
                  let meshCols = args["meshCols"] as? Int,
                  let meshRows = args["meshRows"] as? Int,
                  let boundsLeft = args["boundsLeft"] as? Double,
                  let boundsTop = args["boundsTop"] as? Double,
                  let boundsWidth = args["boundsWidth"] as? Double,
                  let boundsHeight = args["boundsHeight"] as? Double else {
                result(FlutterError(code: "ARGS", message: "Missing warp data", details: nil))
                return
            }
            applyWarp(
                meshData: meshData.data,
                meshCols: meshCols,
                meshRows: meshRows,
                boundsLeft: Float(boundsLeft),
                boundsTop: Float(boundsTop),
                boundsWidth: Float(boundsWidth),
                boundsHeight: Float(boundsHeight)
            )
            result(true)

        case "setSourceImage":
            guard let args = call.arguments as? [String: Any],
                  let imageData = args["imageData"] as? FlutterStandardTypedData,
                  let width = args["width"] as? Int,
                  let height = args["height"] as? Int else {
                result(FlutterError(code: "ARGS", message: "Missing image data", details: nil))
                return
            }
            setSourceImage(data: imageData.data, width: width, height: height)
            result(true)

        case "destroy":
            destroyResources()
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // TEXTURE MANAGEMENT
    // ═══════════════════════════════════════════════════════════════

    private func initializeTextures(width: Int, height: Int) -> Int64? {
        textureWidth = width
        textureHeight = height

        // Create source texture
        let srcDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width, height: height,
            mipmapped: false
        )
        srcDesc.usage = [.shaderRead]
        srcDesc.storageMode = .shared
        sourceTexture = device.makeTexture(descriptor: srcDesc)

        // Create output texture backed by CVPixelBuffer for Flutter sharing
        let attrs: [String: Any] = [
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
        ]

        var pb: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA,
                           attrs as CFDictionary, &pb)
        guard let pixelBuffer = pb, let cache = textureCache else { return nil }

        outputPixelBuffer = pixelBuffer

        var cvTex: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(
            nil, cache, pixelBuffer, nil,
            .bgra8Unorm, width, height, 0, &cvTex)
        guard let cvMetalTex = cvTex else { return nil }
        cvOutputTexture = cvMetalTex
        outputTexture = CVMetalTextureGetTexture(cvMetalTex)

        // Register with Flutter
        guard let registry = textureRegistry else { return nil }
        let textureEntry = PixelBufferTextureEntry(pixelBuffer: pixelBuffer)
        flutterTextureId = registry.register(textureEntry)

        isInitialized = true
        return flutterTextureId
    }

    private func setSourceImage(data: Data, width: Int, height: Int) {
        guard let tex = sourceTexture, width == textureWidth, height == textureHeight else { return }

        let region = MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                               size: MTLSize(width: width, height: height, depth: 1))
        data.withUnsafeBytes { ptr in
            tex.replace(region: region, mipmapLevel: 0,
                       withBytes: ptr.baseAddress!,
                       bytesPerRow: width * 4)
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // COMPUTE DISPATCH
    // ═══════════════════════════════════════════════════════════════

    private func applyLiquify(fieldData: Data, fieldWidth: Int, fieldHeight: Int) {
        guard let pipeline = liquifyPipeline,
              let src = sourceTexture,
              let dst = outputTexture,
              let cmdBuffer = commandQueue.makeCommandBuffer(),
              let encoder = cmdBuffer.makeComputeCommandEncoder() else { return }

        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(src, index: 0)
        encoder.setTexture(dst, index: 1)

        // Upload displacement field
        let fieldBuffer = device.makeBuffer(bytes: (fieldData as NSData).bytes,
                                            length: fieldData.count,
                                            options: .storageModeShared)
        encoder.setBuffer(fieldBuffer, offset: 0, index: 0)

        // Params
        var params = _LiquifyParams(
            width: UInt32(textureWidth),
            height: UInt32(textureHeight),
            fieldWidth: UInt32(fieldWidth),
            fieldHeight: UInt32(fieldHeight)
        )
        encoder.setBytes(&params, length: MemoryLayout<_LiquifyParams>.size, index: 1)

        // Dispatch
        let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadGroups = MTLSize(
            width: (textureWidth + 15) / 16,
            height: (textureHeight + 15) / 16,
            depth: 1
        )
        encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        encoder.endEncoding()

        cmdBuffer.commit()
        cmdBuffer.waitUntilCompleted()

        // Notify Flutter
        if let tid = flutterTextureId {
            textureRegistry?.textureFrameAvailable(tid)
        }
    }

    private func applySmudge(samplesData: Data, sampleCount: Int) {
        guard let pipeline = smudgePipeline,
              let dst = outputTexture,
              let cmdBuffer = commandQueue.makeCommandBuffer(),
              let encoder = cmdBuffer.makeComputeCommandEncoder() else { return }

        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(dst, index: 0)

        let samplesBuffer = device.makeBuffer(bytes: (samplesData as NSData).bytes,
                                              length: samplesData.count,
                                              options: .storageModeShared)
        encoder.setBuffer(samplesBuffer, offset: 0, index: 0)

        var params = _SmudgeParams(
            width: UInt32(textureWidth),
            height: UInt32(textureHeight),
            sampleCount: UInt32(sampleCount)
        )
        encoder.setBytes(&params, length: MemoryLayout<_SmudgeParams>.size, index: 1)

        let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadGroups = MTLSize(
            width: (textureWidth + 15) / 16,
            height: (textureHeight + 15) / 16,
            depth: 1
        )
        encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        encoder.endEncoding()

        cmdBuffer.commit()
        cmdBuffer.waitUntilCompleted()

        if let tid = flutterTextureId {
            textureRegistry?.textureFrameAvailable(tid)
        }
    }

    private func applyWarp(meshData: Data, meshCols: Int, meshRows: Int,
                           boundsLeft: Float, boundsTop: Float,
                           boundsWidth: Float, boundsHeight: Float) {
        guard let pipeline = warpPipeline,
              let src = sourceTexture,
              let dst = outputTexture,
              let cmdBuffer = commandQueue.makeCommandBuffer(),
              let encoder = cmdBuffer.makeComputeCommandEncoder() else { return }

        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(src, index: 0)
        encoder.setTexture(dst, index: 1)

        let meshBuffer = device.makeBuffer(bytes: (meshData as NSData).bytes,
                                           length: meshData.count,
                                           options: .storageModeShared)
        encoder.setBuffer(meshBuffer, offset: 0, index: 0)

        var params = _WarpParams(
            width: UInt32(textureWidth),
            height: UInt32(textureHeight),
            meshCols: UInt32(meshCols),
            meshRows: UInt32(meshRows),
            boundsLeft: boundsLeft,
            boundsTop: boundsTop,
            boundsWidth: boundsWidth,
            boundsHeight: boundsHeight
        )
        encoder.setBytes(&params, length: MemoryLayout<_WarpParams>.size, index: 1)

        let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadGroups = MTLSize(
            width: (textureWidth + 15) / 16,
            height: (textureHeight + 15) / 16,
            depth: 1
        )
        encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        encoder.endEncoding()

        cmdBuffer.commit()
        cmdBuffer.waitUntilCompleted()

        if let tid = flutterTextureId {
            textureRegistry?.textureFrameAvailable(tid)
        }
    }

    private func destroyResources() {
        isInitialized = false
        sourceTexture = nil
        outputTexture = nil
        cvOutputTexture = nil
        outputPixelBuffer = nil

        if let tid = flutterTextureId {
            textureRegistry?.unregisterTexture(tid)
            flutterTextureId = nil
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// HELPER STRUCTS (must match Metal shader structs)
// ═══════════════════════════════════════════════════════════════

private struct _LiquifyParams {
    var width: UInt32
    var height: UInt32
    var fieldWidth: UInt32
    var fieldHeight: UInt32
}

private struct _SmudgeParams {
    var width: UInt32
    var height: UInt32
    var sampleCount: UInt32
}

private struct _WarpParams {
    var width: UInt32
    var height: UInt32
    var meshCols: UInt32
    var meshRows: UInt32
    var boundsLeft: Float
    var boundsTop: Float
    var boundsWidth: Float
    var boundsHeight: Float
}

// ═══════════════════════════════════════════════════════════════
// PIXEL BUFFER TEXTURE ENTRY
// ═══════════════════════════════════════════════════════════════

/// FlutterTexture wrapper for CVPixelBuffer.
class PixelBufferTextureEntry: NSObject, FlutterTexture {
    private let pixelBuffer: CVPixelBuffer

    init(pixelBuffer: CVPixelBuffer) {
        self.pixelBuffer = pixelBuffer
    }

    func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        return Unmanaged.passRetained(pixelBuffer)
    }
}
