import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/export/pdf_export_writer.dart';

void main() {
  group('PdfExportWriter', () {
    // =========================================================================
    // 1. Valid PDF structure
    // =========================================================================
    test('generates valid PDF with header and trailer', () {
      final writer = PdfExportWriter();
      writer.beginPage(width: 200, height: 300);
      final bytes = writer.finish();
      final text = latin1.decode(bytes);

      expect(text, startsWith('%PDF-1.4'));
      expect(text, contains('%%EOF'));
      expect(text, contains('xref'));
      expect(text, contains('trailer'));
      expect(text, contains('startxref'));
      expect(text, contains('/Type /Catalog'));
      expect(text, contains('/Type /Pages'));
    });

    // =========================================================================
    // 2. Page dimensions
    // =========================================================================
    test('sets correct MediaBox dimensions', () {
      final writer = PdfExportWriter();
      writer.beginPage(width: 400, height: 600);
      final bytes = writer.finish();
      final text = latin1.decode(bytes);

      expect(text, contains('/MediaBox [0 0 400 600]'));
    });

    // =========================================================================
    // 3. Default page size (A4)
    // =========================================================================
    test('uses A4 default dimensions', () {
      final writer = PdfExportWriter();
      writer.beginPage();
      final bytes = writer.finish();
      final text = latin1.decode(bytes);

      expect(text, contains('/MediaBox [0 0 595 842]'));
    });

    // =========================================================================
    // 4. Rectangle commands
    // =========================================================================
    test('generates rectangle PDF operators', () {
      final writer = PdfExportWriter();
      writer.beginPage(width: 200, height: 200);
      writer.drawRect(10, 10, 50, 30);
      writer.fill();
      final bytes = writer.finish();
      final text = latin1.decode(bytes);

      // Should contain 're' (rectangle) and 'f' (fill) operators.
      expect(text, contains('re'));
      expect(text, contains('f'));
    });

    // =========================================================================
    // 5. Path commands
    // =========================================================================
    test('generates path PDF operators', () {
      final writer = PdfExportWriter();
      writer.beginPage(width: 200, height: 200);
      writer.moveTo(10, 10);
      writer.lineTo(50, 50);
      writer.curveTo(60, 60, 70, 70, 80, 80);
      writer.closePath();
      writer.stroke();
      final bytes = writer.finish();
      final text = latin1.decode(bytes);

      // Should contain m (move), l (line), c (curve), h (close), S (stroke).
      expect(text, contains(' m'));
      expect(text, contains(' l'));
      expect(text, contains(' c'));
      expect(text, contains('h'));
      expect(text, contains('S'));
    });

    // =========================================================================
    // 6. Fill and stroke colors
    // =========================================================================
    test('generates color operators', () {
      final writer = PdfExportWriter();
      writer.beginPage(width: 100, height: 100);
      writer.setFillColor(const Color(0xFFFF0000)); // Red
      writer.setStrokeColor(const Color(0xFF0000FF)); // Blue
      writer.drawRect(0, 0, 50, 50);
      writer.fillAndStroke();
      final bytes = writer.finish();
      final text = latin1.decode(bytes);

      // Should contain rg (fill color) and RG (stroke color) operators.
      expect(text, contains('rg'));
      expect(text, contains('RG'));
      // Should contain B (fill and stroke).
      expect(text, contains('B'));
    });

    // =========================================================================
    // 7. Transform matrix
    // =========================================================================
    test('generates transform matrix operator', () {
      final writer = PdfExportWriter();
      writer.beginPage(width: 100, height: 100);
      writer.setTransform(1, 0, 0, 1, 50, 50);
      final bytes = writer.finish();
      final text = latin1.decode(bytes);

      // Should contain 'cm' (concat matrix).
      expect(text, contains(' cm'));
    });

    // =========================================================================
    // 8. Graphics state save/restore
    // =========================================================================
    test('generates save/restore operators', () {
      final writer = PdfExportWriter();
      writer.beginPage(width: 100, height: 100);
      writer.saveState();
      writer.setLineWidth(2.0);
      writer.restoreState();
      final bytes = writer.finish();
      final text = latin1.decode(bytes);

      // Should contain q (save) and Q (restore).
      expect(text, contains('q'));
      expect(text, contains('Q'));
    });

    // =========================================================================
    // 9. Text rendering
    // =========================================================================
    test('generates text operators', () {
      final writer = PdfExportWriter();
      writer.beginPage(width: 200, height: 200);
      writer.drawText('Hello PDF!', 10, 50, 12);
      final bytes = writer.finish();
      final text = latin1.decode(bytes);

      // Should contain BT/ET (begin/end text), Tf (font), Td (position), Tj (show).
      expect(text, contains('BT'));
      expect(text, contains('ET'));
      expect(text, contains('Tf'));
      expect(text, contains('Td'));
      expect(text, contains('Hello PDF!'));
      // Font resource should be Helvetica.
      expect(text, contains('/BaseFont /Helvetica'));
    });

    // =========================================================================
    // 10. Multi-page output
    // =========================================================================
    test('generates multi-page PDF', () {
      final writer = PdfExportWriter();
      writer.beginPage(width: 200, height: 300);
      writer.drawRect(0, 0, 100, 100);
      writer.fill();

      writer.beginPage(width: 400, height: 600);
      writer.drawRect(10, 10, 50, 50);
      writer.fill();

      final bytes = writer.finish();
      final text = latin1.decode(bytes);

      // Should contain /Count 2.
      expect(text, contains('/Count 2'));
      // Should contain both MediaBoxes.
      expect(text, contains('/MediaBox [0 0 200 300]'));
      expect(text, contains('/MediaBox [0 0 400 600]'));
    });

    // =========================================================================
    // 11. Empty document
    // =========================================================================
    test('empty writer produces valid PDF', () {
      final writer = PdfExportWriter();
      final bytes = writer.finish();
      final text = latin1.decode(bytes);

      // Should still be a valid PDF.
      expect(text, startsWith('%PDF-1.4'));
      expect(text, contains('%%EOF'));
      // Should have exactly 1 blank page.
      expect(text, contains('/Count 1'));
    });

    // =========================================================================
    // 12. Opacity via ExtGState
    // =========================================================================
    test('generates ExtGState for opacity', () {
      final writer = PdfExportWriter();
      writer.beginPage(width: 100, height: 100);
      writer.setOpacity(0.5);
      writer.drawRect(0, 0, 50, 50);
      writer.fill();
      final bytes = writer.finish();
      final text = latin1.decode(bytes);

      // Should contain ExtGState with ca/CA operators.
      expect(text, contains('/ExtGState'));
      expect(text, contains('gs'));
    });

    // =========================================================================
    // 13. Text escaping
    // =========================================================================
    test('escapes special characters in text', () {
      final writer = PdfExportWriter();
      writer.beginPage(width: 200, height: 200);
      writer.drawText('Hello (world) \\test', 10, 50, 12);
      final bytes = writer.finish();
      final text = latin1.decode(bytes);

      // Parentheses and backslash should be escaped.
      expect(text, contains(r'Hello \(world\)'));
    });

    // =========================================================================
    // 14. hasPages property
    // =========================================================================
    test('hasPages reflects state correctly', () {
      final writer = PdfExportWriter();
      expect(writer.hasPages, isFalse);

      writer.beginPage(width: 100, height: 100);
      expect(writer.hasPages, isTrue);
    });

    // =========================================================================
    // 15. Flate compression
    // =========================================================================
    test('generates compressed content streams with FlateDecode', () {
      final writer = PdfExportWriter(enableCompression: true);
      writer.beginPage(width: 200, height: 200);
      // Write enough content to trigger compression (>64 bytes)
      for (int i = 0; i < 20; i++) {
        writer.drawRect(i.toDouble(), i.toDouble(), 50, 50);
        writer.fill();
      }
      final bytes = writer.finish();
      final text = latin1.decode(bytes);

      expect(text, contains('/Filter /FlateDecode'));
    });

    test('compression disabled produces no FlateDecode', () {
      final writer = PdfExportWriter(enableCompression: false);
      writer.beginPage(width: 200, height: 200);
      for (int i = 0; i < 20; i++) {
        writer.drawRect(i.toDouble(), i.toDouble(), 50, 50);
        writer.fill();
      }
      final bytes = writer.finish();
      final text = latin1.decode(bytes);

      expect(text, isNot(contains('/Filter /FlateDecode')));
    });

    test('compressed PDF is smaller than uncompressed', () {
      // Compressed version
      final writerC = PdfExportWriter(enableCompression: true);
      writerC.beginPage(width: 200, height: 200);
      for (int i = 0; i < 50; i++) {
        writerC.drawRect(i.toDouble(), i.toDouble(), 50, 50);
        writerC.fill();
      }
      final compressed = writerC.finish();

      // Uncompressed version
      final writerU = PdfExportWriter(enableCompression: false);
      writerU.beginPage(width: 200, height: 200);
      for (int i = 0; i < 50; i++) {
        writerU.drawRect(i.toDouble(), i.toDouble(), 50, 50);
        writerU.fill();
      }
      final uncompressed = writerU.finish();

      expect(
        compressed.length,
        lessThan(uncompressed.length),
        reason: 'Compressed PDF should be smaller',
      );
    });

    // =========================================================================
    // 16. Line styling (cap, join, dash)
    // =========================================================================
    test('generates line cap and join operators', () {
      final writer = PdfExportWriter(enableCompression: false);
      writer.beginPage(width: 100, height: 100);
      writer.setLineCap(1); // Round
      writer.setLineJoin(1); // Round
      writer.setDashPattern([6, 3], 0);
      writer.moveTo(10, 10);
      writer.lineTo(90, 90);
      writer.stroke();
      final bytes = writer.finish();
      final text = latin1.decode(bytes);

      expect(text, contains('1 J')); // line cap
      expect(text, contains('1 j')); // line join
      expect(text, contains('[6 3] 0 d')); // dash pattern
    });

    // =========================================================================
    // 17. Clipping paths
    // =========================================================================
    test('generates clipping operators', () {
      final writer = PdfExportWriter(enableCompression: false);
      writer.beginPage(width: 200, height: 200);
      writer.clipRect(10, 10, 100, 100);
      writer.setFillColor(const Color(0xFFFF0000));
      writer.drawRect(0, 0, 200, 200);
      writer.fill();
      final bytes = writer.finish();
      final text = latin1.decode(bytes);

      expect(text, contains('W n')); // clip operator
    });

    // =========================================================================
    // 18. PDF metadata
    // =========================================================================
    test('generates Info dictionary with metadata', () {
      final writer = PdfExportWriter(enableCompression: false);
      writer.beginPage(width: 100, height: 100);
      final bytes = writer.finish(
        title: 'Test Document',
        author: 'Test Author',
      );
      final text = latin1.decode(bytes);

      expect(text, contains('/Title (Test Document)'));
      expect(text, contains('/Author (Test Author)'));
      expect(text, contains('/Creator (Nebula Engine)'));
      expect(text, contains('/Producer (Nebula Engine PDF Writer)'));
      expect(text, contains('/CreationDate'));
      expect(text, contains('/Info'));
    });

    test('no Info dict when no metadata provided', () {
      final writer = PdfExportWriter(enableCompression: false);
      writer.beginPage(width: 100, height: 100);
      final bytes = writer.finish();
      final text = latin1.decode(bytes);

      expect(text, isNot(contains('/Info')));
    });

    // =========================================================================
    // 19. JPEG image XObject
    // =========================================================================
    test('embeds JPEG image XObject with DCTDecode', () {
      final writer = PdfExportWriter(enableCompression: false);
      writer.beginPage(width: 200, height: 200);

      // Create a minimal fake JPEG (just the marker bytes for testing)
      final fakeJpeg = Uint8List.fromList([
        0xFF, 0xD8, 0xFF, 0xE0, // JPEG SOI + APP0
        ...List.filled(100, 0x42), // fake data
        0xFF, 0xD9, // JPEG EOI
      ]);

      final xobj = writer.addJpegXObject(fakeJpeg, 100, 80);
      writer.drawImageXObject(xobj, 10, 10, 100, 80);
      final bytes = writer.finish();
      final text = latin1.decode(bytes);

      expect(text, contains('/Subtype /Image'));
      expect(text, contains('/Filter /DCTDecode'));
      expect(text, contains('/Width 100'));
      expect(text, contains('/Height 80'));
      expect(text, contains('/ColorSpace /DeviceRGB'));
      expect(text, contains('Do')); // image draw operator
      expect(text, contains('/XObject')); // in resources
    });

    // =========================================================================
    // 20. RGBA image XObject with SMask
    // =========================================================================
    test('embeds RGBA image XObject with FlateDecode and SMask', () {
      final writer = PdfExportWriter(enableCompression: false);
      writer.beginPage(width: 200, height: 200);

      // Create a 2x2 RGBA image with varying alpha
      final rgba = Uint8List.fromList([
        255, 0, 0, 255, // Red, fully opaque
        0, 255, 0, 128, // Green, half transparent
        0, 0, 255, 0, // Blue, fully transparent
        255, 255, 0, 200, // Yellow, mostly opaque
      ]);

      final xobj = writer.addRgbaXObject(rgba, 2, 2);
      writer.drawImageXObject(xobj, 0, 0, 100, 100);
      final bytes = writer.finish();
      final text = latin1.decode(bytes);

      expect(text, contains('/Subtype /Image'));
      expect(text, contains('/SMask')); // alpha channel present
      expect(text, contains('/DeviceGray')); // SMask is grayscale
      expect(xobj.smaskId, isNotNull);
    });

    // =========================================================================
    // 21. Linear gradient shading pattern
    // =========================================================================
    test('generates linear gradient shading pattern', () {
      final writer = PdfExportWriter(enableCompression: false);
      writer.beginPage(width: 200, height: 200);

      final patternId = writer.addLinearGradient(
        const Offset(0, 0),
        const Offset(200, 200),
        [const Color(0xFFFF0000), const Color(0xFF0000FF)],
        [0.0, 1.0],
      );

      writer.setFillGradient(patternId);
      writer.drawRect(0, 0, 200, 200);
      writer.fill();
      final bytes = writer.finish();
      final text = latin1.decode(bytes);

      expect(text, contains('/ShadingType 2')); // linear
      expect(text, contains('/Pattern')); // pattern resource
      expect(text, contains('/FunctionType 2')); // interpolation
      expect(text, contains('/Pattern cs')); // pattern color space
      expect(text, contains('scn')); // set pattern
    });

    // =========================================================================
    // 22. Radial gradient shading pattern
    // =========================================================================
    test('generates radial gradient shading pattern', () {
      final writer = PdfExportWriter(enableCompression: false);
      writer.beginPage(width: 200, height: 200);

      final patternId = writer.addRadialGradient(
        const Offset(100, 100),
        100,
        [const Color(0xFFFF0000), const Color(0xFF0000FF)],
        [0.0, 1.0],
      );

      expect(patternId, greaterThan(0));
      writer.setFillGradient(patternId);
      writer.drawRect(0, 0, 200, 200);
      writer.fill();
      final bytes = writer.finish();
      final text = latin1.decode(bytes);

      expect(text, contains('/ShadingType 3')); // radial
    });

    // =========================================================================
    // 23. Multi-stop gradient (stitching function)
    // =========================================================================
    test('generates multi-stop gradient with stitching function', () {
      final writer = PdfExportWriter(enableCompression: false);
      writer.beginPage(width: 200, height: 200);

      final patternId = writer.addLinearGradient(
        const Offset(0, 0),
        const Offset(200, 0),
        [
          const Color(0xFFFF0000),
          const Color(0xFF00FF00),
          const Color(0xFF0000FF),
        ],
        [0.0, 0.5, 1.0],
      );

      expect(patternId, greaterThan(0));
      final bytes = writer.finish();
      final text = latin1.decode(bytes);

      expect(text, contains('/FunctionType 3')); // stitching
      expect(text, contains('/Bounds')); // multi-stop bounds
    });

    // =========================================================================
    // 24. Bookmarks / Outlines
    // =========================================================================
    test('generates outline tree with bookmarks', () {
      final writer = PdfExportWriter(enableCompression: false);
      writer.beginPage(width: 200, height: 300);
      writer.beginPage(width: 200, height: 300);
      writer.beginPage(width: 200, height: 300);

      writer.addBookmarkEntry('Chapter 1', 0);
      writer.addBookmarkEntry('Chapter 2', 1);
      writer.addBookmarkEntry('Chapter 3', 2);

      final bytes = writer.finish();
      final text = latin1.decode(bytes);

      expect(text, contains('/Type /Outlines'));
      expect(text, contains('/Title (Chapter 1)'));
      expect(text, contains('/Title (Chapter 2)'));
      expect(text, contains('/Title (Chapter 3)'));
      expect(text, contains('/Dest'));
      expect(text, contains('/Fit'));
      expect(text, contains('/PageMode /UseOutlines'));
    });

    test('generates nested bookmarks', () {
      final writer = PdfExportWriter(enableCompression: false);
      writer.beginPage(width: 200, height: 300);
      writer.beginPage(width: 200, height: 300);

      writer.addBookmark(
        PdfBookmark(
          title: 'Parent',
          pageIndex: 0,
          children: [
            PdfBookmark(title: 'Child 1', pageIndex: 0),
            PdfBookmark(title: 'Child 2', pageIndex: 1),
          ],
        ),
      );

      final bytes = writer.finish();
      final text = latin1.decode(bytes);

      expect(text, contains('/Title (Parent)'));
      expect(text, contains('/Title (Child 1)'));
      expect(text, contains('/Title (Child 2)'));
      expect(text, contains('/Count 2')); // children count
    });

    // =========================================================================
    // 25. Watermarks
    // =========================================================================
    test('generates diagonal watermark', () {
      final writer = PdfExportWriter(enableCompression: false);
      writer.setWatermark(
        const PdfWatermark(text: 'DRAFT', position: WatermarkPosition.diagonal),
      );
      writer.beginPage(width: 595, height: 842);
      writer.drawRect(10, 10, 100, 100);
      writer.fill();
      final bytes = writer.finish();
      final text = latin1.decode(bytes);

      expect(text, contains('DRAFT'));
      expect(text, contains('Tm')); // text matrix (rotation)
      expect(text, contains('gs')); // opacity
    });

    test('generates centered watermark', () {
      final writer = PdfExportWriter(enableCompression: false);
      writer.setWatermark(
        const PdfWatermark(
          text: 'CONFIDENTIAL',
          position: WatermarkPosition.center,
          fontSize: 48,
          opacity: 0.2,
        ),
      );
      writer.beginPage(width: 595, height: 842);
      final bytes = writer.finish();
      final text = latin1.decode(bytes);

      expect(text, contains('CONFIDENTIAL'));
      expect(text, contains('Td')); // text position (not rotated)
    });

    // =========================================================================
    // 26. Inject raw content
    // =========================================================================
    test('injectRawContent writes operators verbatim', () {
      final writer = PdfExportWriter(enableCompression: false);
      writer.beginPage(width: 200, height: 200);
      writer.injectRawContent('1 0 0 rg\n10 10 50 50 re\nf');
      final bytes = writer.finish();
      final text = latin1.decode(bytes);

      expect(text, contains('1 0 0 rg'));
      expect(text, contains('10 10 50 50 re'));
      expect(text, contains('f'));
    });

    // =========================================================================
    // 27. Hyperlinks — URI annotation
    // =========================================================================
    test('generates URI link annotations', () {
      final writer = PdfExportWriter(enableCompression: false);
      writer.beginPage(width: 200, height: 200);
      writer.addUriLink(
        const Rect.fromLTWH(10, 10, 100, 20),
        'https://example.com',
      );
      final bytes = writer.finish();
      final text = latin1.decode(bytes);

      expect(text, contains('/Subtype /Link'));
      expect(text, contains('/S /URI'));
      expect(text, contains('https://example.com'));
      expect(text, contains('/Border [0 0 0]'));
      expect(text, contains('/Annots'));
    });

    // =========================================================================
    // 28. Hyperlinks — internal page link
    // =========================================================================
    test('generates internal page link annotations', () {
      final writer = PdfExportWriter(enableCompression: false);
      writer.beginPage(width: 200, height: 200);
      writer.addPageLink(const Rect.fromLTWH(10, 10, 100, 20), 1);
      writer.beginPage(width: 200, height: 200);
      final bytes = writer.finish();
      final text = latin1.decode(bytes);

      expect(text, contains('/Subtype /Link'));
      expect(text, contains('/Dest'));
      expect(text, contains('/Fit'));
      // %%PAGEDEST_1%% should have been resolved to an actual object reference.
      expect(text, isNot(contains('%%PAGEDEST_')));
    });

    // =========================================================================
    // 29. Page labels — decimal
    // =========================================================================
    test('generates page labels with decimal numbering', () {
      final writer = PdfExportWriter(enableCompression: false);
      writer.beginPage(width: 200, height: 200);
      writer.beginPage(width: 200, height: 200);
      writer.setPageLabels([
        const PdfPageLabel(startPage: 0, style: PageLabelStyle.decimal),
      ]);
      final bytes = writer.finish();
      final text = latin1.decode(bytes);

      expect(text, contains('/PageLabels'));
      expect(text, contains('/Nums'));
      expect(text, contains('/S /D'));
    });

    // =========================================================================
    // 30. Page labels — Roman + prefix
    // =========================================================================
    test('generates page labels with Roman numerals and prefix', () {
      final writer = PdfExportWriter(enableCompression: false);
      writer.beginPage(width: 200, height: 200);
      writer.beginPage(width: 200, height: 200);
      writer.beginPage(width: 200, height: 200);
      writer.setPageLabels([
        const PdfPageLabel(
          startPage: 0,
          style: PageLabelStyle.lowerRoman,
          prefix: 'Intro-',
        ),
        const PdfPageLabel(
          startPage: 2,
          style: PageLabelStyle.decimal,
          startNumber: 1,
        ),
      ]);
      final bytes = writer.finish();
      final text = latin1.decode(bytes);

      expect(text, contains('/S /r')); // lowercase roman
      expect(text, contains('/P (Intro-)')); // prefix
      expect(text, contains('/S /D')); // decimal for later pages
    });

    // =========================================================================
    // 31. AcroForm — Text Field
    // =========================================================================
    test('generates AcroForm text field', () {
      final writer = PdfExportWriter(enableCompression: false);
      writer.beginPage(width: 200, height: 200);
      writer.addTextField(
        const PdfTextField(
          name: 'FirstName',
          rect: Rect.fromLTWH(10, 10, 100, 20),
          defaultValue: 'John Doe',
        ),
      );
      final bytes = writer.finish();
      final text = latin1.decode(bytes);

      expect(text, contains('/AcroForm'));
      expect(text, contains('/FT /Tx')); // text field type
      expect(text, contains('/T (FirstName)'));
      expect(text, contains('/V (John Doe)'));
    });

    // =========================================================================
    // 32. AcroForm — Checkbox
    // =========================================================================
    test('generates AcroForm checkbox field', () {
      final writer = PdfExportWriter(enableCompression: false);
      writer.beginPage(width: 200, height: 200);
      writer.addCheckbox(
        const PdfCheckboxField(
          name: 'Subscribe',
          rect: Rect.fromLTWH(10, 10, 20, 20),
          defaultChecked: true,
        ),
      );
      final bytes = writer.finish();
      final text = latin1.decode(bytes);

      expect(text, contains('/AcroForm'));
      expect(text, contains('/FT /Btn')); // button/checkbox type
      expect(text, contains('/T (Subscribe)'));
      expect(text, contains('/V /Yes')); // checked state
      expect(text, contains('/AS /Yes')); // appearance state
    });

    // =========================================================================
    // 33. AcroForm — Dropdown
    // =========================================================================
    test('generates AcroForm dropdown field', () {
      final writer = PdfExportWriter(enableCompression: false);
      writer.beginPage(width: 200, height: 200);
      writer.addDropdown(
        const PdfDropdownField(
          name: 'Country',
          rect: Rect.fromLTWH(10, 10, 100, 20),
          options: ['USA', 'Canada', 'Mexico'],
          defaultValue: 'Canada',
        ),
      );
      final bytes = writer.finish();
      final text = latin1.decode(bytes);

      expect(text, contains('/AcroForm'));
      expect(text, contains('/FT /Ch')); // choice/dropdown type
      expect(text, contains('/T (Country)'));
      expect(text, contains('/Opt [(USA) (Canada) (Mexico)]'));
      expect(text, contains('/V (Canada)'));
    });

    // =========================================================================
    // 34. Redaction
    // =========================================================================
    test('generates redaction annotations', () {
      final writer = PdfExportWriter(enableCompression: false);
      writer.beginPage(width: 200, height: 200);
      writer.addRedaction(
        const PdfRedaction(
          rect: Rect.fromLTWH(10, 10, 100, 20),
          overlayColor: Color(0xFFFF0000), // Red
          replacementText: 'REDACTED',
        ),
      );
      final bytes = writer.finish();
      final text = latin1.decode(bytes);

      expect(text, contains('/Subtype /Redact'));
      expect(text, contains('/IC [1 0 0]')); // Red color
      expect(text, contains('/OverlayText (REDACTED)'));
    });

    // =========================================================================
    // 35. PDF/A-1b Conformance
    // =========================================================================
    test('generates PDF/A-1b metadata and OutputIntents when enabled', () {
      final writer = PdfExportWriter(enableCompression: false);
      writer.pdfAConformance = true;
      writer.beginPage(width: 200, height: 200);
      final bytes = writer.finish();
      final text = latin1.decode(bytes);

      // XMP Metadata
      expect(text, contains('/Type /Metadata'));
      expect(text, contains('<pdfaid:part>1</pdfaid:part>'));
      expect(text, contains('<pdfaid:conformance>B</pdfaid:conformance>'));

      // Output Intents
      expect(text, contains('/Type /OutputIntent'));
      expect(text, contains('/S /GTS_PDFA1'));

      // MarkInfo
      expect(text, contains('/MarkInfo << /Marked true >>'));
    });
  });
}
