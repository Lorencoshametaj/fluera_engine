import 'dart:async';
import 'package:flutter/foundation.dart';

import '../../platform/native_performance_monitor.dart';
import '../../core/engine_scope.dart';
import '../../core/engine_event.dart';
import '../../core/engine_error.dart';
import './memory_managed_cache.dart';
import './memory_event.dart';
import '../optimization/frame_budget_manager.dart';

/// 🧠 MEMORY BUDGET CONTROLLER — Top-tier enterprise memory orchestrator
///
/// Coordinates memory management across all engine cache subsystems with
/// four enterprise-grade capabilities:
///
/// 1. **Adaptive device-aware thresholds** — Auto-calibrates budget and
///    pressure thresholds based on physical device RAM (iPhone SE vs iPad Pro).
/// 2. **Priority-weighted eviction** — Evicts cheap-to-rebuild caches first,
///    preserving expensive GPU-rasterized caches as long as possible.
/// 3. **Telemetry event stream** — Push-based [onMemoryEvent] broadcast stream
///    for real-time dashboarding and analytics.
/// 4. **Hysteresis** — High-water/low-water marks prevent evict→refill→evict
///    thrashing by locking cache refill until pressure drops significantly.
///
/// Usage:
/// ```dart
/// final controller = MemoryBudgetController(
///   performanceMonitor: EngineScope.current.performanceMonitor,
///   memoryPressureHandler: EngineScope.current.memoryPressureHandler,
/// );
/// controller.registerCache(tileCacheManager);
/// controller.registerCache(imageCacheService, warningFraction: 0.50);
/// controller.startMonitoring();
///
/// // Telemetry
/// controller.onMemoryEvent.listen((e) => print(e));
/// ```
class MemoryBudgetController {
  // ═══════════════════════════════════════════════════════════════════════════
  // CONFIGURATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Maximum memory budget in MB before self-eviction kicks in.
  /// Auto-calibrated by [_calibrateFromDevice] when native metrics arrive.
  int _budgetCapMB;

  /// Warning threshold (percentage) — triggers partial eviction.
  double _warningThresholdPercent;

  /// Critical threshold (percentage) — triggers full flush.
  double _criticalThresholdPercent;

  /// Low-water mark (percentage) — hysteresis unlocks refill below this.
  double _lowWaterMarkPercent;

  /// Seconds between self-scan ticks.
  final int scanIntervalSeconds;

  /// Fraction to evict per cache at `warning` level.
  /// Each cache may define its own override via [registerCache].
  static const double _defaultWarningFraction = 0.30;

  /// Whether adaptive threshold calibration has been performed.
  bool _calibrated = false;

  // ═══════════════════════════════════════════════════════════════════════════
  // DEPENDENCIES
  // ═══════════════════════════════════════════════════════════════════════════

  final NativePerformanceMonitor? _performanceMonitor;
  final MemoryPressureHandler _memoryPressureHandler;

  // ═══════════════════════════════════════════════════════════════════════════
  // STATE
  // ═══════════════════════════════════════════════════════════════════════════

  final List<_CacheRegistration> _caches = [];
  Timer? _scanTimer;
  StreamSubscription<PerformanceMetrics>? _metricsSubscription;
  MemoryPressureLevel _currentLevel = MemoryPressureLevel.normal;
  bool _isMonitoring = false;

  // Hysteresis state
  bool _hysteresisActive = false;

  // Cooldown: avoid evicting more than once per 3 seconds
  DateTime _lastEvictionTime = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _evictionCooldown = Duration(seconds: 3);

  // Telemetry stream
  final StreamController<MemoryEvent> _eventController =
      StreamController<MemoryEvent>.broadcast();

  // ═══════════════════════════════════════════════════════════════════════════
  // CONSTRUCTORS
  // ═══════════════════════════════════════════════════════════════════════════

  MemoryBudgetController({
    required NativePerformanceMonitor? performanceMonitor,
    required MemoryPressureHandler memoryPressureHandler,
    int budgetCapMB = 350,
    this.scanIntervalSeconds = 5,
  }) : _performanceMonitor = performanceMonitor,
       _memoryPressureHandler = memoryPressureHandler,
       _budgetCapMB = budgetCapMB,
       _warningThresholdPercent = 70.0,
       _criticalThresholdPercent = 85.0,
       _lowWaterMarkPercent = 50.0;

