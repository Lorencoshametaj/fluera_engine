import 'dart:async';
import 'package:flutter/scheduler.dart';
import './native_display_plugin.dart';

/// 🖥️ DISPLAY CAPABILITIES DETECTOR
///
/// Detects automaticamente le capability of the display (refresh rate, ecc.)
/// with double strategy:
/// 1. **Native detection** (Android): Reads HW directly and forces 120Hz
/// 2. **Frame sampling** (fallback iOS/Desktop): Frame interval sampling
///
/// Uso:
/// ```dart
/// final caps = await DisplayCapabilitiesDetector.detect();
/// print('Refresh rate: ${caps.refreshRate.value}Hz');
/// print('Frame budget: ${caps.frameBudgetMs}ms');
/// ```
class DisplayCapabilitiesDetector {
  /// Detects le capability of the display con native plugin + fallback
  static Future<DisplayCapabilities> detect() async {
    // 🚀 STEP 1: Prova native detection (Android)
    try {
      final nativeRate = await NativeDisplayPlugin.getNativeRefreshRate();

      if (nativeRate != null) {

        // If is 120Hz+, forza Flutter a usarlo
        if (nativeRate >= 110) {
          await NativeDisplayPlugin.setPreferredRefreshRate(nativeRate);
        }

        final refreshRate = _normalizeRefreshRate(nativeRate.toDouble());
        return DisplayCapabilities(
          refreshRate: refreshRate,
          frameBudgetMs: 1000.0 / refreshRate.value,
          isHighRefreshRate: refreshRate.value >= 90,
        );
      }
    } catch (e) {
    }

    // 🔄 STEP 2: Fallback to frame-based detection (iOS/Desktop)
    return _detectViaFrameSampling();
  }

  /// Frame-based detection (fallback per iOS/Desktop)
  static Future<DisplayCapabilities> _detectViaFrameSampling() async {
    final Completer<DisplayCapabilities> completer = Completer();

    // Sampling variables
    DateTime? firstFrameTime;
    DateTime? lastFrameTime;
    int frameCount = 0;
    const int warmupFrames = 30; // Scarta primi 30 frame (warm-up)
    const int targetSamples = 90; // Poi campiona 90 frame per accuracy
    const int totalFrames = warmupFrames + targetSamples;

    // Callback for every frame
    void frameCallback(Duration timestamp) {
      final now = DateTime.now();
      frameCount++;

      // Skip warm-up period (frame iniziali sono more lenti)
      if (frameCount <= warmupFrames) {
        SchedulerBinding.instance.scheduleFrameCallback(frameCallback);
        return;
      }

      // Start campionamento DOPO warm-up
      firstFrameTime ??= now;

      lastFrameTime = now;

      // Quando abbiamo abbastanza campioni, calcola refresh rate
      if (frameCount >= totalFrames) {
        final totalDuration = lastFrameTime!.difference(firstFrameTime!);
        final avgFrameTimeMs =
            totalDuration.inMicroseconds / targetSamples / 1000.0;
        final detectedRefreshRate = 1000.0 / avgFrameTimeMs; // Hz

        // 🔍 DEBUG: Detailed log for troubleshooting

        // Normalize a valori standard
        final refreshRate = _normalizeRefreshRate(detectedRefreshRate);

        completer.complete(
          DisplayCapabilities(
            refreshRate: refreshRate,
            frameBudgetMs: 1000.0 / refreshRate.value,
            isHighRefreshRate: refreshRate.value >= 90,
          ),
        );
      } else {
        // Continua a campionare
        SchedulerBinding.instance.scheduleFrameCallback(frameCallback);
      }
    }

    // Avvia campionamento
    SchedulerBinding.instance.scheduleFrameCallback(frameCallback);

    return completer.future;
  }

  /// Normalize il refresh rate rilevato a valori standard
  static RefreshRate _normalizeRefreshRate(double detected) {
    // Tolerance ±5Hz to account for variations
    if (detected > 135) {
      return RefreshRate.hz144;
    } else if (detected > 110) {
      return RefreshRate.hz120;
    } else if (detected > 75) {
      return RefreshRate.hz90;
    } else {
      return RefreshRate.hz60;
    }
  }
}

/// Enum per refresh rate standard
enum RefreshRate {
  hz60(60),
  hz90(90),
  hz120(120),
  hz144(144);

  final int value;
  const RefreshRate(this.value);

  @override
  String toString() => '${value}Hz';
}

/// Detected display capabilities
class DisplayCapabilities {
  /// Refresh rate of the display
  final RefreshRate refreshRate;

  /// Frame budget in millisecondi (es. 8.33ms @ 120Hz)
  final double frameBudgetMs;

  /// True if display supports high refresh rate (>= 90Hz)
  final bool isHighRefreshRate;

  const DisplayCapabilities({
    required this.refreshRate,
    required this.frameBudgetMs,
    required this.isHighRefreshRate,
  });

  @override
  String toString() {
    return 'DisplayCapabilities('
        'refreshRate: $refreshRate, '
        'frameBudget: ${frameBudgetMs.toStringAsFixed(2)}ms, '
        'highRefresh: $isHighRefreshRate'
        ')';
  }
}
