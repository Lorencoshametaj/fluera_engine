// ============================================================================
// 🧠 ClusterConceptIndex — Unit tests
//
// Covers:
//   - resolve() lazy field computation (rawOcr / cleanedOcr / concepts)
//   - Memoize-while-pending (concurrent resolves dedup)
//   - Cache hit (no AI call on second resolve when satisfied)
//   - Stroke-set change → re-resolve
//   - Avoid ring buffer cap + cross-feature recording
//   - FSRS lookup via concepts
//   - invalidate() drops entries
// ============================================================================

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/ai/ai_provider.dart';
import 'package:fluera_engine/src/canvas/ai/cluster_concept.dart';
import 'package:fluera_engine/src/canvas/ai/cluster_concept_index.dart';
import 'package:fluera_engine/src/canvas/ai/fsrs_scheduler.dart';
import 'package:fluera_engine/src/drawing/models/pro_drawing_point.dart';
import 'package:fluera_engine/src/reflow/content_cluster.dart';
import 'package:fluera_engine/src/utils/ai_language_preference.dart';

import '_fakes.dart';

// ─── Test helpers ──────────────────────────────────────────────────────────

ProStroke _makeStroke(String id, DateTime t) {
  return ProStroke(
    id: id,
    points: [
      ProDrawingPoint(
        position: const Offset(0, 0),
        pressure: 0.5,
        timestamp: t.millisecondsSinceEpoch,
      ),
      ProDrawingPoint(
        position: const Offset(20, 10),
        pressure: 0.5,
        timestamp: t.millisecondsSinceEpoch + 5,
      ),
      ProDrawingPoint(
        position: const Offset(40, 20),
        pressure: 0.5,
        timestamp: t.millisecondsSinceEpoch + 10,
      ),
    ],
    color: const Color(0xFF000000),
    baseWidth: 2.0,
    penType: ProPenType.ballpoint,
    createdAt: t,
  );
}

ContentCluster _makeCluster(String id, List<String> strokeIds) {
  return ContentCluster(
    id: id,
    strokeIds: strokeIds,
    bounds: const Rect.fromLTWH(0, 0, 100, 50),
    centroid: const Offset(50, 25),
  );
}

ClusterConceptIndex _makeIndex({
  Map<String, ProStroke>? strokeMap,
  Map<String, SrsCardData>? schedule,
  String language = 'Italian',
  AiProvider? provider,
}) {
  return ClusterConceptIndex(
    providerFn: () => provider, // null when omitted; tests can inject a fake
    strokeMapFn: () => strokeMap ?? const {},
    reviewScheduleFn: () => schedule ?? const {},
    languageNameFn: () => language,
  );
}

