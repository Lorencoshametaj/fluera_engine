import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/marketplace/plugin_manifest_schema.dart';

void main() {
  // ===========================================================================
  // MarketplaceManifest — construction
  // ===========================================================================

  group('MarketplaceManifest - construction', () {
    test('creates with required fields', () {
      const manifest = MarketplaceManifest(
        id: 'com.example.plugin',
        name: 'Test Plugin',
        version: '1.0.0',
        author: 'Test Author',
        description: 'A test plugin.',
        category: ManifestCategory.effects,
        pricing: PricingTier.free,
      );
      expect(manifest.id, 'com.example.plugin');
      expect(manifest.name, 'Test Plugin');
      expect(manifest.version, '1.0.0');
      expect(manifest.category, ManifestCategory.effects);
      expect(manifest.pricing, PricingTier.free);
    });

    test('defaults are sensible', () {
      const manifest = MarketplaceManifest(
        id: 'com.test.defaults',
        name: 'Defaults',
        version: '1.0.0',
        author: 'Author',
      );
      expect(manifest.category, ManifestCategory.other);
      expect(manifest.pricing, PricingTier.free);
      expect(manifest.minApiLevel, 1);
      expect(manifest.screenshots, isEmpty);
      expect(manifest.tags, isEmpty);
    });
  });

  // ===========================================================================
  // MarketplaceManifest — toJson / fromJson
  // ===========================================================================

  group('MarketplaceManifest - serialization', () {
    test('toJson contains expected keys', () {
      const manifest = MarketplaceManifest(
        id: 'com.example.json',
        name: 'JSON Test',
        version: '1.2.3',
        author: 'Author',
        category: ManifestCategory.tools,
        pricing: PricingTier.paid,
      );
      final json = manifest.toJson();
      expect(json['id'], 'com.example.json');
      expect(json['name'], 'JSON Test');
      expect(json['version'], '1.2.3');
      expect(json['category'], 'tools');
      expect(json['pricing'], 'paid');
    });

    test('fromJson round-trips correctly', () {
      const original = MarketplaceManifest(
        id: 'com.test.roundtrip',
        name: 'Round Trip',
        version: '2.0.0',
        author: 'Dev',
        description: 'Round trip test',
        category: ManifestCategory.integrations,
        tags: ['tag1', 'tag2'],
      );
      final json = original.toJson();
      final restored = MarketplaceManifest.fromJson(json);
      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.version, original.version);
      expect(restored.category, original.category);
      expect(restored.tags, original.tags);
    });
  });

  // ===========================================================================
  // ManifestValidator
  // ===========================================================================

  group('ManifestValidator', () {
    test('valid manifest produces no errors', () {
      const manifest = MarketplaceManifest(
        id: 'com.valid.plugin',
        name: 'Valid Plugin',
        version: '1.0.0',
        author: 'Author Name',
      );
      final errors = ManifestValidator.validate(manifest);
      final realErrors =
          errors
              .where((e) => e.severity == ManifestErrorSeverity.error)
              .toList();
      expect(realErrors, isEmpty);
    });

    test('empty id produces error', () {
      const manifest = MarketplaceManifest(
        id: '',
        name: 'Plugin',
        version: '1.0.0',
        author: 'Author',
      );
      final errors = ManifestValidator.validate(manifest);
      expect(
        errors.any(
          (e) => e.field == 'id' && e.severity == ManifestErrorSeverity.error,
        ),
        isTrue,
      );
    });

    test('empty name produces error', () {
      const manifest = MarketplaceManifest(
        id: 'com.test.plugin',
        name: '',
        version: '1.0.0',
        author: 'Author',
      );
      final errors = ManifestValidator.validate(manifest);
      expect(errors.any((e) => e.field == 'name'), isTrue);
    });

    test('invalid version produces error', () {
      const manifest = MarketplaceManifest(
        id: 'com.test.plugin',
        name: 'Test',
        version: 'not-a-version',
        author: 'Author',
      );
      final errors = ManifestValidator.validate(manifest);
      expect(errors.any((e) => e.field == 'version'), isTrue);
    });

    test('isValid returns true for valid manifest', () {
      const manifest = MarketplaceManifest(
        id: 'com.valid.plugin2',
        name: 'Valid Plugin 2',
        version: '2.0.0',
        author: 'Author Name',
      );
      expect(ManifestValidator.isValid(manifest), isTrue);
    });

    test('isValid returns false for invalid manifest', () {
      const manifest = MarketplaceManifest(
        id: '',
        name: '',
        version: '',
        author: '',
      );
      expect(ManifestValidator.isValid(manifest), isFalse);
    });
  });

  // ===========================================================================
  // ManifestError
  // ===========================================================================

  group('ManifestError', () {
    test('toString contains field and message', () {
      const error = ManifestError('name', 'Name is required');
      expect(error.toString(), contains('name'));
      expect(error.toString(), contains('Name is required'));
    });
  });

  // ===========================================================================
  // Enums
  // ===========================================================================

  group('Enums', () {
    test('ManifestCategory has expected values', () {
      expect(ManifestCategory.values, contains(ManifestCategory.tools));
      expect(ManifestCategory.values, contains(ManifestCategory.effects));
    });

    test('PricingTier has expected values', () {
      expect(PricingTier.values, contains(PricingTier.free));
      expect(PricingTier.values, contains(PricingTier.paid));
      expect(PricingTier.values, contains(PricingTier.enterprise));
    });
  });
}
