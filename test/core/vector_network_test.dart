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
        id: 'test-node-1',
        network: network,
        fillColor: const Color(0xFFFF0000),
        strokeColor: const Color(0xFF000000),
        strokeWidth: 3.0,
      );

      final json = node.toJson();
      expect(json['nodeType'], 'vector_network');

      final restored = VectorNetworkNode.fromJson(json);
      expect(restored.id, 'test-node-1');
      expect(restored.network.vertices.length, 2);
      expect(restored.strokeWidth, 3.0);
      expect(restored.fillColor, const Color(0xFFFF0000));
    });

    test('localBounds includes stroke width', () {
      final network = VectorNetwork();
      network.addVertex(NetworkVertex(position: Offset.zero));
      network.addVertex(NetworkVertex(position: const Offset(100, 100)));
      network.addSegment(NetworkSegment(start: 0, end: 1));

      final node = VectorNetworkNode(
        id: 'bounds-test',
        network: network,
        strokeWidth: 4.0,
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
        id: 'region-fill-test',
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
}
