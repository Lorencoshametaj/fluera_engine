import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/reflow/reflow_physics_engine.dart';
import 'package:nebula_engine/src/reflow/content_cluster.dart';

void main() {
  // ===========================================================================
  // ReflowConfig
  // ===========================================================================

  group('ReflowConfig', () {
    test('default config has positive repulsion', () {
      const config = ReflowConfig();
      expect(config.repulsionStrength, greaterThan(0));
    });
  });

  // ===========================================================================
  // estimateDisplacements
  // ===========================================================================

  group('ReflowPhysicsEngine - estimateDisplacements', () {
    test('no displacement when no overlap', () {
      const engine = ReflowPhysicsEngine(config: ReflowConfig());
      final cluster = ContentCluster(
        id: 'c1',
        bounds: const Rect.fromLTWH(200, 200, 50, 50),
        centroid: const Offset(225, 225),
        strokeIds: ['e1'],
      );
      final result = engine.estimateDisplacements(
        clusters: [cluster],
        disturbance: const Rect.fromLTWH(0, 0, 50, 50),
        excludeIds: {},
      );
      expect(result, isA<Map<String, Offset>>());
    });

    test('overlap produces displacement', () {
      const engine = ReflowPhysicsEngine(config: ReflowConfig());
      final cluster = ContentCluster(
        id: 'c1',
        bounds: const Rect.fromLTWH(40, 40, 50, 50),
        centroid: const Offset(65, 65),
        strokeIds: ['e1'],
      );
      final result = engine.estimateDisplacements(
        clusters: [cluster],
        disturbance: const Rect.fromLTWH(30, 30, 50, 50),
        excludeIds: {},
      );
      expect(result.containsKey('c1'), isTrue);
    });

    test('excludeIds are skipped', () {
      const engine = ReflowPhysicsEngine(config: ReflowConfig());
      final cluster = ContentCluster(
        id: 'c1',
        bounds: const Rect.fromLTWH(40, 40, 50, 50),
        centroid: const Offset(65, 65),
        strokeIds: ['e1'],
      );
      final result = engine.estimateDisplacements(
        clusters: [cluster],
        disturbance: const Rect.fromLTWH(30, 30, 50, 50),
        excludeIds: {'c1'},
      );
      expect(result.containsKey('c1'), isFalse);
    });
  });

  // ===========================================================================
  // solve
  // ===========================================================================

  group('ReflowPhysicsEngine - solve', () {
    test('solves with collision resolution', () {
      const engine = ReflowPhysicsEngine(config: ReflowConfig());
      final clusters = [
        ContentCluster(
          id: 'c1',
          bounds: const Rect.fromLTWH(40, 40, 50, 50),
          centroid: const Offset(65, 65),
          strokeIds: ['e1'],
        ),
        ContentCluster(
          id: 'c2',
          bounds: const Rect.fromLTWH(60, 60, 50, 50),
          centroid: const Offset(85, 85),
          strokeIds: ['e2'],
        ),
      ];
      final result = engine.solve(
        clusters: clusters,
        disturbance: const Rect.fromLTWH(30, 30, 60, 60),
        excludeIds: {},
      );
      expect(result, isA<Map<String, Offset>>());
    });
  });
}
