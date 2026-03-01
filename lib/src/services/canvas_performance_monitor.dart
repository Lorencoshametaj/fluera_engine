import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Performance monitoring service for Professional Canvas.
///
/// Tracks real-time performance metrics with production-grade diagnostics:
/// - Frame time histogram with **P50/P90/P99 percentiles**
/// - Frame budget tracking (% of frames within 16.67ms)
/// - FPS with mini sparkline graph
/// - Memory usage (RSS)
/// - Jank detection and alerting
///
/// Usage:
/// ```dart
/// // In paint() method:
/// CanvasPerformanceMonitor.instance.startFrame();
/// // ... rendering ...
/// CanvasPerformanceMonitor.instance.endFrame(strokeCount);
///
/// // Toggle overlay:
/// CanvasPerformanceMonitor.instance.setEnabled(true);
/// ```
class CanvasPerformanceMonitor {
  static final CanvasPerformanceMonitor instance = CanvasPerformanceMonitor._();

  CanvasPerformanceMonitor._();

  // ═══════════════════════════════════════════════════════════════════
  // Frame time tracking
  // ═══════════════════════════════════════════════════════════════════

  /// Rolling window of per-frame durations (microseconds).
  final List<int> _frameTimesUs = [];

  /// 🖥️ Raster thread frame times (microseconds) from FrameTiming API.
  final List<int> _rasterTimesUs = [];

  /// FPS sparkline history (last 60 data points = ~30 seconds).
  final List<double> _fpsSparkline = [];

  /// Sliding window of frame-to-frame intervals for FPS.
  DateTime? _lastFrameStart;
  int _frameCount = 0;
  int _currentStrokeCount = 0;

  /// Jank counter: frames exceeding 2× budget.
  int _jankFrames = 0;
  int _totalFramesMeasured = 0;

  /// Whether the FrameTiming callback is registered.
  bool _timingsCallbackRegistered = false;

  /// Whether the overlay is collapsed (shows only FPS header).
  bool _isCollapsed = false;

  // ═══════════════════════════════════════════════════════════════════
  // Configuration
  // ═══════════════════════════════════════════════════════════════════

  static const double _targetFPS = 60.0;
  static const int _frameBudgetUs = 16667; // 16.67ms
  static const int _jankThresholdUs = _frameBudgetUs * 2; // >33.3ms = jank
  static const int _maxSamples = 120; // 2 seconds @ 60 FPS
  static const int _sparklinePoints = 60; // 30 seconds of sparkline

  bool _isEnabled = false;

  /// Enable/disable monitoring.
  void setEnabled(bool enabled) {
    _isEnabled = enabled;
    if (enabled) {
      _registerTimingsCallback();
    } else {
      _unregisterTimingsCallback();
      reset();
    }
  }

  bool get isEnabled => _isEnabled;

