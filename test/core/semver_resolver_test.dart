import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/marketplace/semver_resolver.dart';

void main() {
  // ===========================================================================
  // Semver parsing
  // ===========================================================================

  group('Semver - parse', () {
    test('parses major.minor.patch', () {
      final v = Semver.parse('1.2.3');
      expect(v.major, 1);
      expect(v.minor, 2);
      expect(v.patch, 3);
    });

    test('parses prerelease', () {
      final v = Semver.parse('1.0.0-beta.1');
      expect(v.prerelease, isNotEmpty);
    });

    test('toString round-trips', () {
      final v = Semver.parse('2.1.0');
      expect(v.toString(), contains('2.1.0'));
    });
  });

  // ===========================================================================
  // Semver comparison
  // ===========================================================================

  group('Semver - compareTo', () {
    test('equal versions', () {
      expect(Semver.parse('1.0.0').compareTo(Semver.parse('1.0.0')), 0);
    });

    test('higher major wins', () {
      expect(
        Semver.parse('2.0.0').compareTo(Semver.parse('1.9.9')),
        greaterThan(0),
      );
    });

    test('higher minor wins', () {
      expect(
        Semver.parse('1.2.0').compareTo(Semver.parse('1.1.9')),
        greaterThan(0),
      );
    });

    test('higher patch wins', () {
      expect(
        Semver.parse('1.0.2').compareTo(Semver.parse('1.0.1')),
        greaterThan(0),
      );
    });
  });

  // ===========================================================================
  // SemverRange
  // ===========================================================================

  group('SemverRange', () {
    test('caret range satisfies compatible versions', () {
      final range = SemverRange.parse('^1.0.0');
      expect(range.satisfiedBy(Semver.parse('1.2.3')), isTrue);
    });

    test('caret range rejects next major', () {
      final range = SemverRange.parse('^1.0.0');
      expect(range.satisfiedBy(Semver.parse('2.0.0')), isFalse);
    });

    test('toString is readable', () {
      final range = SemverRange.parse('^1.0.0');
      expect(range.toString(), isNotEmpty);
    });
  });

  // ===========================================================================
  // DependencyResolver
  // ===========================================================================

  group('DependencyResolver', () {
    test('resolves simple dependency', () {
      final result = DependencyResolver.resolve(
        required: {'plugin-a': '^1.0.0'},
        available: {
          'plugin-a': ['1.0.0', '1.1.0', '1.2.0'],
        },
      );
      expect(result.resolved, isNotEmpty);
      expect(result.conflicts, isEmpty);
    });

    test('detects missing dependency', () {
      final result = DependencyResolver.resolve(
        required: {'plugin-x': '^1.0.0'},
        available: {},
      );
      expect(result.conflicts, isNotEmpty);
    });

    test('detects version conflict', () {
      final result = DependencyResolver.resolve(
        required: {'plugin-a': '^2.0.0'},
        available: {
          'plugin-a': ['1.0.0', '1.1.0'],
        },
      );
      expect(result.conflicts, isNotEmpty);
    });

    test('toString is readable', () {
      final result = DependencyResolver.resolve(
        required: {'a': '^1.0.0'},
        available: {
          'a': ['1.0.0'],
        },
      );
      expect(result.toString(), isNotEmpty);
    });
  });
}
