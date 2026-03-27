import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/export/fluera_file_format.dart';

void main() {
  // ───────────────────────────────────────────────────────────────────────────
  // FlueraFileWriter + FlueraFileReader — write → read roundtrip
  // ───────────────────────────────────────────────────────────────────────────

  group('FlueraFileFormat roundtrip', () {
    test('write and read metadata section', () {
      final writer = FlueraFileWriter();
      final metadata = {'name': 'Test Design', 'version': 1};
      writer.addMetadata(metadata);

      final bytes = writer.build();
      final reader = FlueraFileReader(bytes);

      expect(reader.version, 4);
      expect(reader.sectionCount, 1);

      final readMeta = reader.readMetadata();
      expect(readMeta, isNotNull);
      expect(readMeta!['name'], 'Test Design');
      expect(readMeta['version'], 1);
    });

    test('write and read multiple pages', () {
      final writer = FlueraFileWriter();
      writer.addMetadata({'name': 'Multi Page'});
      writer.addPageDirectory([
        {'id': 'page_0', 'name': 'Home'},
        {'id': 'page_1', 'name': 'Icons'},
      ]);
      writer.addPageData(0, {'layers': []});
      writer.addPageData(1, {
        'layers': [
          {'type': 'layer'},
        ],
      });

      final bytes = writer.build();
      final reader = FlueraFileReader(bytes);

      expect(reader.sectionCount, 4);
      expect(reader.pageIndices, [0, 1]);

      final page0 = reader.readPageData(0);
      expect(page0, isNotNull);
      expect(page0!['layers'], isEmpty);

      final page1 = reader.readPageData(1);
      expect(page1, isNotNull);
      expect((page1!['layers'] as List).length, 1);
    });

    test('lazy loading: only requested sections are read', () {
      final writer = FlueraFileWriter();
      writer.addMetadata({'name': 'Lazy Test'});
      writer.addPageData(0, {'layers': []});
      writer.addPageData(1, {'layers': []});
      writer.addPageData(2, {'layers': []});

      final bytes = writer.build();
      final reader = FlueraFileReader(bytes);

      // Only read page 2 — pages 0 and 1 are not loaded
      final page2 = reader.readPageData(2);
      expect(page2, isNotNull);

      // Non-existent page returns null
      expect(reader.readPageData(99), isNull);
    });

    test('thumbnail roundtrip', () {
      final writer = FlueraFileWriter();
      final thumb = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0, 1, 2, 3]);
      writer.addThumbnail(thumb);

      final bytes = writer.build();
      final reader = FlueraFileReader(bytes);

      final readThumb = reader.readThumbnail();
      expect(readThumb, isNotNull);
      expect(readThumb, thumb);
    });

    test('asset blob roundtrip', () {
      final writer = FlueraFileWriter();
      final assetData = Uint8List.fromList(List.generate(256, (i) => i % 256));
      writer.addAssetBlob(42, assetData);

      final bytes = writer.build();
      final reader = FlueraFileReader(bytes);

      final readAsset = reader.readAssetBlob(42);
      expect(readAsset, isNotNull);
      expect(readAsset!.length, 256);
      expect(readAsset, assetData);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // CRC32 integrity
  // ───────────────────────────────────────────────────────────────────────────

  group('CRC32 integrity', () {
    test('detects corruption in section data', () {
      final writer = FlueraFileWriter();
      writer.addMetadata({'key': 'value'});
      final bytes = writer.build();

      // Corrupt one byte in the section data area (after 32-byte header)
      bytes[40] = bytes[40] ^ 0xFF;

      final reader = FlueraFileReader(bytes);
      expect(() => reader.readMetadata(), throwsA(isA<FormatException>()));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Header validation
  // ───────────────────────────────────────────────────────────────────────────

  group('FlueraFileHeader', () {
    test('isFlueraFile detects valid magic', () {
      final writer = FlueraFileWriter();
      writer.addMetadata({});
      final bytes = writer.build();
      expect(FlueraFileHeader.isFlueraFile(bytes), isTrue);
    });

    test('isFlueraFile rejects invalid magic', () {
      final bytes = Uint8List.fromList([0, 0, 0, 0]);
      expect(FlueraFileHeader.isFlueraFile(bytes), isFalse);
    });

    test('rejects too-small file', () {
      expect(
        () => FlueraFileHeader.decode(Uint8List(10)),
        throwsA(isA<FormatException>()),
      );
    });

    test('isValid static method works', () {
      final writer = FlueraFileWriter();
      writer.addMetadata({});
      expect(FlueraFileReader.isValid(writer.build()), isTrue);
      expect(FlueraFileReader.isValid(Uint8List(5)), isFalse);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Incremental save
  // ───────────────────────────────────────────────────────────────────────────

  group('Incremental save', () {
    test('only dirty sections are replaced', () {
      // Build original file with 2 pages
      final writer = FlueraFileWriter();
      writer.addMetadata({'version': 1});
      writer.addPageData(0, {'layers': []});
      writer.addPageData(1, {
        'layers': [
          {'old': true},
        ],
      });
      final original = writer.build();

      // Incrementally save with only page 1 dirty
      final updated = FlueraFileWriter.incrementalSave(
        existingBytes: original,
        dirtySections: [
          PreparedSection(
            type: SectionType.pageData,
            data: Uint8List.fromList(
              utf8.encode(
                jsonEncode({
                  'layers': [
                    {'new': true},
                  ],
                }),
              ),
            ),
            tag: 1,
          ),
        ],
      );

      final reader = FlueraFileReader(updated);

      // Metadata should be unchanged
      final meta = reader.readMetadata();
      expect(meta!['version'], 1);

      // Page 0 should be unchanged
      final page0 = reader.readPageData(0);
      expect(page0!['layers'], isEmpty);

      // Page 1 should be updated
      final page1 = reader.readPageData(1);
      expect((page1!['layers'] as List).first['new'], isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Stats
  // ───────────────────────────────────────────────────────────────────────────

  group('File stats', () {
    test('stats returns section breakdown', () {
      final writer = FlueraFileWriter();
      writer.addMetadata({'name': 'Stats Test'});
      writer.addPageData(0, {'layers': []});
      writer.addPageData(1, {'layers': []});

      final bytes = writer.build();
      final reader = FlueraFileReader(bytes);
      final stats = reader.stats();

      expect(stats['sectionCount'], 3);
      expect(stats['version'], 4);
      expect((stats['sectionsByType'] as Map)['metadata'], 1);
      expect((stats['sectionsByType'] as Map)['pageData'], 2);
    });
  });
}
