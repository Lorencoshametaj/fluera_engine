import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import '../core/engine_scope.dart';
import '../core/engine_error.dart';

/// 🖥️ DisplayLinkService - CADisplayLink Sync for Ultra-Low Latency Rendering
///
/// This service provides frame-synchronized callbacks for smooth 120Hz rendering
/// on ProMotion displays (iPad Pro, iPhone 13 Pro+).
///
/// Benefits:
/// - Eliminates tearing and stutter
/// - Syncs with 120Hz ProMotion displays
/// - Provides precise frame timing for optimal rendering
///
/// Usage:
/// ```dart
/// final service = DisplayLinkService();
/// await service.initialize();
///
/// service.frameStream.listen((frameInfo) {
///   // Use frameInfo.targetTimestamp for rendering at optimal times
/// });
/// ```
class DisplayLinkService {
  /// Legacy singleton accessor — delegates to [EngineScope.current].
  static DisplayLinkService get instance =>
      EngineScope.current.displayLinkService;

  /// Creates a new instance (used by [EngineScope]).
  DisplayLinkService.create();

  // EventChannel for receiving frame timing from iOS
  static const EventChannel _eventChannel = EventChannel(
    'com.nebulaengine/display_link',
  );

  // MethodChannel for control
  static const MethodChannel _methodChannel = MethodChannel(
    'com.nebulaengine/display_link_control',
  );

  // Stream controller for frame timing
  final StreamController<FrameInfo> _frameController =
      StreamController<FrameInfo>.broadcast();

  // Subscription to native events
  StreamSubscription<dynamic>? _eventSubscription;

  // State
  bool _isInitialized = false;
  bool _isProMotionSupported = false;
  int _maxFrameRate = 60;

  /// Stream of frame timing info
  Stream<FrameInfo> get frameStream => _frameController.stream;

  /// Whether the service is initialized
  bool get isInitialized => _isInitialized;

  /// Whether ProMotion (120Hz) is supported
  bool get isProMotionSupported => _isProMotionSupported;

  /// Maximum frame rate of the display
  int get maxFrameRate => _maxFrameRate;

  /// Initialize the service
  Future<void> initialize() async {
    if (_isInitialized) return;

    // Only supported on iOS
    if (!Platform.isIOS) {
      _isInitialized = true;
      return;
    }

    try {
      // Check if ProMotion is supported
      _isProMotionSupported =
          await _methodChannel.invokeMethod<bool>('isProMotionSupported') ??
          false;
      _maxFrameRate =
          await _methodChannel.invokeMethod<int>('getMaxFrameRate') ?? 60;

      _isInitialized = true;
    } catch (e, stack) {
      EngineScope.current.errorRecovery.reportError(
        EngineError(
          severity: ErrorSeverity.degraded,
          domain: ErrorDomain.platform,
          source: 'DisplayLinkService.initialize',
          original: e,
          stack: stack,
        ),
      );
      _isInitialized = true;
    }
  }

  /// Start frame sync (subscribe to display link)
  Future<void> start() async {
    if (!Platform.isIOS || _eventSubscription != null) return;

    try {
      _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
        _handleFrameEvent,
        onError: _handleError,
      );
    } catch (e, stack) {
      EngineScope.current.errorRecovery.reportError(
        EngineError(
          severity: ErrorSeverity.transient,
          domain: ErrorDomain.platform,
          source: 'DisplayLinkService.start',
          original: e,
          stack: stack,
        ),
      );
    }
  }

  /// Stop frame sync
  Future<void> stop() async {
    _eventSubscription?.cancel();
    _eventSubscription = null;
  }

  /// Handle native frame events
  void _handleFrameEvent(dynamic event) {
    if (event == null || event is! Map) return;

    final frameInfo = FrameInfo(
      timestamp: (event['timestamp'] as num?)?.toInt() ?? 0,
      targetTimestamp: (event['targetTimestamp'] as num?)?.toInt() ?? 0,
      deltaTime: (event['deltaTime'] as num?)?.toDouble() ?? 16.67,
      frameRate: (event['frameRate'] as num?)?.toDouble() ?? 60.0,
      isProMotion: event['isProMotion'] as bool? ?? false,
    );

    _frameController.add(frameInfo);
  }

  /// Handle errors
  void _handleError(dynamic error) {
    EngineScope.current.errorRecovery.reportError(
      EngineError(
        severity: ErrorSeverity.transient,
        domain: ErrorDomain.platform,
        source: 'DisplayLinkService.nativeStream',
        original: error ?? 'unknown display link error',
      ),
    );
  }

  /// Dispose the service
  void dispose() {
    stop();
    _frameController.close();
    _isInitialized = false;
  }

  /// Reset all state for testing.
  void resetForTesting() {
    stop();
    _isInitialized = false;
    _isProMotionSupported = false;
    _maxFrameRate = 60;
  }
}

/// Frame timing information from CADisplayLink
class FrameInfo {
  final int timestamp;
  final int targetTimestamp;
  final double deltaTime;
  final double frameRate;
  final bool isProMotion;

  const FrameInfo({
    required this.timestamp,
    required this.targetTimestamp,
    required this.deltaTime,
    required this.frameRate,
    required this.isProMotion,
  });

  @override
  String toString() =>
      'FrameInfo(fps: ${frameRate.toStringAsFixed(1)}, delta: ${deltaTime.toStringAsFixed(2)}ms, proMotion: $isProMotion)';
}
