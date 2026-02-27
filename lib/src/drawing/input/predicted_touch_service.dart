import 'dart:async';
import '../../utils/platform_guard.dart';
import 'package:flutter/services.dart';
import '../../core/engine_scope.dart';
import '../../core/engine_error.dart';

/// 🚀 PredictedTouchService - Native Predicted Touches for Low-Latency Drawing
///
/// This service consumes iOS native predicted touches via EventChannel.
/// iOS predicts 2-3 touch points ahead using velocity and direction analysis,
/// reducing perceived latency by ~15-20ms.
///
/// Usage:
/// ```dart
/// final service = PredictedTouchService();
/// await service.initialize();
///
/// service.predictedTouchStream.listen((points) {
///   // Use predicted points for anti-lag rendering
/// });
/// ```
class PredictedTouchService {
  /// Legacy singleton accessor — delegates to [EngineScope.current].
  static PredictedTouchService get instance =>
      EngineScope.current.predictedTouchService;

  /// Creates a new instance (used by [EngineScope]).
  PredictedTouchService.create();

  // EventChannel for receiving predicted touches from native
  static const EventChannel _eventChannel = EventChannel(
    'com.flueraengine/predicted_touches',
  );

  // MethodChannel for control
  static const MethodChannel _methodChannel = MethodChannel(
    'com.flueraengine/predicted_touches_control',
  );

  // Stream controller for predicted touches
  final StreamController<List<PredictedTouchPoint>> _predictedTouchController =
      StreamController<List<PredictedTouchPoint>>.broadcast();

  // Subscription to native events
  StreamSubscription<dynamic>? _eventSubscription;

  // State
  bool _isInitialized = false;
  bool _isSupported = false;

  /// Stream of predicted touch points from native iOS
  Stream<List<PredictedTouchPoint>> get predictedTouchStream =>
      _predictedTouchController.stream;

  /// Whether the service is initialized
  bool get isInitialized => _isInitialized;

  /// Whether predicted touches are supported on this platform
  bool get isSupported => _isSupported;

  /// Initialize the service
  Future<void> initialize() async {
    if (_isInitialized) return;

    // Supported on iOS and Android
    if (!PlatformGuard.isIOS && !PlatformGuard.isAndroid) {
      _isSupported = false;
      _isInitialized = true;
      return;
    }

    try {
      // Check if native predicted touches are supported
      final supported =
          await _methodChannel.invokeMethod<bool>('isSupported') ?? false;
      _isSupported = supported;

      if (_isSupported) {
        // Subscribe to native event channel
        _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
          _handleNativeEvent,
          onError: _handleError,
        );

        final platform = PlatformGuard.isIOS ? 'iOS' : 'Android';
      } else {}

      _isInitialized = true;
    } catch (e, stack) {
      EngineScope.current.errorRecovery.reportError(
        EngineError(
          severity: ErrorSeverity.degraded,
          domain: ErrorDomain.platform,
          source: 'PredictedTouchService.initialize',
          original: e,
          stack: stack,
        ),
      );
      _isSupported = false;
      _isInitialized = true;
    }
  }

  /// Enable predicted touch capture
  Future<void> enable() async {
    if (!_isSupported) return;

    try {
      await _methodChannel.invokeMethod('enable');
    } catch (e, stack) {
      EngineScope.current.errorRecovery.reportError(
        EngineError(
          severity: ErrorSeverity.transient,
          domain: ErrorDomain.platform,
          source: 'PredictedTouchService.enable',
          original: e,
          stack: stack,
        ),
      );
    }
  }

  /// Disable predicted touch capture
  Future<void> disable() async {
    if (!_isSupported) return;

    try {
      await _methodChannel.invokeMethod('disable');
    } catch (e, stack) {
      EngineScope.current.errorRecovery.reportError(
        EngineError(
          severity: ErrorSeverity.transient,
          domain: ErrorDomain.platform,
          source: 'PredictedTouchService.disable',
          original: e,
          stack: stack,
        ),
      );
    }
  }

  /// Handle native events from iOS
  void _handleNativeEvent(dynamic event) {
    if (event == null || event is! Map) return;

    final predictedPointsRaw = event['predicted_points'] as List<dynamic>?;
    if (predictedPointsRaw == null || predictedPointsRaw.isEmpty) return;

    final points =
        predictedPointsRaw.map((p) {
          final map = p as Map<dynamic, dynamic>;
          return PredictedTouchPoint(
            x: (map['x'] as num).toDouble(),
            y: (map['y'] as num).toDouble(),
            pressure: (map['pressure'] as num?)?.toDouble() ?? 0.5,
            timestamp: (map['timestamp'] as num?)?.toInt() ?? 0,
            isPredicted: map['isPredicted'] as bool? ?? true,
          );
        }).toList();

    _predictedTouchController.add(points);
  }

  /// Handle errors from native
  void _handleError(dynamic error) {
    EngineScope.current.errorRecovery.reportError(
      EngineError(
        severity: ErrorSeverity.transient,
        domain: ErrorDomain.platform,
        source: 'PredictedTouchService.nativeStream',
        original: error ?? 'unknown native error',
      ),
    );
  }

  /// Dispose the service
  void dispose() {
    _eventSubscription?.cancel();
    _predictedTouchController.close();
    _isInitialized = false;
  }

  /// Reset all state for testing.
  void resetForTesting() {
    _eventSubscription?.cancel();
    _eventSubscription = null;
    _isInitialized = false;
    _isSupported = false;
  }
}

/// Represents a predicted or coalesced touch point from native iOS
class PredictedTouchPoint {
  final double x;
  final double y;
  final double pressure;
  final int timestamp;
  final bool isPredicted;

  const PredictedTouchPoint({
    required this.x,
    required this.y,
    required this.pressure,
    required this.timestamp,
    required this.isPredicted,
  });

  @override
  String toString() =>
      'PredictedTouchPoint(x: $x, y: $y, pressure: $pressure, predicted: $isPredicted)';
}
