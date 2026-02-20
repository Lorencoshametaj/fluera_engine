import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import '../core/engine_scope.dart';
import '../core/engine_error.dart';

/// 📊 NativePerformanceMonitor — Cross-Platform Performance Metrics
///
/// Provides unified access to native performance data across iOS and Android:
/// - **Memory**: Used/total/available RAM, heap info, pressure level
/// - **Thermal**: Thermal throttle state (nominal → critical)
/// - **Battery**: Level, charging state, low power mode
///
/// Supports two usage modes:
/// 1. **One-shot**: `getSnapshot()` for immediate metrics
/// 2. **Continuous**: `metricsStream` for periodic sampling
///
/// Usage:
/// ```dart
/// final monitor = NativePerformanceMonitor.instance;
/// await monitor.initialize();
///
/// // One-shot
/// final snapshot = await monitor.getSnapshot();
/// print('Memory: ${snapshot.memoryUsedMB}MB / ${snapshot.memoryTotalMB}MB');
/// print('Thermal: ${snapshot.thermalState}');
///
/// // Continuous (every 2 seconds)
/// await monitor.startMonitoring(intervalMs: 2000);
/// monitor.metricsStream.listen((metrics) {
///   if (metrics.memoryPressureLevel == 'critical') {
///     // Reduce quality settings
///   }
/// });
/// ```
class NativePerformanceMonitor {
  /// Legacy singleton accessor — delegates to [EngineScope.current].
  static NativePerformanceMonitor get instance =>
      EngineScope.current.performanceMonitor;

  /// Creates a new instance (used by [EngineScope]).
  NativePerformanceMonitor.create();

  // ═══════════════════════════════════════════════════════════════════════════
  // CHANNELS
  // ═══════════════════════════════════════════════════════════════════════════

  static const MethodChannel _methodChannel = MethodChannel(
    'com.nebulaengine/performance_monitor_control',
  );
  static const EventChannel _eventChannel = EventChannel(
    'com.nebulaengine/performance_monitor',
  );

  // ═══════════════════════════════════════════════════════════════════════════
  // STATE
  // ═══════════════════════════════════════════════════════════════════════════

  final StreamController<PerformanceMetrics> _metricsController =
      StreamController<PerformanceMetrics>.broadcast();

  StreamSubscription<dynamic>? _eventSubscription;
  bool _isInitialized = false;
  bool _isMonitoring = false;
  PerformanceCapabilities? _capabilities;

  /// Stream of performance metrics from periodic sampling
  Stream<PerformanceMetrics> get metricsStream => _metricsController.stream;

  /// Whether the service is initialized
  bool get isInitialized => _isInitialized;

  /// Whether continuous monitoring is active
  bool get isMonitoring => _isMonitoring;

  /// Device performance capabilities (null until initialized)
  PerformanceCapabilities? get capabilities => _capabilities;

