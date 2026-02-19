import Flutter
import UIKit
import PDFKit

/// 📄 PdfRendererPlugin — Native iOS PDF Rendering via PDFKit
///
/// Provides direct access to Apple's PDFKit for:
/// - Loading PDF documents from raw bytes
/// - Rendering pages as raw RGBA pixel buffers
/// - Extracting text geometry for selection
///
/// Channel: com.nebulaengine/pdf_renderer
public class PdfRendererPlugin: NSObject, FlutterPlugin {
    
    private var methodChannel: FlutterMethodChannel?
    private var currentDocument: PDFDocument?
    
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
        case "dispose":
            handleDispose(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    // MARK: - Load Document
    
    private func handleLoadDocument(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let flutterData = args["bytes"] as? FlutterStandardTypedData else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing 'bytes'", details: nil))
            return
        }
        
        let data = flutterData.data
        guard let document = PDFDocument(data: data) else {
            result(["pageCount": 0, "success": false])
            return
        }
        
        // Release previous document
        currentDocument = nil
        currentDocument = document
        
        result([
            "pageCount": document.pageCount,
            "success": true
        ])
    }
    
    // MARK: - Page Size
    
    private func handleGetPageSize(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let pageIndex = args["pageIndex"] as? Int else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing 'pageIndex'", details: nil))
            return
        }
        
        guard let document = currentDocument,
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
              let pageIndex = args["pageIndex"] as? Int,
              let targetWidth = args["targetWidth"] as? Int,
              let targetHeight = args["targetHeight"] as? Int else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing arguments", details: nil))
            return
        }
        
        guard let document = currentDocument,
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
            let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            
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
            // PDF coordinate system is bottom-up; CGContext for bitmap is also bottom-up
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
              let pageIndex = args["pageIndex"] as? Int else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing 'pageIndex'", details: nil))
            return
        }
        
        guard let document = currentDocument,
              pageIndex >= 0 && pageIndex < document.pageCount,
              let page = document.page(at: pageIndex) else {
            result([])
            return
        }
        
        // Extract text rects using PDFKit selections
        var textRects: [[String: Any]] = []
        let pageBounds = page.bounds(for: .mediaBox)
        
        guard let pageText = page.string, !pageText.isEmpty else {
            result([])
            return
        }
        
        // Get character-level selections for text geometry
        var charOffset = 0
        for i in 0..<pageText.count {
            let range = NSRange(location: i, length: 1)
            if let selection = page.selection(for: range) {
                let bounds = selection.bounds(for: page)
                // Convert from PDF coords (bottom-up) to top-down
                let flippedY = pageBounds.height - bounds.origin.y - bounds.height
                
                let char = String(pageText[pageText.index(pageText.startIndex, offsetBy: i)])
                
                textRects.append([
                    "x": Double(bounds.origin.x),
                    "y": Double(flippedY),
                    "width": Double(bounds.width),
                    "height": Double(bounds.height),
                    "text": char,
                    "charOffset": charOffset
                ])
            }
            charOffset += 1
        }
        
        result(textRects)
    }
    
    // MARK: - Get Page Text
    
    private func handleGetPageText(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let pageIndex = args["pageIndex"] as? Int else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing 'pageIndex'", details: nil))
            return
        }
        
        guard let document = currentDocument,
              pageIndex >= 0 && pageIndex < document.pageCount,
              let page = document.page(at: pageIndex) else {
            result("")
            return
        }
        
        result(page.string ?? "")
    }
    
    // MARK: - Dispose
    
    private func handleDispose(result: @escaping FlutterResult) {
        currentDocument = nil
        result(nil)
    }
}
