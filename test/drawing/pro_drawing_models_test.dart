import 'package:nebula_engine/src/core/scene_graph/node_id.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/drawing/models/pro_drawing_point.dart';
import 'package:nebula_engine/src/drawing/models/pro_brush_settings.dart';

void main() {
  // =========================================================================
  // ProDrawingPoint
  // =========================================================================

  group('ProDrawingPoint', () {
    // ── Construction ───────────────────────────────────────────────────

    group('construction', () {
      test('creates with required fields', () {
        const point = ProDrawingPoint(
          position: Offset(10.0, 20.0),
          pressure: 0.5,
          timestamp: 1000,
        );
        expect(point.position, const Offset(10.0, 20.0));
        expect(point.pressure, 0.5);
        expect(point.timestamp, 1000);
      });

      test('defaults optional fields to zero', () {
        const point = ProDrawingPoint(
          position: Offset.zero,
          pressure: 1.0,
          timestamp: 0,
        );
        expect(point.tiltX, 0.0);
        expect(point.tiltY, 0.0);
        expect(point.orientation, 0.0);
      });

      test('offset getter returns position', () {
        const point = ProDrawingPoint(
          position: Offset(5.0, 10.0),
          pressure: 0.5,
          timestamp: 100,
        );
        expect(point.offset, equals(point.position));
      });
    });

    // ── Serialization ──────────────────────────────────────────────────

    group('toJson / fromJson', () {
      test('round-trips basic fields', () {
        const original = ProDrawingPoint(
          position: Offset(100.1234, 200.5678),
          pressure: 0.75,
          timestamp: 12345,
        );
        final json = original.toJson();
        final restored = ProDrawingPoint.fromJson(json);

        expect(restored.position.dx, closeTo(100.1234, 0.001));
        expect(restored.position.dy, closeTo(200.5678, 0.001));
        expect(restored.pressure, closeTo(0.75, 0.01));
        expect(restored.timestamp, 12345);
      });

      test('omits zero tilt and orientation from JSON', () {
        const point = ProDrawingPoint(
          position: Offset(1.0, 2.0),
          pressure: 0.5,
          timestamp: 100,
        );
        final json = point.toJson();
        expect(json.containsKey('tiltX'), isFalse);
        expect(json.containsKey('tiltY'), isFalse);
        expect(json.containsKey('orientation'), isFalse);
      });

      test('includes non-zero tilt in JSON', () {
        const point = ProDrawingPoint(
          position: Offset(1.0, 2.0),
          pressure: 0.5,
          tiltX: 0.3,
          tiltY: 0.4,
          orientation: 1.5,
          timestamp: 100,
        );
        final json = point.toJson();
        expect(json.containsKey('tiltX'), isTrue);
        expect(json.containsKey('tiltY'), isTrue);
        expect(json.containsKey('orientation'), isTrue);
      });

      test('round-trips full fields including tilt', () {
        const original = ProDrawingPoint(
          position: Offset(50.0, 75.0),
          pressure: 0.8,
          tiltX: 0.2,
          tiltY: 0.3,
          orientation: 1.5,
          timestamp: 9999,
        );
        final json = original.toJson();
        final restored = ProDrawingPoint.fromJson(json);

        expect(restored.tiltX, closeTo(0.2, 0.01));
        expect(restored.tiltY, closeTo(0.3, 0.01));
        expect(restored.orientation, closeTo(1.5, 0.01));
      });
    });

    // ── Precision ──────────────────────────────────────────────────────

    group('precision', () {
      test('coordinates are rounded to 4 decimals', () {
        const point = ProDrawingPoint(
          position: Offset(1.123456789, 2.987654321),
          pressure: 0.5,
          timestamp: 0,
        );
        final json = point.toJson();
        // 4 decimal places: 1.1235, 2.9877
        expect((json['x'] as double).toString().length, lessThanOrEqualTo(8));
      });

      test('pressure is rounded to 2 decimals', () {
        const point = ProDrawingPoint(
          position: Offset.zero,
          pressure: 0.7777,
          timestamp: 0,
        );
        final json = point.toJson();
        expect(json['pressure'], closeTo(0.78, 0.001));
      });
    });

    // ── copyWith ───────────────────────────────────────────────────────

    group('copyWith', () {
      test('copies all fields when nothing overridden', () {
        const original = ProDrawingPoint(
          position: Offset(10, 20),
          pressure: 0.6,
          tiltX: 0.1,
          timestamp: 500,
        );
        final copy = original.copyWith();
        expect(copy.position, original.position);
        expect(copy.pressure, original.pressure);
        expect(copy.tiltX, original.tiltX);
        expect(copy.timestamp, original.timestamp);
      });

      test('overrides specified fields', () {
        const original = ProDrawingPoint(
          position: Offset(10, 20),
          pressure: 0.5,
          timestamp: 100,
        );
        final copy = original.copyWith(
          position: const Offset(30, 40),
          pressure: 0.9,
        );
        expect(copy.position, const Offset(30, 40));
        expect(copy.pressure, 0.9);
        expect(copy.timestamp, 100); // unchanged
      });
    });
  });

  // =========================================================================
  // ProStroke
  // =========================================================================

  group('ProStroke', () {
    final testPoints = [
      const ProDrawingPoint(
        position: Offset(10, 20),
        pressure: 0.5,
        timestamp: 100,
      ),
      const ProDrawingPoint(
        position: Offset(30, 40),
        pressure: 0.7,
        timestamp: 200,
      ),
      const ProDrawingPoint(
        position: Offset(50, 60),
        pressure: 0.9,
        timestamp: 300,
      ),
    ];

    ProStroke createStroke({
      String id = 'test-stroke',
      List<ProDrawingPoint>? points,
      Color color = Colors.black,
      double baseWidth = 2.0,
      ProPenType penType = ProPenType.ballpoint,
    }) {
      return ProStroke(
        id: id,
        points: points ?? testPoints,
        color: color,
        baseWidth: baseWidth,
        penType: penType,
        createdAt: DateTime(2025, 1, 1),
      );
    }

    // ── Construction ───────────────────────────────────────────────────

    group('construction', () {
      test('creates with required fields', () {
        final stroke = createStroke();
        expect(stroke.id, 'test-stroke');
        expect(stroke.points.length, 3);
        expect(stroke.color, Colors.black);
        expect(stroke.baseWidth, 2.0);
        expect(stroke.penType, ProPenType.ballpoint);
      });

      test('defaults to current engine version', () {
        final stroke = createStroke();
        expect(stroke.engineVersion, ProStroke.currentEngineVersion);
      });

      test('defaults to default brush settings', () {
        final stroke = createStroke();
        expect(stroke.settings, equals(const ProBrushSettings()));
      });

      test('points list is unmodifiable', () {
        final stroke = createStroke();
        expect(
          () => (stroke.points as List).add(testPoints.first),
          throwsUnsupportedError,
        );
      });
    });

    // ── Bounds ─────────────────────────────────────────────────────────

    group('bounds', () {
      test('calculates correct bounds with padding', () {
        final stroke = createStroke(baseWidth: 2.0);
        final bounds = stroke.bounds;
        // Points: (10,20), (30,40), (50,60) with padding = baseWidth * 2 = 4
        expect(bounds.left, closeTo(10 - 4, 0.01));
        expect(bounds.top, closeTo(20 - 4, 0.01));
        expect(bounds.right, closeTo(50 + 4, 0.01));
        expect(bounds.bottom, closeTo(60 + 4, 0.01));
      });

      test('bounds are cached (same reference)', () {
        final stroke = createStroke();
        final bounds1 = stroke.bounds;
        final bounds2 = stroke.bounds;
        expect(identical(bounds1, bounds2), isTrue);
      });

      test('empty points return Rect.zero', () {
        final stroke = createStroke(points: []);
        expect(stroke.bounds, Rect.zero);
      });
    });

    // ── Fill Overlay ───────────────────────────────────────────────────

    group('fill overlay', () {
      test('isFill is false by default', () {
        final stroke = createStroke();
        expect(stroke.isFill, isFalse);
      });
    });

    // ── Serialization ──────────────────────────────────────────────────

    group('toJson / fromJson', () {
      test('round-trips basic fields', () {
        final original = createStroke();
        final json = original.toJson();
        final restored = ProStroke.fromJson(json);

        expect(restored.id, original.id);
        expect(restored.points.length, original.points.length);
        expect(restored.baseWidth, original.baseWidth);
        expect(restored.penType, original.penType);
      });

      test('preserves engine version', () {
        final stroke = createStroke();
        final json = stroke.toJson();
        final restored = ProStroke.fromJson(json);
        expect(restored.engineVersion, stroke.engineVersion);
      });

      test('omits default settings from JSON', () {
        final stroke = createStroke();
        final json = stroke.toJson();
        // Default settings should be omitted (isDefault == true)
        expect(json.containsKey('settings'), isFalse);
      });

      test('includes custom settings in JSON', () {
        final stroke = ProStroke(
          id: NodeId('custom'),
          points: testPoints,
          color: Colors.red,
          baseWidth: 3.0,
          penType: ProPenType.fountain,
          createdAt: DateTime(2025, 1, 1),
          settings: const ProBrushSettings(fountainMinPressure: 0.3),
        );
        final json = stroke.toJson();
        expect(json.containsKey('settings'), isTrue);
      });

      test('old strokes without ev default to version 1', () {
        final json = {
          'id': 'old-stroke',
          'points': [
            {'x': 0, 'y': 0, 'pressure': 0.5, 'timestamp': 0},
          ],
          'color': Colors.black.toARGB32(),
          'baseWidth': 2.0,
          'penType': 'ProPenType.ballpoint',
          'createdAt': '2025-01-01T00:00:00.000',
        };
        final stroke = ProStroke.fromJson(json);
        expect(stroke.engineVersion, 1);
      });
    });

    // ── copyWith ───────────────────────────────────────────────────────

    group('copyWith', () {
      test('copies all fields when nothing overridden', () {
        final original = createStroke();
        final copy = original.copyWith();
        expect(copy.id, original.id);
        expect(copy.color, original.color);
        expect(copy.baseWidth, original.baseWidth);
        expect(copy.penType, original.penType);
      });

      test('overrides specified fields', () {
        final original = createStroke();
        final copy = original.copyWith(
          id: NodeId('new-id'),
          color: Colors.blue,
          baseWidth: 5.0,
        );
        expect(copy.id, 'new-id');
        expect(copy.color, Colors.blue);
        expect(copy.baseWidth, 5.0);
        expect(copy.penType, original.penType); // unchanged
      });
    });

    // ── ProPenType ─────────────────────────────────────────────────────

    group('ProPenType', () {
      test('has eleven values', () {
        expect(ProPenType.values.length, 11);
      });

      test('contains expected types', () {
        expect(ProPenType.values, contains(ProPenType.ballpoint));
        expect(ProPenType.values, contains(ProPenType.fountain));
        expect(ProPenType.values, contains(ProPenType.pencil));
        expect(ProPenType.values, contains(ProPenType.highlighter));
        expect(ProPenType.values, contains(ProPenType.watercolor));
        expect(ProPenType.values, contains(ProPenType.marker));
        expect(ProPenType.values, contains(ProPenType.charcoal));
        expect(ProPenType.values, contains(ProPenType.oilPaint));
        expect(ProPenType.values, contains(ProPenType.sprayPaint));
        expect(ProPenType.values, contains(ProPenType.neonGlow));
        expect(ProPenType.values, contains(ProPenType.inkWash));
      });
    });
  });
}
