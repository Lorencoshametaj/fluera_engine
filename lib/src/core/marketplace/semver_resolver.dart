/// 🔌 SEMVER RESOLVER — Semantic versioning with dependency resolution.
///
/// Parses, compares, and resolves semantic versions and range constraints.
///
/// ```dart
/// final v = Semver.parse('1.2.3');
/// final range = SemverRange.parse('^1.0.0');
/// assert(range.satisfiedBy(v));
/// ```
library;

// =============================================================================
// SEMVER
// =============================================================================

/// Semantic version: major.minor.patch[-prerelease][+build].
class Semver implements Comparable<Semver> {
  final int major;
  final int minor;
  final int patch;
  final String? prerelease;
  final String? build;

  const Semver(
    this.major,
    this.minor,
    this.patch, {
    this.prerelease,
    this.build,
  });

  /// Parse a semver string.
  factory Semver.parse(String input) {
    final clean = input.trim();
    if (clean.isEmpty) return const Semver(0, 0, 0);

    String? buildMeta;
    var core = clean;

    // Extract build metadata
    final buildIdx = core.indexOf('+');
    if (buildIdx >= 0) {
      buildMeta = core.substring(buildIdx + 1);
      core = core.substring(0, buildIdx);
    }

    // Extract prerelease
    String? pre;
    final preIdx = core.indexOf('-');
    if (preIdx >= 0) {
      pre = core.substring(preIdx + 1);
      core = core.substring(0, preIdx);
    }

    final parts = core.split('.');
    return Semver(
      parts.isNotEmpty ? int.tryParse(parts[0]) ?? 0 : 0,
      parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
      parts.length > 2 ? int.tryParse(parts[2]) ?? 0 : 0,
      prerelease: pre,
      build: buildMeta,
    );
  }

  /// Whether this is a prerelease version.
  bool get isPrerelease => prerelease != null && prerelease!.isNotEmpty;

  /// Next major version.
  Semver get nextMajor => Semver(major + 1, 0, 0);

  /// Next minor version.
  Semver get nextMinor => Semver(major, minor + 1, 0);

  /// Next patch version.
  Semver get nextPatch => Semver(major, minor, patch + 1);

  @override
  int compareTo(Semver other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);
    // Prerelease has lower precedence than release
    if (isPrerelease && !other.isPrerelease) return -1;
    if (!isPrerelease && other.isPrerelease) return 1;
    return 0;
  }

  bool operator >=(Semver other) => compareTo(other) >= 0;
  bool operator >(Semver other) => compareTo(other) > 0;
  bool operator <=(Semver other) => compareTo(other) <= 0;
  bool operator <(Semver other) => compareTo(other) < 0;

  @override
  bool operator ==(Object other) =>
      other is Semver &&
      major == other.major &&
      minor == other.minor &&
      patch == other.patch &&
      prerelease == other.prerelease;

  @override
  int get hashCode => Object.hash(major, minor, patch, prerelease);

  @override
  String toString() {
    final buf = StringBuffer('$major.$minor.$patch');
    if (prerelease != null) buf.write('-$prerelease');
    if (build != null) buf.write('+$build');
    return buf.toString();
  }
}

// =============================================================================
// SEMVER RANGE
// =============================================================================

/// A version constraint (e.g. ^1.0.0, >=2.0.0 <3.0.0, ~1.2.0).
class SemverRange {
  /// Minimum version (inclusive).
  final Semver min;

  /// Maximum version (exclusive).
  final Semver max;

  /// Whether min is inclusive.
  final bool minInclusive;

  /// Whether max is inclusive.
  final bool maxInclusive;

  const SemverRange({
    required this.min,
    required this.max,
    this.minInclusive = true,
    this.maxInclusive = false,
  });

