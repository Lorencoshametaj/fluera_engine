import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../core/latex/ink_stroke_data.dart';
import 'latex_recognition_bridge.dart';
import 'ink_rasterizer.dart';

/// 🧮 NativeLatexRecognizer — concrete ML recognition using Platform Channels.
///
/// Implements [LatexRecognitionBridge] by communicating with native modules:
/// - **iOS**: Swift `LatexRecognizerPlugin` using Core ML
/// - **Android**: Kotlin `LatexRecognizerPlugin` using TFLite
///
/// The flow:
/// 1. Dart rasterizes ink strokes into a 256×256 PNG
/// 2. PNG bytes are sent to native via [MethodChannel]
/// 3. Native runs ML inference and returns JSON result
/// 4. Dart parses the JSON into [LatexRecognitionResult]
///
/// Example:
/// ```dart
/// final recognizer = NativeLatexRecognizer();
/// await recognizer.initialize();
/// if (await recognizer.isAvailable()) {
///   final result = await recognizer.recognize(inkData);
///   print(result.latexString);
/// }
/// ```
class NativeLatexRecognizer implements LatexRecognitionBridge {
  /// Platform channel for communicating with native ML inference code.
  static const MethodChannel _channel = MethodChannel(
    'fluera_engine/latex_recognition',
  );

  bool _initialized = false;
  bool _modelAvailable = false;
  bool _warmingUp = false;

  /// Whether the model has been loaded and is ready for inference.
  bool get isWarmedUp => _initialized && _modelAvailable;

  /// Eagerly warm up the ML model in the background.
  ///
  /// Call this at app start or when a notebook is opened to avoid
  /// the 500ms–1.5s cold-start penalty on the first recognition.
  /// Safe to call multiple times — subsequent calls are no-ops.
  ///
  /// ```dart
  /// // In your app's init:
  /// final recognizer = NativeLatexRecognizer();
  /// recognizer.warmUp(); // fire-and-forget
  /// ```
  Future<void> warmUp({Duration timeout = const Duration(seconds: 5)}) async {
    if (_initialized || _warmingUp) return;
    _warmingUp = true;
    try {
      await initialize().timeout(
        timeout,
        onTimeout: () {
          debugPrint(
            '[NativeLatexRecognizer] warm-up timed out after ${timeout.inSeconds}s',
          );
        },
      );
    } catch (e) {
      debugPrint('[NativeLatexRecognizer] warm-up failed: $e');
    } finally {
      _warmingUp = false;
    }
  }

