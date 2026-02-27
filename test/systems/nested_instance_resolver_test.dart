import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/scene_graph/node_id.dart';
import 'package:fluera_engine/src/core/nodes/group_node.dart';
import 'package:fluera_engine/src/core/nodes/symbol_system.dart';
import 'package:fluera_engine/src/systems/nested_instance_resolver.dart';

void main() {
  late SymbolRegistry registry;
  late NestedInstanceResolver resolver;

  setUp(() {
    registry = SymbolRegistry();
    resolver = NestedInstanceResolver(registry: registry);
  });

  group('NestedInstanceResolver', () {
    test('resolves single-level instance', () {
      // Create a simple definition: a group with a named child.
      final defContent = GroupNode(
        id: NodeId('content-root'),
        name: 'BtnContent',
      );
      defContent.add(GroupNode(id: NodeId('label'), name: 'label'));

      final def = SymbolDefinition(
        id: 'btn-def',
        name: 'Button',
        content: defContent,
      );
      registry.register(def);

      final instance = SymbolInstanceNode(
        id: NodeId('inst-1'),
        symbolDefinitionId: 'btn-def',
      );

      final resolved = resolver.resolveDeep(instance);
      expect(resolved, isNotNull);
      expect(resolved!.children, isNotEmpty);
    });

    test('returns null for unknown definition', () {
      final instance = SymbolInstanceNode(
        id: NodeId('inst-1'),
        symbolDefinitionId: 'nonexistent',
      );
      expect(resolver.resolveDeep(instance), isNull);
    });

    test('respects max depth limit', () {
      // With maxDepth=0, even a valid definition should return null.
      final defContent = GroupNode(id: NodeId('content'), name: 'Content');
      final def = SymbolDefinition(
        id: 'def-1',
        name: 'Comp',
        content: defContent,
      );
      registry.register(def);

      final instance = SymbolInstanceNode(
        id: NodeId('inst-1'),
        symbolDefinitionId: 'def-1',
      );

      // maxDepth=0 means no resolution at all.
      final zeroDepth = NestedInstanceResolver(registry: registry, maxDepth: 0);
      expect(zeroDepth.resolveDeep(instance), isNull);

      // maxDepth=1 allows single-level resolution.
      final oneDepth = NestedInstanceResolver(registry: registry, maxDepth: 1);
      expect(oneDepth.resolveDeep(instance), isNotNull);
    });

    test('applies override to child by name', () {
      final defContent = GroupNode(id: NodeId('root'), name: 'Root');
      final child = GroupNode(id: NodeId('inner'), name: 'inner');
      defContent.add(child);

      final def = SymbolDefinition(
        id: 'card-def',
        name: 'Card',
        content: defContent,
      );
      registry.register(def);

      final instance = SymbolInstanceNode(
        id: NodeId('inst-1'),
        symbolDefinitionId: 'card-def',
        overrides: {'inner.opacity': 0.5},
      );

      final resolved = resolver.resolveDeep(instance);
      expect(resolved, isNotNull);
      // The override cascade applied 'inner.opacity' = 0.5.
      final innerNode = resolved!.children.first;
      expect(innerNode.opacity, closeTo(0.5, 0.01));
    });

    test('countNestingDepth detects unresolved instances', () {
      final instance = SymbolInstanceNode(
        id: NodeId('orphan'),
        symbolDefinitionId: 'nonexistent',
      );
      expect(NestedInstanceResolver.countNestingDepth(instance), 1);
    });

    test('findUnresolved returns SymbolInstanceNodes', () {
      final group = GroupNode(id: NodeId('g'), name: 'g');
      group.add(
        SymbolInstanceNode(
          id: NodeId('i1'),
          symbolDefinitionId: 'missing',
          name: 'orphan1',
        ),
      );
      group.add(GroupNode(id: NodeId('g2'), name: 'g2'));

      final unresolved = NestedInstanceResolver.findUnresolved(group);
      expect(unresolved.length, 1);
      expect(unresolved.first.name, 'orphan1');
    });

    test('extracts nested overrides with prefix stripping', () {
      final defContent = GroupNode(id: NodeId('root'), name: 'Root');
      final btnGroup = GroupNode(id: NodeId('btn'), name: 'button');
      defContent.add(btnGroup);

      final def = SymbolDefinition(
        id: 'card-def',
        name: 'Card',
        content: defContent,
      );
      registry.register(def);

      // Override with a dot-path targeting nested "button.opacity".
      final instance = SymbolInstanceNode(
        id: NodeId('inst-1'),
        symbolDefinitionId: 'card-def',
        overrides: {'button.opacity': 0.3},
      );

      final resolved = resolver.resolveDeep(instance);
      expect(resolved, isNotNull);
      final btn = resolved!.children.first;
      expect(btn.name, 'button');
      expect(btn.opacity, closeTo(0.3, 0.01));
    });
  });
}
