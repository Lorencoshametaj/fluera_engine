import 'package:flutter/foundation.dart';

/// Centralized logging utility for the Fluera Engine.
///
/// Provides leveled logging (debug, info, warning, error) with consistent
/// formatting and optional stack traces. In release mode, only warnings
/// and errors are printed.
///
/// Usage:
/// ```dart
/// EngineLogger.info('Canvas loaded', tag: 'LayerController');
/// EngineLogger.warning('Fallback to default brush', error: e, tag: 'BrushEngine');
/// EngineLogger.error('Delta save failed', error: e, stack: stack, tag: 'WAL');
/// ```
class EngineLogger {
  EngineLogger._();

  /// Enable/disable all logging globally.
  static bool enabled = true;

  /// Log at debug level (suppressed in release builds).
  static void debug(String message, {String? tag, Object? error}) {
    if (!enabled) return;
    assert(() {
      _print('🔍', tag, message, error: error);
      return true;
    }());
  }

  /// Log at info level (suppressed in release builds).
  static void info(String message, {String? tag, Object? error}) {
    if (!enabled) return;
    assert(() {
      _print('ℹ️', tag, message, error: error);
      return true;
    }());
  }

  /// Log at warning level (always printed).
  static void warning(
    String message, {
    String? tag,
    Object? error,
    StackTrace? stack,
  }) {
    if (!enabled) return;
    _print('⚠️', tag, message, error: error, stack: stack);
  }

  /// Log at error level (always printed).
  static void error(
    String message, {
    String? tag,
    Object? error,
    StackTrace? stack,
  }) {
    if (!enabled) return;
    _print('❌', tag, message, error: error, stack: stack);
  }

  static void _print(
    String emoji,
    String? tag,
    String message, {
    Object? error,
    StackTrace? stack,
  }) {
    final prefix = tag != null ? '[$tag] ' : '';
    final buf = StringBuffer('$emoji $prefix$message');
    if (error != null) buf.write(' | Error: $error');
    if (stack != null) buf.write('\n$stack');
    // ignore: avoid_print
    print(buf.toString());
  }
}
