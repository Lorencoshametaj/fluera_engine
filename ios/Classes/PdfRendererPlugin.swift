// PdfRendererPlugin.swift — Native iOS PDF Rendering via PDFKit
//
// Provides direct access to Apple's PDFKit for:
// - Loading PDF documents from raw bytes (multi-document support)
// - Rendering pages as raw RGBA pixel buffers (legacy path)
// - Rendering pages via FlutterTextureRegistry for zero-copy GPU sharing (fast path)
// - Fast thumbnail rendering via PDFPage.thumbnail(of:for:)
// - Extracting text geometry for selection
//
// Channel: com.flueraengine/pdf_renderer

import Flutter
import UIKit
import PDFKit
import Vision
import CoreVideo

/// 📄 PdfRendererPlugin — Native iOS PDF Rendering via PDFKit + FlutterTextureRegistry
public class PdfRendererPlugin: NSObject, FlutterPlugin {
    
    private var methodChannel: FlutterMethodChannel?
    
    /// Multi-document storage keyed by documentId.
    private var documents: [String: PDFDocument] = [:]
    
    // =========================================================================
    // TextureRegistry — Zero-copy GPU texture sharing
    // =========================================================================
    
    private var textureRegistry: FlutterTextureRegistry?
    
    /// Pool of texture entries, keyed by "WxH".
    private var texturePool: [String: PdfTextureEntry] = [:]
    
    /// Maximum texture pool size to avoid exhausting GPU memory.
    private let maxTexturePool = 8
    
    // MARK: - Plugin Registration
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = PdfRendererPlugin()
        
