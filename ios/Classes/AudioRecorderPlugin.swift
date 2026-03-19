import Flutter
import UIKit
import AVFoundation

/// 🎤 AudioRecorderPlugin — Native audio recorder for Fluera Engine (iOS)
///
/// Uses AVAudioRecorder for high-quality audio capture. Supports:
/// - Start/stop/pause/resume recording
/// - Configurable format, sample rate, bit rate, channels
/// - Real-time amplitude and duration updates via EventChannel
/// - Microphone permission management
///
/// Platform Channel: `flueraengine.audio/recorder`
/// Event Channel: `flueraengine.audio/recorder_events`
class AudioRecorderPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    
    // MARK: - Properties
    
    private var audioRecorder: AVAudioRecorder?
    private var recordingFilePath: String?
    private var eventSink: FlutterEventSink?
    private var updateTimer: Timer?
    private var recordingStartTime: Date?
    private var pausedDuration: TimeInterval = 0
    private var pauseStartTime: Date?
    
    // 🎤 Live PCM streaming for real-time transcription
    fileprivate var pcmEventSink: FlutterEventSink?
    private var audioEngine: AVAudioEngine?
    private var pcmStreamEnabled = false
    
    // MARK: - Plugin Registration
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let methodChannel = FlutterMethodChannel(
            name: "flueraengine.audio/recorder",
            binaryMessenger: registrar.messenger()
        )
        
        let eventChannel = FlutterEventChannel(
            name: "flueraengine.audio/recorder_events",
            binaryMessenger: registrar.messenger()
        )
        
        let pcmEventChannel = FlutterEventChannel(
            name: "flueraengine.audio/recorder_pcm",
            binaryMessenger: registrar.messenger()
        )
        
        let instance = AudioRecorderPlugin()
        registrar.addMethodCallDelegate(instance, channel: methodChannel)
        eventChannel.setStreamHandler(instance)
        pcmEventChannel.setStreamHandler(PcmStreamHandler(plugin: instance))
    }
    
    deinit {
        stopUpdateTimer()
        audioRecorder?.stop()
        audioRecorder = nil
    }
    
    // MARK: - FlutterPlugin
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "initialize":
            handleInitialize(result: result)
            
        case "startRecording":
            handleStartRecording(call: call, result: result)
            
        case "stopRecording":
            handleStopRecording(result: result)
            
        case "pauseRecording":
            handlePauseRecording(result: result)
            
        case "resumeRecording":
            handleResumeRecording(result: result)
            
        case "cancelRecording":
            handleCancelRecording(result: result)
            
        case "hasPermission":
            handleHasPermission(result: result)
            
        case "requestPermission":
            handleRequestPermission(result: result)
            
        case "applyAudioProcessing":
            handleApplyAudioProcessing(call: call, result: result)
            
        case "convertToWav":
            handleConvertToWav(call: call, result: result)
            
        case "enablePcmStream":
            pcmStreamEnabled = true
            startPcmTap()
            result(nil)
            
        case "disablePcmStream":
            pcmStreamEnabled = false
            stopPcmTap()
            result(nil)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    // MARK: - FlutterStreamHandler
    
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }
    
    // MARK: - Method Handlers
    
    private func handleInitialize(result: @escaping FlutterResult) {
        result(nil)
    }
    
    private func handleStartRecording(call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        let formatStr = args["format"] as? String ?? "m4a"
        let sampleRate = args["sampleRate"] as? Int ?? 48000
        let bitRate = args["bitRate"] as? Int ?? 256000
        let numChannels = args["numChannels"] as? Int ?? 1
        let noiseSuppression = args["noiseSuppression"] as? Bool ?? true
        
        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        do {
            // 🔇 Use .videoRecording mode when noise suppression is enabled
            // (reduces pen/finger scratch noise from screen)
            let mode: AVAudioSession.Mode = noiseSuppression ? .videoRecording : .default
            try audioSession.setCategory(.playAndRecord, mode: mode, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true)
        } catch {
            sendError("Failed to configure audio session: \(error.localizedDescription)")
            result(FlutterError(code: "SESSION_ERROR", message: "Failed to configure audio session", details: error.localizedDescription))
            return
        }
        
        // Create temp file
        let fileExtension: String
        let audioFormat: AudioFormatID
        
        switch formatStr {
        case "wav":
            fileExtension = "wav"
            audioFormat = kAudioFormatLinearPCM
        case "aac":
            fileExtension = "aac"
            audioFormat = kAudioFormatMPEG4AAC
        default: // m4a
            fileExtension = "m4a"
            audioFormat = kAudioFormatMPEG4AAC
        }
        
        // 🔧 FIX: Use persistent Documents directory instead of temp
        let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let recordingsDir = docDir.appendingPathComponent("recordings")
        try? FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
        let fileName = "fluera_recording_\(Int(Date().timeIntervalSince1970 * 1000)).\(fileExtension)"
        let filePath = recordingsDir.appendingPathComponent(fileName).path
        recordingFilePath = filePath
        
        let url = URL(fileURLWithPath: filePath)
        
        // Recording settings
        var settings: [String: Any] = [
            AVFormatIDKey: audioFormat,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: numChannels,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        
        if audioFormat == kAudioFormatMPEG4AAC {
            settings[AVEncoderBitRateKey] = bitRate
        }
        
        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()
            
            recordingStartTime = Date()
            pausedDuration = 0
            pauseStartTime = nil
            
            sendState("recording")
            startUpdateTimer()
            
            result(nil)
        } catch {
            sendError("Failed to start recording: \(error.localizedDescription)")
            result(FlutterError(code: "RECORD_ERROR", message: "Failed to start recording", details: error.localizedDescription))
        }
    }
    
    private func handleStopRecording(result: @escaping FlutterResult) {
        guard let recorder = audioRecorder, recorder.isRecording || pauseStartTime != nil else {
            result(FlutterError(code: "NOT_RECORDING", message: "Not currently recording", details: nil))
            return
        }
        
        recorder.stop()
        stopUpdateTimer()
        deactivateAudioSession()
        
        let path = recordingFilePath
        sendState("stopped")
        
        audioRecorder = nil
        recordingStartTime = nil
        pausedDuration = 0
        pauseStartTime = nil
        
        result(path)
    }
    
    private func handlePauseRecording(result: @escaping FlutterResult) {
        guard let recorder = audioRecorder, recorder.isRecording else {
            result(FlutterError(code: "NOT_RECORDING", message: "Not currently recording", details: nil))
            return
        }
        
        recorder.pause()
        pauseStartTime = Date()
        sendState("paused")
        
        result(nil)
    }
    
    private func handleResumeRecording(result: @escaping FlutterResult) {
        guard let recorder = audioRecorder else {
            result(FlutterError(code: "NOT_RECORDING", message: "No recorder available", details: nil))
            return
        }
        
        if let pauseStart = pauseStartTime {
            pausedDuration += Date().timeIntervalSince(pauseStart)
            pauseStartTime = nil
        }
        
        recorder.record()
        sendState("recording")
        
        result(nil)
    }
    
    private func handleCancelRecording(result: @escaping FlutterResult) {
        audioRecorder?.stop()
        stopUpdateTimer()
        deactivateAudioSession()
        
        // Delete temp file
        if let path = recordingFilePath {
            try? FileManager.default.removeItem(atPath: path)
        }
        
        audioRecorder = nil
        recordingFilePath = nil
        recordingStartTime = nil
        pausedDuration = 0
        pauseStartTime = nil
        
        sendState("idle")
        
        result(nil)
    }
    
    private func handleHasPermission(result: @escaping FlutterResult) {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted:
            result(true)
        case .denied, .undetermined:
            result(false)
        @unknown default:
            result(false)
        }
    }
    
    private func handleRequestPermission(result: @escaping FlutterResult) {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                result(granted)
            }
        }
    }
    
    // MARK: - Timer & Event Sending
    
    private func startUpdateTimer() {
        stopUpdateTimer()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.sendPeriodicUpdate()
        }
    }
    
    private func stopUpdateTimer() {
        updateTimer?.invalidate()
        updateTimer = nil
    }
    
    private func sendPeriodicUpdate() {
        guard let recorder = audioRecorder, let startTime = recordingStartTime else { return }
        
        // Duration (excluding paused time)
        let totalElapsed = Date().timeIntervalSince(startTime)
        let currentPauseDuration = pauseStartTime != nil ? Date().timeIntervalSince(pauseStartTime!) : 0
        let effectiveDuration = totalElapsed - pausedDuration - currentPauseDuration
        let durationMs = Int(max(0, effectiveDuration) * 1000)
        
        sendDuration(durationMs)
        
        // Amplitude
        recorder.updateMeters()
        let avgPower = recorder.averagePower(forChannel: 0)
        let peakPower = recorder.peakPower(forChannel: 0)
        
        // Convert dB to linear (0.0 - 1.0)
        let linearAvg = pow(10.0, avgPower / 20.0)
        let linearPeak = pow(10.0, peakPower / 20.0)
        
        sendAmplitude(current: Double(linearAvg), max: Double(linearPeak))
    }
    
    private func sendState(_ state: String) {
        DispatchQueue.main.async { [weak self] in
            self?.eventSink?(["event": "state", "state": state])
        }
    }
    
    private func sendDuration(_ durationMs: Int) {
        DispatchQueue.main.async { [weak self] in
            self?.eventSink?(["event": "duration", "duration": durationMs])
        }
    }
    
    private func sendAmplitude(current: Double, max: Double) {
        DispatchQueue.main.async { [weak self] in
            self?.eventSink?(["event": "amplitude", "current": current, "max": max])
        }
    }
    
    private func sendError(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.eventSink?(["event": "error", "error": message])
        }
    }
    
    private func deactivateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            // Ignore — session may be shared
        }
    }
    
    // MARK: - Audio Processing Pipeline
    
    private func handleApplyAudioProcessing(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let filePath = args["filePath"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "filePath is required", details: nil))
            return
        }
        let sampleRate = args["sampleRate"] as? Int ?? 48000
        let highPassFilterHz = args["highPassFilterHz"] as? Int ?? 0
        let noiseGate = args["noiseGate"] as? Bool ?? false
        let compressor = args["compressor"] as? Bool ?? false
        let normalization = args["normalization"] as? Bool ?? false
        let rawIntervals = args["penIntervals"] as? [[Int]]
        
        // Convert to array of tuples
        let penIntervals = rawIntervals?.map { ($0[0], $0[1]) }
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try self.processAudioFile(
                    filePath: filePath,
                    sampleRate: sampleRate,
                    highPassFilterHz: highPassFilterHz,
                    noiseGate: noiseGate,
                    compressor: compressor,
                    normalization: normalization,
                    penIntervals: penIntervals
                )
                DispatchQueue.main.async {
                    result(filePath)
                }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(code: "PROCESSING_ERROR", message: "Audio processing failed: \(error.localizedDescription)", details: nil))
                }
            }
        }
    }
    
    /// Full audio processing pipeline:
    /// 1. Read with AVAudioFile → PCM float buffer
    /// 2. High-pass filter (Butterworth 2nd order)
    /// 3. Noise gate (silences below threshold)
    /// 4. Compressor (evens dynamics)
    /// 5. Normalization (peak → -3dB)
    /// 6. Write back to M4A
    private func processAudioFile(
        filePath: String,
        sampleRate: Int,
        highPassFilterHz: Int,
        noiseGate: Bool,
        compressor: Bool,
        normalization: Bool,
        penIntervals: [(Int, Int)]? = nil
    ) throws {
        let inputURL = URL(fileURLWithPath: filePath)
        let inputFile = try AVAudioFile(forReading: inputURL)
        
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                          sampleRate: inputFile.processingFormat.sampleRate,
                                          channels: inputFile.processingFormat.channelCount,
                                          interleaved: false) else {
            throw NSError(domain: "DSP", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create format"])
        }
        
        let frameCount = AVAudioFrameCount(inputFile.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw NSError(domain: "DSP", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to create buffer"])
        }
        
        try inputFile.read(into: buffer)
        buffer.frameLength = frameCount
        
        let actualSampleRate = inputFile.processingFormat.sampleRate
        let count = Int(frameCount)
        
        // Apply pipeline to each channel
        for ch in 0..<Int(format.channelCount) {
            guard let channelData = buffer.floatChannelData?[ch] else { continue }
            
            // Step 2: High-pass filter
            if highPassFilterHz > 0 {
                butterworthHPF(samples: channelData, count: count, cutoffHz: Double(highPassFilterHz), sampleRate: actualSampleRate)
            }
            
            // Step 3: RNNoise neural denoising
            if actualSampleRate == 48000 {
                applyRNNoise(samples: channelData, count: count)
            }
            
            // Step 4: Presence EQ (voice clarity)
            applyPresenceEQ(samples: channelData, count: count, sampleRate: actualSampleRate)
            
            // Step 5: Compressor
            if compressor {
                applyCompressor(samples: channelData, count: count, sampleRate: actualSampleRate)
            }
            
            // Step 6: Normalization
            if normalization {
                applyNormalization(samples: channelData, count: count)
            }
        }
        
        // Write to temp file
        let tempURL = inputURL.deletingLastPathComponent().appendingPathComponent("processed_\(inputURL.lastPathComponent)")
        
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: actualSampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVEncoderBitRateKey: 256000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        
        let outputFile = try AVAudioFile(forWriting: tempURL, settings: settings)
        try outputFile.write(from: buffer)
        
        // Replace original
        try FileManager.default.removeItem(at: inputURL)
        try FileManager.default.moveItem(at: tempURL, to: inputURL)
    }
    
    // MARK: - DSP Functions
    // MARK: - RNNoise Neural Denoising
    
    /// 🧠 Process audio through RNNoise ML model.
    /// Operates on 480-sample frames at 48kHz.
    private func applyRNNoise(samples: UnsafeMutablePointer<Float>, count: Int) {
        guard let st = rnnoise_create(nil) else { return }
        defer { rnnoise_destroy(st) }
        
        let frameSize = Int(rnnoise_get_frame_size())  // 480
        var frame = [Float](repeating: 0, count: frameSize)
        var framesProcessed = 0
        
        // RNNoise expects samples in [-32768, 32767] range (16-bit PCM scale)
        // but AVAudioEngine uses Float32 [-1.0, 1.0] — must scale!
        let scaleFactor: Float = 32768.0
        
        var i = 0
        while i + frameSize <= count {
            // Scale [-1, 1] → [-32768, 32767] for RNNoise
            for j in 0..<frameSize {
                frame[j] = samples[i + j] * scaleFactor
            }
            
            _ = rnnoise_process_frame(st, &frame, frame)
            
            // Scale back [-32768, 32767] → [-1, 1]
            for j in 0..<frameSize {
                samples[i + j] = frame[j] / scaleFactor
            }
            
            framesProcessed += 1
            i += frameSize
        }
        
        // Handle remaining samples
        if i < count {
            frame = [Float](repeating: 0, count: frameSize)
            let remaining = count - i
            for j in 0..<remaining {
                frame[j] = samples[i + j] * scaleFactor
            }
            _ = rnnoise_process_frame(st, &frame, frame)
            for j in 0..<remaining {
                samples[i + j] = frame[j] / scaleFactor
            }
            framesProcessed += 1
        }
    }
    
    // MARK: - Butterworth HPF
    
    private func butterworthHPF(samples: UnsafeMutablePointer<Float>, count: Int, cutoffHz: Double, sampleRate: Double) {
        // Run two passes for 4th-order (-24dB/oct)
        butterworthHPFPass(samples: samples, count: count, cutoffHz: cutoffHz, sampleRate: sampleRate)
        butterworthHPFPass(samples: samples, count: count, cutoffHz: cutoffHz, sampleRate: sampleRate)
    }
    
    private func butterworthHPFPass(samples: UnsafeMutablePointer<Float>, count: Int, cutoffHz: Double, sampleRate: Double) {
        let omega = 2.0 * Double.pi * cutoffHz / sampleRate
        let sinOmega = sin(omega)
        let cosOmega = cos(omega)
        let alpha = sinOmega / (2.0 * sqrt(2.0))
        
        let a0 = 1.0 + alpha
        let b0 = Float(((1.0 + cosOmega) / 2.0) / a0)
        let b1 = Float((-(1.0 + cosOmega)) / a0)
        let b2 = Float(((1.0 + cosOmega) / 2.0) / a0)
        let a1 = Float((-2.0 * cosOmega) / a0)
        let a2 = Float((1.0 - alpha) / a0)
        
        var x1: Float = 0, x2: Float = 0
        var y1: Float = 0, y2: Float = 0
        
        for i in 0..<count {
            let x0 = samples[i]
            let y0 = b0 * x0 + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = x0
            y2 = y1; y1 = y0
            samples[i] = y0
        }
    }
    
    /// 4th-order Butterworth low-pass filter (in-place on Float32).
    /// Cascades two 2nd-order stages for -24dB/octave roll-off.
    private func butterworthLPF(samples: UnsafeMutablePointer<Float>, count: Int, cutoffHz: Double, sampleRate: Double) {
        butterworthLPFPass(samples: samples, count: count, cutoffHz: cutoffHz, sampleRate: sampleRate)
        butterworthLPFPass(samples: samples, count: count, cutoffHz: cutoffHz, sampleRate: sampleRate)
    }
    
    private func butterworthLPFPass(samples: UnsafeMutablePointer<Float>, count: Int, cutoffHz: Double, sampleRate: Double) {
        let omega = 2.0 * Double.pi * cutoffHz / sampleRate
        let sinOmega = sin(omega)
        let cosOmega = cos(omega)
        let alpha = sinOmega / (2.0 * sqrt(2.0))
        
        let a0 = 1.0 + alpha
        let b0 = Float(((1.0 - cosOmega) / 2.0) / a0)
        let b1 = Float((1.0 - cosOmega) / a0)
        let b2 = Float(((1.0 - cosOmega) / 2.0) / a0)
        let a1 = Float((-2.0 * cosOmega) / a0)
        let a2 = Float((1.0 - alpha) / a0)
        
        var x1: Float = 0, x2: Float = 0
        var y1: Float = 0, y2: Float = 0
        
        for i in 0..<count {
            let x0 = samples[i]
            let y0 = b0 * x0 + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = x0
            y2 = y1; y1 = y0
            samples[i] = y0
        }
    }

    
    /// Compressor — reduces dynamic range.
    /// Threshold: -20dB, Ratio: 4:1, Attack: 5ms, Release: 50ms, Auto make-up gain.
    private func applyCompressor(samples: UnsafeMutablePointer<Float>, count: Int, sampleRate: Double) {
        // Find peak for threshold reference
        var peak: Float = 0
        for i in 0..<count {
            let absVal = abs(samples[i])
            if absVal > peak { peak = absVal }
        }
        if peak < 0.0001 { return }
        
        let thresholdLinear = peak * Float(pow(10.0, -18.0 / 20.0)) // -18dB of peak
        let ratio: Float = 2.5
        let attackCoeff: Float = 1.0 / max(Float(sampleRate * 0.010), 1.0)  // 10ms
        let releaseCoeff: Float = 1.0 / max(Float(sampleRate * 0.100), 1.0) // 100ms
        
        var envelope: Float = 0
        
        // Pass 1: Compress
        for i in 0..<count {
            let absVal = abs(samples[i])
            let coeff = absVal > envelope ? attackCoeff : releaseCoeff
            envelope += (absVal - envelope) * coeff
            
            if envelope > thresholdLinear {
                let overDb = 20.0 * log10(envelope / thresholdLinear)
                let reducedDb = overDb * (1.0 - 1.0 / ratio)
                let gain = powf(10.0, -reducedDb / 20.0)
                samples[i] *= gain
            }
        }
        
        // Pass 2: Auto make-up gain
        var newPeak: Float = 0
        for i in 0..<count {
            let absVal = abs(samples[i])
            if absVal > newPeak { newPeak = absVal }
        }
        if newPeak > 0 {
            let makeupGain = (peak * 0.707) / newPeak // target -3dB of original peak
            if makeupGain > 1.0 {
                for i in 0..<count {
                    samples[i] *= makeupGain
                }
            }
        }
    }
    
    /// Presence EQ — subtle voice clarity boost at 3kHz (+3dB, Q=1.5).
    /// Enhances speech intelligibility through the presence frequency range.
    private func applyPresenceEQ(samples: UnsafeMutablePointer<Float>, count: Int, sampleRate: Double) {
        let centerHz = 3000.0
        let gainDb = 3.0
        let q = 1.5
        
        let A = pow(10.0, gainDb / 40.0)
        let omega = 2.0 * Double.pi * centerHz / sampleRate
        let sinOmega = sin(omega)
        let cosOmega = cos(omega)
        let alpha = sinOmega / (2.0 * q)
        
        let a0 = 1.0 + alpha / A
        let b0 = Float((1.0 + alpha * A) / a0)
        let b1 = Float((-2.0 * cosOmega) / a0)
        let b2 = Float((1.0 - alpha * A) / a0)
        let a1f = Float((-2.0 * cosOmega) / a0)
        let a2f = Float((1.0 - alpha / A) / a0)
        
        var x1: Float = 0, x2: Float = 0
        var y1: Float = 0, y2: Float = 0
        
        for i in 0..<count {
            let x0 = samples[i]
            let y0 = b0 * x0 + b1 * x1 + b2 * x2 - a1f * y1 - a2f * y2
            x2 = x1; x1 = x0
            y2 = y1; y1 = y0
            samples[i] = y0
        }
    }
    
    /// Peak normalization to -3dB.
    private func applyNormalization(samples: UnsafeMutablePointer<Float>, count: Int) {
        var peak: Float = 0
        for i in 0..<count {
            let absVal = abs(samples[i])
            if absVal > peak { peak = absVal }
        }
        
        if peak < 0.0001 { return } // Silence
        
        let targetPeak: Float = 0.707 // -3 dB
        let gain = targetPeak / peak
        
        for i in 0..<count {
            samples[i] *= gain
        }
    }
    
    // MARK: - Audio Format Conversion
    
    /// 🔄 Convert an audio file (M4A/AAC) to 16kHz mono WAV for ASR models.
    ///
    /// Uses AVAudioFile to read the source and AVAudioConverter to resample
    /// to the target sample rate. Writes a standard 16-bit PCM WAV file.
    private func handleConvertToWav(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let inputPath = args["inputPath"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "inputPath is required", details: nil))
            return
        }
        let targetSampleRate = args["sampleRate"] as? Int ?? 16000
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let inputURL = URL(fileURLWithPath: inputPath)
                let inputFile = try AVAudioFile(forReading: inputURL)
                
                // Target format: 16kHz mono Float32 (for intermediate processing)
                guard let targetFormat = AVAudioFormat(
                    commonFormat: .pcmFormatFloat32,
                    sampleRate: Double(targetSampleRate),
                    channels: 1,
                    interleaved: false
                ) else {
                    throw NSError(domain: "WAV", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create target format"])
                }
                
                let sourceFormat = inputFile.processingFormat
                let sourceFrameCount = AVAudioFrameCount(inputFile.length)
                
                // Read source audio
                guard let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: sourceFrameCount) else {
                    throw NSError(domain: "WAV", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to create source buffer"])
                }
                try inputFile.read(into: sourceBuffer)
                sourceBuffer.frameLength = sourceFrameCount
                
                // Resample if needed
                let outputBuffer: AVAudioPCMBuffer
                if sourceFormat.sampleRate != Double(targetSampleRate) || sourceFormat.channelCount != 1 {
                    guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
                        throw NSError(domain: "WAV", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to create converter"])
                    }
                    
                    let ratio = Double(targetSampleRate) / sourceFormat.sampleRate
                    let outputFrameCount = AVAudioFrameCount(Double(sourceFrameCount) * ratio)
                    guard let resampledBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCount) else {
                        throw NSError(domain: "WAV", code: -4, userInfo: [NSLocalizedDescriptionKey: "Failed to create resample buffer"])
                    }
                    
                    var error: NSError?
                    converter.convert(to: resampledBuffer, error: &error) { _, outStatus in
                        outStatus.pointee = .haveData
                        return sourceBuffer
                    }
                    if let error = error {
                        throw error
                    }
                    outputBuffer = resampledBuffer
                } else {
                    outputBuffer = sourceBuffer
                }
                
                // Write as 16-bit PCM WAV
                let baseName = (inputPath as NSString).deletingPathExtension
                let outputPath = "\(baseName)_16k.wav"
                let outputURL = URL(fileURLWithPath: outputPath)
                
                guard let wavFormat = AVAudioFormat(
                    commonFormat: .pcmFormatInt16,
                    sampleRate: Double(targetSampleRate),
                    channels: 1,
                    interleaved: true
                ) else {
                    throw NSError(domain: "WAV", code: -5, userInfo: [NSLocalizedDescriptionKey: "Failed to create WAV format"])
                }
                
                let outputFile = try AVAudioFile(forWriting: outputURL, settings: wavFormat.settings)
                
                // Convert Float32 → Int16 for WAV
                guard let int16Converter = AVAudioConverter(from: targetFormat, to: wavFormat) else {
                    throw NSError(domain: "WAV", code: -6, userInfo: [NSLocalizedDescriptionKey: "Failed to create Int16 converter"])
                }
                
                guard let int16Buffer = AVAudioPCMBuffer(pcmFormat: wavFormat, frameCapacity: outputBuffer.frameLength) else {
                    throw NSError(domain: "WAV", code: -7, userInfo: [NSLocalizedDescriptionKey: "Failed to create Int16 buffer"])
                }
                
                var convError: NSError?
                int16Converter.convert(to: int16Buffer, error: &convError) { _, outStatus in
                    outStatus.pointee = .haveData
                    return outputBuffer
                }
                if let convError = convError {
                    throw convError
                }
                
                try outputFile.write(from: int16Buffer)
                
                DispatchQueue.main.async {
                    result(outputPath)
                }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(code: "CONVERT_ERROR", message: "WAV conversion failed: \(error.localizedDescription)", details: nil))
                }
            }
        }
    }
    
    // MARK: - 🎤 Live PCM Streaming
    
    private func startPcmTap() {
        guard audioEngine == nil else { return }
        
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let nativeFormat = inputNode.outputFormat(forBus: 0)
        
        // Target: 16kHz mono Int16
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: true
        ) else { return }
        
        // 🚀 Create converter once (reused by closure capture)
        let converter = AVAudioConverter(from: nativeFormat, to: targetFormat)
        
        // 🚀 Pre-allocate output buffer (~100ms at 16kHz = 1600 frames)
        let targetFrameCount = AVAudioFrameCount(16000 * 0.1)
        let reusableOutputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: targetFrameCount)
        
        // Buffer size: ~100ms of audio at native rate
        let bufferSize = AVAudioFrameCount(nativeFormat.sampleRate * 0.1)
        
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: nativeFormat) { [weak self] (buffer, _) in
            guard let self = self, self.pcmStreamEnabled, let sink = self.pcmEventSink else { return }
            guard let converter = converter, let outputBuffer = reusableOutputBuffer else { return }
            
            // 🚀 Reset frame length (reuse buffer without reallocation)
            outputBuffer.frameLength = 0
            
            var convError: NSError?
            let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            
            converter.convert(to: outputBuffer, error: &convError, withInputFrom: inputBlock)
            if convError != nil { return }
            
            let frameCount = Int(outputBuffer.frameLength)
            guard frameCount > 0, let int16Ptr = outputBuffer.int16ChannelData else { return }
            
            // Convert Int16 samples to ByteArray
            let byteCount = frameCount * 2
            let data = Data(bytes: int16Ptr[0], count: byteCount)
            
            DispatchQueue.main.async {
                sink(FlutterStandardTypedData(bytes: data))
            }
        }
        
        do {
            try engine.start()
            audioEngine = engine
        } catch {
            NSLog("🎤 PCM tap failed to start: \(error.localizedDescription)")
        }
    }
    
    private func stopPcmTap() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
    }
}

// MARK: - PCM EventChannel StreamHandler

private class PcmStreamHandler: NSObject, FlutterStreamHandler {
    weak var plugin: AudioRecorderPlugin?
    
    init(plugin: AudioRecorderPlugin) {
        self.plugin = plugin
    }
    
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        plugin?.pcmEventSink = events
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        plugin?.pcmEventSink = nil
        return nil
    }
}