void main() {
  group('ClusterConceptIndex — basic resolve', () {
    test('resolve returns empty concept when stroke map is empty', () async {
      final index = _makeIndex();
      final cluster = _makeCluster('c1', ['s1']);
      final concept = await index.resolve(cluster, needsRawOcr: true);
      expect(concept.clusterId, 'c1');
      expect(concept.rawOcr, isNull);
    });

    test('resolve is idempotent for the same field set', () async {
      final index = _makeIndex();
      final cluster = _makeCluster('c1', ['s1']);
      final c1 = await index.resolve(cluster, needsRawOcr: true);
      final c2 = await index.resolve(cluster, needsRawOcr: true);
      // Same instance — cache hit.
      expect(identical(c1, c2), isTrue);
    });

    test('snapshot reflects resolved concepts', () async {
      final index = _makeIndex();
      final cluster = _makeCluster('c1', ['s1']);
      await index.resolve(cluster, needsRawOcr: true);
      expect(index.snapshot().keys, contains('c1'));
    });

    test('peek returns null for unresolved cluster', () {
      final index = _makeIndex();
      expect(index.peek('not-yet'), isNull);
    });
  });

  group('ClusterConceptIndex — memoize-while-pending', () {
    test('concurrent resolve calls share the same Future', () async {
      final index = _makeIndex();
      final cluster = _makeCluster('c1', ['s1']);
      final f1 = index.resolve(cluster, needsRawOcr: true);
      final f2 = index.resolve(cluster, needsRawOcr: true);
      // Same Future identity while in-flight.
      expect(identical(f1, f2), isTrue);
      await f1;
    });
  });

  group('ClusterConceptIndex — invalidation', () {
    test('invalidate drops concept entries', () async {
      final index = _makeIndex();
      final cluster = _makeCluster('c1', ['s1']);
      await index.resolve(cluster, needsRawOcr: true);
      expect(index.peek('c1'), isNotNull);
      index.invalidate({'c1'});
      expect(index.peek('c1'), isNull);
    });

    test('stroke checksum change triggers re-resolve', () async {
      final index = _makeIndex();
      final c1 = _makeCluster('c1', ['s1', 's2']);
      await index.resolve(c1, needsRawOcr: true);
      // Seed a value to detect re-resolve clearing it.
      index.seed(ClusterConcept(
        clusterId: 'c1',
        rawOcr: 'old-raw',
        strokeChecksum: 999, // intentionally wrong
      ));
      final c1Updated = _makeCluster('c1', ['s1', 's2', 's3']);
      final concept = await index.resolve(c1Updated, needsRawOcr: true);
      // strokeChecksum mismatch → derived fields wiped.
      expect(concept.rawOcr, isNot('old-raw'));
    });
  });

  group('ClusterConceptIndex — cross-feature avoid', () {
    test('records and replays recent questions', () {
      final index = _makeIndex();
      index.recordQuestionAsked('c1', 'What is F=ma?', AskedBy.exam);
      index.recordQuestionAsked('c1', 'Spiega l\'inerzia', AskedBy.socratic);
      final recent = index.recentQuestionsFor('c1');
      // Most-recent first.
      expect(recent.first, contains('inerzia'));
      expect(recent, hasLength(2));
    });

    test('ring buffer caps at 8 entries per cluster', () {
      final index = _makeIndex();
      for (int i = 0; i < 12; i++) {
        index.recordQuestionAsked('c1', 'Q$i', AskedBy.socratic);
      }
      final recent = index.recentQuestionsFor('c1');
      expect(recent, hasLength(8));
      // Oldest 4 evicted; the most-recent (Q11) is at position 0.
      expect(recent.first, 'Q11');
      expect(recent.last, 'Q4');
    });

    test('empty question is ignored', () {
      final index = _makeIndex();
      index.recordQuestionAsked('c1', '   ', AskedBy.exam);
      expect(index.recentQuestionsFor('c1'), isEmpty);
    });

    test('cross-cluster isolation', () {
      final index = _makeIndex();
      index.recordQuestionAsked('c1', 'A', AskedBy.exam);
      index.recordQuestionAsked('c2', 'B', AskedBy.exam);
      expect(index.recentQuestionsFor('c1'), ['A']);
      expect(index.recentQuestionsFor('c2'), ['B']);
    });
  });

  group('ClusterConceptIndex — FSRS lookup', () {
    test('srsFor returns null when concept has no entities', () {
      final index = _makeIndex();
      index.seed(ClusterConcept(clusterId: 'c1'));
      expect(index.srsFor('c1'), isNull);
    });

    test('srsFor returns first matching SRS card', () {
      final card = SrsCardData.newCard();
      final index = _makeIndex(schedule: {'Newton': card});
      index.seed(ClusterConcept(
        clusterId: 'c1',
        concepts: ['Newton', 'Inerzia'],
      ));
      expect(index.srsFor('c1'), same(card));
    });

    test('srsFor returns null when no concept matches schedule', () {
      final index = _makeIndex(schedule: {});
      index.seed(ClusterConcept(
        clusterId: 'c1',
        concepts: ['Schrodinger'],
      ));
      expect(index.srsFor('c1'), isNull);
    });
  });

  group('ClusterConceptIndex — bestLabel / bestPromptSource', () {
    test('bestLabel falls back through title → cleaned → raw', () {
      final c1 = ClusterConcept(clusterId: 'a', rawOcr: 'raw');
      expect(c1.bestLabel, 'raw');
      c1.cleanedOcr = 'clean';
      expect(c1.bestLabel, 'clean');
      c1.title = 'Title';
      expect(c1.bestLabel, 'Title');
    });

    test('bestPromptSource ignores title, prefers cleaned over raw', () {
      final c1 = ClusterConcept(clusterId: 'a', rawOcr: 'raw');
      expect(c1.bestPromptSource, 'raw');
      c1.cleanedOcr = 'clean';
      expect(c1.bestPromptSource, 'clean');
      c1.title = 'Title';
      // Title is a label, not a content source — still 'clean'.
      expect(c1.bestPromptSource, 'clean');
    });

    test('bestLabel returns empty string when all fields null', () {
      final c1 = ClusterConcept(clusterId: 'a');
      expect(c1.bestLabel, '');
      expect(c1.bestPromptSource, isNull);
    });
  });

  group('ClusterConcept — JSON round-trip', () {
    test('toJson / fromJson preserves all fields', () {
      final original = ClusterConcept(
        clusterId: 'c1',
        rawOcr: 'raw',
        cleanedOcr: 'clean',
        title: 'Title',
        topic: 'Topic',
        concepts: ['Newton', 'Inerzia'],
        sourceVersion: 3,
        strokeChecksum: 12345,
      );
      final json = original.toJson();
      final restored = ClusterConcept.fromJson(json);
      expect(restored.clusterId, 'c1');
      expect(restored.rawOcr, 'raw');
      expect(restored.cleanedOcr, 'clean');
      expect(restored.title, 'Title');
      expect(restored.topic, 'Topic');
      expect(restored.concepts, ['Newton', 'Inerzia']);
      expect(restored.sourceVersion, 3);
      expect(restored.strokeChecksum, 12345);
    });
  });

  group('ClusterConceptIndex — cleanedOcr eligibility (Primalele bug)', () {
    test('Single-stroke cluster with long rawOcr → cleanOcrItalian fires',
        () async {
      // Device bug 2026-05-10: user wrote "prima legge" in 1-2 long
      // cursive strokes. MyScript fused it into "Primalele". The
      // ≥3-strokes-only rule skipped cleanup → garbled anchor in UI.
      final fake = FakeGeminiProvider();
      fake.cleanOcrItalianOverride = (raw) =>
          raw == 'Primalele' ? 'prima legge' : raw;
      final index = _makeIndex(provider: fake);
      addTearDown(index.dispose);

      final cluster = _makeCluster('c1', ['s1']); // ONE stroke
      index.seed(ClusterConcept(
        clusterId: 'c1',
        rawOcr: 'Primalele', // 9 chars → ≥5 char fallback fires
        strokeChecksum: Object.hashAll(['s1']),
      ));

      final concept = await index.resolve(cluster, needsCleanedOcr: true);
      expect(concept.cleanedOcr, 'prima legge',
          reason: 'length-based fallback must trigger cleanup on long OCR');
      expect(fake.cleanOcrItalianCalls, 1);
    });

    test('Single-stroke cluster with short rawOcr → cleanup skipped',
        () async {
      // "io" / "à" / single short tokens are still risky to LLM-correct.
      final fake = FakeGeminiProvider();
      final index = _makeIndex(provider: fake);
      addTearDown(index.dispose);

      final cluster = _makeCluster('c1', ['s1']);
      index.seed(ClusterConcept(
        clusterId: 'c1',
        rawOcr: 'io', // 2 chars, below threshold
        strokeChecksum: Object.hashAll(['s1']),
      ));

      final concept = await index.resolve(cluster, needsCleanedOcr: true);
      expect(concept.cleanedOcr, 'io',
          reason: 'short raw OCR falls through, cached as-is');
      expect(fake.cleanOcrItalianCalls, 0,
          reason: 'no cleanup call for short single-stroke clusters');
    });

    test('3+ strokes still triggers cleanup regardless of length', () async {
      final fake = FakeGeminiProvider();
      fake.cleanOcrItalianOverride = (raw) => 'cleaned';
      final index = _makeIndex(provider: fake);
      addTearDown(index.dispose);

      final cluster = _makeCluster('c1', ['s1', 's2', 's3']);
      index.seed(ClusterConcept(
        clusterId: 'c1',
        rawOcr: 'abc', // would be skipped by length rule, but stroke count saves it
        strokeChecksum: Object.hashAll(['s1', 's2', 's3']),
      ));

      final concept = await index.resolve(cluster, needsCleanedOcr: true);
      expect(concept.cleanedOcr, 'cleaned');
      expect(fake.cleanOcrItalianCalls, 1);
    });
  });

  group('ClusterConceptIndex — title generation', () {
    test('Short text bypass: ≤3 words returns capitalized directly (no AI call)',
        () async {
      final fake = FakeGeminiProvider();
      final index = _makeIndex(provider: fake);
      addTearDown(index.dispose);

      final cluster = _makeCluster('c1', ['s1']);
      index.seed(ClusterConcept(
        clusterId: 'c1',
        rawOcr: 'legge inerzia', // 2 words → bypass
        strokeChecksum: Object.hashAll(['s1']),
      ));

      final concept = await index.resolve(cluster, needsTitle: true);
      expect(concept.title, 'Legge Inerzia');
      // No askAtlas call should have fired.
      expect(fake.askAtlasPrompts, isEmpty);
    });

    test('Long text triggers AI call and stores cleaned title', () async {
      // 2026-05-12: title generation now uses askFreeText (not askAtlas)
      // to bypass the canvas-action system prompt that was making Gemini
      // emit meta-commentary in the `spiegazione` field.
      final fake = FakeGeminiProvider();
      fake.askFreeTextResponse = '2ª Legge Newton F=ma';
      final index = _makeIndex(provider: fake);
      addTearDown(index.dispose);

      final cluster = _makeCluster('c1', ['s1']);
      index.seed(ClusterConcept(
        clusterId: 'c1',
        rawOcr:
            'Seconda legge di Newton F=ma forza accelerazione massa esempio applicato a un corpo rigido in moto rettilineo',
        strokeChecksum: Object.hashAll(['s1']),
      ));

      final concept = await index.resolve(cluster, needsTitle: true);
      expect(concept.title, '2ª Legge Newton F=ma');
      expect(fake.askFreeTextPrompts, hasLength(1));
      expect(fake.askFreeTextPrompts.first, contains('Seconda legge'));
    });

    test('Title is cached: second resolve does NOT re-fire askFreeText',
        () async {
      final fake = FakeGeminiProvider();
      fake.askFreeTextResponse = 'Entropia';
      final index = _makeIndex(provider: fake);
      addTearDown(index.dispose);

      final cluster = _makeCluster('c1', ['s1']);
      index.seed(ClusterConcept(
        clusterId: 'c1',
        rawOcr:
            'termodinamica entropia secondo principio universo aumento disordine sistema isolato spontaneo',
        strokeChecksum: Object.hashAll(['s1']),
      ));

      await index.resolve(cluster, needsTitle: true);
      await index.resolve(cluster, needsTitle: true);
      expect(fake.askFreeTextPrompts, hasLength(1),
          reason: 'second resolve must hit cache');
    });

    test('Sentence-disguised-as-title is rejected → title remains null',
        () async {
      final fake = FakeGeminiProvider();
      fake.askFreeTextResponse = 'Ho estratto il concetto principale dagli appunti';
      final index = _makeIndex(provider: fake);
      addTearDown(index.dispose);

      final cluster = _makeCluster('c1', ['s1']);
      index.seed(ClusterConcept(
        clusterId: 'c1',
        rawOcr:
            'lungo testo per non bypassare lo short-text path con almeno quattro parole significative',
        strokeChecksum: Object.hashAll(['s1']),
      ));

      final concept = await index.resolve(cluster, needsTitle: true);
      expect(concept.title, isNull,
          reason: 'sentence starters must be filtered out');
    });

    test('setTitle (write-through from Semantic Titles) is preserved',
        () async {
      final index = _makeIndex();
      addTearDown(index.dispose);

      // Simulate Semantic Titles' dual-write helper depositing a title.
      index.setTitle('c1', 'Cinematica', sourceText: 'velocita accelerazione');

      final cluster = _makeCluster('c1', ['s1']);
      // resolve(needsTitle: true) should NOT regenerate — it already has one.
      final concept = await index.resolve(cluster, needsTitle: true);
      expect(concept.title, 'Cinematica');
    });
  });

  group('ClusterConceptIndex — bulkGenerateTitles (no zoom-out path)', () {
    test('returns immediately when provider is null', () async {
      final index = _makeIndex(); // no provider
      addTearDown(index.dispose);
      await index.bulkGenerateTitles({'c1': 'lungo testo da analizzare per il titolo'});
      // No exception, no title written.
      expect(index.peek('c1')?.title, isNull);
    });

    test('skips clusters that already have a title', () async {
      final fake = FakeGeminiProvider();
      fake.askFreeTextResponse = 'Should-not-be-used';
      final index = _makeIndex(provider: fake);
      addTearDown(index.dispose);
      index.setTitle('c1', 'Existing Title');
      await index.bulkGenerateTitles({'c1': 'qualche testo'});
      expect(index.peek('c1')?.title, 'Existing Title');
      // No AI call because everything was filtered out.
      expect(fake.askFreeTextPrompts, isEmpty);
    });

    test('single-cluster short text uses bypass (no AI call)', () async {
      final fake = FakeGeminiProvider();
      final index = _makeIndex(provider: fake);
      addTearDown(index.dispose);
      await index.bulkGenerateTitles({'c1': 'forza newton'}); // 2 words
      expect(index.peek('c1')?.title, 'Forza Newton');
      expect(fake.askFreeTextPrompts, isEmpty);
    });

    test('multi-cluster batch fires single AI call', () async {
      final fake = FakeGeminiProvider();
      // bulkGenerateTitles parses askFreeText output as JSON
      // `{"titoli": {...}}` — same shape the prompt requests.
      fake.askFreeTextResponse =
          '{"titoli": {"1": "1ª Legge Newton", "2": "Termodinamica"}}';
      final index = _makeIndex(provider: fake);
      addTearDown(index.dispose);
      await index.bulkGenerateTitles({
        'c1': 'prima legge di Newton inerzia forza nulla movimento rettilineo',
        'c2': 'primo principio termodinamica energia conservazione sistema chiuso',
      });
      expect(index.peek('c1')?.title, '1ª Legge Newton');
      expect(index.peek('c2')?.title, 'Termodinamica');
      expect(fake.askFreeTextPrompts, hasLength(1));
      expect(fake.askFreeTextPrompts.first, contains('prima legge'));
    });

    test('explanation fallback when rawJson missing', () async {
      final fake = FakeGeminiProvider();
      // Model returned plain newline-separated titles (no JSON).
      // The parser falls back to line-per-cluster matching.
      fake.askFreeTextResponse = 'Forza\nMassa\n';
      final index = _makeIndex(provider: fake);
      addTearDown(index.dispose);
      await index.bulkGenerateTitles({
        'c1': 'lungo testo prima cluster per forzare il batch path Multi',
        'c2': 'altro lungo testo secondo cluster per forzare batch path Multi',
      });
      expect(index.peek('c1')?.title, 'Forza');
      expect(index.peek('c2')?.title, 'Massa');
    });

    test('Atlas failure does not crash (silent fallback)', () async {
      final fake = FakeGeminiProvider();
      fake.askAtlasResponse = const AtlasResponse(actions: [], rawJson: null);
      final index = _makeIndex(provider: fake);
      addTearDown(index.dispose);
      // Empty response → no titles written, no exception.
      await index.bulkGenerateTitles({
        'c1': 'lungo testo da analizzare per generare un titolo significativo',
        'c2': 'altro lungo testo da analizzare per generare un titolo distinto',
      });
      expect(index.peek('c1')?.title, isNull);
      expect(index.peek('c2')?.title, isNull);
    });
  });

  group('ClusterConceptIndex — topic grouping cache (B)', () {
    test('cachedTopicGrouping returns null on miss', () {
      final index = _makeIndex();
      addTearDown(index.dispose);
      expect(index.cachedTopicGrouping(['a', 'b']), isNull);
    });

    test('cacheTopicGrouping + cachedTopicGrouping round-trip', () {
      final index = _makeIndex();
      addTearDown(index.dispose);
      final groups = [
        (topic: 'Newton', clusterIds: ['c1', 'c2']),
        (topic: 'Termodinamica', clusterIds: ['c3']),
      ];
      index.cacheTopicGrouping(['c1', 'c2', 'c3'], groups);
      final hit = index.cachedTopicGrouping(['c1', 'c2', 'c3']);
      expect(hit, isNotNull);
      expect(hit!.length, 2);
      expect(hit[0].topic, 'Newton');
    });

    test('cache hit is order-independent', () {
      final index = _makeIndex();
      addTearDown(index.dispose);
      index.cacheTopicGrouping(['c1', 'c2'], [
        (topic: 'X', clusterIds: ['c1', 'c2']),
      ]);
      // Different iteration order should still hit.
      expect(index.cachedTopicGrouping(['c2', 'c1']), isNotNull);
    });

    test('invalidate clears the topic grouping cache', () {
      final index = _makeIndex();
      addTearDown(index.dispose);
      index.cacheTopicGrouping(['c1'], [
        (topic: 'X', clusterIds: ['c1']),
      ]);
      expect(index.cachedTopicGrouping(['c1']), isNotNull);
      index.invalidate({'c1'});
      expect(index.cachedTopicGrouping(['c1']), isNull);
    });
  });

  group('ClusterConceptIndex — setTopic (Atlas Exam batch grouping)', () {
    test('setTopic seeds a fresh entry when none exists', () {
      final index = _makeIndex();
      addTearDown(index.dispose);
      index.setTopic('c1', 'Le Leggi di Newton');
      expect(index.peek('c1')?.topic, 'Le Leggi di Newton');
    });

    test('setTopic updates the topic of an existing entry', () {
      final index = _makeIndex();
      addTearDown(index.dispose);
      index.seed(ClusterConcept(clusterId: 'c1', topic: 'Vecchio'));
      index.setTopic('c1', 'Nuovo');
      expect(index.peek('c1')?.topic, 'Nuovo');
    });

    test('setTopic ignores empty input', () {
      final index = _makeIndex();
      addTearDown(index.dispose);
      index.seed(ClusterConcept(clusterId: 'c1', topic: 'Existing'));
      index.setTopic('c1', '   ');
      expect(index.peek('c1')?.topic, 'Existing');
    });

    test('setTopic bumps sourceVersion', () {
      final index = _makeIndex();
      addTearDown(index.dispose);
      index.seed(ClusterConcept(clusterId: 'c1', sourceVersion: 5));
      index.setTopic('c1', 'Nuovo');
      expect(index.peek('c1')?.sourceVersion, 6);
    });
  });

  group('ClusterConceptIndex — upsertConcepts (Ghost Map path)', () {
    test('upsertConcepts seeds a fresh concept entry', () {
      final index = _makeIndex();
      addTearDown(index.dispose);
      index.upsertConcepts('c1', ['Mitocondri', 'ATP']);
      expect(index.peek('c1')?.concepts, ['Mitocondri', 'ATP']);
    });

    test('upsertConcepts replaces (caller pre-merges)', () {
      final index = _makeIndex();
      addTearDown(index.dispose);
      index.seed(ClusterConcept(
        clusterId: 'c1',
        concepts: ['Stale'],
      ));
      index.upsertConcepts('c1', ['Fresh1', 'Fresh2']);
      expect(index.peek('c1')?.concepts, ['Fresh1', 'Fresh2']);
    });

    test('upsertConcepts ignores empty list', () {
      final index = _makeIndex();
      addTearDown(index.dispose);
      index.seed(ClusterConcept(
        clusterId: 'c1',
        concepts: ['Existing'],
      ));
      index.upsertConcepts('c1', const []);
      expect(index.peek('c1')?.concepts, ['Existing']);
    });

    test('upsertConcepts bumps sourceVersion (cache invalidation signal)', () {
      final index = _makeIndex();
      addTearDown(index.dispose);
      index.seed(ClusterConcept(
        clusterId: 'c1',
        sourceVersion: 5,
      ));
      index.upsertConcepts('c1', ['New']);
      expect(index.peek('c1')?.sourceVersion, 6);
    });
  });

  // ─── Device 2026-05-12: title language-drift guard ─────────────────────
  // Path C (resolve(needsTitle: true)) → _generateTitle → _cleanGeneratedTitle.
  // Drift detection delegates to socraticLanguageDriftsFromSource which
  // uses the shared language-signature detector (ai_provider.dart).
  // The detector is CONSERVATIVE on short ambiguous titles (returns
  // 'unknown' when < 2 function-word matches) — this is intentional:
  // the EN-master prompt itself now prevents drift at the source, so the
  // detector only needs to catch UNAMBIGUOUS drift (full EN sentence on
  // IT source). Short ambiguous titles like "Newtons Laws" (just 2 proper
  // nouns) pass through; the system prompt diet is the primary defense.
  group('ClusterConceptIndex — title language-drift guard (Phase 1.3)', () {
    setUp(() {
      // Force target lang IT for these tests; device locale default in
      // headless tests is 'en' which would mark EN titles as legitimate
      // (cross-language). The scenarios under test assume target=IT.
      AiLanguagePreference.setForTests('it');
    });
    tearDown(() {
      AiLanguagePreference.resetForTests();
    });

    test('IT source + clear EN sentence title → drift rejected', () async {
      // A FULL English sentence as title on IT-target session — caught.
      final fake = FakeGeminiProvider()
        ..askFreeTextResponse = "These are the laws that Newton stated"; // EN
      final stroke = _makeStroke('s1', DateTime(2026, 5, 12));
      final index = _makeIndex(
        strokeMap: {'s1': stroke},
        provider: fake,
        language: 'Italian',
      );
      addTearDown(index.dispose);
      final cluster = _makeCluster('c1', ['s1']);
      index.seed(ClusterConcept(
        clusterId: 'c1',
        rawOcr: 'LEGGI DI NEWTON PRIMA CORPO A RIPOSO SECONDA LEGGE',
      ));
      await index.resolve(cluster, needsTitle: true);
      final concept = index.peek('c1');
      expect(concept, isNotNull);
      expect(concept!.title, isNull,
          reason: 'Clear EN sentence on IT target must not become title');
    });

    test('IT source + IT title → title accepted', () async {
      final fake = FakeGeminiProvider()
        ..askFreeTextResponse = 'Leggi di Newton'; // IT — valid
      final stroke = _makeStroke('s1', DateTime(2026, 5, 12));
      final index = _makeIndex(
        strokeMap: {'s1': stroke},
        provider: fake,
        language: 'Italian',
      );
      addTearDown(index.dispose);
      final cluster = _makeCluster('c1', ['s1']);
      index.seed(ClusterConcept(
        clusterId: 'c1',
        rawOcr: 'LEGGI DI NEWTON PRIMA CORPO A RIPOSO',
      ));
      await index.resolve(cluster, needsTitle: true);
      expect(index.peek('c1')?.title, 'Leggi di Newton');
    });
  });

  // ── Sprint F.1 (2026-05-13 PM) — stale title cache on lang change ────────
  // Bug: user changes AiLanguagePreference EN→IT mid-session, but cached
  // titles like "Newton's First Law" (EN) remain in the index because
  // _kTitlePromptVersion bump catches cross-version invalidation, NOT
  // cross-language. Fix: _satisfies() returns false when cached title
  // language doesn't match the OCR source language (drift detected).
  // This forces _doResolve to regenerate the title in the new target lang.
  group('ClusterConceptIndex — stale title cache invalidation (Sprint F.1)',
      () {
    tearDown(() => AiLanguagePreference.resetForTests());

    test('Cached EN title on IT-source cluster → regenerated when needed',
        () async {
      // Setup: user is currently on IT preference (would mean they want
      // IT output). Cluster has IT OCR + cached title "Newton's First Law"
      // (EN — stale from when preference was EN).
      AiLanguagePreference.setForTests('it');

      final fake = FakeGeminiProvider()..askFreeTextResponse = 'Leggi di Newton';
      final stroke = _makeStroke('s1', DateTime(2026, 5, 13));
      final index = _makeIndex(
        provider: fake,
        language: 'Italian',
        strokeMap: {'s1': stroke},
      );
      addTearDown(index.dispose);
      final cluster = _makeCluster('c1', ['s1']);

      // Seed the cache with an EN title on IT-source OCR — simulates the
      // stale-cache state observed on device after preference change.
      // Set titlePromptVersion to a high value so the VERSION invalidation
      // path doesn't kick in — we want to isolate the DRIFT detection.
      index.seed(ClusterConcept(
        clusterId: 'c1',
        rawOcr: 'LEGGI DI NEWTON PRIMA CORPO A RIPOSO',
        cleanedOcr: 'LEGGI DI NEWTON PRIMA CORPO A RIPOSO',
        title: "Newton's First Law", // stale EN title
        titlePromptVersion: 999, // bypass version invalidation
        cleanedOcrPromptVersion: 999, // bypass version invalidation
        sourceVersion: 999,
      ));

      // Trigger a resolve with needsTitle=true. The _satisfies guard
      // should detect the language drift (title=EN, source=IT) and
      // return false → _doResolve regenerates → new title from fake.
      final resolved = await index.resolve(cluster, needsTitle: true);
      expect(resolved.title, 'Leggi di Newton',
          reason: 'Title must be regenerated in IT (current preference + OCR '
              'language), not the stale EN cached value');
    });

    test(
        'Cached IT title on IT-source cluster → preserved (no false-positive '
        'invalidation)', () async {
      AiLanguagePreference.setForTests('it');

      // Provider should NOT be invoked: cache hit, satisfies as-is.
      final fake = FakeGeminiProvider()..askFreeTextResponse = 'SHOULD NOT FIRE';
      final index = _makeIndex(provider: fake, language: 'Italian');
      final cluster = _makeCluster('c1', ['s1']);

      index.seed(ClusterConcept(
        clusterId: 'c1',
        rawOcr: 'LEGGI DI NEWTON PRIMA CORPO A RIPOSO',
        cleanedOcr: 'LEGGI DI NEWTON PRIMA CORPO A RIPOSO',
        title: 'Leggi di Newton', // legitimate IT title
        titlePromptVersion: 999, // bypass version invalidation
        cleanedOcrPromptVersion: 999, // bypass version invalidation
        sourceVersion: 999,
      ));

      final resolved = await index.resolve(cluster, needsTitle: true);
      expect(resolved.title, 'Leggi di Newton',
          reason: 'IT title on IT source → no drift → cache hit preserves');
    });
  });
}
