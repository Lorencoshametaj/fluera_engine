import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/time_travel/services/time_travel_compressor.dart';

void main() {
  // ===========================================================================
  // Stroke compression round-trip
  // ===========================================================================

  group('TimeTravelCompressor - stroke round-trip', () {
    test('compress then decompress preserves stroke data', () {
      final strokeData = <String, dynamic>{
        'points': [
          {'x': 100.0, 'y': 200.0, 'pressure': 0.5, 'timestamp': 1000},
          {'x': 110.0, 'y': 210.0, 'pressure': 0.5, 'timestamp': 1016},
          {'x': 120.0, 'y': 220.0, 'pressure': 0.6, 'timestamp': 1032},
          {'x': 130.0, 'y': 225.0, 'pressure': 0.6, 'timestamp': 1048},
        ],
        'color': 0xFF000000,
        'width': 2.0,
      };
      final compressed = TimeTravelCompressor.compressStrokeData(
        Map<String, dynamic>.from(strokeData),
      );
      final decompressed = TimeTravelCompressor.decompressStrokeData(
        compressed,
      );
      final origPoints = strokeData['points'] as List;
      final decPoints = decompressed['points'] as List;
      expect(decPoints.length, origPoints.length);
    });

    test('compressed data has compression marker', () {
      final strokeData = <String, dynamic>{
        'points': List.generate(
          50,
          (i) => {
            'x': 100.0 + i * 2.0,
            'y': 200.0 + i * 1.5,
            'pressure': 0.5,
            'timestamp': 1000 + i * 16,
          },
        ),
        'color': 0xFF000000,
        'width': 2.0,
      };
      final compressed = TimeTravelCompressor.compressStrokeData(
        Map<String, dynamic>.from(strokeData),
      );
      expect(compressed.containsKey('_tt_v'), isTrue);
    });
  });

  // ===========================================================================
  // compressElementData dispatch
  // ===========================================================================

  group('TimeTravelCompressor - element dispatch', () {
    test('strokeAdded type triggers stroke compression', () {
      final data = <String, dynamic>{
        'points': [
          {'x': 10.0, 'y': 20.0, 'pressure': 0.5, 'timestamp': 100},
        ],
      };
      final result = TimeTravelCompressor.compressElementData(
        'strokeAdded',
        data,
      );
      expect(result, isNotNull);
    });

    test('null data returns null', () {
      expect(
        TimeTravelCompressor.compressElementData('strokeAdded', null),
        isNull,
      );
    });

    test('non-stroke type passes data through', () {
      final data = <String, dynamic>{'id': 'shape1', 'type': 'rect'};
      final result = TimeTravelCompressor.compressElementData(
        'shapeAdded',
        data,
      );
      expect(result, equals(data));
    });
  });

  // ===========================================================================
  // decompressElementData dispatch
  // ===========================================================================

  group('TimeTravelCompressor - decompress dispatch', () {
    test('decompresses strokeAdded data', () {
      final data = <String, dynamic>{
        'points': [
          {'x': 50.0, 'y': 60.0, 'pressure': 0.7, 'timestamp': 500},
          {'x': 55.0, 'y': 65.0, 'pressure': 0.7, 'timestamp': 516},
        ],
      };
      final compressed = TimeTravelCompressor.compressElementData(
        'strokeAdded',
        data,
      );
      final decompressed = TimeTravelCompressor.decompressElementData(
        'strokeAdded',
        compressed,
      );
      expect(decompressed, isNotNull);
    });

    test('null data returns null', () {
      expect(
        TimeTravelCompressor.decompressElementData('strokeAdded', null),
        isNull,
      );
    });
  });

  // ===========================================================================
  // Edge cases
  // ===========================================================================

  group('TimeTravelCompressor - edge cases', () {
    test('single point stroke compresses', () {
      final data = <String, dynamic>{
        'points': [
          {'x': 100.0, 'y': 200.0, 'pressure': 0.5, 'timestamp': 1000},
        ],
      };
      final compressed = TimeTravelCompressor.compressStrokeData(data);
      final decompressed = TimeTravelCompressor.decompressStrokeData(
        compressed,
      );
      expect((decompressed['points'] as List).length, 1);
    });

    test('empty points list compresses', () {
      final data = <String, dynamic>{'points': <Map<String, dynamic>>[]};
      final compressed = TimeTravelCompressor.compressStrokeData(data);
      final decompressed = TimeTravelCompressor.decompressStrokeData(
        compressed,
      );
      expect((decompressed['points'] as List), isEmpty);
    });
  });
}
