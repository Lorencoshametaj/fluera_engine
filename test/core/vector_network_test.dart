import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/nebula_engine.dart';

void main() {
  // ===========================================================================
  // DATA MODEL BASICS
  // ===========================================================================

  group('NetworkVertex', () {
    test('construction and clone', () {
      final v = NetworkVertex(position: const Offset(10, 20));
      expect(v.position, const Offset(10, 20));
      final clone = v.clone();
      expect(clone.position, const Offset(10, 20));
      expect(identical(v, clone), isFalse);
    });

    test('serialization roundtrip', () {
      final v = NetworkVertex(position: const Offset(3.5, -7.2));
      final json = v.toJson();
      final restored = NetworkVertex.fromJson(json);
      expect(restored.position.dx, closeTo(3.5, 0.001));
      expect(restored.position.dy, closeTo(-7.2, 0.001));
    });

    test('equality', () {
      final a = NetworkVertex(position: const Offset(1, 2));
      final b = NetworkVertex(position: const Offset(1, 2));
      final c = NetworkVertex(position: const Offset(3, 4));
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  group('NetworkSegment', () {
    test('straight segment', () {
      final seg = NetworkSegment(start: 0, end: 1);
      expect(seg.isStraight, isTrue);
      expect(seg.hasStrokeOverride, isFalse);
    });

    test('curved segment', () {
      final seg = NetworkSegment(
        start: 0,
        end: 1,
        tangentStart: const Offset(10, 20),
        tangentEnd: const Offset(30, 40),
      );
      expect(seg.isStraight, isFalse);
    });

    test('per-segment stroke override', () {
      final seg = NetworkSegment(
        start: 0,
        end: 1,
        segmentStrokeWidth: 5.0,
        segmentStrokeColor: 0xFFFF0000,
        segmentStrokeCap: StrokeCap.butt,
      );
      expect(seg.hasStrokeOverride, isTrue);
      expect(seg.segmentStrokeWidth, 5.0);
      expect(seg.segmentStrokeColor, 0xFFFF0000);
      expect(seg.segmentStrokeCap, StrokeCap.butt);
    });

    test('serialization roundtrip — with stroke override', () {
      final seg = NetworkSegment(
        start: 0,
        end: 1,
        segmentStrokeWidth: 3.0,
        segmentStrokeColor: 0xFF00FF00,
        segmentStrokeCap: StrokeCap.square,
      );
      final json = seg.toJson();
      final restored = NetworkSegment.fromJson(json);
      expect(restored.segmentStrokeWidth, 3.0);
      expect(restored.segmentStrokeColor, 0xFF00FF00);
      expect(restored.segmentStrokeCap, StrokeCap.square);
    });

    test('serialization roundtrip — curved', () {
      final seg = NetworkSegment(
        start: 0,
        end: 1,
        tangentStart: const Offset(1.5, 2.5),
        tangentEnd: const Offset(3.5, 4.5),
      );
      final json = seg.toJson();
      final restored = NetworkSegment.fromJson(json);
      expect(restored.tangentStart!.dx, closeTo(1.5, 0.001));
      expect(restored.tangentEnd!.dy, closeTo(4.5, 0.001));
    });
  });

  // ===========================================================================
  // CRUD
  // ===========================================================================

  group('VectorNetwork — CRUD', () {
    late VectorNetwork network;

    setUp(() {
      network = VectorNetwork();
    });

    test('addVertex returns incremental indices', () {
      final i0 = network.addVertex(NetworkVertex(position: Offset.zero));
      final i1 = network.addVertex(
        NetworkVertex(position: const Offset(10, 0)),
      );
      expect(i0, 0);
      expect(i1, 1);
      expect(network.vertices.length, 2);
    });

    test('addSegment validates vertex indices', () {
      network.addVertex(NetworkVertex(position: Offset.zero));
      network.addVertex(NetworkVertex(position: const Offset(10, 0)));
      final segIdx = network.addSegment(NetworkSegment(start: 0, end: 1));
      expect(segIdx, 0);
    });

    test('addSegment throws on invalid start', () {
      network.addVertex(NetworkVertex(position: Offset.zero));
      expect(
        () => network.addSegment(NetworkSegment(start: 5, end: 0)),
        throwsArgumentError,
      );
    });

    test('addSegment throws on self-loop', () {
      network.addVertex(NetworkVertex(position: Offset.zero));
      expect(
        () => network.addSegment(NetworkSegment(start: 0, end: 0)),
        throwsArgumentError,
      );
    });

    test('removeVertex removes connected segments', () {
      network.addVertex(NetworkVertex(position: Offset.zero));
      network.addVertex(NetworkVertex(position: const Offset(10, 0)));
      network.addVertex(NetworkVertex(position: const Offset(5, 10)));
      network.addSegment(NetworkSegment(start: 0, end: 1));
      network.addSegment(NetworkSegment(start: 1, end: 2));
      network.addSegment(NetworkSegment(start: 2, end: 0));

      network.removeVertex(1);
      expect(network.vertices.length, 2);
      expect(network.segments.length, 1);
    });

    test('removeSegment keeps vertices', () {
      network.addVertex(NetworkVertex(position: Offset.zero));
      network.addVertex(NetworkVertex(position: const Offset(10, 0)));
      network.addSegment(NetworkSegment(start: 0, end: 1));
      network.removeSegment(0);
      expect(network.segments.length, 0);
      expect(network.vertices.length, 2);
    });
  });

  // ===========================================================================
  // REVISION COUNTER
  // ===========================================================================

  group('VectorNetwork — Revision', () {
    test('revision increments on mutation', () {
      final network = VectorNetwork();
      final r0 = network.revision;
      network.addVertex(NetworkVertex(position: Offset.zero));
      expect(network.revision, greaterThan(r0));
      final r1 = network.revision;
      network.addVertex(NetworkVertex(position: const Offset(10, 0)));
      expect(network.revision, greaterThan(r1));
      final r2 = network.revision;
      network.addSegment(NetworkSegment(start: 0, end: 1));
      expect(network.revision, greaterThan(r2));
    });
  });

  // ===========================================================================
  // ADJACENCY MAP
  // ===========================================================================

  group('VectorNetwork — Adjacency', () {
    test('adjacentSegments returns correct indices', () {
      final network = VectorNetwork();
      network.addVertex(NetworkVertex(position: Offset.zero));
      network.addVertex(NetworkVertex(position: const Offset(100, 0)));
      network.addVertex(NetworkVertex(position: const Offset(50, 86)));
      network.addSegment(NetworkSegment(start: 0, end: 1));
      network.addSegment(NetworkSegment(start: 1, end: 2));
      network.addSegment(NetworkSegment(start: 2, end: 0));

      final adj0 = network.adjacentSegments(0);
      expect(adj0, containsAll([0, 2]));
      expect(adj0.length, 2);
    });

    test('adjacentSegments invalidates after mutation', () {
      final network = VectorNetwork();
      network.addVertex(NetworkVertex(position: Offset.zero));
      network.addVertex(NetworkVertex(position: const Offset(10, 0)));
      network.addSegment(NetworkSegment(start: 0, end: 1));
      expect(network.adjacentSegments(0).length, 1);

      network.addVertex(NetworkVertex(position: const Offset(20, 0)));
      network.addSegment(NetworkSegment(start: 0, end: 2));
      expect(network.adjacentSegments(0).length, 2);
    });
  });

  // ===========================================================================
  // TOPOLOGY
  // ===========================================================================

  group('VectorNetwork — Topology', () {
    late VectorNetwork network;

    setUp(() {
      network = VectorNetwork();
      network.addVertex(NetworkVertex(position: Offset.zero));
      network.addVertex(NetworkVertex(position: const Offset(100, 0)));
      network.addVertex(NetworkVertex(position: const Offset(50, 86)));
      network.addSegment(NetworkSegment(start: 0, end: 1));
      network.addSegment(NetworkSegment(start: 1, end: 2));
      network.addSegment(NetworkSegment(start: 2, end: 0));
    });

    test('degree', () {
      expect(network.degree(0), 2);
      expect(network.degree(1), 2);
    });

    test('oppositeVertex', () {
      expect(network.oppositeVertex(0, 0), 1);
      expect(network.oppositeVertex(0, 1), 0);
    });

    test('isConnected', () {
      expect(network.isConnected, isTrue);
    });

    test('connectedComponents', () {
      final components = network.connectedComponents();
      expect(components.length, 1);
      expect(components.first.length, 3);
    });

    test('disconnected components', () {
      network.addVertex(NetworkVertex(position: const Offset(200, 200)));
      final components = network.connectedComponents();
      expect(components.length, 2);
    });

    test('isDeadEnd and isJunction', () {
      network.addVertex(NetworkVertex(position: const Offset(-50, 0)));
      network.addSegment(NetworkSegment(start: 0, end: 3));
      expect(network.isJunction(0), isTrue);
      expect(network.isDeadEnd(3), isTrue);
    });
  });

  // ===========================================================================
  // VALIDATION
  // ===========================================================================

  group('VectorNetwork — Validation', () {
    test('valid network returns no errors', () {
      final network = VectorNetwork();
      network.addVertex(NetworkVertex(position: Offset.zero));
      network.addVertex(NetworkVertex(position: const Offset(10, 0)));
      network.addSegment(NetworkSegment(start: 0, end: 1));
      expect(network.validate(), isEmpty);
    });

    test('detects isolated vertex', () {
      final network = VectorNetwork();
      network.addVertex(NetworkVertex(position: Offset.zero));
      final errors = network.validate();
      expect(errors.length, 1);
      expect(errors.first.type, NetworkErrorType.isolatedVertex);
    });

    test('detects duplicate segments', () {
      final network = VectorNetwork(
        vertices: [
          NetworkVertex(position: Offset.zero),
          NetworkVertex(position: const Offset(10, 0)),
        ],
        segments: [
          NetworkSegment(start: 0, end: 1),
          NetworkSegment(start: 0, end: 1),
        ],
      );
      final errors = network.validate();
      expect(
        errors.any((e) => e.type == NetworkErrorType.duplicateSegment),
        isTrue,
      );
    });

    test('compact removes isolated vertices', () {
      final network = VectorNetwork();
      network.addVertex(NetworkVertex(position: Offset.zero));
      network.addVertex(NetworkVertex(position: const Offset(10, 0)));
      network.addVertex(NetworkVertex(position: const Offset(20, 0)));
      network.addSegment(NetworkSegment(start: 0, end: 1));
      // Vertex 2 is isolated.
      final removed = network.compact();
      expect(removed, 1);
      expect(network.vertices.length, 2);
    });
  });

  // ===========================================================================
  // HIT TESTING
  // ===========================================================================

  group('VectorNetwork — Hit Testing', () {
    late VectorNetwork network;

    setUp(() {
      network = VectorNetwork();
      network.addVertex(NetworkVertex(position: Offset.zero));
      network.addVertex(NetworkVertex(position: const Offset(100, 0)));
      network.addVertex(NetworkVertex(position: const Offset(50, 86)));
      network.addSegment(NetworkSegment(start: 0, end: 1));
      network.addSegment(NetworkSegment(start: 1, end: 2));
      network.addSegment(NetworkSegment(start: 2, end: 0));
    });

    test('hitTestVertex finds nearby vertex', () {
      expect(network.hitTestVertex(const Offset(2, 2), 5), 0);
      expect(network.hitTestVertex(const Offset(98, 1), 5), 1);
    });

    test('hitTestVertex returns null when too far', () {
      expect(network.hitTestVertex(const Offset(50, 50), 5), isNull);
    });

    test('hitTestSegment finds nearby segment', () {
      final idx = network.hitTestSegment(const Offset(50, 0), 5);
      expect(idx, 0); // Segment 0 runs from (0,0) to (100,0).
    });

    test('hitTestRegion on triangle', () {
      network.addRegion(
        NetworkRegion(
          loops: [
            RegionLoop(
              segments: [
                const SegmentRef(index: 0),
                const SegmentRef(index: 1),
                const SegmentRef(index: 2),
              ],
            ),
          ],
        ),
      );
      // Center of triangle (50, 28.67) should be inside.
      expect(network.hitTestRegion(const Offset(50, 28)), 0);
      // Point far outside should not be in any region.
      expect(network.hitTestRegion(const Offset(200, 200)), isNull);
    });

    test('nearestPointOnSegment straight', () {
      final (pt, t) = network.nearestPointOnSegment(0, const Offset(50, 10));
      expect(pt.dx, closeTo(50, 1));
      expect(pt.dy, closeTo(0, 1));
      expect(t, closeTo(0.5, 0.05));
    });
  });

  // ===========================================================================
  // PATH MATH
  // ===========================================================================

  group('VectorNetwork — Path Math', () {
    test('segmentLength straight', () {
      final network = VectorNetwork();
      network.addVertex(NetworkVertex(position: Offset.zero));
      network.addVertex(NetworkVertex(position: const Offset(100, 0)));
      network.addSegment(NetworkSegment(start: 0, end: 1));
      expect(network.segmentLength(0), closeTo(100, 0.01));
    });

    test('segmentLength curved > straight', () {
      final network = VectorNetwork();
      network.addVertex(NetworkVertex(position: Offset.zero));
      network.addVertex(NetworkVertex(position: const Offset(100, 0)));
      network.addSegment(
        NetworkSegment(
          start: 0,
          end: 1,
          tangentStart: const Offset(25, 80),
          tangentEnd: const Offset(75, 80),
        ),
      );
      expect(network.segmentLength(0), greaterThan(100));
    });

    test('pointOnSegment at endpoints', () {
      final network = VectorNetwork();
      network.addVertex(NetworkVertex(position: Offset.zero));
      network.addVertex(NetworkVertex(position: const Offset(100, 0)));
      network.addSegment(NetworkSegment(start: 0, end: 1));

      final start = network.pointOnSegment(0, 0);
      final end = network.pointOnSegment(0, 1);
      expect(start.dx, closeTo(0, 0.01));
      expect(end.dx, closeTo(100, 0.01));
    });

    test('tangentAtPoint straight is constant', () {
      final network = VectorNetwork();
      network.addVertex(NetworkVertex(position: Offset.zero));
      network.addVertex(NetworkVertex(position: const Offset(100, 0)));
      network.addSegment(NetworkSegment(start: 0, end: 1));

      final t0 = network.tangentAtPoint(0, 0);
      final t1 = network.tangentAtPoint(0, 0.5);
      expect(t0.dx, closeTo(t1.dx, 0.01));
      expect(t0.dy, closeTo(t1.dy, 0.01));
    });

    test('totalLength sums segments', () {
      final network = VectorNetwork();
      network.addVertex(NetworkVertex(position: Offset.zero));
      network.addVertex(NetworkVertex(position: const Offset(100, 0)));
      network.addVertex(NetworkVertex(position: const Offset(100, 100)));
      network.addSegment(NetworkSegment(start: 0, end: 1));
      network.addSegment(NetworkSegment(start: 1, end: 2));
      expect(network.totalLength(), closeTo(200, 0.01));
    });
  });

  // ===========================================================================
  // SIMPLIFY & SMOOTH
  // ===========================================================================

  group('VectorNetwork — Simplify & Smooth', () {
    test('simplify removes collinear vertex', () {
      final network = VectorNetwork();
      network.addVertex(NetworkVertex(position: Offset.zero));
      network.addVertex(NetworkVertex(position: const Offset(50, 0)));
      network.addVertex(NetworkVertex(position: const Offset(100, 0)));
      network.addSegment(NetworkSegment(start: 0, end: 1));
      network.addSegment(NetworkSegment(start: 1, end: 2));

      final removed = network.simplify(0.1);
      expect(removed, 1);
      expect(network.vertices.length, 2);
      expect(network.segments.length, 1);
    });

    test('simplify keeps non-collinear vertex', () {
      final network = VectorNetwork();
      network.addVertex(NetworkVertex(position: Offset.zero));
      network.addVertex(NetworkVertex(position: const Offset(50, 50)));
      network.addVertex(NetworkVertex(position: const Offset(100, 0)));
      network.addSegment(NetworkSegment(start: 0, end: 1));
      network.addSegment(NetworkSegment(start: 1, end: 2));

      final removed = network.simplify(0.1);
      expect(removed, 0);
    });

    test('smooth adds tangent handles', () {
      final network = VectorNetwork();
      network.addVertex(NetworkVertex(position: Offset.zero));
      network.addVertex(NetworkVertex(position: const Offset(50, 50)));
      network.addVertex(NetworkVertex(position: const Offset(100, 0)));
      network.addSegment(NetworkSegment(start: 0, end: 1));
      network.addSegment(NetworkSegment(start: 1, end: 2));

      network.smooth(0.3);
      // Vertex 1 (degree 2) should now have tangent handles.
      final seg0 = network.segments[0];
      final seg1 = network.segments[1];
      // At least one tangent on each segment should be non-null.
      expect(seg0.tangentStart != null || seg0.tangentEnd != null, isTrue);
      expect(seg1.tangentStart != null || seg1.tangentEnd != null, isTrue);
    });
  });

  // ===========================================================================
  // SNAP & GRID
  // ===========================================================================

  group('VectorNetwork — Snap & Grid', () {
    test('snapToGrid snaps positions', () {
      final network = VectorNetwork();
      network.addVertex(NetworkVertex(position: const Offset(13, 27)));
      network.addVertex(NetworkVertex(position: const Offset(96, 54)));

      network.snapToGrid(10);
      expect(network.vertices[0].position, const Offset(10, 30));
      expect(network.vertices[1].position, const Offset(100, 50));
    });

    test('snapVertexToNearest finds closest', () {
      final network = VectorNetwork();
      network.addVertex(NetworkVertex(position: Offset.zero));
      network.addVertex(NetworkVertex(position: const Offset(5, 0)));
      network.addVertex(NetworkVertex(position: const Offset(100, 0)));

      expect(network.snapVertexToNearest(0, 10), 1);
      expect(network.snapVertexToNearest(0, 3), isNull);
    });

    test('weldVertices merges close vertices', () {
      final network = VectorNetwork();
      network.addVertex(NetworkVertex(position: Offset.zero));
      network.addVertex(NetworkVertex(position: const Offset(1, 0)));
      network.addVertex(NetworkVertex(position: const Offset(100, 0)));
      network.addSegment(NetworkSegment(start: 0, end: 2));
      network.addSegment(NetworkSegment(start: 1, end: 2));

      final merges = network.weldVertices(5);
      expect(merges, 1);
      expect(network.vertices.length, 2);
    });
  });

  // ===========================================================================
  // SVG CONVERSION
  // ===========================================================================

  group('VectorNetworkSvg', () {
    test('toSvgPath straight line', () {
      final network = VectorNetwork();
      network.addVertex(NetworkVertex(position: Offset.zero));
      network.addVertex(NetworkVertex(position: const Offset(100, 0)));
      network.addSegment(NetworkSegment(start: 0, end: 1));

      final d = VectorNetworkSvg.toSvgPath(network);
      expect(d, contains('M'));
      expect(d, contains('L'));
    });

    test('toSvgPath cubic curve', () {
      final network = VectorNetwork();
      network.addVertex(NetworkVertex(position: Offset.zero));
      network.addVertex(NetworkVertex(position: const Offset(100, 0)));
      network.addSegment(
        NetworkSegment(
          start: 0,
          end: 1,
          tangentStart: const Offset(25, 50),
          tangentEnd: const Offset(75, 50),
        ),
      );

      final d = VectorNetworkSvg.toSvgPath(network);
      expect(d, contains('C'));
    });

    test('fromSvgPath roundtrip — triangle', () {
      const d = 'M 0 0 L 100 0 L 50 86 Z';
      final network = VectorNetworkSvg.fromSvgPath(d);
      expect(network.vertices.length, 3);
      expect(network.segments.length, 3);
    });

    test('fromSvgPath roundtrip — cubic', () {
      const d = 'M 0 0 C 25 50 75 50 100 0';
      final network = VectorNetworkSvg.fromSvgPath(d);
      expect(network.vertices.length, 2);
      expect(network.segments.length, 1);
      expect(network.segments[0].tangentStart, isNotNull);
      expect(network.segments[0].tangentEnd, isNotNull);
    });

    test('fromSvgPath roundtrip — quadratic', () {
      const d = 'M 0 0 Q 50 100 100 0';
      final network = VectorNetworkSvg.fromSvgPath(d);
      expect(network.vertices.length, 2);
      expect(network.segments.length, 1);
      expect(network.segments[0].tangentStart, isNotNull);
    });

    test('full roundtrip export/import', () {
      final original = VectorNetwork();
      original.addVertex(NetworkVertex(position: Offset.zero));
      original.addVertex(NetworkVertex(position: const Offset(100, 0)));
      original.addVertex(NetworkVertex(position: const Offset(50, 86)));
      original.addSegment(NetworkSegment(start: 0, end: 1));
      original.addSegment(NetworkSegment(start: 1, end: 2));
      original.addSegment(NetworkSegment(start: 2, end: 0));

      final d = VectorNetworkSvg.toSvgPath(original);
      expect(d, isNotEmpty);
      final restored = VectorNetworkSvg.fromSvgPath(d);
      // SVG roundtrip may add extra vertices due to Z close semantics.
      // Verify that the restored network is connected.
      expect(restored.isConnected, isTrue);
      expect(restored.vertices.length, greaterThanOrEqualTo(3));
      expect(restored.segments.length, greaterThanOrEqualTo(3));
    });
  });

  // ===========================================================================
  // SERIALIZATION
  // ===========================================================================

  group('VectorNetwork — Serialization', () {
    test('full roundtrip', () {
      final original = VectorNetwork();
      original.addVertex(NetworkVertex(position: Offset.zero));
      original.addVertex(NetworkVertex(position: const Offset(100, 0)));
      original.addVertex(NetworkVertex(position: const Offset(50, 86)));
      original.addSegment(NetworkSegment(start: 0, end: 1));
      original.addSegment(
        NetworkSegment(
          start: 1,
          end: 2,
          tangentStart: const Offset(120, 30),
          tangentEnd: const Offset(80, 60),
        ),
      );
      original.addSegment(NetworkSegment(start: 2, end: 0));
      original.addRegion(
        NetworkRegion(
          loops: [
            RegionLoop(
              segments: [
                const SegmentRef(index: 0),
                const SegmentRef(index: 1),
                const SegmentRef(index: 2, reversed: true),
              ],
            ),
          ],
        ),
      );

      final json = original.toJson();
      final restored = VectorNetwork.fromJson(json);
      expect(restored.vertices.length, 3);
      expect(restored.segments.length, 3);
      expect(restored.regions.length, 1);
      expect(restored.segments[1].tangentStart!.dx, closeTo(120, 0.001));
      expect(restored.regions[0].loops[0].segments[2].reversed, isTrue);
    });

    test('clone produces independent copy', () {
      final original = VectorNetwork();
      original.addVertex(NetworkVertex(position: Offset.zero));
      original.addVertex(NetworkVertex(position: const Offset(10, 0)));
      original.addSegment(NetworkSegment(start: 0, end: 1));

      final clone = original.clone();
      clone.vertices[0].position = const Offset(99, 99);
      expect(original.vertices[0].position, Offset.zero);
    });
  });

  // ===========================================================================
  // SPLIT & MERGE
  // ===========================================================================

  group('VectorNetwork — splitSegment', () {
    test('split straight segment at midpoint', () {
      final network = VectorNetwork();
      network.addVertex(NetworkVertex(position: Offset.zero));
      network.addVertex(NetworkVertex(position: const Offset(100, 0)));
      network.addSegment(NetworkSegment(start: 0, end: 1));

      final newVertex = network.splitSegment(0, 0.5);
      expect(network.vertices.length, 3);
      expect(network.segments.length, 2);
      expect(network.vertices[newVertex].position.dx, closeTo(50, 0.1));
    });

    test('split curved segment', () {
      final network = VectorNetwork();
      network.addVertex(NetworkVertex(position: Offset.zero));
      network.addVertex(NetworkVertex(position: const Offset(100, 0)));
      network.addSegment(
        NetworkSegment(
          start: 0,
          end: 1,
          tangentStart: const Offset(25, 50),
          tangentEnd: const Offset(75, 50),
        ),
      );

      final newVertex = network.splitSegment(0, 0.5);
      expect(network.vertices.length, 3);
      expect(network.segments.length, 2);
      expect(network.vertices[newVertex].position.dy, greaterThan(0));
    });
  });

  group('VectorNetwork — mergeVertices', () {
    test('merge creates midpoint and reconnects', () {
      final network = VectorNetwork();
      network.addVertex(NetworkVertex(position: Offset.zero));
      network.addVertex(NetworkVertex(position: const Offset(10, 0)));
      network.addVertex(NetworkVertex(position: const Offset(20, 0)));
      network.addSegment(NetworkSegment(start: 0, end: 1));
      network.addSegment(NetworkSegment(start: 1, end: 2));

      network.mergeVertices(0, 1);
      expect(network.vertices.length, 2);
      expect(network.vertices[0].position.dx, closeTo(5, 0.1));
    });
  });

  // ===========================================================================
  // CONVERSION & BOUNDS
  // ===========================================================================

  group('VectorNetwork — Conversion', () {
    test('toVectorPaths creates paths', () {
      final network = VectorNetwork();
      network.addVertex(NetworkVertex(position: Offset.zero));
      network.addVertex(NetworkVertex(position: const Offset(100, 0)));
      network.addSegment(NetworkSegment(start: 0, end: 1));

      final paths = network.toVectorPaths();
      expect(paths.length, greaterThanOrEqualTo(1));
    });

    test('fromVectorPath roundtrip', () {
      final path = VectorPath.moveTo(Offset.zero);
      path.lineTo(100, 0);
      path.lineTo(50, 86);
      path.close();

      final network = VectorNetwork.fromVectorPath(path);
      expect(network.vertices.length, 3);
      expect(network.segments.length, 3);
    });

    test('regionToFlutterPath produces non-empty path', () {
      final network = VectorNetwork();
      network.addVertex(NetworkVertex(position: Offset.zero));
      network.addVertex(NetworkVertex(position: const Offset(100, 0)));
      network.addVertex(NetworkVertex(position: const Offset(50, 86)));
      network.addSegment(NetworkSegment(start: 0, end: 1));
      network.addSegment(NetworkSegment(start: 1, end: 2));
      network.addSegment(NetworkSegment(start: 2, end: 0));
      network.addRegion(
        NetworkRegion(
          loops: [
            RegionLoop(
              segments: [
                const SegmentRef(index: 0),
                const SegmentRef(index: 1),
                const SegmentRef(index: 2),
              ],
            ),
          ],
        ),
      );

      final flutterPath = network.regionToFlutterPath(0);
      final bounds = flutterPath.getBounds();
      expect(bounds.width, greaterThan(0));
      expect(bounds.height, greaterThan(0));
    });
  });

  group('VectorNetwork — Bounds', () {
    test('computeBounds includes vertices', () {
      final network = VectorNetwork();
      network.addVertex(NetworkVertex(position: const Offset(-10, -20)));
      network.addVertex(NetworkVertex(position: const Offset(100, 50)));
      final bounds = network.computeBounds();
      expect(bounds.left, -10);
      expect(bounds.top, -20);
      expect(bounds.right, 100);
      expect(bounds.bottom, 50);
    });

    test('computeBounds includes tangent handles', () {
      final network = VectorNetwork();
      network.addVertex(NetworkVertex(position: Offset.zero));
      network.addVertex(NetworkVertex(position: const Offset(100, 0)));
      network.addSegment(
        NetworkSegment(
          start: 0,
          end: 1,
          tangentStart: const Offset(50, -100),
          tangentEnd: const Offset(50, 100),
        ),
      );
      final bounds = network.computeBounds();
      expect(bounds.top, -100);
      expect(bounds.bottom, 100);
    });

    test('empty network bounds', () {
      final network = VectorNetwork();
      expect(network.computeBounds(), Rect.zero);
    });
  });

  // ===========================================================================
  // REGION DETECTION
  // ===========================================================================

  group('VectorNetwork — Region detection', () {
    test('findRegions detects a triangle', () {
      final network = VectorNetwork();
      network.addVertex(NetworkVertex(position: Offset.zero));
      network.addVertex(NetworkVertex(position: const Offset(100, 0)));
      network.addVertex(NetworkVertex(position: const Offset(50, 86)));
      network.addSegment(NetworkSegment(start: 0, end: 1));
      network.addSegment(NetworkSegment(start: 1, end: 2));
      network.addSegment(NetworkSegment(start: 2, end: 0));

      final regions = network.findRegions();
      expect(regions.length, greaterThanOrEqualTo(1));
    });

    test('findRegions on open path finds no regions', () {
      final network = VectorNetwork();
      network.addVertex(NetworkVertex(position: Offset.zero));
      network.addVertex(NetworkVertex(position: const Offset(100, 0)));
      network.addVertex(NetworkVertex(position: const Offset(200, 0)));
      network.addSegment(NetworkSegment(start: 0, end: 1));
      network.addSegment(NetworkSegment(start: 1, end: 2));

      final regions = network.findRegions();
      expect(regions, isEmpty);
    });
  });

  // ===========================================================================
  // NODE SERIALIZATION
  // ===========================================================================

  group('VectorNetworkNode', () {
    test('fromJson/toJson roundtrip', () {
      final network = VectorNetwork();
      network.addVertex(NetworkVertex(position: Offset.zero));
      network.addVertex(NetworkVertex(position: const Offset(100, 0)));
      network.addSegment(NetworkSegment(start: 0, end: 1));

      final node = VectorNetworkNode(
        id: NodeId('test-node-1'),
        network: network,
        fills: [FillLayer.solid(color: const Color(0xFFFF0000))],
        strokes: [StrokeLayer(color: const Color(0xFF000000), width: 3.0)],
      );

      final json = node.toJson();
      expect(json['nodeType'], 'vector_network');

      final restored = VectorNetworkNode.fromJson(json);
      expect(restored.id, 'test-node-1');
      expect(restored.network.vertices.length, 2);
      expect(restored.strokes.first.width, 3.0);
      expect(restored.fills.first.color, const Color(0xFFFF0000));
    });

    test('localBounds includes stroke width', () {
      final network = VectorNetwork();
      network.addVertex(NetworkVertex(position: Offset.zero));
      network.addVertex(NetworkVertex(position: const Offset(100, 100)));
      network.addSegment(NetworkSegment(start: 0, end: 1));

      final node = VectorNetworkNode(
        id: NodeId('bounds-test'),
        network: network,
        strokes: [StrokeLayer(width: 4.0, color: const Color(0xFF000000))],
      );

      final bounds = node.localBounds;
      expect(bounds.left, -2.0);
      expect(bounds.top, -2.0);
      expect(bounds.right, 102.0);
      expect(bounds.bottom, 102.0);
    });

    test('regionFills serialization', () {
      final network = VectorNetwork();
      network.addVertex(NetworkVertex(position: Offset.zero));
      network.addVertex(NetworkVertex(position: const Offset(100, 0)));
      network.addVertex(NetworkVertex(position: const Offset(50, 86)));
      network.addSegment(NetworkSegment(start: 0, end: 1));
      network.addSegment(NetworkSegment(start: 1, end: 2));
      network.addSegment(NetworkSegment(start: 2, end: 0));

      final node = VectorNetworkNode(
        id: NodeId('region-fill-test'),
        network: network,
        regionFills: [
          RegionFill(regionIndex: 0, color: const Color(0xFF00FF00)),
        ],
      );

      final json = node.toJson();
      final restored = VectorNetworkNode.fromJson(json);
      expect(restored.regionFills.length, 1);
      expect(restored.regionFills[0].color, const Color(0xFF00FF00));
    });
  });

  // ===========================================================================
  // FLUTTER PATH CONVERSION
  // ===========================================================================

  group('VectorNetwork — toFlutterPath / fromFlutterPath', () {
    test('toFlutterPath produces non-empty path', () {
      final network = VectorNetwork();
      network.addVertex(NetworkVertex(position: Offset.zero));
      network.addVertex(NetworkVertex(position: const Offset(100, 0)));
      network.addSegment(NetworkSegment(start: 0, end: 1));

      final path = network.toFlutterPath();
      expect(path.getBounds().width, greaterThan(0));
    });

    test('toFlutterPath handles cubic curves', () {
      final network = VectorNetwork();
      network.addVertex(NetworkVertex(position: Offset.zero));
      network.addVertex(NetworkVertex(position: const Offset(100, 0)));
      network.addSegment(
        NetworkSegment(
          start: 0,
          end: 1,
          tangentStart: const Offset(25, 50),
          tangentEnd: const Offset(75, 50),
        ),
      );

      final path = network.toFlutterPath();
      final bounds = path.getBounds();
      expect(bounds.height, greaterThan(0));
    });

    test('fromFlutterPath creates valid network', () {
      final network = VectorNetwork();
      network.addVertex(NetworkVertex(position: Offset.zero));
      network.addVertex(NetworkVertex(position: const Offset(100, 0)));
      network.addVertex(NetworkVertex(position: const Offset(50, 86)));
      network.addSegment(NetworkSegment(start: 0, end: 1));
      network.addSegment(NetworkSegment(start: 1, end: 2));
      network.addSegment(NetworkSegment(start: 2, end: 0));

      final flutterPath = network.toFlutterPath();
      final restored = VectorNetwork.fromFlutterPath(flutterPath);
      expect(restored.vertices.length, greaterThan(0));
      expect(restored.segments.length, greaterThan(0));
    });

    test('empty network produces empty path', () {
      final network = VectorNetwork();
      final path = network.toFlutterPath();
      expect(path.getBounds(), Rect.zero);
    });
  });

  // ===========================================================================
  // BOOLEAN OPS ON VECTOR NETWORK
  // ===========================================================================

  group('BooleanOps — VectorNetwork', () {
    late VectorNetwork squareA;
    late VectorNetwork squareB;

    setUp(() {
      // Square A: (0,0) → (100,0) → (100,100) → (0,100)
      squareA = VectorNetwork();
      squareA.addVertex(NetworkVertex(position: Offset.zero));
      squareA.addVertex(NetworkVertex(position: const Offset(100, 0)));
      squareA.addVertex(NetworkVertex(position: const Offset(100, 100)));
      squareA.addVertex(NetworkVertex(position: const Offset(0, 100)));
      squareA.addSegment(NetworkSegment(start: 0, end: 1));
      squareA.addSegment(NetworkSegment(start: 1, end: 2));
      squareA.addSegment(NetworkSegment(start: 2, end: 3));
      squareA.addSegment(NetworkSegment(start: 3, end: 0));

      // Square B: (50,50) → (150,50) → (150,150) → (50,150) — overlapping
      squareB = VectorNetwork();
      squareB.addVertex(NetworkVertex(position: const Offset(50, 50)));
      squareB.addVertex(NetworkVertex(position: const Offset(150, 50)));
      squareB.addVertex(NetworkVertex(position: const Offset(150, 150)));
      squareB.addVertex(NetworkVertex(position: const Offset(50, 150)));
      squareB.addSegment(NetworkSegment(start: 0, end: 1));
      squareB.addSegment(NetworkSegment(start: 1, end: 2));
      squareB.addSegment(NetworkSegment(start: 2, end: 3));
      squareB.addSegment(NetworkSegment(start: 3, end: 0));
    });

    test('union produces larger network', () {
      final result = BooleanOps.executeOnNetworks(
        BooleanOpType.union,
        squareA,
        squareB,
      );
      expect(result.vertices.length, greaterThan(0));
      expect(result.segments.length, greaterThan(0));
    });

    test('intersect produces result', () {
      final result = BooleanOps.executeOnNetworks(
        BooleanOpType.intersect,
        squareA,
        squareB,
      );
      expect(result.vertices.length, greaterThan(0));
    });

    test('subtract produces result', () {
      final result = BooleanOps.executeOnNetworks(
        BooleanOpType.subtract,
        squareA,
        squareB,
      );
      expect(result.vertices.length, greaterThan(0));
    });

    test('exclude produces result', () {
      final result = BooleanOps.executeOnNetworks(
        BooleanOpType.exclude,
        squareA,
        squareB,
      );
      expect(result.vertices.length, greaterThan(0));
    });
  });

  // ===========================================================================
  // UNDO/REDO COMMANDS
  // ===========================================================================

  group('VectorNetwork Commands — AddVertex', () {
    test('execute adds, undo removes', () {
      final network = VectorNetwork();
      network.addVertex(NetworkVertex(position: Offset.zero));
      final node = VectorNetworkNode(id: NodeId('cmd-test'), network: network);

      final cmd = AddVertexCommand(
        node: node,
        vertex: NetworkVertex(position: const Offset(50, 50)),
      );
      cmd.execute();
      expect(node.network.vertices.length, 2);
      expect(cmd.insertedIndex, 1);

      cmd.undo();
      expect(node.network.vertices.length, 1);

      cmd.redo();
      expect(node.network.vertices.length, 2);
    });
  });

  group('VectorNetwork Commands — RemoveVertex', () {
    test('execute removes, undo restores full state', () {
      final network = VectorNetwork();
      network.addVertex(NetworkVertex(position: Offset.zero));
      network.addVertex(NetworkVertex(position: const Offset(100, 0)));
      network.addVertex(NetworkVertex(position: const Offset(50, 86)));
      network.addSegment(NetworkSegment(start: 0, end: 1));
      network.addSegment(NetworkSegment(start: 1, end: 2));
      network.addSegment(NetworkSegment(start: 2, end: 0));
      final node = VectorNetworkNode(id: NodeId('cmd-test'), network: network);

      final cmd = RemoveVertexCommand(node: node, vertexIndex: 1);
      cmd.execute();
      expect(node.network.vertices.length, 2);

      cmd.undo();
      expect(node.network.vertices.length, 3);
      expect(node.network.segments.length, 3);
    });
  });

  group('VectorNetwork Commands — AddSegment', () {
    test('execute adds, undo removes', () {
      final network = VectorNetwork();
      network.addVertex(NetworkVertex(position: Offset.zero));
      network.addVertex(NetworkVertex(position: const Offset(100, 0)));
      final node = VectorNetworkNode(id: NodeId('cmd-test'), network: network);

      final cmd = AddSegmentCommand(
        node: node,
        segment: NetworkSegment(start: 0, end: 1),
      );
      cmd.execute();
      expect(node.network.segments.length, 1);

      cmd.undo();
      expect(node.network.segments.length, 0);
    });
  });

  group('VectorNetwork Commands — RemoveSegment', () {
    test('execute removes, undo restores', () {
      final network = VectorNetwork();
      network.addVertex(NetworkVertex(position: Offset.zero));
      network.addVertex(NetworkVertex(position: const Offset(100, 0)));
      network.addSegment(NetworkSegment(start: 0, end: 1));
      final node = VectorNetworkNode(id: NodeId('cmd-test'), network: network);

      final cmd = RemoveSegmentCommand(node: node, segmentIndex: 0);
      cmd.execute();
      expect(node.network.segments.length, 0);

      cmd.undo();
      expect(node.network.segments.length, 1);
    });
  });

  group('VectorNetwork Commands — MoveVertex', () {
    test('execute moves, undo restores', () {
      final network = VectorNetwork();
      network.addVertex(NetworkVertex(position: Offset.zero));
      final node = VectorNetworkNode(id: NodeId('cmd-test'), network: network);

      final cmd = MoveVertexCommand(
        node: node,
        vertexIndex: 0,
        newPosition: const Offset(99, 99),
      );
      cmd.execute();
      expect(node.network.vertices[0].position, const Offset(99, 99));

      cmd.undo();
      expect(node.network.vertices[0].position, Offset.zero);
    });

    test('drag coalescing merges positions', () {
      final network = VectorNetwork();
      network.addVertex(NetworkVertex(position: Offset.zero));
      final node = VectorNetworkNode(id: NodeId('cmd-test'), network: network);

      final cmd1 = MoveVertexCommand(
        node: node,
        vertexIndex: 0,
        newPosition: const Offset(10, 10),
      );
      final cmd2 = MoveVertexCommand(
        node: node,
        vertexIndex: 0,
        newPosition: const Offset(20, 20),
      );

      expect(cmd1.canMergeWith(cmd2), isTrue);
      cmd1.execute();
      cmd1.mergeWith(cmd2);
      cmd1.execute();
      expect(node.network.vertices[0].position, const Offset(20, 20));

      cmd1.undo();
      expect(node.network.vertices[0].position, Offset.zero);
    });
  });

  group('VectorNetwork Commands — NetworkBoolean', () {
    test('execute applies, undo restores both networks', () {
      final netA = VectorNetwork();
      netA.addVertex(NetworkVertex(position: Offset.zero));
      netA.addVertex(NetworkVertex(position: const Offset(100, 0)));
      netA.addVertex(NetworkVertex(position: const Offset(100, 100)));
      netA.addVertex(NetworkVertex(position: const Offset(0, 100)));
      netA.addSegment(NetworkSegment(start: 0, end: 1));
      netA.addSegment(NetworkSegment(start: 1, end: 2));
      netA.addSegment(NetworkSegment(start: 2, end: 3));
      netA.addSegment(NetworkSegment(start: 3, end: 0));

      final netB = VectorNetwork();
      netB.addVertex(NetworkVertex(position: const Offset(50, 50)));
      netB.addVertex(NetworkVertex(position: const Offset(150, 50)));
      netB.addVertex(NetworkVertex(position: const Offset(150, 150)));
      netB.addVertex(NetworkVertex(position: const Offset(50, 150)));
      netB.addSegment(NetworkSegment(start: 0, end: 1));
      netB.addSegment(NetworkSegment(start: 1, end: 2));
      netB.addSegment(NetworkSegment(start: 2, end: 3));
      netB.addSegment(NetworkSegment(start: 3, end: 0));

      final nodeA = VectorNetworkNode(id: NodeId('a'), network: netA);
      final nodeB = VectorNetworkNode(id: NodeId('b'), network: netB);

      final origAVertCount = nodeA.network.vertices.length;
      final origBVertCount = nodeB.network.vertices.length;

      final cmd = NetworkBooleanCommand(
        targetNode: nodeA,
        otherNode: nodeB,
        operation: BooleanOpType.union,
      );
      cmd.execute();
      // Target network should be different after boolean op.
      expect(
        nodeA.network.vertices.length != origAVertCount ||
            nodeA.network.segments.length != 4,
        isTrue,
      );

      cmd.undo();
      expect(nodeA.network.vertices.length, origAVertCount);
      expect(nodeB.network.vertices.length, origBVertCount);
    });
  });

  // ===========================================================================
  // SPATIAL INDEX
  // ===========================================================================

  group('NetworkSpatialIndex', () {
    test('build and queryVertices', () {
      final network = VectorNetwork();
      network.addVertex(NetworkVertex(position: Offset.zero));
      network.addVertex(NetworkVertex(position: const Offset(100, 0)));
      network.addVertex(NetworkVertex(position: const Offset(200, 200)));
      network.addSegment(NetworkSegment(start: 0, end: 1));
      network.addSegment(NetworkSegment(start: 1, end: 2));

      final index = NetworkSpatialIndex.build(network);
      final found = index.queryVertices(const Rect.fromLTWH(-10, -10, 120, 20));
      expect(found, containsAll([0, 1]));
      expect(found, isNot(contains(2)));
    });

    test('querySegments finds overlapping', () {
      final network = VectorNetwork();
      network.addVertex(NetworkVertex(position: Offset.zero));
      network.addVertex(NetworkVertex(position: const Offset(100, 0)));
      network.addVertex(NetworkVertex(position: const Offset(200, 200)));
      network.addSegment(NetworkSegment(start: 0, end: 1));
      network.addSegment(NetworkSegment(start: 1, end: 2));

      final index = NetworkSpatialIndex.build(network);
      final found = index.querySegments(const Rect.fromLTWH(-10, -10, 50, 20));
      expect(found, contains(0));
    });

    test('nearestVertex finds closest', () {
      final network = VectorNetwork();
      network.addVertex(NetworkVertex(position: Offset.zero));
      network.addVertex(NetworkVertex(position: const Offset(100, 0)));

      final index = NetworkSpatialIndex.build(network);
      expect(index.nearestVertex(const Offset(5, 5), 20), 0);
      expect(index.nearestVertex(const Offset(95, 0), 20), 1);
      expect(index.nearestVertex(const Offset(500, 500), 5), isNull);
    });

    test('nearestSegment finds closest', () {
      final network = VectorNetwork();
      network.addVertex(NetworkVertex(position: Offset.zero));
      network.addVertex(NetworkVertex(position: const Offset(100, 0)));
      network.addSegment(NetworkSegment(start: 0, end: 1));

      final index = NetworkSpatialIndex.build(network);
      expect(index.nearestSegment(const Offset(50, 3), 10), 0);
      expect(index.nearestSegment(const Offset(50, 500), 5), isNull);
    });

    test('isStale detects mutation', () {
      final network = VectorNetwork();
      network.addVertex(NetworkVertex(position: Offset.zero));
      final index = NetworkSpatialIndex.build(network);
      expect(index.isStale, isFalse);

      network.addVertex(NetworkVertex(position: const Offset(10, 0)));
      expect(index.isStale, isTrue);
    });

    test('spatialIndex getter rebuilds when stale', () {
      final network = VectorNetwork();
      network.addVertex(NetworkVertex(position: Offset.zero));
      network.addVertex(NetworkVertex(position: const Offset(100, 0)));
      network.addSegment(NetworkSegment(start: 0, end: 1));

      final idx1 = network.spatialIndex;
      expect(idx1.isStale, isFalse);

      network.addVertex(NetworkVertex(position: const Offset(50, 50)));
      final idx2 = network.spatialIndex;
      expect(idx2.isStale, isFalse); // Rebuilt automatically.
      expect(identical(idx1, idx2), isFalse);
    });

    test('large network hit testing via spatial index', () {
      final network = VectorNetwork();
      // Create 100 vertices in a grid.
      for (int y = 0; y < 10; y++) {
        for (int x = 0; x < 10; x++) {
          network.addVertex(
            NetworkVertex(position: Offset(x * 10.0, y * 10.0)),
          );
        }
      }
      // Create horizontal segments.
      for (int y = 0; y < 10; y++) {
        for (int x = 0; x < 9; x++) {
          final idx = y * 10 + x;
          network.addSegment(NetworkSegment(start: idx, end: idx + 1));
        }
      }

      // Should use spatial index (>50 vertices/segments).
      final vertexHit = network.hitTestVertex(const Offset(0.5, 0.5), 2.0);
      expect(vertexHit, 0);

      final segHit = network.hitTestSegment(const Offset(5, 0), 2.0);
      expect(segHit, isNotNull);
    });
  });

  // ===========================================================================
  // PHASE 3: R-TREE SPATIAL INDEX
  // ===========================================================================

  group('R-tree spatial index', () {
    test('build and query vertices', () {
      final network = VectorNetwork();
      for (int i = 0; i < 100; i++) {
        network.addVertex(NetworkVertex(position: Offset(i * 10.0, i * 10.0)));
      }
      // Connect some.
      for (int i = 0; i < 99; i++) {
        network.addSegment(NetworkSegment(start: i, end: i + 1));
      }

      final idx = NetworkSpatialIndex.build(network);
      expect(idx.isStale, false);
      expect(idx.revision, network.revision);

      // Query region that should contain vertices 0-5 (positions 0,0 to 50,50).
      final hits = idx.queryVertices(const Rect.fromLTRB(0, 0, 55, 55));
      expect(hits.length, greaterThanOrEqualTo(5));
      expect(hits, contains(0));
      expect(hits, contains(5));
    });

    test('query segments', () {
      final network = VectorNetwork();
      network.addVertex(NetworkVertex(position: Offset.zero));
      network.addVertex(NetworkVertex(position: const Offset(100, 0)));
      network.addVertex(NetworkVertex(position: const Offset(200, 200)));
      network.addSegment(NetworkSegment(start: 0, end: 1));
      network.addSegment(NetworkSegment(start: 1, end: 2));

      final idx = NetworkSpatialIndex.build(network);
      final segHits = idx.querySegments(const Rect.fromLTRB(0, -5, 50, 5));
      expect(segHits, contains(0)); // seg 0→1 passes through
    });

    test('nearest vertex', () {
      final network = VectorNetwork();
      network.addVertex(NetworkVertex(position: const Offset(10, 10)));
      network.addVertex(NetworkVertex(position: const Offset(100, 100)));
      network.addSegment(NetworkSegment(start: 0, end: 1));

      final idx = NetworkSpatialIndex.build(network);
      final nearest = idx.nearestVertex(const Offset(12, 12), 20);
      expect(nearest, 0);
    });

    test('staleness detection', () {
      final network = VectorNetwork();
      network.addVertex(NetworkVertex(position: Offset.zero));
      final idx = NetworkSpatialIndex.build(network);
      expect(idx.isStale, false);

      network.addVertex(NetworkVertex(position: const Offset(1, 1)));
      expect(idx.isStale, true);
    });

    test('empty network returns empty results', () {
      final network = VectorNetwork();
      final idx = NetworkSpatialIndex.build(network);
      expect(idx.queryVertices(const Rect.fromLTRB(0, 0, 100, 100)), isEmpty);
      expect(idx.querySegments(const Rect.fromLTRB(0, 0, 100, 100)), isEmpty);
      expect(idx.nearestVertex(Offset.zero, 10), isNull);
      expect(idx.nearestSegment(Offset.zero, 10), isNull);
    });
  });

  // ===========================================================================
  // PHASE 3: BÉZIER CLIPPING
  // ===========================================================================

  group('BezierClipping', () {
    test('De Casteljau split at 0.5 produces two sub-curves', () {
      final c = CubicBezier(
        Offset.zero,
        const Offset(0, 100),
        const Offset(100, 100),
        const Offset(100, 0),
      );
      final (left, right) = BezierClipping.splitAt(c, 0.5);

      // left starts at c.p0, right ends at c.p3
      expect(left.p0, c.p0);
      expect(right.p3, c.p3);

      // Both meet at the split point (shared endpoint).
      expect((left.p3 - right.p0).distance, lessThan(0.01));

      // Split point should be on the original curve.
      final midOriginal = c.pointAt(0.5);
      expect((left.p3 - midOriginal).distance, lessThan(0.01));
    });

    test('line → cubic is collinear', () {
      final c = BezierClipping.lineToCubic(Offset.zero, const Offset(100, 0));
      // All 4 points should have y ≈ 0.
      expect(c.p0.dy, closeTo(0, 0.01));
      expect(c.p1.dy, closeTo(0, 0.01));
      expect(c.p2.dy, closeTo(0, 0.01));
      expect(c.p3.dy, closeTo(0, 0.01));
    });

    test('intersectCubics finds crossing of two lines', () {
      // Horizontal line (0,50) → (100,50)
      final a = BezierClipping.lineToCubic(
        const Offset(0, 50),
        const Offset(100, 50),
      );
      // Vertical line (50,0) → (50,100)
      final b = BezierClipping.lineToCubic(
        const Offset(50, 0),
        const Offset(50, 100),
      );

      final hits = BezierClipping.intersectCubics(a, b);
      expect(hits, isNotEmpty);

      // The intersection should be near (50, 50).
      final point = a.pointAt(hits.first.$1);
      expect(point.dx, closeTo(50, 1));
      expect(point.dy, closeTo(50, 1));
    });

    test('winding number detects inside/outside of a square', () {
      // Square: (0,0) → (100,0) → (100,100) → (0,100) → (0,0)
      final boundary = [
        BezierClipping.lineToCubic(Offset.zero, const Offset(100, 0)),
        BezierClipping.lineToCubic(
          const Offset(100, 0),
          const Offset(100, 100),
        ),
        BezierClipping.lineToCubic(
          const Offset(100, 100),
          const Offset(0, 100),
        ),
        BezierClipping.lineToCubic(const Offset(0, 100), Offset.zero),
      ];

      // Point inside.
      final windingInside = BezierClipping.windingNumber(
        const Offset(50, 50),
        boundary,
      );
      expect(windingInside, isNot(0));

      // Point outside.
      final windingOutside = BezierClipping.windingNumber(
        const Offset(200, 200),
        boundary,
      );
      expect(windingOutside, 0);
    });
  });

  // ===========================================================================
  // PHASE 3: GEOMETRIC CONSTRAINTS
  // ===========================================================================

  group('Geometric constraints', () {
    test('horizontal constraint forces same Y', () {
      final network = VectorNetwork();
      network.addVertex(NetworkVertex(position: const Offset(0, 10)));
      network.addVertex(NetworkVertex(position: const Offset(100, 30)));
      network.addSegment(NetworkSegment(start: 0, end: 1));

      final c = GeometricConstraint(
        type: ConstraintType.horizontal,
        vertexIndices: [0, 1],
      );
      final solver = ConstraintSolver(network: network, constraints: [c]);
      final converged = solver.solve();
      expect(converged, true);
      expect(
        network.vertices[0].position.dy,
        closeTo(network.vertices[1].position.dy, 0.1),
      );
    });

    test('vertical constraint forces same X', () {
      final network = VectorNetwork();
      network.addVertex(NetworkVertex(position: const Offset(10, 0)));
      network.addVertex(NetworkVertex(position: const Offset(30, 100)));
      network.addSegment(NetworkSegment(start: 0, end: 1));

      final c = GeometricConstraint(
        type: ConstraintType.vertical,
        vertexIndices: [0, 1],
      );
      final solver = ConstraintSolver(network: network, constraints: [c]);
      solver.solve();
      expect(
        network.vertices[0].position.dx,
        closeTo(network.vertices[1].position.dx, 0.1),
      );
    });

    test('fixedLength constraint', () {
      final network = VectorNetwork();
      network.addVertex(NetworkVertex(position: Offset.zero));
      network.addVertex(NetworkVertex(position: const Offset(50, 0)));
      network.addSegment(NetworkSegment(start: 0, end: 1));

      final c = GeometricConstraint(
        type: ConstraintType.fixedLength,
        vertexIndices: [0, 1],
        value: 100,
      );
      final solver = ConstraintSolver(network: network, constraints: [c]);
      solver.solve();

      final dist =
          (network.vertices[1].position - network.vertices[0].position)
              .distance;
      expect(dist, closeTo(100, 0.5));
    });

    test('coincident constraint merges positions', () {
      final network = VectorNetwork();
      network.addVertex(NetworkVertex(position: const Offset(10, 10)));
      network.addVertex(NetworkVertex(position: const Offset(20, 20)));

      final c = GeometricConstraint(
        type: ConstraintType.coincident,
        vertexIndices: [0, 1],
      );
      final solver = ConstraintSolver(network: network, constraints: [c]);
      solver.solve();
      expect(
        (network.vertices[0].position - network.vertices[1].position).distance,
        closeTo(0, 0.1),
      );
    });

    test('symmetric constraint mirrors vertex', () {
      final network = VectorNetwork();
      network.addVertex(NetworkVertex(position: const Offset(0, 0))); // v0
      network.addVertex(NetworkVertex(position: const Offset(50, 0))); // center
      network.addVertex(NetworkVertex(position: const Offset(80, 0))); // v2

      final c = GeometricConstraint(
        type: ConstraintType.symmetric,
        vertexIndices: [0, 1, 2], // v0, center, mirror
      );
      final solver = ConstraintSolver(network: network, constraints: [c]);
      solver.solve();
      // v2 should be mirror of v0 about v1: 2*50 - 0 = 100
      expect(network.vertices[2].position.dx, closeTo(100, 0.5));
    });

    test('constraint JSON serialization', () {
      final c = GeometricConstraint(
        type: ConstraintType.fixedAngle,
        vertexIndices: [0, 1],
        value: 1.57,
      );
      final json = c.toJson();
      final restored = GeometricConstraint.fromJson(json);
      expect(restored.type, ConstraintType.fixedAngle);
      expect(restored.vertexIndices, [0, 1]);
      expect(restored.value, closeTo(1.57, 0.01));
    });

    test('unsatisfiedConstraints detects broken constraints', () {
      final network = VectorNetwork();
      network.addVertex(NetworkVertex(position: const Offset(0, 0)));
      network.addVertex(NetworkVertex(position: const Offset(100, 50)));

      final c = GeometricConstraint(
        type: ConstraintType.horizontal,
        vertexIndices: [0, 1],
      );
      final solver = ConstraintSolver(network: network, constraints: [c]);
      final unsatisfied = solver.unsatisfiedConstraints();
      expect(unsatisfied, isNotEmpty);
    });

    test('constraints persist through VectorNetwork clone', () {
      final network = VectorNetwork();
      network.addVertex(NetworkVertex(position: Offset.zero));
      network.addVertex(NetworkVertex(position: const Offset(10, 10)));
      network.addConstraint(
        GeometricConstraint(
          type: ConstraintType.horizontal,
          vertexIndices: [0, 1],
        ),
      );

      expect(network.constraints.length, 1);
      final cloned = network.clone();
      expect(cloned.constraints.length, 1);
      expect(cloned.constraints[0].type, ConstraintType.horizontal);
    });

    test('constraints persist through JSON roundtrip', () {
      final network = VectorNetwork();
      network.addVertex(NetworkVertex(position: Offset.zero));
      network.addVertex(NetworkVertex(position: const Offset(10, 10)));
      network.addSegment(NetworkSegment(start: 0, end: 1));
      network.addConstraint(
        GeometricConstraint(
          type: ConstraintType.fixedLength,
          vertexIndices: [0, 1],
          value: 50,
        ),
      );

      final json = network.toJson();
      final restored = VectorNetwork.fromJson(json);
      expect(restored.constraints.length, 1);
      expect(restored.constraints[0].type, ConstraintType.fixedLength);
      expect(restored.constraints[0].value, 50);
    });
  });

  // ===========================================================================
  // PHASE 3: LOD RENDERING
  // ===========================================================================

  group('NetworkLOD', () {
    test('detail level thresholds', () {
      expect(NetworkLOD.detailLevelForZoom(2.0), DetailLevel.full);
      expect(NetworkLOD.detailLevelForZoom(1.0), DetailLevel.medium);
      expect(NetworkLOD.detailLevelForZoom(0.5), DetailLevel.medium);
      expect(NetworkLOD.detailLevelForZoom(0.3), DetailLevel.medium);
      expect(NetworkLOD.detailLevelForZoom(0.1), DetailLevel.low);
    });

    test('shouldDrawVertexHandles at high zoom', () {
      expect(NetworkLOD.shouldDrawVertexHandles(3.0), true);
      expect(NetworkLOD.shouldDrawVertexHandles(1.0), false);
    });

    test('shouldDrawPerSegmentStroke at medium zoom', () {
      expect(NetworkLOD.shouldDrawPerSegmentStroke(1.0), true);
      expect(NetworkLOD.shouldDrawPerSegmentStroke(0.3), false);
    });

    test('buildForZoom produces non-empty path at full detail', () {
      final network = VectorNetwork();
      network.addVertex(NetworkVertex(position: Offset.zero));
      network.addVertex(NetworkVertex(position: const Offset(100, 100)));
      network.addSegment(NetworkSegment(start: 0, end: 1));

      final path = NetworkLOD.buildForZoom(network, 2.0, networkId: 'test1');
      expect(path.getBounds().isEmpty, false);
    });

    test('buildForZoom at low zoom produces bounds rect', () {
      final network = VectorNetwork();
      network.addVertex(NetworkVertex(position: Offset.zero));
      network.addVertex(NetworkVertex(position: const Offset(100, 100)));
      network.addSegment(NetworkSegment(start: 0, end: 1));

      final path = NetworkLOD.buildForZoom(network, 0.1, networkId: 'test2');
      expect(path.getBounds().isEmpty, false);
    });

    test('cached path returns same object for same revision', () {
      NetworkLOD.clearCache();
      final network = VectorNetwork();
      network.addVertex(NetworkVertex(position: Offset.zero));
      network.addVertex(NetworkVertex(position: const Offset(100, 100)));
      network.addSegment(NetworkSegment(start: 0, end: 1));

      final p1 = NetworkLOD.buildForZoom(network, 2.0, networkId: 'cache_test');
      final p2 = NetworkLOD.buildForZoom(network, 2.0, networkId: 'cache_test');
      expect(identical(p1, p2), true);
    });
  });

  // ===========================================================================
  // PHASE 3: COMMAND TRANSACTION
  // ===========================================================================

  group('CommandTransaction', () {
    test('commit wraps commands into CompositeCommand', () {
      final network = VectorNetwork();
      network.addVertex(NetworkVertex(position: Offset.zero));
      network.addVertex(NetworkVertex(position: const Offset(10, 0)));
      network.addSegment(NetworkSegment(start: 0, end: 1));

      final node = VectorNetworkNode(id: NodeId('test-txn'), network: network);

      final txn = CommandTransaction(label: 'batch move');
      txn.add(
        MoveVertexCommand(
          node: node,
          vertexIndex: 0,
          newPosition: const Offset(5, 5),
        ),
      );
      txn.add(
        MoveVertexCommand(
          node: node,
          vertexIndex: 1,
          newPosition: const Offset(15, 5),
        ),
      );

      expect(txn.length, 2);
      // Commands are already executed.
      expect(node.network.vertices[0].position, const Offset(5, 5));
      expect(node.network.vertices[1].position, const Offset(15, 5));

      final composite = txn.commit();
      expect(composite.label, 'batch move');
      expect(txn.isFinished, true);

      // Undo all at once.
      composite.undo();
      expect(node.network.vertices[0].position, Offset.zero);
      expect(node.network.vertices[1].position, const Offset(10, 0));

      // Redo all at once.
      composite.redo();
      expect(node.network.vertices[0].position, const Offset(5, 5));
      expect(node.network.vertices[1].position, const Offset(15, 5));
    });

    test('rollback undoes all commands in reverse', () {
      final network = VectorNetwork();
      network.addVertex(NetworkVertex(position: Offset.zero));
      network.addVertex(NetworkVertex(position: const Offset(10, 0)));
      network.addSegment(NetworkSegment(start: 0, end: 1));

      final node = VectorNetworkNode(id: NodeId('test-txn'), network: network);

      final txn = CommandTransaction(label: 'will rollback');
      txn.add(
        MoveVertexCommand(
          node: node,
          vertexIndex: 0,
          newPosition: const Offset(99, 99),
        ),
      );
      expect(node.network.vertices[0].position, const Offset(99, 99));

      txn.rollback();
      expect(node.network.vertices[0].position, Offset.zero);
      expect(txn.isFinished, true);
    });

    test('double commit throws', () {
      final txn = CommandTransaction(label: 'test');
      txn.commit();
      expect(() => txn.commit(), throwsA(isA<StateError>()));
    });

    test('add after commit throws', () {
      final network = VectorNetwork();
      network.addVertex(NetworkVertex(position: Offset.zero));
      network.addVertex(NetworkVertex(position: const Offset(10, 0)));
      network.addSegment(NetworkSegment(start: 0, end: 1));
      final node = VectorNetworkNode(id: NodeId('test-txn'), network: network);

      final txn = CommandTransaction(label: 'test');
      txn.commit();
      expect(
        () => txn.add(
          MoveVertexCommand(
            node: node,
            vertexIndex: 0,
            newPosition: const Offset(1, 1),
          ),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
