import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_digital_ink_recognition/google_mlkit_digital_ink_recognition.dart';
import '../drawing/models/pro_drawing_point.dart';

/// ✍️ Digital Ink Recognition Service
///
/// Wraps Google ML Kit Digital Ink Recognition for on-device
/// handwriting-to-text conversion.
///
/// DESIGN:
/// - Singleton: one recognizer per language, shared across the app
/// - Lazy init: model is downloaded on first use (~15 MB, one-time)
/// - Graceful fallback: returns null on Desktop/Web or if model unavailable
/// - Thread-safe: recognition is async, UI stays responsive
class DigitalInkService {
  DigitalInkService._();
  static final DigitalInkService instance = DigitalInkService._();

  // ── State ──────────────────────────────────────────────────────────────────
  String _languageCode = 'en';
  DigitalInkRecognizer? _recognizer;
  final DigitalInkRecognizerModelManager _modelManager =
      DigitalInkRecognizerModelManager();
  bool _modelReady = false;
  bool _initializing = false;

  /// Whether the service is available on this platform.
  bool get isAvailable {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid || Platform.isIOS;
    } catch (_) {
      return false;
    }
  }

  /// Whether the language model is downloaded and ready.
  bool get isReady => _modelReady;

  /// Current language code (BCP-47).
  String get languageCode => _languageCode;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  /// Initializes the recognizer for [languageCode].
  ///
  /// Downloads the model if not already available (~15 MB, one-time).
  /// Safe to call multiple times — subsequent calls are no-ops if the
  /// same language is already loaded.
  Future<void> init({String languageCode = 'en'}) async {
    if (!isAvailable) return;
    if (_modelReady && _languageCode == languageCode) return;
    if (_initializing) return;
    _initializing = true;

    try {
      _languageCode = languageCode;

      // Check if model is already downloaded
      final isDownloaded = await _modelManager.isModelDownloaded(languageCode);
      if (!isDownloaded) {
        debugPrint('✍️ [DigitalInk] Downloading model for "$languageCode"...');
        await _modelManager.downloadModel(languageCode);
        debugPrint('✍️ [DigitalInk] Model downloaded successfully.');
      }

      // Create recognizer
      _recognizer?.close();
      _recognizer = DigitalInkRecognizer(languageCode: languageCode);
      _modelReady = true;
    } catch (e) {
      debugPrint('✍️ [DigitalInk] Init failed: $e');
      _modelReady = false;
    } finally {
      _initializing = false;
    }
  }

  // ── Recognition ────────────────────────────────────────────────────────────

  /// Recognize handwriting from a list of [ProDrawingPoint]s.
  ///
  /// Returns the best candidate text, or `null` if:
  /// - Platform is unsupported (Desktop/Web)
  /// - Model is not downloaded
  /// - Recognition fails or returns no candidates
  /// - Points are too few (< 5 points)
  Future<String?> recognizeStroke(List<ProDrawingPoint> points) async {
    if (!_modelReady || _recognizer == null) {
      // Auto-init on first call
      await init(languageCode: _languageCode);
      if (!_modelReady || _recognizer == null) return null;
    }

    if (points.length < 5) return null;

    try {
      // Convert ProDrawingPoint → ML Kit StrokePoint
      final inkPoints = <StrokePoint>[];
      for (final p in points) {
        inkPoints.add(
          StrokePoint(x: p.position.dx, y: p.position.dy, t: p.timestamp),
        );
      }

      final stroke = Stroke();
      stroke.points = inkPoints;

      final ink = Ink();
      ink.strokes = [stroke];

      final candidates = await _recognizer!.recognize(ink);

      if (candidates.isEmpty) return null;

      // Return the top candidate
      final best = candidates.first.text;
      debugPrint(
        '✍️ [DigitalInk] Recognized: "$best" '
        '(${candidates.length} candidates, '
        '${points.length} points)',
      );
      return best;
    } catch (e) {
      debugPrint('✍️ [DigitalInk] Recognition error: $e');
      return null;
    }
  }

  /// Recognize handwriting from multiple strokes (for multi-stroke letters).
  ///
  /// Each inner list is a separate stroke. Useful for characters like
  /// 't', 'i', 'j' that require multiple strokes.
  Future<String?> recognizeMultiStroke(
    List<List<ProDrawingPoint>> strokeSets,
  ) async {
    if (!_modelReady || _recognizer == null) {
      await init(languageCode: _languageCode);
      if (!_modelReady || _recognizer == null) return null;
    }

    final totalPoints = strokeSets.fold<int>(0, (sum, s) => sum + s.length);
    if (totalPoints < 5) return null;

    try {
      final mlStrokes = <Stroke>[];
      for (final points in strokeSets) {
        final inkPoints = <StrokePoint>[];
        for (final p in points) {
          inkPoints.add(
            StrokePoint(x: p.position.dx, y: p.position.dy, t: p.timestamp),
          );
        }
        mlStrokes.add(Stroke()..points = inkPoints);
      }

      final ink = Ink();
      ink.strokes = mlStrokes;
      final candidates = await _recognizer!.recognize(ink);

      if (candidates.isEmpty) return null;

      final best = candidates.first.text;
      debugPrint(
        '✍️ [DigitalInk] Multi-stroke recognized: "$best" '
        '(${mlStrokes.length} strokes, $totalPoints points)',
      );
      return best;
    } catch (e) {
      debugPrint('✍️ [DigitalInk] Multi-stroke recognition error: $e');
      return null;
    }
  }

  // ── Cleanup ────────────────────────────────────────────────────────────────

  /// Release resources.
  void dispose() {
    _recognizer?.close();
    _recognizer = null;
    _modelReady = false;
  }

  /// Delete a downloaded model to free storage.
  Future<void> deleteModel(String languageCode) async {
    if (!isAvailable) return;
    try {
      await _modelManager.deleteModel(languageCode);
      if (languageCode == _languageCode) {
        _modelReady = false;
      }
    } catch (e) {
      debugPrint('✍️ [DigitalInk] Delete model error: $e');
    }
  }

  // ── Language Management ────────────────────────────────────────────────────

  /// Check if a model is downloaded.
  Future<bool> isModelDownloaded(String languageCode) async {
    if (!isAvailable) return false;
    try {
      return await _modelManager.isModelDownloaded(languageCode);
    } catch (e) {
      debugPrint('✍️ [DigitalInk] Check model error: $e');
      return false;
    }
  }

  /// Download a language model (returns true on success).
  Future<bool> downloadLanguage(String languageCode) async {
    if (!isAvailable) return false;
    try {
      debugPrint('✍️ [DigitalInk] Downloading "$languageCode"...');
      await _modelManager.downloadModel(languageCode);
      debugPrint('✍️ [DigitalInk] "$languageCode" downloaded.');
      return true;
    } catch (e) {
      debugPrint('✍️ [DigitalInk] Download failed for "$languageCode": $e');
      return false;
    }
  }

  /// Switch active language. Downloads if needed.
  Future<bool> switchLanguage(String languageCode) async {
    if (!isAvailable) return false;
    if (_languageCode == languageCode && _modelReady) return true;

    // Reset current state
    _modelReady = false;
    _recognizer?.close();
    _recognizer = null;

    await init(languageCode: languageCode);
    return _modelReady;
  }

  /// Get download status for multiple languages.
  Future<Map<String, bool>> getDownloadStatus(
    List<String> languageCodes,
  ) async {
    if (!isAvailable) {
      return {for (final c in languageCodes) c: false};
    }
    final results = <String, bool>{};
    for (final code in languageCodes) {
      results[code] = await isModelDownloaded(code);
    }
    return results;
  }

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
