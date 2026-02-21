import 'dart:typed_data';

import '../core/latex/ink_stroke_data.dart';

/// 🧮 LaTeX Recognition Bridge — abstract interface for ML-based recognition.
///
/// This bridge abstracts the recognition backend, allowing the Dart layer
/// to invoke handwriting or image-based recognition without knowing
/// the underlying engine (pix2tex, ML Kit, custom model, etc.).
///
/// The pipeline supports two input modes:
/// 1. **Ink strokes** via [InkData] → rasterized internally → recognized
/// 2. **Direct images** via [Uint8List] → recognized (screenshots, PDF, photos)
///
/// Example:
/// ```dart
/// final bridge = Pix2TexRecognizer();
/// await bridge.initialize();
///
/// // From handwriting
/// final result = await bridge.recognize(inkData);
///
/// // From screenshot
/// final imgResult = await bridge.recognizeImage(pngBytes);
/// print(imgResult.latexString); // e.g. "\frac{a}{b}"
/// ```
abstract class LatexRecognitionBridge {
  /// Initialize the recognition backend and allocate resources.
  ///
  /// Must be called before [recognize] or [recognizeImage].
  /// Safe to call multiple times.
  Future<void> initialize();

  /// Recognize handwritten LaTeX from ink stroke data.
  ///
  /// The implementation may rasterize the strokes to an image internally.
  ///
  /// Returns a [LatexRecognitionResult] with the best-guess LaTeX string,
  /// overall confidence score, and alternative suggestions.
  ///
  /// Throws [LatexRecognitionException] if the backend is not initialized
  /// or if recognition fails.
  Future<LatexRecognitionResult> recognize(InkData inkData);

  /// Recognize LaTeX from an image (PNG or JPEG bytes).
  ///
  /// Use this for screenshots, PDF crops, camera captures, or any
  /// pre-existing image of a mathematical expression.
  ///
  /// Throws [LatexRecognitionException] if the backend is not initialized
  /// or if recognition fails.
  Future<LatexRecognitionResult> recognizeImage(Uint8List imageBytes);

  /// Check whether the recognition backend is available and ready.
  Future<bool> isAvailable();

  /// Release backend resources.
  void dispose();
}

/// Result of a LaTeX recognition attempt.
class LatexRecognitionResult {
  /// The best-guess LaTeX string.
  final String latexString;

  /// Overall confidence score (0.0 to 1.0).
  final double confidence;

  /// Alternative recognition results, ordered by decreasing confidence.
  final List<LatexAlternative> alternatives;

  /// Per-symbol confidence mapping (token index → confidence).
  ///
  /// Used by the UI to highlight uncertain symbols.
  final List<SymbolConfidence> perSymbolConfidence;

  /// Time taken for inference in milliseconds.
  final int inferenceTimeMs;

  const LatexRecognitionResult({
    required this.latexString,
    required this.confidence,
    this.alternatives = const [],
    this.perSymbolConfidence = const [],
    this.inferenceTimeMs = 0,
  });

  /// Whether the result has high confidence (>= 0.7).
  bool get isHighConfidence => confidence >= 0.7;

  /// Whether the result has low confidence (< 0.4).
  bool get isLowConfidence => confidence < 0.4;

  Map<String, dynamic> toJson() => {
    'latexString': latexString,
    'confidence': confidence,
    'alternatives': alternatives.map((a) => a.toJson()).toList(),
    'perSymbolConfidence': perSymbolConfidence.map((s) => s.toJson()).toList(),
    'inferenceTimeMs': inferenceTimeMs,
  };

  factory LatexRecognitionResult.fromJson(Map<String, dynamic> json) {
    return LatexRecognitionResult(
      latexString: json['latexString'] as String? ?? '',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      alternatives:
          (json['alternatives'] as List<dynamic>?)
              ?.map((a) => LatexAlternative.fromJson(a as Map<String, dynamic>))
              .toList() ??
          [],
      perSymbolConfidence:
          (json['perSymbolConfidence'] as List<dynamic>?)
              ?.map((s) => SymbolConfidence.fromJson(s as Map<String, dynamic>))
              .toList() ??
          [],
      inferenceTimeMs: json['inferenceTimeMs'] as int? ?? 0,
    );
  }
}

/// An alternative recognition result.
class LatexAlternative {
  final String latexString;
  final double confidence;

  const LatexAlternative({required this.latexString, required this.confidence});

  Map<String, dynamic> toJson() => {
    'latexString': latexString,
    'confidence': confidence,
  };

  factory LatexAlternative.fromJson(Map<String, dynamic> json) {
    return LatexAlternative(
      latexString: json['latexString'] as String? ?? '',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Per-symbol confidence for highlighting uncertain regions.
class SymbolConfidence {
  /// The token text (e.g. `\frac`, `x`, `^`).
  final String token;

  /// Start index in the LaTeX string.
  final int startIndex;

  /// End index in the LaTeX string.
  final int endIndex;

  /// Confidence for this specific symbol (0.0 to 1.0).
  final double confidence;

  const SymbolConfidence({
    required this.token,
    required this.startIndex,
    required this.endIndex,
    required this.confidence,
  });

  /// Whether this symbol is uncertain (confidence < 0.7).
  bool get isUncertain => confidence < 0.7;

  /// Whether this symbol is very uncertain (confidence < 0.4).
  bool get isVeryUncertain => confidence < 0.4;

  Map<String, dynamic> toJson() => {
    'token': token,
    'startIndex': startIndex,
    'endIndex': endIndex,
    'confidence': confidence,
  };

  factory SymbolConfidence.fromJson(Map<String, dynamic> json) {
    return SymbolConfidence(
      token: json['token'] as String? ?? '',
      startIndex: json['startIndex'] as int? ?? 0,
      endIndex: json['endIndex'] as int? ?? 0,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Exception thrown when LaTeX recognition fails.
class LatexRecognitionException implements Exception {
  final String message;
  final Object? cause;

  const LatexRecognitionException(this.message, {this.cause});

  @override
  String toString() =>
      'LatexRecognitionException: $message${cause != null ? ' (cause: $cause)' : ''}';
}
