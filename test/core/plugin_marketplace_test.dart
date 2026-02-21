import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/marketplace/plugin_manifest_schema.dart';
import 'package:nebula_engine/src/core/marketplace/semver_resolver.dart';
import 'package:nebula_engine/src/core/marketplace/plugin_signing_service.dart';
import 'package:nebula_engine/src/core/marketplace/plugin_update_manager.dart';

void main() {
  // ===========================================================================
  // PLUGIN MANIFEST SCHEMA
  // ===========================================================================

  group('MarketplaceManifest', () {
    test('valid manifest passes validation', () {
      const manifest = MarketplaceManifest(
        id: 'com.acme.blur',
        name: 'Blur Tool',
        version: '1.2.0',
        author: 'Acme Corp',
      );
      expect(ManifestValidator.isValid(manifest), isTrue);
    });

    test('empty id fails', () {
      const manifest = MarketplaceManifest(
        id: '',
        name: 'Test',
        version: '1.0.0',
        author: 'Me',
      );
      final errors = ManifestValidator.validate(manifest);
      expect(errors.any((e) => e.field == 'id'), isTrue);
    });

    test('invalid semver fails', () {
      const manifest = MarketplaceManifest(
        id: 'com.test.x',
        name: 'Test',
        version: 'not-a-version',
        author: 'Me',
      );
      final errors = ManifestValidator.validate(manifest);
      expect(errors.any((e) => e.field == 'version'), isTrue);
    });

    test('name too long fails', () {
      final manifest = MarketplaceManifest(
        id: 'com.test.x',
        name: 'A' * 51,
        version: '1.0.0',
        author: 'Me',
      );
      final errors = ManifestValidator.validate(manifest);
      expect(errors.any((e) => e.field == 'name'), isTrue);
    });

    test('serialization round-trip', () {
      const manifest = MarketplaceManifest(
        id: 'com.acme.blur',
        name: 'Blur',
        version: '2.0.0',
        author: 'Acme',
        category: ManifestCategory.effects,
        pricing: PricingTier.freemium,
        tags: ['blur', 'effect'],
      );
      final json = manifest.toJson();
      final restored = MarketplaceManifest.fromJson(json);
      expect(restored.id, manifest.id);
      expect(restored.category, ManifestCategory.effects);
      expect(restored.pricing, PricingTier.freemium);
    });
  });

  // ===========================================================================
  // SEMVER RESOLVER
  // ===========================================================================

  group('Semver', () {
    test('parse basic version', () {
      final v = Semver.parse('1.2.3');
      expect(v.major, 1);
      expect(v.minor, 2);
      expect(v.patch, 3);
    });

    test('parse prerelease', () {
      final v = Semver.parse('1.0.0-beta.1');
      expect(v.isPrerelease, isTrue);
      expect(v.prerelease, 'beta.1');
    });

    test('parse build metadata', () {
      final v = Semver.parse('1.0.0+build.123');
      expect(v.build, 'build.123');
    });

    test('comparison', () {
      expect(Semver.parse('2.0.0') > Semver.parse('1.9.9'), isTrue);
      expect(Semver.parse('1.1.0') > Semver.parse('1.0.9'), isTrue);
      expect(Semver.parse('1.0.1') > Semver.parse('1.0.0'), isTrue);
    });

    test('prerelease lower than release', () {
      expect(Semver.parse('1.0.0-alpha') < Semver.parse('1.0.0'), isTrue);
    });

    test('next versions', () {
      final v = Semver.parse('1.2.3');
      expect(v.nextMajor.toString(), '2.0.0');
      expect(v.nextMinor.toString(), '1.3.0');
      expect(v.nextPatch.toString(), '1.2.4');
    });
  });

  group('SemverRange', () {
    test('caret range', () {
      final range = SemverRange.parse('^1.2.0');
      expect(range.satisfiedBy(Semver.parse('1.2.0')), isTrue);
      expect(range.satisfiedBy(Semver.parse('1.9.9')), isTrue);
      expect(range.satisfiedBy(Semver.parse('2.0.0')), isFalse);
    });

    test('tilde range', () {
      final range = SemverRange.parse('~1.2.0');
      expect(range.satisfiedBy(Semver.parse('1.2.5')), isTrue);
      expect(range.satisfiedBy(Semver.parse('1.3.0')), isFalse);
    });

    test('compound range', () {
      final range = SemverRange.parse('>=1.0.0 <2.0.0');
      expect(range.satisfiedBy(Semver.parse('1.5.0')), isTrue);
      expect(range.satisfiedBy(Semver.parse('0.9.0')), isFalse);
      expect(range.satisfiedBy(Semver.parse('2.0.0')), isFalse);
    });

    test('exact version', () {
      final range = SemverRange.parse('1.2.3');
      expect(range.satisfiedBy(Semver.parse('1.2.3')), isTrue);
      expect(range.satisfiedBy(Semver.parse('1.2.4')), isFalse);
    });
  });

  group('DependencyResolver', () {
    test('resolves compatible dependencies', () {
      final result = DependencyResolver.resolve(
        required: {'plugin-a': '^1.0.0', 'plugin-b': '~2.1.0'},
        available: {
          'plugin-a': ['1.0.0', '1.2.0', '2.0.0'],
          'plugin-b': ['2.1.0', '2.1.5', '2.2.0'],
        },
      );
      expect(result.success, isTrue);
      expect(result.resolved['plugin-a'].toString(), '1.2.0');
      expect(result.resolved['plugin-b'].toString(), '2.1.5');
    });

    test('detects missing dependency', () {
      final result = DependencyResolver.resolve(
        required: {'missing-plugin': '^1.0.0'},
        available: {},
      );
      expect(result.success, isFalse);
      expect(result.conflicts[0], contains('not found'));
    });

    test('detects version conflict', () {
      final result = DependencyResolver.resolve(
        required: {'plugin-a': '^3.0.0'},
        available: {
          'plugin-a': ['1.0.0', '2.0.0'],
        },
      );
      expect(result.success, isFalse);
      expect(result.conflicts[0], contains('no version satisfies'));
    });
  });

  // ===========================================================================
  // PLUGIN SIGNING SERVICE
  // ===========================================================================

  group('PluginSigningService', () {
    const manifest = MarketplaceManifest(
      id: 'com.test.plugin',
      name: 'Test Plugin',
      version: '1.0.0',
      author: 'Test',
    );

    test('sign and verify', () {
      const service = PluginSigningService(secretKey: 'my-secret');
      final bundle = service.sign(manifest: manifest, contentHash: 'abc123');
      final result = service.verify(bundle);
      expect(result.valid, isTrue);
    });

    test('tampered content fails verification', () {
      const service = PluginSigningService(secretKey: 'my-secret');
      final bundle = service.sign(manifest: manifest, contentHash: 'abc123');

      // Tamper by creating a new bundle with different hash but same sig
      final tampered = SignedBundle(
        manifest: manifest,
        contentHash: 'TAMPERED',
        signature: bundle.signature,
        signedAtMs: bundle.signedAtMs,
      );
      final result = service.verify(tampered);
      expect(result.valid, isFalse);
    });

    test('wrong key fails verification', () {
      const signer = PluginSigningService(secretKey: 'key-1');
      const verifier = PluginSigningService(secretKey: 'key-2');

      final bundle = signer.sign(manifest: manifest, contentHash: 'abc123');
      final result = verifier.verify(bundle);
      expect(result.valid, isFalse);
    });

    test('empty content hash fails', () {
      const service = PluginSigningService(secretKey: 'key');
      final bundle = SignedBundle(
        manifest: manifest,
        contentHash: '',
        signature: 'some-sig',
        signedAtMs: 0,
      );
      final result = service.verify(bundle);
      expect(result.valid, isFalse);
    });

    test('serialization round-trip', () {
      const service = PluginSigningService(secretKey: 'my-secret');
      final bundle = service.sign(manifest: manifest, contentHash: 'hash123');
      final json = bundle.toJson();
      final restored = SignedBundle.fromJson(json);
      expect(restored.signature, bundle.signature);
      expect(service.verify(restored).valid, isTrue);
    });
  });

  // ===========================================================================
  // PLUGIN UPDATE MANAGER
  // ===========================================================================

  group('PluginUpdateManager', () {
    test('register and check for updates', () {
      final manager = PluginUpdateManager();
      manager.registerInstalled('plugin-a', '1.0.0');

      final updates = manager.checkForUpdates({'plugin-a': '1.1.0'});
      expect(updates.length, 1);
      expect(updates[0].newVersion.toString(), '1.1.0');
    });

    test('no update when already latest', () {
      final manager = PluginUpdateManager();
      manager.registerInstalled('plugin-a', '2.0.0');

      final updates = manager.checkForUpdates({'plugin-a': '1.0.0'});
      expect(updates, isEmpty);
    });

    test('complete update sets new version', () {
      final manager = PluginUpdateManager();
      manager.registerInstalled('plugin-a', '1.0.0');

      final entry = manager.beginUpdate('plugin-a', '1.1.0');
      expect(entry.status, UpdateStatus.downloading);

      manager.completeUpdate(entry);
      expect(entry.status, UpdateStatus.installed);
      expect(manager.getInstalledVersion('plugin-a'), '1.1.0');
    });

    test('failed update triggers rollback', () {
      final manager = PluginUpdateManager();
      manager.registerInstalled('plugin-a', '1.0.0');

      final entry = manager.beginUpdate('plugin-a', '2.0.0');
      manager.failUpdate(entry, 'Install failed');

      expect(entry.status, UpdateStatus.rolledBack);
      expect(manager.getInstalledVersion('plugin-a'), '1.0.0');
    });

    test('update history tracking', () {
      final manager = PluginUpdateManager();
      manager.registerInstalled('p', '1.0.0');

      final e1 = manager.beginUpdate('p', '1.1.0');
      manager.completeUpdate(e1);
      final e2 = manager.beginUpdate('p', '1.2.0');
      manager.failUpdate(e2, 'error');

      expect(manager.successfulUpdates, 1);
      expect(manager.failedUpdates, 1);
      expect(manager.historyFor('p').length, 2);
    });

    test('staged rollout filters updates', () {
      final manager = PluginUpdateManager(
        rolloutPercent: 0, // nobody should get the update
        random: math.Random(42),
      );
      manager.registerInstalled('p', '1.0.0');

      final updates = manager.checkForUpdates({'p': '2.0.0'});
      expect(updates, isEmpty);
    });
  });
}
