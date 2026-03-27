import 'dart:io';
import 'dart:ui' as ui;
import 'package:path_provider/path_provider.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'ocr_engine.dart';

// ============================================================================
// 📷 ML Kit OCR Engine — Google ML Kit Text Recognition adapter
// ============================================================================

/// OCR engine backed by Google ML Kit Text Recognition.
///
/// Runs entirely on-device. Supports Latin script by default.
/// Available on Android and iOS only.
///
/// This is an adapter that isolates all ML Kit dependencies.
/// To swap OCR backend, implement [OcrEngine] with a different engine
/// (e.g., Tesseract, PaddleOCR) and pass it to [TextRecognitionService].
class MlKitOcrEngine extends OcrEngine {
  TextRecognizer? _recognizer;

  /// Initialize recognizer lazily.
  void _ensureInit() {
    _recognizer ??= TextRecognizer();
  }

  @override
  Future<OcrResult?> recognizeFromFile(String imagePath) async {
    _ensureInit();

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
    }
  }

  @override
  Future<OcrResult?> recognizeFromImage(ui.Image image) async {
    _ensureInit();

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

  @override
  void dispose() {
    _recognizer?.close();
    _recognizer = null;
  }
}
