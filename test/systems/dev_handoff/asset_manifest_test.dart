import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/systems/dev_handoff/asset_manifest.dart';

void main() {
  group('AssetManifest Tests', () {
    test('addEntry and getEntry', () {
      final manifest = AssetManifest();
      final entry = HandoffAssetEntry(
        nodeId: 'node-1',
        name: 'Icon/Home',
        formats: [AssetFormat.svg, AssetFormat.png3x],
        group: 'Icons',
      );

      manifest.addEntry(entry);

      expect(manifest.length, 1);
      expect(manifest.hasEntry('node-1'), isTrue);

      final retrieved = manifest.getEntry('node-1');
      expect(retrieved, isNotNull);
      expect(retrieved!.name, 'Icon/Home');
      expect(retrieved.formats, contains(AssetFormat.svg));
      expect(retrieved.formats, contains(AssetFormat.png3x));
      expect(retrieved.group, 'Icons');

      expect(retrieved.fileNames(), contains('Icon/Home.svg'));
      expect(retrieved.fileNames(), contains('Icon/Home.@3x.png'));
    });

    test('removeEntry', () {
      final manifest = AssetManifest();
      manifest.addEntry(HandoffAssetEntry(nodeId: 'node-1', name: 'AppLogo'));

      expect(manifest.hasEntry('node-1'), isTrue);

      final removed = manifest.removeEntry('node-1');
      expect(removed, isTrue);
      expect(manifest.hasEntry('node-1'), isFalse);
      expect(manifest.length, 0);
    });

    test('grouping and filtering', () {
      final manifest = AssetManifest();
      manifest.addEntry(
        HandoffAssetEntry(
          nodeId: '1',
          name: 'Icon1',
          group: 'Icons',
          formats: [AssetFormat.svg],
        ),
      );
      manifest.addEntry(
        HandoffAssetEntry(
          nodeId: '2',
          name: 'Icon2',
          group: 'Icons',
          formats: [AssetFormat.png2x],
        ),
      );
      manifest.addEntry(
        HandoffAssetEntry(
          nodeId: '3',
          name: 'Illu1',
          group: 'Illustrations',
          formats: [AssetFormat.svg],
        ),
      );
      manifest.addEntry(
        HandoffAssetEntry(
          nodeId: '4',
          name: 'Untethered',
          formats: [AssetFormat.webp],
        ),
      );

      expect(manifest.groups, containsAll(['Icons', 'Illustrations']));

      final icons = manifest.entriesInGroup('Icons');
      expect(icons.length, 2);

      final svgs = manifest.entriesByFormat(AssetFormat.svg);
      expect(svgs.length, 2);
      expect(svgs.map((e) => e.name), containsAll(['Icon1', 'Illu1']));

      final grouped = manifest.groupedEntries();
      expect(
        grouped.keys,
        containsAll(['Icons', 'Illustrations', 'ungrouped']),
      );
      expect(grouped['Icons']!.length, 2);
      expect(grouped['ungrouped']!.length, 1);
    });

    test('serialization roundtrip', () {
      final manifest = AssetManifest();
      manifest.addEntry(
        HandoffAssetEntry(
          nodeId: 'node-A',
          name: 'AssetA',
          formats: [AssetFormat.pdf, AssetFormat.svg],
          description: 'Primary vector asset',
          group: 'Vectors',
        ),
      );

      final json = manifest.toJson();

      final restored = AssetManifest.fromJson(json);
      expect(restored.length, 1);
      final entry = restored.getEntry('node-A');
      expect(entry, isNotNull);
      expect(entry!.name, 'AssetA');
      expect(entry.formats, containsAll([AssetFormat.pdf, AssetFormat.svg]));
      expect(entry.description, 'Primary vector asset');
      expect(entry.group, 'Vectors');
    });
  });
}
