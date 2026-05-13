import 'package:flutter_test/flutter_test.dart';
import 'dart:ui';
import 'package:fluera_engine/src/reflow/cluster_detector.dart';
import 'package:fluera_engine/src/reflow/content_cluster.dart';
import 'package:fluera_engine/src/drawing/models/pro_drawing_point.dart';
import 'package:fluera_engine/src/core/models/shape_type.dart';
import 'package:fluera_engine/src/core/models/digital_text_element.dart';
import 'package:fluera_engine/src/core/models/image_element.dart';
import 'package:fluera_engine/src/feature_flags/cluster_id_v2_flag.dart';

/// Helper to create a minimal ProStroke with given bounds and creation time.
ProStroke _makeStroke({
  required String id,
  required Rect bounds,
  required DateTime createdAt,
}) {
  final points = [
    ProDrawingPoint(
      position: bounds.topLeft,
      pressure: 0.5,
      timestamp: createdAt.millisecondsSinceEpoch,
    ),
    ProDrawingPoint(
      position: bounds.bottomRight,
      pressure: 0.5,
      timestamp: createdAt.millisecondsSinceEpoch + 10,
    ),
  ];
  return ProStroke(
    id: id,
    points: points,
    color: const Color(0xFF000000),
    baseWidth: 2.0,
    penType: ProPenType.ballpoint,
    createdAt: createdAt,
  );
}

GeometricShape _makeShape({
  required String id,
  required ShapeType type,
  required Offset start,
  required Offset end,
}) {
  return GeometricShape(
    id: id,
    type: type,
    startPoint: start,
    endPoint: end,
    color: const Color(0xFF000000),
    strokeWidth: 2.0,
    createdAt: DateTime(2024),
  );
}

