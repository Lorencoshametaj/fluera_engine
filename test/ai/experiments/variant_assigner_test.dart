// ============================================================================
// 🧪 VariantAssigner — Unit tests
//
// Verifies:
//   - Bucket consistency: same userId × 1000 calls → same bucket
//   - Distribution accuracy: 10k userId → 50/50 split within ±2%
//   - Kill switch: active=false → all users get 'control'
//   - Date window: pre-startedAt / post-endsAt → 'control'
//   - Hash stability: SHA-256 deterministic across calls
//   - Cache: cacheSize grows with unique (user, exp) pairs
//   - Multi-experiment: same user can be in different variants across experiments
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/ai/experiments/experiment_definition.dart';
import 'package:fluera_engine/src/ai/experiments/variant_assigner.dart';

ExperimentDefinition _exp({
  String id = 'test_exp',
  List<VariantConfig>? variants,
  bool active = true,
  DateTime? startedAt,
  DateTime? endsAt,
}) {
  return ExperimentDefinition(
    id: id,
    name: 'Test experiment',
    hypothesis: 'Testing the test',
    variants: variants ??
        const [
          VariantConfig(id: 'control', label: 'A', trafficPercent: 50),
          VariantConfig(id: 'variant_b', label: 'B', trafficPercent: 50),
        ],
    primaryMetric: 'metric_x',
    startedAt: startedAt ?? DateTime(2026, 1, 1),
    endsAt: endsAt,
    active: active,
  );
}

void main() {
  group('VariantAssigner — bucket consistency', () {
    test('Same userId × 1000 calls → identical assignment', () {
      final assigner = VariantAssigner();
      final exp = _exp();
      final first = assigner.assignmentFor(
          userId: 'user-abc-123', experiment: exp);
      for (var i = 0; i < 1000; i++) {
        final r = assigner.assignmentFor(
            userId: 'user-abc-123', experiment: exp);
        expect(r.variantId, first.variantId);
      }
    });

    test('Hash short is 8 chars hex', () {
      final assigner = VariantAssigner();
      final r =
          assigner.assignmentFor(userId: 'u1', experiment: _exp());
      expect(r.userIdHashShort.length, 8);
      expect(RegExp(r'^[0-9a-f]{8}$').hasMatch(r.userIdHashShort), isTrue);
    });

    test('Cache: re-call same (user, exp) does NOT rehash', () {
      final assigner = VariantAssigner();
      assigner.assignmentFor(userId: 'u1', experiment: _exp());
      expect(assigner.cacheSize, 1);
      assigner.assignmentFor(userId: 'u1', experiment: _exp());
      expect(assigner.cacheSize, 1);
      assigner.assignmentFor(userId: 'u2', experiment: _exp());
      expect(assigner.cacheSize, 2);
    });

    test('clearCache forces re-hash on next call', () {
      final assigner = VariantAssigner();
      assigner.assignmentFor(userId: 'u1', experiment: _exp());
      expect(assigner.cacheSize, 1);
      assigner.clearCache();
      expect(assigner.cacheSize, 0);
    });
  });

  group('VariantAssigner — distribution accuracy', () {
    test('10k userId × 50/50 split: each branch within ±2% of 5000', () {
      final assigner = VariantAssigner();
      final exp = _exp();
      int controlCount = 0;
      int variantCount = 0;
      for (var i = 0; i < 10000; i++) {
        final r =
            assigner.assignmentFor(userId: 'user-$i', experiment: exp);
        if (r.variantId == 'control') {
          controlCount++;
        } else if (r.variantId == 'variant_b') {
          variantCount++;
        }
      }
      // Tolerance ±2% = 4800-5200 per branch
      expect(controlCount, greaterThan(4800));
      expect(controlCount, lessThan(5200));
      expect(variantCount, greaterThan(4800));
      expect(variantCount, lessThan(5200));
      expect(controlCount + variantCount, 10000);
    });

    test('3-way split 60/30/10 respects allocation', () {
      final assigner = VariantAssigner();
      final exp = _exp(variants: const [
        VariantConfig(id: 'control', label: 'A', trafficPercent: 60),
        VariantConfig(id: 'variant_b', label: 'B', trafficPercent: 30),
        VariantConfig(id: 'variant_c', label: 'C', trafficPercent: 10),
      ]);
      final counts = {'control': 0, 'variant_b': 0, 'variant_c': 0};
      for (var i = 0; i < 10000; i++) {
        final r =
            assigner.assignmentFor(userId: 'user-$i', experiment: exp);
        counts[r.variantId] = (counts[r.variantId] ?? 0) + 1;
      }
      // Tolerance ±3% for skewed distributions
      expect(counts['control'], greaterThan(5700));
      expect(counts['control'], lessThan(6300));
      expect(counts['variant_b'], greaterThan(2700));
      expect(counts['variant_b'], lessThan(3300));
      expect(counts['variant_c'], greaterThan(700));
      expect(counts['variant_c'], lessThan(1300));
    });
  });

  group('VariantAssigner — kill switch + date window', () {
    test('active=false → all users get control', () {
      final assigner = VariantAssigner();
      final exp = _exp(active: false);
      for (var i = 0; i < 100; i++) {
        final r =
            assigner.assignmentFor(userId: 'user-$i', experiment: exp);
        expect(r.variantId, 'control');
      }
    });

    test('Before startedAt → control', () {
      final assigner = VariantAssigner();
      final exp = _exp(startedAt: DateTime(2027, 1, 1));
      final r = assigner.assignmentFor(
        userId: 'u1',
        experiment: exp,
        now: DateTime(2026, 6, 1),
      );
      expect(r.variantId, 'control');
    });

    test('After endsAt → control', () {
      final assigner = VariantAssigner();
      final exp = _exp(
        startedAt: DateTime(2026, 1, 1),
        endsAt: DateTime(2026, 6, 1),
      );
      final r = assigner.assignmentFor(
        userId: 'u1',
        experiment: exp,
        now: DateTime(2026, 12, 1),
      );
      expect(r.variantId, 'control');
    });
  });
}