        let methodChannel = FlutterMethodChannel(
            name: "com.flueraengine/pdf_renderer",
            binaryMessenger: registrar.messenger()
        )
        instance.methodChannel = methodChannel
        instance.textureRegistry = registrar.textures()
        registrar.addMethodCallDelegate(instance, channel: methodChannel)
    }
    
    // MARK: - Method Channel Handler
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "loadDocument":
            handleLoadDocument(call, result: result)
        case "getPageSize":
            handleGetPageSize(call, result: result)
        case "renderPage":
            handleRenderPage(call, result: result)
        case "renderPageTexture":
            handleRenderPageTexture(call, result: result)
        case "renderThumbnail":
            handleRenderThumbnail(call, result: result)
        case "releaseTexture":
            handleReleaseTexture(call, result: result)
        case "extractText":
            handleExtractText(call, result: result)
        case "getPageText":
            handleGetPageText(call, result: result)
        case "ocrPage":
            handleOcrPage(call, result: result)
        case "dispose":
            handleDispose(call, result: result)
        case "disposeAll":
            handleDisposeAll(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    // MARK: - Load Document
    
    private func handleLoadDocument(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let flutterData = args["bytes"] as? FlutterStandardTypedData,
              let documentId = args["documentId"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing 'bytes' or 'documentId'", details: nil))
            return
        }
        
        let data = flutterData.data
        guard let document = PDFDocument(data: data) else {
            result(["pageCount": 0, "success": false])
            return
        }
        
        // Remove previous document with same ID if present
        documents[documentId] = document
        
        // Pre-compute all page sizes for Dart-side cache
        var pageSizes: [[String: Double]] = []
        for i in 0..<document.pageCount {
            if let page = document.page(at: i) {
                let bounds = page.bounds(for: .mediaBox)
                pageSizes.append([
                    "width": Double(bounds.width),
                    "height": Double(bounds.height)
                ])
            } else {
                pageSizes.append(["width": 0.0, "height": 0.0])
            }
        }
        
        result([
            "pageCount": document.pageCount,
            "success": true,
            "pageSizes": pageSizes
        ])
    }
    
    // MARK: - Page Size
    
    private func handleGetPageSize(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let documentId = args["documentId"] as? String,
              let pageIndex = args["pageIndex"] as? Int else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing arguments", details: nil))
            return
        }
        
        guard let document = documents[documentId],
              pageIndex >= 0 && pageIndex < document.pageCount,
              let page = document.page(at: pageIndex) else {
            result(["width": 0.0, "height": 0.0])
            return
        }
        
        let bounds = page.bounds(for: .mediaBox)
        result([
            "width": Double(bounds.width),
            "height": Double(bounds.height)
        ])
    }
    
    // MARK: - Render Page (raw RGBA pixels) — legacy path
    
    private func handleRenderPage(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let documentId = args["documentId"] as? String,
              let pageIndex = args["pageIndex"] as? Int,
              let targetWidth = args["targetWidth"] as? Int,
              let targetHeight = args["targetHeight"] as? Int else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing arguments", details: nil))
            return
        }
        
        guard let document = documents[documentId],
              pageIndex >= 0 && pageIndex < document.pageCount,
              let page = document.page(at: pageIndex) else {
            result(nil)
            return
        }
        
        // Render on background queue to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async {
            let width = max(1, targetWidth)
            let height = max(1, targetHeight)
            
            // Create RGBA bitmap context
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            // Use noneSkipLast (opaque) — PDFs are fully opaque,
            // avoids premultiplied alpha darkening artifacts.
            let bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            
            guard let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else {
                DispatchQueue.main.async { result(nil) }
                return
            }
            
            // White background
            context.setFillColor(UIColor.white.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            
            // Scale to fit target size
            let pageBounds = page.bounds(for: .mediaBox)
            let scaleX = CGFloat(width) / pageBounds.width
            let scaleY = CGFloat(height) / pageBounds.height
            
            context.saveGState()
            context.scaleBy(x: scaleX, y: scaleY)
            
            // Draw the PDF page
            if let cgPage = page.pageRef {
                context.drawPDFPage(cgPage)
            }
            context.restoreGState()
            
            // Extract raw pixel data
            guard let data = context.data else {
                DispatchQueue.main.async { result(nil) }
                return
            }
            
            let byteCount = width * height * 4
            let pixelData = Data(bytes: data, count: byteCount)
            
            DispatchQueue.main.async {
                result([
                    "width": width,
                    "height": height,
                    "pixels": FlutterStandardTypedData(bytes: pixelData)
                ])
            }
        }
    }
    
    // MARK: - Render Page via TextureRegistry — ZERO-COPY fast path
    
    /// 🚀 Zero-copy PDF page rendering via FlutterTextureRegistry.
    ///
    /// Flow:
    /// 1. Create/reuse a CVPixelBuffer at target dimensions
    /// 2. Create a CGContext backed by the pixel buffer
    /// 3. Draw the PDF page into it
    /// 4. Register with FlutterTextureRegistry → textureFrameAvailable()
    /// 5. Return textureId — Metal composites the CVPixelBuffer directly, zero copy
    private func handleRenderPageTexture(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let documentId = args["documentId"] as? String,
              let pageIndex = args["pageIndex"] as? Int,
              let targetWidth = args["targetWidth"] as? Int,
              let targetHeight = args["targetHeight"] as? Int else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing arguments", details: nil))
            return
        }
        
        guard let document = documents[documentId],
              pageIndex >= 0 && pageIndex < document.pageCount,
              let page = document.page(at: pageIndex),
              let registry = textureRegistry else {
            result(nil)
            return
        }
        
        let width = max(1, targetWidth)
        let height = max(1, targetHeight)
        
        // Render on background queue
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { result(nil) }
                return
            }
            
            // Step 1: Get or create texture entry with CVPixelBuffer
            let key = "\(width)x\(height)"
            let texEntry: PdfTextureEntry
            
            if let existing = self.texturePool[key] {
                texEntry = existing
            } else {
                // Create new CVPixelBuffer
                guard let newEntry = PdfTextureEntry(width: width, height: height, registry: registry) else {
                    DispatchQueue.main.async { result(nil) }
                    return
                }
                
                // Evict oldest if pool is full
                if self.texturePool.count >= self.maxTexturePool {
                    if let oldestKey = self.texturePool.keys.first {
                        self.texturePool[oldestKey]?.release(registry: registry)
                        self.texturePool.removeValue(forKey: oldestKey)
                    }
                }
                
                self.texturePool[key] = newEntry
                texEntry = newEntry
            }
            
            // Step 2: Draw PDF page into the CVPixelBuffer
            guard let pixelBuffer = texEntry.pixelBuffer else {
                DispatchQueue.main.async { result(nil) }
                return
            }
            
            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
            
            guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
                DispatchQueue.main.async { result(nil) }
                return
            }
            
            let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            
            guard let context = CGContext(
                data: baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else {
                DispatchQueue.main.async { result(nil) }
                return
            }
            
            // White background
            context.setFillColor(UIColor.white.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            
            // Scale and draw PDF page
            let pageBounds = page.bounds(for: .mediaBox)
            let scaleX = CGFloat(width) / pageBounds.width
            let scaleY = CGFloat(height) / pageBounds.height
            
            context.saveGState()
            context.scaleBy(x: scaleX, y: scaleY)
            if let cgPage = page.pageRef {
                context.drawPDFPage(cgPage)
            }
            context.restoreGState()
            
            // Step 3: Notify Flutter and return texture ID
            DispatchQueue.main.async {
                registry.textureFrameAvailable(texEntry.textureId)
                result([
                    "textureId": texEntry.textureId,
                    "width": width,
                    "height": height
                ] as [String: Any])
            }
        }
    }
    
    // MARK: - Render Thumbnail — fast low-res preview
    
    /// 🖼️ Render a low-resolution thumbnail using PDFPage.thumbnail(of:for:)
    /// Apple's optimized API — ~10x faster than full render.
    private func handleRenderThumbnail(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let documentId = args["documentId"] as? String,
              let pageIndex = args["pageIndex"] as? Int else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing arguments", details: nil))
            return
        }
        
        guard let document = documents[documentId],
              pageIndex >= 0 && pageIndex < document.pageCount,
              let page = document.page(at: pageIndex) else {
            result(nil)
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let pageBounds = page.bounds(for: .mediaBox)
            
            // Fixed thumbnail width, preserve aspect ratio
            let thumbWidth: CGFloat = 200
            let thumbHeight = (thumbWidth * pageBounds.height / max(1, pageBounds.width)).clamped(to: 1...400)
            let thumbSize = CGSize(width: thumbWidth, height: thumbHeight)
            
            // Use Apple's optimized thumbnail API
            let thumbnail = page.thumbnail(of: thumbSize, for: .mediaBox)
            
            // Convert UIImage to raw RGBA bytes
            let width = Int(thumbnail.size.width * thumbnail.scale)
            let height = Int(thumbnail.size.height * thumbnail.scale)
            
            guard width > 0, height > 0 else {
                DispatchQueue.main.async { result(nil) }
                return
            }
            
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            
            guard let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else {
                DispatchQueue.main.async { result(nil) }
                return
            }
            
            // White background
            context.setFillColor(UIColor.white.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            
            // Draw thumbnail
            if let cgImage = thumbnail.cgImage {
                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            }
            
            guard let data = context.data else {
                DispatchQueue.main.async { result(nil) }
                return
            }
            
            let byteCount = width * height * 4
            let pixelData = Data(bytes: data, count: byteCount)
            
            DispatchQueue.main.async {
                result([
                    "width": width,
                    "height": height,
                    "pixels": FlutterStandardTypedData(bytes: pixelData)
                ] as [String : Any])
            }
        }
    }
    
    // MARK: - Texture Management
    
    private func handleReleaseTexture(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let textureId = args["textureId"] as? Int64,
              let registry = textureRegistry else {
            result(nil)
            return
        }
        
        if let entry = texturePool.first(where: { $0.value.textureId == textureId }) {
            entry.value.release(registry: registry)
            texturePool.removeValue(forKey: entry.key)
        }
        result(nil)
    }
    
    private func releaseAllTextures() {
        guard let registry = textureRegistry else { return }
        for entry in texturePool.values {
            entry.release(registry: registry)
        }
        texturePool.removeAll()
    }
    
    // MARK: - Extract Text Geometry
    
    private func handleExtractText(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let documentId = args["documentId"] as? String,
              let pageIndex = args["pageIndex"] as? Int else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing arguments", details: nil))
            return
        }
        
        guard let document = documents[documentId],
              pageIndex >= 0 && pageIndex < document.pageCount,
              let page = document.page(at: pageIndex) else {
            result([])
            return
        }
        
        // Move to background queue — text extraction can be slow on dense pages
        DispatchQueue.global(qos: .userInitiated).async {
            let pageBounds = page.bounds(for: .mediaBox)
            
            guard let pageText = page.string, !pageText.isEmpty else {
                DispatchQueue.main.async { result([]) }
                return
            }
            
            var textRects: [[String: Any]] = []
            textRects.reserveCapacity(pageText.count)
            
            // Word-level batch extraction → split into chars.
            // Using word ranges avoids O(n²) per-character PDFSelection creation.
            let nsText = pageText as NSString
            var wordStart = 0
            
            while wordStart < nsText.length {
                let wordRange = nsText.rangeOfComposedCharacterSequences(
                    for: NSRange(location: wordStart, length: min(64, nsText.length - wordStart))
                )
                
                if let selection = page.selection(for: wordRange) {
                    // Split word selection into individual chars
                    for offset in 0..<wordRange.length {
                        let charIdx = wordRange.location + offset
                        let charRange = NSRange(location: charIdx, length: 1)
                        if let charSelection = page.selection(for: charRange) {
                            let bounds = charSelection.bounds(for: page)
                            let flippedY = pageBounds.height - bounds.origin.y - bounds.height
                            
                            let char = nsText.substring(with: charRange)
                            
                            textRects.append([
                                "x": Double(bounds.origin.x),
                                "y": Double(flippedY),
                                "width": Double(bounds.width),
                                "height": Double(bounds.height),
                                "text": char,
                                "charOffset": charIdx
                            ])
                        }
                    }
                }
                
                wordStart += wordRange.length
                if wordRange.length == 0 { wordStart += 1 } // Safety: avoid infinite loop
            }
            
            DispatchQueue.main.async {
                result(textRects)
            }
        }
    }
    
    // MARK: - Get Page Text
    
    private func handleGetPageText(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let documentId = args["documentId"] as? String,
              let pageIndex = args["pageIndex"] as? Int else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing arguments", details: nil))
            return
        }
        
        guard let document = documents[documentId],
              pageIndex >= 0 && pageIndex < document.pageCount,
              let page = document.page(at: pageIndex) else {
            result("")
            return
        }
        
        result(page.string ?? "")
    }
    
    // MARK: - Dispose
    
    private func handleDispose(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let documentId = args["documentId"] as? String else {
            result(nil)
            return
        }
        documents.removeValue(forKey: documentId)
        result(nil)
    }
    
    private func handleDisposeAll(result: @escaping FlutterResult) {
        documents.removeAll()
        releaseAllTextures()
        result(nil)
    }
    
    // MARK: - OCR — Vision Framework Text Recognition for scanned PDFs
    
    private func handleOcrPage(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let documentId = args["documentId"] as? String,
              let pageIndex = args["pageIndex"] as? Int else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing arguments", details: nil))
            return
        }
        
        guard let document = documents[documentId],
              pageIndex >= 0 && pageIndex < document.pageCount,
              let page = document.page(at: pageIndex) else {
            result(nil)
            return
        }
        
        // Render page to CGImage on background queue, then run Vision OCR
        DispatchQueue.global(qos: .userInitiated).async {
            let pageBounds = page.bounds(for: .mediaBox)
            
            // Render at reasonable resolution for OCR (~1200px wide)
            let scale = 1200.0 / max(pageBounds.width, 1.0)
            let width = Int(pageBounds.width * scale)
            let height = Int(pageBounds.height * scale)
            
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            
            guard let context = CGContext(
                data: nil,
                width: max(1, width),
                height: max(1, height),
                bitsPerComponent: 8,
                bytesPerRow: max(1, width) * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else {
                DispatchQueue.main.async { result(nil) }
                return
            }
            
            // White background
            context.setFillColor(UIColor.white.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            
            // Scale and draw PDF page
            let scaleX = CGFloat(width) / pageBounds.width
            let scaleY = CGFloat(height) / pageBounds.height
            context.saveGState()
            context.scaleBy(x: scaleX, y: scaleY)
            if let cgPage = page.pageRef {
                context.drawPDFPage(cgPage)
            }
            context.restoreGState()
            
            guard let cgImage = context.makeImage() else {
                DispatchQueue.main.async { result(nil) }
                return
            }
            
            // Run Vision text recognition
            let request = VNRecognizeTextRequest { (request, error) in
                guard error == nil,
                      let observations = request.results as? [VNRecognizedTextObservation] else {
                    DispatchQueue.main.async { result(nil) }
                    return
                }
                
                var blocks: [[String: Any]] = []
                var fullTextParts: [String] = []
                
                for observation in observations {
                    guard let topCandidate = observation.topCandidates(1).first else { continue }
                    let text = topCandidate.string
                    let boundingBox = observation.boundingBox
                    
                    fullTextParts.append(text)
                    
                    // Vision coordinates: origin bottom-left, normalized 0–1.
                    // Flip Y to top-left origin for consistency.
                    blocks.append([
                        "text": text,
                        "x": Double(boundingBox.origin.x),
                        "y": Double(1.0 - boundingBox.origin.y - boundingBox.height),
                        "width": Double(boundingBox.width),
                        "height": Double(boundingBox.height),
                        "confidence": Double(observation.confidence)
                    ])
                }
                
                let response: [String: Any] = [
                    "text": fullTextParts.joined(separator: "\n"),
                    "blocks": blocks
                ]
                
                DispatchQueue.main.async {
                    result(response)
                }
            }
            
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                DispatchQueue.main.async { result(nil) }
            }
        }
    }
}

// =============================================================================
// PdfTextureEntry — CVPixelBuffer-backed Flutter texture
// =============================================================================

/// Wraps a CVPixelBuffer + Flutter texture registration for zero-copy PDF rendering.
class PdfTextureEntry: NSObject, FlutterTexture {
    private(set) var textureId: Int64 = -1
    private(set) var pixelBuffer: CVPixelBuffer?
    
    init?(width: Int, height: Int, registry: FlutterTextureRegistry) {
        // Create CVPixelBuffer with Metal compatibility for zero-copy GPU sharing
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        
        var pb: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pb
        )
        
        guard status == kCVReturnSuccess, let pixelBuffer = pb else {
            return nil
        }
        
        self.pixelBuffer = pixelBuffer
        super.init()
        
        // Register with Flutter — self is now fully initialized
        self.textureId = registry.register(self)
    }
    
    // MARK: - FlutterTexture protocol
    
    public func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        guard let pb = pixelBuffer else { return nil }
        return Unmanaged.passRetained(pb)
    }
    
    /// Release the texture and unregister from Flutter.
    func release(registry: FlutterTextureRegistry) {
        registry.unregisterTexture(textureId)
        pixelBuffer = nil
    }
}

// MARK: - Comparable extension for CGFloat clamping

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
