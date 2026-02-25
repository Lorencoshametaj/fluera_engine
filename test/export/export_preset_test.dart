import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/export/export_preset.dart';

void main() {
  // ===========================================================================
  // ExportPreset — Static presets
  // ===========================================================================

  group('ExportPreset static presets', () {
    test('allPresets contains all categories', () {
      expect(ExportPreset.allPresets, isNotEmpty);
      expect(ExportPreset.paperPresets, isNotEmpty);
      expect(ExportPreset.socialPresets, isNotEmpty);
      expect(ExportPreset.specialPresets, isNotEmpty);
    });

    test('A4 portrait has correct dimensions', () {
      final a4 = ExportPreset.a4Portrait;
      expect(a4.id, 'a4_portrait');
      expect(a4.fixedSize, const Size(595, 842));
      expect(a4.category, ExportPresetCategory.paper);
    });

    test('Instagram square is 1:1', () {
      final ig = ExportPreset.instagramSquare;
      expect(ig.aspectRatio, 1.0);
      expect(ig.fixedSize, const Size(1080, 1080));
    });

    test('findById returns correct preset', () {
      final a4 = ExportPreset.findById('a4_portrait');
      expect(a4, isNotNull);
      expect(a4!.name, 'A4 Portrait');
    });

    test('findById returns null for unknown id', () {
      expect(ExportPreset.findById('nonexistent'), isNull);
    });
  });

  // ===========================================================================
  // ExportPreset — getSizeAtDpi
  // ===========================================================================

  group('getSizeAtDpi', () {
    test('returns fixed size scaled by DPI', () {
      final a4 = ExportPreset.a4Portrait;
      final size72 = a4.getSizeAtDpi(72);
      final size300 = a4.getSizeAtDpi(300);

      // At 72 DPI, should be the base size
      expect(size72.width, closeTo(595, 1));
      expect(size72.height, closeTo(842, 1));

      // At 300 DPI, should be ~4.17x larger
      expect(size300.width, greaterThan(size72.width));
      expect(size300.height, greaterThan(size72.height));
    });

    test('returns Size.zero for custom preset without reference', () {
      final custom = ExportPreset.custom;
      final size = custom.getSizeAtDpi(72);
      expect(size, Size.zero);
    });
  });

  // ===========================================================================
  // ExportPreset — Multi-page
  // ===========================================================================

  group('multi-page', () {
    test('requiresMultiPage for large area', () {
      final a4 = ExportPreset.a4Portrait;
      final largeArea = const Rect.fromLTWH(0, 0, 5000, 5000);
      expect(a4.requiresMultiPage(largeArea, 300), true);
    });

    test('calculatePageGrid returns valid grid', () {
      final a4 = ExportPreset.a4Portrait;
      final area = const Rect.fromLTWH(0, 0, 2000, 3000);
      final (cols, rows) = a4.calculatePageGrid(area, 300);
      expect(cols, greaterThanOrEqualTo(1));
      expect(rows, greaterThanOrEqualTo(1));
    });

    test('calculatePageGrid returns (1,1) for small area', () {
      final a4 = ExportPreset.a4Portrait;
      final smallArea = const Rect.fromLTWH(0, 0, 100, 100);
      final (cols, rows) = a4.calculatePageGrid(smallArea, 72);
      expect(cols, 1);
      expect(rows, 1);
    });
  });

  // ===========================================================================
  // ExportConfig
  // ===========================================================================

  group('ExportConfig', () {
    test('default values', () {
      const config = ExportConfig();
      expect(config.format, ExportFormat.png);
      expect(config.quality, ExportQuality.standard);
      expect(config.background, ExportBackground.transparent);
      expect(config.multiPage, false);
    });

    test('copyWith preserves unchanged fields', () {
      const config = ExportConfig();
      final updated = config.copyWith(format: ExportFormat.jpeg);

      expect(updated.format, ExportFormat.jpeg);
      expect(updated.quality, ExportQuality.standard); // unchanged
    });

    test('finalSizePixels scales with DPI', () {
      final config = ExportConfig(
        exportArea: const Rect.fromLTWH(0, 0, 100, 200),
        quality: ExportQuality.high, // 300 DPI
      );
      final size = config.finalSizePixels;
      // 100 * (300/72) ≈ 416.7
      expect(size.width, closeTo(416.7, 1));
    });

    test('exceedsImageLimit is false for small areas', () {
      const config = ExportConfig(exportArea: Rect.fromLTWH(0, 0, 500, 500));
      expect(config.exceedsImageLimit, false);
    });
  });

  // ===========================================================================
  // ExportQuality
  // ===========================================================================

  group('ExportQuality', () {
    test('has correct DPI values', () {
      expect(ExportQuality.screen.dpi, 72);
      expect(ExportQuality.standard.dpi, 150);
      expect(ExportQuality.high.dpi, 300);
    });
  });

  // ===========================================================================
  // ExportPageFormat
  // ===========================================================================

  group('ExportPageFormat', () {
    test('sizeInPoints has expected values', () {
      expect(ExportPageFormat.a4Portrait.sizeInPoints, const Size(595, 842));
      expect(
        ExportPageFormat.letterPortrait.sizeInPoints,
        const Size(612, 792),
      );
    });

    test('label returns readable string', () {
      expect(ExportPageFormat.a4Portrait.label, 'A4');
      expect(ExportPageFormat.custom.label, 'Custom');
    });

    test('aspectRatio is positive', () {
      for (final fmt in ExportPageFormat.values) {
        expect(fmt.aspectRatio, greaterThan(0));
      }
    });
  });
}
