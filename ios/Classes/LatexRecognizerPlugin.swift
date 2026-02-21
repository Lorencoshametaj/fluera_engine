import Foundation
import Flutter
import CoreML
import Vision

/// 🧮 LatexRecognizerPlugin — iOS native module for LaTeX handwriting recognition.
///
/// Integrates with Flutter via MethodChannel to provide on-device ML inference
/// using Core ML. The plugin loads a pre-trained LaTeX-OCR model (LatexOCR.mlmodel)
/// and performs image-to-LaTeX conversion.
///
/// Channel: `nebula_engine/latex_recognition`
///
/// Methods:
/// - `initialize` → loads the Core ML model
/// - `recognize` → runs inference on a PNG image
/// - `dispose` → releases model resources
public class LatexRecognizerPlugin: NSObject, FlutterPlugin {
    
    private var model: VNCoreMLModel?
    private var isInitialized = false
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "nebula_engine/latex_recognition",
            binaryMessenger: registrar.messenger()
        )
        let instance = LatexRecognizerPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "initialize":
            handleInitialize(result: result)
        case "recognize":
            guard let args = call.arguments as? [String: Any],
                  let imageBytes = args["imageBytes"] as? FlutterStandardTypedData else {
                result(FlutterError(
                    code: "INVALID_ARGS",
                    message: "Missing imageBytes argument",
                    details: nil
                ))
                return
            }
            handleRecognize(imageBytes: imageBytes.data, result: result)
        case "dispose":
            handleDispose(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    // MARK: - Initialize
    
    private func handleInitialize(result: @escaping FlutterResult) {
        guard !isInitialized else {
            result(["available": model != nil])
            return
        }
        
        // Attempt to load the Core ML model from the app bundle
        guard let modelURL = Bundle.main.url(
            forResource: "LatexOCR",
            withExtension: "mlmodelc"
        ) else {
            NSLog("[LatexRecognizerPlugin] Model file not found in bundle")
            isInitialized = true
            result(["available": false])
            return
        }
        
        do {
            let coreMLModel = try MLModel(contentsOf: modelURL)
            model = try VNCoreMLModel(for: coreMLModel)
            isInitialized = true
            NSLog("[LatexRecognizerPlugin] Model loaded successfully")
            result(["available": true])
        } catch {
            NSLog("[LatexRecognizerPlugin] Failed to load model: \(error)")
            isInitialized = true
            result(["available": false])
        }
    }
    
    // MARK: - Recognize
    
    private func handleRecognize(imageBytes: Data, result: @escaping FlutterResult) {
        guard let vncoremlModel = model else {
            result(FlutterError(
                code: "NOT_AVAILABLE",
                message: "ML model not loaded",
                details: nil
            ))
            return
        }
        
        guard let image = UIImage(data: imageBytes)?.cgImage else {
            result(FlutterError(
                code: "INVALID_IMAGE",
                message: "Could not decode image from bytes",
                details: nil
            ))
            return
        }
        
        let request = VNCoreMLRequest(model: vncoremlModel) { request, error in
            if let error = error {
                result(FlutterError(
                    code: "INFERENCE_ERROR",
                    message: "Inference failed: \(error.localizedDescription)",
                    details: nil
                ))
                return
            }
            
            guard let observations = request.results as? [VNClassificationObservation],
                  let topResult = observations.first else {
                result([
                    "latex": "",
                    "confidence": 0.0,
                    "alternatives": [] as [[String: Any]]
                ])
                return
            }
            
            // Build response
            var alternatives: [[String: Any]] = []
            for obs in observations.prefix(5).dropFirst() {
                alternatives.append([
                    "latex": obs.identifier,
                    "confidence": Double(obs.confidence)
                ])
            }
            
            result([
                "latex": topResult.identifier,
                "confidence": Double(topResult.confidence),
                "alternatives": alternatives
            ])
        }
        
        request.imageCropAndScaleOption = .scaleFill
        
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                result(FlutterError(
                    code: "HANDLER_ERROR",
                    message: "Failed to perform inference: \(error.localizedDescription)",
                    details: nil
                ))
            }
        }
    }
    
    // MARK: - Dispose
    
    private func handleDispose(result: @escaping FlutterResult) {
        model = nil
        isInitialized = false
        NSLog("[LatexRecognizerPlugin] Disposed")
        result(nil)
    }
}
