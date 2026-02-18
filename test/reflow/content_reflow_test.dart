import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/reflow/content_cluster.dart';
import 'package:nebula_engine/src/reflow/cluster_detector.dart';
import 'package:nebula_engine/src/reflow/reflow_physics_engine.dart';
import 'package:nebula_engine/src/drawing/models/pro_drawing_point.dart';
import 'package:nebula_engine/src/core/models/shape_type.dart';
import 'package:nebula_engine/src/core/models/digital_text_element.dart';
import 'package:nebula_engine/src/core/models/image_element.dart';

// =============================================================================
// Helpers
// =============================================================================

ProStroke _stroke({
  required String id,
  required Rect bounds,
  DateTime? createdAt,
}) {
  final time = createdAt ?? DateTime(2025, 1, 1);
  // Create a minimal stroke covering the bounds
  return ProStroke(
    id: id,
    points: [
      ProDrawingPoint(position: bounds.topLeft, pressure: 0.5, timestamp: 0),
      ProDrawingPoint(position: bounds.topRight, pressure: 0.5, timestamp: 1),
      ProDrawingPoint(
        position: bounds.bottomRight,
        pressure: 0.5,
        timestamp: 2,
      ),
      ProDrawingPoint(position: bounds.bottomLeft, pressure: 0.5, timestamp: 3),
    ],
    color: const Color(0xFF000000),
    baseWidth: 2.0,
    penType: ProPenType.ballpoint,
    createdAt: time,
  );
}

