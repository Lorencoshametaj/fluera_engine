import 'package:fluera_engine/src/core/scene_graph/node_id.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/nodes/section_node.dart';
import 'package:fluera_engine/src/core/scene_graph/canvas_node.dart';
import 'package:fluera_engine/src/core/scene_graph/canvas_node_factory.dart';
import 'package:fluera_engine/src/core/scene_graph/node_visitor.dart';

// =============================================================================
// Test helpers
// =============================================================================

/// Concrete leaf node for testing children inside sections.
class _Box extends CanvasNode {
  final Rect _bounds;

  _Box({required super.id, required double width, required double height})
    : _bounds = Rect.fromLTWH(0, 0, width, height);

  @override
  Rect get localBounds => _bounds;

  @override
  Map<String, dynamic> toJson() => {'id': id, 'nodeType': 'test'};

  @override
  R accept<R>(NodeVisitor<R> visitor) =>
      throw UnimplementedError('not needed for tests');
}

// =============================================================================
// Tests
// =============================================================================

void main() {
  // ===========================================================================
  // 1. Default construction
  // ===========================================================================
  test('default construction has expected values', () {
    final section = SectionNode(id: NodeId('s1'));

    expect(section.sectionName, 'Section');
    expect(section.sectionSize, const Size(800, 600));
    expect(section.backgroundColor, isNull);
    expect(section.showGrid, isFalse);
    expect(section.gridSpacing, 20);
    expect(section.preset, isNull);
    expect(section.clipContent, isFalse);
    expect(section.borderWidth, 1.0);
  });

  // ===========================================================================
  // 2. fromPreset factory
  // ===========================================================================
  test('fromPreset creates section with preset dimensions', () {
    final section = SectionNode.fromPreset(
      id: NodeId('s2'),
      preset: SectionPreset.iphone16,
    );

    expect(section.sectionName, 'iPhone 16');
    expect(section.sectionSize, const Size(393, 852));
    expect(section.preset, SectionPreset.iphone16);
    expect(section.backgroundColor, Colors.white);
  });

  // ===========================================================================
  // 3. localBounds
  // ===========================================================================
  test('localBounds returns rect from sectionSize', () {
    final section = SectionNode(
      id: NodeId('s3'),
      sectionSize: const Size(1920, 1080),
    );

    expect(section.localBounds, const Rect.fromLTWH(0, 0, 1920, 1080));
  });

  // ===========================================================================
  // 4. boundsWithLabel
  // ===========================================================================
  test('boundsWithLabel includes label area above', () {
    final section = SectionNode(
      id: NodeId('s4'),
      sectionSize: const Size(800, 600),
    );

    final bounds = section.boundsWithLabel;
    expect(bounds.top, -SectionNode.labelHeight);
    expect(bounds.width, 800);
    expect(bounds.height, 600 + SectionNode.labelHeight);
  });

  // ===========================================================================
  // 5. JSON serialization roundtrip
  // ===========================================================================
  test('JSON roundtrip preserves all fields', () {
    final original = SectionNode(
      id: NodeId('s5'),
      sectionName: 'Home Screen',
      sectionSize: const Size(393, 852),
      backgroundColor: const Color(0xFFF5F5F5),
      showGrid: true,
      gridSpacing: 16,
      preset: SectionPreset.iphone16,
      clipContent: true,
      borderColor: const Color(0xFF2196F3),
      borderWidth: 2.0,
    );

    final json = original.toJson();
    final restored = SectionNode.fromJson(json);

    expect(restored.id, 's5');
    expect(restored.sectionName, 'Home Screen');
    expect(restored.sectionSize, const Size(393, 852));
    expect(restored.backgroundColor, const Color(0xFFF5F5F5));
    expect(restored.showGrid, isTrue);
    expect(restored.gridSpacing, 16);
    expect(restored.preset, SectionPreset.iphone16);
    expect(restored.clipContent, isTrue);
    expect(restored.borderColor, const Color(0xFF2196F3));
    expect(restored.borderWidth, 2.0);
  });

  // ===========================================================================
  // 6. JSON nodeType
  // ===========================================================================
  test('toJson emits nodeType "section"', () {
    final section = SectionNode(id: NodeId('s6'));
    final json = section.toJson();
    expect(json['nodeType'], 'section');
  });

  // ===========================================================================
  // 7. JSON without preset
  // ===========================================================================
  test('JSON roundtrip works without preset', () {
    final section = SectionNode(
      id: NodeId('s7'),
      sectionName: 'Custom Area',
      sectionSize: const Size(500, 400),
    );

    final json = section.toJson();
    expect(json.containsKey('preset'), isFalse);

    final restored = SectionNode.fromJson(json);
    expect(restored.preset, isNull);
  });

  // ===========================================================================
  // 8. JSON with unknown preset (graceful)
  // ===========================================================================
  test('fromJson handles unknown preset gracefully', () {
    final json = <String, dynamic>{
      'id': 's8',
      'nodeType': 'section',
      'sectionName': 'Test',
      'sectionSize': {'width': 800, 'height': 600},
      'preset': 'nonExistentPreset',
      'showGrid': false,
      'gridSpacing': 20,
      'clipContent': false,
      'borderColor': 0xFFBDBDBD,
      'borderWidth': 1.0,
      'children': <dynamic>[],
    };

    final section = SectionNode.fromJson(json);
    expect(section.preset, isNull);
    expect(section.sectionName, 'Test');
  });

  // ===========================================================================
  // 9. Children in section
  // ===========================================================================
  test('children can be added to section', () {
    final section = SectionNode(
      id: NodeId('s9'),
      sectionSize: const Size(800, 600),
    );

    final box1 = _Box(id: NodeId('b1'), width: 100, height: 50);
    final box2 = _Box(id: NodeId('b2'), width: 200, height: 100);

    section.add(box1);
    section.add(box2);

    expect(section.childCount, 2);
    expect(section.findChild('b1'), isNotNull);
    expect(section.findChild('b2'), isNotNull);
  });

  // ===========================================================================
  // 10. Section presets
  // ===========================================================================
  test('SectionPreset provides correct dimensions', () {
    expect(SectionPreset.a4Portrait.size, const Size(595, 842));
    expect(SectionPreset.desktop1080p.size, const Size(1920, 1080));
    expect(SectionPreset.instagramPost.size, const Size(1080, 1080));
    expect(SectionPreset.presentation16x9.size, const Size(1920, 1080));
    expect(SectionPreset.ipadPro11.size, const Size(834, 1194));
  });

  // ===========================================================================
  // 11. Resize clears preset
  // ===========================================================================
  test('resize clears preset', () {
    final section = SectionNode.fromPreset(
      id: NodeId('s11'),
      preset: SectionPreset.iphone16,
    );

    expect(section.preset, SectionPreset.iphone16);

    section.resize(const Size(400, 700));

    expect(section.sectionSize, const Size(400, 700));
    expect(section.preset, isNull);
  });

  // ===========================================================================
  // 12. JSON children roundtrip via CanvasNodeFactory
  // ===========================================================================
  test('JSON serializes children array', () {
    final section = SectionNode(
      id: NodeId('s12'),
      sectionSize: const Size(800, 600),
    );

    final json = section.toJson();
    expect(json['children'], isA<List>());
    expect((json['children'] as List).isEmpty, isTrue);
  });

  // ===========================================================================
  // 13. Visitor dispatch
  // ===========================================================================
  test('accept dispatches to visitSection', () {
    final section = SectionNode(id: NodeId('s13'));
    var visited = false;

    final visitor = _SectionVisitor(onVisit: () => visited = true);
    section.accept(visitor);

    expect(visited, isTrue);
  });

  // ===========================================================================
  // 14. Hit testing within bounds
  // ===========================================================================
  test('hitTest returns true for point inside bounds', () {
    final section = SectionNode(
      id: NodeId('s14'),
      sectionSize: const Size(800, 600),
    );

    expect(section.hitTest(const Offset(400, 300)), isTrue);
    expect(section.hitTest(const Offset(0, 0)), isTrue);
    expect(section.hitTest(const Offset(799, 599)), isTrue);
  });

  test('hitTest returns false for point outside bounds', () {
    final section = SectionNode(
      id: NodeId('s15'),
      sectionSize: const Size(800, 600),
    );

    expect(section.hitTest(const Offset(-1, 300)), isFalse);
    expect(section.hitTest(const Offset(400, -1)), isFalse);
    expect(section.hitTest(const Offset(801, 300)), isFalse);
    expect(section.hitTest(const Offset(400, 601)), isFalse);
  });

  // ===========================================================================
  // 15. All presets have valid labels
  // ===========================================================================
  test('all presets have non-empty labels and positive dimensions', () {
    for (final preset in SectionPreset.values) {
      expect(
        preset.label.isNotEmpty,
        isTrue,
        reason: '${preset.name} should have a label',
      );
      expect(
        preset.width,
        greaterThan(0),
        reason: '${preset.name} width should be > 0',
      );
      expect(
        preset.height,
        greaterThan(0),
        reason: '${preset.name} height should be > 0',
      );
    }
  });
}

// =============================================================================
// Helper visitor
// =============================================================================

class _SectionVisitor extends DefaultNodeVisitor<void> {
  final void Function() onVisit;

  _SectionVisitor({required this.onVisit}) : super(null);

  @override
  void visitSection(SectionNode node) => onVisit();
}
