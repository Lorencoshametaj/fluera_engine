import Flutter
import UIKit
import AudioToolbox
import CoreHaptics

/// 📳 Plugin nativo per la gestione della vibrazione su iOS
///
/// Supporta:
/// - Vibrazione semplice con durata (simulata con feedback aptico)
/// - Pattern di vibrazione complessi
/// - Intensità variabile tramite Core Haptics (iOS 13+)
/// - Controllo della disponibilità dell'hardware
/// - Cancellazione della vibrazione attiva
class VibrationPlugin: NSObject, FlutterPlugin {
    
    // MARK: - Properties
    
    private var hapticEngine: CHHapticEngine?
    private var hapticPlayer: CHHapticPatternPlayer?
    private var legacyVibrationTimer: Timer?
    private var isVibrating = false
    
    // MARK: - Plugin Registration
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "flueraengine.vibration/method",
            binaryMessenger: registrar.messenger()
        )
        let instance = VibrationPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        setupHapticEngine()
    }
    
    deinit {
        stopVibration()
        hapticEngine?.stop()
    }
    
    /// Setup del motore aptico (iOS 13+)
    private func setupHapticEngine() {
        guard #available(iOS 13.0, *) else {
            return
        }
        
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            return
        }
        
        do {
            hapticEngine = try CHHapticEngine()
            hapticEngine?.isAutoShutdownEnabled = true
            hapticEngine?.stoppedHandler = { [weak self] reason in
                self?.hapticEngine = nil
            }
            hapticEngine?.resetHandler = { [weak self] in
                do {
                    try self?.hapticEngine?.start()
                } catch {
                    self?.hapticEngine = nil
                }
            }
            try hapticEngine?.start()
        } catch {
            hapticEngine = nil
        }
    }
    
    // MARK: - FlutterPlugin
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "hasVibrator":
            handleHasVibrator(result: result)
            
        case "vibrate":
            handleVibrate(call: call, result: result)
            
        case "cancel":
            handleCancel(result: result)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    // MARK: - Method Handlers
    
    private func handleHasVibrator(result: @escaping FlutterResult) {
        if #available(iOS 13.0, *) {
            let hasAdvancedHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
            result(hasAdvancedHaptics)
        } else {
            result(true)
        }
    }
    
    private func handleVibrate(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any] else {
            vibrateWithDuration(duration: 400, amplitude: nil, result: result)
            return
        }
        
        // Stop any active vibration
        stopVibration()
        
        if let pattern = args["pattern"] as? [Int] {
            let intensities = args["intensities"] as? [Int]
            vibrateWithPattern(pattern: pattern, intensities: intensities, result: result)
        } else {
            let duration = args["duration"] as? Int ?? 400
            let amplitude = args["amplitude"] as? Int
            vibrateWithDuration(duration: duration, amplitude: amplitude, result: result)
        }
    }
    
    private func handleCancel(result: @escaping FlutterResult) {
        stopVibration()
        result(nil)
    }
    
    // MARK: - Vibration Implementation
    
    private func vibrateWithDuration(duration: Int, amplitude: Int?, result: @escaping FlutterResult) {
        isVibrating = true
        
        if #available(iOS 13.0, *), hapticEngine != nil {
            vibrateWithCoreHaptics(duration: duration, amplitude: amplitude, result: result)
        } else {
            vibrateWithLegacyMethod(duration: duration, result: result)
        }
    }
    
    @available(iOS 13.0, *)
    private func vibrateWithCoreHaptics(duration: Int, amplitude: Int?, result: @escaping FlutterResult) {
        guard let engine = hapticEngine else {
            vibrateWithLegacyMethod(duration: duration, result: result)
            return
        }
        
        do {
            let intensity: Float
            if let amp = amplitude {
                intensity = Float(min(max(amp, 0), 255)) / 255.0
            } else {
                intensity = 1.0
            }
            
            let durationSeconds = Float(duration) / 1000.0
            
            let hapticEvent = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
                ],
                relativeTime: 0,
                duration: TimeInterval(durationSeconds)
            )
            
            let pattern = try CHHapticPattern(events: [hapticEvent], parameters: [])
            hapticPlayer = try engine.makePlayer(with: pattern)
            try hapticPlayer?.start(atTime: 0)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(duration)) { [weak self] in
                self?.isVibrating = false
                self?.hapticPlayer = nil
            }
            
            result(nil)
            
        } catch {
            vibrateWithLegacyMethod(duration: duration, result: result)
        }
    }
    
    private func vibrateWithLegacyMethod(duration: Int, result: @escaping FlutterResult) {
        let repeatCount = max(1, duration / 400)
        var currentRepeat = 0
        
        legacyVibrationTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] timer in
            guard let self = self, self.isVibrating else {
                timer.invalidate()
                self?.legacyVibrationTimer = nil
                return
            }
            
            if currentRepeat >= repeatCount {
                timer.invalidate()
                self.legacyVibrationTimer = nil
                self.isVibrating = false
            } else {
                currentRepeat += 1
            }
        }
        
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        
        result(nil)
    }
    
    private func vibrateWithPattern(pattern: [Int], intensities: [Int]?, result: @escaping FlutterResult) {
        isVibrating = true
        
        if #available(iOS 13.0, *), hapticEngine != nil {
            vibratePatternWithCoreHaptics(pattern: pattern, intensities: intensities, result: result)
        } else {
            vibratePatternWithLegacy(pattern: pattern, result: result)
        }
    }
    
    @available(iOS 13.0, *)
    private func vibratePatternWithCoreHaptics(pattern: [Int], intensities: [Int]?, result: @escaping FlutterResult) {
        guard let engine = hapticEngine else {
            vibratePatternWithLegacy(pattern: pattern, result: result)
            return
        }
        
        do {
            var events: [CHHapticEvent] = []
            var currentTime: TimeInterval = 0
            
            for (index, duration) in pattern.enumerated() {
                let durationSeconds = TimeInterval(duration) / 1000.0
                
                if index % 2 == 1 {
                    let intensity: Float
                    if let ints = intensities {
                        let intIndex = index / 2
                        if intIndex < ints.count {
                            intensity = Float(min(max(ints[intIndex], 0), 255)) / 255.0
                        } else {
                            intensity = 1.0
                        }
                    } else {
                        intensity = 1.0
                    }
                    
                    let event = CHHapticEvent(
                        eventType: .hapticContinuous,
                        parameters: [
                            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
                        ],
                        relativeTime: currentTime,
                        duration: durationSeconds
                    )
                    events.append(event)
                }
                
                currentTime += durationSeconds
            }
            
            let hapticPattern = try CHHapticPattern(events: events, parameters: [])
            hapticPlayer = try engine.makePlayer(with: hapticPattern)
            try hapticPlayer?.start(atTime: 0)
            
            let totalDuration = Int(currentTime * 1000)
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(totalDuration)) { [weak self] in
                self?.isVibrating = false
                self?.hapticPlayer = nil
            }
            
            result(nil)
            
        } catch {
            vibratePatternWithLegacy(pattern: pattern, result: result)
        }
    }
    
    private func vibratePatternWithLegacy(pattern: [Int], result: @escaping FlutterResult) {
        var currentTime: TimeInterval = 0
        
        for (index, duration) in pattern.enumerated() {
            if index % 2 == 1 {
                DispatchQueue.main.asyncAfter(deadline: .now() + currentTime) { [weak self] in
                    guard self?.isVibrating == true else { return }
                    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                }
            }
            currentTime += TimeInterval(duration) / 1000.0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + currentTime) { [weak self] in
            self?.isVibrating = false
        }
        
        result(nil)
    }
    
    private func stopVibration() {
        isVibrating = false
        legacyVibrationTimer?.invalidate()
        legacyVibrationTimer = nil
        
        if #available(iOS 13.0, *) {
            try? hapticPlayer?.stop(atTime: 0)
            hapticPlayer = nil
        }
    }
}
