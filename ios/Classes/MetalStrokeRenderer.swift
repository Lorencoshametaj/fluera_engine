// MetalStrokeRenderer.swift — Pure Metal live stroke renderer for iOS
// Renders live strokes as triangles with round caps + MSAA 4x
// Equivalent to VkStrokeRenderer (C++ Vulkan) on Android

import Metal
import CoreVideo
import QuartzCore

/// Vertex layout: 2D position + RGBA color (24 bytes, matches StrokeShaders.metal)
struct StrokeVertex {
    var x: Float
    var y: Float
    var r: Float
    var g: Float
    var b: Float
    var a: Float
}

/// Uniform buffer for transform matrix
struct StrokeUniforms {
    var transform: simd_float4x4
}

/// Performance statistics snapshot
struct MetalStrokeStats {
    var frameTimeP50Us: Float = 0
    var frameTimeP90Us: Float = 0
    var frameTimeP99Us: Float = 0
    var vertexCount: UInt32 = 0
    var drawCalls: UInt32 = 0
    var totalFrames: UInt32 = 0
    var active: Bool = false
    var deviceName: String = ""
}

/// 🎨 MetalStrokeRenderer — GPU live stroke renderer for iOS
///
/// Renders strokes as tessellated triangles into an offscreen MTLTexture
/// backed by a CVPixelBuffer for zero-copy sharing with Flutter via TextureRegistry.
///
/// Pipeline:
/// 1. Dart sends touch points via MethodChannel
/// 2. Swift tessellates points → triangle vertices (with round caps + taper)
/// 3. Metal renders triangles with MSAA 4x
/// 4. Flutter composites via Texture widget
class MetalStrokeRenderer {
    
    // ─── Metal Core ─────────────────────────────────────────────
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    
    // ─── Render Target ──────────────────────────────────────────
    private var renderTexture: MTLTexture?       // MSAA resolve target
    private var msaaTexture: MTLTexture?          // MSAA 4x render target
    private var pixelBuffer: CVPixelBuffer?       // Shared with Flutter
    private var textureCache: CVMetalTextureCache?
    private var cvMetalTexture: CVMetalTexture?
    
    // ─── Vertex Buffer ──────────────────────────────────────────
    private static let maxVertices = 524288       // 512K vertices (~12MB)
    private var vertexBuffer: MTLBuffer?
    private var accumulatedVerts: [StrokeVertex] = []
    private var allRawPoints: [Float] = []          // Raw accumulated points (stride 5)
    private var totalAccumulatedPoints: Int = 0
    
    // ─── Uniforms ───────────────────────────────────────────────
    private var uniformBuffer: MTLBuffer?
    private var transform: simd_float4x4 = matrix_identity_float4x4
    
    // ─── State ──────────────────────────────────────────────────
    private(set) var width: Int = 0
    private(set) var height: Int = 0
    private(set) var isInitialized: Bool = false
    
    // ─── Stats ──────────────────────────────────────────────────
    private var frameTimes: [Float] = []
    private var totalFrames: UInt32 = 0
    private var statsActive: Bool = false
    private static let statsMaxSamples = 120
    
    // ─── MSAA ───────────────────────────────────────────────────
    private let msaaSampleCount = 4
    
    // ═══════════════════════════════════════════════════════════════
    // INIT
    // ═══════════════════════════════════════════════════════════════
    
