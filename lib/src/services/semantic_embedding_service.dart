// ============================================================================
// 🧠 SEMANTIC EMBEDDING SERVICE — On-device sentence embeddings (A7)
//
// Specifica: A7-01 → A7-10
//
// Provides on-device semantic embeddings using MiniLM-L6-v2 via ONNX
// Runtime. Converts text to 384-dimensional vectors for semantic
// similarity comparisons — enabling offline, private, zero-cost
// cross-domain bridge detection (Passo 9).
//
// ARCHITECTURE:
//   - Pluggable engine interface (same pattern as InkRecognitionEngine)
//   - Default: MiniLmEmbeddingEngine (ONNX, ~22MB model)
//   - Fallback: LlmEmbeddingEngine (remote API, existing behavior)
//   - Cosine similarity for bridge detection
//
// MODEL:
//   - sentence-transformers/all-MiniLM-L6-v2
//   - 384 dimensions, INT8 quantized (~22MB)
//   - Asset path: assets/models/minilm/encoder.onnx
//
// THREAD SAFETY: Inference can run in a separate isolate.
// ============================================================================

import 'dart:math';
import 'dart:typed_data';

/// 🧠 Embedding result: a concept ID + its vector representation.
class SemanticEmbedding {
  /// Identifier for the embedded content (e.g., clusterId, nodeId).
  final String contentId;

  /// The embedding vector (384 dimensions for MiniLM).
  final Float64List vector;

  /// Original text that was embedded (for debug/display).
  final String sourceText;

  const SemanticEmbedding({
    required this.contentId,
    required this.vector,
    required this.sourceText,
  });

  /// L2 norm of the vector (pre-computed for fast cosine similarity).
  double get norm {
    double sum = 0;
    for (int i = 0; i < vector.length; i++) {
      sum += vector[i] * vector[i];
    }
    return sqrt(sum);
  }
}

/// 🧠 A semantic bridge candidate found by embedding comparison.
class SemanticBridgeCandidate {
  /// Source content embedding.
  final SemanticEmbedding source;

  /// Target content embedding.
  final SemanticEmbedding target;

  /// Cosine similarity score (0.0–1.0).
  final double similarity;

  const SemanticBridgeCandidate({
    required this.source,
    required this.target,
    required this.similarity,
  });
}

// =============================================================================
// EMBEDDING ENGINE INTERFACE
// =============================================================================

/// 🧠 Abstract embedding engine (pluggable backend).
///
/// Implementations:
///   - [MiniLmEmbeddingEngine]: on-device ONNX (default)
///   - Host app can provide a remote embedding engine as fallback
abstract class EmbeddingEngine {
  /// Whether the engine is available on this platform.
  bool get isAvailable;

  /// Whether the model is loaded and ready.
  bool get isReady;

  /// Embedding dimension (384 for MiniLM-L6-v2).
  int get dimension;

  /// Initialize the engine (download/load model).
  Future<void> init();

  /// Embed a single text string.
  ///
  /// Returns a vector of [dimension] floats.
  Future<Float64List> embed(String text);

  /// Embed multiple texts in batch (more efficient than individual calls).
  Future<List<Float64List>> embedBatch(List<String> texts);

  /// Release resources.
  void dispose();
}

// =============================================================================
// MINILM EMBEDDING ENGINE (ONNX)
// =============================================================================

/// 🧠 MiniLM-L6-v2 on-device embedding engine via ONNX Runtime.
///
/// Uses the same ONNX Runtime infrastructure as OnnxLatexRecognizer.
/// Model: sentence-transformers/all-MiniLM-L6-v2 (INT8, ~22MB).
///
/// Asset path: `assets/models/minilm/encoder.onnx`
///
/// NOTE: The actual ONNX inference is delegated to the native platform
/// via MethodChannel (same pattern as MyScriptInkEngine). This class
/// provides the Dart-side API and tokenization.
class MiniLmEmbeddingEngine implements EmbeddingEngine {
  bool _isAvailable = false;
  bool _isReady = false;

  /// Model asset path.
  static const String modelPath = 'assets/models/minilm/encoder.onnx';

  @override
  bool get isAvailable => _isAvailable;

  @override
  bool get isReady => _isReady;

  @override
  int get dimension => 384;

  @override
  Future<void> init() async {
    // In production, this would:
    // 1. Check if the ONNX model file exists in assets
    // 2. Load via OrtSession.fromBuffer (like OnnxLatexRecognizer)
    // 3. Set _isAvailable = true, _isReady = true
    //
    // For now, mark as unavailable — the service will fall back to
    // the LLM-based bridge detection (existing behavior).
    _isAvailable = false;
    _isReady = false;
  }

  @override
  Future<Float64List> embed(String text) async {
    if (!_isReady) {
      throw StateError('MiniLmEmbeddingEngine not initialized');
    }
    // In production: tokenize → run ONNX → mean pooling → normalize
    return Float64List(dimension);
  }

  @override
  Future<List<Float64List>> embedBatch(List<String> texts) async {
    // In production: batch tokenize → single ONNX call → split results
    final results = <Float64List>[];
    for (final text in texts) {
      results.add(await embed(text));
    }
    return results;
  }

  @override
  void dispose() {
    _isReady = false;
  }
}

// =============================================================================
// DETERMINISTIC MOCK ENGINE (TESTING)
// =============================================================================

