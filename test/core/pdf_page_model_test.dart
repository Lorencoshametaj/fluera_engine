import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/models/pdf_page_model.dart';

void main() {
  // ===========================================================================
  // PdfPageBackground enum
  // ===========================================================================

  group('PdfPageBackground', () {
    test('has blank and ruled', () {
      expect(PdfPageBackground.values, contains(PdfPageBackground.blank));
      expect(PdfPageBackground.values, contains(PdfPageBackground.ruled));
    });
  });

  // ===========================================================================
  // Construction
  // ===========================================================================

  group('PdfPageModel - construction', () {
    test('creates with page index', () {
      final model = PdfPageModel(
        pageIndex: 0,
        originalSize: const Size(612, 792),
      );
      expect(model.pageIndex, 0);
      expect(model.originalSize, const Size(612, 792));
    });

    test('defaults are sensible', () {
      final model = PdfPageModel(
        pageIndex: 1,
        originalSize: const Size(100, 100),
      );
      expect(model.isLocked, isA<bool>());
      expect(model.rotation, 0.0);
    });
  });

  // ===========================================================================
  // copyWith
  // ===========================================================================

  group('PdfPageModel - copyWith', () {
    test('overrides single field', () {
      final model = PdfPageModel(
        pageIndex: 0,
        originalSize: const Size(100, 100),
      );
      final locked = model.copyWith(isLocked: true);
      expect(locked.isLocked, isTrue);
      expect(locked.pageIndex, 0);
    });

    test('preserves unchanged fields', () {
      final model = PdfPageModel(
        pageIndex: 5,
        originalSize: const Size(200, 300),
        rotation: 90.0,
      );
      final copy = model.copyWith(isBookmarked: true);
      expect(copy.rotation, 90.0);
      expect(copy.pageIndex, 5);
    });
  });

  // ===========================================================================
  // toJson
  // ===========================================================================

  group('PdfPageModel - toJson', () {
    test('serializes to map', () {
      final model = PdfPageModel(
        pageIndex: 0,
        originalSize: const Size(612, 792),
      );
      final json = model.toJson();
      expect(json, isA<Map<String, dynamic>>());
      expect(json['pageIndex'], 0);
    });
  });

  // ===========================================================================
  // toString
  // ===========================================================================

  group('PdfPageModel - toString', () {
    test('is readable', () {
      final model = PdfPageModel(
        pageIndex: 3,
        originalSize: const Size(100, 100),
      );
      expect(model.toString(), isNotEmpty);
    });
  });
}
