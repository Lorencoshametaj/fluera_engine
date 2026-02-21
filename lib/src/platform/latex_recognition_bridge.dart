import '../core/latex/ink_stroke_data.dart';

/// 🧮 LaTeX Recognition Bridge — abstract interface for on-device ML inference.
///
/// This bridge abstracts the platform-specific ML model integration
/// (Core ML on iOS, TFLite on Android), allowing the Dart layer to
/// invoke handwriting recognition without knowing the underlying engine.
///
/// The pipeline:
/// 1. Capture ink strokes via [InkData]
/// 2. Rasterize to a 256×256 bitmap (handled internally)
/// 3. Send to native ML model via platform channel
/// 4. Receive [LatexRecognitionResult] with LaTeX + confidence
///
/// Example:
/// ```dart
/// final bridge = NativeLatexRecognizer();
/// await bridge.initialize();
/// final result = await bridge.recognize(inkData);
/// print(result.latexString); // e.g. "\frac{a}{b}"
/// ```
abstract class LatexRecognitionBridge {
  /// Initialize the ML model and allocate resources.
  ///
  /// Must be called before [recognize]. Safe to call multiple times.
  Future<void> initialize();

  /// Recognize handwritten LaTeX from ink stroke data.
  ///
  /// Returns a [LatexRecognitionResult] with the best-guess LaTeX string,
  /// overall confidence score, and alternative suggestions.
  ///
  /// Throws [LatexRecognitionException] if the model is not initialized
  /// or if inference fails.
  Future<LatexRecognitionResult> recognize(InkData inkData);

  /// Check whether the ML model is available and ready on this platform.
  Future<bool> isAvailable();

  /// Release model resources.
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
