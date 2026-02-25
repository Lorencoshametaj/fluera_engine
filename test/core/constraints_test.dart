import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/vector/constraints.dart';
import 'package:nebula_engine/src/core/vector/vector_network.dart';

// =============================================================================
// Helpers
// =============================================================================

/// Build a simple network with 2 vertices and 1 segment.
VectorNetwork _twoPointNetwork(Offset p0, Offset p1) {
  return VectorNetwork(
    vertices: [NetworkVertex(position: p0), NetworkVertex(position: p1)],
    segments: [NetworkSegment(start: 0, end: 1)],
  );
}

/// Build a network with 4 vertices and 2 segments (for parallel/perpendicular/equal).
VectorNetwork _fourPointNetwork(Offset a, Offset b, Offset c, Offset d) {
  return VectorNetwork(
    vertices: [
      NetworkVertex(position: a),
      NetworkVertex(position: b),
      NetworkVertex(position: c),
      NetworkVertex(position: d),
    ],
    segments: [
      NetworkSegment(start: 0, end: 1), // seg0: a→b
      NetworkSegment(start: 2, end: 3), // seg1: c→d
    ],
  );
}

double _distance(Offset a, Offset b) => (a - b).distance;

void main() {
  // ===========================================================================
  // GeometricConstraint — serialization
  // ===========================================================================

  group('GeometricConstraint', () {
    test('toJson and fromJson roundtrip', () {
      final c = GeometricConstraint(
        type: ConstraintType.fixedLength,
        vertexIndices: [0, 1],
        value: 42.5,
      );
      final json = c.toJson();
      expect(json['type'], 'fixedLength');
      expect(json['vertexIndices'], [0, 1]);
      expect(json['value'], 42.5);

      final restored = GeometricConstraint.fromJson(json);
      expect(restored.type, ConstraintType.fixedLength);
      expect(restored.vertexIndices, [0, 1]);
      expect(restored.value, 42.5);
    });

    test('fromJson without value', () {
      final c = GeometricConstraint(
        type: ConstraintType.horizontal,
        vertexIndices: [0, 1],
      );
      final json = c.toJson();
      expect(json.containsKey('value'), isFalse);

      final restored = GeometricConstraint.fromJson(json);
      expect(restored.value, isNull);
    });
  });

  // ===========================================================================
  // ConstraintSolver — horizontal
  // ===========================================================================

  group('ConstraintSolver - horizontal', () {
    test('solver makes two vertices same Y', () {
      final net = _twoPointNetwork(const Offset(0, 10), const Offset(100, 50));
      final solver = ConstraintSolver(
        network: net,
        constraints: [
          GeometricConstraint(
            type: ConstraintType.horizontal,
            vertexIndices: [0, 1],
          ),
        ],
      );

      final converged = solver.solve();
      expect(converged, isTrue);
      expect(
        net.vertices[0].position.dy,
        closeTo(net.vertices[1].position.dy, 0.01),
      );
    });
  });

  // ===========================================================================
  // ConstraintSolver — vertical
  // ===========================================================================

  group('ConstraintSolver - vertical', () {
    test('solver makes two vertices same X', () {
      final net = _twoPointNetwork(const Offset(10, 0), const Offset(50, 100));
      final solver = ConstraintSolver(
        network: net,
        constraints: [
          GeometricConstraint(
            type: ConstraintType.vertical,
            vertexIndices: [0, 1],
          ),
        ],
      );

      final converged = solver.solve();
      expect(converged, isTrue);
      expect(
        net.vertices[0].position.dx,
        closeTo(net.vertices[1].position.dx, 0.01),
      );
    });
  });

  // ===========================================================================
  // ConstraintSolver — coincident
  // ===========================================================================

  group('ConstraintSolver - coincident', () {
    test('solver merges two vertices to same point', () {
      final net = _twoPointNetwork(const Offset(0, 0), const Offset(10, 10));
      final solver = ConstraintSolver(
        network: net,
        constraints: [
          GeometricConstraint(
            type: ConstraintType.coincident,
            vertexIndices: [0, 1],
          ),
        ],
      );

      final converged = solver.solve();
      expect(converged, isTrue);
      expect(
        _distance(net.vertices[0].position, net.vertices[1].position),
        lessThan(0.01),
      );
    });
  });

  // ===========================================================================
  // ConstraintSolver — fixedLength
  // ===========================================================================

  group('ConstraintSolver - fixedLength', () {
    test('solver enforces segment length', () {
      final net = _twoPointNetwork(const Offset(0, 0), const Offset(100, 0));
      // Current length = 100, target = 50
      final solver = ConstraintSolver(
        network: net,
        constraints: [
          GeometricConstraint(
            type: ConstraintType.fixedLength,
            vertexIndices: [0, 1],
            value: 50,
          ),
        ],
      );

      final converged = solver.solve();
      expect(converged, isTrue);
      final len = _distance(net.vertices[0].position, net.vertices[1].position);
      expect(len, closeTo(50, 0.1));
    });

    test('solver stretches segment to target length', () {
      final net = _twoPointNetwork(const Offset(0, 0), const Offset(10, 0));
      // Current length = 10, target = 100
      final solver = ConstraintSolver(
        network: net,
        constraints: [
          GeometricConstraint(
            type: ConstraintType.fixedLength,
            vertexIndices: [0, 1],
            value: 100,
          ),
        ],
      );

      final converged = solver.solve();
      expect(converged, isTrue);
      final len = _distance(net.vertices[0].position, net.vertices[1].position);
      expect(len, closeTo(100, 0.1));
    });
  });

  // ===========================================================================
  // ConstraintSolver — fixedAngle
  // ===========================================================================

  group('ConstraintSolver - fixedAngle', () {
    test('solver enforces horizontal angle (0 rad)', () {
      final net = _twoPointNetwork(
        const Offset(0, 0),
        const Offset(50, 50), // 45° angle
      );
      final solver = ConstraintSolver(
        network: net,
        constraints: [
          GeometricConstraint(
            type: ConstraintType.fixedAngle,
            vertexIndices: [0, 1],
            value: 0, // horizontal
          ),
        ],
      );

      final converged = solver.solve();
      expect(converged, isTrue);
      // After solving, dy should be ≈0 between the two points
      final dy =
          (net.vertices[1].position.dy - net.vertices[0].position.dy).abs();
      expect(dy, closeTo(0, 0.5));
    });
  });

  // ===========================================================================
  // ConstraintSolver — parallel
  // ===========================================================================

  group('ConstraintSolver - parallel', () {
    test('solver makes two segments parallel', () {
      final net = _fourPointNetwork(
        const Offset(0, 0), // seg0 start
        const Offset(100, 0), // seg0 end (horizontal)
        const Offset(0, 50), // seg1 start
        const Offset(80, 80), // seg1 end (not horizontal)
      );
      final solver = ConstraintSolver(
        network: net,
        constraints: [
          GeometricConstraint(
            type: ConstraintType.parallel,
            segmentIndices: [0, 1],
          ),
        ],
      );

      final converged = solver.solve();
      expect(converged, isTrue);
      // After solving, both segments should have the same angle
      final d0 = net.vertices[1].position - net.vertices[0].position;
      final d1 = net.vertices[3].position - net.vertices[2].position;
      final angle0 = math.atan2(d0.dy, d0.dx);
      final angle1 = math.atan2(d1.dy, d1.dx);
      expect((angle0 - angle1).abs() % math.pi, closeTo(0, 0.05));
    });
  });

  // ===========================================================================
  // ConstraintSolver — perpendicular
  // ===========================================================================

  group('ConstraintSolver - perpendicular', () {
    test('solver makes two segments perpendicular', () {
      final net = _fourPointNetwork(
        const Offset(0, 0),
        const Offset(100, 0), // seg0: horizontal
        const Offset(50, 0),
        const Offset(80, 30), // seg1: diagonal
      );
      final solver = ConstraintSolver(
        network: net,
        constraints: [
          GeometricConstraint(
            type: ConstraintType.perpendicular,
            segmentIndices: [0, 1],
          ),
        ],
      );

      final converged = solver.solve();
      expect(converged, isTrue);
      // After solving, segments should be 90° apart
      final d0 = net.vertices[1].position - net.vertices[0].position;
      final d1 = net.vertices[3].position - net.vertices[2].position;
      final dot = d0.dx * d1.dx + d0.dy * d1.dy;
      // Dot product of perpendicular vectors ≈ 0
      expect(dot.abs(), closeTo(0, 1.0));
    });
  });

  // ===========================================================================
  // ConstraintSolver — equal length
  // ===========================================================================

  group('ConstraintSolver - equal length', () {
    test('solver makes two segments equal length', () {
      final net = _fourPointNetwork(
        const Offset(0, 0),
        const Offset(100, 0), // seg0: length 100
        const Offset(0, 50),
        const Offset(50, 50), // seg1: length 50
      );
      final solver = ConstraintSolver(
        network: net,
        constraints: [
          GeometricConstraint(
            type: ConstraintType.equal,
            segmentIndices: [0, 1],
          ),
        ],
      );

      final converged = solver.solve();
      expect(converged, isTrue);
      final len0 = _distance(
        net.vertices[0].position,
        net.vertices[1].position,
      );
      final len1 = _distance(
        net.vertices[2].position,
        net.vertices[3].position,
      );
      expect(len0, closeTo(len1, 1.0));
    });
  });

  // ===========================================================================
  // ConstraintSolver — symmetric
  // ===========================================================================

  group('ConstraintSolver - symmetric', () {
    test('solver makes v0 and v2 symmetric about v1', () {
      final net = VectorNetwork(
        vertices: [
          NetworkVertex(position: const Offset(0, 0)), // v0
          NetworkVertex(position: const Offset(50, 50)), // v1 (center)
          NetworkVertex(
            position: const Offset(80, 80),
          ), // v2 (should mirror to 100,100)
        ],
      );
      final solver = ConstraintSolver(
        network: net,
        constraints: [
          GeometricConstraint(
            type: ConstraintType.symmetric,
            vertexIndices: [0, 1, 2],
          ),
        ],
      );

      final converged = solver.solve();
      expect(converged, isTrue);
      // v2 should be at 2*v1 - v0 = (100, 100)
      expect(net.vertices[2].position.dx, closeTo(100, 0.1));
      expect(net.vertices[2].position.dy, closeTo(100, 0.1));
    });
  });

  // ===========================================================================
  // ConstraintSolver — tangent
  // ===========================================================================

  group('ConstraintSolver - tangent', () {
    test('solver projects vertex onto segment line', () {
      final net = VectorNetwork(
        vertices: [
          NetworkVertex(position: const Offset(0, 0)), // seg start
          NetworkVertex(position: const Offset(100, 0)), // seg end
          NetworkVertex(position: const Offset(50, 30)), // free vertex above
        ],
        segments: [NetworkSegment(start: 0, end: 1)],
      );
      final solver = ConstraintSolver(
        network: net,
        constraints: [
          GeometricConstraint(
            type: ConstraintType.tangent,
            vertexIndices: [2],
            segmentIndices: [0],
          ),
        ],
      );

      final converged = solver.solve();
      expect(converged, isTrue);
      // v2 should be projected onto the horizontal line (y ≈ 0)
      expect(net.vertices[2].position.dy, closeTo(0, 0.1));
      // X preserved (projection onto horizontal line keeps x)
      expect(net.vertices[2].position.dx, closeTo(50, 0.1));
    });
  });

  // ===========================================================================
  // ConstraintSolver — multiple constraints
  // ===========================================================================

  group('ConstraintSolver - multiple constraints', () {
    test('horizontal + fixedLength combined', () {
      final net = _twoPointNetwork(const Offset(0, 10), const Offset(80, 30));
      final solver = ConstraintSolver(
        network: net,
        constraints: [
          GeometricConstraint(
            type: ConstraintType.horizontal,
            vertexIndices: [0, 1],
          ),
          GeometricConstraint(
            type: ConstraintType.fixedLength,
            vertexIndices: [0, 1],
            value: 100,
          ),
        ],
      );

      final converged = solver.solve();
      expect(converged, isTrue);
      // Same Y
      expect(
        net.vertices[0].position.dy,
        closeTo(net.vertices[1].position.dy, 0.1),
      );
      // Length 100
      final len = _distance(net.vertices[0].position, net.vertices[1].position);
      expect(len, closeTo(100, 0.5));
    });
  });

  // ===========================================================================
  // ConstraintSolver — unsatisfiedConstraints
  // ===========================================================================

  group('ConstraintSolver - unsatisfiedConstraints', () {
    test('reports unsatisfied before solve', () {
      final net = _twoPointNetwork(const Offset(0, 10), const Offset(100, 50));
      final solver = ConstraintSolver(
        network: net,
        constraints: [
          GeometricConstraint(
            type: ConstraintType.horizontal,
            vertexIndices: [0, 1],
          ),
        ],
      );

      final unsatisfied = solver.unsatisfiedConstraints();
      expect(unsatisfied, isNotEmpty);
    });

    test('reports empty after solve', () {
      final net = _twoPointNetwork(const Offset(0, 10), const Offset(100, 50));
      final solver = ConstraintSolver(
        network: net,
        constraints: [
          GeometricConstraint(
            type: ConstraintType.horizontal,
            vertexIndices: [0, 1],
          ),
        ],
      );

      solver.solve();
      final unsatisfied = solver.unsatisfiedConstraints();
      expect(unsatisfied, isEmpty);
    });
  });
}
