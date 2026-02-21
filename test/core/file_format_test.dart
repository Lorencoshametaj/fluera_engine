import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/formats/format_registry.dart';
import 'package:nebula_engine/src/core/formats/format_parser.dart';
import 'package:nebula_engine/src/core/formats/batch_export_pipeline.dart';
import 'package:nebula_engine/src/core/formats/format_converter.dart';

void main() {
  // ===========================================================================
  // FORMAT REGISTRY
  // ===========================================================================

  group('FormatRegistry', () {
    test('withDefaults has 10 formats', () {
      final registry = FormatRegistry.withDefaults();
      expect(registry.count, 10);
    });

    test('lookup by ID', () {
      final registry = FormatRegistry.withDefaults();
      final png = registry.byId('png');
      expect(png, isNotNull);
      expect(png!.name, 'PNG');
    });

    test('lookup by extension', () {
      final registry = FormatRegistry.withDefaults();
      expect(registry.byExtension('.jpg')?.id, 'jpg');
      expect(registry.byExtension('jpeg')?.id, 'jpg');
      expect(registry.byExtension('.PNG')?.id, 'png');
    });

    test('lookup by MIME type', () {
      final registry = FormatRegistry.withDefaults();
      expect(registry.byMimeType('image/png')?.id, 'png');
    });

    test('filter by capability', () {
      final registry = FormatRegistry.withDefaults();
      final exportable = registry.withCapability(FormatCapability.export_);
      expect(exportable.length, greaterThan(3));
    });

    test('filter by category', () {
      final registry = FormatRegistry.withDefaults();
      final design = registry.inCategory(FormatCategory.design);
      expect(design.length, 3); // psd, figma, sketch
    });

    test('register custom format', () {
      final registry = FormatRegistry();
      registry.register(
        const FileFormatDescriptor(
          id: 'custom',
          name: 'Custom',
          extensions: ['.cst'],
        ),
      );
      expect(registry.byId('custom'), isNotNull);
    });

    test('unregister format', () {
      final registry = FormatRegistry.withDefaults();
      registry.unregister('png');
      expect(registry.byId('png'), isNull);
    });

    test('format has capability', () {
      final registry = FormatRegistry.withDefaults();
      final tiff = registry.byId('tiff')!;
      expect(tiff.hasCapability(FormatCapability.cmyk), isTrue);
      expect(tiff.hasCapability(FormatCapability.animation), isFalse);
    });
  });

  // ===========================================================================
  // FORMAT PARSER
  // ===========================================================================

  group('FormatParser', () {
    test('ParsedDocument layer count (flat)', () {
      const doc = ParsedDocument(
        name: 'test',
        width: 100,
        height: 100,
        layers: [
          ParsedLayer(id: 'l1', name: 'Layer 1'),
          ParsedLayer(id: 'l2', name: 'Layer 2'),
        ],
      );
      expect(doc.totalLayers, 2);
    });

    test('ParsedDocument layer count (nested)', () {
      const doc = ParsedDocument(
        name: 'test',
        layers: [
          ParsedLayer(
            id: 'g1',
            type: ParsedLayerType.group,
            children: [ParsedLayer(id: 'c1'), ParsedLayer(id: 'c2')],
          ),
        ],
      );
      expect(doc.totalLayers, 3); // group + 2 children
    });

    test('ImportResult success', () {
      const doc = ParsedDocument(name: 'ok', layers: [ParsedLayer(id: 'l')]);
      final result = ImportResult.ok(doc, durationMs: 50);
      expect(result.success, isTrue);
      expect(result.document, isNotNull);
    });

    test('ImportResult failure', () {
      final result = ImportResult.fail('Bad file');
      expect(result.success, isFalse);
      expect(result.errors, contains('Bad file'));
    });

    test('ParsedLayer serialization', () {
      const layer = ParsedLayer(
        id: 'l1',
        name: 'Test',
        type: ParsedLayerType.text,
        x: 10,
        y: 20,
        width: 100,
        height: 50,
        opacity: 0.8,
      );
      final json = layer.toJson();
      expect(json['type'], 'text');
      expect(json['opacity'], 0.8);
    });
  });

  // ===========================================================================
  // BATCH EXPORT PIPELINE
  // ===========================================================================

  group('BatchExportPipeline', () {
    test('execute exports all targets', () {
      final pipeline = BatchExportPipeline();
      pipeline.addTarget(const ExportTarget(formatId: 'png'));
      pipeline.addTarget(const ExportTarget(formatId: 'webp', quality: 80));

      final results = pipeline.execute(
        exporter:
            (target) => ExportResult(
              target: target,
              success: true,
              fileSizeBytes: 1024,
              durationMs: 10,
            ),
      );

      expect(results.length, 2);
      expect(pipeline.successCount, 2);
      expect(pipeline.totalFileSizeBytes, 2048);
    });

    test('handles export failure', () {
      final pipeline = BatchExportPipeline();
      pipeline.addTarget(const ExportTarget(formatId: 'broken'));

      pipeline.execute(exporter: (target) => throw Exception('Export failed'));

      expect(pipeline.failCount, 1);
    });

    test('progress callback', () {
      final pipeline = BatchExportPipeline();
      pipeline.addTarget(const ExportTarget(formatId: 'a'));
      pipeline.addTarget(const ExportTarget(formatId: 'b'));

      final progressValues = <double>[];
      pipeline.execute(
        exporter: (t) => ExportResult(target: t, success: true),
        onProgress: (progress, _) => progressValues.add(progress),
      );

      expect(progressValues.length, 3); // 0.0, 0.5, 1.0
      expect(progressValues.last, 1.0);
    });

    test('summary report', () {
      final pipeline = BatchExportPipeline();
      pipeline.addTarget(const ExportTarget(formatId: 'png'));
      pipeline.execute(
        exporter:
            (t) => ExportResult(target: t, success: true, fileSizeBytes: 500),
      );

      final summary = pipeline.summary();
      expect(summary['totalTargets'], 1);
      expect(summary['succeeded'], 1);
    });

    test('remove target', () {
      final pipeline = BatchExportPipeline();
      pipeline.addTarget(const ExportTarget(formatId: 'png'));
      pipeline.addTarget(const ExportTarget(formatId: 'jpg'));
      pipeline.removeTarget('png');
      expect(pipeline.targets.length, 1);
    });
  });

  // ===========================================================================
  // FORMAT CONVERTER
  // ===========================================================================

  group('FormatConverter', () {
    test('withDefaults has conversion paths', () {
      final converter = FormatConverter.withDefaults();
      expect(converter.canConvert('png', 'webp'), isTrue);
      expect(converter.canConvert('psd', 'png'), isTrue);
    });

    test('convert basic format', () {
      final converter = FormatConverter.withDefaults();
      const doc = ParsedDocument(
        name: 'test',
        width: 100,
        height: 100,
        sourceFormat: 'png',
        layers: [ParsedLayer(id: 'l1')],
      );

      final result = converter.convert(doc, targetFormat: 'webp');
      expect(result.success, isTrue);
      expect(result.output?.sourceFormat, 'webp');
    });

    test('unsupported conversion fails', () {
      final converter = FormatConverter();
      const doc = ParsedDocument(name: 'test', sourceFormat: 'xyz');

      final result = converter.convert(doc, targetFormat: 'abc');
      expect(result.success, isFalse);
      expect(result.error, contains('No conversion path'));
    });

    test('scaling applies to dimensions', () {
      final converter = FormatConverter.withDefaults();
      const doc = ParsedDocument(
        name: 'test',
        width: 100,
        height: 200,
        sourceFormat: 'png',
        layers: [ParsedLayer(id: 'l1')],
      );

      final result = converter.convert(
        doc,
        targetFormat: 'jpg',
        options: const ConversionOptions(scale: 2.0),
      );
      expect(result.output!.width, 200);
      expect(result.output!.height, 400);
    });

    test('flatten layers', () {
      final converter = FormatConverter.withDefaults();
      const doc = ParsedDocument(
        name: 'test',
        width: 100,
        height: 100,
        sourceFormat: 'psd',
        layers: [ParsedLayer(id: 'l1'), ParsedLayer(id: 'l2')],
      );

      final result = converter.convert(
        doc,
        targetFormat: 'png',
        options: const ConversionOptions(flattenLayers: true),
      );
      expect(result.output!.layers.length, 1);
      expect(result.warnings, isNotEmpty);
    });

    test('targetFormatsFor returns valid set', () {
      final converter = FormatConverter.withDefaults();
      final targets = converter.targetFormatsFor('svg');
      expect(targets, contains('png'));
      expect(targets, contains('pdf'));
    });

    test('register custom path', () {
      final converter = FormatConverter();
      converter.registerPath('custom', 'png');
      expect(converter.canConvert('custom', 'png'), isTrue);
    });
  });
}