  @override
  Future<void> initialize() async {
    if (_initialized) return;

    final stopwatch = Stopwatch()..start();
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'initialize',
      );
      _modelAvailable = result?['available'] as bool? ?? false;
      _initialized = true;
      stopwatch.stop();
      debugPrint(
        '[NativeLatexRecognizer] initialized in ${stopwatch.elapsedMilliseconds}ms, '
        'model available: $_modelAvailable',
      );
    } on PlatformException catch (e) {
      debugPrint('[NativeLatexRecognizer] initialization failed: ${e.message}');
      _initialized = true;
      _modelAvailable = false;
    } on MissingPluginException {
      // Platform channel not implemented (e.g. running on desktop/web)
      debugPrint('[NativeLatexRecognizer] platform not supported');
      _initialized = true;
      _modelAvailable = false;
    }
  }

  @override
  Future<bool> isAvailable() async {
    if (!_initialized) await initialize();
    return _modelAvailable;
  }

  @override
  Future<LatexRecognitionResult> recognize(InkData inkData) async {
    if (!_initialized) {
      throw const LatexRecognitionException('Recognizer not initialized');
    }
    if (!_modelAvailable) {
      throw const LatexRecognitionException('ML model not available');
    }
    if (inkData.isEmpty) {
      throw const LatexRecognitionException('No ink data to recognize');
    }

    // 1. Rasterize ink strokes to PNG bitmap
    final stopwatch = Stopwatch()..start();
    final pngBytes = await InkRasterizer.rasterize(inkData);
    if (pngBytes == null) {
      throw const LatexRecognitionException('Failed to rasterize ink data');
    }

    // 2. Send to native for ML inference
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'recognize',
        {'imageBytes': pngBytes},
      );
      stopwatch.stop();

      if (result == null) {
        throw const LatexRecognitionException('Native inference returned null');
      }

      // 3. Parse the result
      return LatexRecognitionResult(
        latexString: result['latex'] as String? ?? '',
        confidence: (result['confidence'] as num?)?.toDouble() ?? 0.0,
        alternatives: _parseAlternatives(result['alternatives']),
        perSymbolConfidence: _parseSymbolConfidences(
          result['perSymbolConfidence'],
        ),
        inferenceTimeMs: stopwatch.elapsedMilliseconds,
      );
    } on PlatformException catch (e) {
      throw LatexRecognitionException(
        'Native inference failed: ${e.message}',
        cause: e,
      );
    }
  }

  @override
  Future<LatexRecognitionResult> recognizeImage(Uint8List imageBytes) async {
    if (!_initialized) {
      throw const LatexRecognitionException('Recognizer not initialized');
    }
    if (!_modelAvailable) {
      throw const LatexRecognitionException('ML model not available');
    }

    final stopwatch = Stopwatch()..start();
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'recognize',
        {'imageBytes': imageBytes},
      );
      stopwatch.stop();

      if (result == null) {
        throw const LatexRecognitionException('Native inference returned null');
      }

      return LatexRecognitionResult(
        latexString: result['latex'] as String? ?? '',
        confidence: (result['confidence'] as num?)?.toDouble() ?? 0.0,
        alternatives: _parseAlternatives(result['alternatives']),
        perSymbolConfidence: _parseSymbolConfidences(
          result['perSymbolConfidence'],
        ),
        inferenceTimeMs: stopwatch.elapsedMilliseconds,
      );
    } on PlatformException catch (e) {
      throw LatexRecognitionException(
        'Native inference failed: ${e.message}',
        cause: e,
      );
    }
  }

  @override
  void dispose() {
    _initialized = false;
    _modelAvailable = false;
    try {
      _channel.invokeMethod<void>('dispose');
    } catch (_) {
      // Best effort — don't crash on dispose
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  List<LatexAlternative> _parseAlternatives(dynamic raw) {
    if (raw == null || raw is! List) return [];
    return raw.map((item) {
      if (item is Map) {
        return LatexAlternative(
          latexString: item['latex'] as String? ?? '',
          confidence: (item['confidence'] as num?)?.toDouble() ?? 0.0,
        );
      }
      return const LatexAlternative(latexString: '', confidence: 0.0);
    }).toList();
  }

  List<SymbolConfidence> _parseSymbolConfidences(dynamic raw) {
    if (raw == null || raw is! List) return [];
    return raw.map((item) {
      if (item is Map) {
        return SymbolConfidence(
          token: item['token'] as String? ?? '',
          startIndex: item['startIndex'] as int? ?? 0,
          endIndex: item['endIndex'] as int? ?? 0,
          confidence: (item['confidence'] as num?)?.toDouble() ?? 0.0,
        );
      }
      return const SymbolConfidence(
        token: '',
        startIndex: 0,
        endIndex: 0,
        confidence: 0.0,
      );
    }).toList();
  }
}

/// 🧪 Mock recognizer for testing and preview without ML model.
///
/// Returns a fixed or configurable LaTeX string, useful for unit tests
/// and UI development when the ML model isn't available.
class MockLatexRecognizer implements LatexRecognitionBridge {
  /// The LaTeX string to return from [recognize].
  final String mockResult;

  /// The confidence score to return.
  final double mockConfidence;

  /// Artificial delay to simulate inference time.
  final Duration delay;

  const MockLatexRecognizer({
    this.mockResult = r'\frac{a}{b}',
    this.mockConfidence = 0.95,
    this.delay = const Duration(milliseconds: 100),
  });

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<LatexRecognitionResult> recognize(InkData inkData) async {
    await Future.delayed(delay);
    return LatexRecognitionResult(
      latexString: mockResult,
      confidence: mockConfidence,
      inferenceTimeMs: delay.inMilliseconds,
    );
  }

  @override
  Future<LatexRecognitionResult> recognizeImage(Uint8List imageBytes) async {
    await Future.delayed(delay);
    return LatexRecognitionResult(
      latexString: mockResult,
      confidence: mockConfidence,
      inferenceTimeMs: delay.inMilliseconds,
    );
  }

  @override
  void dispose() {}
}
