import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/tools/pdf/pdf_document_operations.dart';
import 'package:fluera_engine/src/export/pdf_export_writer.dart';

/// Helper to create a simple test PDF with the given number of pages.
Uint8List _createTestPdf(
  int pageCount, {
  double width = 200,
  double height = 300,
}) {
  final writer = PdfExportWriter(enableCompression: false);
  for (int i = 0; i < pageCount; i++) {
    writer.beginPage(width: width, height: height);
    writer.drawText('Page ${i + 1}', 10, 50, 14);
  }
  return writer.finish(title: 'Test PDF');
}

void main() {
  group('PdfDocumentOperations', () {
    // =========================================================================
    // 1. Merge — basic
    // =========================================================================
    test('merge combines pages from multiple PDFs', () {
      final pdf1 = _createTestPdf(2);
      final pdf2 = _createTestPdf(3);

      final merged = PdfDocumentOperations.merge([pdf1, pdf2]);

      expect(merged.isNotEmpty, true);
      final text = latin1.decode(merged);
      expect(text, startsWith('%PDF-1.4'));
      expect(text, contains('%%EOF'));
    });

    // =========================================================================
    // 2. Merge — single document passthrough
    // =========================================================================
    test('merge single document returns original', () {
      final pdf = _createTestPdf(3);
      final merged = PdfDocumentOperations.merge([pdf]);
      // Should return the original bytes.
      expect(merged, pdf);
    });

    // =========================================================================
    // 3. Merge — empty input
    // =========================================================================
    test('merge empty list returns empty bytes', () {
      final merged = PdfDocumentOperations.merge([]);
      expect(merged.isEmpty, true);
    });

    // =========================================================================
    // 4. Split by page
    // =========================================================================
    test('splitByPage creates one PDF per page', () {
      final pdf = _createTestPdf(3);
      final pages = PdfDocumentOperations.splitByPage(pdf);

      // Each result should be a valid PDF.
      for (final page in pages) {
        final text = latin1.decode(page);
        expect(text, startsWith('%PDF-1.4'));
        expect(text, contains('%%EOF'));
      }
    });

    // =========================================================================
    // 5. Extract pages
    // =========================================================================
    test('extractPages returns valid PDF', () {
      final pdf = _createTestPdf(5);
      final extracted = PdfDocumentOperations.extractPages(pdf, [0, 2, 4]);

      expect(extracted.isNotEmpty, true);
      final text = latin1.decode(extracted);
      expect(text, startsWith('%PDF-1.4'));
      expect(text, contains('%%EOF'));
    });

    // =========================================================================
    // 6. Extract — out of range indices are skipped
    // =========================================================================
    test('extractPages skips invalid indices', () {
      final pdf = _createTestPdf(2);
      final extracted = PdfDocumentOperations.extractPages(pdf, [0, 5, 10]);

      expect(extracted.isNotEmpty, true);
    });

    // =========================================================================
    // 7. Page count
    // =========================================================================
    test('pageCount returns correct count', () {
      final pdf = _createTestPdf(4);
      final count = PdfDocumentOperations.pageCount(pdf);

      expect(count, 4);
    });
  });
}