  /// Parse a version range string.
  ///
  /// Supports: `^1.0.0`, `~1.2.0`, `>=1.0.0 <2.0.0`, `1.2.3` (exact).
  factory SemverRange.parse(String input) {
    final trimmed = input.trim();

    // Caret range: ^1.2.3 → >=1.2.3 <2.0.0
    if (trimmed.startsWith('^')) {
      final v = Semver.parse(trimmed.substring(1));
      return SemverRange(min: v, max: v.nextMajor);
    }

    // Tilde range: ~1.2.3 → >=1.2.3 <1.3.0
    if (trimmed.startsWith('~')) {
      final v = Semver.parse(trimmed.substring(1));
      return SemverRange(min: v, max: v.nextMinor);
    }

    // Compound range: >=1.0.0 <2.0.0
    if (trimmed.contains(' ')) {
      final parts = trimmed.split(RegExp(r'\s+'));
      Semver? rangeMin;
      Semver? rangeMax;
      bool minIncl = true;
      bool maxIncl = false;

      for (final part in parts) {
        if (part.startsWith('>=')) {
          rangeMin = Semver.parse(part.substring(2));
          minIncl = true;
        } else if (part.startsWith('>')) {
          rangeMin = Semver.parse(part.substring(1));
          minIncl = false;
        } else if (part.startsWith('<=')) {
          rangeMax = Semver.parse(part.substring(2));
          maxIncl = true;
        } else if (part.startsWith('<')) {
          rangeMax = Semver.parse(part.substring(1));
          maxIncl = false;
        }
      }

      return SemverRange(
        min: rangeMin ?? const Semver(0, 0, 0),
        max: rangeMax ?? const Semver(999, 999, 999),
        minInclusive: minIncl,
        maxInclusive: maxIncl,
      );
    }

    // Exact version
    final v = Semver.parse(trimmed);
    return SemverRange(min: v, max: v, minInclusive: true, maxInclusive: true);
  }

  /// Check if a version satisfies this range.
  bool satisfiedBy(Semver version) {
    final minOk = minInclusive ? version >= min : version > min;
    final maxOk = maxInclusive ? version <= max : version < max;
    return minOk && maxOk;
  }

  @override
  String toString() {
    if (min == max && minInclusive && maxInclusive) return min.toString();
    final minOp = minInclusive ? '>=' : '>';
    final maxOp = maxInclusive ? '<=' : '<';
    return '$minOp$min $maxOp$max';
  }
}

// =============================================================================
// DEPENDENCY RESOLVER
// =============================================================================

/// Resolves plugin dependency trees with conflict detection.
class DependencyResolver {
  const DependencyResolver._();

  /// Resolve a dependency tree.
  ///
  /// [required] maps plugin ID → version constraint.
  /// [available] maps plugin ID → list of available versions.
  /// Returns resolved versions or list of conflicts.
  static DependencyResult resolve({
    required Map<String, String> required,
    required Map<String, List<String>> available,
  }) {
    final resolved = <String, Semver>{};
    final conflicts = <String>[];

    for (final entry in required.entries) {
      final pluginId = entry.key;
      final constraint = SemverRange.parse(entry.value);
      final versions = available[pluginId];

      if (versions == null || versions.isEmpty) {
        conflicts.add('$pluginId: not found in registry');
        continue;
      }

      // Parse and sort versions descending
      final parsed =
          versions.map(Semver.parse).toList()..sort((a, b) => b.compareTo(a));

      // Find highest satisfying version
      Semver? best;
      for (final v in parsed) {
        if (constraint.satisfiedBy(v)) {
          best = v;
          break;
        }
      }

      if (best != null) {
        resolved[pluginId] = best;
      } else {
        conflicts.add('$pluginId: no version satisfies ${entry.value}');
      }
    }

    return DependencyResult(resolved: resolved, conflicts: conflicts);
  }
}

/// Result of dependency resolution.
class DependencyResult {
  /// Resolved plugin ID → version.
  final Map<String, Semver> resolved;

  /// Conflict messages.
  final List<String> conflicts;

  const DependencyResult({this.resolved = const {}, this.conflicts = const []});

  /// Whether resolution succeeded (no conflicts).
  bool get success => conflicts.isEmpty;

  @override
  String toString() =>
      success
          ? 'Resolved: ${resolved.entries.map((e) => '${e.key}@${e.value}').join(', ')}'
          : 'Conflicts: ${conflicts.join('; ')}';
}
