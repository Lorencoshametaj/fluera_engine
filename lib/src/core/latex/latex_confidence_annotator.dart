import '../../platform/latex_recognition_bridge.dart';

/// 🧮 LaTeX Confidence Annotator — maps ML confidence to AST regions.
///
/// Takes per-token confidence data from [LatexRecognitionResult] and
/// annotates regions of the LaTeX string with confidence levels.
/// The UI uses these annotations to highlight uncertain symbols.
///
/// Example:
/// ```dart
/// final annotations = LatexConfidenceAnnotator.annotate(
///   r'\frac{a}{b}',
///   result.perSymbolConfidence,
/// );
/// for (final a in annotations) {
///   print('${a.text}: ${a.level.name}');  // e.g. "a: high", "b: medium"
/// }
/// ```
class LatexConfidenceAnnotator {
  /// Confidence threshold for "high" confidence.
  static const double highThreshold = 0.85;

  /// Confidence threshold for "medium" confidence.
  static const double mediumThreshold = 0.6;

  /// Confidence threshold for "low" confidence.
  /// Below this, the symbol is marked as very uncertain.
  static const double lowThreshold = 0.4;

  /// Annotate a LaTeX string with confidence levels.
  ///
  /// Returns a list of [ConfidenceAnnotation] covering the entire string.
  /// Regions without explicit per-symbol confidence data are marked as
  /// [ConfidenceLevel.unknown].
  static List<ConfidenceAnnotation> annotate(
    String latexSource,
    List<SymbolConfidence> perSymbolConfidence,
  ) {
    if (latexSource.isEmpty) return [];

    // Build a confidence map for each character position
    final charConfidence = List.filled(latexSource.length, -1.0);
    for (final sc in perSymbolConfidence) {
      final start = sc.startIndex.clamp(0, latexSource.length);
      final end = sc.endIndex.clamp(start, latexSource.length);
      for (int i = start; i < end; i++) {
        charConfidence[i] = sc.confidence;
      }
    }

    // Group consecutive characters with the same confidence level
    final annotations = <ConfidenceAnnotation>[];
    int segStart = 0;
    ConfidenceLevel? currentLevel;

    for (int i = 0; i <= latexSource.length; i++) {
      final level =
          i < latexSource.length
              ? _classifyConfidence(charConfidence[i])
              : null;

      if (level != currentLevel || i == latexSource.length) {
        if (currentLevel != null && segStart < i) {
          annotations.add(
            ConfidenceAnnotation(
              text: latexSource.substring(segStart, i),
              startIndex: segStart,
              endIndex: i,
              level: currentLevel,
              confidence: charConfidence[segStart],
            ),
          );
        }
        segStart = i;
        currentLevel = level;
      }
    }

    return annotations;
  }

  /// Classify a confidence value into a level.
  static ConfidenceLevel _classifyConfidence(double confidence) {
    if (confidence < 0) return ConfidenceLevel.unknown;
    if (confidence >= highThreshold) return ConfidenceLevel.high;
    if (confidence >= mediumThreshold) return ConfidenceLevel.medium;
    if (confidence >= lowThreshold) return ConfidenceLevel.low;
    return ConfidenceLevel.veryLow;
  }

  /// Get only the uncertain annotations (medium, low, veryLow).
  static List<ConfidenceAnnotation> getUncertainRegions(
    String latexSource,
    List<SymbolConfidence> perSymbolConfidence,
  ) {
    return annotate(
      latexSource,
      perSymbolConfidence,
    ).where((a) => a.isUncertain).toList();
  }
}

/// A region of the LaTeX string annotated with confidence level.
class ConfidenceAnnotation {
  /// The text in this region.
  final String text;

  /// Start index in the LaTeX source string.
  final int startIndex;

  /// End index in the LaTeX source string.
  final int endIndex;

  /// Overall confidence level for this region.
  final ConfidenceLevel level;

  /// Raw confidence value (0.0 to 1.0, or -1 for unknown).
  final double confidence;

  const ConfidenceAnnotation({
    required this.text,
    required this.startIndex,
    required this.endIndex,
    required this.level,
    required this.confidence,
  });

  /// Whether this region has uncertain confidence (not high and not unknown).
  bool get isUncertain =>
      level == ConfidenceLevel.medium ||
      level == ConfidenceLevel.low ||
      level == ConfidenceLevel.veryLow;
}

/// Confidence level classification.
enum ConfidenceLevel {
  /// High confidence (>= 0.85) — no highlighting needed.
  high,

  /// Medium confidence (0.6 – 0.85) — subtle orange highlight.
  medium,

  /// Low confidence (0.4 – 0.6) — amber highlight.
  low,

  /// Very low confidence (< 0.4) — red highlight, suggest alternatives.
  veryLow,

  /// No confidence data available.
  unknown,
}
