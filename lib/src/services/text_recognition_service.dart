import 'dart:io';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

// ============================================================================
// 📷 Text Recognition Service — OCR from Images
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

/// Service for recognizing text in images using ML Kit.
///
/// Supports Latin script by default.
/// Runs entirely on-device — no internet required.
class TextRecognitionService {
  TextRecognitionService._();
  static final instance = TextRecognitionService._();

  TextRecognizer? _recognizer;
  bool _isProcessing = false;

  /// Whether recognition is currently running.
  bool get isProcessing => _isProcessing;

  /// Initialize recognizer lazily.
  void _ensureInit() {
    _recognizer ??= TextRecognizer();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Core Recognition
  // ──────────────────────────────────────────────────────────────────────────

  /// Run text recognition on an image file.
  ///
  /// Returns [OcrResult] with all detected text blocks and their positions.
  /// Returns null if recognition fails or finds no text.
  Future<OcrResult?> recognizeFromFile(String imagePath) async {
    _ensureInit();
    if (_isProcessing) return null;
    _isProcessing = true;

    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final recognized = await _recognizer!.processImage(inputImage);

      if (recognized.blocks.isEmpty) return null;

      // Get image dimensions for coordinate mapping
      final imageSize = await _getImageSize(imagePath);

      final blocks = <OcrTextBlock>[];
      final fullTextBuffer = StringBuffer();

      for (final block in recognized.blocks) {
        final rect = block.boundingBox;
        final lines = block.lines.map((l) => l.text).toList();
        final text = block.text;

        blocks.add(
          OcrTextBlock(
            text: text,
            boundingBox: ui.Rect.fromLTRB(
              rect.left,
              rect.top,
              rect.right,
              rect.bottom,
            ),
            lines: lines,
          ),
        );

        if (fullTextBuffer.isNotEmpty) fullTextBuffer.write('\n\n');
        fullTextBuffer.write(text);
      }

      return OcrResult(
        blocks: blocks,
        imageWidth: imageSize.width.toInt(),
        imageHeight: imageSize.height.toInt(),
        fullText: fullTextBuffer.toString(),
      );
    } catch (_) {
      return null;
    } finally {
      _isProcessing = false;
    }
  }

  /// Run text recognition on a [ui.Image] already in memory.
  ///
  /// Converts the image to PNG, saves to a temp file, then runs OCR.
  /// Returns [OcrResult] with all detected text blocks and their positions.
  Future<OcrResult?> recognizeFromImage(ui.Image image) async {
    _ensureInit();
    if (_isProcessing) return null;
    _isProcessing = true;

    try {
      // Convert ui.Image to PNG bytes
      final byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (byteData == null) return null;

      final pngBytes = byteData.buffer.asUint8List();

      // Write to temp file (ML Kit needs a file path)
      final tempDir = await getTemporaryDirectory();
      final tempFile = File(
        '${tempDir.path}/ocr_scan_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await tempFile.writeAsBytes(pngBytes);

      try {
        final inputImage = InputImage.fromFilePath(tempFile.path);
        final recognized = await _recognizer!.processImage(inputImage);

        if (recognized.blocks.isEmpty) return null;

        final blocks = <OcrTextBlock>[];
        final fullTextBuffer = StringBuffer();

        for (final block in recognized.blocks) {
          final rect = block.boundingBox;
          final lines = block.lines.map((l) => l.text).toList();
          final text = block.text;

          blocks.add(
            OcrTextBlock(
              text: text,
              boundingBox: ui.Rect.fromLTRB(
                rect.left,
                rect.top,
                rect.right,
                rect.bottom,
              ),
              lines: lines,
            ),
          );

          if (fullTextBuffer.isNotEmpty) fullTextBuffer.write('\n\n');
          fullTextBuffer.write(text);
        }

        return OcrResult(
          blocks: blocks,
          imageWidth: image.width,
          imageHeight: image.height,
          fullText: fullTextBuffer.toString(),
        );
      } finally {
        // Cleanup temp file
        try {
          await tempFile.delete();
        } catch (_) {}
      }
    } catch (_) {
      return null;
    } finally {
      _isProcessing = false;
    }
  }

  /// Get image dimensions by decoding the image codec header.
  Future<ui.Size> _getImageSize(String path) async {
    try {
      final file = File(path);
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final size = ui.Size(
        frame.image.width.toDouble(),
        frame.image.height.toDouble(),
      );
      frame.image.dispose();
      codec.dispose();
      return size;
    } catch (_) {
      return const ui.Size(1080, 1920);
    }
  }

  /// Dispose resources.
  void dispose() {
    _recognizer?.close();
    _recognizer = null;
  }
}
