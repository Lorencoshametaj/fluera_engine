// ============================================================================
// 📱 DEGRADED MODE CONTROLLER — Platform-adaptive UX (A20.7)
//
// Specifica: A20.7-01 → A20.7-08
//
// Adapts the pedagogical interface when the device is limited:
//   - Smartphone (small screen, finger input)
//   - Tablet without stylus (finger = imprecise)
//   - Desktop without touch (mouse-only)
//   - Offline (no LLM access)
//
// For each mode, provides a set of UX parameter overrides that
// the rendering layer can consume.
//
// RULES:
//   - Detection is automatic (from platform info)
//   - Student can manually override mode
//   - All features remain accessible (just adapted)
//   - Performance targets: 60fps on all modes
//
// ARCHITECTURE:
//   Pure model — no BuildContext, no platform channels.
//   Host app provides platform info at initialization.
//
// THREAD SAFETY: Main isolate only.
// ============================================================================

import 'package:flutter/foundation.dart';

/// 📱 Device capability level.
enum DeviceCapability {
  /// iPad/tablet with stylus — full features.
  full,

  /// Tablet without stylus — adapted touch targets.
  tabletNoStylus,

  /// Smartphone — compact UI, simplified gestures.
  smartphone,

  /// Desktop/laptop — mouse+keyboard, no touch.
  desktop,
}

/// 📱 Network capability level.
enum NetworkCapability {
  /// Full internet — all AI features available.
  online,

  /// Intermittent — buffer requests, degrade gracefully.
  unstable,

  /// No internet — disable remote AI, local-only.
  offline,
}

/// 📱 UX parameter overrides for degraded mode.
class DegradedModeConfig {
  /// Minimum touch target size in logical pixels (WCAG: 44px).
  final double minTouchTarget;

  /// Whether to show the compact toolbar (vs full toolbar).
  final bool compactToolbar;

  /// Whether to auto-zoom to writing area.
  final bool autoZoomToWrite;

  /// Touch slop for gesture detection (higher = more forgiving).
  final double touchSlop;

  /// Whether palm rejection is enabled (only with stylus).
  final bool palmRejection;

  /// Maximum simultaneous overlays (reduce on small screens).
  final int maxOverlays;

  /// Whether Socratic AI is available.
  final bool socraticEnabled;

  /// Whether Ghost Map AI is available.
  final bool ghostMapEnabled;

  /// Whether to show "offline" badge.
  final bool showOfflineBadge;

  /// Toolbar button count (reduce for small screens).
  final int toolbarButtonLimit;

  /// Canvas minimap visibility.
  final bool showMinimap;

  /// Font scale for UI text.
  final double uiFontScale;

  /// Italian label for the mode.
  final String labelIt;

  const DegradedModeConfig({
    required this.minTouchTarget,
    required this.compactToolbar,
    required this.autoZoomToWrite,
    required this.touchSlop,
    required this.palmRejection,
    required this.maxOverlays,
    required this.socraticEnabled,
    required this.ghostMapEnabled,
    required this.showOfflineBadge,
    required this.toolbarButtonLimit,
    required this.showMinimap,
    required this.uiFontScale,
    required this.labelIt,
  });
}

/// 📱 Degraded Mode Controller (A20.7).
///
/// Detects device/network limitations and provides UX overrides.
///
/// Usage:
/// ```dart
/// final controller = DegradedModeController();
///
/// // Host app provides platform info
/// controller.configure(
///   device: DeviceCapability.smartphone,
///   network: NetworkCapability.online,
///   screenWidth: 375,
///   hasStylus: false,
/// );
///
/// // Get config for rendering
/// final config = controller.config;
/// if (config.compactToolbar) { ... }
/// if (!config.socraticEnabled) { ... }
/// ```
class DegradedModeController extends ChangeNotifier {
  DeviceCapability _device = DeviceCapability.full;
  NetworkCapability _network = NetworkCapability.online;
  double _screenWidth = 1024;
  bool _hasStylus = true;
  bool _manualOverride = false;

  /// Current device capability.
  DeviceCapability get device => _device;

  /// Current network capability.
  NetworkCapability get network => _network;

  /// Whether we're in a degraded mode.
  bool get isDegraded =>
      _device != DeviceCapability.full ||
      _network != NetworkCapability.online;

  /// Whether AI features are available.
  bool get isAiAvailable => _network == NetworkCapability.online;

  /// Screen width in logical pixels.
  double get screenWidth => _screenWidth;

  /// Whether a stylus is connected.
  bool get hasStylus => _hasStylus;

