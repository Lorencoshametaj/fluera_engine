// ============================================================================
// 🧪 UNIT TESTS — Semantic Embedding Service (A7)
// ============================================================================

import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/services/semantic_embedding_service.dart';

/// Test embedding engine that returns deterministic vectors.
///
/// Maps each text to a vector based on a simple hash, so identical texts
/// produce identical vectors and similar texts produce similar vectors.
class _TestEmbeddingEngine implements EmbeddingEngine {
  bool _ready = false;

  @override
  bool get isAvailable => true;

  @override
  bool get isReady => _ready;

  @override
  int get dimension => 384;

  @override
  Future<void> init() async {
    _ready = true;
  }

  @override
  Future<Float64List> embed(String text) async {
    // Deterministic pseudo-random vector from text hash.
    final vec = Float64List(dimension);
    final rng = Random(text.hashCode);
    double norm = 0;
    for (int i = 0; i < dimension; i++) {
      vec[i] = rng.nextDouble() - 0.5;
      norm += vec[i] * vec[i];
    }
    // Normalize to unit vector.
    norm = sqrt(norm);
    if (norm > 0) {
      for (int i = 0; i < dimension; i++) {
        vec[i] /= norm;
      }
    }
    return vec;
  }

  @override
  Future<List<Float64List>> embedBatch(List<String> texts) async {
    return Future.wait(texts.map(embed));
  }

  @override
  void dispose() {
    _ready = false;
  }
}

/// Test engine that returns IDENTICAL vectors for similar texts.
class _SimilarityTestEngine implements EmbeddingEngine {
  bool _ready = false;
  final Map<String, Float64List> _overrides = {};

  @override
  bool get isAvailable => true;
  @override
  bool get isReady => _ready;
  @override
  int get dimension => 4; // Small for test clarity.

  void setVector(String text, List<double> values) {
    _overrides[text] = Float64List.fromList(values);
  }

  @override
  Future<void> init() async => _ready = true;

  @override
  Future<Float64List> embed(String text) async =>
      _overrides[text] ?? Float64List(dimension);

  @override
  Future<List<Float64List>> embedBatch(List<String> texts) async =>
      Future.wait(texts.map(embed));

