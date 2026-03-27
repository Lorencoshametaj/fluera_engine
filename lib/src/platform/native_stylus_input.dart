import 'dart:async';
import '../utils/platform_guard.dart';
import 'package:flutter/services.dart';
import '../core/engine_scope.dart';
import '../core/engine_error.dart';

/// 🖊️ NativeStylusInput — Cross-Platform Stylus Metadata Service
///
/// Provides unified access to advanced stylus features across iOS and Android:
/// - **Hover detection**: Stylus proximity above the screen
/// - **Tilt & altitude**: Pen angle relative to the screen surface
/// - **Orientation**: Pen rotation around its own axis
/// - **Palm rejection**: Tool-type filtering for stylus-only events
/// - **Button state**: Side button press detection (S Pen, Apple Pencil)
///
/// On iOS, delegates to PredictedTouchPlugin's hover events.
/// On Android, delegates to StylusInputPlugin's hover and metadata events.
///
/// Usage:
/// ```dart
/// final stylus = NativeStylusInput.instance;
/// await stylus.initialize();
///
/// stylus.hoverStream.listen((event) {
///   print('Hovering at: ${event.x}, ${event.y}');
///   print('Altitude: ${event.altitude}');
/// });
///
/// stylus.stylusMetadataStream.listen((event) {
///   print('Tilt: ${event.tiltX}, Orientation: ${event.orientation}');
/// });
/// ```
class NativeStylusInput {
  /// Legacy singleton accessor — delegates to [EngineScope.current].
  static NativeStylusInput get instance =>
      EngineScope.current.nativeStylusInput;

  /// Creates a new instance (used by [EngineScope]).
  NativeStylusInput.create();

  // ═══════════════════════════════════════════════════════════════════════════
  // CHANNELS
  // ═══════════════════════════════════════════════════════════════════════════

  // iOS uses PredictedTouchPlugin channels for hover
  static const EventChannel _iosEventChannel = EventChannel(
    'com.flueraengine/predicted_touches',
  );
  static const MethodChannel _iosMethodChannel = MethodChannel(
    'com.flueraengine/predicted_touches_control',
  );

  // Android uses dedicated StylusInputPlugin channels
  static const EventChannel _androidEventChannel = EventChannel(
    'com.flueraengine/stylus_input',
  );
  static const MethodChannel _androidMethodChannel = MethodChannel(
    'com.flueraengine/stylus_input_control',
  );

  // ═══════════════════════════════════════════════════════════════════════════
  // STATE
  // ═══════════════════════════════════════════════════════════════════════════

  final StreamController<StylusHoverEvent> _hoverController =
      StreamController<StylusHoverEvent>.broadcast();

  final StreamController<StylusMetadataEvent> _metadataController =
      StreamController<StylusMetadataEvent>.broadcast();

  StreamSubscription<dynamic>? _eventSubscription;
  bool _isInitialized = false;
  bool _isStylusSupported = false;
  StylusCapabilities? _capabilities;

  /// Stream of hover events from the stylus
  Stream<StylusHoverEvent> get hoverStream => _hoverController.stream;

  /// Stream of enhanced stylus metadata (tilt, orientation, button)
  Stream<StylusMetadataEvent> get stylusMetadataStream =>
      _metadataController.stream;

  /// Whether the service is initialized
  bool get isInitialized => _isInitialized;

  /// Whether stylus input is supported on this device
  bool get isStylusSupported => _isStylusSupported;

  /// Detected stylus capabilities (null until initialized)
  StylusCapabilities? get capabilities => _capabilities;

  // ═══════════════════════════════════════════════════════════════════════════
  // INITIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Initialize the stylus input service.
  /// Detects platform capabilities and starts listening for events.
  Future<void> initialize() async {
    if (_isInitialized) return;

    if (!PlatformGuard.isIOS && !PlatformGuard.isAndroid) {
      _isStylusSupported = false;
      _isInitialized = true;
      return;
    }

    try {
      if (PlatformGuard.isIOS) {
        await _initializeIOS();
      } else if (PlatformGuard.isAndroid) {
        await _initializeAndroid();
      }

      _isInitialized = true;
    } catch (e, stack) {
      EngineScope.current.errorRecovery.reportError(
        EngineError(
          severity: ErrorSeverity.degraded,
          domain: ErrorDomain.platform,
          source: 'NativeStylusInput.initialize',
          original: e,
          stack: stack,
        ),
      );
      _isStylusSupported = false;
      _isInitialized = true;
    }
  }

