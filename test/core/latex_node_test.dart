import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/nodes/latex_node.dart';
import 'package:fluera_engine/src/core/scene_graph/canvas_node_factory.dart';
import 'package:fluera_engine/src/core/scene_graph/node_id.dart';
import 'package:fluera_engine/src/core/latex/latex_draw_command.dart';

void main() {
  // ===========================================================================
  // LatexNode — Properties & Defaults
  // ===========================================================================

  group('LatexNode properties', () {
    test('default values are correct', () {
      final node = LatexNode(id: NodeId('test-1'), latexSource: r'\frac{a}{b}');
      expect(node.latexSource, r'\frac{a}{b}');
      expect(node.fontSize, 20.0);
      expect(node.color, const Color(0xFFFFFFFF));
      expect(node.opacity, 1.0);
      expect(node.isVisible, true);
      expect(node.isLocked, false);
      expect(node.cachedLayout, isNull);
      expect(node.cachedDrawCommands, isNull);
    });

    test('custom properties are set correctly', () {
      final node = LatexNode(
        id: NodeId('test-2'),
        latexSource: r'x^2',
        fontSize: 32.0,
        color: const Color(0xFF00FF00),
        name: 'My Equation',
      );
      expect(node.latexSource, r'x^2');
      expect(node.fontSize, 32.0);
      expect(node.color, const Color(0xFF00FF00));
      expect(node.name, 'My Equation');
    });

    test('setting latexSource invalidates cache', () {
      final node = LatexNode(id: NodeId('test-3'), latexSource: r'a');
      node.cachedLayout = const LatexLayoutResult(
        commands: [],
        size: Size(10, 10),
      );
      expect(node.cachedLayout, isNotNull);

      node.latexSource = r'b';
      expect(node.cachedLayout, isNull);
    });

    test('setting fontSize invalidates cache', () {
      final node = LatexNode(id: NodeId('test-4'), latexSource: r'x');
      node.cachedLayout = const LatexLayoutResult(
        commands: [],
        size: Size(10, 10),
      );
      node.fontSize = 48.0;
      expect(node.cachedLayout, isNull);
    });

    test('setting color invalidates cache', () {
      final node = LatexNode(id: NodeId('test-5'), latexSource: r'x');
      node.cachedLayout = const LatexLayoutResult(
        commands: [],
        size: Size(10, 10),
      );
      node.color = const Color(0xFFFF0000);
      expect(node.cachedLayout, isNull);
    });

    test('setting same value does not invalidate cache', () {
      final node = LatexNode(id: NodeId('test-6'), latexSource: r'x');
      node.cachedLayout = const LatexLayoutResult(
        commands: [],
        size: Size(10, 10),
      );
      node.latexSource = r'x'; // same value
      expect(node.cachedLayout, isNotNull);
    });
  });

  // ===========================================================================
  // LatexNode — Bounds
  // ===========================================================================

  group('LatexNode bounds', () {
    test('localBounds uses cached layout size when available', () {
      final node = LatexNode(id: NodeId('bounds-1'), latexSource: r'x');
      node.cachedLayout = const LatexLayoutResult(
        commands: [],
        size: Size(100, 30),
      );
      expect(node.localBounds, const Rect.fromLTWH(0, 0, 100, 30));
    });

    test('localBounds estimates when no cached layout', () {
      final node = LatexNode(
        id: NodeId('bounds-2'),
        latexSource: r'abc',
        fontSize: 20.0,
      );
      final bounds = node.localBounds;
      expect(bounds.width, greaterThan(0));
      expect(bounds.height, greaterThan(0));
    });
  });

  // ===========================================================================
  // LatexNode — Serialization Roundtrip
  // ===========================================================================

  group('LatexNode serialization roundtrip', () {
    test('toJson → fromJson preserves all fields', () {
      final original = LatexNode(
        id: NodeId('ser-1'),
        latexSource: r'\int_{0}^{1} x^2 dx',
        fontSize: 28.0,
        color: const Color(0xFF00CCFF),
        name: 'Integral',
      );
      original.opacity = 0.75;
      original.isVisible = false;
      original.isLocked = true;

      final json = original.toJson();
      final restored = LatexNode.fromJson(json);

      expect(restored.id, 'ser-1');
      expect(restored.latexSource, r'\int_{0}^{1} x^2 dx');
      expect(restored.fontSize, 28.0);
      expect(restored.color, const Color(0xFF00CCFF));
      expect(restored.name, 'Integral');
      expect(restored.opacity, 0.75);
      expect(restored.isVisible, false);
      expect(restored.isLocked, true);
    });

    test('nodeType is "latex"', () {
      final node = LatexNode(id: NodeId('ser-2'), latexSource: r'x');
      expect(node.toJson()['nodeType'], 'latex');
    });

    test('default fontSize is omitted from JSON', () {
      final node = LatexNode(
        id: NodeId('ser-3'),
        latexSource: r'x',
        fontSize: 20.0,
      );
      expect(node.toJson().containsKey('fontSize'), false);
    });

    test('non-default fontSize is included in JSON', () {
      final node = LatexNode(
        id: NodeId('ser-4'),
        latexSource: r'x',
        fontSize: 32.0,
      );
      expect(node.toJson()['fontSize'], 32.0);
    });

    test('fromJson handles missing optional fields gracefully', () {
      final json = {'id': 'ser-5', 'nodeType': 'latex', 'latexSource': 'y'};
      final node = LatexNode.fromJson(json);
      expect(node.latexSource, 'y');
      expect(node.fontSize, 20.0);
      expect(node.color, const Color(0xFFFFFFFF));
    });
  });

  // ===========================================================================
  // LatexNode — CanvasNodeFactory Integration
  // ===========================================================================

  group('CanvasNodeFactory dispatch', () {
    test('fromJson creates LatexNode for nodeType "latex"', () {
      final json = {
        'id': 'factory-1',
        'nodeType': 'latex',
        'latexSource': r'\sqrt{2}',
        'color': 0xFFFFFFFF,
      };
      final node = CanvasNodeFactory.fromJson(json);
      expect(node, isA<LatexNode>());
      expect((node as LatexNode).latexSource, r'\sqrt{2}');
    });
  });

  // ===========================================================================
  // LatexNode — Clone
  // ===========================================================================

  group('LatexNode clone', () {
    test('clone produces a different node with different id', () {
      final original = LatexNode(
        id: NodeId('clone-1'),
        latexSource: r'\alpha + \beta',
        fontSize: 24.0,
        color: const Color(0xFFFF0000),
      );
      final cloned = original.clone();

      expect(cloned.id, isNot(equals(original.id)));
      expect(cloned, isA<LatexNode>());
    });

    test('clone preserves properties', () {
      final original = LatexNode(
        id: NodeId('clone-2'),
        latexSource: r'\pi',
        fontSize: 30.0,
        color: const Color(0xFF0000FF),
        name: 'Pi',
      );
      original.opacity = 0.5;
      final cloned = original.clone() as LatexNode;

      expect(cloned.latexSource, r'\pi');
      expect(cloned.fontSize, 30.0);
      expect(cloned.color, const Color(0xFF0000FF));
      expect(cloned.name, 'Pi');
      expect(cloned.opacity, 0.5);
    });
  });

  // ===========================================================================
  // LatexDrawCommand — Serialization
  // ===========================================================================

  group('LatexDrawCommand serialization', () {
    test('GlyphDrawCommand roundtrip', () {
      final cmd = GlyphDrawCommand(
        text: 'x',
        x: 10.0,
        y: 20.0,
        fontSize: 24.0,
        color: const Color(0xFFFF0000),
        italic: true,
        bold: false,
      );
      final json = cmd.toJson();
      final restored = LatexDrawCommand.fromJson(json) as GlyphDrawCommand;

      expect(restored.text, 'x');
      expect(restored.x, 10.0);
      expect(restored.y, 20.0);
      expect(restored.fontSize, 24.0);
      expect(restored.italic, true);
      expect(restored.bold, false);
    });

    test('LineDrawCommand roundtrip', () {
      final cmd = LineDrawCommand(
        x1: 0.0,
        y1: 10.0,
        x2: 100.0,
        y2: 10.0,
        thickness: 2.0,
        color: const Color(0xFF00FF00),
      );
      final json = cmd.toJson();
      final restored = LatexDrawCommand.fromJson(json) as LineDrawCommand;

      expect(restored.x1, 0.0);
      expect(restored.y1, 10.0);
      expect(restored.x2, 100.0);
      expect(restored.thickness, 2.0);
    });

    test('PathDrawCommand roundtrip', () {
      final cmd = PathDrawCommand(
        points: [const Offset(0, 0), const Offset(10, 20), const Offset(5, 30)],
        closed: true,
        strokeWidth: 1.5,
        color: const Color(0xFF0000FF),
        filled: true,
      );
      final json = cmd.toJson();
      final restored = LatexDrawCommand.fromJson(json) as PathDrawCommand;

      expect(restored.points.length, 3);
      expect(restored.points[1].dx, 10.0);
      expect(restored.points[1].dy, 20.0);
      expect(restored.closed, true);
      expect(restored.filled, true);
    });
  });
}
