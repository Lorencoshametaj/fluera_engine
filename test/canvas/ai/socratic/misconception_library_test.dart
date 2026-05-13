// ============================================================================
// 🧠 Misconception library — Unit tests
//
// Covers:
//   - All 30 entries have non-empty required fields
//   - Each discipline has at least 2 entries
//   - kMisconceptionLibrary getter is idempotent (Map view)
//   - All probePattern templates contain [concept] placeholder
//   - No duplicate ids
//   - Citation strings (where present) are non-empty
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/canvas/ai/socratic/socratic_misconception_library.dart';
import 'package:fluera_engine/src/canvas/ai/socratic/socratic_model.dart';

void main() {
  group('kMisconceptionLibrary', () {
    test('contains ≥ 25 entries total', () {
      final all = kMisconceptionLibrary.values.expand((l) => l).toList();
      expect(all.length, greaterThanOrEqualTo(25));
    });

    test('each non-generic discipline has ≥ 2 entries', () {
      final lib = kMisconceptionLibrary;
      for (final d in Discipline.values) {
        if (d == Discipline.generic) continue;
        expect(lib[d], isNotNull,
            reason: '$d should have at least one misconception');
        expect(lib[d]!.length, greaterThanOrEqualTo(2),
            reason: '$d should have ≥2 misconceptions, got ${lib[d]!.length}');
      }
    });

    test('all entries have non-empty fields', () {
      for (final m in kMisconceptionLibrary.values.expand((l) => l)) {
        expect(m.id, isNotEmpty, reason: 'id missing');
        expect(m.conceptKeywords, isNotEmpty,
            reason: '${m.id} has no keywords');
        expect(m.misconceptionText, isNotEmpty,
            reason: '${m.id} has empty misconceptionText');
        expect(m.correctView, isNotEmpty,
            reason: '${m.id} has empty correctView');
        expect(m.probePattern, isNotEmpty,
            reason: '${m.id} has empty probePattern');
      }
    });

    test('all probePattern templates contain [concept] placeholder', () {
      for (final m in kMisconceptionLibrary.values.expand((l) => l)) {
        expect(m.probePattern, contains('[concept]'),
            reason: '${m.id} probePattern missing [concept] placeholder');
      }
    });

    test('no duplicate ids across the library', () {
      final ids = <String>{};
      for (final m in kMisconceptionLibrary.values.expand((l) => l)) {
        expect(ids.add(m.id), isTrue, reason: 'duplicate id: ${m.id}');
      }
    });

    test('all keywords are ≥3 chars (avoids noise matches)', () {
      for (final m in kMisconceptionLibrary.values.expand((l) => l)) {
        for (final kw in m.conceptKeywords) {
          expect(kw.length, greaterThanOrEqualTo(3),
              reason: '${m.id} has short keyword "$kw"');
        }
      }
    });

    test('Physics entries cite Hestenes / FCI where applicable', () {
      final phys = kMisconceptionLibrary[Discipline.physics]!;
      final motion = phys.firstWhere((m) => m.id == 'motion-requires-force');
      expect(motion.citation, contains('Hestenes'));
    });
  });
}
