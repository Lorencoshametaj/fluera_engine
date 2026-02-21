import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/nebula_engine.dart';

void main() {
  // =========================================================================
  // FillLayer
  // =========================================================================
  group('FillLayer', () {
    test('solid factory creates a solid FillLayer', () {
      final fill = FillLayer.solid(color: Colors.red);
      expect(fill.type, FillType.solid);
      expect(fill.color, Colors.red);
      expect(fill.opacity, 1.0);
      expect(fill.blendMode, ui.BlendMode.srcOver);
      expect(fill.isVisible, true);
      expect(fill.id, isNotEmpty);
    });

    test('fromGradient factory creates a gradient FillLayer', () {
      final gradient = LinearGradientFill(
        colors: [Colors.red, Colors.blue],
        stops: [0.0, 1.0],
      );
      final fill = FillLayer.fromGradient(gradient: gradient, opacity: 0.5);
      expect(fill.type, FillType.gradient);
      expect(fill.gradient, gradient);
      expect(fill.opacity, 0.5);
    });

    test('opacity is clamped to 0.0–1.0', () {
      final fill = FillLayer.solid(color: Colors.black, opacity: 1.5);
      expect(fill.opacity, 1.0);

      fill.opacity = -0.5;
      expect(fill.opacity, 0.0);
    });

    test('serialization roundtrip for solid fill', () {
      final original = FillLayer.solid(
        color: const Color(0xFFFF0000),
        opacity: 0.8,
        blendMode: ui.BlendMode.multiply,
      );
      final json = original.toJson();
      final restored = FillLayer.fromJson(json);

      expect(restored.type, FillType.solid);
      expect(restored.color, const Color(0xFFFF0000));
      expect(restored.opacity, closeTo(0.8, 0.001));
      expect(restored.blendMode, ui.BlendMode.multiply);
      expect(restored.isVisible, true);
    });

    test('serialization roundtrip for gradient fill', () {
      final gradient = LinearGradientFill(
        colors: [const Color(0xFFFF0000), const Color(0xFF0000FF)],
        stops: [0.0, 1.0],
      );
      final original = FillLayer.fromGradient(gradient: gradient);
      final json = original.toJson();
      final restored = FillLayer.fromJson(json);

      expect(restored.type, FillType.gradient);
      expect(restored.gradient, isNotNull);
      expect(restored.gradient, isA<LinearGradientFill>());
    });

    test('serialization for invisible/default-blend omits defaults', () {
      final fill = FillLayer.solid(color: Colors.red);
      final json = fill.toJson();
      expect(json.containsKey('opacity'), false); // 1.0 = default, omitted
      expect(json.containsKey('blendMode'), false); // srcOver = default
      expect(json.containsKey('isVisible'), false); // true = default
    });

    test('toPaint returns null when not visible', () {
      final fill = FillLayer.solid(color: Colors.red, isVisible: false);
      expect(fill.toPaint(const Rect.fromLTWH(0, 0, 100, 100)), isNull);
    });

    test('toPaint returns null for solid fill with null color', () {
      final fill = FillLayer(type: FillType.solid, color: null);
      expect(fill.toPaint(const Rect.fromLTWH(0, 0, 100, 100)), isNull);
    });

    test('toPaint returns valid Paint for solid fill', () {
      final fill = FillLayer.solid(color: Colors.blue);
      final paint = fill.toPaint(const Rect.fromLTWH(0, 0, 100, 100));
      expect(paint, isNotNull);
      expect(paint!.style, PaintingStyle.fill);
    });

    test('copyWith preserves id and overrides fields', () {
      final fill = FillLayer.solid(color: Colors.red);
      final copy = fill.copyWith(color: Colors.green, opacity: 0.5);
      expect(copy.id, fill.id);
      expect(copy.color, Colors.green);
      expect(copy.opacity, 0.5);
      expect(copy.type, FillType.solid);
    });

    test('equality is based on id', () {
      final a = FillLayer.solid(color: Colors.red);
      final b = FillLayer.solid(color: Colors.red);
      expect(a, isNot(equals(b))); // Different IDs.
      expect(a, equals(a));
    });
  });

  // =========================================================================
  // StrokeLayer
  // =========================================================================
  group('StrokeLayer', () {
    test('default constructor creates valid stroke', () {
      final stroke = StrokeLayer(color: Colors.black, width: 2.0);
      expect(stroke.color, Colors.black);
      expect(stroke.width, 2.0);
      expect(stroke.cap, ui.StrokeCap.round);
      expect(stroke.join, ui.StrokeJoin.round);
      expect(stroke.position, StrokePosition.center);
      expect(stroke.opacity, 1.0);
      expect(stroke.isVisible, true);
      expect(stroke.dashPattern, isNull);
    });

    test('serialization roundtrip with dash pattern', () {
      final original = StrokeLayer(
        color: const Color(0xFF000000),
        width: 3.0,
        position: StrokePosition.outside,
        dashPattern: [6.0, 3.0],
        opacity: 0.7,
      );
      final json = original.toJson();
      final restored = StrokeLayer.fromJson(json);

      expect(restored.width, 3.0);
      expect(restored.position, StrokePosition.outside);
      expect(restored.dashPattern, [6.0, 3.0]);
      expect(restored.opacity, closeTo(0.7, 0.001));
    });

    test('boundsInflation for center/inside/outside', () {
      final center = StrokeLayer(
        color: Colors.black,
        width: 4.0,
        position: StrokePosition.center,
      );
      expect(center.boundsInflation, 2.0);

      final inside = StrokeLayer(
        color: Colors.black,
        width: 4.0,
        position: StrokePosition.inside,
      );
      expect(inside.boundsInflation, 0.0);

      final outside = StrokeLayer(
        color: Colors.black,
        width: 4.0,
        position: StrokePosition.outside,
      );
      expect(outside.boundsInflation, 4.0);
    });

    test('boundsInflation is 0 when not visible', () {
      final stroke = StrokeLayer(
        color: Colors.black,
        width: 4.0,
        isVisible: false,
      );
      expect(stroke.boundsInflation, 0.0);
    });

    test('toPaint returns null when not visible', () {
      final stroke = StrokeLayer(
        color: Colors.black,
        width: 2.0,
        isVisible: false,
      );
      expect(stroke.toPaint(const Rect.fromLTWH(0, 0, 100, 100)), isNull);
    });

    test('toPaint returns null when no color or gradient', () {
      final stroke = StrokeLayer(width: 2.0);
      expect(stroke.toPaint(const Rect.fromLTWH(0, 0, 100, 100)), isNull);
    });

    test('toPaint returns valid Paint for colored stroke', () {
      final stroke = StrokeLayer(color: Colors.red, width: 2.0);
      final paint = stroke.toPaint(const Rect.fromLTWH(0, 0, 100, 100));
      expect(paint, isNotNull);
      expect(paint!.style, PaintingStyle.stroke);
      expect(paint.strokeWidth, 2.0);
    });

    test('serialization omits defaults', () {
      final stroke = StrokeLayer(color: Colors.red, width: 1.0);
      final json = stroke.toJson();
      expect(json.containsKey('cap'), false); // round = default
      expect(json.containsKey('join'), false); // round = default
      expect(json.containsKey('position'), false); // center = default
      expect(json.containsKey('opacity'), false); // 1.0 = default
      expect(json.containsKey('blendMode'), false); // srcOver = default
      expect(json.containsKey('isVisible'), false); // true = default
      expect(json.containsKey('dashPattern'), false); // null = default
    });
  });

  // =========================================================================
  // PaintStackMixin (tested via PathNode)
  // =========================================================================
  group('PaintStackMixin', () {
    late PathNode node;

    setUp(() {
      node = PathNode(id: NodeId('test-path'), path: _testVectorPath());
    });

    test('starts with empty fill and stroke lists', () {
      final freshNode = PathNode(
        id: NodeId('fresh'),
        path: _testVectorPath(),
        fills: [],
        strokes: [],
      );
      expect(freshNode.fills, isEmpty);
      expect(freshNode.strokes, isEmpty);
    });

    test('addFill appends to the end by default', () {
      node.fills = [];
      final fill1 = FillLayer.solid(color: Colors.red);
      final fill2 = FillLayer.solid(color: Colors.blue);
      node.addFill(fill1);
      node.addFill(fill2);
      expect(node.fills.length, 2);
      expect(node.fills[0].color, Colors.red);
      expect(node.fills[1].color, Colors.blue);
    });

    test('addFill inserts at index', () {
      node.fills = [];
      final fill1 = FillLayer.solid(color: Colors.red);
      final fill2 = FillLayer.solid(color: Colors.blue);
      final fill3 = FillLayer.solid(color: Colors.green);
      node.addFill(fill1);
      node.addFill(fill2);
      node.addFill(fill3, 1); // Insert at index 1.
      expect(node.fills[0].color, Colors.red);
      expect(node.fills[1].color, Colors.green);
      expect(node.fills[2].color, Colors.blue);
    });

    test('removeFill removes by id', () {
      node.fills = [];
      final fill = FillLayer.solid(color: Colors.red);
      node.addFill(fill);
      expect(node.fills.length, 1);
      final removed = node.removeFill(fill.id);
      expect(removed, true);
      expect(node.fills, isEmpty);
    });

    test('removeFill returns false when id not found', () {
      node.fills = [];
      expect(node.removeFill('nonexistent'), false);
    });

    test('reorderFill moves fill within list', () {
      node.fills = [];
      final fill1 = FillLayer.solid(color: Colors.red);
      final fill2 = FillLayer.solid(color: Colors.green);
      final fill3 = FillLayer.solid(color: Colors.blue);
      node.addFill(fill1);
      node.addFill(fill2);
      node.addFill(fill3);

      node.reorderFill(0, 2); // Move red from 0 to 2.
      expect(node.fills[0].color, Colors.green);
      expect(node.fills[1].color, Colors.red);
      expect(node.fills[2].color, Colors.blue);
    });

    test('addStroke/removeStroke work correctly', () {
      node.strokes = [];
      final s1 = StrokeLayer(color: Colors.black, width: 1.0);
      final s2 = StrokeLayer(color: Colors.red, width: 2.0);
      node.addStroke(s1);
      node.addStroke(s2);
      expect(node.strokes.length, 2);

      node.removeStroke(s1.id);
      expect(node.strokes.length, 1);
      expect(node.strokes[0].id, s2.id);
    });

    test('maxStrokeBoundsInflation returns max inflation', () {
      node.strokes = [
        StrokeLayer(
          color: Colors.black,
          width: 4.0,
          position: StrokePosition.center,
        ), // inf = 2.0
        StrokeLayer(
          color: Colors.red,
          width: 3.0,
          position: StrokePosition.outside,
        ), // inf = 3.0
      ];
      expect(node.maxStrokeBoundsInflation, 3.0);
    });

    test('paintStackToJson serializes fills and strokes', () {
      node.fills = [FillLayer.solid(color: Colors.red)];
      node.strokes = [StrokeLayer(color: Colors.black, width: 2.0)];
      final json = node.paintStackToJson();
      expect(json.containsKey('fills'), true);
      expect(json.containsKey('strokes'), true);
      expect((json['fills'] as List).length, 1);
      expect((json['strokes'] as List).length, 1);
    });

    test('paintStackToJson omits empty lists', () {
      node.fills = [];
      node.strokes = [];
      final json = node.paintStackToJson();
      expect(json.containsKey('fills'), false);
      expect(json.containsKey('strokes'), false);
    });
  });

  // =========================================================================
  // PathNode backward-compat migration
  // =========================================================================
  group('PathNode backward compatibility', () {
    test('legacy fillColor migrates to fills stack on fromJson', () {
      final legacyJson = {
        'id': 'legacy-path',
        'nodeType': 'path',
        'path': _testVectorPath().toJson(),
        'fillColor': Colors.red.toARGB32(),
        'strokeColor': Colors.black.toARGB32(),
        'strokeWidth': 3.0,
        'strokeCap': ui.StrokeCap.butt.index,
        'strokeJoin': ui.StrokeJoin.miter.index,
      };

      final node = PathNode.fromJson(legacyJson);

      // Should have auto-migrated into the stack.
      expect(node.fills.length, 1);
      expect(node.fills[0].type, FillType.solid);
      expect(node.fills[0].color!.toARGB32(), Colors.red.toARGB32());

      expect(node.strokes.length, 1);
      expect(node.strokes[0].color!.toARGB32(), Colors.black.toARGB32());
      expect(node.strokes[0].width, 3.0);
    });

    test('new paint stack format takes priority over legacy', () {
      final newJson = {
        'id': 'new-path',
        'nodeType': 'path',
        'path': _testVectorPath().toJson(),
        'fillColor': Colors.red.toARGB32(), // legacy — ignored
        'fills': [
          FillLayer.solid(color: Colors.blue).toJson(),
          FillLayer.solid(color: Colors.green).toJson(),
        ],
        'strokes': [StrokeLayer(color: Colors.white, width: 1.0).toJson()],
      };

      final node = PathNode.fromJson(newJson);

      // New format should win.
      expect(node.fills.length, 2);
      expect(node.fills[0].color!.toARGB32(), Colors.blue.toARGB32());
      expect(node.fills[1].color!.toARGB32(), Colors.green.toARGB32());
      expect(node.strokes.length, 1);
    });

    test('PathNode toJson roundtrip preserves paint stack', () {
      final original = PathNode(
        id: NodeId('roundtrip'),
        path: _testVectorPath(),
        fills: [
          FillLayer.solid(color: Colors.red),
          FillLayer.fromGradient(
            gradient: LinearGradientFill(
              colors: [Colors.blue, Colors.green],
              stops: [0.0, 1.0],
            ),
            opacity: 0.6,
          ),
        ],
        strokes: [
          StrokeLayer(
            color: Colors.black,
            width: 2.0,
            position: StrokePosition.inside,
          ),
        ],
      );

      final json = original.toJson();
      final restored = PathNode.fromJson(json);

      expect(restored.fills.length, 2);
      expect(restored.fills[0].type, FillType.solid);
      expect(restored.fills[1].type, FillType.gradient);
      expect(restored.fills[1].opacity, closeTo(0.6, 0.001));
      expect(restored.strokes.length, 1);
      expect(restored.strokes[0].position, StrokePosition.inside);
    });
  });

  // =========================================================================
  // ShapeNode backward-compat migration
  // =========================================================================
  group('ShapeNode backward compatibility', () {
    test('legacy GeometricShape data migrates to paint stack', () {
      final shape = GeometricShape(
        id: NodeId('gs-1'),
        type: ShapeType.rectangle,
        startPoint: Offset.zero,
        endPoint: const Offset(100, 100),
        color: Colors.blue,
        strokeWidth: 2.0,
        filled: true,
        createdAt: DateTime.now(),
      );
      final legacyJson = {
        'id': 'legacy-shape',
        'nodeType': 'shape',
        'shape': shape.toJson(),
      };

      final node = ShapeNode.fromJson(legacyJson);
      expect(node.fills.length, 1);
      expect(node.fills[0].type, FillType.solid);
      expect(node.fills[0].color!.toARGB32(), Colors.blue.toARGB32());
      expect(node.strokes.length, 1);
      expect(node.strokes[0].width, 2.0);
    });
  });

  // =========================================================================
  // VectorNetworkNode backward-compat migration
  // =========================================================================
  group('VectorNetworkNode backward compatibility', () {
    test('legacy fillColor/strokeColor migrate to paint stack', () {
      final network = VectorNetwork(
        vertices: [
          NetworkVertex(position: Offset.zero),
          NetworkVertex(position: const Offset(100, 0)),
          NetworkVertex(position: const Offset(50, 100)),
        ],
        segments: [
          NetworkSegment(start: 0, end: 1),
          NetworkSegment(start: 1, end: 2),
          NetworkSegment(start: 2, end: 0),
        ],
        regions: [
          NetworkRegion(
            loops: [
              RegionLoop(
                segments: [
                  SegmentRef(index: 0, reversed: false),
                  SegmentRef(index: 1, reversed: false),
                  SegmentRef(index: 2, reversed: false),
                ],
              ),
            ],
          ),
        ],
      );

      final legacyJson = {
        'id': 'legacy-vn',
        'nodeType': 'vector_network',
        'network': network.toJson(),
        'fillColor': Colors.red.toARGB32(),
        'strokeColor': Colors.black.toARGB32(),
        'strokeWidth': 2.0,
      };

      final node = VectorNetworkNode.fromJson(legacyJson);
      expect(node.fills.length, 1);
      expect(node.fills[0].type, FillType.solid);
      expect(node.strokes.length, 1);
      expect(node.strokes[0].width, 2.0);
    });
  });

  // =========================================================================
  // localBounds with stroke stack
  // =========================================================================
  group('localBounds with stroke stack', () {
    test('PathNode localBounds uses maxStrokeBoundsInflation', () {
      final node = PathNode(
        id: NodeId('bounds-test'),
        path: _testVectorPath(),
        fills: [FillLayer.solid(color: Colors.red)],
        strokes: [
          StrokeLayer(
            color: Colors.black,
            width: 4.0,
            position: StrokePosition.center,
          ), // inf = 2.0
          StrokeLayer(
            color: Colors.blue,
            width: 6.0,
            position: StrokePosition.outside,
          ), // inf = 6.0
        ],
      );

      final bounds = node.localBounds;
      // The path's own bounds are approximately 0,0 to 100,100.
      // Max stroke inflation = 6.0 (outside with width 6).
      // So bounds should be inflated by 6 on each side.
      expect(bounds.left, lessThan(-5));
      expect(bounds.right, greaterThan(105));
    });
  });

  // =========================================================================
  // StyleDefinition integration
  // =========================================================================
  group('StyleDefinition paint stack', () {
    test('applyTo sets fills/strokes on PaintStackMixin node', () {
      final style = StyleDefinition(
        id: NodeId('test-style'),
        fills: [FillLayer.solid(color: Colors.red)],
        strokes: [StrokeLayer(color: Colors.black, width: 2.0)],
      );

      final node = PathNode(
        id: NodeId('styled-path'),
        path: _testVectorPath(),
        fills: [],
        strokes: [],
      );

      style.applyTo(node);

      expect(node.fills.length, 1);
      expect(node.fills[0].color!.toARGB32(), Colors.red.toARGB32());
      expect(node.strokes.length, 1);
      expect(node.strokes[0].width, 2.0);
    });

    test('StyleDefinition serialization roundtrip with fills/strokes', () {
      final original = StyleDefinition(
        id: NodeId('style-roundtrip'),
        name: 'Test',
        fills: [
          FillLayer.solid(color: Colors.blue),
          FillLayer.fromGradient(
            gradient: LinearGradientFill(
              colors: [Colors.red, Colors.green],
              stops: [0.0, 1.0],
            ),
          ),
        ],
        strokes: [StrokeLayer(color: Colors.black, width: 1.5)],
      );

      final json = original.toJson();
      final restored = StyleDefinition.fromJson(json);

      expect(restored.fills, isNotNull);
      expect(restored.fills!.length, 2);
      expect(restored.strokes, isNotNull);
      expect(restored.strokes!.length, 1);
    });
  });

  // =========================================================================
  // Sentinel copyWith (null-out fields)
  // =========================================================================
  group('Sentinel copyWith', () {
    test('FillLayer.copyWith can null-out color', () {
      final fill = FillLayer.solid(color: Colors.red);
      expect(fill.color, isNotNull);
      final cleared = fill.copyWith(color: null);
      expect(cleared.color, isNull);
      expect(cleared.id, fill.id);
      expect(cleared.type, FillType.solid);
    });

    test('FillLayer.copyWith can null-out gradient', () {
      final gradient = LinearGradientFill(
        colors: [Colors.red, Colors.blue],
        stops: [0.0, 1.0],
      );
      final fill = FillLayer.fromGradient(gradient: gradient);
      expect(fill.gradient, isNotNull);
      final cleared = fill.copyWith(gradient: null);
      expect(cleared.gradient, isNull);
    });

    test('StrokeLayer.copyWith can null-out color to switch to gradient', () {
      final stroke = StrokeLayer(color: Colors.red, width: 2.0);
      final gradient = LinearGradientFill(
        colors: [Colors.blue, Colors.green],
        stops: [0.0, 1.0],
      );
      final switched = stroke.copyWith(color: null, gradient: gradient);
      expect(switched.color, isNull);
      expect(switched.gradient, isNotNull);
    });

    test('StrokeLayer.copyWith can null-out dashPattern', () {
      final stroke = StrokeLayer(
        color: Colors.black,
        width: 1.0,
        dashPattern: [6.0, 3.0],
      );
      expect(stroke.dashPattern, isNotNull);
      final cleared = stroke.copyWith(dashPattern: null);
      expect(cleared.dashPattern, isNull);
    });
  });

  // =========================================================================
  // findFill / findStroke / clonePaintStackInto
  // =========================================================================
  group('Mixin helpers', () {
    test('findFill returns matching layer or null', () {
      final node = PathNode(id: NodeId('test'), path: _testVectorPath());
      final fill1 = FillLayer.solid(color: Colors.red);
      final fill2 = FillLayer.solid(color: Colors.blue);
      node.fills = [fill1, fill2];

      expect(node.findFill(fill1.id)?.color, Colors.red);
      expect(node.findFill(fill2.id)?.color, Colors.blue);
      expect(node.findFill('nonexistent'), isNull);
    });

    test('findStroke returns matching layer or null', () {
      final node = PathNode(id: NodeId('test'), path: _testVectorPath());
      final s1 = StrokeLayer(color: Colors.black, width: 1.0);
      final s2 = StrokeLayer(color: Colors.red, width: 3.0);
      node.strokes = [s1, s2];

      expect(node.findStroke(s1.id)?.width, 1.0);
      expect(node.findStroke(s2.id)?.width, 3.0);
      expect(node.findStroke('nonexistent'), isNull);
    });

    test('clonePaintStackInto creates independent copies', () {
      final source = PathNode(
        id: NodeId('src'),
        path: _testVectorPath(),
        fills: [FillLayer.solid(color: Colors.red)],
        strokes: [StrokeLayer(color: Colors.black, width: 2.0)],
      );
      final target = PathNode(id: NodeId('tgt'), path: _testVectorPath());

      source.clonePaintStackInto(target);

      // Same content.
      expect(target.fills.length, 1);
      expect(target.fills[0].color, Colors.red);
      expect(target.strokes.length, 1);
      expect(target.strokes[0].width, 2.0);

      // Independent — mutations don't leak.
      target.fills[0].color = Colors.green;
      expect(source.fills[0].color, Colors.red);

      target.strokes[0].width = 5.0;
      expect(source.strokes[0].width, 2.0);
    });
  });
}

// ---------------------------------------------------------------------------
// Helper: create a simple triangle VectorPath.
// ---------------------------------------------------------------------------
VectorPath _testVectorPath() {
  return VectorPath(
    segments: [
      MoveSegment(endPoint: Offset.zero),
      LineSegment(endPoint: const Offset(100, 0)),
      LineSegment(endPoint: const Offset(100, 100)),
    ],
    isClosed: true,
  );
}
