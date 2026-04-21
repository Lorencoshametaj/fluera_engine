import Flutter
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// PredictedTouchPlugin - Native Apple Pencil / touch sample capture.
///
/// Exposes coalesced (ground-truth ~240 Hz on ProMotion) and predicted
/// (look-ahead) UITouch samples to Flutter via EventChannel, so the Dart
/// stroke pipeline isn't limited to the ~120 Hz rate of Flutter PointerEvents.
///
/// Two UIKit pieces work together:
///   - TouchOverlayView: transparent sibling used only for UIHoverGestureRecognizer
///     (Apple Pencil hover). It stays touch-transparent.
///   - PredictiveTouchGestureRecognizer: installed on FlutterViewController.view
///     with cancelsTouchesInView=false. It observes touches without consuming
///     them, so Flutter still receives its normal PointerEvents.
public class PredictedTouchPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

    // MARK: - Properties

    private var eventSink: FlutterEventSink?
    private var overlayView: TouchOverlayView?
    private var touchRecognizer: PredictiveTouchGestureRecognizer?
    private weak var flutterViewController: FlutterViewController?

    // MARK: - Plugin Registration

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = PredictedTouchPlugin()
        instance.setupChannels(messenger: registrar.messenger())
        instance.methodChannel?.setMethodCallHandler(instance.handle)
    }

    public static func register(with messenger: FlutterBinaryMessenger) {
        let instance = PredictedTouchPlugin()
        instance.setupChannels(messenger: messenger)
        instance.methodChannel?.setMethodCallHandler(instance.handle)
    }

    private var methodChannel: FlutterMethodChannel?

    private func setupChannels(messenger: FlutterBinaryMessenger) {
        let eventChannel = FlutterEventChannel(
            name: "com.flueraengine/predicted_touches",
            binaryMessenger: messenger
        )
        eventChannel.setStreamHandler(self)

        methodChannel = FlutterMethodChannel(
            name: "com.flueraengine/predicted_touches_control",
            binaryMessenger: messenger
        )
    }

    // MARK: - FlutterStreamHandler

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        installOnFlutterView()
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        uninstallFromFlutterView()
        return nil
    }

    // MARK: - Install / uninstall

    private func installOnFlutterView() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            guard let window = UIApplication.shared.windows.first(where: { $0.isKeyWindow }),
                  let rootVC = window.rootViewController else {
                return
            }

            var vc: UIViewController? = rootVC
            while let current = vc {
                if let flutterVC = current as? FlutterViewController {
                    self.flutterViewController = flutterVC
                    break
                }
                vc = current.presentedViewController ?? current.children.first
            }

            guard let flutterVC = self.flutterViewController else { return }

            // Hover overlay (touch-transparent; covers the full Flutter view).
            let overlay = TouchOverlayView(frame: flutterVC.view.bounds)
            overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            overlay.onHoverUpdate = { [weak self] hoverInfo in
                self?.sendHoverEvent(hoverInfo)
            }
            flutterVC.view.addSubview(overlay)
            self.overlayView = overlay

            // Passive touch recognizer on the Flutter view itself.
            let recognizer = PredictiveTouchGestureRecognizer(target: nil, action: nil)
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
            recognizer.requiresExclusiveTouchType = false
            recognizer.onSamples = { [weak self] points in
                self?.sendSamples(points)
            }
            flutterVC.view.addGestureRecognizer(recognizer)
            self.touchRecognizer = recognizer
        }
    }

    private func uninstallFromFlutterView() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.overlayView?.removeFromSuperview()
            self.overlayView = nil
            if let r = self.touchRecognizer, let view = r.view {
                view.removeGestureRecognizer(r)
            }
            self.touchRecognizer = nil
        }
    }

    // MARK: - Send to Flutter

    private func sendSamples(_ points: [[String: Any]]) {
        guard let sink = eventSink, !points.isEmpty else { return }
        sink(["predicted_points": points])
    }

    private func sendHoverEvent(_ hoverInfo: [String: Any]) {
        guard let sink = eventSink else { return }
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
            installOnFlutterView()
            result(nil)
        case "disable":
            uninstallFromFlutterView()
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}

// MARK: - Hover overlay (touch-transparent)

