import 'dart:ui' as ui;

// ============================================================================
// 📷 OCR Engine — Abstract interface for text recognition
// ============================================================================

/// Result of OCR: a block of recognized text with its bounding box.
class OcrTextBlock {
  final String text;
  final ui.Rect boundingBox;
  final List<String> lines;
  final double confidence;

  const OcrTextBlock({
    required this.text,
    required this.boundingBox,
    required this.lines,
    this.confidence = 1.0,
  });
}

/// Result of a full OCR scan.
class OcrResult {
  final List<OcrTextBlock> blocks;
  final int imageWidth;
  final int imageHeight;
  final String fullText;

  const OcrResult({
    required this.blocks,
    required this.imageWidth,
    required this.imageHeight,
    required this.fullText,
  });
}

/// Abstract OCR engine interface.
///
/// Implement this to plug in different OCR backends:
/// - [MlKitOcrEngine] — Google ML Kit (default, Android/iOS)
/// - Tesseract, PaddleOCR, Apple Vision, etc.
///
/// The engine handles the raw recognition. [TextRecognitionService]
/// wraps it with processing guards and singleton management.
abstract class OcrEngine {
  /// Recognize text from an image file on disk.
  ///
  /// Returns [OcrResult] with detected text blocks and positions,
  /// or `null` if recognition fails or finds no text.
  Future<OcrResult?> recognizeFromFile(String imagePath);

  /// Recognize text from a [ui.Image] in memory.
  ///
  /// Returns [OcrResult] with detected text blocks and positions,
  /// or `null` if recognition fails or finds no text.
  Future<OcrResult?> recognizeFromImage(ui.Image image);

  /// Release engine resources.
  void dispose();
}
