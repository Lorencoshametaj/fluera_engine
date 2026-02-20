import Flutter
import UIKit
import PDFKit
import Vision

/// 📄 PdfRendererPlugin — Native iOS PDF Rendering via PDFKit
///
/// Provides direct access to Apple's PDFKit for:
/// - Loading PDF documents from raw bytes (multi-document support)
/// - Rendering pages as raw RGBA pixel buffers
/// - Extracting text geometry for selection
///
/// Channel: com.nebulaengine/pdf_renderer
public class PdfRendererPlugin: NSObject, FlutterPlugin {
    
    private var methodChannel: FlutterMethodChannel?
    
    /// Multi-document storage keyed by documentId.
    private var documents: [String: PDFDocument] = [:]
    
    // MARK: - Plugin Registration
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = PdfRendererPlugin()
        
        let methodChannel = FlutterMethodChannel(
            name: "com.nebulaengine/pdf_renderer",
            binaryMessenger: registrar.messenger()
        )
        instance.methodChannel = methodChannel
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
    
    // MARK: - Render Page (raw RGBA pixels)
    
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
