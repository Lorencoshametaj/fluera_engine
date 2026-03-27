import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/nodes/group_node.dart';
import 'package:fluera_engine/src/core/nodes/symbol_system.dart';
import 'package:fluera_engine/src/core/scene_graph/node_id.dart';
import 'package:fluera_engine/src/systems/component_set.dart';

void main() {
  group('ComponentSet', () {
    test('manages definition IDs', () {
      final set = ComponentSet(
        id: 'set-1',
        name: 'Button',
        definitionIds: ['btn-a', 'btn-b'],
      );
      expect(set.variantCount, 2);
      expect(set.contains('btn-a'), isTrue);
      set.addDefinition('btn-c');
      expect(set.variantCount, 3);
      set.removeDefinition('btn-b');
      expect(set.variantCount, 2);
    });

    test('prevents duplicates', () {
      final set = ComponentSet(id: 's', name: 'S', definitionIds: ['a']);
      set.addDefinition('a');
      expect(set.variantCount, 1);
    });

    test('JSON roundtrip', () {
      final set = ComponentSet(
        id: 'set-1',
        name: 'Card',
        description: 'Card variants',
        definitionIds: ['c1', 'c2'],
        variantAxes: ['Style', 'Size'],
      );
      final restored = ComponentSet.fromJson(set.toJson());
      expect(restored.name, 'Card');
      expect(restored.variantAxes, ['Style', 'Size']);
      expect(restored.definitionIds.length, 2);
    });
  });

  group('ComponentSetRegistry', () {
    late ComponentSetRegistry registry;
    late SymbolRegistry symbolReg;

    setUp(() {
      registry = ComponentSetRegistry();
      symbolReg = SymbolRegistry();
    });

    test('register and find set for definition', () {
      registry.register(
        ComponentSet(
          id: 's1',
          name: 'Button',
          definitionIds: ['btn-a', 'btn-b'],
        ),
      );
      expect(registry.findSetForDefinition('btn-a')?.name, 'Button');
      expect(registry.findSetForDefinition('unknown'), isNull);
    });

    test('auto-groups by name prefix', () {
      symbolReg.register(
        SymbolDefinition(
          id: 'd1',
          name: 'Button/Primary',
          content: GroupNode(id: NodeId('c1')),
        ),
      );
      symbolReg.register(
        SymbolDefinition(
          id: 'd2',
          name: 'Button/Secondary',
          content: GroupNode(id: NodeId('c2')),
        ),
      );
      symbolReg.register(
        SymbolDefinition(
          id: 'd3',
          name: 'Card/Default',
          content: GroupNode(id: NodeId('c3')),
        ),
      );
      symbolReg.register(
        SymbolDefinition(
          id: 'd4',
          name: 'Standalone',
          content: GroupNode(id: NodeId('c4')),
        ),
      );

      final sets = registry.autoGroup(symbolReg);
      // Button has 2 variants → grouped. Card has 1 → not grouped. Standalone → no prefix.
      expect(sets.length, 1);
      expect(sets.first.name, 'Button');
      expect(sets.first.variantCount, 2);
    });

    test('resolves definitions from SymbolRegistry', () {
      symbolReg.register(
        SymbolDefinition(
          id: 'x',
          name: 'X',
          content: GroupNode(id: NodeId('cx')),
        ),
      );
      registry.register(
        ComponentSet(id: 's1', name: 'S', definitionIds: ['x', 'missing']),
      );
      final defs = registry.resolveDefinitions('s1', symbolReg);
      expect(defs.length, 1);
      expect(defs.first.name, 'X');
    });

    test('JSON roundtrip', () {
      registry.register(
        ComponentSet(id: 's1', name: 'Tab', definitionIds: ['t1', 't2']),
      );
      final restored = ComponentSetRegistry.fromJson(registry.toJson());
      expect(restored.length, 1);
      expect(restored.get('s1')?.name, 'Tab');
    });
  });
}
