import 'package:flutter/foundation.dart';

/// 📊 Telemetry for PDF rendering pipeline.
///
/// Tracks cache hit rates, render latency, and eviction counts.
/// All metrics are lightweight counters — zero allocation overhead.
///
/// Usage:
/// ```dart
/// final stats = painter.stats;
/// debugPrint(stats.summary); // "Memory: 85% hit | Disk: 60% hit | Avg: 45ms | Evictions: 12"
/// ```
class PdfRenderStats {
  // ─── Counters ────────────────────────────────────────────────────────────
  int _memoryHits = 0;
  int _memoryMisses = 0;
  int _diskHits = 0;
  int _diskMisses = 0;
  int _nativeRenders = 0;
  int _renderErrors = 0;
  int _evictions = 0;
  int _diskEvictions = 0;

  // ─── Latency tracking (rolling average) ──────────────────────────────────
  int _totalRenderTimeMs = 0;
  int _renderCount = 0;

  // ─── Public API ──────────────────────────────────────────────────────────

  /// Record a memory cache hit (image already in RAM).
  void recordMemoryHit() => _memoryHits++;

  /// Record a memory cache miss (need disk or native render).
  void recordMemoryMiss() => _memoryMisses++;

  /// Record a disk cache hit (loaded from .gz file).
  void recordDiskHit() => _diskHits++;

  /// Record a disk cache miss (need native render).
  void recordDiskMiss() => _diskMisses++;

  /// Record a native render completion with duration.
  void recordNativeRender(int durationMs) {
    _nativeRenders++;
    _totalRenderTimeMs += durationMs;
    _renderCount++;
  }

  /// Record a render error (null image or exception).
  void recordRenderError() => _renderErrors++;

  /// Record a memory eviction (LRU or off-viewport).
  void recordEviction() => _evictions++;

  /// Record a disk eviction (budget enforcement).
  void recordDiskEviction() => _diskEvictions++;

  // ─── Computed metrics ────────────────────────────────────────────────────

  /// Memory cache hit rate (0.0 → 1.0).
  double get memoryHitRate {
    final total = _memoryHits + _memoryMisses;
    return total == 0 ? 0.0 : _memoryHits / total;
  }

  /// Disk cache hit rate (0.0 → 1.0).
  double get diskHitRate {
    final total = _diskHits + _diskMisses;
    return total == 0 ? 0.0 : _diskHits / total;
  }

  /// Average native render time in milliseconds.
  double get avgRenderTimeMs =>
      _renderCount == 0 ? 0.0 : _totalRenderTimeMs / _renderCount;

  /// Total native renders completed.
  int get totalNativeRenders => _nativeRenders;

  /// Total evictions (memory + disk).
  int get totalEvictions => _evictions + _diskEvictions;

  /// One-line summary for debug output.
  String get summary =>
      'Memory: ${(memoryHitRate * 100).toStringAsFixed(0)}% hit '
      '($_memoryHits/${_memoryHits + _memoryMisses}) | '
      'Disk: ${(diskHitRate * 100).toStringAsFixed(0)}% hit '
      '($_diskHits/${_diskHits + _diskMisses}) | '
      'Avg render: ${avgRenderTimeMs.toStringAsFixed(1)}ms | '
      'Evictions: $_evictions mem + $_diskEvictions disk | '
      'Errors: $_renderErrors';

  /// Reset all counters (e.g., on document close).
  void reset() {
    _memoryHits = 0;
    _memoryMisses = 0;
    _diskHits = 0;
    _diskMisses = 0;
    _nativeRenders = 0;
    _renderErrors = 0;
    _evictions = 0;
    _diskEvictions = 0;
    _totalRenderTimeMs = 0;
    _renderCount = 0;
  }

  @override
  String toString() => 'PdfRenderStats($summary)';
}
