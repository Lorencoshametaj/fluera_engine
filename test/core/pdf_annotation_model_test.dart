import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/models/pdf_annotation_model.dart';

void main() {
  // ===========================================================================
  // Enums
  // ===========================================================================

  group('PdfAnnotationType', () {
    test('has 4 types', () {
      expect(PdfAnnotationType.values.length, 4);
    });
  });

  group('PdfStampType', () {
    test('has stamp values', () {
      expect(PdfStampType.values, contains(PdfStampType.approved));
      expect(PdfStampType.values, contains(PdfStampType.draft));
    });
  });

  // ===========================================================================
  // Construction
  // ===========================================================================

  group('PdfAnnotation - construction', () {
    test('creates with required fields', () {
      const a = PdfAnnotation(
        id: 'ann-1',
        type: PdfAnnotationType.highlight,
        pageIndex: 0,
        rect: Rect.fromLTWH(10, 20, 200, 30),
      );
      expect(a.id, 'ann-1');
      expect(a.type, PdfAnnotationType.highlight);
      expect(a.pageIndex, 0);
    });

    test('default color is yellow highlight', () {
      const a = PdfAnnotation(
        id: 'ann-2',
        type: PdfAnnotationType.highlight,
        pageIndex: 0,
        rect: Rect.zero,
      );
      expect(a.color, const Color(0x80FFEB3B));
    });
  });

  // ===========================================================================
  // copyWith
  // ===========================================================================

  group('PdfAnnotation - copyWith', () {
    test('overrides fields', () {
      const a = PdfAnnotation(
        id: 'ann-1',
        type: PdfAnnotationType.highlight,
        pageIndex: 0,
        rect: Rect.zero,
        text: 'note',
      );
      final b = a.copyWith(pageIndex: 3, color: const Color(0xFFFF0000));
      expect(b.pageIndex, 3);
      expect(b.text, 'note'); // preserved
    });

    test('clearText nulls text', () {
      const a = PdfAnnotation(
        id: 'ann-1',
        type: PdfAnnotationType.stickyNote,
        pageIndex: 0,
        rect: Rect.zero,
        text: 'hello',
      );
      final b = a.copyWith(clearText: true);
      expect(b.text, isNull);
    });
  });

  // ===========================================================================
  // Equality
  // ===========================================================================

  group('PdfAnnotation - equality', () {
    test('equal annotations', () {
      const a = PdfAnnotation(
        id: 'x',
        type: PdfAnnotationType.underline,
        pageIndex: 0,
        rect: Rect.zero,
      );
      const b = PdfAnnotation(
        id: 'x',
        type: PdfAnnotationType.underline,
        pageIndex: 0,
        rect: Rect.zero,
      );
      expect(a, b);
    });
  });

  // ===========================================================================
  // Serialization
  // ===========================================================================

  group('PdfAnnotation - toJson/fromJson', () {
    test('round-trips', () {
      const a = PdfAnnotation(
        id: 'ann-1',
        type: PdfAnnotationType.stickyNote,
        pageIndex: 2,
        rect: Rect.fromLTRB(10, 20, 110, 50),
        text: 'My note',
      );
      final json = a.toJson();
      final restored = PdfAnnotation.fromJson(json);
      expect(restored.id, 'ann-1');
      expect(restored.type, PdfAnnotationType.stickyNote);
      expect(restored.pageIndex, 2);
      expect(restored.text, 'My note');
    });

    test('fromJson with missing fields uses defaults', () {
      final a = PdfAnnotation.fromJson({});
      expect(a.id, '');
      expect(a.type, PdfAnnotationType.highlight);
    });
  });

  // ===========================================================================
  // Extension defaults
  // ===========================================================================

  group('PdfAnnotationTypeDefaults', () {
    test('all types have default color', () {
      for (final type in PdfAnnotationType.values) {
        expect(type.defaultColor, isNotNull);
      }
    });

    test('all types have label', () {
      for (final type in PdfAnnotationType.values) {
        expect(type.label, isNotEmpty);
      }
    });
  });
}
