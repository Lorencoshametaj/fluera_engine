import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/export/export_pipeline.dart';
import 'package:fluera_engine/src/export/raster_image_encoder.dart';

void main() {
  group('ExportFormat', () {
    // =========================================================================
    // 1. Extension correctness
    // =========================================================================
    test('ExportResult.extension returns correct values', () {
      const results = <ExportFormat, String>{
        ExportFormat.png: 'png',
        ExportFormat.jpeg: 'jpg',
        ExportFormat.webp: 'webp',
        ExportFormat.svg: 'svg',
        ExportFormat.pdf: 'pdf',
      };

      for (final entry in results.entries) {
        final result = ExportResult(
          bytes: Uint8List(0),
          format: entry.key,
          logicalSize: Size.zero,
          pixelSize: Size.zero,
        );
        expect(
          result.extension,
          entry.value,
          reason: '${entry.key} should have extension ${entry.value}',
        );
      }
    });

    // =========================================================================
    // 2. MIME type correctness
    // =========================================================================
    test('ExportResult.mimeType returns correct MIME types', () {
      const mimeTypes = <ExportFormat, String>{
        ExportFormat.png: 'image/png',
        ExportFormat.jpeg: 'image/jpeg',
        ExportFormat.webp: 'image/webp',
        ExportFormat.svg: 'image/svg+xml',
        ExportFormat.pdf: 'application/pdf',
      };

      for (final entry in mimeTypes.entries) {
        final result = ExportResult(
          bytes: Uint8List(0),
          format: entry.key,
          logicalSize: Size.zero,
          pixelSize: Size.zero,
        );
        expect(
          result.mimeType,
          entry.value,
          reason: '${entry.key} should have MIME type ${entry.value}',
        );
      }
    });
  });

  group('ExportConfig', () {
    // =========================================================================
    // 3. Default quality
    // =========================================================================
    test('default quality is 85', () {
      const config = ExportConfig();
      expect(config.quality, 85);
    });

    // =========================================================================
    // 4. Custom quality
    // =========================================================================
    test('custom quality is preserved', () {
      const config = ExportConfig(quality: 50, format: ExportFormat.jpeg);
      expect(config.quality, 50);
      expect(config.format, ExportFormat.jpeg);
    });

    // =========================================================================
    // 5. PNG presets have correct defaults
    // =========================================================================
    test('PNG 1x preset uses pixelRatio 1.0', () {
      const config = ExportConfig.png1x();
      expect(config.pixelRatio, 1.0);
      expect(config.format, ExportFormat.png);
    });

    test('PNG 2x preset uses pixelRatio 2.0', () {
      const config = ExportConfig.png2x();
      expect(config.pixelRatio, 2.0);
    });

    test('PNG 3x preset uses pixelRatio 3.0', () {
      const config = ExportConfig.png3x();
      expect(config.pixelRatio, 3.0);
    });
  });

  group('RasterImageEncoder', () {
    // =========================================================================
    // 6. BMP encoding produces valid BMP
    // =========================================================================
    test('BMP fallback encodes valid BMP header', () {
      // Create a 2x2 red image in RGBA format.
      final rgba = Uint8List.fromList([
        // Row 0
        255, 0, 0, 255, // Red pixel
        0, 255, 0, 255, // Green pixel
        // Row 1
        0, 0, 255, 255, // Blue pixel
        255, 255, 255, 255, // White pixel
      ]);

      final bmp = RasterImageEncoder.encodeBmp(rgba, 2, 2);

      // BMP magic bytes.
      expect(bmp[0], 0x42); // 'B'
      expect(bmp[1], 0x4D); // 'M'

      // File size should be header (54) + pixel data (2*4 * 2 = 16).
      // Each row is 2*4=8 bytes, already 4-byte aligned.
      final fileSize = ByteData.sublistView(bmp).getUint32(2, Endian.little);
      expect(fileSize, 54 + 16);

      // Width = 2.
      final width = ByteData.sublistView(bmp).getInt32(18, Endian.little);
      expect(width, 2);

      // Height = 2.
      final height = ByteData.sublistView(bmp).getInt32(22, Endian.little);
      expect(height, 2);

      // Bits per pixel = 32.
      final bpp = ByteData.sublistView(bmp).getUint16(28, Endian.little);
      expect(bpp, 32);
    });

    // =========================================================================
    // 7. BMP encoding roundtrip pixel order
    // =========================================================================
    test('BMP stores pixels in BGRA bottom-to-top order', () {
      // Single pixel red image.
      final rgba = Uint8List.fromList([255, 0, 0, 255]);
      final bmp = RasterImageEncoder.encodeBmp(rgba, 1, 1);

      // Pixel data starts at offset 54.
      // Should be BGRA = [0, 0, 255, 255].
      expect(bmp[54], 0); // B
      expect(bmp[55], 0); // G
      expect(bmp[56], 255); // R
      expect(bmp[57], 255); // A
    });
  });

  group('ExportFormat enum', () {
    // =========================================================================
    // 8. All five formats exist
    // =========================================================================
    test('all five export formats are available', () {
      expect(ExportFormat.values.length, 5);
      expect(ExportFormat.values, contains(ExportFormat.png));
      expect(ExportFormat.values, contains(ExportFormat.jpeg));
      expect(ExportFormat.values, contains(ExportFormat.webp));
      expect(ExportFormat.values, contains(ExportFormat.svg));
      expect(ExportFormat.values, contains(ExportFormat.pdf));
    });
  });
}
