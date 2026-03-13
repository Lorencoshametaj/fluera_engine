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
    
    func updateAndRender(points: [Float], color: UInt32, strokeWidth: Float, totalPoints: Int, brushType: Int = 0) {
        guard isInitialized, points.count >= 6 else { return }
        guard let vertexBuffer = vertexBuffer else { return }
        
        let pointCount = points.count / 5
        
        // Extract RGBA from ARGB32
        let a = Float((color >> 24) & 0xFF) / 255.0
        let r = Float((color >> 16) & 0xFF) / 255.0
        let g = Float((color >> 8) & 0xFF) / 255.0
        let b = Float(color & 0xFF) / 255.0
        
        // Track global point index for tapering
        let startIndex = totalAccumulatedPoints
        totalAccumulatedPoints += pointCount
        let adjustedStart = startIndex > 0 ? startIndex - 1 : 0
        
        // Tessellate new points
        let prevCount = accumulatedVerts.count
        
        if brushType == 1 {
            // 🖍️ THICK MARKER: wider, pressure-sensitive, flat caps
            tessellateMarker(points: points, pointCount: pointCount,
                             r: r, g: g, b: b, a: a,
                             strokeWidth: strokeWidth)
        } else if brushType == 2 {
            // ✏️ SOFT PENCIL: pressure→opacity+width, round caps, grain
            tessellatePencil(points: points, pointCount: pointCount,
                             r: r, g: g, b: b, a: a,
                             strokeWidth: strokeWidth,
                             pointStartIndex: adjustedStart,
                             totalPoints: totalPoints)
        } else {
            // ✒️ BALLPOINT (default): constant width, round caps, entry taper
            tessellateStroke(points: points, pointCount: pointCount,
                             r: r, g: g, b: b, a: a,
                             strokeWidth: strokeWidth,
                             pointStartIndex: adjustedStart,
                             totalPoints: totalPoints)
        }
        
        guard accumulatedVerts.count <= MetalStrokeRenderer.maxVertices else {
            accumulatedVerts.removeLast(accumulatedVerts.count - prevCount)
            return
        }
        
        // Upload only new vertices
        let newCount = accumulatedVerts.count - prevCount
        if newCount > 0 {
            let dst = vertexBuffer.contents().advanced(by: prevCount * MemoryLayout<StrokeVertex>.stride)
            accumulatedVerts.withUnsafeBufferPointer { buffer in
                let src = UnsafeRawPointer(buffer.baseAddress! + prevCount)
                dst.copyMemory(from: src, byteCount: newCount * MemoryLayout<StrokeVertex>.stride)
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
    
    private func tessellateStroke(points: [Float], pointCount: Int,
                                  r: Float, g: Float, b: Float, a: Float,
                                  strokeWidth: Float, pointStartIndex: Int,
                                  totalPoints: Int) {
        guard pointCount >= 2 else { return }
        
        // Ballpoint: constant width matching Dart
        let widthFactor: Float = 0.925
        let taperPoints = 3
        let taperStartFrac: Float = 0.60
        let baseHalfW = strokeWidth * widthFactor * 0.5
        
        for i in 0..<pointCount {
            let px = points[i * 5]
            let py = points[i * 5 + 1]
            let globalIdx = pointStartIndex + i
            
            // Width = base × entry taper
            var halfW = baseHalfW
            if globalIdx < taperPoints {
                let t = Float(globalIdx + 1) / Float(taperPoints)
                let ease = 1.0 - (1.0 - t) * (1.0 - t) * (1.0 - t)  // easeOutCubic
                halfW *= taperStartFrac + (1.0 - taperStartFrac) * ease
            }
            
            // Circle at every point (round join/cap)
            generateCircle(cx: px, cy: py, radius: halfW, r: r, g: g, b: b, a: a)
            
            // Segment quad to next point
            if i < pointCount - 1 {
                let nx = points[(i + 1) * 5]
                let ny = points[(i + 1) * 5 + 1]
                
                let dx = nx - px
                let dy = ny - py
                let len = sqrt(dx * dx + dy * dy)
                guard len >= 0.001 else { continue }
                
                // Next point's taper width
                let nextGlobal = globalIdx + 1
                var nHalfW = baseHalfW
                if nextGlobal < taperPoints {
                    let t = Float(nextGlobal + 1) / Float(taperPoints)
                    let ease = 1.0 - (1.0 - t) * (1.0 - t) * (1.0 - t)
                    nHalfW *= taperStartFrac + (1.0 - taperStartFrac) * ease
                }
                
                let perpX = -dy / len
                let perpY = dx / len
                
                // Two triangles forming a quad
                accumulatedVerts.append(StrokeVertex(x: px + perpX * halfW, y: py + perpY * halfW, r: r, g: g, b: b, a: a))
                accumulatedVerts.append(StrokeVertex(x: px - perpX * halfW, y: py - perpY * halfW, r: r, g: g, b: b, a: a))
                accumulatedVerts.append(StrokeVertex(x: nx + perpX * nHalfW, y: ny + perpY * nHalfW, r: r, g: g, b: b, a: a))
                accumulatedVerts.append(StrokeVertex(x: px - perpX * halfW, y: py - perpY * halfW, r: r, g: g, b: b, a: a))
                accumulatedVerts.append(StrokeVertex(x: nx + perpX * nHalfW, y: ny + perpY * nHalfW, r: r, g: g, b: b, a: a))
                accumulatedVerts.append(StrokeVertex(x: nx - perpX * nHalfW, y: ny - perpY * nHalfW, r: r, g: g, b: b, a: a))
            }
        }
    }
    
    private func generateCircle(cx: Float, cy: Float, radius: Float,
                                 r: Float, g: Float, b: Float, a: Float) {
        // Adaptive segment count based on radius
        let segments = max(8, min(24, Int(radius * 2.0)))
        
        for i in 0..<segments {
            let a0 = 2.0 * Float.pi * Float(i) / Float(segments)
            let a1 = 2.0 * Float.pi * Float(i + 1) / Float(segments)
            
            let x0 = cx + radius * cos(a0)
            let y0 = cy + radius * sin(a0)
            let x1 = cx + radius * cos(a1)
            let y1 = cy + radius * sin(a1)
            
            // Triangle fan
            accumulatedVerts.append(StrokeVertex(x: cx, y: cy, r: r, g: g, b: b, a: a))
            accumulatedVerts.append(StrokeVertex(x: x0, y: y0, r: r, g: g, b: b, a: a))
            accumulatedVerts.append(StrokeVertex(x: x1, y: y1, r: r, g: g, b: b, a: a))
        }
    }
    
    // ═══════════════════════════════════════════════════════════════
    // TESSELLATE MARKER (ported from vk_stroke_renderer.cpp)
    // ═══════════════════════════════════════════════════════════════
    
    private func tessellateMarker(points: [Float], pointCount: Int,
                                   r: Float, g: Float, b: Float, a: Float,
                                   strokeWidth: Float) {
        guard pointCount >= 2 else { return }
        let halfW = strokeWidth * 2.5 * 0.5
        let ma = a * 0.7
        
        // No EMA on GPU — applied only in Dart committed stroke
        
        struct V2 { var x: Float; var y: Float }
        var lp = [V2](repeating: V2(x:0,y:0), count: pointCount)
        var rp = [V2](repeating: V2(x:0,y:0), count: pointCount)
        for i in 0..<pointCount {
            let px = points[i*5], py = points[i*5+1]
            var tx: Float = 0, ty: Float = 0
            if i > 0 { tx += px-points[(i-1)*5]; ty += py-points[(i-1)*5+1] }
            if i < pointCount-1 { tx += points[(i+1)*5]-px; ty += points[(i+1)*5+1]-py }
            var tl = sqrt(tx*tx+ty*ty); if tl < 0.0001 { tx=1; ty=0; tl=1 }; tx/=tl; ty/=tl
            lp[i] = V2(x: px+(-ty)*halfW, y: py+tx*halfW)
            rp[i] = V2(x: px-(-ty)*halfW, y: py-tx*halfW)
        }
        for i in 0..<(pointCount-1) {
            accumulatedVerts.append(StrokeVertex(x:lp[i].x,y:lp[i].y,r:r,g:g,b:b,a:ma))
            accumulatedVerts.append(StrokeVertex(x:rp[i].x,y:rp[i].y,r:r,g:g,b:b,a:ma))
            accumulatedVerts.append(StrokeVertex(x:lp[i+1].x,y:lp[i+1].y,r:r,g:g,b:b,a:ma))
            accumulatedVerts.append(StrokeVertex(x:rp[i].x,y:rp[i].y,r:r,g:g,b:b,a:ma))
            accumulatedVerts.append(StrokeVertex(x:lp[i+1].x,y:lp[i+1].y,r:r,g:g,b:b,a:ma))
            accumulatedVerts.append(StrokeVertex(x:rp[i+1].x,y:rp[i+1].y,r:r,g:g,b:b,a:ma))
        }
    }
                                   strokeWidth: Float) {
        guard pointCount >= 2 else { return }
        let halfW = strokeWidth * 2.5 * 0.5
        let ma = a * 0.7
        
        struct V2 { var x: Float; var y: Float }
        var leftPts = [V2](repeating: V2(x:0,y:0), count: pointCount)
        var rightPts = [V2](repeating: V2(x:0,y:0), count: pointCount)
        
        for i in 0..<pointCount {
            let px = points[i*5], py = points[i*5+1]
            var tx: Float = 0, ty: Float = 0
            if i > 0 { tx += px - points[(i-1)*5]; ty += py - points[(i-1)*5+1] }
            if i < pointCount-1 { tx += points[(i+1)*5] - px; ty += points[(i+1)*5+1] - py }
            var tLen = sqrt(tx*tx + ty*ty)
            if tLen < 0.0001 { tx = 1; ty = 0; tLen = 1 }
            tx /= tLen; ty /= tLen
            leftPts[i] = V2(x: px + (-ty)*halfW, y: py + tx*halfW)
            rightPts[i] = V2(x: px - (-ty)*halfW, y: py - tx*halfW)
        }
        
        generateCircle(cx: points[0], cy: points[1], radius: halfW, r: r, g: g, b: b, a: ma)
        for i in 0..<(pointCount-1) {
            accumulatedVerts.append(StrokeVertex(x: leftPts[i].x, y: leftPts[i].y, r: r, g: g, b: b, a: ma))
            accumulatedVerts.append(StrokeVertex(x: rightPts[i].x, y: rightPts[i].y, r: r, g: g, b: b, a: ma))
            accumulatedVerts.append(StrokeVertex(x: leftPts[i+1].x, y: leftPts[i+1].y, r: r, g: g, b: b, a: ma))
            accumulatedVerts.append(StrokeVertex(x: rightPts[i].x, y: rightPts[i].y, r: r, g: g, b: b, a: ma))
            accumulatedVerts.append(StrokeVertex(x: leftPts[i+1].x, y: leftPts[i+1].y, r: r, g: g, b: b, a: ma))
            accumulatedVerts.append(StrokeVertex(x: rightPts[i+1].x, y: rightPts[i+1].y, r: r, g: g, b: b, a: ma))
        }
        let last = (pointCount-1)*5
        generateCircle(cx: points[last], cy: points[last+1], radius: halfW, r: r, g: g, b: b, a: ma)
    }
                                   strokeWidth: Float) {
        guard pointCount >= 2 else { return }
        let widthMult: Float = 2.5
        let markerOpacity: Float = 0.7
        let halfW = strokeWidth * widthMult * 0.5
        let ma = a * markerOpacity
        
        // Start cap only
        generateCircle(cx: points[0], cy: points[1], radius: halfW, r: r, g: g, b: b, a: ma)
        
        // Body quads (no per-point circles)
        for i in 0..<(pointCount - 1) {
            let px = points[i * 5], py = points[i * 5 + 1]
            let nx = points[(i + 1) * 5], ny = points[(i + 1) * 5 + 1]
            let dx = nx - px, dy = ny - py
            let len = sqrt(dx * dx + dy * dy)
            guard len >= 0.001 else { continue }
            let perpX = -dy / len, perpY = dx / len
            accumulatedVerts.append(StrokeVertex(x: px + perpX * halfW, y: py + perpY * halfW, r: r, g: g, b: b, a: ma))
            accumulatedVerts.append(StrokeVertex(x: px - perpX * halfW, y: py - perpY * halfW, r: r, g: g, b: b, a: ma))
            accumulatedVerts.append(StrokeVertex(x: nx + perpX * halfW, y: ny + perpY * halfW, r: r, g: g, b: b, a: ma))
            accumulatedVerts.append(StrokeVertex(x: px - perpX * halfW, y: py - perpY * halfW, r: r, g: g, b: b, a: ma))
            accumulatedVerts.append(StrokeVertex(x: nx + perpX * halfW, y: ny + perpY * halfW, r: r, g: g, b: b, a: ma))
            accumulatedVerts.append(StrokeVertex(x: nx - perpX * halfW, y: ny - perpY * halfW, r: r, g: g, b: b, a: ma))
        }
        
        // End cap
        let last = (pointCount - 1) * 5
        generateCircle(cx: points[last], cy: points[last + 1], radius: halfW, r: r, g: g, b: b, a: ma)
    }
                                   strokeWidth: Float) {
        guard pointCount >= 2 else { return }
        
        // Aligned with MarkerBrush.dart
        let widthMult: Float = 2.5
        let markerOpacity: Float = 0.7
        let halfW = strokeWidth * widthMult * 0.5
        let ma = a * markerOpacity
        
        for i in 0..<pointCount {
            let px = points[i * 5]
            let py = points[i * 5 + 1]
            
            // Round cap (matches Dart StrokeCap.round)
            generateCircle(cx: px, cy: py, radius: halfW, r: r, g: g, b: b, a: ma)
            
            if i < pointCount - 1 {
                let nx = points[(i + 1) * 5]
                let ny = points[(i + 1) * 5 + 1]
                
                let dx = nx - px
                let dy = ny - py
                let len = sqrt(dx * dx + dy * dy)
                guard len >= 0.001 else { continue }
                
                let perpX = -dy / len
                let perpY = dx / len
                
                // Constant width, constant alpha
                accumulatedVerts.append(StrokeVertex(x: px + perpX * halfW, y: py + perpY * halfW, r: r, g: g, b: b, a: ma))
                accumulatedVerts.append(StrokeVertex(x: px - perpX * halfW, y: py - perpY * halfW, r: r, g: g, b: b, a: ma))
                accumulatedVerts.append(StrokeVertex(x: nx + perpX * halfW, y: ny + perpY * halfW, r: r, g: g, b: b, a: ma))
                accumulatedVerts.append(StrokeVertex(x: px - perpX * halfW, y: py - perpY * halfW, r: r, g: g, b: b, a: ma))
                accumulatedVerts.append(StrokeVertex(x: nx + perpX * halfW, y: ny + perpY * halfW, r: r, g: g, b: b, a: ma))
                accumulatedVerts.append(StrokeVertex(x: nx - perpX * halfW, y: ny - perpY * halfW, r: r, g: g, b: b, a: ma))
            }
        }
    }
                                  strokeWidth: Float) {
        guard pointCount >= 2 else { return }
        
        // Thick marker: 2.5× wider than ballpoint, pressure-sensitive
        let markerWidthMult: Float = 2.5
        let baseHalfW = strokeWidth * markerWidthMult * 0.5
        
        for i in 0..<(pointCount - 1) {
            let px = points[i * 5]
            let py = points[i * 5 + 1]
            let pp = points[i * 5 + 2]  // pressure
            let nx = points[(i + 1) * 5]
            let ny = points[(i + 1) * 5 + 1]
            let np = points[(i + 1) * 5 + 2]  // next pressure
            
            // Pressure modulates width: 0.4× (light) to 1.0× (full)
            let halfW = baseHalfW * (0.4 + 0.6 * pp)
            let nHalfW = baseHalfW * (0.4 + 0.6 * np)
            
            let dx = nx - px
            let dy = ny - py
            let len = sqrt(dx * dx + dy * dy)
            guard len >= 0.001 else { continue }
            
            let perpX = -dy / len
            let perpY = dx / len
            
            // Two triangles forming a quad (flat caps, no circles)
            accumulatedVerts.append(StrokeVertex(x: px + perpX * halfW, y: py + perpY * halfW, r: r, g: g, b: b, a: a))
            accumulatedVerts.append(StrokeVertex(x: px - perpX * halfW, y: py - perpY * halfW, r: r, g: g, b: b, a: a))
            accumulatedVerts.append(StrokeVertex(x: nx + perpX * nHalfW, y: ny + perpY * nHalfW, r: r, g: g, b: b, a: a))
            accumulatedVerts.append(StrokeVertex(x: px - perpX * halfW, y: py - perpY * halfW, r: r, g: g, b: b, a: a))
            accumulatedVerts.append(StrokeVertex(x: nx + perpX * nHalfW, y: ny + perpY * nHalfW, r: r, g: g, b: b, a: a))
            accumulatedVerts.append(StrokeVertex(x: nx - perpX * nHalfW, y: ny - perpY * nHalfW, r: r, g: g, b: b, a: a))
        }
    }
    
    // ═══════════════════════════════════════════════════════════════
    // TESSELLATE PENCIL (ported from vk_stroke_renderer.cpp)
    // ═══════════════════════════════════════════════════════════════
    
    private func tessellatePencil(points: [Float], pointCount: Int,
                                  r: Float, g: Float, b: Float, a: Float,
                                  strokeWidth: Float,
                                  pointStartIndex: Int, totalPoints: Int) {
        guard pointCount >= 2 else { return }
        let minP: Float=0.5, maxP: Float=1.2, tPts=4, tStart: Float=0.15
        let bOp: Float=0.4, mOp: Float=0.8, gr: Float=0.08
        let twb: Float=0.5, tod: Float=0.15, vad: Float=0.10
        let bhw = strokeWidth * 0.5
        
        func gh(_ x: Float, _ y: Float) -> Float {
            var ix=Int(x*7.3), iy=Int(y*11.7)
            var h=(ix &* 374761393 &+ iy &* 668265263)^(ix &* 1274126177)
            h=(h^(h>>13)) &* 1103515245
            return Float(h&0x7FFFFFFF)/Float(0x7FFFFFFF)
        }
        
        // No EMA on GPU — applied only in Dart committed stroke
        
        var tp: Float=0; for i in 0..<pointCount { tp+=points[i*5+2] }
        let ua=a*(bOp+(mOp-bOp)*tp/Float(pointCount))
        
        struct OP { var lx:Float,ly:Float,rx:Float,ry:Float,a:Float }
        var ol=[OP](repeating:OP(lx:0,ly:0,rx:0,ry:0,a:0),count:pointCount)
        
        for i in 0..<pointCount {
            let px=points[i*5],py=points[i*5+1],pp=points[i*5+2],ptx=points[i*5+3],pty=points[i*5+4]
            let gi=pointStartIndex+i
            var hw=bhw*(minP+pp*(maxP-minP))
            let tm=min(sqrt(ptx*ptx+pty*pty),1.0)
            hw *= 1+tm*twb
            if gi<tPts { let t=Float(gi)/Float(tPts); hw *= tStart+t*(2-t)*(1-tStart) }
            let wr=(minP+pp*(maxP-minP))/maxP
            var pa=ua*(0.85+0.15*wr)
            pa *= 1-tm*tod
            if i>0 { let d1=points[i*5]-points[(i-1)*5],d2=points[i*5+1]-points[(i-1)*5+1]; pa *= 1-vad*min(sqrt(d1*d1+d2*d2)/30,1) }
            pa *= 1-gr+gr*gh(px,py); pa *= 0.92
            var tx:Float=0,ty:Float=0
            if i>0 { tx+=px-points[(i-1)*5]; ty+=py-points[(i-1)*5+1] }
            if i<pointCount-1 { tx+=points[(i+1)*5]-px; ty+=points[(i+1)*5+1]-py }
            var tl=sqrt(tx*tx+ty*ty); if tl<0.0001 { tx=1;ty=0;tl=1 }; tx/=tl; ty/=tl
            ol[i]=OP(lx:px+(-ty)*hw,ly:py+tx*hw,rx:px-(-ty)*hw,ry:py-tx*hw,a:pa)
        }
        for i in 0..<(pointCount-1) {
            let p=ol[i],n=ol[i+1]
            accumulatedVerts.append(StrokeVertex(x:p.lx,y:p.ly,r:r,g:g,b:b,a:p.a))
            accumulatedVerts.append(StrokeVertex(x:p.rx,y:p.ry,r:r,g:g,b:b,a:p.a))
            accumulatedVerts.append(StrokeVertex(x:n.lx,y:n.ly,r:r,g:g,b:b,a:n.a))
            accumulatedVerts.append(StrokeVertex(x:p.rx,y:p.ry,r:r,g:g,b:b,a:p.a))
            accumulatedVerts.append(StrokeVertex(x:n.lx,y:n.ly,r:r,g:g,b:b,a:n.a))
            accumulatedVerts.append(StrokeVertex(x:n.rx,y:n.ry,r:r,g:g,b:b,a:n.a))
        }
    }

                                  strokeWidth: Float,
                                  pointStartIndex: Int, totalPoints: Int) {
        guard pointCount >= 2 else { return }
        let minP: Float = 0.5, maxP: Float = 1.2
        let taperPts = 4; let taperStart: Float = 0.15
        let baseOp: Float = 0.4, maxOp: Float = 0.8
        let grain: Float = 0.08, tiltWB: Float = 0.5, tiltOD: Float = 0.15, velAD: Float = 0.10
        let baseHW = strokeWidth * 0.5
        
        func gh(_ x: Float, _ y: Float) -> Float {
            var ix = Int(x * 7.3); var iy = Int(y * 11.7)
            var h = (ix &* 374761393 &+ iy &* 668265263) ^ (ix &* 1274126177)
            h = (h ^ (h >> 13)) &* 1103515245
            return Float(h & 0x7FFFFFFF) / Float(0x7FFFFFFF)
        }
        
        var totalPressure: Float = 0
        for i in 0..<pointCount { totalPressure += points[i*5+2] }
        let uAlpha = a * (baseOp + (maxOp - baseOp) * totalPressure / Float(pointCount))
        
        struct OPt { var lx: Float; var ly: Float; var rx: Float; var ry: Float; var alpha: Float }
        var outline = [OPt](repeating: OPt(lx:0,ly:0,rx:0,ry:0,alpha:0), count: pointCount)
        
        for i in 0..<pointCount {
            let px = points[i*5], py = points[i*5+1], pp = points[i*5+2]
            let ptx = points[i*5+3], pty = points[i*5+4]
            let gi = pointStartIndex + i
            var hw = baseHW * (minP + pp * (maxP - minP))
            let tm = min(sqrt(ptx*ptx + pty*pty), 1.0)
            hw *= 1.0 + tm * tiltWB
            if gi < taperPts { let t = Float(gi)/Float(taperPts); let e = t*(2-t); hw *= taperStart + e*(1-taperStart) }
            let wr = (minP + pp*(maxP-minP))/maxP
            var pa = uAlpha * (0.85 + 0.15*wr)
            pa *= 1.0 - tm*tiltOD
            if i > 0 { let d1=px-points[(i-1)*5],d2=py-points[(i-1)*5+1]; pa *= 1.0-velAD*min(sqrt(d1*d1+d2*d2)/30,1) }
            pa *= 1.0 - grain + grain*gh(px,py)
            pa *= 0.92
            var tx: Float = 0, ty: Float = 0
            if i > 0 { tx += px-points[(i-1)*5]; ty += py-points[(i-1)*5+1] }
            if i < pointCount-1 { tx += points[(i+1)*5]-px; ty += points[(i+1)*5+1]-py }
            var tL = sqrt(tx*tx+ty*ty); if tL < 0.0001 { tx=1; ty=0; tL=1 }; tx /= tL; ty /= tL
            outline[i] = OPt(lx: px+(-ty)*hw, ly: py+tx*hw, rx: px-(-ty)*hw, ry: py-tx*hw, alpha: pa)
        }
        
        if pointStartIndex == 0 {
            let pp = points[2]; let hw = baseHW*(minP+pp*(maxP-minP))
            generateCircle(cx: points[0], cy: points[1], radius: hw, r: r, g: g, b: b, a: outline[0].alpha)
        }
        for i in 0..<(pointCount-1) {
            let p = outline[i], n = outline[i+1]
            accumulatedVerts.append(StrokeVertex(x:p.lx,y:p.ly,r:r,g:g,b:b,a:p.alpha))
            accumulatedVerts.append(StrokeVertex(x:p.rx,y:p.ry,r:r,g:g,b:b,a:p.alpha))
            accumulatedVerts.append(StrokeVertex(x:n.lx,y:n.ly,r:r,g:g,b:b,a:n.alpha))
            accumulatedVerts.append(StrokeVertex(x:p.rx,y:p.ry,r:r,g:g,b:b,a:p.alpha))
            accumulatedVerts.append(StrokeVertex(x:n.lx,y:n.ly,r:r,g:g,b:b,a:n.alpha))
            accumulatedVerts.append(StrokeVertex(x:n.rx,y:n.ry,r:r,g:g,b:b,a:n.alpha))
        }
        let last = pointCount-1; let pp = points[last*5+2]
        let hw = baseHW*(minP+pp*(maxP-minP))
        generateCircle(cx: points[last*5], cy: points[last*5+1], radius: hw, r:r,g:g,b:b,a:outline[last].alpha)
    }

                                  strokeWidth: Float,
                                  pointStartIndex: Int, totalPoints: Int) {
        guard pointCount >= 2 else { return }
        
        let minPressure: Float = 0.5
        let maxPressure: Float = 1.2
        let taperPoints = 4
        let taperStartFrac: Float = 0.15
        let baseOpacity: Float = 0.4
        let maxOpacityVal: Float = 0.8
        let grainIntensity: Float = 0.08
        let tiltWidthBoost: Float = 0.5
        let tiltOpacityDrop: Float = 0.15
        let velocityAlphaDrop: Float = 0.10
        let baseHalfW = strokeWidth * 0.5
        
        func grainHash(_ x: Float, _ y: Float) -> Float {
            var ix = Int(x * 7.3)
            var iy = Int(y * 11.7)
            var h = (ix &* 374761393 &+ iy &* 668265263) ^ (ix &* 1274126177)
            h = (h ^ (h >> 13)) &* 1103515245
            return Float(h & 0x7FFFFFFF) / Float(0x7FFFFFFF)
        }
        
        var totalPressure: Float = 0.0
        for i in 0..<pointCount { totalPressure += points[i * 5 + 2] }
        let avgPressure = totalPressure / Float(pointCount)
        let uniformAlpha = a * (baseOpacity + (maxOpacityVal - baseOpacity) * avgPressure)
        
        func computeHalfW(_ i: Int) -> Float {
            let pp = points[i * 5 + 2]
            let ptx = points[i * 5 + 3], pty = points[i * 5 + 4]
            let globalIdx = pointStartIndex + i
            var hw = baseHalfW * (minPressure + pp * (maxPressure - minPressure))
            let tiltMag = min(sqrt(ptx * ptx + pty * pty), 1.0)
            hw *= 1.0 + tiltMag * tiltWidthBoost
            if globalIdx < taperPoints {
                let t = Float(globalIdx) / Float(taperPoints)
                let ease = t * (2.0 - t)
                hw *= taperStartFrac + ease * (1.0 - taperStartFrac)
            }
            return hw
        }
        
        func computeAlpha(_ i: Int, _ vel: Float) -> Float {
            let pp = points[i * 5 + 2]
            let ptx = points[i * 5 + 3], pty = points[i * 5 + 4]
            let tiltMag = min(sqrt(ptx * ptx + pty * pty), 1.0)
            let widthRatio = (minPressure + pp * (maxPressure - minPressure)) / maxPressure
            var pa = uniformAlpha * (0.85 + 0.15 * widthRatio)
            pa *= 1.0 - tiltMag * tiltOpacityDrop
            pa *= 1.0 - velocityAlphaDrop * min(vel / 30.0, 1.0)
            let px = points[i * 5], py = points[i * 5 + 1]
            pa *= 1.0 - grainIntensity + grainIntensity * grainHash(px, py)
            pa *= 0.92
            return pa
        }
        
        // Start cap only
        if pointStartIndex == 0 {
            let hw0 = computeHalfW(0)
            let pa0 = computeAlpha(0, 0.0)
            generateCircle(cx: points[0], cy: points[1], radius: hw0, r: r, g: g, b: b, a: pa0)
        }
        
        // Body quads (NO per-point circles)
        for i in 0..<(pointCount - 1) {
            let px = points[i * 5], py = points[i * 5 + 1]
            let nx = points[(i + 1) * 5], ny = points[(i + 1) * 5 + 1]
            let dx = nx - px, dy = ny - py
            let len = sqrt(dx * dx + dy * dy)
            guard len >= 0.001 else { continue }
            
            let halfW = computeHalfW(i)
            let vel: Float = i > 0 ? len : 0.0
            let pa = computeAlpha(i, vel)
            let nHalfW = computeHalfW(i + 1)
            let na = computeAlpha(i + 1, len)
            
            let perpX = -dy / len, perpY = dx / len
            accumulatedVerts.append(StrokeVertex(x: px + perpX * halfW, y: py + perpY * halfW, r: r, g: g, b: b, a: pa))
            accumulatedVerts.append(StrokeVertex(x: px - perpX * halfW, y: py - perpY * halfW, r: r, g: g, b: b, a: pa))
            accumulatedVerts.append(StrokeVertex(x: nx + perpX * nHalfW, y: ny + perpY * nHalfW, r: r, g: g, b: b, a: na))
            accumulatedVerts.append(StrokeVertex(x: px - perpX * halfW, y: py - perpY * halfW, r: r, g: g, b: b, a: pa))
            accumulatedVerts.append(StrokeVertex(x: nx + perpX * nHalfW, y: ny + perpY * nHalfW, r: r, g: g, b: b, a: na))
            accumulatedVerts.append(StrokeVertex(x: nx - perpX * nHalfW, y: ny - perpY * nHalfW, r: r, g: g, b: b, a: na))
        }
        
        // End cap
        let last = pointCount - 1
        let hwLast = computeHalfW(last)
        var velLast: Float = 0.0
        if last > 0 {
            let dx = points[last*5] - points[(last-1)*5]
            let dy = points[last*5+1] - points[(last-1)*5+1]
            velLast = sqrt(dx*dx + dy*dy)
        }
        let paLast = computeAlpha(last, velLast)
        generateCircle(cx: points[last*5], cy: points[last*5+1], radius: hwLast, r: r, g: g, b: b, a: paLast)
    }

                                  strokeWidth: Float,
                                  pointStartIndex: Int, totalPoints: Int) {
        guard pointCount >= 2 else { return }
        
        // Aligned with PencilBrush.dart
        let minPressure: Float = 0.5
        let maxPressure: Float = 1.2
        let taperPoints = 4
        let taperStartFrac: Float = 0.15
        let baseOpacity: Float = 0.4
        let maxOpacity: Float = 0.8
        let grainIntensity: Float = 0.08
        let tiltWidthBoost: Float = 0.5
        let tiltOpacityDrop: Float = 0.15
        let velocityAlphaDrop: Float = 0.10
        let baseHalfW = strokeWidth * 0.5
        
        func grainHash(_ x: Float, _ y: Float) -> Float {
            var ix = Int(x * 7.3)
            var iy = Int(y * 11.7)
            var h = (ix &* 374761393 &+ iy &* 668265263) ^ (ix &* 1274126177)
            h = (h ^ (h >> 13)) &* 1103515245
            return Float(h & 0x7FFFFFFF) / Float(0x7FFFFFFF)
        }
        
        // Average pressure for uniform alpha (like Dart)
        var totalPressure: Float = 0.0
        for i in 0..<pointCount { totalPressure += points[i * 5 + 2] }
        let avgPressure = totalPressure / Float(pointCount)
        let uniformAlpha = a * (baseOpacity + (maxOpacity - baseOpacity) * avgPressure)
        
        for i in 0..<pointCount {
            let px = points[i * 5]
            let py = points[i * 5 + 1]
            let pp = points[i * 5 + 2]
            let ptx = points[i * 5 + 3]
            let pty = points[i * 5 + 4]
            let globalIdx = pointStartIndex + i
            
            var halfW = baseHalfW * (minPressure + pp * (maxPressure - minPressure))
            let tiltMag = min(sqrt(ptx * ptx + pty * pty), 1.0)
            halfW *= 1.0 + tiltMag * tiltWidthBoost
            
            // Taper: 4pt easeOutQuad from 0.15
            if globalIdx < taperPoints {
                let t = Float(globalIdx) / Float(taperPoints)
                let ease = t * (2.0 - t)
                halfW *= taperStartFrac + ease * (1.0 - taperStartFrac)
            }
            
            let widthRatio = (minPressure + pp * (maxPressure - minPressure)) / maxPressure
            var pa = uniformAlpha * (0.85 + 0.15 * widthRatio)
            pa *= 1.0 - tiltMag * tiltOpacityDrop
            if i > 0 {
                let dx = px - points[(i - 1) * 5]
                let dy = py - points[(i - 1) * 5 + 1]
                let vel = sqrt(dx * dx + dy * dy)
                pa *= 1.0 - velocityAlphaDrop * min(vel / 30.0, 1.0)
            }
            pa *= 1.0 - grainIntensity + grainIntensity * grainHash(px, py)
            pa *= 0.92
            
            generateCircle(cx: px, cy: py, radius: halfW, r: r, g: g, b: b, a: pa)
            
            if i < pointCount - 1 {
                let nx = points[(i + 1) * 5]
                let ny = points[(i + 1) * 5 + 1]
                let np = points[(i + 1) * 5 + 2]
                let ntx = points[(i + 1) * 5 + 3]
                let nty = points[(i + 1) * 5 + 4]
                
                let dx = nx - px
                let dy = ny - py
                let len = sqrt(dx * dx + dy * dy)
                guard len >= 0.001 else { continue }
                
                let nextGlobal = globalIdx + 1
                let nTilt = min(sqrt(ntx * ntx + nty * nty), 1.0)
                var nHalfW = baseHalfW * (minPressure + np * (maxPressure - minPressure))
                nHalfW *= 1.0 + nTilt * tiltWidthBoost
                if nextGlobal < taperPoints {
                    let t = Float(nextGlobal) / Float(taperPoints)
                    let ease = t * (2.0 - t)
                    nHalfW *= taperStartFrac + ease * (1.0 - taperStartFrac)
                }
                
                let nWidthRatio = (minPressure + np * (maxPressure - minPressure)) / maxPressure
                var na = uniformAlpha * (0.85 + 0.15 * nWidthRatio)
                na *= 1.0 - nTilt * tiltOpacityDrop
                na *= 1.0 - velocityAlphaDrop * min(len / 30.0, 1.0)
                na *= 1.0 - grainIntensity + grainIntensity * grainHash(nx, ny)
                na *= 0.92
                
                let perpX = -dy / len
                let perpY = dx / len
                
                accumulatedVerts.append(StrokeVertex(x: px + perpX * halfW, y: py + perpY * halfW, r: r, g: g, b: b, a: pa))
                accumulatedVerts.append(StrokeVertex(x: px - perpX * halfW, y: py - perpY * halfW, r: r, g: g, b: b, a: pa))
                accumulatedVerts.append(StrokeVertex(x: nx + perpX * nHalfW, y: ny + perpY * nHalfW, r: r, g: g, b: b, a: na))
                accumulatedVerts.append(StrokeVertex(x: px - perpX * halfW, y: py - perpY * halfW, r: r, g: g, b: b, a: pa))
                accumulatedVerts.append(StrokeVertex(x: nx + perpX * nHalfW, y: ny + perpY * nHalfW, r: r, g: g, b: b, a: na))
                accumulatedVerts.append(StrokeVertex(x: nx - perpX * nHalfW, y: ny - perpY * nHalfW, r: r, g: g, b: b, a: na))
            }
        }
    }
                                  strokeWidth: Float,
                                  pointStartIndex: Int, totalPoints: Int) {
        guard pointCount >= 2 else { return }
        
        let widthFactor: Float = 1.2
        let taperPoints = 3
        let taperStartFrac: Float = 0.40
        let grainIntensity: Float = 0.25
        let tiltWidthBoost: Float = 2.0
        let tiltOpacityDrop: Float = 0.5
        let velocityMaxDist: Float = 30.0
        let baseHalfW = strokeWidth * widthFactor * 0.5
        
        func grainHash(_ x: Float, _ y: Float) -> Float {
            var ix = Int(x * 7.3)
            var iy = Int(y * 11.7)
            var h = (ix &* 374761393 &+ iy &* 668265263) ^ (ix &* 1274126177)
            h = (h ^ (h >> 13)) &* 1103515245
            return Float(h & 0x7FFFFFFF) / Float(0x7FFFFFFF)
        }
        
        for i in 0..<pointCount {
            let px = points[i * 5]
            let py = points[i * 5 + 1]
            let pp = points[i * 5 + 2]
            let ptx = points[i * 5 + 3]
            let pty = points[i * 5 + 4]
            let globalIdx = pointStartIndex + i
            
            var halfW = baseHalfW * (0.5 + 0.7 * pp)
            let tiltMag = min(sqrt(ptx * ptx + pty * pty), 1.0)
            halfW *= 1.0 + tiltMag * tiltWidthBoost
            
            if globalIdx < taperPoints {
                let t = Float(globalIdx + 1) / Float(taperPoints)
                let ease: Float = 1.0 - (1.0 - t) * (1.0 - t) * (1.0 - t)
                halfW *= taperStartFrac + (1.0 - taperStartFrac) * ease
            }
            
            var velocity: Float = 0.0
            if i > 0 {
                let dx = px - points[(i - 1) * 5]
                let dy = py - points[(i - 1) * 5 + 1]
                velocity = sqrt(dx * dx + dy * dy)
            }
            let velAlpha: Float = 1.0 - 0.30 * min(velocity / velocityMaxDist, 1.0)
            
            var pa = a * (0.30 + 0.60 * pp)
            pa *= 1.0 - tiltMag * tiltOpacityDrop
            pa *= velAlpha
            pa *= 1.0 - grainIntensity + grainIntensity * grainHash(px, py)
            
            generateCircle(cx: px, cy: py, radius: halfW, r: r, g: g, b: b, a: pa)
            
            if i < pointCount - 1 {
                let nx = points[(i + 1) * 5]
                let ny = points[(i + 1) * 5 + 1]
                let np = points[(i + 1) * 5 + 2]
                let ntx = points[(i + 1) * 5 + 3]
                let nty = points[(i + 1) * 5 + 4]
                
                let dx = nx - px
                let dy = ny - py
                let len = sqrt(dx * dx + dy * dy)
                guard len >= 0.001 else { continue }
                
                let nextGlobal = globalIdx + 1
                let nTilt = min(sqrt(ntx * ntx + nty * nty), 1.0)
                var nHalfW = baseHalfW * (0.5 + 0.7 * np)
                nHalfW *= 1.0 + nTilt * tiltWidthBoost
                if nextGlobal < taperPoints {
                    let t = Float(nextGlobal + 1) / Float(taperPoints)
                    let ease: Float = 1.0 - (1.0 - t) * (1.0 - t) * (1.0 - t)
                    nHalfW *= taperStartFrac + (1.0 - taperStartFrac) * ease
                }
                
                let nVelAlpha: Float = 1.0 - 0.30 * min(len / velocityMaxDist, 1.0)
                var na = a * (0.30 + 0.60 * np)
                na *= 1.0 - nTilt * tiltOpacityDrop
                na *= nVelAlpha
                na *= 1.0 - grainIntensity + grainIntensity * grainHash(nx, ny)
                
                let perpX = -dy / len
                let perpY = dx / len
                
                accumulatedVerts.append(StrokeVertex(x: px + perpX * halfW, y: py + perpY * halfW, r: r, g: g, b: b, a: pa))
                accumulatedVerts.append(StrokeVertex(x: px - perpX * halfW, y: py - perpY * halfW, r: r, g: g, b: b, a: pa))
                accumulatedVerts.append(StrokeVertex(x: nx + perpX * nHalfW, y: ny + perpY * nHalfW, r: r, g: g, b: b, a: na))
                accumulatedVerts.append(StrokeVertex(x: px - perpX * halfW, y: py - perpY * halfW, r: r, g: g, b: b, a: pa))
                accumulatedVerts.append(StrokeVertex(x: nx + perpX * nHalfW, y: ny + perpY * nHalfW, r: r, g: g, b: b, a: na))
                accumulatedVerts.append(StrokeVertex(x: nx - perpX * nHalfW, y: ny - perpY * nHalfW, r: r, g: g, b: b, a: na))
            }
        }
    }
                                  strokeWidth: Float,
                                  pointStartIndex: Int, totalPoints: Int) {
        guard pointCount >= 2 else { return }
        
        let widthFactor: Float = 1.2
        let taperPoints = 3
        let taperStartFrac: Float = 0.40
        let baseHalfW = strokeWidth * widthFactor * 0.5
        
        for i in 0..<pointCount {
            let px = points[i * 5]
            let py = points[i * 5 + 1]
            let pp = points[i * 5 + 2]  // pressure
            let globalIdx = pointStartIndex + i
            
            // Pressure → width: 0.5× (light) to 1.2× (full)
            var halfW = baseHalfW * (0.5 + 0.7 * pp)
            
            // Entry taper
            if globalIdx < taperPoints {
                let t = Float(globalIdx + 1) / Float(taperPoints)
                let ease: Float = 1.0 - (1.0 - t) * (1.0 - t) * (1.0 - t)
                halfW *= taperStartFrac + (1.0 - taperStartFrac) * ease
            }
            
            // Pressure → opacity: 0.30 (light) to 0.90 (full)
            let pa = a * (0.30 + 0.60 * pp)
            
            // Round cap
            generateCircle(cx: px, cy: py, radius: halfW, r: r, g: g, b: b, a: pa)
            
            // Segment quad
            if i < pointCount - 1 {
                let nx = points[(i + 1) * 5]
                let ny = points[(i + 1) * 5 + 1]
                let np = points[(i + 1) * 5 + 2]
                
                let dx = nx - px
                let dy = ny - py
                let len = sqrt(dx * dx + dy * dy)
                guard len >= 0.001 else { continue }
                
                let nextGlobal = globalIdx + 1
                var nHalfW = baseHalfW * (0.5 + 0.7 * np)
                if nextGlobal < taperPoints {
                    let t = Float(nextGlobal + 1) / Float(taperPoints)
                    let ease: Float = 1.0 - (1.0 - t) * (1.0 - t) * (1.0 - t)
                    nHalfW *= taperStartFrac + (1.0 - taperStartFrac) * ease
                }
                let na = a * (0.30 + 0.60 * np)
                
                let perpX = -dy / len
                let perpY = dx / len
                
                accumulatedVerts.append(StrokeVertex(x: px + perpX * halfW, y: py + perpY * halfW, r: r, g: g, b: b, a: pa))
                accumulatedVerts.append(StrokeVertex(x: px - perpX * halfW, y: py - perpY * halfW, r: r, g: g, b: b, a: pa))
                accumulatedVerts.append(StrokeVertex(x: nx + perpX * nHalfW, y: ny + perpY * nHalfW, r: r, g: g, b: b, a: na))
                accumulatedVerts.append(StrokeVertex(x: px - perpX * halfW, y: py - perpY * halfW, r: r, g: g, b: b, a: pa))
                accumulatedVerts.append(StrokeVertex(x: nx + perpX * nHalfW, y: ny + perpY * nHalfW, r: r, g: g, b: b, a: na))
                accumulatedVerts.append(StrokeVertex(x: nx - perpX * nHalfW, y: ny - perpY * nHalfW, r: r, g: g, b: b, a: na))
            }
        }
    }
}