  @override
  void dispose() => _ready = false;
}

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // COSINE SIMILARITY
  // ═══════════════════════════════════════════════════════════════════════════

  group('cosineSimilarity', () {
    test('identical vectors → 1.0', () {
      final a = Float64List.fromList([1, 2, 3]);
      final b = Float64List.fromList([1, 2, 3]);
      expect(SemanticEmbeddingService.cosineSimilarity(a, b), closeTo(1.0, 1e-9));
    });

    test('opposite vectors → -1.0', () {
      final a = Float64List.fromList([1, 0, 0]);
      final b = Float64List.fromList([-1, 0, 0]);
      expect(SemanticEmbeddingService.cosineSimilarity(a, b), closeTo(-1.0, 1e-9));
    });

    test('orthogonal vectors → 0.0', () {
      final a = Float64List.fromList([1, 0, 0]);
      final b = Float64List.fromList([0, 1, 0]);
      expect(SemanticEmbeddingService.cosineSimilarity(a, b), closeTo(0.0, 1e-9));
    });

    test('zero vector → 0.0', () {
      final a = Float64List.fromList([1, 2, 3]);
      final b = Float64List.fromList([0, 0, 0]);
      expect(SemanticEmbeddingService.cosineSimilarity(a, b), 0.0);
    });

    test('different lengths → 0.0', () {
      final a = Float64List.fromList([1, 2]);
      final b = Float64List.fromList([1, 2, 3]);
      expect(SemanticEmbeddingService.cosineSimilarity(a, b), 0.0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SEMANTIC EMBEDDING
  // ═══════════════════════════════════════════════════════════════════════════

  group('SemanticEmbedding', () {
    test('norm computes correctly', () {
      final e = SemanticEmbedding(
        contentId: 'test',
        vector: Float64List.fromList([3, 4]),
        sourceText: 'test',
      );
      expect(e.norm, closeTo(5.0, 1e-9));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // EMBEDDING ENGINE INTERFACE
  // ═══════════════════════════════════════════════════════════════════════════

  group('TestEmbeddingEngine', () {
    late _TestEmbeddingEngine engine;

    setUp(() => engine = _TestEmbeddingEngine());
    tearDown(() => engine.dispose());

    test('not ready before init', () {
      expect(engine.isReady, isFalse);
    });

    test('ready after init', () async {
      await engine.init();
      expect(engine.isReady, isTrue);
    });

    test('dimension is 384', () {
      expect(engine.dimension, 384);
    });

    test('embed produces 384-dim vector', () async {
      await engine.init();
      final vec = await engine.embed('hello world');
      expect(vec.length, 384);
    });

    test('same text → identical vectors', () async {
      await engine.init();
      final v1 = await engine.embed('test phrase');
      final v2 = await engine.embed('test phrase');
      expect(v1, equals(v2));
    });

    test('different text → different vectors', () async {
      await engine.init();
      final v1 = await engine.embed('biology');
      final v2 = await engine.embed('chemistry');
      expect(v1, isNot(equals(v2)));
    });

    test('batch embed returns correct count', () async {
      await engine.init();
      final results = await engine.embedBatch(['a', 'b', 'c']);
      expect(results.length, 3);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SERVICE ORCHESTRATION
  // ═══════════════════════════════════════════════════════════════════════════

  group('SemanticEmbeddingService', () {
    late SemanticEmbeddingService service;
    late _TestEmbeddingEngine testEngine;

    setUp(() async {
      service = SemanticEmbeddingService.instance;
      testEngine = _TestEmbeddingEngine();
      service.setEngine(testEngine);
      await service.init();
    });

    test('embedText returns SemanticEmbedding', () async {
      final result = await service.embedText('bio_1', 'cell respiration');
      expect(result.contentId, 'bio_1');
      expect(result.vector.length, 384);
      expect(result.sourceText, 'cell respiration');
    });

    test('embedBatch returns all embeddings', () async {
      final results = await service.embedBatch({
        'bio_1': 'cell respiration',
        'chem_1': 'oxidative phosphorylation',
        'phys_1': 'thermodynamics',
      });
      expect(results.length, 3);
      expect(results[0].contentId, 'bio_1');
      expect(results[2].contentId, 'phys_1');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // BRIDGE DETECTION
  // ═══════════════════════════════════════════════════════════════════════════

  group('SemanticBridgeFinder', () {
    late SemanticEmbeddingService service;
    late _SimilarityTestEngine engine;

    setUp(() async {
      service = SemanticEmbeddingService.instance;
      engine = _SimilarityTestEngine();
      service.setEngine(engine);
      await service.init();
    });

    test('finds bridge when similarity >= threshold', () async {
      // Same direction → cosine ≈ 1.0
      engine.setVector('respirazione cellulare', [1, 0, 0, 0]);
      engine.setVector('fosforilazione ossidativa', [0.9, 0.1, 0, 0]);

      final bridges = await service.findBridges(
        sourceTexts: {'bio': 'respirazione cellulare'},
        targetTexts: {'chem': 'fosforilazione ossidativa'},
        minSimilarity: 0.9,
      );

      expect(bridges.length, 1);
      expect(bridges.first.source.contentId, 'bio');
      expect(bridges.first.target.contentId, 'chem');
      expect(bridges.first.similarity, greaterThan(0.9));
    });

    test('no bridge when similarity < threshold', () async {
      // Orthogonal → cosine ≈ 0
      engine.setVector('arte rinascimentale', [1, 0, 0, 0]);
      engine.setVector('meccanica quantistica', [0, 1, 0, 0]);

      final bridges = await service.findBridges(
        sourceTexts: {'art': 'arte rinascimentale'},
        targetTexts: {'phys': 'meccanica quantistica'},
        minSimilarity: 0.75,
      );

      expect(bridges, isEmpty);
    });

    test('maxResults caps output', () async {
      // All similar
      engine.setVector('a', [1, 0, 0, 0]);
      engine.setVector('b', [1, 0, 0, 0]);
      engine.setVector('c', [1, 0, 0, 0]);
      engine.setVector('d', [1, 0, 0, 0]);

      final bridges = await service.findBridges(
        sourceTexts: {'s1': 'a', 's2': 'b'},
        targetTexts: {'t1': 'c', 't2': 'd'},
        minSimilarity: 0.5,
        maxResults: 2,
      );

      expect(bridges.length, 2);
    });

    test('results sorted by descending similarity', () async {
      engine.setVector('src', [1, 0, 0, 0]);
      engine.setVector('close', [0.95, 0.05, 0, 0]);
      engine.setVector('far', [0.7, 0.3, 0, 0]);

      final bridges = await service.findBridges(
        sourceTexts: {'s': 'src'},
        targetTexts: {'t1': 'close', 't2': 'far'},
        minSimilarity: 0.5,
      );

      expect(bridges.length, 2);
      expect(bridges[0].similarity, greaterThan(bridges[1].similarity));
    });

    test('returns empty when engine not ready', () async {
      engine.dispose(); // Mark as not ready

      final bridges = await service.findBridges(
        sourceTexts: {'s': 'test'},
        targetTexts: {'t': 'test'},
      );

      expect(bridges, isEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // MINILM ENGINE (GRACEFUL UNAVAILABILITY)
  // ═══════════════════════════════════════════════════════════════════════════

  group('MiniLmEmbeddingEngine', () {
    test('starts unavailable (no model bundled)', () async {
      final engine = MiniLmEmbeddingEngine();
      await engine.init();
      expect(engine.isAvailable, isFalse);
      expect(engine.isReady, isFalse);
      expect(engine.dimension, 384);
      engine.dispose();
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // DETERMINISTIC MOCK ENGINE
  // ═══════════════════════════════════════════════════════════════════════════

  group('DeterministicMockEmbeddingEngine', () {
    late DeterministicMockEmbeddingEngine engine;

    setUp(() => engine = DeterministicMockEmbeddingEngine());

    test('always available and ready', () {
      expect(engine.isAvailable, isTrue);
      expect(engine.isReady, isTrue);
    });

    test('produces 384-dim vectors', () async {
      final vec = await engine.embed('test text');
      expect(vec.length, 384);
    });

    test('same text produces identical vectors', () async {
      final v1 = await engine.embed('hello world');
      final v2 = await engine.embed('hello world');
      expect(v1, equals(v2));
    });

    test('different text produces different vectors', () async {
      final v1 = await engine.embed('biology');
      final v2 = await engine.embed('chemistry');
      expect(v1, isNot(equals(v2)));
    });

    test('vectors are L2-normalized (unit length)', () async {
      final vec = await engine.embed('any text');
      double norm = 0;
      for (int i = 0; i < vec.length; i++) {
        norm += vec[i] * vec[i];
      }
      expect(sqrt(norm), closeTo(1.0, 1e-9));
    });

    test('works with SemanticEmbeddingService pipeline', () async {
      final service = SemanticEmbeddingService.instance;
      service.setEngine(engine);
      await service.init();

      expect(service.isAvailable, isTrue);
      final embedding = await service.embedText('id1', 'test content');
      expect(embedding.vector.length, 384);
    });
  });
}
