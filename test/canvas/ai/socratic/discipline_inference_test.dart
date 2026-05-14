// ============================================================================
// 🎓 inferDiscipline — Unit tests
//
// Covers:
//   - Physics keyword set → Discipline.physics
//   - Math, biology, medicine, etc. each map correctly
//   - Mixed-discipline texts return highest-score
//   - Below 30% margin returns Discipline.generic
//   - Empty input → generic
//   - Case-insensitive matching
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/canvas/ai/socratic/socratic_misconception_library.dart';
import 'package:fluera_engine/src/canvas/ai/socratic/socratic_model.dart';

void main() {
  group('inferDiscipline', () {
    test('Physics keywords → physics', () {
      final d = inferDiscipline([
        'Prima legge di Newton',
        'Inerzia e forza gravitazionale',
      ]);
      expect(d, Discipline.physics);
    });

    test('Math keywords → math', () {
      final d = inferDiscipline([
        'Derivata della funzione',
        'Teorema di Lagrange e integrali',
      ]);
      expect(d, Discipline.math);
    });

    test('Biology keywords → biology', () {
      final d = inferDiscipline([
        'Cellula eucariote, mitocondri',
        'Sintesi proteica e DNA',
      ]);
      expect(d, Discipline.biology);
    });

    test('Law keywords → law', () {
      final d = inferDiscipline([
        'Contratto di compravendita',
        'Prescrizione e obbligazione',
      ]);
      expect(d, Discipline.law);
    });

    test('Case-insensitive matching', () {
      final d = inferDiscipline(['NEWTON', 'gravitÀ', 'Inerzia']);
      expect(d, Discipline.physics);
    });

    test('Empty text → generic', () {
      expect(inferDiscipline([]), Discipline.generic);
      expect(inferDiscipline(['', '   ']), Discipline.generic);
    });

    test('No keyword match → generic', () {
      final d = inferDiscipline([
        'foo bar baz',
        'lorem ipsum dolor sit amet',
      ]);
      expect(d, Discipline.generic);
    });

    test('Cross-disciplinary canvas → generic (sub-30% margin)', () {
      // Roughly equal physics + biology keywords → ambiguous, return generic.
      // 2 phys hits (newton, inerzia) vs 2 bio hits (cellula, dna) → tie,
      // 30% margin not met → generic.
      final d = inferDiscipline([
        'Cellula e DNA',
        'Newton e inerzia',
      ]);
      expect(d, Discipline.generic);
    });
  });

  group('pickMisconceptionFor', () {
    test('Newton physics → motion-requires-force', () {
      final m = pickMisconceptionFor(
        Discipline.physics,
        ['Prima legge di Newton, inerzia, corpo a riposo'],
      );
      expect(m?.id, 'motion-requires-force');
    });

    test('Evolution biology → lamarckian-inheritance or related', () {
      final m = pickMisconceptionFor(
        Discipline.biology,
        ['Evoluzione e selezione naturale'],
      );
      expect(m, isNotNull);
      expect(m!.discipline, Discipline.biology);
    });

    test('Generic discipline → null (no library)', () {
      final m = pickMisconceptionFor(
        Discipline.generic,
        ['Anything goes here'],
      );
      expect(m, isNull);
    });

    test('No keyword match → null', () {
      final m = pickMisconceptionFor(
        Discipline.physics,
        ['Random text without physics keywords like xyz qux'],
      );
      expect(m, isNull);
    });

    test('Deterministic: same input → same output', () {
      final a = pickMisconceptionFor(
        Discipline.physics,
        ['Inerzia, Newton, prima legge'],
      );
      final b = pickMisconceptionFor(
        Discipline.physics,
        ['Inerzia, Newton, prima legge'],
      );
      expect(a?.id, b?.id);
    });

    test('Empty texts → null', () {
      final m = pickMisconceptionFor(Discipline.physics, []);
      expect(m, isNull);
    });
  });

  // ── EN coverage tests (i18n, 2026-05-12) ─────────────────────────────────
  group('inferDiscipline — English', () {
    test('EN physics keywords → physics', () {
      final d = inferDiscipline(
        ['Newton inertia and gravity force', 'motion velocity'],
        language: 'en',
      );
      expect(d, Discipline.physics);
    });

    test('EN biology keywords → biology', () {
      final d = inferDiscipline(
        ['Cell mitochondrial DNA evolution', 'protein selection'],
        language: 'en',
      );
      expect(d, Discipline.biology);
    });

    test('EN no match → generic', () {
      final d = inferDiscipline(
        ['lorem ipsum dolor sit amet foo bar'],
        language: 'en',
      );
      expect(d, Discipline.generic);
    });
  });

  group('pickMisconceptionFor — English', () {
    test('EN physics Newton → motion-requires-force', () {
      final m = pickMisconceptionFor(
        Discipline.physics,
        ['Newton first law inertia'],
        language: 'en',
      );
      expect(m?.id, 'motion-requires-force');
      // The EN text should be English (not Italian).
      expect(m?.textFor('en')?.misconception, contains('moving body'));
    });

    test('Missing language falls back to IT in textFor', () {
      // Post Sprint F.2 misconception bootstrap, FR/ES/etc are in the
      // bootstrap map → no longer fall back to IT. Use a lang code that
      // is NOT in the 14 Tier-1/2 bootstrap set (e.g. 'zu' Zulu) to
      // exercise the IT fallback path.
      final m = pickMisconceptionFor(
        Discipline.physics,
        ['inerzia'],
        language: 'it',
      );
      expect(m?.textFor('zu'),
          equals(m?.textFor('it')), // fallback to IT
          reason: 'unknown language (not bootstrap-covered) returns IT payload');
    });
  });
}
