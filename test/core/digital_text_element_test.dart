import 'package:nebula_engine/src/core/scene_graph/node_id.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/models/digital_text_element.dart';

void main() {
  DigitalTextElement _createElement({
    String id = 'test-1',
    String text = 'Hello World',
    Offset position = const Offset(100, 200),
    double fontSize = 24.0,
    double scale = 1.0,
    Color color = Colors.black,
  }) {
    return DigitalTextElement(
      id: id,
      text: text,
      position: position,
      color: color,
      fontSize: fontSize,
      scale: scale,
      createdAt: DateTime(2026, 1, 1),
    );
  }

  group('DigitalTextElement layout caching', () {
    test('layoutPainter is created lazily and returns non-null', () {
      final element = _createElement();
      final painter = element.layoutPainter;
      expect(painter, isNotNull);
      expect(painter, isA<TextPainter>());
    });

    test('layoutPainter returns same instance on subsequent calls', () {
      final element = _createElement();
      final painter1 = element.layoutPainter;
      final painter2 = element.layoutPainter;
      expect(
        identical(painter1, painter2),
        isTrue,
        reason: 'layoutPainter should return the cached instance',
      );
    });

    test('layoutPainter has correct text after layout', () {
      final element = _createElement(text: 'Test ABC');
      final painter = element.layoutPainter;
      expect(painter.text, isNotNull);
      expect((painter.text as TextSpan).text, 'Test ABC');
    });

    test('layoutPainter applies fontSize * scale', () {
      final element = _createElement(fontSize: 20.0, scale: 2.0);
      final painter = element.layoutPainter;
      final style = (painter.text as TextSpan).style!;
      expect(style.fontSize, 40.0); // 20 * 2
    });

    test('layoutPainter has been laid out (width/height > 0)', () {
      final element = _createElement(text: 'ABC');
      final painter = element.layoutPainter;
      expect(painter.width, greaterThan(0));
      expect(painter.height, greaterThan(0));
    });

    test('copyWith produces element with fresh cache (no shared state)', () {
      final original = _createElement(text: 'Original');
      final _ = original.layoutPainter; // Trigger cache

      final copy = original.copyWith(text: 'Modified');
      final copyPainter = copy.layoutPainter;

      // Must be a different TextPainter instance
      expect(identical(original.layoutPainter, copyPainter), isFalse);
      expect((copyPainter.text as TextSpan).text, 'Modified');
    });

    test('copyWith(fontSize) produces different layout dimensions', () {
      final small = _createElement(text: 'Text', fontSize: 12.0);
      final large = _createElement(text: 'Text', fontSize: 48.0);

      // Both should produce valid painters with different sizes
      expect(small.layoutPainter.height, lessThan(large.layoutPainter.height));
    });

    test(
      'copyWith(position) produces different bounds but same painter size',
      () {
        final a = _createElement(position: const Offset(0, 0));
        final b = a.copyWith(position: const Offset(500, 500));

        // Painter size should be identical (same text, same fontSize)
        expect(a.layoutPainter.width, b.layoutPainter.width);
        expect(a.layoutPainter.height, b.layoutPainter.height);
      },
    );
  });

  group('DigitalTextElement getBounds caching', () {
    test('getBounds returns cached Rect on consecutive calls', () {
      final element = _createElement(
        text: 'Cached',
        position: const Offset(10, 20),
      );

      final bounds1 = element.getBounds();
      final bounds2 = element.getBounds();

      expect(bounds1, bounds2);
      expect(
        identical(bounds1, bounds2),
        isTrue,
        reason: 'getBounds should return the exact same Rect instance',
      );
    });

    test('getBounds position matches element position', () {
      final element = _createElement(position: const Offset(42, 99));
      final bounds = element.getBounds();

      expect(bounds.left, 42.0);
      expect(bounds.top, 99.0);
      expect(bounds.width, greaterThan(0));
      expect(bounds.height, greaterThan(0));
    });

    test('copyWith invalidates bounds cache', () {
      final original = _createElement(text: 'Short');
      final boundsOriginal = original.getBounds();

      final modified = original.copyWith(text: 'This is a much longer text');
      final boundsModified = modified.getBounds();

      expect(
        boundsModified.width,
        greaterThan(boundsOriginal.width),
        reason: 'Longer text should produce wider bounds',
      );
    });
  });

  group('DigitalTextElement containsPoint', () {
    test('containsPoint uses cached bounds', () {
      final element = _createElement(
        position: const Offset(100, 100),
        text: 'Clickable',
      );

      // Point inside the text area
      expect(element.containsPoint(const Offset(105, 105)), isTrue);

      // Point far outside
      expect(element.containsPoint(const Offset(5000, 5000)), isFalse);
    });
  });

  group('DigitalTextElement serialization', () {
    test('toJson/fromJson round-trip preserves all fields', () {
      final original = _createElement(
        id: NodeId('ser-1'),
        text: 'Serialize me',
        position: const Offset(11.5, 22.5),
        fontSize: 18.0,
        scale: 1.5,
        color: Colors.red,
      );

      final json = original.toJson();
      final restored = DigitalTextElement.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.text, original.text);
      expect(restored.position, original.position);
      expect(restored.fontSize, original.fontSize);
      expect(restored.scale, original.scale);
    });

    test('equality is based on id only', () {
      final a = _createElement(id: NodeId('same-id'), text: 'A');
      final b = _createElement(id: NodeId('same-id'), text: 'B');
      final c = _createElement(id: NodeId('diff-id'), text: 'A');

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });
}
