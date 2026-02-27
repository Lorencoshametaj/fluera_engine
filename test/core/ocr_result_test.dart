import 'dart:ui' show Rect;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/models/ocr_result.dart';

void main() {
  // ===========================================================================
  // OcrTextBlock
  // ===========================================================================

  group('OcrTextBlock', () {
    test('creates with required fields', () {
      const block = OcrTextBlock(
        text: 'Hello',
        rect: Rect.fromLTWH(0.1, 0.2, 0.3, 0.4),
        confidence: 0.95,
      );
      expect(block.text, 'Hello');
      expect(block.rect.left, closeTo(0.1, 0.001));
      expect(block.confidence, 0.95);
    });

    test('fromMap clamps bounds to 0-1', () {
      final block = OcrTextBlock.fromMap({
        'text': 'Overflow',
        'x': -0.5,
        'y': 1.5,
        'width': 2.0,
        'height': -1.0,
        'confidence': 1.5,
      });
      expect(block.rect.left, 0.0);
      expect(block.rect.top, 1.0);
      expect(block.rect.width, 1.0);
      expect(block.rect.height, 0.0);
      expect(block.confidence, 1.0);
    });

    test('toJson / fromJson round-trip', () {
      const original = OcrTextBlock(
        text: 'World',
        rect: Rect.fromLTWH(0.1, 0.2, 0.5, 0.3),
        confidence: 0.85,
      );
      final json = original.toJson();
      final restored = OcrTextBlock.fromJson(json);
      expect(restored, equals(original));
    });

    test('copyWith overrides fields', () {
      const original = OcrTextBlock(text: 'A', rect: Rect.fromLTWH(0, 0, 1, 1));
      final copy = original.copyWith(text: 'B', confidence: 0.5);
      expect(copy.text, 'B');
      expect(copy.confidence, 0.5);
      expect(copy.rect, original.rect);
    });

    test('estimatedBytes is positive', () {
      const block = OcrTextBlock(
        text: 'Test string',
        rect: Rect.fromLTWH(0, 0, 1, 1),
      );
      expect(block.estimatedBytes, greaterThan(0));
    });

    test('equality by text, rect, confidence', () {
      const a = OcrTextBlock(
        text: 'Same',
        rect: Rect.fromLTWH(0, 0, 1, 1),
        confidence: 0.9,
      );
      const b = OcrTextBlock(
        text: 'Same',
        rect: Rect.fromLTWH(0, 0, 1, 1),
        confidence: 0.9,
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });
  });

  // ===========================================================================
  // OcrPageResult
  // ===========================================================================

  group('OcrPageResult', () {
    test('empty sentinel', () {
      expect(OcrPageResult.empty.isEmpty, isTrue);
      expect(OcrPageResult.empty.blocks, isEmpty);
    });

    test('averageConfidence computes correctly', () {
      final result = OcrPageResult(
        text: 'Hello World',
        blocks: const [
          OcrTextBlock(
            text: 'Hello',
            rect: Rect.fromLTWH(0, 0, 0.5, 0.5),
            confidence: 0.8,
          ),
          OcrTextBlock(
            text: 'World',
            rect: Rect.fromLTWH(0.5, 0, 0.5, 0.5),
            confidence: 0.6,
          ),
        ],
      );
      expect(result.averageConfidence, closeTo(0.7, 0.01));
    });

    test('minConfidence returns lowest', () {
      final result = OcrPageResult(
        text: 'A B',
        blocks: const [
          OcrTextBlock(
            text: 'A',
            rect: Rect.fromLTWH(0, 0, 1, 1),
            confidence: 0.9,
          ),
          OcrTextBlock(
            text: 'B',
            rect: Rect.fromLTWH(0, 0, 1, 1),
            confidence: 0.3,
          ),
        ],
      );
      expect(result.minConfidence, closeTo(0.3, 0.01));
    });

    test('blocksAboveConfidence counts correctly', () {
      final result = OcrPageResult(
        text: 'A B C',
        blocks: const [
          OcrTextBlock(
            text: 'A',
            rect: Rect.fromLTWH(0, 0, 1, 1),
            confidence: 0.9,
          ),
          OcrTextBlock(
            text: 'B',
            rect: Rect.fromLTWH(0, 0, 1, 1),
            confidence: 0.5,
          ),
          OcrTextBlock(
            text: 'C',
            rect: Rect.fromLTWH(0, 0, 1, 1),
            confidence: 0.3,
          ),
        ],
      );
      expect(result.blocksAboveConfidence(0.5), 2);
    });

    test('filterByConfidence removes low-confidence blocks', () {
      final result = OcrPageResult(
        text: 'A B C',
        blocks: const [
          OcrTextBlock(
            text: 'A',
            rect: Rect.fromLTWH(0, 0, 1, 1),
            confidence: 0.9,
          ),
          OcrTextBlock(
            text: 'B',
            rect: Rect.fromLTWH(0, 0, 1, 1),
            confidence: 0.2,
          ),
          OcrTextBlock(
            text: 'C',
            rect: Rect.fromLTWH(0, 0, 1, 1),
            confidence: 0.8,
          ),
        ],
      );
      final filtered = result.filterByConfidence(0.5);
      expect(filtered.blocks.length, 2);
      expect(filtered.blocks[0].text, 'A');
      expect(filtered.blocks[1].text, 'C');
    });

    test('toJson / fromJson round-trip', () {
      final original = OcrPageResult(
        text: 'Test text',
        blocks: const [
          OcrTextBlock(
            text: 'Test',
            rect: Rect.fromLTWH(0.1, 0.2, 0.3, 0.4),
            confidence: 0.95,
          ),
        ],
        processingDuration: const Duration(milliseconds: 150),
        pageIndex: 3,
      );
      final json = original.toJson();
      final restored = OcrPageResult.fromJson(json);
      expect(restored.text, original.text);
      expect(restored.blocks.length, original.blocks.length);
      expect(restored.processingDuration, original.processingDuration);
      expect(restored.pageIndex, original.pageIndex);
    });

    test('toTextRects produces PdfTextRects', () {
      final result = OcrPageResult(
        text: 'Hello\nWorld',
        blocks: const [
          OcrTextBlock(text: 'Hello', rect: Rect.fromLTWH(0, 0, 0.5, 0.1)),
          OcrTextBlock(text: 'World', rect: Rect.fromLTWH(0, 0.1, 0.5, 0.1)),
        ],
      );
      final rects = result.toTextRects();
      expect(rects.length, 2);
      expect(rects[0].text, 'Hello');
      expect(rects[1].text, 'World');
    });

    test('copyWith overrides pageIndex', () {
      const original = OcrPageResult(text: 'X', blocks: []);
      final copy = original.copyWith(pageIndex: 5);
      expect(copy.pageIndex, 5);
      expect(copy.text, 'X');
    });

    test('estimatedBytes is positive', () {
      final result = OcrPageResult(
        text: 'Some OCR text',
        blocks: const [
          OcrTextBlock(text: 'Some', rect: Rect.fromLTWH(0, 0, 1, 1)),
        ],
      );
      expect(result.estimatedBytes, greaterThan(0));
    });

    test('value equality works', () {
      const a = OcrPageResult(
        text: 'ABC',
        blocks: [OcrTextBlock(text: 'ABC', rect: Rect.fromLTWH(0, 0, 1, 1))],
      );
      const b = OcrPageResult(
        text: 'ABC',
        blocks: [OcrTextBlock(text: 'ABC', rect: Rect.fromLTWH(0, 0, 1, 1))],
      );
      expect(a, equals(b));
    });
  });

  // ===========================================================================
  // OcrPageStatus
  // ===========================================================================

  group('OcrPageStatus', () {
    test('has all expected values', () {
      expect(OcrPageStatus.values.length, 6);
      expect(OcrPageStatus.values, contains(OcrPageStatus.notAttempted));
      expect(OcrPageStatus.values, contains(OcrPageStatus.completed));
      expect(OcrPageStatus.values, contains(OcrPageStatus.failed));
    });
  });
}
