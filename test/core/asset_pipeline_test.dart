import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/assets/asset_dependency_graph.dart';
import 'package:fluera_engine/src/core/assets/asset_handle.dart';
import 'package:fluera_engine/src/core/assets/asset_metadata.dart';
import 'package:fluera_engine/src/core/assets/asset_validator.dart';

void main() {
  // ===========================================================================
  // ASSET METADATA
  // ===========================================================================

  group('AssetMetadata', () {
    test('creates with defaults', () {
      final meta = AssetMetadata();
      expect(meta.tags, isEmpty);
      expect(meta.license, AssetLicense.unknown);
      expect(meta.importedBy, 'system');
      expect(meta.importedAt.isUtc, isTrue);
      expect(meta.description, isNull);
      expect(meta.widthPx, isNull);
    });

    test('creates with all fields', () {
      final meta = AssetMetadata(
        tags: {'icon', 'brand'},
        description: 'Primary logo',
        license: AssetLicense.royaltyFree,
        widthPx: 512,
        heightPx: 512,
        fileSizeBytes: 24000,
        mimeType: 'image/png',
        importedBy: 'user-1',
      );

      expect(meta.tags, {'icon', 'brand'});
      expect(meta.license, AssetLicense.royaltyFree);
      expect(meta.widthPx, 512);
      expect(meta.mimeType, 'image/png');
    });

    test('copyWith preserves unmodified fields', () {
      final original = AssetMetadata(
        tags: {'a'},
        license: AssetLicense.licensed,
        description: 'test',
      );
      final updated = original.copyWith(tags: {'b', 'c'});

      expect(updated.tags, {'b', 'c'});
      expect(updated.license, AssetLicense.licensed);
      expect(updated.description, 'test');
    });

    test('addTags is additive', () {
      final meta = AssetMetadata(tags: {'a'});
      final updated = meta.addTags({'b', 'c'});
      expect(updated.tags, {'a', 'b', 'c'});
    });

    test('removeTags removes specified', () {
      final meta = AssetMetadata(tags: {'a', 'b', 'c'});
      final updated = meta.removeTags({'b'});
      expect(updated.tags, {'a', 'c'});
    });

    test('matchesTags case-insensitive', () {
      final meta = AssetMetadata(tags: {'Icon', 'Brand'});
      expect(meta.matchesTags('icon'), isTrue);
      expect(meta.matchesTags('BRAND'), isTrue);
      expect(meta.matchesTags('logo'), isFalse);
    });

    test('matchesSearch across tags and description', () {
      final meta = AssetMetadata(
        tags: {'ui'},
        description: 'Primary logo asset',
        mimeType: 'image/png',
      );

      expect(meta.matchesSearch('ui'), isTrue);
      expect(meta.matchesSearch('logo'), isTrue);
      expect(meta.matchesSearch('png'), isTrue);
      expect(meta.matchesSearch('font'), isFalse);
    });

    test('toJson/fromJson round-trips', () {
      final original = AssetMetadata(
        tags: {'icon', 'brand'},
        description: 'Logo',
        license: AssetLicense.proprietary,
        widthPx: 256,
        heightPx: 128,
        fileSizeBytes: 5000,
        mimeType: 'image/webp',
        importedBy: 'admin',
        custom: {'project': 'alpha'},
      );

      final json = original.toJson();
      final restored = AssetMetadata.fromJson(json);

      expect(restored.tags, original.tags);
      expect(restored.description, original.description);
      expect(restored.license, original.license);
      expect(restored.widthPx, original.widthPx);
      expect(restored.heightPx, original.heightPx);
      expect(restored.fileSizeBytes, original.fileSizeBytes);
      expect(restored.mimeType, original.mimeType);
      expect(restored.importedBy, original.importedBy);
      expect(restored.custom, original.custom);
    });

    test('fromJson handles unknown license', () {
      final json = {
        'license': 'nonexistent',
        'importedAt': DateTime.utc(2025).toIso8601String(),
      };
      final meta = AssetMetadata.fromJson(json);
      expect(meta.license, AssetLicense.unknown);
    });
  });

  // ===========================================================================
  // ASSET VERSION
  // ===========================================================================

  group('AssetVersion', () {
    test('toJson/fromJson round-trips', () {
      final v = AssetVersion(
        version: 3,
        contentHash: 'sha256:abc123',
        createdAt: DateTime.utc(2025, 6, 1),
        comment: 'Updated colors',
        createdBy: 'designer-1',
      );

      final json = v.toJson();
      final restored = AssetVersion.fromJson(json);

      expect(restored.version, 3);
      expect(restored.contentHash, 'sha256:abc123');
      expect(restored.createdAt, DateTime.utc(2025, 6, 1));
      expect(restored.comment, 'Updated colors');
      expect(restored.createdBy, 'designer-1');
    });

    test('fromJson handles missing optional fields', () {
      final json = {
        'version': 1,
        'contentHash': 'sha256:xyz',
        'createdAt': DateTime.utc(2025).toIso8601String(),
      };
      final v = AssetVersion.fromJson(json);
      expect(v.comment, isNull);
      expect(v.createdBy, 'system');
    });
  });

  // ===========================================================================
  // ASSET ENTRY (metadata/version extension)
  // ===========================================================================

  group('AssetEntry metadata extension', () {
    test('entry has nullable metadata', () {
      final entry = AssetEntry(
        handle: const AssetHandle(
          id: 'abc',
          type: AssetType.image,
          sourcePath: '/img.png',
        ),
      );
      expect(entry.metadata, isNull);
      expect(entry.versions, isEmpty);
    });

    test('entry with metadata and versions', () {
      final entry = AssetEntry(
        handle: const AssetHandle(
          id: 'abc',
          type: AssetType.image,
          sourcePath: '/img.png',
        ),
        metadata: AssetMetadata(tags: {'logo'}),
        versions: [
          AssetVersion(
            version: 1,
            contentHash: 'sha256:v1',
            createdAt: DateTime.utc(2025),
          ),
        ],
      );

      expect(entry.metadata!.tags, {'logo'});
      expect(entry.versions.length, 1);
    });

    test('toJson includes metadata and versions', () {
      final entry = AssetEntry(
        handle: const AssetHandle(
          id: 'abc',
          type: AssetType.image,
          sourcePath: '/img.png',
        ),
        metadata: AssetMetadata(tags: {'ui'}),
        versions: [
          AssetVersion(
            version: 1,
            contentHash: 'sha256:v1',
            createdAt: DateTime.utc(2025),
          ),
        ],
      );

      final json = entry.toJson();
      expect(json.containsKey('metadata'), isTrue);
      expect(json.containsKey('versions'), isTrue);
      expect((json['metadata'] as Map)['tags'], ['ui']);
    });

    test('toJson omits metadata and versions when empty', () {
      final entry = AssetEntry(
        handle: const AssetHandle(
          id: 'abc',
          type: AssetType.image,
          sourcePath: '/img.png',
        ),
      );

      final json = entry.toJson();
      expect(json.containsKey('metadata'), isFalse);
      expect(json.containsKey('versions'), isFalse);
    });
  });

  // ===========================================================================
  // ASSET VALIDATOR
  // ===========================================================================

  group('AssetValidator', () {
    test('validates nonexistent file as error', () {
      final validator = AssetValidator();
      final result = validator.validate(
        '/nonexistent/path/image.png',
        AssetType.image,
      );

      expect(result.isValid, isFalse);
      expect(result.hasErrors, isTrue);
      expect(result.issues.first.code, 'file_not_found');
    });

    test('detects MIME type from extension', () {
      // Skip file existence check for MIME detection test
      final validator = AssetValidator(
        config: const AssetValidationConfig(validateFileExists: false),
      );
      final result = validator.validate('/path/to/image.png', AssetType.image);

      expect(result.detectedMimeType, 'image/png');
    });

    test('rejects unsupported format', () {
      final validator = AssetValidator(
        config: const AssetValidationConfig(
          validateFileExists: false,
          allowedMimeTypes: {
            AssetType.image: {'image/png'},
          },
        ),
      );

      final result = validator.validate('/path/to/image.bmp', AssetType.image);
      expect(result.isValid, isFalse);
      expect(result.issues.any((i) => i.code == 'unsupported_format'), isTrue);
    });

    test('accepts allowed format', () {
      final validator = AssetValidator(
        config: const AssetValidationConfig(
          validateFileExists: false,
          allowedMimeTypes: {
            AssetType.image: {'image/png', 'image/jpeg'},
          },
        ),
      );

      final result = validator.validate('/path/to/photo.jpg', AssetType.image);
      expect(result.isValid, isTrue);
    });

    test('warns on unknown extension', () {
      final validator = AssetValidator(
        config: const AssetValidationConfig(validateFileExists: false),
      );
      final result = validator.validate('/path/to/file.xyz', AssetType.image);
      expect(result.issues.any((i) => i.code == 'unknown_format'), isTrue);
    });

    test('license_required info when configured', () {
      final validator = AssetValidator(
        config: const AssetValidationConfig(
          validateFileExists: false,
          requireLicenseTag: true,
        ),
      );
      final result = validator.validate('/img.png', AssetType.image);
      expect(result.issues.any((i) => i.code == 'license_required'), isTrue);
    });

    test('validateBatch processes multiple files', () {
      final validator = AssetValidator(
        config: const AssetValidationConfig(validateFileExists: false),
      );

      final results = validator.validateBatch({
        '/a.png': AssetType.image,
        '/b.ttf': AssetType.font,
      });

      expect(results.length, 2);
      expect(results['/a.png']!.detectedMimeType, 'image/png');
      expect(results['/b.ttf']!.detectedMimeType, 'font/ttf');
    });

    test('permissive config accepts most things', () {
      final validator = AssetValidator(
        config: AssetValidationConfig.permissive,
      );
      // Cannot test actual file, but config values are relaxed
      expect(
        AssetValidationConfig.permissive.maxFileSizeBytes,
        500 * 1024 * 1024,
      );
    });

    test('strict config has tight limits', () {
      expect(AssetValidationConfig.strict.maxFileSizeBytes, 10 * 1024 * 1024);
      expect(AssetValidationConfig.strict.requireLicenseTag, isTrue);
      expect(AssetValidationConfig.strict.maxImageDimension, 4096);
    });
  });

  // ===========================================================================
  // ASSET DEPENDENCY GRAPH
  // ===========================================================================

  group('AssetDependencyGraph', () {
    late AssetDependencyGraph graph;

    setUp(() {
      graph = AssetDependencyGraph();
    });

    tearDown(() {
      graph.dispose();
    });

    test('link creates bidirectional edge', () {
      graph.link('node-1', 'asset-a');

      expect(graph.nodesUsing('asset-a'), {'node-1'});
      expect(graph.assetsUsedBy('node-1'), {'asset-a'});
    });

    test('link is idempotent', () {
      graph.link('node-1', 'asset-a');
      graph.link('node-1', 'asset-a');

      expect(graph.linkCount, 1);
    });

    test('multiple links per node', () {
      graph.link('node-1', 'asset-a');
      graph.link('node-1', 'asset-b');

      expect(graph.assetsUsedBy('node-1'), {'asset-a', 'asset-b'});
      expect(graph.linkCount, 2);
    });

    test('multiple nodes per asset', () {
      graph.link('node-1', 'asset-a');
      graph.link('node-2', 'asset-a');

      expect(graph.nodesUsing('asset-a'), {'node-1', 'node-2'});
    });

    test('unlink removes edge', () {
      graph.link('node-1', 'asset-a');
      graph.unlink('node-1', 'asset-a');

      expect(graph.nodesUsing('asset-a'), isEmpty);
      expect(graph.assetsUsedBy('node-1'), isEmpty);
    });

    test('unlinkNode removes all edges for node', () {
      graph.link('node-1', 'asset-a');
      graph.link('node-1', 'asset-b');
      graph.link('node-2', 'asset-a');

      graph.unlinkNode('node-1');

      expect(graph.assetsUsedBy('node-1'), isEmpty);
      expect(graph.nodesUsing('asset-a'), {'node-2'});
      expect(graph.nodesUsing('asset-b'), isEmpty);
    });

    test('unlinkAsset removes all edges for asset', () {
      graph.link('node-1', 'asset-a');
      graph.link('node-2', 'asset-a');

      graph.unlinkAsset('asset-a');

      expect(graph.nodesUsing('asset-a'), isEmpty);
      expect(graph.assetsUsedBy('node-1'), isEmpty);
      expect(graph.assetsUsedBy('node-2'), isEmpty);
    });

    test('referencedAssets returns all linked assets', () {
      graph.link('n1', 'a1');
      graph.link('n2', 'a2');
      graph.link('n3', 'a1');

      expect(graph.referencedAssets, {'a1', 'a2'});
    });

    test('orphanedAssets returns unreferenced', () {
      graph.link('n1', 'a1');
      final all = {'a1', 'a2', 'a3'};

      expect(graph.orphanedAssets(all), {'a2', 'a3'});
    });

    test('counts are correct', () {
      graph.link('n1', 'a1');
      graph.link('n1', 'a2');
      graph.link('n2', 'a1');

      expect(graph.nodeCount, 2);
      expect(graph.assetCount, 2);
      expect(graph.linkCount, 3);
    });

    test('findBrokenLinks detects missing assets', () {
      graph.link('n1', 'a-missing');
      graph.link('n1', 'a-loaded');

      final broken = graph.findBrokenLinks({'a-loaded': AssetState.loaded});

      expect(broken.length, 1);
      expect(broken.first.assetId, 'a-missing');
      expect(broken.first.reason, BrokenLinkReason.missing);
    });

    test('findBrokenLinks detects error state', () {
      graph.link('n1', 'a-error');

      final broken = graph.findBrokenLinks({'a-error': AssetState.error});

      expect(broken.length, 1);
      expect(broken.first.reason, BrokenLinkReason.error);
    });

    test('findBrokenLinks detects disposed state', () {
      graph.link('n1', 'a-disposed');

      final broken = graph.findBrokenLinks({'a-disposed': AssetState.disposed});

      expect(broken.length, 1);
      expect(broken.first.reason, BrokenLinkReason.disposed);
    });

    test('findBrokenLinks detects evicted state', () {
      graph.link('n1', 'a-evicted');

      final broken = graph.findBrokenLinks({'a-evicted': AssetState.evicted});

      expect(broken.length, 1);
      expect(broken.first.reason, BrokenLinkReason.evicted);
    });

    test('findBrokenLinks returns empty for healthy graph', () {
      graph.link('n1', 'a1');
      graph.link('n2', 'a2');

      final broken = graph.findBrokenLinks({
        'a1': AssetState.loaded,
        'a2': AssetState.loaded,
      });

      expect(broken, isEmpty);
    });

    test('toJson/fromJson round-trips', () {
      graph.link('n1', 'a1');
      graph.link('n1', 'a2');
      graph.link('n2', 'a1');

      final json = graph.toJson();
      final restored = AssetDependencyGraph.fromJson(json);

      expect(restored.nodesUsing('a1'), {'n1', 'n2'});
      expect(restored.assetsUsedBy('n1'), {'a1', 'a2'});
      expect(restored.linkCount, 3);
      restored.dispose();
    });

    test('clear removes all links', () {
      graph.link('n1', 'a1');
      graph.link('n2', 'a2');
      graph.clear();

      expect(graph.linkCount, 0);
      expect(graph.nodeCount, 0);
      expect(graph.assetCount, 0);
    });

    test('dispose marks graph as disposed', () {
      graph.dispose();
      expect(graph.isDisposed, isTrue);
    });
  });
}
