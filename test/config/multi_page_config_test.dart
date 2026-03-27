import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/config/multi_page_config.dart';
import 'package:fluera_engine/src/export/export_preset.dart';

void main() {
  late MultiPageConfig config;

  setUp(() {
    config = MultiPageConfig(pageFormat: ExportPageFormat.a4Portrait);
  });

  // ===========================================================================
  // Default state
  // ===========================================================================

  group('MultiPageConfig - defaults', () {
    test('created with A4 format', () {
      expect(config.pageFormat, ExportPageFormat.a4Portrait);
    });

    test('getPageSizeInPoints returns valid dimensions', () {
      final size = config.getPageSizeInPoints();
      expect(size.width, greaterThan(0));
      expect(size.height, greaterThan(0));
    });

    test('getPageSizeInPixels returns valid dimensions', () {
      final size = config.getPageSizeInPixels();
      expect(size.width, greaterThan(0));
      expect(size.height, greaterThan(0));
    });
  });

  // ===========================================================================
  // copyWith
  // ===========================================================================

  group('MultiPageConfig - copyWith', () {
    test('copies with changed format', () {
      final copy = config.copyWith(pageFormat: ExportPageFormat.letterPortrait);
      expect(copy.pageFormat, ExportPageFormat.letterPortrait);
    });

    test('copies with changed maxPages', () {
      final copy = config.copyWith(maxPages: 10);
      expect(copy.maxPages, 10);
    });

    test('unchanged fields remain the same', () {
      final copy = config.copyWith(maxPages: 5);
      expect(copy.pageFormat, config.pageFormat);
    });
  });

  // ===========================================================================
  // addPage
  // ===========================================================================

  group('MultiPageConfig - addPage', () {
    test('adds a page within canvas area', () {
      final canvasArea = const Rect.fromLTWH(0, 0, 2000, 3000);
      final updated = config.addPage(canvasArea);
      expect(
        updated.individualPageBounds.length,
        greaterThan(config.individualPageBounds.length),
      );
    });
  });

  // ===========================================================================
  // addPageAtCenter
  // ===========================================================================

  group('MultiPageConfig - addPageAtCenter', () {
    test('adds a page centered at offset', () {
      final updated = config.addPageAtCenter(const Offset(500, 500));
      expect(
        updated.individualPageBounds.length,
        greaterThan(config.individualPageBounds.length),
      );
    });
  });

  // ===========================================================================
  // removeSelectedPage
  // ===========================================================================

  group('MultiPageConfig - removeSelectedPage', () {
    test('removes selected page when multiple exist', () {
      // Add 2 pages first
      var c = config.addPage(const Rect.fromLTWH(0, 0, 2000, 3000));
      c = c.addPage(const Rect.fromLTWH(0, 0, 2000, 3000));
      final count = c.individualPageBounds.length;
      final removed = c.removeSelectedPage();
      expect(removed.individualPageBounds.length, count - 1);
    });
  });

  // ===========================================================================
  // movePage
  // ===========================================================================

  group('MultiPageConfig - movePage', () {
    test('moves page by delta', () {
      var c = config.addPage(const Rect.fromLTWH(0, 0, 2000, 3000));
      if (c.individualPageBounds.isNotEmpty) {
        final originalLeft = c.individualPageBounds.first.left;
        final moved = c.movePage(0, const Offset(100, 50));
        expect(
          moved.individualPageBounds.first.left,
          closeTo(originalLeft + 100, 1),
        );
      }
    });
  });

  // ===========================================================================
  // toJson
  // ===========================================================================

  group('MultiPageConfig - toJson', () {
    test('serializes to JSON map', () {
      final json = config.toJson();
      expect(json, isA<Map<String, dynamic>>());
      expect(json.containsKey('pageFormat'), isTrue);
    });
  });

  // ===========================================================================
  // reorganizeAsGrid
  // ===========================================================================

  group('MultiPageConfig - reorganizeAsGrid', () {
    test('reorganizes pages into grid layout', () {
      var c = config;
      for (int i = 0; i < 4; i++) {
        c = c.addPage(const Rect.fromLTWH(0, 0, 2000, 3000));
      }
      final reorganized = c.reorganizeAsGrid(
        const Rect.fromLTWH(0, 0, 2000, 3000),
        columns: 2,
        spacing: 20,
      );
      expect(
        reorganized.individualPageBounds.length,
        c.individualPageBounds.length,
      );
    });
  });
}
