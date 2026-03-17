
import '../drawing/models/pro_drawing_point.dart';
import 'ink_recognition_engine.dart';
import 'mlkit_ink_engine.dart';
import 'language_detection_service.dart';

// Re-export so consumers don't need to import ink_recognition_engine.dart
export 'ink_recognition_engine.dart' show InkRecognitionEngine;

/// ✍️ Digital Ink Recognition Service
///
/// Orchestrates handwriting-to-text conversion with auto-detect support.
///
/// Delegates raw recognition to a pluggable [InkRecognitionEngine].
/// Default engine: [MlKitInkEngine] (Google ML Kit, Android/iOS).
///
/// To swap engine:
/// ```dart
/// DigitalInkService.instance.setEngine(MyCustomInkEngine());
/// ```
///
/// DESIGN:
/// - Singleton: one service instance, shared across the app
/// - Pluggable engine: swap recognition backend at runtime
/// - Auto-detect: verifies recognized text with Language Detection
///   and switches language if needed
class DigitalInkService {
  DigitalInkService._();
  static final DigitalInkService instance = DigitalInkService._();

  // ── Engine ────────────────────────────────────────────────────────────────

  /// The active ink recognition engine. Defaults to ML Kit.
  InkRecognitionEngine _engine = MlKitInkEngine();

  /// The current recognition engine.
  InkRecognitionEngine get engine => _engine;

  /// Swap the ink recognition engine at runtime.
  ///
  /// Disposes the previous engine before switching.
  void setEngine(InkRecognitionEngine engine) {
    _engine.dispose();
    _engine = engine;
  }

  // ── State (delegated to engine) ────────────────────────────────────────────

  /// Whether auto-detect language is enabled.
  /// When true, recognized text is verified with Language Identification
  /// and the recognizer switches language automatically if needed.
  bool autoDetect = true;

  /// Whether the service is available on this platform.
  bool get isAvailable => _engine.isAvailable;

  /// Whether the language model is downloaded and ready.
  bool get isReady => _engine.isReady;

  /// Current language code (BCP-47).
  String get languageCode => _engine.languageCode;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  /// Initializes the recognizer for [languageCode].
  ///
  /// Downloads the model if not already available (~15 MB, one-time).
  /// Safe to call multiple times — subsequent calls are no-ops if the
  /// same language is already loaded.
  Future<void> init({String languageCode = 'en'}) =>
      _engine.init(languageCode: languageCode);

  // ── Recognition (delegated) ────────────────────────────────────────────────

  /// Recognize handwriting from a list of [ProDrawingPoint]s.
  ///
  /// Returns the best candidate text, or `null` if recognition fails.
  Future<String?> recognizeStroke(List<ProDrawingPoint> points) =>
      _engine.recognizeStroke(points);

  /// Recognize handwriting from multiple strokes (for multi-stroke letters).
  Future<String?> recognizeMultiStroke(
    List<List<ProDrawingPoint>> strokeSets,
  ) =>
      _engine.recognizeMultiStroke(strokeSets);

  // ── Auto-Detect Recognition ────────────────────────────────────────────────

  /// Recognize handwriting with automatic language detection.
  ///
  /// Feedback loop:
  /// 1. Recognize with current language → get text
  /// 2. Feed text to Language Identification
  /// 3. If detected language differs AND model is downloaded → re-recognize
  /// 4. Return text + actual language code
  ///
  /// Falls back to standard recognition if auto-detect is disabled
  /// or language detection fails.
  Future<({String text, String languageCode})?> recognizeWithAutoDetect(
    List<ProDrawingPoint> points,
  ) async {
    // First pass: recognize with current language
    final text = await _engine.recognizeStroke(points);
    if (text == null || text.trim().isEmpty) return null;

    if (!autoDetect) {
      return (text: text, languageCode: _engine.languageCode);
    }

    // Detect language of recognized text
    final langService = LanguageDetectionService.instance;
    final detected = await langService.identifyLanguage(text);

    // If same language or detection failed, return as-is
    if (detected == null || detected == _engine.languageCode) {
      return (text: text, languageCode: _engine.languageCode);
    }

    // Check if we have the detected language model downloaded
    final hasModel = await _engine.isModelDownloaded(detected);
    if (!hasModel) {

      return (text: text, languageCode: _engine.languageCode);
    }

    // Re-recognize with detected language

    final prevLang = _engine.languageCode;
    await _engine.switchLanguage(detected);
    final reText = await _engine.recognizeStroke(points);

    if (reText != null && reText.trim().isNotEmpty) {
      return (text: reText, languageCode: detected);
    }

    // Re-recognition failed, revert
    await _engine.switchLanguage(prevLang);
    return (text: text, languageCode: prevLang);
  }

