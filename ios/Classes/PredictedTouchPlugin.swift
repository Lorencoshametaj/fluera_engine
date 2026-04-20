import Flutter
import UIKit

/// 🚀 PredictedTouchPlugin - Native Predicted Touches for Low-Latency Drawing
///
/// This plugin exposes iOS's native predicted touches to Flutter via EventChannel.
/// iOS predicts 2-3 touch points ahead using velocity and direction analysis,
/// reducing perceived latency by ~15-20ms.
///
/// Usage:
/// - Flutter subscribes to EventChannel "predicted_touches"
/// - Plugin sends predicted touch points as events
/// - DrawingInputHandler uses predicted points for anti-lag rendering
public class PredictedTouchPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    
    // MARK: - Properties
    
    private var eventSink: FlutterEventSink?
    private var overlayView: TouchOverlayView?
    private weak var flutterViewController: FlutterViewController?
    
    // MARK: - Plugin Registration
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = PredictedTouchPlugin()
        instance.setupChannels(messenger: registrar.messenger())
        instance.methodChannel?.setMethodCallHandler(instance.handle)
        ()
    }

    public static func register(with messenger: FlutterBinaryMessenger) {
        let instance = PredictedTouchPlugin()
        instance.setupChannels(messenger: messenger)
        instance.methodChannel?.setMethodCallHandler(instance.handle)
        ()
    }

    private var methodChannel: FlutterMethodChannel?

    private func setupChannels(messenger: FlutterBinaryMessenger) {
        // EventChannel for streaming predicted touches
        let eventChannel = FlutterEventChannel(
            name: "com.flueraengine/predicted_touches",
            binaryMessenger: messenger
        )
        eventChannel.setStreamHandler(self)
        
        // MethodChannel for control
        methodChannel = FlutterMethodChannel(
            name: "com.flueraengine/predicted_touches_control",
            binaryMessenger: messenger
        )
    }
    
    // MARK: - FlutterStreamHandler
    
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        setupOverlayView()
        ()
        return nil
    }
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        removeOverlayView()
        ()
        return nil
    }
    
    // MARK: - Overlay View Setup
    
    private func setupOverlayView() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Find FlutterViewController
            guard let window = UIApplication.shared.windows.first(where: { $0.isKeyWindow }),
                  let rootVC = window.rootViewController else {
                ()
                return
            }
            
            // Find FlutterViewController in the hierarchy
            var vc: UIViewController? = rootVC
            while let current = vc {
                if let flutterVC = current as? FlutterViewController {
                    self.flutterViewController = flutterVC
                    break
                }
                vc = current.presentedViewController ?? current.children.first
            }
            
            guard let flutterVC = self.flutterViewController else {
                ()
                return
            }
            
            let overlay = TouchOverlayView(frame: flutterVC.view.bounds)
            overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            overlay.onPredictedTouches = { [weak self] points in
                self?.sendPredictedTouches(points)
            }
            overlay.onHoverUpdate = { [weak self] hoverInfo in
                self?.sendHoverEvent(hoverInfo)
            }
            
            flutterVC.view.addSubview(overlay)
            self.overlayView = overlay
            ()
        }
    }
    
    private func removeOverlayView() {
        DispatchQueue.main.async { [weak self] in
            self?.overlayView?.removeFromSuperview()
            self?.overlayView = nil
            ()
        }
    }
    
    // MARK: - Send Predicted Touches to Flutter
    
    private func sendPredictedTouches(_ points: [[String: Any]]) {
        guard let sink = eventSink, !points.isEmpty else { return }
        
        // Send as batch for efficiency
        sink(["predicted_points": points])
    }
    
    private func sendHoverEvent(_ hoverInfo: [String: Any]) {
        guard let sink = eventSink else { return }
        
        // Send hover event with type marker
        sink(["hover_event": hoverInfo])
    }
}

// MARK: - MethodChannel Handler

extension PredictedTouchPlugin {
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isSupported":
            result(true)
            
        case "isPredictionSupported":
            result(true)
            
        case "enable":
            setupOverlayView()
            result(nil)
            
        case "disable":
            removeOverlayView()
            result(nil)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}

// MARK: - Touch Overlay View

/// Transparent UIView that captures touches and extracts predicted points
private class TouchOverlayView: UIView {
    
    var onPredictedTouches: (([[String: Any]]) -> Void)?
    var onHoverUpdate: (([String: Any]) -> Void)?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        // Allow touches to pass through to Flutter
        self.isMultipleTouchEnabled = true
        self.backgroundColor = .clear
        self.isUserInteractionEnabled = true
        
        // Add hover gesture recognizer for Apple Pencil
        if #available(iOS 16.0, *) {
            let hoverGesture = UIHoverGestureRecognizer(target: self, action: #selector(handleHover(_:)))
            self.addGestureRecognizer(hoverGesture)
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @available(iOS 16.0, *)
    @objc private func handleHover(_ gesture: UIHoverGestureRecognizer) {
        let location = gesture.location(in: self)
        
        // Get altitude angle (how close to screen: 0 = touching, π/2 = parallel)
        var altitude: Double = 0.0
        if #available(iOS 16.4, *) {
            altitude = gesture.altitudeAngle
        }
        
        switch gesture.state {
        case .began, .changed:
            let hoverInfo: [String: Any] = [
                "x": Double(location.x),
                "y": Double(location.y),
                "state": gesture.state == .began ? "began" : "changed",
                "isHovering": true,
                "altitude": altitude
            ]
            onHoverUpdate?(hoverInfo)
            
        case .ended, .cancelled:
            let hoverInfo: [String: Any] = [
                "x": Double(location.x),
                "y": Double(location.y),
                "state": "ended",
                "isHovering": false
            ]
            onHoverUpdate?(hoverInfo)
        default:
            break
        }
    }
    
    // MARK: - Touch Handling
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Pass touches to Flutter's view
        super.touchesMoved(touches, with: event)
        
        guard let touch = touches.first, let event = event else { return }
        
        var predictedPoints: [[String: Any]] = []
        
        // Extract predicted touches (iOS native)
        if let predictedTouches = event.predictedTouches(for: touch) {
            for predictedTouch in predictedTouches {
                let location = predictedTouch.location(in: self)
                
                let point: [String: Any] = [
                    "x": Double(location.x),
                    "y": Double(location.y),
                    "pressure": Double(predictedTouch.force / predictedTouch.maximumPossibleForce),
                    "timestamp": Int(predictedTouch.timestamp * 1000),
                    "isPredicted": true
                ]
                predictedPoints.append(point)
            }
        }
        
        // Also include coalesced touches for better accuracy
        if let coalescedTouches = event.coalescedTouches(for: touch) {
            for coalescedTouch in coalescedTouches {
                let location = coalescedTouch.location(in: self)
                
                let point: [String: Any] = [
                    "x": Double(location.x),
                    "y": Double(location.y),
                    "pressure": Double(coalescedTouch.force / coalescedTouch.maximumPossibleForce),
                    "timestamp": Int(coalescedTouch.timestamp * 1000),
                    "isPredicted": false
                ]
                predictedPoints.append(point)
            }
        }
        
        onPredictedTouches?(predictedPoints)
    }
    
    // MARK: - Hit Testing
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // 🔴 CRITICAL: Return nil to let touches pass through to Flutter
        // We capture touches in touchesMoved but don't consume them
        return nil
    }
    
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        // We want to observe all touches but not block them
        return false
    }
}
