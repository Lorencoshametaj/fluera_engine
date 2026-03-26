import 'dart:ui' as ui;
import '../drawing/models/pro_drawing_point.dart';

// ============================================================================
// ✍️ Ink Recognition Engine — Abstract interface for handwriting recognition
// ============================================================================

/// Context for improving recognition accuracy.
///
/// Provides the recognizer with additional information about the writing
/// environment, boosting accuracy by ~15-25%.
class InkRecognitionContext {
  /// The physical dimensions of the writing area (in the same coordinate
  /// system as stroke points). Helps disambiguate characters like 'o' vs 'O'.
  final ui.Size? writingArea;

  /// Characters immediately preceding the text to be recognized.
  /// Feeds the language model for better predictions.
  /// Recommended: up to ~20 characters of preceding text.
  final String? preContext;

  const InkRecognitionContext({this.writingArea, this.preContext});

  /// Empty context (no hints).
  static const empty = InkRecognitionContext();
}

/// A single recognition candidate with confidence score.
class InkCandidate {
  /// The recognized text.
  final String text;

  /// Engine-specific confidence score (semantics vary by engine).
  /// For ML Kit: index-based rank (0 = best). For others: probability.
  final double score;

  const InkCandidate({required this.text, required this.score});

  @override
  String toString() => 'InkCandidate("$text", score=$score)';
}

/// Abstract engine for digital ink (handwriting-to-text) recognition.
///
/// Implement this to plug in different recognition backends:
/// - [MlKitInkEngine] — Google ML Kit Digital Ink Recognition (default)
/// - Custom TensorFlow Lite / ONNX models
/// - MyScript, Selvy, or other commercial engines
///
/// The engine handles raw recognition and model management.
/// [DigitalInkService] wraps it with auto-detect logic, singleton management,
/// and service orchestration.
abstract class InkRecognitionEngine {
  /// Whether the engine is available on this platform.
  bool get isAvailable;

  /// Whether the language model is downloaded and ready.
  bool get isReady;

  /// Current language code (BCP-47).
  String get languageCode;

  /// Initialize the engine for [languageCode].
  ///
  /// Downloads the model if not already available.
  /// Safe to call multiple times — subsequent calls are no-ops if the
  /// same language is already loaded.
  Future<void> init({String languageCode = 'en'});

  /// Recognize handwriting from a single stroke.
  ///
  /// Returns the best candidate text, or `null` if recognition fails.
  /// When [context] is provided, accuracy improves significantly.
  Future<String?> recognizeStroke(
    List<ProDrawingPoint> points, {
    InkRecognitionContext context = InkRecognitionContext.empty,
  });

  /// Recognize handwriting from multiple strokes (multi-stroke characters).
  ///
  /// Each inner list is a separate stroke. Useful for characters like
  /// 't', 'i', 'j' that require multiple strokes.
  Future<String?> recognizeMultiStroke(
    List<List<ProDrawingPoint>> strokeSets, {
    InkRecognitionContext context = InkRecognitionContext.empty,
  });

  /// Recognize and return multiple candidates ranked by confidence.
  ///
  /// Returns up to [maxCandidates] results. Default: 5.
  /// Falls back to [recognizeStroke] wrapped in a single-element list
  /// if the engine doesn't natively support multiple candidates.
  Future<List<InkCandidate>> recognizeStrokeCandidates(
    List<ProDrawingPoint> points, {
    InkRecognitionContext context = InkRecognitionContext.empty,
    int maxCandidates = 5,
  });

  /// Multi-stroke version of [recognizeStrokeCandidates].
  Future<List<InkCandidate>> recognizeMultiStrokeCandidates(
    List<List<ProDrawingPoint>> strokeSets, {
    InkRecognitionContext context = InkRecognitionContext.empty,
    int maxCandidates = 5,
  });

  /// Switch active language. Downloads model if needed.
  ///
  /// Returns `true` on success.
  Future<bool> switchLanguage(String languageCode);

  /// Check if a model is downloaded.
  Future<bool> isModelDownloaded(String languageCode);

  /// Download a language model.
  ///
  /// Returns `true` on success.
  Future<bool> downloadLanguage(String languageCode);

  /// Delete a downloaded model to free storage.
  Future<void> deleteModel(String languageCode);

  /// Get download status for multiple languages.
  Future<Map<String, bool>> getDownloadStatus(List<String> languageCodes);

  /// Release resources.
  void dispose();
}
