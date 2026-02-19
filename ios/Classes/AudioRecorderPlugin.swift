import Flutter
import UIKit
import AVFoundation

/// 🎤 AudioRecorderPlugin — Native audio recorder for Nebula Engine (iOS)
///
/// Uses AVAudioRecorder for high-quality audio capture. Supports:
/// - Start/stop/pause/resume recording
/// - Configurable format, sample rate, bit rate, channels
/// - Real-time amplitude and duration updates via EventChannel
/// - Microphone permission management
///
/// Platform Channel: `nebulaengine.audio/recorder`
/// Event Channel: `nebulaengine.audio/recorder_events`
class AudioRecorderPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    
    // MARK: - Properties
    
    private var audioRecorder: AVAudioRecorder?
    private var recordingFilePath: String?
    private var eventSink: FlutterEventSink?
    private var updateTimer: Timer?
    private var recordingStartTime: Date?
    private var pausedDuration: TimeInterval = 0
    private var pauseStartTime: Date?
    
    // MARK: - Plugin Registration
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let methodChannel = FlutterMethodChannel(
            name: "nebulaengine.audio/recorder",
            binaryMessenger: registrar.messenger()
        )
        
        let eventChannel = FlutterEventChannel(
            name: "nebulaengine.audio/recorder_events",
            binaryMessenger: registrar.messenger()
        )
        
        let instance = AudioRecorderPlugin()
        registrar.addMethodCallDelegate(instance, channel: methodChannel)
        eventChannel.setStreamHandler(instance)
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
        let sampleRate = args["sampleRate"] as? Int ?? 44100
        let bitRate = args["bitRate"] as? Int ?? 128000
        let numChannels = args["numChannels"] as? Int ?? 1
        
        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
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
        
        let tempDir = NSTemporaryDirectory()
        let fileName = "nebula_recording_\(Int(Date().timeIntervalSince1970 * 1000)).\(fileExtension)"
        let filePath = (tempDir as NSString).appendingPathComponent(fileName)
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
}