/// Transparent UIView used only for UIHoverGestureRecognizer (Apple Pencil
/// hover). Does NOT consume touches — hitTest returns nil so Flutter receives
/// PointerEvents normally. Touch ingestion happens via
/// PredictiveTouchGestureRecognizer on the FlutterViewController.view.
private class TouchOverlayView: UIView {

    var onHoverUpdate: (([String: Any]) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.isMultipleTouchEnabled = true
        self.backgroundColor = .clear
        self.isUserInteractionEnabled = true

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

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        return nil
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        return false
    }
}

// MARK: - Passive touch recognizer

/// Observes UITouches on a view without consuming them. For each phase we
/// drain `event.coalescedTouches(for:)` (ground-truth ~240 Hz samples on
/// ProMotion) and `event.predictedTouches(for:)` (extrapolated anti-lag) and
/// forward them to Flutter. Never transitions to .recognized, so downstream
/// Flutter gesture handling is unaffected.
private class PredictiveTouchGestureRecognizer: UIGestureRecognizer {

    var onSamples: (([[String: Any]]) -> Void)?

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        // Never "win" gesture arbitration; we just observe.
        self.cancelsTouchesInView = false
        self.delaysTouchesBegan = false
        self.delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard let touch = touches.first else { return }
        emit(touch: touch, event: event, phase: "began", markLastAsFinal: false)
        // Stay in .possible so we never consume the gesture stream.
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard let touch = touches.first else { return }
        emit(touch: touch, event: event, phase: "moved", markLastAsFinal: false)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        guard let touch = touches.first else { return }
        emit(touch: touch, event: event, phase: "ended", markLastAsFinal: true)
        self.state = .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        guard let touch = touches.first else { return }
        emit(touch: touch, event: event, phase: "cancelled", markLastAsFinal: true)
        self.state = .failed
    }

    override func reset() {
        super.reset()
    }

    // MARK: - Helpers

    private func emit(
        touch: UITouch,
        event: UIEvent,
        phase: String,
        markLastAsFinal: Bool
    ) {
        guard let view = self.view else { return }
        let touchType = touchTypeString(for: touch)

        var out: [[String: Any]] = []

        // Coalesced (ground-truth samples delivered as a batch; the last one
        // is numerically identical to the primary `touch`).
        if let coalesced = event.coalescedTouches(for: touch), !coalesced.isEmpty {
            for (idx, ct) in coalesced.enumerated() {
                let loc = ct.location(in: view)
                let isLast = idx == coalesced.count - 1
                let maxForce = ct.maximumPossibleForce > 0 ? ct.maximumPossibleForce : 1.0
                out.append([
                    "x": Double(loc.x),
                    "y": Double(loc.y),
                    "pressure": Double(ct.force / maxForce),
                    "timestamp": Int(ct.timestamp * 1000),
                    "isPredicted": false,
                    "phase": phase,
                    "isFinal": markLastAsFinal && isLast,
                    "touchType": touchType
                ])
            }
        } else {
            // Fallback: no coalesced set available, use the primary touch.
            let loc = touch.location(in: view)
            let maxForce = touch.maximumPossibleForce > 0 ? touch.maximumPossibleForce : 1.0
            out.append([
                "x": Double(loc.x),
                "y": Double(loc.y),
                "pressure": Double(touch.force / maxForce),
                "timestamp": Int(touch.timestamp * 1000),
                "isPredicted": false,
                "phase": phase,
                "isFinal": markLastAsFinal,
                "touchType": touchType
            ])
        }

        // Predicted (only during moves — iOS doesn't predict at began/ended).
        if phase == "moved", let predicted = event.predictedTouches(for: touch) {
            for pt in predicted {
                let loc = pt.location(in: view)
                let maxForce = pt.maximumPossibleForce > 0 ? pt.maximumPossibleForce : 1.0
                out.append([
                    "x": Double(loc.x),
                    "y": Double(loc.y),
                    "pressure": Double(pt.force / maxForce),
                    "timestamp": Int(pt.timestamp * 1000),
                    "isPredicted": true,
                    "phase": phase,
                    "isFinal": false,
                    "touchType": touchType
                ])
            }
        }

        if !out.isEmpty {
            onSamples?(out)
        }
    }

    private func touchTypeString(for touch: UITouch) -> String {
        switch touch.type {
        case .pencil: return "pencil"
        case .direct: return "finger"
        case .indirect: return "indirect"
        case .indirectPointer: return "indirect"
        @unknown default: return "finger"
        }
    }
}
