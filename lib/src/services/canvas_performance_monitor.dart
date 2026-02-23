import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';

/// Performance monitoring service for Professional Canvas.
///
/// Tracks real-time performance metrics:
/// - FPS (Frames Per Second)
/// - Memory usage
/// - Render time per frame
/// - Stroke count
/// - Auto-detection of performance bottlenecks
///
/// Usage:
/// ```dart
/// // In paint() method:
/// CanvasPerformanceMonitor.instance.startFrame();
/// // ... rendering ...
/// CanvasPerformanceMonitor.instance.endFrame(strokeCount);
///
/// // Get metrics:
/// final metrics = CanvasPerformanceMonitor.instance.getMetrics();
/// print('FPS: ${metrics.currentFPS}');
/// ```
class CanvasPerformanceMonitor {
  static final CanvasPerformanceMonitor instance = CanvasPerformanceMonitor._();

  CanvasPerformanceMonitor._();

  // Metrics storage
  final List<double> _fpsHistory = [];
  final List<Duration> _renderTimeHistory = [];
  DateTime? _lastFrameTime;
  int _frameCount = 0;
  int _currentStrokeCount = 0;

  // Performance thresholds
  static const double _lowFPSThreshold = 50.0;
  static const double _targetFPS = 60.0;
  static const int _sampleSize = 60; // 1 second @ 60 FPS

  // Controls
  bool _isEnabled = false;

  /// Enable/disable monitoring
  void setEnabled(bool enabled) {
    _isEnabled = enabled;
    if (!enabled) {
      reset();
    }
  }

  bool get isEnabled => _isEnabled;

  /// Start frame measurement
  void startFrame() {
    if (!_isEnabled) return;
    _lastFrameTime = DateTime.now();
  }

  /// End frame measurement
  void endFrame(int strokeCount) {
    if (!_isEnabled) return;
    if (_lastFrameTime == null) return;

    _currentStrokeCount = strokeCount;

    final now = DateTime.now();
    final renderTime = now.difference(_lastFrameTime!);
    _renderTimeHistory.add(renderTime);

    // Calculate FPS
    _frameCount++;
    if (_frameCount >= _sampleSize) {
      final avgRenderTimeMs =
          _calculateAverageDuration(_renderTimeHistory).inMicroseconds / 1000.0;
      final fps = avgRenderTimeMs > 0 ? 1000.0 / avgRenderTimeMs : 0.0;
      _fpsHistory.add(fps);

      // Keep history limited
      if (_fpsHistory.length > 100) {
        _fpsHistory.removeAt(0);
      }

      // Auto-detect issues
      if (fps < _lowFPSThreshold) {
        _logPerformanceWarning('Low FPS detected: ${fps.toStringAsFixed(1)}');
      }

      _frameCount = 0;
      _renderTimeHistory.clear();
    }
  }

  /// Get current metrics
  PerformanceMetrics getMetrics() {
    return PerformanceMetrics(
      currentFPS: _fpsHistory.isNotEmpty ? _fpsHistory.last : 0,
      avgFPS: _fpsHistory.isNotEmpty ? _calculateAverage(_fpsHistory) : 0,
      memoryUsageMB: _getMemoryUsage(),
      strokeCount: _currentStrokeCount,
      targetFPS: _targetFPS,
    );
  }

  /// Reset all metrics
  void reset() {
    _fpsHistory.clear();
    _renderTimeHistory.clear();
    _frameCount = 0;
    _currentStrokeCount = 0;
    _lastFrameTime = null;
  }

  // Helper methods

  double _calculateAverage(List<double> values) {
    if (values.isEmpty) return 0;
    return values.reduce((a, b) => a + b) / values.length;
  }

  Duration _calculateAverageDuration(List<Duration> durations) {
    if (durations.isEmpty) return Duration.zero;
    final totalMicros = durations.fold<int>(
      0,
      (sum, d) => sum + d.inMicroseconds,
    );
    return Duration(microseconds: totalMicros ~/ durations.length);
  }

  double _getMemoryUsage() {
    // Get current process memory (in MB)
    // Note: ProcessInfo is only available on desktop/mobile, not web
    try {
      final info = ProcessInfo.currentRss;
      return info / (1024 * 1024); // Convert bytes to MB
    } catch (e) {
      return 0.0; // Fallback for platforms that don't support this
    }
  }

  void _logPerformanceWarning(String message) {}

  /// Build debug overlay widget
  Widget buildDebugOverlay() {
    if (!_isEnabled) return const SizedBox.shrink();

    return StreamBuilder(
      stream: Stream.periodic(const Duration(milliseconds: 500)),
      builder: (context, snapshot) {
        final metrics = getMetrics();
        return Stack(
          children: [
            Positioned(
              top: 40,
              right: 10,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color:
                        metrics.currentFPS < _lowFPSThreshold
                            ? Colors.red.withValues(alpha: 0.5)
                            : Colors.green.withValues(alpha: 0.5),
                    width: 2,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildMetricRow(
                      '📊 FPS',
                      '${metrics.currentFPS.toStringAsFixed(1)} / ${metrics.targetFPS.toInt()}',
                      metrics.currentFPS >= metrics.targetFPS * 0.9
                          ? Colors.green
                          : metrics.currentFPS >= _lowFPSThreshold
                          ? Colors.orange
                          : Colors.red,
                    ),
                    const SizedBox(height: 4),
                    _buildMetricRow(
                      '📈 Avg FPS',
                      metrics.avgFPS.toStringAsFixed(1),
                      Colors.white70,
                    ),
                    const SizedBox(height: 4),
                    _buildMetricRow(
                      '💾 Memory',
                      '${metrics.memoryUsageMB.toStringAsFixed(1)} MB',
                      Colors.white70,
                    ),
                    const SizedBox(height: 4),
                    _buildMetricRow(
                      '✏️ Strokes',
                      metrics.strokeCount.toString(),
                      Colors.white70,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMetricRow(String label, String value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

/// Performance metrics snapshot
class PerformanceMetrics {
  final double currentFPS;
  final double avgFPS;
  final double memoryUsageMB;
  final int strokeCount;
  final double targetFPS;

  const PerformanceMetrics({
    required this.currentFPS,
    required this.avgFPS,
    required this.memoryUsageMB,
    required this.strokeCount,
    required this.targetFPS,
  });

  @override
  String toString() {
    return 'PerformanceMetrics('
        'FPS: ${currentFPS.toStringAsFixed(1)}/${targetFPS.toInt()}, '
        'Avg: ${avgFPS.toStringAsFixed(1)}, '
        'Memory: ${memoryUsageMB.toStringAsFixed(1)} MB, '
        'Strokes: $strokeCount)';
  }
}
