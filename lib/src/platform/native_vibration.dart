import 'package:flutter/services.dart';

/// 📳 Native wrapper for vibration management
///
/// Supporta:
/// - Simple vibration with custom duration
/// - Pattern di vibrazione complessi
/// - Controllo dell'intensity (ampiezza)
/// - Cancel active vibration
/// - Verify disponibilità hardware
///
/// Esempio d'uso:
/// ```dart
/// // Verify disponibilità
/// bool? hasVibrator = await NativeVibration.hasVibrator();
///
/// // Vibrazione semplice (400ms)
/// await NativeVibration.vibrate();
///
/// // Vibration with duration and intensity
/// await NativeVibration.vibrate(duration: 1000, amplitude: 180);
///
/// // Pattern complesso (pausa-vibra-pausa-vibra)
/// await NativeVibration.vibrate(
///   pattern: [0, 1000, 500, 1000],
///   intensities: [255, 180]
/// );
///
/// // Stops vibration
/// await NativeVibration.cancel();
/// ```
class NativeVibration {
  // Method Channel
  static const MethodChannel _channel = MethodChannel(
    'nebulaengine.vibration/method',
  );

  // Private constructor
  NativeVibration._();

  /// Check if the device has a vibrator
  static Future<bool?> hasVibrator() async {
    try {
      final bool? result = await _channel.invokeMethod<bool>('hasVibrator');
      return result;
    } catch (e) {
      return null;
    }
  }

  /// Execute a vibration
  ///
  /// Parameters:
  /// - [duration]: Duration in milliseconds (default: 400ms)
  /// - [amplitude]: Vibration intensity 0-255 (default: 255 = max)
  /// - [pattern]: List of durations alternating pause-vibration-pause-vibration
  /// - [intensities]: List of intensities for each vibration step in the pattern
  ///
  /// Platform notes:
  /// - **iOS 13+**: Full support via Core Haptics
  /// - **iOS < 13**: Standard vibration (400ms), no amplitude control
  /// - **Android 8.0+**: Full support for duration, amplitude and patterns
  /// - **Android < 8.0**: Duration and pattern only, no amplitude control
  static Future<void> vibrate({
    int? duration,
    int? amplitude,
    List<int>? pattern,
    List<int>? intensities,
  }) async {
    try {
      if (amplitude != null && (amplitude < 0 || amplitude > 255)) {
        throw ArgumentError(
          'amplitude must be between 0 and 255, got: $amplitude',
        );
      }

      if (pattern != null) {
        if (pattern.isEmpty) {
          throw ArgumentError('pattern cannot be empty');
        }
        if (pattern.any((d) => d < 0)) {
          throw ArgumentError('pattern can only contain values >= 0');
        }
      }

      if (intensities != null) {
        if (intensities.any((i) => i < 0 || i > 255)) {
          throw ArgumentError(
            'intensities must contain values between 0 and 255',
          );
        }
      }

      // Prepare arguments
      final Map<String, dynamic> args = {};

      if (pattern != null) {
        args['pattern'] = pattern;
        if (intensities != null) {
          args['intensities'] = intensities;
        }
      } else {
        if (duration != null) {
          args['duration'] = duration;
        }
        if (amplitude != null) {
          args['amplitude'] = amplitude;
        }
      }

      await _channel.invokeMethod('vibrate', args);
    } on PlatformException {
      rethrow;
    } catch (e) {
      rethrow;
    }
  }

  /// Cancel any active vibration
  static Future<void> cancel() async {
    try {
      await _channel.invokeMethod('cancel');
    } on PlatformException {
      rethrow;
    } catch (e) {
      rethrow;
    }
  }

  // MARK: - Helper Methods

  /// Light vibration (200ms, medium intensity)
  static Future<void> light() async {
    await vibrate(duration: 200, amplitude: 128);
  }

  /// Medium vibration (400ms, high intensity)
  static Future<void> medium() async {
    await vibrate(duration: 400, amplitude: 200);
  }

  /// Heavy vibration (600ms, max intensity)
  static Future<void> heavy() async {
    await vibrate(duration: 600, amplitude: 255);
  }

  /// Success pattern (two short bursts)
  static Future<void> success() async {
    await vibrate(pattern: [0, 100, 100, 100], intensities: [200, 200]);
  }

  /// Error pattern (medium-short-short)
  static Future<void> error() async {
    await vibrate(
      pattern: [0, 300, 100, 150, 100, 150],
      intensities: [255, 200, 200],
    );
  }

  /// Warning pattern (long-pause-long)
  static Future<void> warning() async {
    await vibrate(pattern: [0, 500, 300, 500], intensities: [255, 255]);
  }

  /// Notification pattern (triple short burst)
  static Future<void> notification() async {
    await vibrate(
      pattern: [0, 100, 100, 100, 100, 100],
      intensities: [180, 180, 180],
    );
  }

  /// Alarm pattern (insistent continuous vibration with variations)
  static Future<void> alarm() async {
    await vibrate(
      pattern: [0, 1000, 500, 1000, 500, 1000],
      intensities: [255, 255, 255],
    );
  }
}
