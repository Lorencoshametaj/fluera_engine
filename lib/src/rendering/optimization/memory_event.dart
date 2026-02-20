/// 📊 MEMORY EVENTS — Push-based telemetry for the memory management system.
///
/// Subscribe to [MemoryBudgetController.onMemoryEvent] to receive
/// real-time notifications about pressure changes, eviction actions,
/// and periodic budget snapshots.
///
/// ```dart
/// controller.onMemoryEvent.listen((event) {
///   switch (event) {
///     case MemoryPressureChanged e: log('${e.previous} → ${e.current}');
///     case MemoryEvictionPerformed e: log('Freed ${e.totalBytesFreedMB} MB');
///     case MemoryBudgetSnapshot e: log('${e.usagePercent}% used');
///   }
/// });
/// ```
library;

import '../optimization/frame_budget_manager.dart';

/// Base class for all memory telemetry events.
sealed class MemoryEvent {
  /// When the event occurred.
  final DateTime timestamp;

  MemoryEvent() : timestamp = DateTime.now();
}

/// Emitted when the memory pressure level changes (e.g. normal → warning).
class MemoryPressureChanged extends MemoryEvent {
  /// Previous pressure level before the change.
  final MemoryPressureLevel previous;

  /// New (current) pressure level.
  final MemoryPressureLevel current;

  /// Total estimated memory across all registered caches at the time.
  final double totalEstimatedMB;

  MemoryPressureChanged({
    required this.previous,
    required this.current,
    required this.totalEstimatedMB,
  });

  @override
  String toString() =>
      'MemoryPressureChanged($previous → $current, ${totalEstimatedMB.toStringAsFixed(1)} MB)';
}

/// Emitted after an eviction pass completes across registered caches.
class MemoryEvictionPerformed extends MemoryEvent {
  /// The pressure level that triggered this eviction.
  final MemoryPressureLevel trigger;

  /// Bytes freed per cache: `{cacheName: bytesFreed}`.
  final Map<String, int> bytesFreedPerCache;

  /// Total bytes freed across all caches, in MB.
  final double totalBytesFreedMB;

  MemoryEvictionPerformed({
    required this.trigger,
    required this.bytesFreedPerCache,
    required this.totalBytesFreedMB,
  });

  @override
  String toString() =>
      'MemoryEvictionPerformed($trigger, freed ${totalBytesFreedMB.toStringAsFixed(1)} MB)';
}

/// Periodic snapshot of the budget state — emitted every scan cycle.
class MemoryBudgetSnapshot extends MemoryEvent {
  /// Total estimated memory across all caches, in MB.
  final double totalEstimatedMB;

  /// Configured budget cap in MB (may be adaptive).
  final int budgetCapMB;

  /// Usage as percentage: `totalEstimatedMB / budgetCapMB * 100`.
  final double usagePercent;

  /// Per-cache breakdown: `{cacheName: estimatedMB}`.
  final Map<String, double> perCacheMB;

  /// Whether hysteresis refill-lock is active.
  final bool hysteresisActive;

  MemoryBudgetSnapshot({
    required this.totalEstimatedMB,
    required this.budgetCapMB,
    required this.usagePercent,
    required this.perCacheMB,
    required this.hysteresisActive,
  });

  @override
  String toString() =>
      'MemoryBudgetSnapshot(${usagePercent.toStringAsFixed(0)}%, ${totalEstimatedMB.toStringAsFixed(1)}/${budgetCapMB} MB)';
}