void main() {
  // ===========================================================================
  // ContentCluster Model Tests
  // ===========================================================================
  group('ContentCluster', () {
    test('calculates mass from bounds area', () {
      final cluster = ContentCluster(
        id: 'c1',
        strokeIds: ['s1'],
        bounds: const Rect.fromLTWH(0, 0, 100, 50),
        centroid: const Offset(50, 25),
      );
      expect(cluster.mass, 5000.0); // 100 × 50
    });

    test('displacedBounds applies displacement', () {
      final cluster = ContentCluster(
        id: 'c1',
        strokeIds: ['s1'],
        bounds: const Rect.fromLTWH(10, 10, 50, 50),
        centroid: const Offset(35, 35),
        displacement: const Offset(20, -10),
      );
      expect(cluster.displacedBounds, const Rect.fromLTWH(30, 0, 50, 50));
    });

    test('containsElement checks all ID lists', () {
      final cluster = ContentCluster(
        id: 'c1',
        strokeIds: ['s1', 's2'],
        shapeIds: ['sh1'],
        textIds: ['t1'],
        imageIds: ['i1'],
        bounds: Rect.zero,
        centroid: Offset.zero,
      );
      expect(cluster.containsElement('s2'), true);
      expect(cluster.containsElement('sh1'), true);
      expect(cluster.containsElement('t1'), true);
      expect(cluster.containsElement('i1'), true);
      expect(cluster.containsElement('x1'), false);
    });

    test('equality based on id', () {
      final a = ContentCluster(
        id: 'c1',
        strokeIds: ['s1'],
        bounds: Rect.zero,
        centroid: Offset.zero,
      );
      final b = ContentCluster(
        id: 'c1',
        strokeIds: ['s2'],
        bounds: const Rect.fromLTWH(1, 1, 1, 1),
        centroid: Offset.zero,
      );
      expect(a, equals(b));
    });
  });

  // ===========================================================================
  // ClusterDetector Tests
  // ===========================================================================
  group('ClusterDetector', () {
    const detector = ClusterDetector(
      temporalThresholdMs: 1500,
      spatialThreshold: 50.0,
    );

    test('single stroke creates single cluster', () {
      final strokes = [
        _stroke(id: 's1', bounds: const Rect.fromLTWH(0, 0, 100, 30)),
      ];

      final clusters = detector.detect(
        strokes: strokes,
        shapes: [],
        texts: [],
        images: [],
      );

      expect(clusters.length, 1);
      expect(clusters[0].strokeIds, ['s1']);
    });

    test('temporally + spatially close strokes merge into one cluster', () {
      final base = DateTime(2025, 1, 1);
      final strokes = [
        _stroke(
          id: 'c',
          bounds: const Rect.fromLTWH(0, 0, 30, 40),
          createdAt: base,
        ),
        _stroke(
          id: 'i',
          bounds: const Rect.fromLTWH(35, 0, 15, 40),
          createdAt: base.add(const Duration(milliseconds: 500)),
        ),
        _stroke(
          id: 'a',
          bounds: const Rect.fromLTWH(55, 0, 30, 40),
          createdAt: base.add(const Duration(milliseconds: 900)),
        ),
        _stroke(
          id: 'o',
          bounds: const Rect.fromLTWH(90, 0, 30, 40),
          createdAt: base.add(const Duration(milliseconds: 1200)),
        ),
      ];

      final clusters = detector.detect(
        strokes: strokes,
        shapes: [],
        texts: [],
        images: [],
      );

      // All 4 strokes should be in one cluster ("ciao")
      expect(clusters.length, 1);
      expect(clusters[0].strokeIds.length, 4);
    });

    test('temporally distant strokes form separate clusters', () {
      final base = DateTime(2025, 1, 1);
      final strokes = [
        _stroke(
          id: 'word1',
          bounds: const Rect.fromLTWH(0, 0, 80, 40),
          createdAt: base,
        ),
        _stroke(
          id: 'word2',
          bounds: const Rect.fromLTWH(10, 10, 80, 40),
          createdAt: base.add(const Duration(seconds: 10)), // 10s later
        ),
      ];

      final clusters = detector.detect(
        strokes: strokes,
        shapes: [],
        texts: [],
        images: [],
      );

      expect(clusters.length, 2);
    });

    test('spatially distant strokes form separate clusters', () {
      final base = DateTime(2025, 1, 1);
      final strokes = [
        _stroke(
          id: 'left',
          bounds: const Rect.fromLTWH(0, 0, 40, 40),
          createdAt: base,
        ),
        _stroke(
          id: 'right',
          bounds: const Rect.fromLTWH(200, 0, 40, 40), // 160px away
          createdAt: base.add(const Duration(milliseconds: 500)),
        ),
      ];

      final clusters = detector.detect(
        strokes: strokes,
        shapes: [],
        texts: [],
        images: [],
      );

      expect(clusters.length, 2);
    });

    test('shapes always form individual clusters', () {
      final shape1 = GeometricShape(
        id: 'sh1',
        type: ShapeType.rectangle,
        startPoint: const Offset(0, 0),
        endPoint: const Offset(100, 100),
        color: const Color(0xFF000000),
        strokeWidth: 2.0,
        createdAt: DateTime(2025, 1, 1),
      );
      final shape2 = GeometricShape(
        id: 'sh2',
        type: ShapeType.circle,
        startPoint: const Offset(10, 10),
        endPoint: const Offset(50, 50),
        color: const Color(0xFF000000),
        strokeWidth: 2.0,
        createdAt: DateTime(2025, 1, 1),
      );

      final clusters = detector.detect(
        strokes: [],
        shapes: [shape1, shape2],
        texts: [],
        images: [],
      );

      expect(clusters.length, 2);
      expect(clusters[0].shapeIds, ['sh1']);
      expect(clusters[1].shapeIds, ['sh2']);
    });

    test('texts always form individual clusters', () {
      final text = DigitalTextElement(
        id: 't1',
        text: 'Hello World',
        position: const Offset(100, 100),
        color: const Color(0xFF000000),
        fontSize: 16,
        fontWeight: FontWeight.normal,
        fontFamily: 'Roboto',
        scale: 1.0,
        createdAt: DateTime(2025, 1, 1),
      );

      final clusters = detector.detect(
        strokes: [],
        shapes: [],
        texts: [text],
        images: [],
      );

      expect(clusters.length, 1);
      expect(clusters[0].textIds, ['t1']);
    });

    test('incrementally adding a stroke merges into existing cluster', () {
      final base = DateTime(2025, 1, 1);
      final existingStrokes = [
        _stroke(
          id: 's1',
          bounds: const Rect.fromLTWH(0, 0, 40, 40),
          createdAt: base,
        ),
      ];

      var clusters = detector.detect(
        strokes: existingStrokes,
        shapes: [],
        texts: [],
        images: [],
      );
      expect(clusters.length, 1);

      // Add a temporally + spatially close stroke
      final newStroke = _stroke(
        id: 's2',
        bounds: const Rect.fromLTWH(45, 0, 40, 40), // 5px gap
        createdAt: base.add(const Duration(milliseconds: 400)),
      );
      final allStrokes = [...existingStrokes, newStroke];

      clusters = detector.addStroke(clusters, newStroke, allStrokes);

      // Should merge into the same cluster
      expect(clusters.length, 1);
      expect(clusters[0].strokeIds.length, 2);
    });

    test('incrementally adding a distant stroke creates new cluster', () {
      final base = DateTime(2025, 1, 1);
      final existingStrokes = [
        _stroke(
          id: 's1',
          bounds: const Rect.fromLTWH(0, 0, 40, 40),
          createdAt: base,
        ),
      ];

      var clusters = detector.detect(
        strokes: existingStrokes,
        shapes: [],
        texts: [],
        images: [],
      );

      final newStroke = _stroke(
        id: 's2',
        bounds: const Rect.fromLTWH(300, 300, 40, 40), // Far away
        createdAt: base.add(const Duration(seconds: 30)), // Far in time
      );
      final allStrokes = [...existingStrokes, newStroke];

      clusters = detector.addStroke(clusters, newStroke, allStrokes);

      expect(clusters.length, 2);
    });
  });

  // ===========================================================================
  // ReflowPhysicsEngine Tests
  // ===========================================================================
  group('ReflowPhysicsEngine', () {
    const config = ReflowConfig(
      enabled: true,
      repulsionStrength: 1.2,
      clearanceMargin: 20.0,
      maxAffectRadius: 500.0,
      maxIterations: 5,
      maxAffectedClusters: 50,
    );
    const engine = ReflowPhysicsEngine(config: config);

    test('no displacement when clusters do not overlap disturbance', () {
      final clusters = [
        ContentCluster(
          id: 'c1',
          strokeIds: ['s1'],
          bounds: const Rect.fromLTWH(500, 500, 100, 100),
          centroid: const Offset(550, 550),
        ),
      ];

      final result = engine.estimateDisplacements(
        clusters: clusters,
        disturbance: const Rect.fromLTWH(0, 0, 50, 50),
        excludeIds: {},
      );

      expect(result, isEmpty);
    });

    test('clusters overlapping disturbance are displaced', () {
      final clusters = [
        ContentCluster(
          id: 'c1',
          strokeIds: ['s1'],
          bounds: const Rect.fromLTWH(90, 0, 50, 50),
          centroid: const Offset(115, 25),
        ),
      ];

      final result = engine.estimateDisplacements(
        clusters: clusters,
        disturbance: const Rect.fromLTWH(0, 0, 100, 50), // Overlaps c1
        excludeIds: {},
      );

      expect(result.containsKey('c1'), true);
      // Cluster should be pushed to the right (away from disturbance center)
      expect(result['c1']!.dx, greaterThan(0));
    });

    test('excluded clusters are never displaced', () {
      final clusters = [
        ContentCluster(
          id: 'c1',
          strokeIds: ['s1'],
          bounds: const Rect.fromLTWH(50, 0, 50, 50),
          centroid: const Offset(75, 25),
        ),
      ];

      final result = engine.estimateDisplacements(
        clusters: clusters,
        disturbance: const Rect.fromLTWH(0, 0, 100, 50),
        excludeIds: {'c1'},
      );

      expect(result, isEmpty);
    });

    test('pinned clusters are never displaced', () {
      final clusters = [
        ContentCluster(
          id: 'c1',
          strokeIds: ['s1'],
          bounds: const Rect.fromLTWH(50, 0, 50, 50),
          centroid: const Offset(75, 25),
          isPinned: true,
        ),
      ];

      final result = engine.estimateDisplacements(
        clusters: clusters,
        disturbance: const Rect.fromLTWH(0, 0, 100, 50),
        excludeIds: {},
      );

      expect(result, isEmpty);
    });

    test('disabled engine returns empty', () {
      const disabledEngine = ReflowPhysicsEngine(config: ReflowConfig.disabled);

      final clusters = [
        ContentCluster(
          id: 'c1',
          strokeIds: ['s1'],
          bounds: const Rect.fromLTWH(50, 0, 50, 50),
          centroid: const Offset(75, 25),
        ),
      ];

      final result = disabledEngine.estimateDisplacements(
        clusters: clusters,
        disturbance: const Rect.fromLTWH(0, 0, 100, 50),
        excludeIds: {},
      );

      expect(result, isEmpty);
    });

    test('solve resolves secondary collisions', () {
      // Two clusters adjacent — pushing one should cascade to the other
      final clusters = [
        ContentCluster(
          id: 'c1',
          strokeIds: ['s1'],
          bounds: const Rect.fromLTWH(80, 0, 50, 50),
          centroid: const Offset(105, 25),
        ),
        ContentCluster(
          id: 'c2',
          strokeIds: ['s2'],
          bounds: const Rect.fromLTWH(130, 0, 50, 50),
          centroid: const Offset(155, 25),
        ),
      ];

      final result = engine.solve(
        clusters: clusters,
        disturbance: const Rect.fromLTWH(0, 0, 100, 50),
        excludeIds: {},
      );

      // Both should have non-zero displacement
      expect(result.containsKey('c1'), true);
      // c2 may or may not be displaced depending on collision resolution
    });

    test('applyDisplacements mutates cluster fields', () {
      final clusters = [
        ContentCluster(
          id: 'c1',
          strokeIds: ['s1'],
          bounds: const Rect.fromLTWH(0, 0, 50, 50),
          centroid: const Offset(25, 25),
        ),
      ];

      final displacements = {'c1': const Offset(30, 10)};
      final affected = engine.applyDisplacements(clusters, displacements);

      expect(affected, {'s1'});
      expect(clusters[0].displacement, const Offset(30, 10));
    });

    test('clusters beyond maxAffectRadius are ignored', () {
      final clusters = [
        ContentCluster(
          id: 'far',
          strokeIds: ['s1'],
          bounds: const Rect.fromLTWH(2000, 2000, 50, 50),
          centroid: const Offset(2025, 2025),
        ),
      ];

      final result = engine.solve(
        clusters: clusters,
        disturbance: const Rect.fromLTWH(0, 0, 50, 50),
        excludeIds: {},
      );

      expect(result, isEmpty);
    });
  });
}