/// 🧪 Deterministic mock embedding engine for testing.
///
/// Generates reproducible 384D vectors from text content using a
/// hash-based approach. This allows testing the full embedding pipeline
/// (bridge detection, similarity search) without the ONNX model.
///
/// Usage (in tests):
/// ```dart
/// final service = SemanticEmbeddingService.instance;
/// service.setEngine(DeterministicMockEmbeddingEngine());
/// await service.init();
/// // Now service.isAvailable == true, service.isReady == true
/// ```
class DeterministicMockEmbeddingEngine implements EmbeddingEngine {
  @override
  bool get isAvailable => true;

  @override
  bool get isReady => true;

  @override
  int get dimension => 384;

  @override
  Future<void> init() async {}

  @override
  Future<Float64List> embed(String text) async {
    // Deterministic: same text → same vector.
    final hash = text.hashCode;
    final rng = Random(hash);
    final vec = Float64List(dimension);
    double norm = 0;
    for (int i = 0; i < dimension; i++) {
      vec[i] = rng.nextDouble() * 2 - 1; // [-1, 1]
      norm += vec[i] * vec[i];
    }
    // L2-normalize
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
  void dispose() {}
}

// =============================================================================
// SEMANTIC EMBEDDING SERVICE (ORCHESTRATOR)
// =============================================================================

/// 🧠 Semantic Embedding Service (A7).
///
/// Orchestrates embedding generation and semantic bridge detection.
/// Uses pluggable [EmbeddingEngine] backend (default: MiniLM ONNX).
///
/// Usage:
/// ```dart
/// final service = SemanticEmbeddingService.instance;
/// await service.init();
///
/// if (service.isAvailable) {
///   final bridges = await service.findBridges(
///     sourceTexts: {'bio_1': 'Respirazione cellulare...'},
///     targetTexts: {'chem_1': 'Fosforilazione ossidativa...'},
///     minSimilarity: 0.75,
///   );
///   for (final bridge in bridges) {
///     print('Bridge: ${bridge.similarity}');
///   }
/// }
/// ```
class SemanticEmbeddingService {
  SemanticEmbeddingService._();
  static final SemanticEmbeddingService instance = SemanticEmbeddingService._();

  /// The active embedding engine.
  EmbeddingEngine _engine = MiniLmEmbeddingEngine();

  /// Swap engine at runtime.
  void setEngine(EmbeddingEngine engine) {
    _engine.dispose();
    _engine = engine;
  }

  /// Whether the service is available.
  bool get isAvailable => _engine.isAvailable;

  /// Whether the model is loaded.
  bool get isReady => _engine.isReady;

  /// Embedding dimension.
  int get dimension => _engine.dimension;

  /// Initialize the engine.
  Future<void> init() => _engine.init();

  // ── Single Embedding ────────────────────────────────────────────────────

  /// Embed a single text and return a [SemanticEmbedding].
  Future<SemanticEmbedding> embedText(String contentId, String text) async {
    final vector = await _engine.embed(text);
    return SemanticEmbedding(
      contentId: contentId,
      vector: vector,
      sourceText: text,
    );
  }

  /// Embed multiple texts in batch.
  Future<List<SemanticEmbedding>> embedBatch(
    Map<String, String> contentTexts,
  ) async {
    final ids = contentTexts.keys.toList();
    final texts = contentTexts.values.toList();
    final vectors = await _engine.embedBatch(texts);

    return List.generate(ids.length, (i) => SemanticEmbedding(
      contentId: ids[i],
      vector: vectors[i],
      sourceText: texts[i],
    ));
  }

  // ── Bridge Detection ──────────────────────────────────────────────────

  /// Find semantic bridges between two sets of content.
  ///
  /// Computes pairwise cosine similarity between source and target
  /// embeddings, returning pairs that exceed [minSimilarity].
  ///
  /// [sourceTexts]: contentId → text for source zone.
  /// [targetTexts]: contentId → text for target zone.
  /// [minSimilarity]: threshold (default: 0.75).
  /// [maxResults]: max number of bridges to return.
  Future<List<SemanticBridgeCandidate>> findBridges({
    required Map<String, String> sourceTexts,
    required Map<String, String> targetTexts,
    double minSimilarity = 0.75,
    int maxResults = 5,
  }) async {
    if (!_engine.isReady) return [];

    // Embed both sides.
    final sourceEmbeddings = await embedBatch(sourceTexts);
    final targetEmbeddings = await embedBatch(targetTexts);

    // Compute pairwise cosine similarity.
    final candidates = <SemanticBridgeCandidate>[];

    for (final src in sourceEmbeddings) {
      for (final tgt in targetEmbeddings) {
        final sim = cosineSimilarity(src.vector, tgt.vector);
        if (sim >= minSimilarity) {
          candidates.add(SemanticBridgeCandidate(
            source: src,
            target: tgt,
            similarity: sim,
          ));
        }
      }
    }

    // Sort by similarity (descending) and cap at maxResults.
    candidates.sort((a, b) => b.similarity.compareTo(a.similarity));
    return candidates.take(maxResults).toList();
  }

  // ── Math Utilities ────────────────────────────────────────────────────

  /// Cosine similarity between two vectors.
  ///
  /// cos(a, b) = (a · b) / (||a|| × ||b||)
  ///
  /// Returns 0.0 if either vector is zero.
  static double cosineSimilarity(Float64List a, Float64List b) {
    if (a.length != b.length) return 0.0;

    double dot = 0, normA = 0, normB = 0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    final denom = sqrt(normA) * sqrt(normB);
    if (denom == 0) return 0.0;
    return dot / denom;
  }

  /// Dispose the engine.
  void dispose() {
    _engine.dispose();
  }
}
