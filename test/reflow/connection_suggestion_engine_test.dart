import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/reflow/connection_suggestion_engine.dart';
import 'package:fluera_engine/src/reflow/content_cluster.dart';
import 'package:fluera_engine/src/reflow/knowledge_connection.dart';
import 'package:fluera_engine/src/drawing/models/pro_drawing_point.dart';
import 'package:fluera_engine/src/drawing/models/pro_brush_settings.dart';

void main() {
  late ConnectionSuggestionEngine engine;

  setUp(() {
    engine = ConnectionSuggestionEngine();
  });

  /// Helper: create a cluster at a given position
  ContentCluster _makeCluster(String id, double x, double y, {
    List<String> strokeIds = const [],
    List<String> textIds = const [],
    double size = 100,
  }) {
    return ContentCluster(
      id: id,
      strokeIds: strokeIds,
      textIds: textIds,
      bounds: Rect.fromCenter(center: Offset(x, y), width: size, height: size),
      centroid: Offset(x, y),
    );
  }

  /// Helper: create a simple stroke
  ProStroke _makeStroke(String id, Color color, {DateTime? createdAt}) {
    return ProStroke(
      id: id,
      points: [
        ProDrawingPoint(
          position: const Offset(0, 0),
          pressure: 0.5,
          timestamp: 0,
        ),
      ],
      color: color,
      baseWidth: 2.0,
      penType: ProPenType.ballpoint,
      createdAt: createdAt ?? DateTime.now(),
      settings: const ProBrushSettings(),
    );
  }

  group('ConnectionSuggestionEngine', () {
    test('returns empty for fewer than 2 clusters', () {
      final result = engine.computeSuggestions(
        clusters: [_makeCluster('a', 0, 0)],
        allStrokes: [],
        existingConnections: [],
      );
      expect(result, isEmpty);
    });

    test('suggests connection for two close clusters', () {
      final clusters = [
        _makeCluster('a', 0, 0, strokeIds: ['s1']),
        _makeCluster('b', 80, 0, strokeIds: ['s2']),
      ];
      final strokes = [
        _makeStroke('s1', const Color(0xFFFF0000)),
        _makeStroke('s2', const Color(0xFFFF3333)), // Similar red
      ];
      final result = engine.computeSuggestions(
        clusters: clusters,
        allStrokes: strokes,
        existingConnections: [],
        threshold: 0.3, // Lower threshold for test
      );
      expect(result, isNotEmpty);
      expect(result.first.sourceClusterId, 'a');
      expect(result.first.targetClusterId, 'b');
      expect(result.first.score, greaterThan(0.3));
    });

    test('does not suggest already-connected pairs', () {
      final clusters = [
        _makeCluster('a', 0, 0, strokeIds: ['s1']),
        _makeCluster('b', 80, 0, strokeIds: ['s2']),
      ];
      final strokes = [
        _makeStroke('s1', const Color(0xFFFF0000)),
        _makeStroke('s2', const Color(0xFFFF0000)),
      ];
      final existing = [
        KnowledgeConnection(
          id: 'conn1',
          sourceClusterId: 'a',
          targetClusterId: 'b',
          createdAt: 0,
        ),
      ];
      final result = engine.computeSuggestions(
        clusters: clusters,
        allStrokes: strokes,
        existingConnections: existing,
        threshold: 0.0, // Any score
      );
      expect(result, isEmpty);
    });

    test('same-color clusters score higher than different-color', () {
      final clusters = [
        _makeCluster('a', 0, 0, strokeIds: ['s1']),
        _makeCluster('b', 200, 0, strokeIds: ['s2']),
        _makeCluster('c', 200, 200, strokeIds: ['s3']),
      ];
      final strokes = [
        _makeStroke('s1', const Color(0xFFFF0000)), // Red
        _makeStroke('s2', const Color(0xFFFF1111)), // Almost red
        _makeStroke('s3', const Color(0xFF0000FF)), // Blue
      ];
      final result = engine.computeSuggestions(
        clusters: clusters,
        allStrokes: strokes,
        existingConnections: [],
        threshold: 0.0,
        maxSuggestions: 10,
      );
      // a↔b (same color) should score higher than a↔c or b↔c (diff color)
      final abScore = result.firstWhere(
        (s) => (s.sourceClusterId == 'a' && s.targetClusterId == 'b') ||
               (s.sourceClusterId == 'b' && s.targetClusterId == 'a'),
      ).score;
      final acScore = result.firstWhere(
        (s) => (s.sourceClusterId == 'a' && s.targetClusterId == 'c') ||
               (s.sourceClusterId == 'c' && s.targetClusterId == 'a'),
      ).score;
      expect(abScore, greaterThan(acScore));
    });

    test('caps at maxSuggestions', () {
      // Create 5 clusters → 10 pairs → should cap at 3
      final clusters = List.generate(5, (i) =>
        _makeCluster('c$i', i * 50.0, 0, strokeIds: ['s$i']),
      );
      final strokes = List.generate(5, (i) =>
        _makeStroke('s$i', const Color(0xFFFF0000)),
      );
      final result = engine.computeSuggestions(
        clusters: clusters,
        allStrokes: strokes,
        existingConnections: [],
        threshold: 0.0,
        maxSuggestions: 3,
      );
      expect(result.length, lessThanOrEqualTo(3));
    });

    test('dismissed suggestions have dismissed flag', () {
      final suggestion = SuggestedConnection(
        sourceClusterId: 'a',
        targetClusterId: 'b',
        score: 0.8,
        reason: 'Test',
      );
      expect(suggestion.dismissed, isFalse);
      suggestion.dismissed = true;
      expect(suggestion.dismissed, isTrue);
    });

    test('pairKey is order-independent', () {
      final s1 = SuggestedConnection(
        sourceClusterId: 'a',
        targetClusterId: 'b',
        score: 0.5,
        reason: 'Test',
      );
      final s2 = SuggestedConnection(
        sourceClusterId: 'b',
        targetClusterId: 'a',
        score: 0.5,
        reason: 'Test',
      );
      expect(s1.pairKey, equals(s2.pairKey));
    });

    // === EDGE CASE TESTS ===

    test('clusters without strokes (text-only) still score via type/size', () {
      final clusters = [
        _makeCluster('a', 0, 0, textIds: ['t1']),
        _makeCluster('b', 80, 0, textIds: ['t2']),
      ];
      final result = engine.computeSuggestions(
        clusters: clusters,
        allStrokes: [],
        existingConnections: [],
        threshold: 0.0,
      );
      expect(result, isNotEmpty);
      // Type match = 1.0 (both text), so score should be above 0
      expect(result.first.score, greaterThan(0.0));
    });

    test('single-element clusters work correctly', () {
      final clusters = [
        _makeCluster('a', 0, 0, strokeIds: ['s1']),
        _makeCluster('b', 100, 0, strokeIds: ['s2']),
      ];
      final strokes = [
        _makeStroke('s1', const Color(0xFF222222)),
        _makeStroke('s2', const Color(0xFF222222)),
      ];
      final result = engine.computeSuggestions(
        clusters: clusters,
        allStrokes: strokes,
        existingConnections: [],
        threshold: 0.0,
      );
      expect(result.length, 1);
    });

    // === TEMPORAL SCORING TEST ===

    test('clusters created close in time score higher than far apart', () {
      final now = DateTime.now();
      final clusters = [
        _makeCluster('a', 0, 0, strokeIds: ['s1']),
        _makeCluster('b', 500, 0, strokeIds: ['s2']),
        _makeCluster('c', 500, 500, strokeIds: ['s3']),
      ];
      final strokes = [
        _makeStroke('s1', const Color(0xFF888888), createdAt: now),
        _makeStroke('s2', const Color(0xFF888888),
            createdAt: now.add(const Duration(seconds: 30))),
        _makeStroke('s3', const Color(0xFF888888),
            createdAt: now.subtract(const Duration(hours: 2))),
      ];
      final result = engine.computeSuggestions(
        clusters: clusters,
        allStrokes: strokes,
        existingConnections: [],
        threshold: 0.0,
        maxSuggestions: 10,
      );
      // a↔b (30s apart) should score higher than a↔c (2h apart)
      final abScore = result.firstWhere(
        (s) => (s.sourceClusterId == 'a' && s.targetClusterId == 'b') ||
               (s.sourceClusterId == 'b' && s.targetClusterId == 'a'),
      ).score;
      final acScore = result.firstWhere(
        (s) => (s.sourceClusterId == 'a' && s.targetClusterId == 'c') ||
               (s.sourceClusterId == 'c' && s.targetClusterId == 'a'),
      ).score;
      expect(abScore, greaterThan(acScore));
    });

    // === LEARNING WEIGHTS TEST ===

    test('learning weights adapt after reinforcement', () {
      final initialSpatial = engine.wSpatial;
      engine.reinforceAccept('Nearby notes');
      expect(engine.wSpatial, greaterThan(initialSpatial));

      // Weights should still sum to ~1.0 (now 6 weights including semantic)
      final sum = engine.wSpatial + engine.wColor + engine.wSemantic +
          engine.wTemporal + engine.wSize + engine.wType;
      expect(sum, closeTo(1.0, 0.01));
    });

    // === SURFACED TIMESTAMP TEST ===

    test('surfacedAtMs is set on construction', () {
      final before = DateTime.now().millisecondsSinceEpoch;
      final suggestion = SuggestedConnection(
        sourceClusterId: 'a',
        targetClusterId: 'b',
        score: 0.5,
        reason: 'Test',
      );
      final after = DateTime.now().millisecondsSinceEpoch;
      expect(suggestion.surfacedAtMs, greaterThanOrEqualTo(before));
      expect(suggestion.surfacedAtMs, lessThanOrEqualTo(after));
    });

    // === SEMANTIC SIGNAL TESTS ===

    test('clusters with shared keywords score higher than unrelated', () {
      final clusters = [
        _makeCluster('a', 0, 0, strokeIds: ['s1']),
        _makeCluster('b', 500, 0, strokeIds: ['s2']),
        _makeCluster('c', 500, 500, strokeIds: ['s3']),
      ];
      final strokes = [
        _makeStroke('s1', const Color(0xFF888888)),
        _makeStroke('s2', const Color(0xFF888888)),
        _makeStroke('s3', const Color(0xFF888888)),
      ];
      // a="Newton force" + b="Newton physics" → shared keyword "Newton"
      // a="Newton force" + c="chemistry formula" → no shared keywords
      final result = engine.computeSuggestions(
        clusters: clusters,
        allStrokes: strokes,
        existingConnections: [],
        clusterTexts: {
          'a': 'Newton force gravity',
          'b': 'Newton physics momentum',
          'c': 'chemistry organic formula',
        },
        threshold: 0.0,
        maxSuggestions: 10,
      );
      final abScore = result.firstWhere(
        (s) => (s.sourceClusterId == 'a' && s.targetClusterId == 'b') ||
               (s.sourceClusterId == 'b' && s.targetClusterId == 'a'),
      ).score;
      final acScore = result.firstWhere(
        (s) => (s.sourceClusterId == 'a' && s.targetClusterId == 'c') ||
               (s.sourceClusterId == 'c' && s.targetClusterId == 'a'),
      ).score;
      expect(abScore, greaterThan(acScore));
    });

    test('empty clusterTexts gives neutral semantic score', () {
      final clusters = [
        _makeCluster('a', 0, 0, strokeIds: ['s1']),
        _makeCluster('b', 80, 0, strokeIds: ['s2']),
      ];
      final strokes = [
        _makeStroke('s1', const Color(0xFFFF0000)),
        _makeStroke('s2', const Color(0xFFFF0000)),
      ];
      // Without clusterTexts: semantic signal = 0.5 (neutral)
      final without = engine.computeSuggestions(
        clusters: clusters,
        allStrokes: strokes,
        existingConnections: [],
        threshold: 0.0,
      );
      // With empty texts: same result
      final with_ = engine.computeSuggestions(
        clusters: clusters,
        allStrokes: strokes,
        existingConnections: [],
        clusterTexts: {},
        threshold: 0.0,
      );
      // Scores should be identical (both get 0.5 neutral semantic)
      expect(without.first.score, closeTo(with_.first.score, 0.01));
    });

    test('semantic learning adjusts wSemantic weight', () {
      final initialSemantic = engine.wSemantic;
      engine.reinforceAccept('Related content');
      expect(engine.wSemantic, greaterThan(initialSemantic));
    });
  });
}
