import Foundation
import Flutter

// LibTorch headers are bridged via the CocoaPod
// If LibTorchLite is properly linked, these types are available:
//   - TorchModule (load, predict)
//   - Tensor

/// 🧮 LatexRecognizerPlugin — iOS native module for LaTeX recognition.
///
/// Uses PyTorch Mobile (LibTorchLite) to run pix2tex encoder+decoder on-device.
///
/// Pipeline:
/// 1. Decode PNG → CGImage → grayscale float tensor
/// 2. Encode via encoder.ptl → feature tensor
/// 3. Decode autoregressively via decoder.ptl → token IDs
/// 4. Convert token IDs → LaTeX string via vocab.json
///
/// Channel: `nebula_engine/latex_recognition`
public class LatexRecognizerPlugin: NSObject, FlutterPlugin {
    
    // PyTorch Mobile modules
    private var encoderModule: TorchModule?
    private var decoderModule: TorchModule?
    private var resizerModule: TorchModule?
    
    // Vocabulary: token ID → string
    private var vocab: [Int: String] = [:]
    private var bosToken: Int = 1
    private var eosToken: Int = 2
    private var maxSeqLen: Int = 512
    
    private var isInitialized = false
    
    // Encoder input dimensions
    private static let encoderHeight = 192
    private static let encoderWidth = 672
    
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
            // Run inference on background thread
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.handleRecognize(imageBytes: imageBytes.data, result: result)
            }
        case "dispose":
            handleDispose(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    // MARK: - Initialize
    
    private func handleInitialize(result: @escaping FlutterResult) {
        guard !isInitialized else {
            result(["available": encoderModule != nil])
            return
        }
        
        do {
            // Load PyTorch Lite models from Flutter assets
            encoderModule = try loadModule(named: "encoder.ptl")
            decoderModule = try loadModule(named: "decoder.ptl")
            resizerModule = try loadModule(named: "resizer.ptl")
            
            // Load vocabulary and config
            try loadVocab()
            
            isInitialized = true
            let available = encoderModule != nil && decoderModule != nil
            NSLog("[LatexRecognizerPlugin] Initialized: encoder=\(encoderModule != nil), " +
                  "decoder=\(decoderModule != nil), resizer=\(resizerModule != nil), " +
                  "vocab=\(vocab.count) tokens")
            result(["available": available])
        } catch {
            NSLog("[LatexRecognizerPlugin] Initialization failed: \(error)")
            isInitialized = true
            result(["available": false])
        }
    }
    
    // MARK: - Recognize
    
    private func handleRecognize(imageBytes: Data, result: @escaping FlutterResult) {
        guard let encoder = encoderModule, let decoder = decoderModule else {
            DispatchQueue.main.async {
                result(FlutterError(
                    code: "NOT_AVAILABLE",
                    message: "ML model not loaded",
                    details: nil
                ))
            }
            return
        }
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        do {
            // 1. Preprocess image → grayscale float tensor
            let imageTensor = try preprocessImage(imageBytes)
            
            // 2. Encode → features
            guard let features = encoder.predict(withSingle: imageTensor) else {
                throw NSError(domain: "LatexRecognizer", code: 1,
                             userInfo: [NSLocalizedDescriptionKey: "Encoder returned nil"])
            }
            
            // 3. Autoregressive decode
            var tokenIds: [Int] = [bosToken]
            var tokenConfidences: [Float] = []
            
            for _ in 0..<maxSeqLen {
                // Build token tensor
                let tokenData = tokenIds.map { NSNumber(value: Int64($0)) }
                let tokenTensor = Tensor(
                    shape: [1, NSNumber(value: tokenIds.count)],
                    data: tokenData,
                    type: .long
                )
                
                // Run decoder: (tokens, features) → logits
                guard let logitsTensor = decoder.predict(
                    with: [tokenTensor, features]
                ) else {
                    break
                }
                
                let logits = logitsTensor.floatData
                
                // Apply softmax and get best token
                let probs = softmax(logits)
                let nextToken = probs.enumerated().max(by: { $0.element < $1.element })?.offset ?? eosToken
                let confidence = probs[nextToken]
                
                if nextToken == eosToken { break }
                
                tokenIds.append(nextToken)
                tokenConfidences.append(confidence)
            }
            
            // 4. Decode tokens → LaTeX string
            let latex = tokenIds.dropFirst() // skip BOS
                .compactMap { vocab[$0] }
                .joined()
            
            // 5. Overall confidence
            let overallConfidence: Double = tokenConfidences.isEmpty ? 0.0 :
                Double(tokenConfidences.reduce(0, +)) / Double(tokenConfidences.count)
            
            let inferenceTime = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
            NSLog("[LatexRecognizerPlugin] Inference: \(inferenceTime)ms → \(latex)")
            
            DispatchQueue.main.async {
                result([
                    "latex": latex,
                    "confidence": overallConfidence,
                    "alternatives": [] as [[String: Any]],
                    "inferenceTimeMs": inferenceTime
                ])
            }
        } catch {
            NSLog("[LatexRecognizerPlugin] Recognition failed: \(error)")
            DispatchQueue.main.async {
                result(FlutterError(
                    code: "INFERENCE_ERROR",
                    message: "Inference failed: \(error.localizedDescription)",
                    details: nil
                ))
            }
        }
    }
    
    // MARK: - Dispose
    
    private func handleDispose(result: @escaping FlutterResult) {
        encoderModule = nil
        decoderModule = nil
        resizerModule = nil
        vocab = [:]
        isInitialized = false
        NSLog("[LatexRecognizerPlugin] Disposed")
        result(nil)
    }
    
    // MARK: - Helpers
    
    /// Load a PyTorch Lite module from the Flutter assets bundle.
    private func loadModule(named filename: String) throws -> TorchModule? {
        // Flutter assets are in the main bundle under "Frameworks/App.framework/flutter_assets/"
        let key = FlutterDartProject.lookupKey(forAsset: "assets/models/pix2tex/\(filename)")
        guard let path = Bundle.main.path(forResource: key, ofType: nil) else {
            NSLog("[LatexRecognizerPlugin] Asset not found: \(filename)")
            return nil
        }
        
        guard let module = TorchModule(fileAtPath: path) else {
            NSLog("[LatexRecognizerPlugin] Failed to load module: \(filename)")
            return nil
        }
        
        NSLog("[LatexRecognizerPlugin] Loaded module: \(filename)")
        return module
    }
    
    /// Load vocabulary and config from Flutter assets.
    private func loadVocab() throws {
        // Load vocab.json
        let vocabKey = FlutterDartProject.lookupKey(forAsset: "assets/models/pix2tex/vocab.json")
        if let vocabPath = Bundle.main.path(forResource: vocabKey, ofType: nil) {
            let data = try Data(contentsOf: URL(fileURLWithPath: vocabPath))
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: String] {
                vocab = Dictionary(uniqueKeysWithValues: json.compactMap { key, value in
                    guard let id = Int(key) else { return nil }
                    return (id, value)
                })
            }
        }
        
        // Load config.json
        let configKey = FlutterDartProject.lookupKey(forAsset: "assets/models/pix2tex/config.json")
        if let configPath = Bundle.main.path(forResource: configKey, ofType: nil) {
            let data = try Data(contentsOf: URL(fileURLWithPath: configPath))
            if let config = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                bosToken = config["bos_token"] as? Int ?? 1
                eosToken = config["eos_token"] as? Int ?? 2
                maxSeqLen = config["max_seq_len"] as? Int ?? 512
            }
        }
        
        NSLog("[LatexRecognizerPlugin] Vocab: \(vocab.count) tokens, BOS=\(bosToken), EOS=\(eosToken)")
    }
    
    /// Preprocess PNG data → grayscale float tensor [1, 1, H, W].
    private func preprocessImage(_ pngData: Data) throws -> Tensor {
        guard let image = UIImage(data: pngData)?.cgImage else {
            throw NSError(domain: "LatexRecognizer", code: 2,
                         userInfo: [NSLocalizedDescriptionKey: "Could not decode image"])
        }
        
        let width = Self.encoderWidth
        let height = Self.encoderHeight
        
        // Create grayscale context and draw resized image
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            throw NSError(domain: "LatexRecognizer", code: 3,
                         userInfo: [NSLocalizedDescriptionKey: "Could not create bitmap context"])
        }
        
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        guard let pixelData = context.data else {
            throw NSError(domain: "LatexRecognizer", code: 4,
                         userInfo: [NSLocalizedDescriptionKey: "Could not get pixel data"])
        }
        
        // Convert UInt8 grayscale → Float32 [0, 1]
        let buffer = pixelData.bindMemory(to: UInt8.self, capacity: width * height)
        var floatData = [Float](repeating: 0, count: width * height)
        for i in 0..<(width * height) {
            floatData[i] = Float(buffer[i]) / 255.0
        }
        
        return Tensor(
            shape: [1, 1, NSNumber(value: height), NSNumber(value: width)],
            data: floatData.map { NSNumber(value: $0) },
            type: .float
        )
    }
    
    /// Compute softmax over logits array.
    private func softmax(_ logits: [Float]) -> [Float] {
        let maxVal = logits.max() ?? 0
        let exps = logits.map { exp($0 - maxVal) }
        let sum = exps.reduce(0, +)
        return exps.map { $0 / sum }
    }
}
