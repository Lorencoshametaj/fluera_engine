import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'ocr_engine.dart';

// ============================================================================
// 📷 MyScript OCR Engine — Text Recognition via iink SDK
//
// Implements [OcrEngine] by delegating to the MyScript iink native bridge.
// The native side uses the iink SDK's Text recognition on ink content
// extracted from image analysis, or returns the JIIX parse results.
//
// Falls back gracefully when the iink SDK is not linked (returns null).
// ============================================================================

/// OCR engine backed by MyScript iink SDK.
///
/// Uses the same MethodChannel as [MyScriptInkEngine] to send image data
/// to the native iOS/Android side for text recognition.
///
/// If the iink SDK is not linked, all calls return null.
class MyScriptOcrEngine extends OcrEngine {
  static const MethodChannel _channel = MethodChannel(
    'fluera_engine/myscript_ink',
  );

  bool _available = false;

  /// Initialize — checks if iink SDK is available on the native side.
  Future<void> _ensureAvailable() async {
    if (_available) return;
    try {
      final result = await _channel.invokeMethod<Map>('initialize');
      _available = result?['available'] as bool? ?? false;
    } catch (_) {
      _available = false;
    }
  }

  @override
  Future<OcrResult?> recognizeFromFile(String imagePath) async {
    await _ensureAvailable();
    if (!_available) return null;

    try {
      // Send the image path to the native side for recognition.
      // The native iink SDK processes the image and returns JIIX
      // with text blocks and their bounding boxes.
      final result = await _channel.invokeMethod<Map>('recognizeImage', {
        'imagePath': imagePath,
      });

      if (result == null) return null;

      final text = result['text'] as String?;
      if (text == null || text.trim().isEmpty) return null;

      final width = result['imageWidth'] as int? ?? 0;
      final height = result['imageHeight'] as int? ?? 0;

      // Parse blocks from JIIX response if available
      final blocksList = result['blocks'] as List?;
      final blocks = <OcrTextBlock>[];

      if (blocksList != null) {
        for (final b in blocksList) {
          if (b is Map) {
            blocks.add(OcrTextBlock(
              text: b['text'] as String? ?? '',
              boundingBox: ui.Rect.fromLTRB(
                (b['left'] as num?)?.toDouble() ?? 0,
                (b['top'] as num?)?.toDouble() ?? 0,
                (b['right'] as num?)?.toDouble() ?? 0,
                (b['bottom'] as num?)?.toDouble() ?? 0,
              ),
              lines: (b['lines'] as List?)
                      ?.map((l) => l.toString())
                      .toList() ??
                  [b['text'] as String? ?? ''],
            ));
          }
        }
      }

      // Fallback: if no structured blocks, create one block from full text
      if (blocks.isEmpty) {
        blocks.add(OcrTextBlock(
          text: text,
          boundingBox: ui.Rect.fromLTWH(0, 0,
              width.toDouble(), height.toDouble()),
          lines: text.split('\n'),
        ));
      }

      return OcrResult(
        blocks: blocks,
        imageWidth: width,
        imageHeight: height,
        fullText: text,
      );
    } on PlatformException catch (e) {
      debugPrint('[MyScriptOCR] ❌ recognizeFromFile: ${e.message}');
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<OcrResult?> recognizeFromImage(ui.Image image) async {
    await _ensureAvailable();
    if (!_available) return null;

    try {
      // Convert ui.Image to PNG bytes → temp file → delegate to file method
      final byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (byteData == null) return null;

      final pngBytes = byteData.buffer.asUint8List();
      final tempDir = await getTemporaryDirectory();
      final tempFile = File(
        '${tempDir.path}/myscript_ocr_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await tempFile.writeAsBytes(pngBytes);

      try {
        return await recognizeFromFile(tempFile.path);
      } finally {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('[MyScriptOCR] ❌ recognizeFromImage: $e');
      return null;
    }
  }

  @override
  void dispose() {
    // iink Engine lifecycle is managed by MyScriptInkEngine
  }
}
