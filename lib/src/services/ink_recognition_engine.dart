import '../drawing/models/pro_drawing_point.dart';

// ============================================================================
// ✍️ Ink Recognition Engine — Abstract interface for handwriting recognition
// ============================================================================

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
  Future<String?> recognizeStroke(List<ProDrawingPoint> points);

  /// Recognize handwriting from multiple strokes (multi-stroke characters).
  ///
  /// Each inner list is a separate stroke. Useful for characters like
  /// 't', 'i', 'j' that require multiple strokes.
  Future<String?> recognizeMultiStroke(
    List<List<ProDrawingPoint>> strokeSets,
  );

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