  /// Configure from host app platform info.
  void configure({
    DeviceCapability? device,
    NetworkCapability? network,
    double? screenWidth,
    bool? hasStylus,
  }) {
    bool changed = false;

    if (device != null && device != _device && !_manualOverride) {
      _device = device;
      changed = true;
    }
    // Network changes always apply — even during manual device override,
    // because network state is a system fact, not a user preference.
    if (network != null && network != _network) {
      _network = network;
      changed = true;
    }
    if (screenWidth != null && screenWidth != _screenWidth) {
      _screenWidth = screenWidth;
      changed = true;
    }
    if (hasStylus != null && hasStylus != _hasStylus) {
      _hasStylus = hasStylus;
      changed = true;
    }

    if (changed) {
      notifyListeners();
    }
  }

  /// Auto-detect device capability from screen width.
  static DeviceCapability detectDevice({
    required double screenWidth,
    required bool hasStylus,
    required bool isDesktop,
  }) {
    if (isDesktop) return DeviceCapability.desktop;
    if (screenWidth < 600) return DeviceCapability.smartphone;
    if (!hasStylus) return DeviceCapability.tabletNoStylus;
    return DeviceCapability.full;
  }

  /// Manual override (student explicitly selects a mode).
  void setManualOverride(DeviceCapability device) {
    _device = device;
    _manualOverride = true;
    notifyListeners();
  }

  /// Clear manual override (return to auto-detection).
  void clearManualOverride() {
    _manualOverride = false;
    notifyListeners();
  }

  /// Get the UX config for the current mode.
  DegradedModeConfig get config => _configs[_device]!.copyWith(
        network: _network,
      );

  /// Preset configs per device capability.
  static final Map<DeviceCapability, _DegradedModeConfigBase> _configs = {
    DeviceCapability.full: _DegradedModeConfigBase(
      minTouchTarget: 44,
      compactToolbar: false,
      autoZoomToWrite: false,
      touchSlop: 8,
      palmRejection: true,
      maxOverlays: 3,
      toolbarButtonLimit: 12,
      showMinimap: true,
      uiFontScale: 1.0,
      labelIt: 'Completo',
    ),
    DeviceCapability.tabletNoStylus: _DegradedModeConfigBase(
      minTouchTarget: 52,
      compactToolbar: false,
      autoZoomToWrite: true,
      touchSlop: 16, // More forgiving for finger
      palmRejection: false,
      maxOverlays: 2,
      toolbarButtonLimit: 10,
      showMinimap: true,
      uiFontScale: 1.0,
      labelIt: 'Tablet (senza penna)',
    ),
    DeviceCapability.smartphone: _DegradedModeConfigBase(
      minTouchTarget: 56,
      compactToolbar: true,
      autoZoomToWrite: true,
      touchSlop: 20,
      palmRejection: false,
      maxOverlays: 1,
      toolbarButtonLimit: 5,
      showMinimap: false, // Too small
      uiFontScale: 0.9,
      labelIt: 'Smartphone',
    ),
    DeviceCapability.desktop: _DegradedModeConfigBase(
      minTouchTarget: 32, // Mouse is precise
      compactToolbar: false,
      autoZoomToWrite: false,
      touchSlop: 4,
      palmRejection: false,
      maxOverlays: 4,
      toolbarButtonLimit: 15,
      showMinimap: true,
      uiFontScale: 1.0,
      labelIt: 'Desktop',
    ),
  };
}

/// Internal config base (without network-dependent fields).
class _DegradedModeConfigBase {
  final double minTouchTarget;
  final bool compactToolbar;
  final bool autoZoomToWrite;
  final double touchSlop;
  final bool palmRejection;
  final int maxOverlays;
  final int toolbarButtonLimit;
  final bool showMinimap;
  final double uiFontScale;
  final String labelIt;

  const _DegradedModeConfigBase({
    required this.minTouchTarget,
    required this.compactToolbar,
    required this.autoZoomToWrite,
    required this.touchSlop,
    required this.palmRejection,
    required this.maxOverlays,
    required this.toolbarButtonLimit,
    required this.showMinimap,
    required this.uiFontScale,
    required this.labelIt,
  });

  DegradedModeConfig copyWith({required NetworkCapability network}) =>
      DegradedModeConfig(
        minTouchTarget: minTouchTarget,
        compactToolbar: compactToolbar,
        autoZoomToWrite: autoZoomToWrite,
        touchSlop: touchSlop,
        palmRejection: palmRejection,
        maxOverlays: maxOverlays,
        socraticEnabled: network == NetworkCapability.online,
        ghostMapEnabled: network == NetworkCapability.online,
        showOfflineBadge: network != NetworkCapability.online,
        toolbarButtonLimit: toolbarButtonLimit,
        showMinimap: showMinimap,
        uiFontScale: uiFontScale,
        labelIt: labelIt,
      );
}
