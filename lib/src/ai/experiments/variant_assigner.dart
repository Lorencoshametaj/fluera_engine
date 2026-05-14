// ============================================================================
// 🧪 VariantAssigner — deterministic A/B bucket assignment.
//
// Given (experimentId, userId), returns a stable VariantAssignment. Same
// userId always lands in the same bucket for the same experiment, across
// sessions, devices (assuming stable userId), and processes.
//
// Hash function: SHA-256(experimentId + ':' + userId) → take 8 bytes →
// modulo 100 → bucket 0..99. Buckets are mapped to variants by
// cumulative-traffic boundaries.
//
// Why SHA-256 not Murmur3? Dart's `dart:convert` provides SHA-256 in
// the standard library (`crypto` package). Murmur3 would need a 3rd-party
// dep. SHA-256 is overkill for hashing but adds zero supply-chain risk.
// Performance: ~10-50 us per call, negligible (assignment cached
// after first call per session).
//
// Pure function + in-memory cache. No I/O, no async.
// ============================================================================

import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'experiment_definition.dart';

class VariantAssigner {
  /// In-memory cache: keyed by `(userId, experimentId)`.
  final Map<String, VariantAssignment> _cache = {};

  /// Compute (or fetch cached) variant assignment for [userId] in
  /// [experiment]. Returns 'control' if the experiment is not live
  /// at [now] (or [now] defaults to `DateTime.now()`).
  VariantAssignment assignmentFor({
    required String userId,
    required ExperimentDefinition experiment,
    DateTime? now,
  }) {
    final t = now ?? DateTime.now();
    final cacheKey = '$userId::${experiment.id}';
    final cached = _cache[cacheKey];
    if (cached != null) return cached;

    // Kill switch / out-of-window → control.
    if (!experiment.isLiveAt(t)) {
      final hash = _hashShort(userId, experiment.id);
      final result = VariantAssignment(
        experimentId: experiment.id,
        variantId: 'control',
        userIdHashShort: hash,
      );
      _cache[cacheKey] = result;
      return result;
    }

    final bucket = _bucket(userId, experiment.id);
    final variantId = _variantForBucket(bucket, experiment.variants);
    final result = VariantAssignment(
      experimentId: experiment.id,
      variantId: variantId,
      userIdHashShort: _hashShort(userId, experiment.id),
    );
    _cache[cacheKey] = result;
    return result;
  }

  /// Clear the cache. Call on userId change (logout/login) so new user
  /// gets fresh assignment computation.
  void clearCache() => _cache.clear();

  /// Number of cached assignments — useful for tests.
  int get cacheSize => _cache.length;

  // ── Internals ───────────────────────────────────────────────────────────

  /// Compute bucket 0..99 from `(userId, experimentId)`. Stable across
  /// processes (sha256 is deterministic).
  static int _bucket(String userId, String experimentId) {
    final input = '$experimentId:$userId';
    final digest = sha256.convert(utf8.encode(input)).bytes;
    // Take first 8 bytes → uint64 → modulo 100.
    int sum = 0;
    for (int i = 0; i < 8; i++) {
      sum = (sum << 8) | digest[i];
      // Trim to keep int safe (Dart int is 64-bit but bitwise on web is 32).
      sum &= 0x7fffffff;
    }
    return sum % 100;
  }

  /// Map [bucket] (0..99) to a variant id given the variant traffic
  /// distribution. Walks variants in declaration order accumulating
  /// trafficPercent — first variant whose cumulative threshold exceeds
  /// [bucket] wins.
  ///
  /// Example: variants = [(control, 50), (a, 30), (b, 20)]
  ///   bucket 0..49 → 'control'
  ///   bucket 50..79 → 'a'
  ///   bucket 80..99 → 'b'
  static String _variantForBucket(int bucket, List<VariantConfig> variants) {
    int cumulative = 0;
    for (final v in variants) {
      cumulative += v.trafficPercent;
      if (bucket < cumulative) return v.id;
    }
    // Fallback: should never hit if traffic sums to 100, but defensive.
    return variants.isNotEmpty ? variants.last.id : 'control';
  }

  /// Short hex of `sha256(userId + experimentId)`, 8 chars. For telemetry
  /// audit trail (proves the same userId always produced the same
  /// assignment for the same experiment). Not for security.
  static String _hashShort(String userId, String experimentId) {
    final input = '$experimentId:$userId';
    final digest = sha256.convert(utf8.encode(input));
    return digest.toString().substring(0, 8);
  }
}