  /// Multi-stroke version of [recognizeWithAutoDetect].
  Future<({String text, String languageCode})?>
      recognizeMultiStrokeWithAutoDetect(
    List<List<ProDrawingPoint>> strokeSets,
  ) async {
    final text = await _engine.recognizeMultiStroke(strokeSets);
    if (text == null || text.trim().isEmpty) return null;

    if (!autoDetect) {
      return (text: text, languageCode: _engine.languageCode);
    }

    final langService = LanguageDetectionService.instance;
    final detected = await langService.identifyLanguage(text);

    if (detected == null || detected == _engine.languageCode) {
      return (text: text, languageCode: _engine.languageCode);
    }

    final hasModel = await _engine.isModelDownloaded(detected);
    if (!hasModel) {
      return (text: text, languageCode: _engine.languageCode);
    }

    final prevLang = _engine.languageCode;
    await _engine.switchLanguage(detected);
    final reText = await _engine.recognizeMultiStroke(strokeSets);

    if (reText != null && reText.trim().isNotEmpty) {
      return (text: reText, languageCode: detected);
    }

    await _engine.switchLanguage(prevLang);
    return (text: text, languageCode: prevLang);
  }

  // ── Language Management (delegated) ────────────────────────────────────────

  /// Check if a model is downloaded.
  Future<bool> isModelDownloaded(String languageCode) =>
      _engine.isModelDownloaded(languageCode);

  /// Download a language model (returns true on success).
  Future<bool> downloadLanguage(String languageCode) =>
      _engine.downloadLanguage(languageCode);

  /// Switch active language. Downloads if needed.
  Future<bool> switchLanguage(String languageCode) =>
      _engine.switchLanguage(languageCode);

  /// Delete a downloaded model to free storage.
  Future<void> deleteModel(String languageCode) =>
      _engine.deleteModel(languageCode);

  /// Get download status for multiple languages.
  Future<Map<String, bool>> getDownloadStatus(List<String> languageCodes) =>
      _engine.getDownloadStatus(languageCodes);

  // ── Cleanup ────────────────────────────────────────────────────────────────

  /// Release resources.
  void dispose() {
    _engine.dispose();
    LanguageDetectionService.instance.dispose();
  }

  // ── Static Data ────────────────────────────────────────────────────────────

  /// Curated list of popular languages for handwriting recognition.
  /// Each entry: languageCode → (display name, native name, flag emoji).
  static const Map<String, (String, String, String)> supportedLanguages = {
    'en': ('English', 'English', '🇬🇧'),
    'it': ('Italian', 'Italiano', '🇮🇹'),
    'es': ('Spanish', 'Español', '🇪🇸'),
    'fr': ('French', 'Français', '🇫🇷'),
    'de': ('German', 'Deutsch', '🇩🇪'),
    'pt': ('Portuguese', 'Português', '🇵🇹'),
    'nl': ('Dutch', 'Nederlands', '🇳🇱'),
    'ru': ('Russian', 'Русский', '🇷🇺'),
    'ja': ('Japanese', '日本語', '🇯🇵'),
    'ko': ('Korean', '한국어', '🇰🇷'),
    'zh-Hani': ('Chinese', '中文', '🇨🇳'),
    'ar': ('Arabic', 'العربية', '🇸🇦'),
    'hi': ('Hindi', 'हिन्दी', '🇮🇳'),
    'tr': ('Turkish', 'Türkçe', '🇹🇷'),
    'pl': ('Polish', 'Polski', '🇵🇱'),
    'sv': ('Swedish', 'Svenska', '🇸🇪'),
    'da': ('Danish', 'Dansk', '🇩🇰'),
    'fi': ('Finnish', 'Suomi', '🇫🇮'),
    'el': ('Greek', 'Ελληνικά', '🇬🇷'),
    'he': ('Hebrew', 'עברית', '🇮🇱'),
    'th': ('Thai', 'ไทย', '🇹🇭'),
    'vi': ('Vietnamese', 'Tiếng Việt', '🇻🇳'),
    'uk': ('Ukrainian', 'Українська', '🇺🇦'),
    'id': ('Indonesian', 'Bahasa Indonesia', '🇮🇩'),
  };
}
