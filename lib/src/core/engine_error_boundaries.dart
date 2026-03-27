import 'dart:async';
import 'package:flutter/foundation.dart';

import 'engine_error.dart';
import 'engine_event.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// 🛡️ ENGINE ERROR BOUNDARIES — Plugin isolation, watchdog, degradation.
///
/// Complements [ErrorRecoveryService] (circuit breaker, retry, fallback) with
/// three production-critical capabilities:
///
/// 1. **Plugin Error Boundary** — Wraps plugin execution so a crashing plugin
///    cannot take down the engine.
/// 2. **Watchdog Timer** — Detects hanging operations and aborts them after
///    a configurable timeout, preventing the engine from locking up.
/// 3. **Graceful Degradation** — When memory or CPU pressure spikes, the
///    engine automatically reduces rendering quality (LOD, effects, caching)
///    instead of crashing.
///
/// ```dart
/// final boundaries = EngineErrorBoundaries();
///
/// // Plugin isolation
/// boundaries.executePlugin('my-plugin', () => plugin.run());
///
/// // Watchdog
/// final result = await boundaries.withWatchdog(
///   'svg-export',
///   () => exportSvg(network),
///   timeout: Duration(seconds: 10),
/// );
///
/// // Degradation levels
/// boundaries.onDegradationChange.listen((level) {
///   if (level >= DegradationLevel.reduced) disableEffects();
/// });
/// ```
/// ═══════════════════════════════════════════════════════════════════════════
class EngineErrorBoundaries {
  // ═══════════════════════════════════════════════════════════════════
  // Error stream
  // ═══════════════════════════════════════════════════════════════════

  final _errorController = StreamController<BoundaryError>.broadcast();

  /// Stream of all errors caught by boundaries.
  Stream<BoundaryError> get onError => _errorController.stream;

  final _degradationController = StreamController<DegradationLevel>.broadcast();

  /// Emitted when the degradation level changes.
  Stream<DegradationLevel> get onDegradationChange =>
      _degradationController.stream;

  DegradationLevel _currentDegradation = DegradationLevel.none;

  /// Current degradation level.
  DegradationLevel get currentDegradation => _currentDegradation;

  // ═══════════════════════════════════════════════════════════════════
  // 1. PLUGIN ERROR BOUNDARY
  // ═══════════════════════════════════════════════════════════════════

  /// Track per-plugin failure counts for auto-disable.
  final Map<String, int> _pluginFailures = {};

  /// Plugins that have been auto-disabled after too many failures.
  final Set<String> _disabledPlugins = {};

  /// Max consecutive failures before auto-disabling a plugin.
  static const int pluginDisableThreshold = 5;

  /// Execute a plugin action inside an error boundary.
  ///
  /// If the plugin crashes:
  /// - The error is caught and reported (engine stays alive).
  /// - The failure count is incremented.
  /// - After [pluginDisableThreshold] consecutive failures, the plugin
  ///   is auto-disabled.
  ///
  /// Returns the result, or [fallback] if the plugin crashes.
  T? executePlugin<T>(String pluginId, T Function() action, {T? fallback}) {
    if (_disabledPlugins.contains(pluginId)) {
      if (kDebugMode) {
      }
      return fallback;
    }

    try {
      final result = action();
      // Success → reset failure count
      _pluginFailures[pluginId] = 0;
      return result;
    } catch (error, stack) {
      final count = (_pluginFailures[pluginId] ?? 0) + 1;
      _pluginFailures[pluginId] = count;

      _errorController.add(
        BoundaryError(
          source: 'Plugin:$pluginId',
          type: BoundaryErrorType.pluginCrash,
          error: error,
          stackTrace: stack,
          message:
              'Plugin "$pluginId" crashed (failure $count/$pluginDisableThreshold)',
        ),
      );

      if (count >= pluginDisableThreshold) {
        _disabledPlugins.add(pluginId);
        _errorController.add(
          BoundaryError(
            source: 'Plugin:$pluginId',
            type: BoundaryErrorType.pluginDisabled,
            error: error,
            stackTrace: stack,
            message: 'Plugin "$pluginId" auto-disabled after $count failures',
          ),
        );
      }

      return fallback;
    }
  }

  /// Async variant of [executePlugin].
  Future<T?> executePluginAsync<T>(
    String pluginId,
    Future<T> Function() action, {
    T? fallback,
  }) async {
    if (_disabledPlugins.contains(pluginId)) return fallback;

    try {
      final result = await action();
      _pluginFailures[pluginId] = 0;
      return result;
    } catch (error, stack) {
      final count = (_pluginFailures[pluginId] ?? 0) + 1;
      _pluginFailures[pluginId] = count;

      _errorController.add(
        BoundaryError(
          source: 'Plugin:$pluginId',
          type: BoundaryErrorType.pluginCrash,
          error: error,
          stackTrace: stack,
          message:
              'Plugin "$pluginId" async crash (failure $count/$pluginDisableThreshold)',
        ),
      );

      if (count >= pluginDisableThreshold) {
        _disabledPlugins.add(pluginId);
      }

      return fallback;
    }
  }

  /// Whether a plugin has been auto-disabled.
  bool isPluginDisabled(String pluginId) => _disabledPlugins.contains(pluginId);

  /// Manually re-enable a previously disabled plugin.
  void reenablePlugin(String pluginId) {
    _disabledPlugins.remove(pluginId);
    _pluginFailures[pluginId] = 0;
  }

  // ═══════════════════════════════════════════════════════════════════
  // 2. WATCHDOG TIMER
  // ═══════════════════════════════════════════════════════════════════

