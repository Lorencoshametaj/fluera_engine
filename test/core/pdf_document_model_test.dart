import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/models/pdf_document_model.dart';
import 'package:fluera_engine/src/core/models/pdf_page_model.dart';

void main() {
  // ===========================================================================
  // PdfLayoutMode enum
  // ===========================================================================

  group('PdfLayoutMode', () {
    test('has 3 modes', () {
      expect(PdfLayoutMode.values.length, 3);
      expect(PdfLayoutMode.values, contains(PdfLayoutMode.grid));
      expect(PdfLayoutMode.values, contains(PdfLayoutMode.continuous));
      expect(PdfLayoutMode.values, contains(PdfLayoutMode.presentation));
    });
  });

  // ===========================================================================
  // Construction
  // ===========================================================================

  PdfDocumentModel makeDoc({int pages = 2}) => PdfDocumentModel(
    sourceHash: 'abc123',
    totalPages: pages,
    pages: List.generate(
      pages,
      (i) => PdfPageModel(pageIndex: i, originalSize: const Size(612, 792)),
    ),
  );

  group('PdfDocumentModel - construction', () {
    test('creates with required fields', () {
      final doc = makeDoc();
      expect(doc.sourceHash, 'abc123');
      expect(doc.totalPages, 2);
      expect(doc.pages.length, 2);
    });

    test('defaults are sensible', () {
      final doc = makeDoc();
      expect(doc.gridColumns, 2);
      expect(doc.gridSpacing, 20.0);
      expect(doc.nightMode, isFalse);
      expect(doc.layoutMode, PdfLayoutMode.grid);
    });
  });

  // ===========================================================================
  // copyWith
  // ===========================================================================

  group('PdfDocumentModel - copyWith', () {
    test('overrides fields', () {
      final doc = makeDoc();
      final copy = doc.copyWith(gridColumns: 4, nightMode: true);
      expect(copy.gridColumns, 4);
      expect(copy.nightMode, isTrue);
      expect(copy.sourceHash, 'abc123'); // preserved
    });

    test('clearWatermarkText nulls watermark', () {
      final doc = makeDoc().copyWith(watermarkText: 'DRAFT');
      final cleared = doc.copyWith(clearWatermarkText: true);
      expect(cleared.watermarkText, isNull);
    });

    test('clearTimelineRef nulls ref', () {
      final doc = makeDoc().copyWith(timelineRef: 'ref-1');
      final cleared = doc.copyWith(clearTimelineRef: true);
      expect(cleared.timelineRef, isNull);
    });
  });

  // ===========================================================================
  // Equality
  // ===========================================================================

  group('PdfDocumentModel - equality', () {
    test('equal documents', () {
      final a = makeDoc();
      final b = makeDoc();
      expect(a, b);
    });
  });

  // ===========================================================================
  // Serialization
  // ===========================================================================

  group('PdfDocumentModel - toJson/fromJson', () {
    test('round-trips', () {
      final doc = makeDoc().copyWith(
        nightMode: true,
        layoutMode: PdfLayoutMode.continuous,
        watermarkText: 'CONFIDENTIAL',
      );
      final json = doc.toJson();
      final restored = PdfDocumentModel.fromJson(json);
      expect(restored.sourceHash, 'abc123');
      expect(restored.totalPages, 2);
      expect(restored.nightMode, isTrue);
      expect(restored.layoutMode, PdfLayoutMode.continuous);
      expect(restored.watermarkText, 'CONFIDENTIAL');
    });

    test('fromJson with minimal data uses defaults', () {
      final doc = PdfDocumentModel.fromJson({});
      expect(doc.sourceHash, '');
      expect(doc.totalPages, 0);
      expect(doc.gridColumns, 2);
    });
  });

  // ===========================================================================
  // toString
  // ===========================================================================

  group('PdfDocumentModel - toString', () {
    test('is readable', () {
      final doc = makeDoc();
      expect(doc.toString(), contains('2 pages'));
    });
  });
}
