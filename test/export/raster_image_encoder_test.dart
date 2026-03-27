import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/export/raster_image_encoder.dart';

void main() {
  late RasterImageEncoder encoder;

  setUp(() {
    encoder = RasterImageEncoder();
  });

  // ===========================================================================
  // BMP encoding
  // ===========================================================================

  group('encodeBmp', () {
    test('produces valid BMP header', () {
      // 2x2 red pixels (RGBA)
      final rgba = Uint8List.fromList([
        255, 0, 0, 255, // Red
        0, 255, 0, 255, // Green
        0, 0, 255, 255, // Blue
        255, 255, 0, 255, // Yellow
      ]);

      final bmp = RasterImageEncoder.encodeBmp(rgba, 2, 2);

      // BMP starts with 'BM'
      expect(bmp[0], 0x42); // 'B'
      expect(bmp[1], 0x4D); // 'M'
    });

    test('output size matches expected BMP format', () {
      // 1x1 pixel
      final rgba = Uint8List.fromList([255, 0, 0, 255]);
      final bmp = RasterImageEncoder.encodeBmp(rgba, 1, 1);

      // Header (54 bytes) + pixel data (4 bytes, padded to 4-byte boundary)
      expect(bmp.length, 58); // 54 + 4
    });

    test('larger image encodes correctly', () {
      // 10x10 white pixels
      final rgba = Uint8List(10 * 10 * 4);
      for (int i = 0; i < rgba.length; i += 4) {
        rgba[i] = 255; // R
        rgba[i + 1] = 255; // G
        rgba[i + 2] = 255; // B
        rgba[i + 3] = 255; // A
      }

      final bmp = RasterImageEncoder.encodeBmp(rgba, 10, 10);

      // Should have BM header
      expect(bmp[0], 0x42);
      expect(bmp[1], 0x4D);

      // File size should match
      final headerSize = 54;
      final rowSize = 10 * 4; // 40 bytes, already 4-byte aligned
      final pixelDataSize = rowSize * 10;
      expect(bmp.length, headerSize + pixelDataSize);
    });

    test('handles single pixel', () {
      final rgba = Uint8List.fromList([128, 64, 32, 255]);
      final bmp = RasterImageEncoder.encodeBmp(rgba, 1, 1);
      expect(bmp.length, greaterThan(54)); // At least header
    });
  });
}
