import 'dart:ui' as ui;
import 'ocr_engine.dart';
import 'mlkit_ocr_engine.dart';

// Re-export models so consumers don't need to import ocr_engine.dart
export 'ocr_engine.dart' show OcrTextBlock, OcrResult, OcrEngine;

// ============================================================================
// 📷 Text Recognition Service — OCR from Images
// ============================================================================

/// Service for recognizing text in images.
///
/// Delegates to a pluggable [OcrEngine] backend.
/// Default engine: [MyScriptOcrEngine] (MyScript iink SDK, Android/iOS).
///
/// To swap engine:
/// ```dart
/// TextRecognitionService.instance.setEngine(MyCustomOcrEngine());
/// ```
class TextRecognitionService {
  TextRecognitionService._();
  static final instance = TextRecognitionService._();

  /// The active OCR engine. Defaults to MyScript iink.
  OcrEngine _engine = MyScriptOcrEngine();

  bool _isProcessing = false;

  /// Whether recognition is currently running.
  bool get isProcessing => _isProcessing;

  /// The current OCR engine.
  OcrEngine get engine => _engine;

  /// Swap the OCR engine at runtime.
  ///
  /// Disposes the previous engine before switching.
  void setEngine(OcrEngine engine) {
    _engine.dispose();
    _engine = engine;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Core Recognition
  // ──────────────────────────────────────────────────────────────────────────

  /// Run text recognition on an image file.
  ///
  /// Returns [OcrResult] with all detected text blocks and their positions.
  /// Returns null if recognition fails or finds no text.
  Future<OcrResult?> recognizeFromFile(String imagePath) async {
    if (_isProcessing) return null;
    _isProcessing = true;

    try {
      return await _engine.recognizeFromFile(imagePath);
    } finally {
      _isProcessing = false;
    }
  }

  /// Run text recognition on a [ui.Image] already in memory.
  ///
  /// Returns [OcrResult] with all detected text blocks and their positions.
  Future<OcrResult?> recognizeFromImage(ui.Image image) async {
    if (_isProcessing) return null;
    _isProcessing = true;

    try {
      return await _engine.recognizeFromImage(image);
    } finally {
      _isProcessing = false;
    }
  }

  /// Dispose resources.
  void dispose() {
    _engine.dispose();
  }
}
