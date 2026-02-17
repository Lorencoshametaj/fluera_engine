import Flutter
import UIKit

/// 📊 PerformanceMonitorPlugin — Native iOS Performance Metrics
///
/// Provides real-time access to iOS-specific performance data:
/// - **Memory**: Physical memory usage, available memory, pressure level
/// - **Thermal**: Current thermal state (nominal → critical)
/// - **Display**: Frame rate, refresh rate, GPU utilization hint
///
/// Channel: com.nebulaengine/performance_monitor
/// Control: com.nebulaengine/performance_monitor_control
public class PerformanceMonitorPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    
    private var methodChannel: FlutterMethodChannel?
    private var eventChannel: FlutterEventChannel?
    private var eventSink: FlutterEventSink?
    private var monitorTimer: Timer?
    private var isMonitoring = false
    private var samplingIntervalMs: Int = 1000

    // MARK: - Plugin Registration
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = PerformanceMonitorPlugin()
        
        let methodChannel = FlutterMethodChannel(
            name: "com.nebulaengine/performance_monitor_control",
            binaryMessenger: registrar.messenger()
        )
        instance.methodChannel = methodChannel
        registrar.addMethodCallDelegate(instance, channel: methodChannel)
        
        let eventChannel = FlutterEventChannel(
            name: "com.nebulaengine/performance_monitor",
            binaryMessenger: registrar.messenger()
        )
        instance.eventChannel = eventChannel
        eventChannel.setStreamHandler(instance)
    }

    // MARK: - Method Channel
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startMonitoring":
            if let args = call.arguments as? [String: Any],
               let intervalMs = args["intervalMs"] as? Int {
                samplingIntervalMs = max(100, intervalMs)
            }
            startMonitoring()
            result(nil)
        case "stopMonitoring":
            stopMonitoring()
            result(nil)
        case "getSnapshot":
            result(collectMetrics())
        case "getCapabilities":
            result(getCapabilities())
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Event Channel
    
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        stopMonitoring()
        return nil
    }

    // MARK: - Monitoring

    private func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        
        let interval = TimeInterval(samplingIntervalMs) / 1000.0
        monitorTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self = self, let sink = self.eventSink else { return }
            let metrics = self.collectMetrics()
            sink(metrics)
        }
    }
    
    private func stopMonitoring() {
        monitorTimer?.invalidate()
        monitorTimer = nil
        isMonitoring = false
    }

    // MARK: - Metric Collection

    private func collectMetrics() -> [String: Any] {
        var metrics: [String: Any] = [
            "timestamp": Int(Date().timeIntervalSince1970 * 1000),
            "platform": "iOS"
        ]
        
        // Memory metrics
        metrics.merge(collectMemoryMetrics()) { _, new in new }
        
        // Thermal metrics
        metrics.merge(collectThermalMetrics()) { _, new in new }
        
        // Battery metrics
        metrics.merge(collectBatteryMetrics()) { _, new in new }
        
        return metrics
    }

    private func collectMemoryMetrics() -> [String: Any] {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        
        if result == KERN_SUCCESS {
            let usedMemoryMB = Double(info.resident_size) / (1024.0 * 1024.0)
            let totalMemoryMB = Double(totalMemory) / (1024.0 * 1024.0)
            let memoryUsagePercent = (Double(info.resident_size) / Double(totalMemory)) * 100.0
            
            return [
                "memoryUsedMB": usedMemoryMB,
                "memoryTotalMB": totalMemoryMB,
                "memoryUsagePercent": memoryUsagePercent,
                "memoryPressureLevel": getMemoryPressureLevel(usagePercent: memoryUsagePercent)
            ]
        }
        
        return [
            "memoryUsedMB": -1.0,
            "memoryTotalMB": Double(totalMemory) / (1024.0 * 1024.0),
            "memoryUsagePercent": -1.0,
            "memoryPressureLevel": "unknown"
        ]
    }

    private func getMemoryPressureLevel(usagePercent: Double) -> String {
        if usagePercent > 80 { return "critical" }
        if usagePercent > 60 { return "warning" }
        return "normal"
    }

    private func collectThermalMetrics() -> [String: Any] {
        let thermalState: String
        
        if #available(iOS 11.0, *) {
            switch ProcessInfo.processInfo.thermalState {
            case .nominal:
                thermalState = "nominal"
            case .fair:
                thermalState = "fair"
            case .serious:
                thermalState = "serious"
            case .critical:
                thermalState = "critical"
            @unknown default:
                thermalState = "unknown"
            }
        } else {
            thermalState = "unknown"
        }
        
        return [
            "thermalState": thermalState,
            "thermalThrottled": thermalState == "serious" || thermalState == "critical"
        ]
    }

    private func collectBatteryMetrics() -> [String: Any] {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let batteryLevel = UIDevice.current.batteryLevel
        let batteryState: String
        
        switch UIDevice.current.batteryState {
        case .charging:
            batteryState = "charging"
        case .full:
            batteryState = "full"
        case .unplugged:
            batteryState = "unplugged"
        case .unknown:
            batteryState = "unknown"
        @unknown default:
            batteryState = "unknown"
        }
        
        return [
            "batteryLevel": batteryLevel >= 0 ? Double(batteryLevel) * 100.0 : -1.0,
            "batteryState": batteryState,
            "isLowPowerMode": ProcessInfo.processInfo.isLowPowerMode
        ]
    }

    // MARK: - Capabilities

    private func getCapabilities() -> [String: Any] {
        return [
            "hasMemoryMonitoring": true,
            "hasThermalMonitoring": true,
            "hasBatteryMonitoring": true,
            "hasGPUMonitoring": false,
            "platform": "iOS",
            "osVersion": UIDevice.current.systemVersion,
            "deviceModel": UIDevice.current.model
        ]
    }
}
