import Flutter
import UIKit

/// 🚀 DisplayLinkPlugin - CADisplayLink Sync for Ultra-Low Latency Rendering
///
/// This plugin provides frame-synchronized callbacks for smooth 120Hz rendering on ProMotion displays.
/// It sends timing signals to Flutter so the app can render exactly when the display refreshes.
///
/// Benefits:
/// - Eliminates tearing and stutter
/// - Syncs with 120Hz ProMotion displays (iPad Pro)
/// - Reduces input-to-screen latency by rendering at optimal times
public class DisplayLinkPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    
    // MARK: - Properties
    
    private var eventSink: FlutterEventSink?
    private var displayLink: CADisplayLink?
    private var isEnabled: Bool = false
    private var lastTimestamp: CFTimeInterval = 0
    
    // MARK: - Plugin Registration
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = DisplayLinkPlugin()
        instance.setupChannels(messenger: registrar.messenger())
        registrar.addMethodCallDelegate(instance, channel: instance.methodChannel!)
        ()
    }

    public static func register(with messenger: FlutterBinaryMessenger) {
        let instance = DisplayLinkPlugin()
        instance.setupChannels(messenger: messenger)
        instance.methodChannel?.setMethodCallHandler(instance.handle)
        ()
    }

    private var methodChannel: FlutterMethodChannel?

    private func setupChannels(messenger: FlutterBinaryMessenger) {
        // EventChannel for frame timing
        let eventChannel = FlutterEventChannel(
            name: "com.flueraengine/display_link",
            binaryMessenger: messenger
        )
        eventChannel.setStreamHandler(self)
        
        // MethodChannel for control
        methodChannel = FlutterMethodChannel(
            name: "com.flueraengine/display_link_control",
            binaryMessenger: messenger
        )
    }
    
    // MARK: - FlutterStreamHandler
    
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        startDisplayLink()
        ()
        return nil
    }
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        stopDisplayLink()
        ()
        return nil
    }
    
    // MARK: - CADisplayLink Management
    
    private func startDisplayLink() {
        guard displayLink == nil else { return }
        
        displayLink = CADisplayLink(target: self, selector: #selector(handleDisplayLink(_:)))
        
        // Request highest frame rate (ProMotion 120Hz if available)
        if #available(iOS 15.0, *) {
            displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        } else if #available(iOS 10.0, *) {
            displayLink?.preferredFramesPerSecond = 0 // Let system choose best rate
        }
        
        displayLink?.add(to: .current, forMode: .common)
        isEnabled = true
        
        ()
    }
    
    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        isEnabled = false
        ()
    }
    
    @objc private func handleDisplayLink(_ displayLink: CADisplayLink) {
        guard let sink = eventSink else { return }
        
        let timestamp = displayLink.timestamp
        let targetTimestamp = displayLink.targetTimestamp
        let duration = displayLink.duration
        
        // Calculate frame info
        let deltaTime = timestamp - lastTimestamp
        lastTimestamp = timestamp
        
        // Get actual frame rate
        var frameRate: Double = 60.0
        if #available(iOS 15.0, *) {
            let nextFrameDuration = targetTimestamp - timestamp
            if nextFrameDuration > 0 {
                frameRate = 1.0 / nextFrameDuration
            }
        } else {
            frameRate = 1.0 / duration
        }
        
        // Send frame timing to Flutter
        let frameInfo: [String: Any] = [
            "timestamp": Int(timestamp * 1000),
            "targetTimestamp": Int(targetTimestamp * 1000),
            "deltaTime": deltaTime * 1000,
            "frameRate": frameRate,
            "isProMotion": frameRate > 65
        ]
        
        sink(frameInfo)
    }
}

// MARK: - MethodChannel Handler

extension DisplayLinkPlugin {
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isProMotionSupported":
            var isSupported = false
            if #available(iOS 15.0, *) {
                let maxFrameRate = UIScreen.main.maximumFramesPerSecond
                isSupported = maxFrameRate >= 120
            }
            result(isSupported)
            
        case "getMaxFrameRate":
            let maxFrameRate = UIScreen.main.maximumFramesPerSecond
            result(maxFrameRate)
            
        case "start":
            startDisplayLink()
            result(nil)
            
        case "stop":
            stopDisplayLink()
            result(nil)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
