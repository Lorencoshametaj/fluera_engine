import 'package:flutter_test/flutter_test.dart';
import 'dart:ui';

import 'package:nebula_engine/src/rendering/scene_graph/render_plan.dart';
import 'package:nebula_engine/src/rendering/optimization/occlusion_culler.dart';
import 'package:nebula_engine/src/core/scene_graph/node_id.dart';
import 'package:nebula_engine/src/core/nodes/shape_node.dart';
import 'package:nebula_engine/src/core/models/shape_type.dart';

GeometricShape _makeRect(double x, double y, double w, double h, {String? id}) {
  return GeometricShape(
    id: id ?? 'gs-${x.toInt()}-${y.toInt()}',
    type: ShapeType.rectangle,
    startPoint: Offset(x, y),
    endPoint: Offset(x + w, y + h),
    color: const Color(0xFF000000),
    strokeWidth: 1.0,
    createdAt: DateTime(2026),
  );
}

void main() {
  group('OcclusionCuller', () {
    test('returns same list when fewer than 2 draws', () {
      final commands = <RenderCommand>[
        const RenderCommand.save(),
        const RenderCommand.restore(),
      ];
      final result = OcclusionCuller.optimize(commands);
      expect(identical(result, commands), isTrue);
    });

    test('returns same list when single draw', () {
      final shape = ShapeNode(
        id: NodeId('s1'),
        shape: _makeRect(0, 0, 100, 100),
      );
      final commands = <RenderCommand>[
        const RenderCommand.save(),
        RenderCommand.drawNode(shape),
        const RenderCommand.restore(),
      ];
      final result = OcclusionCuller.optimize(commands);
      expect(identical(result, commands), isTrue);
    });

    test('culls node fully occluded by opaque node above', () {
      final bottom = ShapeNode(
        id: NodeId('bottom'),
        shape: _makeRect(10, 10, 50, 50, id: 'gs-bottom'),
      );
      final top = ShapeNode(
        id: NodeId('top'),
        shape: _makeRect(0, 0, 200, 200, id: 'gs-top'),
      );

      final commands = <RenderCommand>[
        RenderCommand.drawNode(bottom),
        RenderCommand.drawNode(top),
      ];

      final result = OcclusionCuller.optimize(commands);
      expect(result.length, 2);
      expect(result[0].type, RenderCommandType.skip);
      expect(result[1].type, RenderCommandType.drawNode);
    });

    test('does NOT cull partially overlapping nodes', () {
      final bottom = ShapeNode(
        id: NodeId('bottom'),
        shape: _makeRect(0, 0, 100, 100, id: 'gs-b'),
      );
      final top = ShapeNode(
        id: NodeId('top'),
        shape: _makeRect(50, 50, 100, 100, id: 'gs-t'),
      );

      final commands = <RenderCommand>[
        RenderCommand.drawNode(bottom),
        RenderCommand.drawNode(top),
      ];

      final result = OcclusionCuller.optimize(commands);
      expect(identical(result, commands), isTrue);
    });

    test('does NOT cull transparent nodes as occluders', () {
      final bottom = ShapeNode(
        id: NodeId('bottom'),
        shape: _makeRect(10, 10, 50, 50, id: 'gs-b'),
      );
      final top = ShapeNode(
        id: NodeId('top'),
        shape: _makeRect(0, 0, 200, 200, id: 'gs-t'),
      );
      top.opacity = 0.5;

      final commands = <RenderCommand>[
        RenderCommand.drawNode(bottom),
        RenderCommand.drawNode(top),
      ];

      final result = OcclusionCuller.optimize(commands);
      expect(identical(result, commands), isTrue);
    });

    test('does NOT cull nodes with non-srcOver blend mode as occluders', () {
      final bottom = ShapeNode(
        id: NodeId('bottom'),
        shape: _makeRect(10, 10, 50, 50, id: 'gs-b'),
      );
      final top = ShapeNode(
        id: NodeId('top'),
        shape: _makeRect(0, 0, 200, 200, id: 'gs-t'),
      );
      top.blendMode = BlendMode.multiply;

      final commands = <RenderCommand>[
        RenderCommand.drawNode(bottom),
        RenderCommand.drawNode(top),
      ];

      final result = OcclusionCuller.optimize(commands);
      expect(identical(result, commands), isTrue);
    });

    test('culls multiple occluded nodes', () {
      final nodes = List.generate(
        3,
        (i) => ShapeNode(
          id: NodeId('s$i'),
          shape: _makeRect(i * 10.0, i * 10.0, 20, 20, id: 'gs-$i'),
        ),
      );
      final top = ShapeNode(
        id: NodeId('top'),
        shape: _makeRect(0, 0, 500, 500, id: 'gs-top'),
      );

      final commands = <RenderCommand>[
        ...nodes.map(RenderCommand.drawNode),
        RenderCommand.drawNode(top),
      ];

      final result = OcclusionCuller.optimize(commands);
      expect(result.length, 4);
      for (int i = 0; i < 3; i++) {
        expect(result[i].type, RenderCommandType.skip);
      }
      expect(result[3].type, RenderCommandType.drawNode);
    });

    test('ignores nodes with tiny area as occluders', () {
      // A tiny opaque node < minOccluderArea (100 px²) should not be an occluder.
      // Note: ShapeNode.localBounds adds strokeWidth padding, so use 0 stroke.
      final bottomShape = GeometricShape(
        id: 'gs-b',
        type: ShapeType.rectangle,
        startPoint: const Offset(0, 0),
        endPoint: const Offset(3, 3),
        color: const Color(0xFF000000),
        strokeWidth: 0.0,
        createdAt: DateTime(2026),
      );
      final topShape = GeometricShape(
        id: 'gs-t',
        type: ShapeType.rectangle,
        startPoint: const Offset(0, 0),
        endPoint: const Offset(5, 5),
        color: const Color(0xFF000000),
        strokeWidth: 0.0,
        createdAt: DateTime(2026),
      );
      final bottom = ShapeNode(id: NodeId('bottom'), shape: bottomShape);
      final top = ShapeNode(id: NodeId('top'), shape: topShape);

      final commands = <RenderCommand>[
        RenderCommand.drawNode(bottom),
        RenderCommand.drawNode(top),
      ];

      // Both are < 100 px², so neither should act as occluder.
      final result = OcclusionCuller.optimize(commands);
      expect(identical(result, commands), isTrue);
    });
  });
}