  // ═══════════════════════════════════════════════════════════════════════════
  // INITIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Initialize the performance monitor.
  /// Detects platform capabilities.
  Future<void> initialize() async {
    if (_isInitialized) return;

    if (!Platform.isIOS && !Platform.isAndroid) {
      _isInitialized = true;
      return;
    }

    try {
      final capsMap = await _methodChannel.invokeMethod<Map>('getCapabilities');
      if (capsMap != null) {
        _capabilities = PerformanceCapabilities(
          hasMemoryMonitoring: capsMap['hasMemoryMonitoring'] as bool? ?? false,
          hasThermalMonitoring:
              capsMap['hasThermalMonitoring'] as bool? ?? false,
          hasBatteryMonitoring:
              capsMap['hasBatteryMonitoring'] as bool? ?? false,
          hasGPUMonitoring: capsMap['hasGPUMonitoring'] as bool? ?? false,
          platform: capsMap['platform'] as String? ?? 'unknown',
          osVersion: capsMap['osVersion'] as String?,
          deviceModel: capsMap['deviceModel'] as String?,
        );
      }

      // Subscribe to event channel
      _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
        _handleEvent,
        onError: (e) {
          EngineScope.current.errorRecovery.reportError(
            EngineError(
              severity: ErrorSeverity.transient,
              domain: ErrorDomain.platform,
              source: 'NativePerformanceMonitor.eventStream',
              original: e,
            ),
          );
        },
      );

      _isInitialized = true;
    } catch (e, stack) {
      EngineScope.current.errorRecovery.reportError(
        EngineError(
          severity: ErrorSeverity.degraded,
          domain: ErrorDomain.platform,
          source: 'NativePerformanceMonitor.initialize',
          original: e,
          stack: stack,
        ),
      );
      _isInitialized = true;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MONITORING CONTROL
  // ═══════════════════════════════════════════════════════════════════════════

  /// Start continuous metric sampling.
  /// [intervalMs] — sampling interval in milliseconds (min: 100ms).
  Future<void> startMonitoring({int intervalMs = 1000}) async {
    if (!_isInitialized || _isMonitoring) return;

    try {
      await _methodChannel.invokeMethod('startMonitoring', {
        'intervalMs': intervalMs,
      });
      _isMonitoring = true;
    } catch (e, stack) {
      EngineScope.current.errorRecovery.reportError(
        EngineError(
          severity: ErrorSeverity.transient,
          domain: ErrorDomain.platform,
          source: 'NativePerformanceMonitor.startMonitoring',
          original: e,
          stack: stack,
        ),
      );
    }
  }

  /// Stop continuous metric sampling.
  Future<void> stopMonitoring() async {
    if (!_isMonitoring) return;

    try {
      await _methodChannel.invokeMethod('stopMonitoring');
      _isMonitoring = false;
    } catch (e, stack) {
      EngineScope.current.errorRecovery.reportError(
        EngineError(
          severity: ErrorSeverity.transient,
          domain: ErrorDomain.platform,
          source: 'NativePerformanceMonitor.stopMonitoring',
          original: e,
          stack: stack,
        ),
      );
    }
  }

  /// Get a single performance snapshot.
  Future<PerformanceMetrics?> getSnapshot() async {
    if (!_isInitialized) return null;

    try {
      final data = await _methodChannel.invokeMethod<Map>('getSnapshot');
      if (data != null) {
        return _parseMetrics(data);
      }
    } catch (e, stack) {
      EngineScope.current.errorRecovery.reportError(
        EngineError(
          severity: ErrorSeverity.transient,
          domain: ErrorDomain.platform,
          source: 'NativePerformanceMonitor.getSnapshot',
          original: e,
          stack: stack,
        ),
      );
    }
    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EVENT HANDLING
  // ═══════════════════════════════════════════════════════════════════════════

  void _handleEvent(dynamic event) {
    if (event == null || event is! Map) return;
    final metrics = _parseMetrics(event);
    _metricsController.add(metrics);
  }

  PerformanceMetrics _parseMetrics(Map<dynamic, dynamic> data) {
    return PerformanceMetrics(
      timestamp:
          (data['timestamp'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
      platform: data['platform'] as String? ?? 'unknown',
      // Memory
      memoryUsedMB: (data['memoryUsedMB'] as num?)?.toDouble() ?? -1.0,
      memoryTotalMB: (data['memoryTotalMB'] as num?)?.toDouble() ?? -1.0,
      memoryAvailableMB: (data['memoryAvailableMB'] as num?)?.toDouble(),
      memoryUsagePercent:
          (data['memoryUsagePercent'] as num?)?.toDouble() ?? -1.0,
      memoryPressureLevel: data['memoryPressureLevel'] as String? ?? 'unknown',
      // Thermal
      thermalState: data['thermalState'] as String? ?? 'unknown',
      thermalThrottled: data['thermalThrottled'] as bool? ?? false,
      // Battery
      batteryLevel: (data['batteryLevel'] as num?)?.toDouble() ?? -1.0,
      batteryState: data['batteryState'] as String? ?? 'unknown',
      isLowPowerMode: data['isLowPowerMode'] as bool? ?? false,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CLEANUP
  // ═══════════════════════════════════════════════════════════════════════════

  void dispose() {
    stopMonitoring();
    _eventSubscription?.cancel();
    _metricsController.close();
    _isInitialized = false;
  }

  /// Reset all state for testing.
  void resetForTesting() {
    _eventSubscription?.cancel();
    _eventSubscription = null;
    _isInitialized = false;
    _isMonitoring = false;
    _capabilities = null;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// DATA MODELS
// ═══════════════════════════════════════════════════════════════════════════

/// A snapshot of performance metrics from the native platform.
class PerformanceMetrics {
  final int timestamp;
  final String platform;

  // Memory
  final double memoryUsedMB;
  final double memoryTotalMB;
  final double? memoryAvailableMB;
  final double memoryUsagePercent;
  final String memoryPressureLevel;

  // Thermal
  final String thermalState;
  final bool thermalThrottled;

  // Battery
  final double batteryLevel;
  final String batteryState;
  final bool isLowPowerMode;

  const PerformanceMetrics({
    required this.timestamp,
    required this.platform,
    required this.memoryUsedMB,
    required this.memoryTotalMB,
    this.memoryAvailableMB,
    required this.memoryUsagePercent,
    required this.memoryPressureLevel,
    required this.thermalState,
    required this.thermalThrottled,
    required this.batteryLevel,
    required this.batteryState,
    required this.isLowPowerMode,
  });

  /// Whether the device is under memory pressure
  bool get isMemoryWarning =>
      memoryPressureLevel == 'warning' || memoryPressureLevel == 'critical';

  /// Whether thermal throttling is reducing performance
  bool get isThermalWarning =>
      thermalState == 'serious' || thermalState == 'critical';

  /// Whether adaptive quality reduction should be triggered
  bool get shouldReduceQuality =>
      isMemoryWarning || isThermalWarning || isLowPowerMode;

  @override
  String toString() =>
      'PerformanceMetrics('
      'mem: ${memoryUsedMB.toStringAsFixed(0)}/${memoryTotalMB.toStringAsFixed(0)}MB '
      '[${memoryPressureLevel}], '
      'thermal: $thermalState, '
      'battery: ${batteryLevel.toStringAsFixed(0)}% [$batteryState]'
      '${isLowPowerMode ? " LOW_POWER" : ""}'
      ')';
}

/// Device performance monitoring capabilities.
class PerformanceCapabilities {
  final bool hasMemoryMonitoring;
  final bool hasThermalMonitoring;
  final bool hasBatteryMonitoring;
  final bool hasGPUMonitoring;
  final String platform;
  final String? osVersion;
  final String? deviceModel;

  const PerformanceCapabilities({
    required this.hasMemoryMonitoring,
    required this.hasThermalMonitoring,
    required this.hasBatteryMonitoring,
    required this.hasGPUMonitoring,
    required this.platform,
    this.osVersion,
    this.deviceModel,
  });

  @override
  String toString() =>
      'PerformanceCapabilities(platform: $platform, '
      'memory: $hasMemoryMonitoring, thermal: $hasThermalMonitoring, '
      'battery: $hasBatteryMonitoring, gpu: $hasGPUMonitoring'
      '${deviceModel != null ? ', device: $deviceModel' : ''})';
}