    init?() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            NSLog("[FlueraMtl] No Metal device available")
            return nil
        }
        self.device = device
        
        guard let queue = device.makeCommandQueue() else {
            NSLog("[FlueraMtl] Failed to create command queue")
            return nil
        }
        self.commandQueue = queue
        
        // Build render pipeline
        guard let pso = MetalStrokeRenderer.buildPipeline(device: device, sampleCount: msaaSampleCount) else {
            NSLog("[FlueraMtl] Failed to build pipeline")
            return nil
        }
        self.pipelineState = pso
        
        // Create uniform buffer
        self.uniformBuffer = device.makeBuffer(length: MemoryLayout<StrokeUniforms>.size,
                                                options: .storageModeShared)
        
        // Create texture cache for CVPixelBuffer → MTLTexture
        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
        self.textureCache = cache
        
        NSLog("[FlueraMtl] Metal device: %@", device.name)
    }
    
    /// Initialize with size and create render targets
    func initialize(width: Int, height: Int) -> Bool {
        self.width = width
        self.height = height
        
        guard createRenderTargets() else {
            NSLog("[FlueraMtl] Failed to create render targets")
            return false
        }
        
        // Pre-allocate vertex buffer
        vertexBuffer = device.makeBuffer(
            length: MetalStrokeRenderer.maxVertices * MemoryLayout<StrokeVertex>.stride,
            options: .storageModeShared
        )
        
        // Set identity transform
        transform = matrix_identity_float4x4
        updateUniformBuffer()
        
        accumulatedVerts.reserveCapacity(8192)
        isInitialized = true
        
        NSLog("[FlueraMtl] Initialized: %dx%d, MSAA %dx", width, height, msaaSampleCount)
        return true
    }
    
    // ═══════════════════════════════════════════════════════════════
    // RENDER TARGETS (CVPixelBuffer → MTLTexture)
    // ═══════════════════════════════════════════════════════════════
    
    private func createRenderTargets() -> Bool {
        // Create CVPixelBuffer (shared with Flutter)
        let attrs: [String: Any] = [
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
        ]
        
        var pb: CVPixelBuffer?
        let status = CVPixelBufferCreate(nil, width, height,
                                          kCVPixelFormatType_32BGRA,
                                          attrs as CFDictionary, &pb)
        guard status == kCVReturnSuccess, let pixelBuffer = pb else {
            NSLog("[FlueraMtl] CVPixelBuffer creation failed: %d", status)
            return false
        }
        self.pixelBuffer = pixelBuffer
        
        // Create MTLTexture from CVPixelBuffer
        guard let cache = textureCache else { return false }
        var cvTex: CVMetalTexture?
        let texStatus = CVMetalTextureCacheCreateTextureFromImage(
            nil, cache, pixelBuffer, nil,
            .bgra8Unorm, width, height, 0, &cvTex
        )
        guard texStatus == kCVReturnSuccess, let cvMetalTexture = cvTex else {
            NSLog("[FlueraMtl] CVMetalTexture creation failed: %d", texStatus)
            return false
        }
        self.cvMetalTexture = cvMetalTexture
        self.renderTexture = CVMetalTextureGetTexture(cvMetalTexture)
        
        // Create MSAA texture
        let msaaDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width, height: height,
            mipmapped: false
        )
        msaaDesc.textureType = .type2DMultisample
        msaaDesc.sampleCount = msaaSampleCount
        msaaDesc.storageMode = .memoryless  // GPU-only, no readback needed
        msaaDesc.usage = .renderTarget
        self.msaaTexture = device.makeTexture(descriptor: msaaDesc)
        
        if msaaTexture == nil {
            NSLog("[FlueraMtl] MSAA texture creation failed")
            return false
        }
        
        NSLog("[FlueraMtl] MSAA %dx render targets created", msaaSampleCount)
        return true
    }
    
    // ═══════════════════════════════════════════════════════════════
    // PIPELINE BUILD
    // ═══════════════════════════════════════════════════════════════
    
    private static func buildPipeline(device: MTLDevice, sampleCount: Int) -> MTLRenderPipelineState? {
        // Load shaders from the plugin bundle
        guard let library = try? device.makeDefaultLibrary(bundle: Bundle(for: MetalStrokeRenderer.self)) else {
            NSLog("[FlueraMtl] Failed to load shader library")
            return nil
        }
        
        guard let vertexFn = library.makeFunction(name: "stroke_vertex"),
              let fragmentFn = library.makeFunction(name: "stroke_fragment") else {
            NSLog("[FlueraMtl] Failed to find shader functions")
            return nil
        }
        
        // Vertex descriptor matching StrokeVertex layout
        let vertDesc = MTLVertexDescriptor()
        // position: float2 at offset 0
        vertDesc.attributes[0].format = .float2
        vertDesc.attributes[0].offset = 0
        vertDesc.attributes[0].bufferIndex = 0
        // color: float4 at offset 8
        vertDesc.attributes[1].format = .float4
        vertDesc.attributes[1].offset = MemoryLayout<Float>.stride * 2
        vertDesc.attributes[1].bufferIndex = 0
        // stride = 24 bytes
        vertDesc.layouts[0].stride = MemoryLayout<StrokeVertex>.stride
        
        let pipeDesc = MTLRenderPipelineDescriptor()
        pipeDesc.vertexFunction = vertexFn
        pipeDesc.fragmentFunction = fragmentFn
        pipeDesc.vertexDescriptor = vertDesc
        pipeDesc.rasterSampleCount = sampleCount
        pipeDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        
        // Alpha blending for transparent background compositing
        pipeDesc.colorAttachments[0].isBlendingEnabled = true
        pipeDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipeDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        pipeDesc.colorAttachments[0].sourceAlphaBlendFactor = .one
        pipeDesc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        do {
            return try device.makeRenderPipelineState(descriptor: pipeDesc)
        } catch {
            NSLog("[FlueraMtl] Pipeline creation failed: %@", error.localizedDescription)
            return nil
        }
    }
    
    // ═══════════════════════════════════════════════════════════════
    // UPDATE AND RENDER
    // ═══════════════════════════════════════════════════════════════
    
    func updateAndRender(points: [Float], color: UInt32, strokeWidth: Float, totalPoints: Int,
                         brushType: Int = 0,
                         pencilBaseOpacity: Float = 0.4, pencilMaxOpacity: Float = 0.8,
                         pencilMinPressure: Float = 0.5, pencilMaxPressure: Float = 1.2,
                         fountainThinning: Float = 0.5, fountainNibAngleDeg: Float = 30.0,
                         fountainNibStrength: Float = 0.35, fountainPressureRate: Float = 0.275,
                         fountainTaperEntry: Int = 6) {
        guard isInitialized, points.count >= 10 else { return }
        guard let vertexBuffer = vertexBuffer else { return }
        
        let pointCount = points.count / 5
        
        // Extract RGBA from ARGB32
        let a = Float((color >> 24) & 0xFF) / 255.0
        let r = Float((color >> 16) & 0xFF) / 255.0
        let g = Float((color >> 8) & 0xFF) / 255.0
        let b = Float(color & 0xFF) / 255.0
        
        let prevCount: Int
        
        if brushType == 0 {
            // ── FULL RETESSELLATION (ballpoint) ──────────────────────
            // Accumulate raw points, retessellate entire stroke for smooth
            // curves. Incremental tessellation caused sawtooth edges.
            let skipFirst = totalAccumulatedPoints > 0 ? 1 : 0
            for i in skipFirst..<pointCount {
                for j in 0..<5 {
                    allRawPoints.append(points[i * 5 + j])
                }
            }
            totalAccumulatedPoints = allRawPoints.count / 5
            
            accumulatedVerts.removeAll(keepingCapacity: true)
            prevCount = 0
            
            if totalAccumulatedPoints >= 2 {
                tessellateStroke(points: allRawPoints, pointCount: totalAccumulatedPoints,
                                 r: r, g: g, b: b, a: a,
                                 strokeWidth: strokeWidth,
                                 pointStartIndex: 0,
                                 totalPoints: totalPoints,
                                 minPressure: pencilMinPressure,
                                 maxPressure: pencilMaxPressure)
            }
        } else {
            // ── FULL RETESSELLATION (marker/pencil/fountain) ─────────
            accumulatedVerts.removeAll(keepingCapacity: true)
            totalAccumulatedPoints = pointCount
            prevCount = 0
            
            if brushType == 1 {
                tessellateMarker(points: points, pointCount: pointCount,
                                 r: r, g: g, b: b, a: a,
                                 strokeWidth: strokeWidth)
            } else if brushType == 4 {
                let nibAngleRad = fountainNibAngleDeg * Float.pi / 180.0
                tessellateFountainPen(points: points, pointCount: pointCount,
                                      r: r, g: g, b: b, a: a,
                                      strokeWidth: strokeWidth, totalPoints: pointCount,
                                      thinning: fountainThinning, nibAngleRad: nibAngleRad,
                                      nibStrength: fountainNibStrength, pressureRate: fountainPressureRate,
                                      taperEntry: fountainTaperEntry)
            } else {
                // brushType == 2 (pencil)
                tessellatePencil(points: points, pointCount: pointCount,
                                 r: r, g: g, b: b, a: a,
                                 strokeWidth: strokeWidth,
                                 pointStartIndex: 0,
                                 totalPoints: pointCount,
                                 pencilBaseOpacity: pencilBaseOpacity,
                                 pencilMaxOpacity: pencilMaxOpacity,
                                 pencilMinPressure: pencilMinPressure,
                                 pencilMaxPressure: pencilMaxPressure)
            }
        }
        
        guard accumulatedVerts.count <= MetalStrokeRenderer.maxVertices else {
            accumulatedVerts.removeLast(accumulatedVerts.count - prevCount)
            return
        }
        
        // Upload entire vertex buffer
        let totalCount = accumulatedVerts.count
        if totalCount > 0 {
            let dst = vertexBuffer.contents()
            accumulatedVerts.withUnsafeBufferPointer { buffer in
                let src = UnsafeRawPointer(buffer.baseAddress!)
                dst.copyMemory(from: src, byteCount: totalCount * MemoryLayout<StrokeVertex>.stride)
            }
        }
        
        // Render
        renderFrame(vertexCount: accumulatedVerts.count)
    }
    
    private func renderFrame(vertexCount: Int) {
        guard let msaaTex = msaaTexture,
              let resolveTex = renderTexture,
              let cmdBuffer = commandQueue.makeCommandBuffer() else { return }
        
        // Stats
        statsActive = true
        totalFrames += 1
        let frameStart = CACurrentMediaTime()
        
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = msaaTex
        rpd.colorAttachments[0].resolveTexture = resolveTex
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].storeAction = .multisampleResolve
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        
        guard let encoder = cmdBuffer.makeRenderCommandEncoder(descriptor: rpd) else { return }
        
        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexCount)
        encoder.endEncoding()
        
        cmdBuffer.commit()
        cmdBuffer.waitUntilCompleted()
        
        // Record frame time
        let frameTimeUs = Float((CACurrentMediaTime() - frameStart) * 1_000_000)
        frameTimes.append(frameTimeUs)
        if frameTimes.count > MetalStrokeRenderer.statsMaxSamples {
            frameTimes.removeFirst()
        }
    }
    
    // ═══════════════════════════════════════════════════════════════
    // SET TRANSFORM
    // ═══════════════════════════════════════════════════════════════
    
    func setTransform(_ matrix: [Float]) {
        guard matrix.count == 16 else { return }
        transform = simd_float4x4(
            simd_float4(matrix[0], matrix[1], matrix[2], matrix[3]),
            simd_float4(matrix[4], matrix[5], matrix[6], matrix[7]),
            simd_float4(matrix[8], matrix[9], matrix[10], matrix[11]),
            simd_float4(matrix[12], matrix[13], matrix[14], matrix[15])
        )
        updateUniformBuffer()
    }
    
    private func updateUniformBuffer() {
        guard let buf = uniformBuffer else { return }
        var uniforms = StrokeUniforms(transform: transform)
        memcpy(buf.contents(), &uniforms, MemoryLayout<StrokeUniforms>.size)
    }
    
    // ═══════════════════════════════════════════════════════════════
    // CLEAR
    // ═══════════════════════════════════════════════════════════════
    
    func clearFrame() {
        accumulatedVerts.removeAll(keepingCapacity: true)
        allRawPoints.removeAll(keepingCapacity: true)
        totalAccumulatedPoints = 0
        statsActive = false
        
        // Clear the render target
        guard let resolveTex = renderTexture,
              let cmdBuffer = commandQueue.makeCommandBuffer() else { return }
        
        let rpd = MTLRenderPassDescriptor()
        if let msaaTex = msaaTexture {
            rpd.colorAttachments[0].texture = msaaTex
            rpd.colorAttachments[0].resolveTexture = resolveTex
            rpd.colorAttachments[0].storeAction = .multisampleResolve
        } else {
            rpd.colorAttachments[0].texture = resolveTex
            rpd.colorAttachments[0].storeAction = .store
        }
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        
        guard let encoder = cmdBuffer.makeRenderCommandEncoder(descriptor: rpd) else { return }
        encoder.endEncoding()
        cmdBuffer.commit()
    }
    
    // ═══════════════════════════════════════════════════════════════
    // RESIZE
    // ═══════════════════════════════════════════════════════════════
    
    func resize(width: Int, height: Int) -> Bool {
        self.width = width
        self.height = height
        
        // Recreate render targets
        renderTexture = nil
        msaaTexture = nil
        cvMetalTexture = nil
        pixelBuffer = nil
        
        return createRenderTargets()
    }
    
    // ═══════════════════════════════════════════════════════════════
    // STATS
    // ═══════════════════════════════════════════════════════════════
    
    func getStats() -> MetalStrokeStats {
        var stats = MetalStrokeStats()
        stats.vertexCount = UInt32(accumulatedVerts.count)
        stats.drawCalls = statsActive ? 1 : 0
        stats.totalFrames = totalFrames
        stats.active = statsActive
        stats.deviceName = device.name
        
        if !frameTimes.isEmpty {
            let sorted = frameTimes.sorted()
            let count = sorted.count
            stats.frameTimeP50Us = sorted[count / 2]
            stats.frameTimeP90Us = sorted[min(count - 1, Int(Float(count) * 0.9))]
            stats.frameTimeP99Us = sorted[min(count - 1, Int(Float(count) * 0.99))]
        }
        
        return stats
    }
    
    // ═══════════════════════════════════════════════════════════════
    // DESTROY
    // ═══════════════════════════════════════════════════════════════
    
    func destroy() {
        isInitialized = false
        accumulatedVerts.removeAll()
        renderTexture = nil
        msaaTexture = nil
        cvMetalTexture = nil
        pixelBuffer = nil
        vertexBuffer = nil
        uniformBuffer = nil
    }
    
    /// Get the CVPixelBuffer for Flutter texture sharing
    var outputPixelBuffer: CVPixelBuffer? {
        return pixelBuffer
    }

    // ═══════════════════════════════════════════════════════════════
    // TESSELLATION (ported from vk_stroke_renderer.cpp)
    // ═══════════════════════════════════════════════════════════════
    
    // ─── BALLPOINT: Catmull-Rom spline + EMA smoothing ───────────
    private func tessellateStroke(points: [Float], pointCount: Int,
                                  r: Float, g: Float, b: Float, a: Float,
                                  strokeWidth: Float, pointStartIndex: Int,
                                  totalPoints: Int,
                                  minPressure: Float = 0.7, maxPressure: Float = 1.1) {
        guard pointCount >= 2 else { return }
        
        let adjustedWidth = strokeWidth * (minPressure + 0.5 * (maxPressure - minPressure))
        let baseHalfW = adjustedWidth * 0.5
        let n = pointCount
        
        // Pass 1: Extract positions
        var px = [Float](repeating: 0, count: n)
        var py = [Float](repeating: 0, count: n)
        for i in 0..<n { px[i] = points[i * 5]; py[i] = points[i * 5 + 1] }
        
        // Pass 2: 2-pass bi-directional EMA smoothing
        if n >= 4 {
            let alpha: Float = 0.25
            for _ in 0..<2 {
                for i in 1..<(n - 1) {
                    px[i] = px[i - 1] * alpha + px[i] * (1.0 - alpha)
                    py[i] = py[i - 1] * alpha + py[i] * (1.0 - alpha)
                }
                for i in stride(from: n - 2, through: 1, by: -1) {
                    px[i] = px[i + 1] * alpha + px[i] * (1.0 - alpha)
                    py[i] = py[i + 1] * alpha + py[i] * (1.0 - alpha)
                }
            }
        }
        
        // Pass 3: Catmull-Rom dense sampling at ~1.5px intervals
        struct Vec2 { var x: Float; var y: Float }
        var dense = [Vec2]()
        dense.reserveCapacity(n * 10)
        let sampleStep: Float = 1.5
        
        for seg in 0..<(n - 1) {
            let i0 = seg > 0 ? seg - 1 : 0
            let i1 = seg
            let i2 = seg + 1
            let i3 = seg + 2 < n ? seg + 2 : n - 1
            
            let x0 = px[i0], y0 = py[i0]
            let x1 = px[i1], y1 = py[i1]
            let x2 = px[i2], y2 = py[i2]
            let x3 = px[i3], y3 = py[i3]
            
            let segDx = x2 - x1, segDy = y2 - y1
            let segLen = sqrt(segDx * segDx + segDy * segDy)
            let nSamples = max(2, Int(segLen / sampleStep) + 1)
            
            for s in 0..<nSamples {
                if seg < n - 2 && s == nSamples - 1 { continue }
                let t = Float(s) / Float(nSamples - 1)
                let t2 = t * t, t3 = t2 * t
                let cx = 0.5 * ((2.0 * x1) + (-x0 + x2) * t +
                    (2.0 * x0 - 5.0 * x1 + 4.0 * x2 - x3) * t2 +
                    (-x0 + 3.0 * x1 - 3.0 * x2 + x3) * t3)
                let cy = 0.5 * ((2.0 * y1) + (-y0 + y2) * t +
                    (2.0 * y0 - 5.0 * y1 + 4.0 * y2 - y3) * t2 +
                    (-y0 + 3.0 * y1 - 3.0 * y2 + y3) * t3)
                dense.append(Vec2(x: cx, y: cy))
            }
        }
        dense.append(Vec2(x: px[n - 1], y: py[n - 1]))
        
        let denseCount = dense.count
        guard denseCount >= 2 else { return }
        
        // Pass 4: Perpendicular offsets on dense samples
        for i in 0..<denseCount {
            var dtx: Float = 0, dty: Float = 0
            if i > 0 { dtx += dense[i].x - dense[i-1].x; dty += dense[i].y - dense[i-1].y }
            if i < denseCount - 1 { dtx += dense[i+1].x - dense[i].x; dty += dense[i+1].y - dense[i].y }
            var tLen = sqrt(dtx * dtx + dty * dty)
            if tLen < 0.0001 { dtx = 1; dty = 0; tLen = 1 }
            dtx /= tLen; dty /= tLen
            
            if i == 0 || i == denseCount - 1 {
                generateCircle(cx: dense[i].x, cy: dense[i].y, radius: baseHalfW, r: r, g: g, b: b, a: a)
            }
            
            if i < denseCount - 1 {
                let perpX = -dty, perpY = dtx
                var ntx: Float = 0, nty: Float = 0
                ntx += dense[i+1].x - dense[i].x; nty += dense[i+1].y - dense[i].y
                if i + 1 < denseCount - 1 { ntx += dense[i+2].x - dense[i+1].x; nty += dense[i+2].y - dense[i+1].y }
                var nLen = sqrt(ntx * ntx + nty * nty)
                if nLen < 0.0001 { ntx = 1; nty = 0; nLen = 1 }
                ntx /= nLen; nty /= nLen
                let perpX2 = -nty, perpY2 = ntx
                
                accumulatedVerts.append(StrokeVertex(x: dense[i].x + perpX * baseHalfW, y: dense[i].y + perpY * baseHalfW, r: r, g: g, b: b, a: a))
                accumulatedVerts.append(StrokeVertex(x: dense[i].x - perpX * baseHalfW, y: dense[i].y - perpY * baseHalfW, r: r, g: g, b: b, a: a))
                accumulatedVerts.append(StrokeVertex(x: dense[i+1].x + perpX2 * baseHalfW, y: dense[i+1].y + perpY2 * baseHalfW, r: r, g: g, b: b, a: a))
                accumulatedVerts.append(StrokeVertex(x: dense[i].x - perpX * baseHalfW, y: dense[i].y - perpY * baseHalfW, r: r, g: g, b: b, a: a))
                accumulatedVerts.append(StrokeVertex(x: dense[i+1].x + perpX2 * baseHalfW, y: dense[i+1].y + perpY2 * baseHalfW, r: r, g: g, b: b, a: a))
                accumulatedVerts.append(StrokeVertex(x: dense[i+1].x - perpX2 * baseHalfW, y: dense[i+1].y - perpY2 * baseHalfW, r: r, g: g, b: b, a: a))
            }
        }
    }
    
    private func generateCircle(cx: Float, cy: Float, radius: Float,
                                 r: Float, g: Float, b: Float, a: Float) {
        let segments = max(6, min(16, Int(radius * 1.5)))
        for i in 0..<segments {
            let a0 = 2.0 * Float.pi * Float(i) / Float(segments)
            let a1 = 2.0 * Float.pi * Float(i + 1) / Float(segments)
            accumulatedVerts.append(StrokeVertex(x: cx, y: cy, r: r, g: g, b: b, a: a))
            accumulatedVerts.append(StrokeVertex(x: cx + radius * cos(a0), y: cy + radius * sin(a0), r: r, g: g, b: b, a: a))
            accumulatedVerts.append(StrokeVertex(x: cx + radius * cos(a1), y: cy + radius * sin(a1), r: r, g: g, b: b, a: a))
        }
    }
    
    // ─── MARKER: Catmull-Rom spline dense sampling ───────────────
    private func tessellateMarker(points: [Float], pointCount: Int,
                                   r: Float, g: Float, b: Float, a: Float,
                                   strokeWidth: Float) {
        guard pointCount >= 2 else { return }
        let halfW = strokeWidth * 2.5 * 0.5
        let ma = a  // Full alpha — marker opacity handled by Flutter Opacity widget
        
        // Extract positions
        var px = [Float](repeating: 0, count: pointCount)
        var py = [Float](repeating: 0, count: pointCount)
        for i in 0..<pointCount { px[i] = points[i * 5]; py[i] = points[i * 5 + 1] }
        
        // Catmull-Rom spline dense sampling
        struct Vec2 { var x: Float; var y: Float }
        var dense = [Vec2]()
        dense.reserveCapacity(pointCount * 10)
        let sampleStep: Float = 1.5
        
        for seg in 0..<(pointCount - 1) {
            let i0 = seg > 0 ? seg - 1 : 0
            let i1 = seg, i2 = seg + 1
            let i3 = seg + 2 < pointCount ? seg + 2 : pointCount - 1
            let x0 = px[i0], y0 = py[i0], x1 = px[i1], y1 = py[i1]
            let x2 = px[i2], y2 = py[i2], x3 = px[i3], y3 = py[i3]
            let segDx = x2 - x1, segDy = y2 - y1
            let segLen = sqrt(segDx * segDx + segDy * segDy)
            let nSamples = max(2, Int(segLen / sampleStep) + 1)
            for s in 0..<nSamples {
                if seg < pointCount - 2 && s == nSamples - 1 { continue }
                let t = Float(s) / Float(nSamples - 1)
                let t2 = t * t, t3 = t2 * t
                let cx = 0.5 * ((2*x1) + (-x0+x2)*t + (2*x0-5*x1+4*x2-x3)*t2 + (-x0+3*x1-3*x2+x3)*t3)
                let cy = 0.5 * ((2*y1) + (-y0+y2)*t + (2*y0-5*y1+4*y2-y3)*t2 + (-y0+3*y1-3*y2+y3)*t3)
                dense.append(Vec2(x: cx, y: cy))
            }
        }
        dense.append(Vec2(x: px[pointCount - 1], y: py[pointCount - 1]))
        
        let denseCount = dense.count
        guard denseCount >= 2 else { return }
        
        // Perpendicular offsets on dense spline
        struct Vec2L { var x: Float; var y: Float }
        var leftPts = [Vec2L](repeating: Vec2L(x: 0, y: 0), count: denseCount)
        var rightPts = [Vec2L](repeating: Vec2L(x: 0, y: 0), count: denseCount)
        
        for i in 0..<denseCount {
            var tx: Float = 0, ty: Float = 0
            if i > 0 { tx += dense[i].x - dense[i-1].x; ty += dense[i].y - dense[i-1].y }
            if i < denseCount - 1 { tx += dense[i+1].x - dense[i].x; ty += dense[i+1].y - dense[i].y }
            var tLen = sqrt(tx * tx + ty * ty)
            if tLen < 0.0001 { tx = 1; ty = 0; tLen = 1 }
            tx /= tLen; ty /= tLen
            leftPts[i] = Vec2L(x: dense[i].x + (-ty) * halfW, y: dense[i].y + tx * halfW)
            rightPts[i] = Vec2L(x: dense[i].x - (-ty) * halfW, y: dense[i].y - tx * halfW)
        }
        
        for i in 0..<(denseCount - 1) {
            accumulatedVerts.append(StrokeVertex(x: leftPts[i].x, y: leftPts[i].y, r: r, g: g, b: b, a: ma))
            accumulatedVerts.append(StrokeVertex(x: rightPts[i].x, y: rightPts[i].y, r: r, g: g, b: b, a: ma))
            accumulatedVerts.append(StrokeVertex(x: leftPts[i+1].x, y: leftPts[i+1].y, r: r, g: g, b: b, a: ma))
            accumulatedVerts.append(StrokeVertex(x: rightPts[i].x, y: rightPts[i].y, r: r, g: g, b: b, a: ma))
            accumulatedVerts.append(StrokeVertex(x: leftPts[i+1].x, y: leftPts[i+1].y, r: r, g: g, b: b, a: ma))
            accumulatedVerts.append(StrokeVertex(x: rightPts[i+1].x, y: rightPts[i+1].y, r: r, g: g, b: b, a: ma))
        }
    }
    
    // ─── PENCIL: pressure→opacity+width, round caps, grain ───────
    private func tessellatePencil(points: [Float], pointCount: Int,
                                  r: Float, g: Float, b: Float, a: Float,
                                  strokeWidth: Float,
                                  pointStartIndex: Int, totalPoints: Int,
                                  pencilBaseOpacity: Float = 0.4, pencilMaxOpacity: Float = 0.8,
                                  pencilMinPressure: Float = 0.5, pencilMaxPressure: Float = 1.2) {
        guard pointCount >= 2 else { return }
        let minP = pencilMinPressure, maxP = pencilMaxPressure
        let taperPts = 4; let taperStart: Float = 0.15
        let baseOp = pencilBaseOpacity, maxOp = pencilMaxOpacity
        let grainI: Float = 0.08
        let baseHW = strokeWidth * 0.5
        
        func grainHash(_ x: Float, _ y: Float) -> Float {
            var ix = Int(x * 7.3), iy = Int(y * 11.7)
            var h = (ix &* 374761393 &+ iy &* 668265263) ^ (ix &* 1274126177)
            h = (h ^ (h >> 13)) &* 1103515245
            return Float(h & 0x7FFFFFFF) / Float(0x7FFFFFFF)
        }
        
        struct OutPt { var lx: Float; var ly: Float; var rx: Float; var ry: Float; var alpha: Float }
        var outline = [OutPt](repeating: OutPt(lx: 0, ly: 0, rx: 0, ry: 0, alpha: 0), count: pointCount)
        
        for i in 0..<pointCount {
            let px = points[i*5], py = points[i*5+1], pp = points[i*5+2]
            let gi = pointStartIndex + i
            var hw = baseHW * (minP + pp * (maxP - minP))
            if gi < taperPts { let t = Float(gi) / Float(taperPts); hw *= taperStart + t * (2 - t) * (1 - taperStart) }
            var pa = a * (baseOp + (maxOp - baseOp) * pp)
            var tx: Float = 0, ty: Float = 0
            if i > 0 { tx += px - points[(i-1)*5]; ty += py - points[(i-1)*5+1] }
            if i < pointCount-1 { tx += points[(i+1)*5] - px; ty += points[(i+1)*5+1] - py }
            var tLen = sqrt(tx*tx + ty*ty); if tLen < 0.0001 { tx = 1; ty = 0; tLen = 1 }
            tx /= tLen; ty /= tLen
            outline[i] = OutPt(lx: px + (-ty)*hw, ly: py + tx*hw, rx: px - (-ty)*hw, ry: py - tx*hw, alpha: pa)
        }
        
        for i in 0..<(pointCount - 1) {
            let p = outline[i], n = outline[i+1]
            accumulatedVerts.append(StrokeVertex(x: p.lx, y: p.ly, r: r, g: g, b: b, a: p.alpha))
            accumulatedVerts.append(StrokeVertex(x: p.rx, y: p.ry, r: r, g: g, b: b, a: p.alpha))
            accumulatedVerts.append(StrokeVertex(x: n.lx, y: n.ly, r: r, g: g, b: b, a: n.alpha))
            accumulatedVerts.append(StrokeVertex(x: p.rx, y: p.ry, r: r, g: g, b: b, a: p.alpha))
            accumulatedVerts.append(StrokeVertex(x: n.lx, y: n.ly, r: r, g: g, b: b, a: n.alpha))
            accumulatedVerts.append(StrokeVertex(x: n.rx, y: n.ry, r: r, g: g, b: b, a: n.alpha))
        }
    }
    // ═══════════════════════════════════════════════════════════════
    // FOUNTAIN PEN (STILOGRAFICA) — Full calligraphic pipeline
    // Ported from vk_stroke_renderer.cpp tessellateFountainPen
    // ═══════════════════════════════════════════════════════════════
    
    private func tessellateFountainPen(points: [Float], pointCount: Int,
                                       r: Float, g: Float, b: Float, a: Float,
                                       strokeWidth: Float, totalPoints: Int,
                                       thinning: Float, nibAngleRad: Float,
                                       nibStrength: Float, pressureRate: Float,
                                       taperEntry: Int) {
        guard pointCount >= 2 else { return }
        let n = pointCount
        
        // Detect finger input (constant pressure)
        var isFingerInput = true
        do {
            let firstP = Double(points[2])
            let checkLen = min(n, 10)
            var minP = firstP, maxP = firstP
            for i in 1..<checkLen {
                let p = Double(points[i * 5 + 2])
                if p < minP { minP = p }
                if p > maxP { maxP = p }
            }
            isFingerInput = (maxP - minP) < 0.15
        }
        
        // Streamline + pressure accumulator + width calculation (all Double)
        var widths = [Double](repeating: 0, count: n)
        var px = [Double](repeating: 0, count: n)
        var py = [Double](repeating: 0, count: n)
        
        do {
            let streamT = 0.575
            var prevSX = Double(points[0]), prevSY = Double(points[1])
            var accPressure = 0.25
            var prevSp = 0.0
            let dSW = Double(strokeWidth)
            let dThin = Double(thinning)
            let dNibRad = Double(nibAngleRad)
            let dPRate = Double(pressureRate)
            let effNibStr = isFingerInput
                ? min(Double(nibStrength) * 0.7, 0.7)
                : min(Double(nibStrength) * 0.75, 0.75)
            
            for i in 0..<n {
                let rawX = Double(points[i * 5]), rawY = Double(points[i * 5 + 1])
                let sx: Double, sy: Double
                if i == 0 { sx = rawX; sy = rawY }
                else { sx = prevSX + (rawX - prevSX) * streamT; sy = prevSY + (rawY - prevSY) * streamT }
                let dist = i > 0 ? sqrt((sx - prevSX) * (sx - prevSX) + (sy - prevSY) * (sy - prevSY)) : 0.0
                px[i] = rawX; py[i] = rawY
                prevSX = sx; prevSY = sy
                
                var dirX = 0.0, dirY = 0.0
                if i > 0 && dist > 0.01 {
                    let dx = rawX - Double(points[(i-1)*5]), dy = rawY - Double(points[(i-1)*5+1])
                    let dlen = sqrt(dx*dx + dy*dy)
                    if dlen > 0 { dirX = dx / dlen; dirY = dy / dlen }
                }
                
                // Pressure accumulator
                var pressure: Double
                var acceleration = 0.0
                if isFingerInput {
                    let sp = min(1.0, dist / (dSW * 0.55))
                    let rp = min(1.0, 1.0 - sp)
                    accPressure = min(1.0, accPressure + (rp - accPressure) * sp * dPRate)
                    pressure = accPressure
                    acceleration = sp - prevSp
                    prevSp = sp
                } else {
                    pressure = Double(points[i * 5 + 2])
                }
                
                var thinned = max(0.02, min(1.0, 0.5 - dThin * (0.5 - pressure)))
                var w = dSW * thinned
                
                if isFingerInput {
                    let accelMod = max(0.88, min(1.12, 1.0 - acceleration * 0.6))
                    w *= accelMod
                }
                
                // Nib angle
                if dirX != 0 || dirY != 0 {
                    let strokeAngle = atan2(dirY, dirX)
                    let angleDiff = fmod(abs(strokeAngle - dNibRad), Double.pi)
                    let perp = sin(angleDiff)
                    w *= (1.0 - effNibStr + perp * effNibStr * 2.0)
                }
                
                // Curvature modulation
                if i >= 2 {
                    let p0x = Double(points[(i-2)*5]), p0y = Double(points[(i-2)*5+1])
                    let p1x = Double(points[(i-1)*5]), p1y = Double(points[(i-1)*5+1])
                    let d1x = p1x-p0x, d1y = p1y-p0y, d2x = rawX-p1x, d2y = rawY-p1y
                    let cross = abs(d1x*d2y - d1y*d2x)
                    let dot = d1x*d2x + d1y*d2y
                    let angle = atan2(cross, dot)
                    let curv = max(0, min(1, angle / Double.pi))
                    w *= 1.0 + curv * 0.35
                }
                
                // Velocity modifier (stylus only)
                if !isFingerInput && dist > 0 {
                    let sp = min(1.0, dist / dSW)
                    let velMod = max(0.5, min(1.3, 1.15 - sp * 0.5 * 0.6))
                    w *= velMod
                }
                
                widths[i] = max(dSW * 0.12, min(dSW * 3.5, w))
            }
        }
        
        // Tapering (entry only, easeInOutCubic)
        do {
            let entryLen = min(taperEntry, n - 1)
            for i in 0..<entryLen {
                let t = Double(i) / Double(taperEntry)
                let factor: Double
                if t < 0.5 { factor = 4.0 * t * t * t }
                else { let v = -2.0 * t + 2.0; factor = 1.0 - (v * v * v) / 2.0 }
                widths[i] *= max(0.0, min(1.0, factor))
            }
        }
        
        // 2-pass EMA width smoothing (alpha=0.35)
        do {
            let alpha = 0.35
            var sm = widths[0]
            for i in 1..<n { sm = sm * alpha + widths[i] * (1.0 - alpha); widths[i] = sm }
            sm = widths[n - 1]
            for i in stride(from: n - 2, through: 0, by: -1) { sm = sm * alpha + widths[i] * (1.0 - alpha); widths[i] = sm }
        }
        
        // Rate limiting (maxChangeRate=0.12)
        do {
            let mcr = 0.12
            for i in 1..<n { widths[i] = max(widths[i-1] * (1-mcr), min(widths[i-1] * (1+mcr), widths[i])) }
            for i in stride(from: n - 2, through: 0, by: -1) { widths[i] = max(widths[i+1] * (1-mcr), min(widths[i+1] * (1+mcr), widths[i])) }
        }
        
        // Position smoothing (2-pass bi-directional)
        if n >= 4 {
            let posAlpha = 0.3
            for _ in 0..<2 {
                for i in 1..<(n - 1) { px[i] = px[i-1]*posAlpha + px[i]*(1-posAlpha); py[i] = py[i-1]*posAlpha + py[i]*(1-posAlpha) }
                for i in stride(from: n - 2, through: 1, by: -1) { px[i] = px[i+1]*posAlpha + px[i]*(1-posAlpha); py[i] = py[i+1]*posAlpha + py[i]*(1-posAlpha) }
            }
        }
        
        // Curvature-adaptive smoothing
        if n >= 5 {
            for i in 2..<(n - 2) {
                let v1x = px[i]-px[i-1], v1y = py[i]-py[i-1]
                let v2x = px[i+1]-px[i], v2y = py[i+1]-py[i]
                let crossV = abs(v1x*v2y - v1y*v2x), dotV = v1x*v2x + v1y*v2y
                let blend = max(0, min(1, atan2(crossV, dotV) / Double.pi)) * 0.4
                if blend > 0.02 {
                    let avgX = (px[i-1]+px[i+1])*0.5, avgY = (py[i-1]+py[i+1])*0.5
                    px[i] = px[i]*(1-blend) + avgX*blend; py[i] = py[i]*(1-blend) + avgY*blend
                }
            }
        }
        
        // Arc-length reparameterization
        if n >= 10 {
            var arcLen = [Double](repeating: 0, count: n)
            for i in 1..<n { let dx = px[i]-px[i-1], dy = py[i]-py[i-1]; arcLen[i] = arcLen[i-1] + sqrt(dx*dx + dy*dy) }
            let totalLen = arcLen[n - 1]
            if totalLen > 1.0 {
                let numSamples = n
                let step = totalLen / Double(numSamples - 1)
                var rPx = [Double](repeating: 0, count: numSamples)
                var rPy = [Double](repeating: 0, count: numSamples)
                var rW = [Double](repeating: 0, count: numSamples)
                rPx[0] = px[0]; rPy[0] = py[0]; rW[0] = widths[0]
                var seg = 0
                for s in 1..<(numSamples - 1) {
                    let targetLen = Double(s) * step
                    while seg < n - 2 && arcLen[seg + 1] < targetLen { seg += 1 }
                    let segLen = arcLen[seg + 1] - arcLen[seg]
                    let frac = segLen > 0.001 ? (targetLen - arcLen[seg]) / segLen : 0.0
                    rPx[s] = px[seg] + (px[seg+1]-px[seg])*frac
                    rPy[s] = py[seg] + (py[seg+1]-py[seg])*frac
                    rW[s] = widths[seg] + (widths[seg+1]-widths[seg])*frac
                }
                rPx[numSamples-1] = px[n-1]; rPy[numSamples-1] = py[n-1]; rW[numSamples-1] = widths[n-1]
                for i in 0..<numSamples { px[i] = rPx[i]; py[i] = rPy[i]; widths[i] = rW[i] }
            }
        }
        
        // 7-point weighted tangent computation
        var tanX = [Double](repeating: 0, count: n), tanY = [Double](repeating: 0, count: n)
        for i in 0..<n {
            var tx: Double, ty: Double
            if i == 0 { tx = px[1]-px[0]; ty = py[1]-py[0] }
            else if i == n-1 { tx = px[n-1]-px[n-2]; ty = py[n-1]-py[n-2] }
            else {
                tx = px[i+1]-px[i-1]; ty = py[i+1]-py[i-1]
                if i >= 2 && i < n-2 {
                    let fx = px[i+2]-px[i-2], fy = py[i+2]-py[i-2]
                    tx = tx*0.6 + fx*0.3; ty = ty*0.6 + fy*0.3
                    if i >= 3 && i < n-3 { tx += (px[i+3]-px[i-3])*0.1; ty += (py[i+3]-py[i-3])*0.1 }
                }
            }
            let tlen = sqrt(tx*tx + ty*ty)
            if tlen > 0 { tanX[i] = tx/tlen; tanY[i] = ty/tlen } else { tanX[i] = 1; tanY[i] = 0 }
        }
        
        // Outline generation
        var leftX = [Double](repeating: 0, count: n), leftY = [Double](repeating: 0, count: n)
        var rightX = [Double](repeating: 0, count: n), rightY = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let hw = widths[i] * 0.5, nx = -tanY[i], ny = tanX[i]
            leftX[i] = px[i] + nx*hw; leftY[i] = py[i] + ny*hw
            rightX[i] = px[i] - nx*hw; rightY[i] = py[i] - ny*hw
        }
        
        // Outline smoothing
        do {
            var avgW = 0.0; for i in 0..<n { avgW += widths[i] }; avgW /= Double(n)
            let alpha = max(0.35, min(0.65, 0.35 + avgW / 40.0))
            let passes = avgW > 8.0 ? 3 : 2
            for _ in 0..<passes {
                for i in 1..<(n-1) {
                    leftX[i] = leftX[i-1]*alpha + leftX[i]*(1-alpha); leftY[i] = leftY[i-1]*alpha + leftY[i]*(1-alpha)
                    rightX[i] = rightX[i-1]*alpha + rightX[i]*(1-alpha); rightY[i] = rightY[i-1]*alpha + rightY[i]*(1-alpha)
                }
                for i in stride(from: n-2, through: 1, by: -1) {
                    leftX[i] = leftX[i+1]*alpha + leftX[i]*(1-alpha); leftY[i] = leftY[i+1]*alpha + leftY[i]*(1-alpha)
                    rightX[i] = rightX[i+1]*alpha + rightX[i]*(1-alpha); rightY[i] = rightY[i+1]*alpha + rightY[i]*(1-alpha)
                }
            }
        }
        
        // Chaikin corner-cutting subdivision (1 iteration)
        do {
            let outLen = 2 * (n - 1) + 2
            var cLX = [Double](repeating: 0, count: outLen), cLY = [Double](repeating: 0, count: outLen)
            var cRX = [Double](repeating: 0, count: outLen), cRY = [Double](repeating: 0, count: outLen)
            var ci = 0
            cLX[ci] = leftX[0]; cLY[ci] = leftY[0]; cRX[ci] = rightX[0]; cRY[ci] = rightY[0]; ci += 1
            for i in 0..<(n-1) {
                cLX[ci] = leftX[i]*0.75+leftX[i+1]*0.25; cLY[ci] = leftY[i]*0.75+leftY[i+1]*0.25
                cRX[ci] = rightX[i]*0.75+rightX[i+1]*0.25; cRY[ci] = rightY[i]*0.75+rightY[i+1]*0.25; ci += 1
                cLX[ci] = leftX[i]*0.25+leftX[i+1]*0.75; cLY[ci] = leftY[i]*0.25+leftY[i+1]*0.75
                cRX[ci] = rightX[i]*0.25+rightX[i+1]*0.75; cRY[ci] = rightY[i]*0.25+rightY[i+1]*0.75; ci += 1
            }
            cLX[ci] = leftX[n-1]; cLY[ci] = leftY[n-1]; cRX[ci] = rightX[n-1]; cRY[ci] = rightY[n-1]; ci += 1
            leftX = Array(cLX[0..<ci]); leftY = Array(cLY[0..<ci])
            rightX = Array(cRX[0..<ci]); rightY = Array(cRY[0..<ci])
        }
        
        let outN = leftX.count
        
        // Crossed-outline fix
        for i in 1..<outN {
            let pLRx = rightX[i-1]-leftX[i-1], pLRy = rightY[i-1]-leftY[i-1]
            let cLRx = rightX[i]-leftX[i], cLRy = rightY[i]-leftY[i]
            let cross = pLRx*cLRy - pLRy*cLRx, dot = pLRx*cLRx + pLRy*cLRy
            let pD = sqrt(pLRx*pLRx + pLRy*pLRy), cD = sqrt(cLRx*cLRx + cLRy*cLRy)
            if dot < 0 || abs(cross) > pD * cD * 0.95 {
                let cx = (leftX[i]+rightX[i])*0.5, cy = (leftY[i]+rightY[i])*0.5
                leftX[i] = cx; leftY[i] = cy; rightX[i] = cx; rightY[i] = cy
            }
        }
        
        // Triangle strip
        for i in 0..<(outN - 1) {
            let ni = i + 1
            accumulatedVerts.append(StrokeVertex(x: Float(leftX[i]), y: Float(leftY[i]), r: r, g: g, b: b, a: a))
            accumulatedVerts.append(StrokeVertex(x: Float(rightX[i]), y: Float(rightY[i]), r: r, g: g, b: b, a: a))
            accumulatedVerts.append(StrokeVertex(x: Float(leftX[ni]), y: Float(leftY[ni]), r: r, g: g, b: b, a: a))
            accumulatedVerts.append(StrokeVertex(x: Float(rightX[i]), y: Float(rightY[i]), r: r, g: g, b: b, a: a))
            accumulatedVerts.append(StrokeVertex(x: Float(leftX[ni]), y: Float(leftY[ni]), r: r, g: g, b: b, a: a))
            accumulatedVerts.append(StrokeVertex(x: Float(rightX[ni]), y: Float(rightY[ni]), r: r, g: g, b: b, a: a))
        }
        
        // End cap: semicircular
        do {
            let lx = leftX[outN-1], ly = leftY[outN-1], rx = rightX[outN-1], ry = rightY[outN-1]
            let cx = (lx+rx)*0.5, cy = (ly+ry)*0.5
            let rad = sqrt((lx-rx)*(lx-rx)+(ly-ry)*(ly-ry)) * 0.5
            if rad > 0.1 {
                let segs = 10
                let base = atan2(ly-cy, lx-cx)
                for s in 0..<segs {
                    let a0 = base - Double.pi * Double(s) / Double(segs)
                    let a1 = base - Double.pi * Double(s+1) / Double(segs)
                    accumulatedVerts.append(StrokeVertex(x: Float(cx), y: Float(cy), r: r, g: g, b: b, a: a))
                    accumulatedVerts.append(StrokeVertex(x: Float(cx + rad*cos(a0)), y: Float(cy + rad*sin(a0)), r: r, g: g, b: b, a: a))
                    accumulatedVerts.append(StrokeVertex(x: Float(cx + rad*cos(a1)), y: Float(cy + rad*sin(a1)), r: r, g: g, b: b, a: a))
                }
            }
        }
        // Start cap: semicircular
        do {
            let lx = leftX[0], ly = leftY[0], rx = rightX[0], ry = rightY[0]
            let cx = (lx+rx)*0.5, cy = (ly+ry)*0.5
            let rad = sqrt((lx-rx)*(lx-rx)+(ly-ry)*(ly-ry)) * 0.5
            if rad > 0.1 {
                let segs = 10
                let base = atan2(ry-cy, rx-cx)
                for s in 0..<segs {
                    let a0 = base - Double.pi * Double(s) / Double(segs)
                    let a1 = base - Double.pi * Double(s+1) / Double(segs)
                    accumulatedVerts.append(StrokeVertex(x: Float(cx), y: Float(cy), r: r, g: g, b: b, a: a))
                    accumulatedVerts.append(StrokeVertex(x: Float(cx + rad*cos(a0)), y: Float(cy + rad*sin(a0)), r: r, g: g, b: b, a: a))
                    accumulatedVerts.append(StrokeVertex(x: Float(cx + rad*cos(a1)), y: Float(cy + rad*sin(a1)), r: r, g: g, b: b, a: a))
                }
            }
        }
    }
}
