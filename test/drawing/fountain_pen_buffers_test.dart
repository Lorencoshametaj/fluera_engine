import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/drawing/brushes/fountain_pen_buffers.dart';

void main() {
  // =========================================================================
  // StrokeWidthBuffer
  // =========================================================================

  group('StrokeWidthBuffer', () {
    late StrokeWidthBuffer buffer;

    setUp(() {
      buffer = StrokeWidthBuffer();
    });

    test('starts with zero length', () {
      expect(buffer.length, 0);
    });

    test('add increases length', () {
      buffer.reset(10);
      buffer.add(1.0);
      buffer.add(2.0);
      buffer.add(3.0);
      expect(buffer.length, 3);
    });

    test('reset clears length but preserves capacity', () {
      buffer.reset(10);
      buffer.add(1.0);
      buffer.add(2.0);
      buffer.reset(10);
      expect(buffer.length, 0);
    });

    test('indexing works correctly', () {
      buffer.reset(10);
      buffer.add(5.0);
      buffer.add(10.0);
      buffer.add(15.0);
      expect(buffer[0], 5.0);
      expect(buffer[1], 10.0);
      expect(buffer[2], 15.0);
    });

    test('index assignment works correctly', () {
      buffer.reset(10);
      buffer.add(5.0);
      buffer[0] = 99.0;
      expect(buffer[0], 99.0);
    });

    test('auto-grows beyond initial capacity', () {
      buffer.reset(5);
      // Add more than 2048 (initial capacity) items
      for (int i = 0; i < 3000; i++) {
        buffer.add(i.toDouble());
      }
      expect(buffer.length, 3000);
      expect(buffer[2999], 2999.0);
    });

    test('reset with larger size grows internal array', () {
      buffer.reset(5000);
      for (int i = 0; i < 5000; i++) {
        buffer.add(i.toDouble());
      }
      expect(buffer.length, 5000);
      expect(buffer[4999], 4999.0);
    });
  });

  // =========================================================================
  // StrokeOffsetBuffer
  // =========================================================================

  group('StrokeOffsetBuffer', () {
    late StrokeOffsetBuffer buffer;

    setUp(() {
      buffer = StrokeOffsetBuffer();
    });

    test('starts with zero length', () {
      expect(buffer.length, 0);
    });

    test('add increases length', () {
      buffer.reset(10);
      buffer.add(const Offset(1, 2));
      buffer.add(const Offset(3, 4));
      expect(buffer.length, 2);
    });

    test('reset clears length', () {
      buffer.reset(10);
      buffer.add(const Offset(1, 2));
      buffer.reset(10);
      expect(buffer.length, 0);
    });

    test('indexing works correctly', () {
      buffer.reset(10);
      buffer.add(const Offset(10, 20));
      buffer.add(const Offset(30, 40));
      expect(buffer[0], const Offset(10, 20));
      expect(buffer[1], const Offset(30, 40));
    });

    test('index assignment works correctly', () {
      buffer.reset(10);
      buffer.add(const Offset(10, 20));
      buffer[0] = const Offset(99, 99);
      expect(buffer[0], const Offset(99, 99));
    });

    test('view returns correct sublist', () {
      buffer.reset(10);
      buffer.add(const Offset(1, 1));
      buffer.add(const Offset(2, 2));
      buffer.add(const Offset(3, 3));
      final view = buffer.view;
      expect(view.length, 3);
      expect(view[0], const Offset(1, 1));
      expect(view[2], const Offset(3, 3));
    });

    test('view is empty after reset', () {
      buffer.reset(10);
      buffer.add(const Offset(1, 1));
      buffer.reset(10);
      expect(buffer.view, isEmpty);
    });

    test('auto-grows beyond initial capacity', () {
      buffer.reset(5);
      for (int i = 0; i < 3000; i++) {
        buffer.add(Offset(i.toDouble(), i.toDouble()));
      }
      expect(buffer.length, 3000);
      expect(buffer[2999], const Offset(2999, 2999));
    });
  });
}
