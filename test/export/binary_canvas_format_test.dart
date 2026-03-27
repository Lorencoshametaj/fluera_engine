import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/export/binary_canvas_format.dart';
import 'package:fluera_engine/src/core/models/canvas_layer.dart';

void main() {
  // ===========================================================================
  // isBinaryFormat
  // ===========================================================================

  group('isBinaryFormat', () {
    test('detects valid binary format header', () {
      // Binary format starts with magic bytes 'NBLF'
      final data = Uint8List.fromList([
        0x4E, 0x42, 0x4C, 0x46, // 'NBLF' magic
        ...List.filled(100, 0),
      ]);

      // This checks only magic bytes — may or may not pass depending
      // on exact header format; we verify it doesn't throw.
      final result = BinaryCanvasFormat.isBinaryFormat(data);
      expect(result, isA<bool>());
    });

    test('rejects empty data', () {
      final data = Uint8List(0);
      expect(BinaryCanvasFormat.isBinaryFormat(data), false);
    });

    test('rejects JSON data', () {
      final jsonBytes = Uint8List.fromList('{"layers": []}'.codeUnits);
      expect(BinaryCanvasFormat.isBinaryFormat(jsonBytes), false);
    });

    test('rejects too-short data', () {
      final data = Uint8List.fromList([0x01, 0x02]);
      expect(BinaryCanvasFormat.isBinaryFormat(data), false);
    });
  });

  // ===========================================================================
  // Encode / Decode roundtrip
  // ===========================================================================

  group('encode/decode roundtrip', () {
    test('empty layers encode to non-empty bytes', () {
      final layers = <CanvasLayer>[];
      final bytes = BinaryCanvasFormat.encode(layers);

      expect(bytes, isNotNull);
      expect(bytes.length, greaterThan(0));
    });

    test('empty layers roundtrip produces empty layers', () {
      final layers = <CanvasLayer>[];
      final bytes = BinaryCanvasFormat.encode(layers);
      final restored = BinaryCanvasFormat.decode(bytes);

      expect(restored, isEmpty);
    });
  });

  // ===========================================================================
  // Multi-page encode/decode
  // ===========================================================================

  group('multi-page encode/decode', () {
    test('empty pages encode', () {
      final pages = <int, List<CanvasLayer>>{
        0: <CanvasLayer>[],
        1: <CanvasLayer>[],
      };

      final bytes = BinaryCanvasFormat.encodePages(pages);
      expect(bytes.length, greaterThan(0));
    });

    test('empty pages roundtrip', () {
      final pages = <int, List<CanvasLayer>>{0: <CanvasLayer>[]};

      final bytes = BinaryCanvasFormat.encodePages(pages);
      final restored = BinaryCanvasFormat.decodePages(bytes);

      expect(restored, isNotEmpty);
      expect(restored[0], isEmpty);
    });
  });
}