  /// Creates a controller for testing without native dependencies.
  @visibleForTesting
  MemoryBudgetController.forTesting({
    int budgetCapMB = 100,
    this.scanIntervalSeconds = 5,
    required MemoryPressureHandler memoryPressureHandler,
    double warningThreshold = 70.0,
    double criticalThreshold = 85.0,
    double lowWaterMark = 50.0,
  }) : _performanceMonitor = null,
       _memoryPressureHandler = memoryPressureHandler,
       _budgetCapMB = budgetCapMB,
       _warningThresholdPercent = warningThreshold,
       _criticalThresholdPercent = criticalThreshold,
       _lowWaterMarkPercent = lowWaterMark;

  // ═══════════════════════════════════════════════════════════════════════════
  // REGISTRATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Register a cache subsystem for coordinated eviction.
  ///
  /// [warningFraction] overrides the default eviction fraction at `warning`
  /// level (0.0–1.0). Pass `null` to use the default 0.30.
  void registerCache(MemoryManagedCache cache, {double? warningFraction}) {
    // Avoid double-registration
    if (_caches.any((r) => identical(r.cache, cache))) return;

    _caches.add(
      _CacheRegistration(
        cache: cache,
        warningFraction: warningFraction ?? _defaultWarningFraction,
      ),
    );
  }

