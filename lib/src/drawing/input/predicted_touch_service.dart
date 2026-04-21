import 'dart:async';
import '../../utils/platform_guard.dart';
import 'package:flutter/foundation.dart';
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

  // Stream controller for predicted touches (isPredicted=true only)
  final StreamController<List<PredictedTouchPoint>> _predictedTouchController =
      StreamController<List<PredictedTouchPoint>>.broadcast();

  // Stream controller for real coalesced touches (isPredicted=false).
  // Separate from predicted because they feed the committed stroke, whereas
  // predicted are visual-only anti-lag.
  final StreamController<List<PredictedTouchPoint>> _realTouchController =
      StreamController<List<PredictedTouchPoint>>.broadcast();

  // Subscription to native events
  StreamSubscription<dynamic>? _eventSubscription;

  // State
  bool _isInitialized = false;
  bool _isSupported = false;

  /// Toggle runtime logging of per-event coalesced/predicted sample counts.
  /// TEMP: on by default so the in-app debug overlay exposes the Apple Pencil
  /// 240 Hz delivery rate on TestFlight. Flip back to false once confirmed.
  static bool debugLogEventRate = true;

  /// Live, human-readable status line. Drives the in-app debug overlay so
  /// you can verify the native 240 Hz path from the iPad itself without
  /// attaching to a Mac. Empty until the first native batch arrives.
  static final ValueNotifier<String> debugStatusNotifier =
      ValueNotifier<String>('');

  int _windowRealCount = 0;
  int _windowPredictedCount = 0;
  int _windowEventCount = 0;
  int _windowStartMs = 0;
  bool _firstBatchLogged = false;

  /// Stream of predicted touch points from native iOS (isPredicted=true).
  /// For visual-only anti-lag rendering; NOT part of the committed stroke.
  Stream<List<PredictedTouchPoint>> get predictedTouchStream =>
      _predictedTouchController.stream;

  /// Stream of real coalesced touch points from native iOS (isPredicted=false).
  /// These are ground-truth Apple Pencil samples at up to ~240 Hz; feed them
  /// to the stroke ingestion path.
  Stream<List<PredictedTouchPoint>> get realTouchStream =>
      _realTouchController.stream;

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

    final List<PredictedTouchPoint> realPoints = [];
    final List<PredictedTouchPoint> predictedPoints = [];
    for (final p in predictedPointsRaw) {
      final map = p as Map<dynamic, dynamic>;
      final pt = PredictedTouchPoint(
        x: (map['x'] as num).toDouble(),
        y: (map['y'] as num).toDouble(),
        pressure: (map['pressure'] as num?)?.toDouble() ?? 0.5,
        timestamp: (map['timestamp'] as num?)?.toInt() ?? 0,
        isPredicted: map['isPredicted'] as bool? ?? true,
        phase: map['phase'] as String? ?? 'moved',
        isFinal: map['isFinal'] as bool? ?? false,
        touchType: map['touchType'] as String? ?? 'pencil',
      );
      if (pt.isPredicted) {
        predictedPoints.add(pt);
      } else {
        realPoints.add(pt);
      }
    }

    if (!_firstBatchLogged && realPoints.isNotEmpty) {
      _firstBatchLogged = true;
      final first = realPoints.first;
      final msg =
          'first native batch: count=${realPoints.length} '
          'type=${first.touchType} phase=${first.phase}';
      debugPrint('[PredictedTouchService] $msg');
      debugStatusNotifier.value = msg;
    }

    if (debugLogEventRate) {
      _logEventRate(realPoints, predictedPoints);
    }

    // Legacy combined stream: preserve existing subscribers' behavior.
    final combined =
        predictedPointsRaw.isEmpty
            ? const <PredictedTouchPoint>[]
            : [...realPoints, ...predictedPoints];
    _predictedTouchController.add(combined);

    if (realPoints.isNotEmpty) _realTouchController.add(realPoints);
  }

  void _logEventRate(
    List<PredictedTouchPoint> realPoints,
    List<PredictedTouchPoint> predictedPoints,
  ) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (_windowStartMs == 0) _windowStartMs = nowMs;
    _windowEventCount++;
    _windowRealCount += realPoints.length;
    _windowPredictedCount += predictedPoints.length;
    final elapsed = nowMs - _windowStartMs;
    if (elapsed >= 1000) {
      final realHz = _windowRealCount * 1000.0 / elapsed;
      final predictedHz = _windowPredictedCount * 1000.0 / elapsed;
      final eventHz = _windowEventCount * 1000.0 / elapsed;
      final line =
          'events/s=${eventHz.toStringAsFixed(0)}  '
          'real/s=${realHz.toStringAsFixed(0)}  '
          'pred/s=${predictedHz.toStringAsFixed(0)}';
      debugPrint('[PredictedTouchService] $line');
      debugStatusNotifier.value = line;
      _windowStartMs = nowMs;
      _windowEventCount = 0;
      _windowRealCount = 0;
      _windowPredictedCount = 0;
    }
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
    _realTouchController.close();
    _isInitialized = false;
    _resetRateWindow();
  }

  /// Reset all state for testing.
  void resetForTesting() {
    _eventSubscription?.cancel();
    _eventSubscription = null;
    _isInitialized = false;
    _isSupported = false;
    _resetRateWindow();
  }

  void _resetRateWindow() {
    _windowStartMs = 0;
    _windowEventCount = 0;
    _windowRealCount = 0;
    _windowPredictedCount = 0;
  }
}

/// Represents a predicted or coalesced touch point from native iOS
class PredictedTouchPoint {
  final double x;
  final double y;
  final double pressure;

  /// Milliseconds; on iOS this is `UITouch.timestamp` (seconds since device
  /// boot / uptime base) times 1000, NOT wall-clock epoch.
  final int timestamp;

  /// true => predicted (iOS extrapolation), false => real coalesced sample.
  final bool isPredicted;

  /// UIKit phase: 'began' | 'moved' | 'ended' | 'cancelled'.
  final String phase;

  /// True for the last sample of the gesture (emitted by touchesEnded).
  final bool isFinal;

  /// 'pencil' | 'finger' | 'indirect'. Only 'pencil' should enable the
  /// native-authoritative 240 Hz path.
  final String touchType;

  const PredictedTouchPoint({
    required this.x,
    required this.y,
    required this.pressure,
    required this.timestamp,
    required this.isPredicted,
    this.phase = 'moved',
    this.isFinal = false,
    this.touchType = 'pencil',
  });

  @override
  String toString() =>
      'PredictedTouchPoint(x: $x, y: $y, pressure: $pressure, '
      'predicted: $isPredicted, phase: $phase, final: $isFinal, type: $touchType)';
}