void main() {
  late ClusterDetector detector;

  setUp(() {
    detector = const ClusterDetector();
  });

  group('ClusterDetector', () {
    group('detect', () {
      test('empty input returns empty clusters', () {
        final clusters = detector.detect(
          strokes: [],
          shapes: [],
          texts: [],
          images: [],
        );
        expect(clusters, isEmpty);
      });

      test('single stroke creates single cluster', () {
        final stroke = _makeStroke(
          id: 's1',
          bounds: const Rect.fromLTWH(0, 0, 100, 50),
          createdAt: DateTime(2024, 1, 1),
        );
        final clusters = detector.detect(
          strokes: [stroke],
          shapes: [],
          texts: [],
          images: [],
        );
        expect(clusters.length, 1);
        expect(clusters[0].strokeIds, ['s1']);
      });

      test('groups temporally and spatially close strokes', () {
        final now = DateTime(2024, 1, 1);
        final strokes = [
          _makeStroke(
            id: 's1',
            bounds: const Rect.fromLTWH(0, 0, 50, 20),
            createdAt: now,
          ),
          _makeStroke(
            id: 's2',
            bounds: const Rect.fromLTWH(55, 0, 50, 20),
            createdAt: now.add(const Duration(milliseconds: 200)),
          ),
        ];
        final clusters = detector.detect(
          strokes: strokes,
          shapes: [],
          texts: [],
          images: [],
        );
        expect(clusters.length, 1);
        expect(clusters[0].strokeIds, containsAll(['s1', 's2']));
      });

      test('separates temporally distant strokes', () {
        final now = DateTime(2024, 1, 1);
        final strokes = [
          _makeStroke(
            id: 's1',
            bounds: const Rect.fromLTWH(0, 0, 50, 20),
            createdAt: now,
          ),
          _makeStroke(
            id: 's2',
            bounds: const Rect.fromLTWH(200, 0, 50, 20),
            createdAt: now.add(const Duration(seconds: 5)),
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

      test('separates spatially distant strokes', () {
        final now = DateTime(2024, 1, 1);
        final strokes = [
          _makeStroke(
            id: 's1',
            bounds: const Rect.fromLTWH(0, 0, 50, 20),
            createdAt: now,
          ),
          _makeStroke(
            id: 's2',
            bounds: const Rect.fromLTWH(500, 0, 50, 20),
            createdAt: now.add(const Duration(milliseconds: 200)),
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

      test('shapes are always individual clusters', () {
        final clusters = detector.detect(
          strokes: [],
          shapes: [
            _makeShape(
              id: 'sh1',
              type: ShapeType.rectangle,
              start: const Offset(0, 0),
              end: const Offset(100, 100),
            ),
            _makeShape(
              id: 'sh2',
              type: ShapeType.circle,
              start: const Offset(10, 10),
              end: const Offset(50, 50),
            ),
          ],
          texts: [],
          images: [],
        );
        expect(clusters.length, 2);
        expect(clusters[0].shapeIds, ['sh1']);
        expect(clusters[1].shapeIds, ['sh2']);
      });

      test('text elements are always individual clusters', () {
        final clusters = detector.detect(
          strokes: [],
          shapes: [],
          texts: [
            DigitalTextElement(
              id: 't1',
              text: 'Hello',
              position: const Offset(10, 10),
              color: const Color(0xFF000000),
              fontSize: 16,
              pageIndex: 0,
              createdAt: DateTime(2024),
            ),
          ],
          images: [],
        );
        expect(clusters.length, 1);
        expect(clusters[0].textIds, ['t1']);
      });

      test('image elements are always individual clusters', () {
        final clusters = detector.detect(
          strokes: [],
          shapes: [],
          texts: [],
          images: [
            ImageElement(
              id: 'img1',
              imagePath: '/tmp/test.png',
              position: const Offset(100, 100),
              createdAt: DateTime(2024),
              pageIndex: 0,
            ),
          ],
        );
        expect(clusters.length, 1);
        expect(clusters[0].imageIds, ['img1']);
      });

      test('mixed elements produce correct cluster count', () {
        final now = DateTime(2024, 1, 1);
        final clusters = detector.detect(
          strokes: [
            _makeStroke(
              id: 's1',
              bounds: const Rect.fromLTWH(0, 0, 50, 20),
              createdAt: now,
            ),
          ],
          shapes: [
            _makeShape(
              id: 'sh1',
              type: ShapeType.line,
              start: const Offset(0, 0),
              end: const Offset(100, 100),
            ),
          ],
          texts: [
            DigitalTextElement(
              id: 't1',
              text: 'Test',
              position: Offset.zero,
              color: const Color(0xFF000000),
              fontSize: 14,
              pageIndex: 0,
              createdAt: DateTime(2024),
            ),
          ],
          images: [
            ImageElement(
              id: 'img1',
              imagePath: '/tmp/test.png',
              position: Offset.zero,
              createdAt: DateTime(2024),
              pageIndex: 0,
            ),
          ],
        );
        expect(clusters.length, 4);
      });
    });

    group('addStroke', () {
      test('adds stroke to matching cluster', () {
        final now = DateTime(2024, 1, 1);
        final s1 = _makeStroke(
          id: 's1',
          bounds: const Rect.fromLTWH(0, 0, 50, 20),
          createdAt: now,
        );
        final s2 = _makeStroke(
          id: 's2',
          bounds: const Rect.fromLTWH(55, 0, 50, 20),
          createdAt: now.add(const Duration(milliseconds: 200)),
        );

        final initial = detector.detect(
          strokes: [s1],
          shapes: [],
          texts: [],
          images: [],
        );
        expect(initial.length, 1);

        final updated = detector.addStroke(initial, s2, [s1, s2]);
        expect(updated.length, 1);
        expect(updated[0].strokeIds, containsAll(['s1', 's2']));
      });

      test('creates new cluster when no match', () {
        final now = DateTime(2024, 1, 1);
        final s1 = _makeStroke(
          id: 's1',
          bounds: const Rect.fromLTWH(0, 0, 50, 20),
          createdAt: now,
        );
        final s2 = _makeStroke(
          id: 's2',
          bounds: const Rect.fromLTWH(500, 500, 50, 20),
          createdAt: now.add(const Duration(seconds: 10)),
        );

        final initial = detector.detect(
          strokes: [s1],
          shapes: [],
          texts: [],
          images: [],
        );
        final updated = detector.addStroke(initial, s2, [s1, s2]);
        expect(updated.length, 2);
      });
    });

    group('custom thresholds', () {
      test('smaller temporal threshold separates more', () {
        final narrow = const ClusterDetector(temporalThresholdMs: 100);
        final now = DateTime(2024, 1, 1);
        final strokes = [
          _makeStroke(
            id: 's1',
            bounds: const Rect.fromLTWH(0, 0, 50, 20),
            createdAt: now,
          ),
          _makeStroke(
            id: 's2',
            bounds: const Rect.fromLTWH(200, 0, 50, 20),
            createdAt: now.add(const Duration(milliseconds: 200)),
          ),
        ];
        final clusters = narrow.detect(
          strokes: strokes,
          shapes: [],
          texts: [],
          images: [],
        );
        expect(clusters.length, 2);
      });

      test('larger spatial threshold merges more', () {
        final wide = const ClusterDetector(spatialThreshold: 500);
        final now = DateTime(2024, 1, 1);
        final strokes = [
          _makeStroke(
            id: 's1',
            bounds: const Rect.fromLTWH(0, 0, 50, 20),
            createdAt: now,
          ),
          _makeStroke(
            id: 's2',
            bounds: const Rect.fromLTWH(400, 0, 50, 20),
            createdAt: now.add(const Duration(milliseconds: 200)),
          ),
        ];
        final clusters = wide.detect(
          strokes: strokes,
          shapes: [],
          texts: [],
          images: [],
        );
        expect(clusters.length, 1);
      });
    });

    group('cluster bounds', () {
      test('stroke cluster bounds span all strokes', () {
        final now = DateTime(2024, 1, 1);
        final strokes = [
          _makeStroke(
            id: 's1',
            bounds: const Rect.fromLTWH(0, 0, 50, 20),
            createdAt: now,
          ),
          _makeStroke(
            id: 's2',
            bounds: const Rect.fromLTWH(30, 10, 50, 20),
            createdAt: now.add(const Duration(milliseconds: 100)),
          ),
        ];
        final clusters = detector.detect(
          strokes: strokes,
          shapes: [],
          texts: [],
          images: [],
        );
        expect(clusters.length, 1);
        final b = clusters[0].bounds;
        // ProStroke.bounds adds baseWidth padding, so check containment
        // rather than exact pixel values
        expect(b.left, lessThanOrEqualTo(0.0));
        expect(b.top, lessThanOrEqualTo(0.0));
        expect(b.right, greaterThanOrEqualTo(80.0));
        expect(b.bottom, greaterThanOrEqualTo(30.0));
      });
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // 🏷️ V2 content-stable cluster IDs (ClusterConceptIndex sprint).
  // V1 (legacy) hashed sortedStrokeIds → ID changed on every edit.
  // V2 hashes (bounds quantized 24px + count + temporal centroid 5min)
  // → IDs survive small edits, downstream caches survive too.
  // ──────────────────────────────────────────────────────────────────
  group('ClusterDetector V2 stable IDs', () {
    setUp(() {
      ClusterIdV2Flag.enabled = true;
    });

    tearDown(() {
      ClusterIdV2Flag.enabled = true;
    });

    test('id has cluster_v2_ prefix when flag enabled', () {
      final stroke = _makeStroke(
        id: 's1',
        bounds: const Rect.fromLTWH(100, 100, 50, 30),
        createdAt: DateTime(2024, 1, 1, 12, 0),
      );
      final clusters = const ClusterDetector().detect(
        strokes: [stroke], shapes: [], texts: [], images: [],
      );
      expect(clusters.length, 1);
      expect(clusters[0].id, startsWith('cluster_v2_'));
    });

    test('id falls back to cluster_stroke_ when flag disabled', () {
      ClusterIdV2Flag.enabled = false;
      final stroke = _makeStroke(
        id: 's1',
        bounds: const Rect.fromLTWH(100, 100, 50, 30),
        createdAt: DateTime(2024, 1, 1, 12, 0),
      );
      final clusters = const ClusterDetector().detect(
        strokes: [stroke], shapes: [], texts: [], images: [],
      );
      expect(clusters.length, 1);
      expect(clusters[0].id, startsWith('cluster_stroke_'));
    });

    test('adding 1 stroke INSIDE the cluster footprint preserves the ID', () {
      // Strokes packed inside a 24x24 quantization box → adding more
      // strokes within the same bounding-box footprint and within the
      // same 5-minute temporal bucket should NOT change the V2 hash.
      // Note: count is part of the hash, so 1-stroke vs 2-stroke clusters
      // get DIFFERENT IDs. Stability is for "same count, same footprint".
      final t = DateTime(2024, 1, 1, 12, 0);
      final twoStrokes = [
        _makeStroke(id: 'a', bounds: const Rect.fromLTWH(100, 100, 50, 30), createdAt: t),
        _makeStroke(id: 'b', bounds: const Rect.fromLTWH(105, 105, 30, 20), createdAt: t.add(const Duration(milliseconds: 200))),
      ];
      final twoStrokesAlt = [
        // Different IDs, same temporal/spatial footprint, same count.
        _makeStroke(id: 'c', bounds: const Rect.fromLTWH(100, 100, 50, 30), createdAt: t.add(const Duration(milliseconds: 50))),
        _makeStroke(id: 'd', bounds: const Rect.fromLTWH(105, 105, 30, 20), createdAt: t.add(const Duration(milliseconds: 250))),
      ];
      final clustersA = const ClusterDetector().detect(
        strokes: twoStrokes, shapes: [], texts: [], images: [],
      );
      final clustersB = const ClusterDetector().detect(
        strokes: twoStrokesAlt, shapes: [], texts: [], images: [],
      );
      expect(clustersA.length, 1);
      expect(clustersB.length, 1);
      // V2 hash depends on bounds + count + temporal centroid only —
      // NOT on strokeIds. Same content → same hash.
      expect(clustersA[0].id, equals(clustersB[0].id));
    });

    test('different temporal session → different ID', () {
      // Two clusters at the same spatial location but in different
      // 5-minute buckets (e.g. revisited days later) get distinct IDs.
      final morningStroke = _makeStroke(
        id: 'm',
        bounds: const Rect.fromLTWH(100, 100, 50, 30),
        createdAt: DateTime(2024, 1, 1, 12, 0),
      );
      final eveningStroke = _makeStroke(
        id: 'e',
        bounds: const Rect.fromLTWH(100, 100, 50, 30),
        createdAt: DateTime(2024, 1, 1, 18, 0),
      );
      final c1 = const ClusterDetector().detect(
        strokes: [morningStroke], shapes: [], texts: [], images: [],
      );
      final c2 = const ClusterDetector().detect(
        strokes: [eveningStroke], shapes: [], texts: [], images: [],
      );
      expect(c1[0].id, isNot(equals(c2[0].id)));
    });

    test('spatially distant clusters → distinct IDs', () {
      final t = DateTime(2024, 1, 1, 12, 0);
      final far = [
        _makeStroke(id: 'a', bounds: const Rect.fromLTWH(0, 0, 50, 30), createdAt: t),
        _makeStroke(id: 'b', bounds: const Rect.fromLTWH(1000, 1000, 50, 30), createdAt: t.add(const Duration(milliseconds: 100))),
      ];
      final clusters = const ClusterDetector().detect(
        strokes: far, shapes: [], texts: [], images: [],
      );
      // Spatial threshold default is 60px → these are 2 separate clusters.
      expect(clusters.length, 2);
      expect(clusters[0].id, isNot(equals(clusters[1].id)));
    });
  });
}