  /// Unregister a previously registered cache.
  void unregisterCache(MemoryManagedCache cache) {
    _caches.removeWhere((r) => identical(r.cache, cache));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ADAPTIVE DEVICE-AWARE THRESHOLDS (Enhancement 1)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Auto-calibrate budget and thresholds based on device physical RAM.
  ///
  /// Called once when the first native metrics arrive.
  void _calibrateFromDevice(double totalRAM_MB) {
    if (_calibrated) return;
    _calibrated = true;

    if (totalRAM_MB <= 3072) {
      // ≤ 3 GB (iPhone SE, low-end Android)
      _budgetCapMB = 150;
      _warningThresholdPercent = 60.0;
      _criticalThresholdPercent = 75.0;
      _lowWaterMarkPercent = 40.0;
    } else if (totalRAM_MB <= 6144) {
      // 3–6 GB (most phones)
      _budgetCapMB = 300;
      _warningThresholdPercent = 65.0;
      _criticalThresholdPercent = 80.0;
      _lowWaterMarkPercent = 45.0;
    } else if (totalRAM_MB <= 12288) {
      // 6–12 GB (flagship phones, tablets)
      _budgetCapMB = 500;
      _warningThresholdPercent = 70.0;
      _criticalThresholdPercent = 85.0;
      _lowWaterMarkPercent = 50.0;
    } else {
      // > 12 GB (iPad Pro, high-end Android tablets)
      _budgetCapMB = 800;
      _warningThresholdPercent = 75.0;
      _criticalThresholdPercent = 90.0;
      _lowWaterMarkPercent = 55.0;
    }

  }

  /// Manually calibrate thresholds for testing or custom devices.
  @visibleForTesting
  void calibrateForRAM(double totalRAM_MB) {
    _calibrated = false;
    _calibrateFromDevice(totalRAM_MB);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MONITORING LIFECYCLE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Start periodic memory monitoring.
  ///
  /// Subscribes to [NativePerformanceMonitor.metricsStream] if available
  /// and starts a periodic self-scan timer as fallback.
  void startMonitoring() {
    if (_isMonitoring) return;
    _isMonitoring = true;

    // Subscribe to native metrics stream (if monitor is initialized)
    if (_performanceMonitor != null && _performanceMonitor.isInitialized) {
      _metricsSubscription = _performanceMonitor.metricsStream.listen(
        _onNativeMetrics,
        onError: (e) {
          EngineScope.current.errorRecovery.reportError(
            EngineError(
              severity: ErrorSeverity.transient,
              domain: ErrorDomain.platform,
              source: 'MemoryBudgetController.metricsStream',
              original: e,
            ),
          );
        },
      );
    }

    // Periodic self-scan as fallback / complement
    _scanTimer = Timer.periodic(
      Duration(seconds: scanIntervalSeconds),
      (_) => _performBudgetScan(),
    );
  }

  /// Stop monitoring and release resources.
  void stopMonitoring() {
    _isMonitoring = false;
    _scanTimer?.cancel();
    _scanTimer = null;
    _metricsSubscription?.cancel();
    _metricsSubscription = null;
  }

  /// Whether the controller is currently monitoring.
  bool get isMonitoring => _isMonitoring;

  // ═══════════════════════════════════════════════════════════════════════════
  // PRESSURE EVALUATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Called when native metrics arrive from the platform.
  void _onNativeMetrics(PerformanceMetrics metrics) {
    // Auto-calibrate thresholds on first native data (Enhancement 1)
    if (!_calibrated && metrics.memoryTotalMB > 0) {
      _calibrateFromDevice(metrics.memoryTotalMB);
    }

    final level = _classifyNativePressure(metrics);
    _applyPressureLevel(level);
  }

  /// Classify native metrics into a pressure level using adaptive thresholds.
  MemoryPressureLevel _classifyNativePressure(PerformanceMetrics metrics) {
    // Use the platform-reported pressure level first
    switch (metrics.memoryPressureLevel) {
      case 'critical':
        return MemoryPressureLevel.critical;
      case 'warning':
        return MemoryPressureLevel.warning;
    }

    // Fallback: use adaptive percentage thresholds
    if (metrics.memoryUsagePercent > _criticalThresholdPercent) {
      return MemoryPressureLevel.critical;
    } else if (metrics.memoryUsagePercent > _warningThresholdPercent) {
      return MemoryPressureLevel.warning;
    }

    return MemoryPressureLevel.normal;
  }

  /// Self-scan using only engine-internal budget tracking.
  void _performBudgetScan() {
    final totalMB = totalEstimatedMemoryMB;
    final usagePercent =
        _budgetCapMB > 0 ? (totalMB / _budgetCapMB) * 100 : 0.0;

    // Unified telemetry bus: update gauges
    if (EngineScope.hasScope) {
      final t = EngineScope.current.telemetry;
      t.gauge('memory.budget_used_pct').set(usagePercent);
      t.gauge('memory.estimated_mb').set(totalMB);
    }

    // Emit telemetry snapshot (Enhancement 3)
    _emitEvent(
      MemoryBudgetSnapshot(
        totalEstimatedMB: totalMB,
        budgetCapMB: _budgetCapMB,
        usagePercent: usagePercent,
        perCacheMB: {
          for (final reg in _caches)
            reg.cache.cacheName: reg.cache.estimatedMemoryBytes / (1024 * 1024),
        },
        hysteresisActive: _hysteresisActive,
      ),
    );

    MemoryPressureLevel level;
    if (usagePercent > _criticalThresholdPercent) {
      level = MemoryPressureLevel.critical;
    } else if (usagePercent > _warningThresholdPercent) {
      level = MemoryPressureLevel.warning;
    } else {
      level = MemoryPressureLevel.normal;
    }

    _applyPressureLevel(level);
  }

  /// Apply a pressure level, evicting if necessary.
  void _applyPressureLevel(MemoryPressureLevel level) {
    final previous = _currentLevel;
    _currentLevel = level;

    // Always propagate to handler so external listeners are aware
    _memoryPressureHandler.notifyPressure(level);

    // Emit telemetry on level change (Enhancement 3)
    if (level != previous) {
      _emitEvent(
        MemoryPressureChanged(
          previous: previous,
          current: level,
          totalEstimatedMB: totalEstimatedMemoryMB,
        ),
      );
    }

    // ── Hysteresis check (Enhancement 4) ──
    if (level == MemoryPressureLevel.normal) {
      // Check if we can unlock hysteresis
      final usagePercent =
          _budgetCapMB > 0
              ? (totalEstimatedMemoryMB / _budgetCapMB) * 100
              : 0.0;
      if (_hysteresisActive && usagePercent < _lowWaterMarkPercent) {
        _hysteresisActive = false;
        _setRefillAllowed(true);
      }
      return;
    }

    // Only evict on escalation (not on same level)
    if (level.index <= previous.index &&
        level != MemoryPressureLevel.critical) {
      return;
    }

    // Cooldown check
    final now = DateTime.now();
    if (now.difference(_lastEvictionTime) < _evictionCooldown) return;
    _lastEvictionTime = now;

    _evictForPressure(level);

    // Activate hysteresis after eviction (Enhancement 4)
    if (!_hysteresisActive) {
      _hysteresisActive = true;
      _setRefillAllowed(false);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EVICTION ENGINE (Enhancement 2: Priority-weighted)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Evict from registered caches in priority order (cheap caches first).
  void _evictForPressure(MemoryPressureLevel level) {
    // Sort by eviction priority: lower priority value = evict first
    final ordered = List<_CacheRegistration>.from(_caches)..sort(
      (a, b) => a.cache.evictionPriority.compareTo(b.cache.evictionPriority),
    );

    final beforeBytes = <String, int>{};
    for (final reg in ordered) {
      beforeBytes[reg.cache.cacheName] = reg.cache.estimatedMemoryBytes;
    }

    for (final reg in ordered) {
      if (reg.cache.cacheEntryCount == 0) continue;

      try {
        switch (level) {
          case MemoryPressureLevel.warning:
            // At warning: evict only caches with priority < 50 first,
            // then the rest if still needed
            reg.cache.evictFraction(reg.warningFraction);
          case MemoryPressureLevel.critical:
            reg.cache.evictAll();
          case MemoryPressureLevel.normal:
            break; // Should not reach here
        }
      } catch (e) {
        // Never let a single cache failure block others
      }
    }

    // Emit telemetry (Enhancement 3)
    final freed = <String, int>{};
    int totalFreed = 0;
    for (final reg in ordered) {
      final before = beforeBytes[reg.cache.cacheName] ?? 0;
      final after = reg.cache.estimatedMemoryBytes;
      final delta = before - after;
      if (delta > 0) {
        freed[reg.cache.cacheName] = delta;
        totalFreed += delta;
      }
    }

    _emitEvent(
      MemoryEvictionPerformed(
        trigger: level,
        bytesFreedPerCache: freed,
        totalBytesFreedMB: totalFreed / (1024 * 1024),
      ),
    );
  }

  /// Manually trigger eviction at the given level.
  ///
  /// Useful for testing or when the app receives an OS memory warning
  /// through a different channel (e.g. `didReceiveMemoryWarning`).
  void forceEviction(MemoryPressureLevel level) {
    _lastEvictionTime = DateTime.fromMillisecondsSinceEpoch(
      0,
    ); // reset cooldown
    _applyPressureLevel(level);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HYSTERESIS HELPERS (Enhancement 4)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Set refill-allowed flag on all registered caches.
  void _setRefillAllowed(bool allowed) {
    for (final reg in _caches) {
      reg.cache.refillAllowed = allowed;
    }
  }

  /// Whether hysteresis refill-lock is currently active.
  bool get hysteresisActive => _hysteresisActive;

  // ═══════════════════════════════════════════════════════════════════════════
  // TELEMETRY (Enhancement 3)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Push-based stream of memory events for external dashboarding.
  Stream<MemoryEvent> get onMemoryEvent => _eventController.stream;

  void _emitEvent(MemoryEvent event) {
    if (!_eventController.isClosed) {
      _eventController.add(event);
    }

    // Bridge to unified telemetry bus + centralized event bus
    if (EngineScope.hasScope) {
      final scope = EngineScope.current;
      final t = scope.telemetry;
      if (event is MemoryEvictionPerformed) {
        t.counter('memory.evictions').increment();
        t.event('memory.eviction', {
          'trigger': event.trigger.name,
          'freedMB': event.totalBytesFreedMB,
        });
        scope.eventBus.emit(
          MemoryPressureEngineEvent(
            level: event.trigger.name,
            totalEstimatedMB: totalEstimatedMemoryMB,
            budgetCapMB: _budgetCapMB,
          ),
        );
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STATISTICS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Total estimated memory usage across all registered caches, in MB.
  double get totalEstimatedMemoryMB {
    int totalBytes = 0;
    for (final reg in _caches) {
      totalBytes += reg.cache.estimatedMemoryBytes;
    }
    return totalBytes / (1024 * 1024);
  }

  /// Current budget cap in MB (may have been auto-calibrated).
  int get budgetCapMB => _budgetCapMB;

  /// Current pressure level.
  MemoryPressureLevel get currentLevel => _currentLevel;

  /// Number of registered caches.
  int get registeredCacheCount => _caches.length;

  /// Whether adaptive calibration has been performed.
  bool get isCalibrated => _calibrated;

  /// Per-cache memory breakdown for diagnostics.
  Map<String, dynamic> get stats => {
    'currentLevel': _currentLevel.name,
    'totalEstimatedMB': totalEstimatedMemoryMB.toStringAsFixed(1),
    'budgetCapMB': _budgetCapMB,
    'warningThreshold': _warningThresholdPercent,
    'criticalThreshold': _criticalThresholdPercent,
    'lowWaterMark': _lowWaterMarkPercent,
    'hysteresisActive': _hysteresisActive,
    'isCalibrated': _calibrated,
    'isMonitoring': _isMonitoring,
    'caches': {
      for (final reg in _caches)
        reg.cache.cacheName: {
          'entries': reg.cache.cacheEntryCount,
          'memoryMB': (reg.cache.estimatedMemoryBytes / 1024 / 1024)
              .toStringAsFixed(1),
          'priority': reg.cache.evictionPriority,
          'refillAllowed': reg.cache.isRefillAllowed,
        },
    },
  };

  /// Dispose the controller (stops monitoring, closes streams).
  void dispose() {
    stopMonitoring();
    _caches.clear();
    _eventController.close();
  }
}

/// Internal: pairs a cache with its per-cache warning eviction fraction.
class _CacheRegistration {
  final MemoryManagedCache cache;
  final double warningFraction;

  const _CacheRegistration({
    required this.cache,
    required this.warningFraction,
  });
}
