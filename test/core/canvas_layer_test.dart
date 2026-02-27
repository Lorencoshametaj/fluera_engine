import 'package:fluera_engine/src/core/scene_graph/node_id.dart';
import 'dart:ui' as ui;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/models/canvas_layer.dart';
import 'package:fluera_engine/src/drawing/models/pro_drawing_point.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // =========================================================================
  // CanvasLayer
  // =========================================================================

  group('CanvasLayer', () {
    CanvasLayer createLayer({
      String id = 'layer-1',
      String name = 'Test Layer',
      List<ProStroke>? strokes,
      bool isVisible = true,
      bool isLocked = false,
      double opacity = 1.0,
    }) {
      return CanvasLayer(
        id: id,
        name: name,
        strokes: strokes,
        isVisible: isVisible,
        isLocked: isLocked,
        opacity: opacity,
      );
    }

    ProStroke createStroke(String id) {
      return ProStroke(
        id: id,
        points: [
          const ProDrawingPoint(
            position: Offset(10, 20),
            pressure: 0.5,
            timestamp: 100,
          ),
        ],
        color: const Color(0xFF000000),
        baseWidth: 2.0,
        penType: ProPenType.ballpoint,
        createdAt: DateTime(2025, 1, 1),
      );
    }

    // ── Construction ───────────────────────────────────────────────────

    group('construction', () {
      test('creates with required fields', () {
        final layer = createLayer();
        expect(layer.id, 'layer-1');
        expect(layer.name, 'Test Layer');
        expect(layer.isVisible, isTrue);
        expect(layer.isLocked, isFalse);
        expect(layer.opacity, 1.0);
        expect(layer.blendMode, ui.BlendMode.srcOver);
      });

      test('starts empty by default', () {
        final layer = createLayer();
        expect(layer.isEmpty, isTrue);
        expect(layer.elementCount, 0);
        expect(layer.strokes, isEmpty);
        expect(layer.shapes, isEmpty);
        expect(layer.texts, isEmpty);
        expect(layer.images, isEmpty);
      });

      test('accepts initial strokes', () {
        final stroke = createStroke('s1');
        final layer = createLayer(strokes: [stroke]);
        expect(layer.strokes.length, 1);
        expect(layer.isEmpty, isFalse);
        expect(layer.elementCount, 1);
      });

      test('custom visibility and lock', () {
        final layer = createLayer(isVisible: false, isLocked: true);
        expect(layer.isVisible, isFalse);
        expect(layer.isLocked, isTrue);
      });

      test('custom opacity', () {
        final layer = createLayer(opacity: 0.5);
        expect(layer.opacity, 0.5);
      });
    });

    // ── copyWith ───────────────────────────────────────────────────────

    group('copyWith', () {
      test('copies all fields when nothing overridden', () {
        final original = createLayer(
          id: NodeId('original'),
          name: 'Original',
          isVisible: true,
          isLocked: false,
          opacity: 0.8,
        );
        final copy = original.copyWith();
        expect(copy.id, 'original');
        expect(copy.name, 'Original');
        expect(copy.isVisible, isTrue);
        expect(copy.isLocked, isFalse);
        expect(copy.opacity, 0.8);
      });

      test('overrides specified fields', () {
        final original = createLayer();
        final copy = original.copyWith(
          name: 'New Name',
          isVisible: false,
          opacity: 0.3,
        );
        expect(copy.name, 'New Name');
        expect(copy.isVisible, isFalse);
        expect(copy.opacity, 0.3);
        expect(copy.id, original.id); // unchanged
      });

      test('can change lock state', () {
        final layer = createLayer(isLocked: false);
        final locked = layer.copyWith(isLocked: true);
        expect(locked.isLocked, isTrue);
      });

      test('can change blend mode', () {
        final layer = createLayer();
        final copy = layer.copyWith(blendMode: ui.BlendMode.multiply);
        expect(copy.blendMode, ui.BlendMode.multiply);
      });
    });

    // ── Serialization ──────────────────────────────────────────────────

    group('serialization', () {
      test('toJson returns a map', () {
        final layer = createLayer();
        final json = layer.toJson();
        expect(json, isA<Map<String, dynamic>>());
      });
    });

    // ── fromNode ───────────────────────────────────────────────────────

    group('fromNode', () {
      test('wraps an existing LayerNode', () {
        final layer = createLayer(id: NodeId('from-node'));
        final wrapped = CanvasLayer.fromNode(layer.node);
        expect(wrapped.id, 'from-node');
        expect(wrapped.name, layer.name);
      });
    });
  });
}
