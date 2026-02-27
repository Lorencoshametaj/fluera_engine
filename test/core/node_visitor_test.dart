import 'package:fluera_engine/src/core/scene_graph/node_id.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/scene_graph/canvas_node.dart';
import 'package:fluera_engine/src/core/scene_graph/node_visitor.dart';
import 'package:fluera_engine/src/core/nodes/stroke_node.dart';
import 'package:fluera_engine/src/core/nodes/shape_node.dart';
import 'package:fluera_engine/src/core/nodes/text_node.dart';
import 'package:fluera_engine/src/core/nodes/image_node.dart';
import 'package:fluera_engine/src/core/nodes/group_node.dart';
import 'package:fluera_engine/src/core/nodes/layer_node.dart';
import 'package:fluera_engine/src/core/nodes/path_node.dart';
import 'package:fluera_engine/src/core/nodes/clip_group_node.dart';
import 'package:fluera_engine/src/core/nodes/rich_text_node.dart';
import 'package:fluera_engine/src/core/nodes/frame_node.dart';
import 'package:fluera_engine/src/core/nodes/symbol_system.dart';
import 'package:fluera_engine/src/core/nodes/advanced_mask_node.dart';
import 'package:fluera_engine/src/core/effects/shader_effect.dart';

import '../helpers/test_helpers.dart';

/// Visitor that records which visit method was called.
class _TrackingVisitor extends DefaultNodeVisitor<String> {
  _TrackingVisitor() : super('');
  @override
  String visitStroke(StrokeNode node) => 'stroke:${node.id}';

  @override
  String visitShape(ShapeNode node) => 'shape:${node.id}';

  @override
  String visitGroup(GroupNode node) => 'group:${node.id}';

  @override
  String visitLayer(LayerNode node) => 'layer:${node.id}';
}

void main() {
  group('NodeVisitor dispatch', () {
    late _TrackingVisitor visitor;

    setUp(() {
      visitor = _TrackingVisitor();
    });

    test('dispatches StrokeNode correctly', () {
      final node = testStrokeNode(id: NodeId('s1'));
      expect(node.accept(visitor), 'stroke:s1');
    });

    test('dispatches ShapeNode correctly', () {
      final node = testShapeNode(id: NodeId('sh1'));
      expect(node.accept(visitor), 'shape:sh1');
    });

    test('dispatches GroupNode correctly', () {
      final node = testGroupNode(id: NodeId('g1'));
      expect(node.accept(visitor), 'group:g1');
    });

    test('dispatches LayerNode correctly', () {
      final node = testLayerNode(id: NodeId('l1'));
      expect(node.accept(visitor), 'layer:l1');
    });
  });

  group('DefaultNodeVisitor fallback', () {
    test('unimplemented visit methods return null', () {
      final visitor = DefaultNodeVisitor<String?>('');
      final stroke = testStrokeNode();
      // DefaultNodeVisitor returns the default value for all visits
      expect(stroke.accept(visitor), '');
    });
  });
}
