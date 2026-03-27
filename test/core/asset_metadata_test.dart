import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/assets/asset_metadata.dart';

void main() {
  // ===========================================================================
  // AssetLicense enum
  // ===========================================================================

  group('AssetLicense', () {
    test('has 4 values', () {
      expect(AssetLicense.values.length, 4);
      expect(AssetLicense.values, contains(AssetLicense.royaltyFree));
      expect(AssetLicense.values, contains(AssetLicense.unknown));
    });
  });

  // ===========================================================================
  // AssetMetadata construction
  // ===========================================================================

  group('AssetMetadata - construction', () {
    test('defaults are sensible', () {
      final meta = AssetMetadata();
      expect(meta.tags, isEmpty);
      expect(meta.license, AssetLicense.unknown);
      expect(meta.importedBy, 'system');
    });

    test('creates with tags and description', () {
      final meta = AssetMetadata(
        tags: {'icon', 'brand'},
        description: 'Logo image',
        mimeType: 'image/png',
      );
      expect(meta.tags, contains('icon'));
      expect(meta.description, 'Logo image');
    });
  });

  // ===========================================================================
  // copyWith
  // ===========================================================================

  group('AssetMetadata - copyWith', () {
    test('overrides single field', () {
      final meta = AssetMetadata(description: 'old');
      final copy = meta.copyWith(description: 'new');
      expect(copy.description, 'new');
    });

    test('preserves unchanged fields', () {
      final meta = AssetMetadata(
        tags: {'a'},
        license: AssetLicense.royaltyFree,
      );
      final copy = meta.copyWith(description: 'hello');
      expect(copy.tags, contains('a'));
      expect(copy.license, AssetLicense.royaltyFree);
    });
  });

  // ===========================================================================
  // Tag operations
  // ===========================================================================

  group('AssetMetadata - tags', () {
    test('addTags adds new tags', () {
      final meta = AssetMetadata(tags: {'a'});
      final updated = meta.addTags({'b', 'c'});
      expect(updated.tags, containsAll(['a', 'b', 'c']));
    });

    test('removeTags removes tags', () {
      final meta = AssetMetadata(tags: {'a', 'b', 'c'});
      final updated = meta.removeTags({'b'});
      expect(updated.tags, isNot(contains('b')));
      expect(updated.tags, contains('a'));
    });
  });

  // ===========================================================================
  // Search
  // ===========================================================================

  group('AssetMetadata - search', () {
    test('matchesTags finds partial match', () {
      final meta = AssetMetadata(tags: {'logo-icon', 'brand'});
      expect(meta.matchesTags('logo'), isTrue);
      expect(meta.matchesTags('xyz'), isFalse);
    });

    test('matchesSearch searches across fields', () {
      final meta = AssetMetadata(
        tags: {'hero'},
        description: 'Main banner image',
        mimeType: 'image/png',
      );
      expect(meta.matchesSearch('banner'), isTrue);
      expect(meta.matchesSearch('png'), isTrue);
      expect(meta.matchesSearch('hero'), isTrue);
      expect(meta.matchesSearch('xyz'), isFalse);
    });
  });

  // ===========================================================================
  // Serialization
  // ===========================================================================

  group('AssetMetadata - toJson/fromJson', () {
    test('round-trips', () {
      final meta = AssetMetadata(
        tags: {'ui', 'icon'},
        description: 'Test asset',
        license: AssetLicense.royaltyFree,
        widthPx: 512,
        heightPx: 512,
        mimeType: 'image/png',
      );
      final json = meta.toJson();
      final restored = AssetMetadata.fromJson(json);
      expect(restored.tags, contains('ui'));
      expect(restored.license, AssetLicense.royaltyFree);
      expect(restored.widthPx, 512);
    });
  });

  // ===========================================================================
  // AssetVersion
  // ===========================================================================

  group('AssetVersion', () {
    test('creates with required fields', () {
      final v = AssetVersion(
        version: 1,
        contentHash: 'abc123',
        createdAt: DateTime.utc(2024),
      );
      expect(v.version, 1);
      expect(v.contentHash, 'abc123');
    });

    test('toJson/fromJson round-trip', () {
      final v = AssetVersion(
        version: 2,
        contentHash: 'def456',
        createdAt: DateTime.utc(2024, 6, 1),
        comment: 'Updated logo',
      );
      final json = v.toJson();
      final restored = AssetVersion.fromJson(json);
      expect(restored.version, 2);
      expect(restored.comment, 'Updated logo');
    });

    test('toString is readable', () {
      final v = AssetVersion(
        version: 1,
        contentHash: 'abc',
        createdAt: DateTime.utc(2024),
      );
      expect(v.toString(), contains('v1'));
    });
  });
}