  /// Execute [action] with a watchdog timer.
  ///
  /// If the action doesn't complete within [timeout], the Future completes
  /// with [fallback] and a [BoundaryErrorType.watchdogTimeout] is emitted.
  ///
  /// ⚠️ Note: this does NOT kill the underlying computation (Dart has no
  /// preemptive cancellation). It simply stops waiting for it.
  Future<T> withWatchdog<T>(
    String operationName,
    Future<T> Function() action, {
    required T fallback,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    try {
      return await action().timeout(
        timeout,
        onTimeout: () {
          _errorController.add(
            BoundaryError(
              source: 'Watchdog:$operationName',
              type: BoundaryErrorType.watchdogTimeout,
              error: TimeoutException(
                'Operation "$operationName" exceeded ${timeout.inSeconds}s',
              ),
              message:
                  'Watchdog timeout: "$operationName" aborted after ${timeout.inSeconds}s',
            ),
          );
          return fallback;
        },
      );
    } catch (error, stack) {
      _errorController.add(
        BoundaryError(
          source: 'Watchdog:$operationName',
          type: BoundaryErrorType.operationError,
          error: error,
          stackTrace: stack,
          message: 'Operation "$operationName" failed: $error',
        ),
      );
      return fallback;
    }
  }

  /// Synchronous watchdog: runs [action] and catches any error.
  ///
  /// Can't enforce a timeout synchronously, but catches crashes and
  /// returns [fallback] to keep the engine alive.
  T withSafeExecution<T>(
    String operationName,
    T Function() action, {
    required T fallback,
  }) {
    try {
      return action();
    } catch (error, stack) {
      _errorController.add(
        BoundaryError(
          source: 'SafeExec:$operationName',
          type: BoundaryErrorType.operationError,
          error: error,
          stackTrace: stack,
          message: 'Safe execution failed: "$operationName"',
        ),
      );
      return fallback;
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // 3. GRACEFUL DEGRADATION
  // ═══════════════════════════════════════════════════════════════════

  /// Update degradation level based on current system pressure.
  ///
  /// Call this periodically (e.g. every frame or every second).
  /// The engine should query [currentDegradation] and adjust behavior:
  ///
  /// - [DegradationLevel.none]     → Full quality
  /// - [DegradationLevel.reduced]  → Disable non-essential effects
  /// - [DegradationLevel.minimal]  → LOD fallback, skip anti-aliasing
  /// - [DegradationLevel.survival] → Wireframe/bounding-box only
  void updateDegradation({
    required double memoryUsageMB,
    required double frameTimeMs,
    double memoryWarningMB = 512,
    double memoryCriticalMB = 768,
    double frameTimeWarningMs = 25,
    double frameTimeCriticalMs = 50,
  }) {
    DegradationLevel level;

    if (memoryUsageMB >= memoryCriticalMB ||
        frameTimeMs >= frameTimeCriticalMs) {
      level = DegradationLevel.survival;
    } else if (memoryUsageMB >= memoryWarningMB ||
        frameTimeMs >= frameTimeWarningMs) {
      level = DegradationLevel.reduced;
    } else if (memoryUsageMB >= memoryWarningMB * 0.8 ||
        frameTimeMs >= frameTimeWarningMs * 0.8) {
      level = DegradationLevel.minimal;
    } else {
      level = DegradationLevel.none;
    }

    if (level != _currentDegradation) {
      _currentDegradation = level;
      _degradationController.add(level);

      if (kDebugMode) {
      }
    }
  }

  /// Query whether a specific feature should be enabled at the current
  /// degradation level.
  bool shouldEnable(DegradationFeature feature) {
    switch (feature) {
      case DegradationFeature.shadows:
      case DegradationFeature.blurEffects:
        return _currentDegradation.index <= DegradationLevel.none.index;
      case DegradationFeature.antiAliasing:
      case DegradationFeature.smoothScrolling:
        return _currentDegradation.index <= DegradationLevel.reduced.index;
      case DegradationFeature.textureRendering:
      case DegradationFeature.tileCache:
        return _currentDegradation.index <= DegradationLevel.minimal.index;
      case DegradationFeature.basicRendering:
        return true; // Always enabled, even in survival
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // Lifecycle
  // ═══════════════════════════════════════════════════════════════════

  /// Dispose all streams.
  void dispose() {
    _errorController.close();
    _degradationController.close();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Supporting types
// ═══════════════════════════════════════════════════════════════════════════

/// Degradation level for the engine under pressure.
enum DegradationLevel {
  /// Full quality — all effects and features enabled.
  none,

  /// Reduced quality — disable heavy effects (blur, shadow).
  reduced,

  /// Minimal quality — LOD fallback, skip anti-aliasing.
  minimal,

  /// Survival mode — wireframe/bounding-box rendering only.
  survival,
}

/// Features that can be toggled by degradation.
enum DegradationFeature {
  shadows,
  blurEffects,
  antiAliasing,
  smoothScrolling,
  textureRendering,
  tileCache,
  basicRendering,
}

/// Classification of boundary errors.
enum BoundaryErrorType {
  pluginCrash,
  pluginDisabled,
  watchdogTimeout,
  operationError,
}

/// Error event emitted by the boundary system.
class BoundaryError {
  final String source;
  final BoundaryErrorType type;
  final Object error;
  final StackTrace? stackTrace;
  final String message;
  final DateTime timestamp;

  BoundaryError({
    required this.source,
    required this.type,
    required this.error,
    this.stackTrace,
    required this.message,
  }) : timestamp = DateTime.now().toUtc();

  @override
  String toString() => 'BoundaryError(${type.name}, $source: $message)';
}