  Future<void> _initializeIOS() async {
    // iOS always supports stylus via Apple Pencil detection
    // Hover is available on iPad Pro with iPadOS 16.1+
    _isStylusSupported = true;
    _capabilities = const StylusCapabilities(
      hasStylusSupport: true,
      hasTilt: true,
      hasPressure: true,
      hasPalmRejection: true,
      hasHover: true,
      hasButton: true,
      platform: 'iOS',
    );

    // Subscribe to iOS event channel (shared with PredictedTouchPlugin)
    _eventSubscription = _iosEventChannel.receiveBroadcastStream().listen(
      _handleIOSEvent,
      onError: (e) {
        EngineScope.current.errorRecovery.reportError(
          EngineError(
            severity: ErrorSeverity.transient,
            domain: ErrorDomain.platform,
            source: 'NativeStylusInput.iOSStream',
            original: e,
          ),
        );
      },
    );
  }

  Future<void> _initializeAndroid() async {
    try {
      final supported =
          await _androidMethodChannel.invokeMethod<bool>('isStylusSupported') ??
          false;
      _isStylusSupported = supported;

      if (supported) {
        // Get detailed capabilities
        final capsMap = await _androidMethodChannel.invokeMethod<Map>(
          'getStylusCapabilities',
        );

        if (capsMap != null) {
          _capabilities = StylusCapabilities(
            hasStylusSupport: capsMap['hasStylusSupport'] as bool? ?? false,
            hasTilt: capsMap['hasTilt'] as bool? ?? false,
            hasPressure: capsMap['hasPressure'] as bool? ?? true,
            hasPalmRejection: capsMap['hasPalmRejection'] as bool? ?? false,
            hasHover: capsMap['hasHover'] as bool? ?? false,
            hasButton: capsMap['hasButton'] as bool? ?? false,
            platform: 'Android',
            deviceName: capsMap['stylusDeviceName'] as String?,
          );
        }

        // Subscribe to Android stylus events
        _eventSubscription = _androidEventChannel
            .receiveBroadcastStream()
            .listen(
              _handleAndroidEvent,
              onError: (e) {
                EngineScope.current.errorRecovery.reportError(
                  EngineError(
                    severity: ErrorSeverity.transient,
                    domain: ErrorDomain.platform,
                    source: 'NativeStylusInput.androidStream',
                    original: e,
                  ),
                );
              },
            );
      }
    } catch (e, stack) {
      EngineScope.current.errorRecovery.reportError(
        EngineError(
          severity: ErrorSeverity.degraded,
          domain: ErrorDomain.platform,
          source: 'NativeStylusInput._initializeAndroid',
          original: e,
          stack: stack,
        ),
      );
      _isStylusSupported = false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EVENT HANDLING
  // ═══════════════════════════════════════════════════════════════════════════

  void _handleIOSEvent(dynamic event) {
    if (event == null || event is! Map) return;

    // Handle hover events from iOS PredictedTouchPlugin
    final hoverEvent = event['hover_event'] as Map?;
    if (hoverEvent != null) {
      _hoverController.add(
        StylusHoverEvent(
          x: (hoverEvent['x'] as num).toDouble(),
          y: (hoverEvent['y'] as num).toDouble(),
          state: _parseHoverState(hoverEvent['state'] as String? ?? 'changed'),
          isHovering: hoverEvent['isHovering'] as bool? ?? false,
          altitude: (hoverEvent['altitude'] as num?)?.toDouble(),
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    }
  }

  void _handleAndroidEvent(dynamic event) {
    if (event == null || event is! Map) return;

    // Handle hover events
    final hoverEvent = event['hover_event'] as Map?;
    if (hoverEvent != null) {
      _hoverController.add(
        StylusHoverEvent(
          x: (hoverEvent['x'] as num).toDouble(),
          y: (hoverEvent['y'] as num).toDouble(),
          state: _parseHoverState(hoverEvent['state'] as String? ?? 'changed'),
          isHovering: hoverEvent['isHovering'] as bool? ?? false,
          altitude: (hoverEvent['altitude'] as num?)?.toDouble(),
          distance: (hoverEvent['distance'] as num?)?.toDouble(),
          tiltX: (hoverEvent['tiltX'] as num?)?.toDouble(),
          orientation: (hoverEvent['orientation'] as num?)?.toDouble(),
          timestamp:
              (hoverEvent['timestamp'] as num?)?.toInt() ??
              DateTime.now().millisecondsSinceEpoch,
        ),
      );
    }

    // Handle stylus metadata events
    final stylusEvent = event['stylus_event'] as Map?;
    if (stylusEvent != null) {
      _metadataController.add(
        StylusMetadataEvent(
          x: (stylusEvent['x'] as num).toDouble(),
          y: (stylusEvent['y'] as num).toDouble(),
          pressure: (stylusEvent['pressure'] as num?)?.toDouble() ?? 0.5,
          tiltX: (stylusEvent['tiltX'] as num?)?.toDouble(),
          orientation: (stylusEvent['orientation'] as num?)?.toDouble(),
          altitude: (stylusEvent['altitude'] as num?)?.toDouble(),
          isButtonPressed: stylusEvent['isButtonPressed'] as bool? ?? false,
          action: stylusEvent['action'] as String? ?? 'move',
          timestamp:
              (stylusEvent['timestamp'] as num?)?.toInt() ??
              DateTime.now().millisecondsSinceEpoch,
        ),
      );
    }
  }

  HoverState _parseHoverState(String state) {
    switch (state) {
      case 'began':
        return HoverState.began;
      case 'changed':
        return HoverState.changed;
      case 'ended':
        return HoverState.ended;
      default:
        return HoverState.changed;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CLEANUP
  // ═══════════════════════════════════════════════════════════════════════════

  void dispose() {
    _eventSubscription?.cancel();
    _hoverController.close();
    _metadataController.close();
    _isInitialized = false;
  }

  /// Reset all state for testing.
  void resetForTesting() {
    _eventSubscription?.cancel();
    _eventSubscription = null;
    _isInitialized = false;
    _isStylusSupported = false;
    _capabilities = null;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// DATA MODELS
// ═══════════════════════════════════════════════════════════════════════════

/// State of a hover event
enum HoverState { began, changed, ended }

/// A hover event from the stylus (proximity above screen)
class StylusHoverEvent {
  final double x;
  final double y;
  final HoverState state;
  final bool isHovering;
  final double? altitude;
  final double? distance;
  final double? tiltX;
  final double? orientation;
  final int timestamp;

  const StylusHoverEvent({
    required this.x,
    required this.y,
    required this.state,
    required this.isHovering,
    this.altitude,
    this.distance,
    this.tiltX,
    this.orientation,
    required this.timestamp,
  });

  @override
  String toString() =>
      'StylusHoverEvent(x: $x, y: $y, state: $state, hovering: $isHovering)';
}

/// Enhanced stylus metadata for touch events (tilt, button, etc.)
class StylusMetadataEvent {
  final double x;
  final double y;
  final double pressure;
  final double? tiltX;
  final double? orientation;
  final double? altitude;
  final bool isButtonPressed;
  final String action;
  final int timestamp;

  const StylusMetadataEvent({
    required this.x,
    required this.y,
    required this.pressure,
    this.tiltX,
    this.orientation,
    this.altitude,
    required this.isButtonPressed,
    required this.action,
    required this.timestamp,
  });

  @override
  String toString() =>
      'StylusMetadataEvent(x: $x, y: $y, p: $pressure, tilt: $tiltX, button: $isButtonPressed)';
}

/// Device stylus capabilities detected at initialization
class StylusCapabilities {
  final bool hasStylusSupport;
  final bool hasTilt;
  final bool hasPressure;
  final bool hasPalmRejection;
  final bool hasHover;
  final bool hasButton;
  final String platform;
  final String? deviceName;

  const StylusCapabilities({
    required this.hasStylusSupport,
    required this.hasTilt,
    required this.hasPressure,
    required this.hasPalmRejection,
    required this.hasHover,
    required this.hasButton,
    required this.platform,
    this.deviceName,
  });

  @override
  String toString() =>
      'StylusCapabilities(platform: $platform, stylus: $hasStylusSupport, '
      'tilt: $hasTilt, hover: $hasHover, button: $hasButton'
      '${deviceName != null ? ', device: $deviceName' : ''})';
}