  /// Register Flutter's FrameTiming callback to capture raster thread times.
  void _registerTimingsCallback() {
    if (_timingsCallbackRegistered) return;
    _timingsCallbackRegistered = true;
    SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);
  }

  /// Unregister the FrameTiming callback.
  void _unregisterTimingsCallback() {
    if (!_timingsCallbackRegistered) return;
    _timingsCallbackRegistered = false;
    SchedulerBinding.instance.removeTimingsCallback(_onFrameTimings);
  }

  /// Callback for FrameTiming data — captures raster thread duration.
  void _onFrameTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      final rasterUs = timing.rasterDuration.inMicroseconds;
      _rasterTimesUs.add(rasterUs);
      if (_rasterTimesUs.length > _maxSamples) {
        _rasterTimesUs.removeAt(0);
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // Frame lifecycle
  // ═══════════════════════════════════════════════════════════════════

  /// Start frame measurement. Call at the beginning of paint().
  void startFrame() {
    if (!_isEnabled) return;
    _lastFrameStart = DateTime.now();
  }

  /// End frame measurement. Call at the end of paint().
  void endFrame(int strokeCount) {
    if (!_isEnabled || _lastFrameStart == null) return;

    _currentStrokeCount = strokeCount;
    final elapsed = DateTime.now().difference(_lastFrameStart!).inMicroseconds;

    // Store raw frame time
    _frameTimesUs.add(elapsed);
    if (_frameTimesUs.length > _maxSamples) {
      _frameTimesUs.removeAt(0);
    }

    // Track jank
    _totalFramesMeasured++;
    if (elapsed > _jankThresholdUs) _jankFrames++;

    // Update sparkline every 30 frames (~500ms)
    _frameCount++;
    if (_frameCount >= 30) {
      final avgUs =
          _frameTimesUs.isNotEmpty
              ? _frameTimesUs.reduce((a, b) => a + b) / _frameTimesUs.length
              : 16667.0;
      final fps = avgUs > 0 ? 1000000.0 / avgUs : 0.0;
      _fpsSparkline.add(fps.clamp(0, 120));
      if (_fpsSparkline.length > _sparklinePoints) {
        _fpsSparkline.removeAt(0);
      }
      _frameCount = 0;
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // Metrics computation
  // ═══════════════════════════════════════════════════════════════════

  /// Get comprehensive performance metrics snapshot.
  PerformanceMetrics getMetrics() {
    final sorted = List<int>.from(_frameTimesUs)..sort();
    final n = sorted.length;

    // Raster thread percentiles
    final rasterSorted = List<int>.from(_rasterTimesUs)..sort();
    final rn = rasterSorted.length;

    return PerformanceMetrics(
      currentFPS: _fpsSparkline.isNotEmpty ? _fpsSparkline.last : 0,
      avgFPS:
          _fpsSparkline.isNotEmpty
              ? _fpsSparkline.reduce((a, b) => a + b) / _fpsSparkline.length
              : 0,
      memoryUsageMB: _getMemoryUsage(),
      strokeCount: _currentStrokeCount,
      targetFPS: _targetFPS,
      // UI thread frame time percentiles
      p50FrameTimeMs: n > 0 ? sorted[n ~/ 2] / 1000.0 : 0,
      p90FrameTimeMs:
          n > 0 ? sorted[(n * 0.9).floor().clamp(0, n - 1)] / 1000.0 : 0,
      p99FrameTimeMs:
          n > 0 ? sorted[(n * 0.99).floor().clamp(0, n - 1)] / 1000.0 : 0,
      // Raster thread frame time percentiles
      rasterP50Ms: rn > 0 ? rasterSorted[rn ~/ 2] / 1000.0 : 0,
      rasterP90Ms:
          rn > 0
              ? rasterSorted[(rn * 0.9).floor().clamp(0, rn - 1)] / 1000.0
              : 0,
      rasterP99Ms:
          rn > 0
              ? rasterSorted[(rn * 0.99).floor().clamp(0, rn - 1)] / 1000.0
              : 0,
      // Budget
      frameBudgetPercent:
          n > 0
              ? sorted.where((t) => t <= _frameBudgetUs).length / n * 100
              : 100,
      // Jank
      jankPercent:
          _totalFramesMeasured > 0
              ? _jankFrames / _totalFramesMeasured * 100
              : 0,
      // Sparkline data
      fpsSparkline: List.unmodifiable(_fpsSparkline),
    );
  }

  /// Reset all metrics.
  void reset() {
    _frameTimesUs.clear();
    _rasterTimesUs.clear();
    _fpsSparkline.clear();
    _frameCount = 0;
    _currentStrokeCount = 0;
    _lastFrameStart = null;
    _jankFrames = 0;
    _totalFramesMeasured = 0;
  }

  double _getMemoryUsage() {
    try {
      return ProcessInfo.currentRss / (1024 * 1024);
    } catch (_) {
      return 0.0;
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // Debug Overlay Widget
  // ═══════════════════════════════════════════════════════════════════

  /// Build the enhanced debug overlay with sparkline, percentiles, and budget.
  Widget buildDebugOverlay() {
    if (!_isEnabled) return const SizedBox.shrink();

    return StreamBuilder(
      stream: Stream.periodic(const Duration(milliseconds: 500)),
      builder: (context, snapshot) {
        final m = getMetrics();
        final fpsColor =
            m.currentFPS >= 54
                ? const Color(0xFF4CAF50)
                : m.currentFPS >= 40
                ? const Color(0xFFFF9800)
                : const Color(0xFFF44336);

        return Positioned(
          top: 40,
          right: 10,
          child: GestureDetector(
            onTap: () => _isCollapsed = !_isCollapsed,
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              width: _isCollapsed ? 120 : 180,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xCC1A1A2E),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: fpsColor.withValues(alpha: 0.6)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── FPS header (always visible) ──
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${m.currentFPS.toStringAsFixed(0)} FPS',
                        style: TextStyle(
                          color: fpsColor,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          fontFamily: 'monospace',
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  m.frameBudgetPercent >= 95
                                      ? const Color(0xFF4CAF50)
                                      : m.frameBudgetPercent >= 80
                                      ? const Color(0xFFFF9800)
                                      : const Color(0xFFF44336),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${m.frameBudgetPercent.toStringAsFixed(0)}%',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (!_isCollapsed) ...[
                            const SizedBox(width: 4),
                            Icon(
                              Icons.expand_less,
                              color: Colors.white38,
                              size: 14,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),

                  // ── Expanded content ──
                  if (!_isCollapsed) ...[
                    const SizedBox(height: 6),

                    // ── Mini sparkline ──
                    if (m.fpsSparkline.length > 1)
                      CustomPaint(
                        size: const Size(160, 30),
                        painter: _SparklinePainter(m.fpsSparkline, fpsColor),
                      ),

                    const SizedBox(height: 8),

                    // ── UI thread percentiles ──
                    _sectionHeader('UI THREAD'),
                    _metricLine(
                      'P50',
                      '${m.p50FrameTimeMs.toStringAsFixed(1)}ms',
                      m.p50FrameTimeMs <= 8.33
                          ? Colors.green
                          : m.p50FrameTimeMs <= 16.67
                          ? Colors.orange
                          : Colors.red,
                    ),
                    _metricLine(
                      'P90',
                      '${m.p90FrameTimeMs.toStringAsFixed(1)}ms',
                      m.p90FrameTimeMs <= 8.33
                          ? Colors.green
                          : m.p90FrameTimeMs <= 16.67
                          ? Colors.orange
                          : Colors.red,
                    ),
                    _metricLine(
                      'P99',
                      '${m.p99FrameTimeMs.toStringAsFixed(1)}ms',
                      m.p99FrameTimeMs <= 16.67
                          ? Colors.green
                          : m.p99FrameTimeMs <= 33.3
                          ? Colors.orange
                          : Colors.red,
                    ),

                    const SizedBox(height: 4),

                    // ── Raster thread percentiles ──
                    _sectionHeader('RASTER'),
                    _metricLine(
                      'P50',
                      '${m.rasterP50Ms.toStringAsFixed(1)}ms',
                      m.rasterP50Ms <= 8.33
                          ? Colors.green
                          : m.rasterP50Ms <= 16.67
                          ? Colors.orange
                          : Colors.red,
                    ),
                    _metricLine(
                      'P90',
                      '${m.rasterP90Ms.toStringAsFixed(1)}ms',
                      m.rasterP90Ms <= 8.33
                          ? Colors.green
                          : m.rasterP90Ms <= 16.67
                          ? Colors.orange
                          : Colors.red,
                    ),
                    _metricLine(
                      'P99',
                      '${m.rasterP99Ms.toStringAsFixed(1)}ms',
                      m.rasterP99Ms <= 16.67
                          ? Colors.green
                          : m.rasterP99Ms <= 33.3
                          ? Colors.orange
                          : Colors.red,
                    ),

                    const Divider(color: Colors.white24, height: 12),

                    // ── Memory + strokes ──
                    _metricLine(
                      'MEM',
                      '${m.memoryUsageMB.toStringAsFixed(0)} MB',
                      m.memoryUsageMB < 300 ? Colors.white70 : Colors.orange,
                    ),
                    _metricLine('STR', '${m.strokeCount}', Colors.white70),
                    if (m.jankPercent > 0)
                      _metricLine(
                        'JANK',
                        '${m.jankPercent.toStringAsFixed(1)}%',
                        m.jankPercent < 1
                            ? Colors.green
                            : m.jankPercent < 5
                            ? Colors.orange
                            : Colors.red,
                      ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _metricLine(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2, top: 2),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          fontFamily: 'monospace',
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Sparkline Painter
// ═══════════════════════════════════════════════════════════════════════════

class _SparklinePainter extends CustomPainter {
  final List<double> data;
  final Color color;

  _SparklinePainter(this.data, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;

    final maxVal = data.reduce(math.max).clamp(60.0, 120.0);
    final minVal = data.reduce(math.min).clamp(0.0, 60.0);
    final range = maxVal - minVal;

    // 60 FPS reference line
    final refY =
        size.height -
        ((60 - minVal) / range * size.height).clamp(0, size.height);
    canvas.drawLine(
      Offset(0, refY),
      Offset(size.width, refY),
      Paint()
        ..color = Colors.white10
        ..strokeWidth = 1,
    );

    // Sparkline path
    final path = Path();
    final fillPath = Path();
    for (int i = 0; i < data.length; i++) {
      final x = i / (data.length - 1) * size.width;
      final y =
          size.height -
          ((data[i] - minVal) / range * size.height).clamp(0, size.height);
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }
    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    // Fill gradient
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.3), color.withValues(alpha: 0.0)],
        ).createShader(Offset.zero & size),
    );

    // Line
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_SparklinePainter old) => true;
}

// ═══════════════════════════════════════════════════════════════════════════
// Performance Metrics Snapshot
// ═══════════════════════════════════════════════════════════════════════════

/// Comprehensive performance metrics snapshot.
class PerformanceMetrics {
  final double currentFPS;
  final double avgFPS;
  final double memoryUsageMB;
  final int strokeCount;
  final double targetFPS;

  /// Frame time at the 50th percentile (median).
  final double p50FrameTimeMs;

  /// Frame time at the 90th percentile.
  final double p90FrameTimeMs;

  /// Frame time at the 99th percentile (worst-case).
  final double p99FrameTimeMs;

  /// Raster thread frame time at the 50th percentile.
  final double rasterP50Ms;

  /// Raster thread frame time at the 90th percentile.
  final double rasterP90Ms;

  /// Raster thread frame time at the 99th percentile.
  final double rasterP99Ms;

  /// Percentage of frames delivered within 16.67ms budget.
  final double frameBudgetPercent;

  /// Percentage of frames exceeding 2× budget (33.3ms).
  final double jankPercent;

  /// FPS sparkline data for mini graph.
  final List<double> fpsSparkline;

  const PerformanceMetrics({
    required this.currentFPS,
    required this.avgFPS,
    required this.memoryUsageMB,
    required this.strokeCount,
    required this.targetFPS,
    this.p50FrameTimeMs = 0,
    this.p90FrameTimeMs = 0,
    this.p99FrameTimeMs = 0,
    this.rasterP50Ms = 0,
    this.rasterP90Ms = 0,
    this.rasterP99Ms = 0,
    this.frameBudgetPercent = 100,
    this.jankPercent = 0,
    this.fpsSparkline = const [],
  });

  @override
  String toString() =>
      'PerformanceMetrics(FPS: ${currentFPS.toStringAsFixed(1)}/${targetFPS.toInt()}, '
      'UI[P50: ${p50FrameTimeMs.toStringAsFixed(1)}ms, P90: ${p90FrameTimeMs.toStringAsFixed(1)}ms, P99: ${p99FrameTimeMs.toStringAsFixed(1)}ms], '
      'Raster[P50: ${rasterP50Ms.toStringAsFixed(1)}ms, P90: ${rasterP90Ms.toStringAsFixed(1)}ms, P99: ${rasterP99Ms.toStringAsFixed(1)}ms], '
      'Budget: ${frameBudgetPercent.toStringAsFixed(0)}%, '
      'Jank: ${jankPercent.toStringAsFixed(1)}%, '
      'Memory: ${memoryUsageMB.toStringAsFixed(1)} MB)';
}
