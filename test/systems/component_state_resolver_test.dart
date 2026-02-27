import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/systems/component_state_machine.dart';
import 'package:fluera_engine/src/systems/component_state_resolver.dart';
import 'package:fluera_engine/src/core/nodes/symbol_system.dart';
import 'package:fluera_engine/src/core/nodes/group_node.dart';
import 'package:fluera_engine/src/core/nodes/variant_property.dart';
import 'package:fluera_engine/src/core/scene_graph/node_id.dart';

// Mock SymbolDefinition that returns a GroupNode with name matching selections
class MockSymbolDefinition extends SymbolDefinition {
  MockSymbolDefinition({required super.id, required String name})
    : super(name: name, content: GroupNode(id: NodeId('mock-content-$id')));

  // Override resolveContent to return a group with serialized selections
  @override
  GroupNode resolveContent(Map<String, String> selections) {
    final keys = selections.keys.toList()..sort();
    final parts = keys.map((k) => '$k=${selections[k]}').join(', ');
    return GroupNode(id: NodeId('content-$id'), name: parts);
  }
}

void main() {
  group('ComponentStateResolver Tests', () {
    late ComponentStateMachine stateMachine;
    late ComponentStateResolver resolver;
    late SymbolDefinition definition;

    setUp(() {
      stateMachine = ComponentStateMachine();
      stateMachine.registerStates('btn-def', {
        InteractiveState.hover: {'state': 'hover'},
        InteractiveState.pressed: {'state': 'pressed', 'shadow': 'none'},
        InteractiveState.disabled: {'state': 'disabled'},
      });

      resolver = ComponentStateResolver(stateMachine: stateMachine);

      definition =
          MockSymbolDefinition(id: 'btn-def', name: 'Button')
            ..addVariantProperty(
              VariantProperty.variant(
                name: 'state',
                options: ['default', 'hover', 'pressed', 'disabled'],
                defaultValue: 'default',
              ),
            )
            ..addVariantProperty(
              VariantProperty.variant(
                name: 'shadow',
                options: ['large', 'none'],
                defaultValue: 'large',
              ),
            )
            ..addVariantProperty(
              VariantProperty.variant(
                name: 'size',
                options: ['small', 'large'],
                defaultValue: 'large',
              ),
            );
    });

    test('resolveSelections applies override cascading', () {
      final instance = SymbolInstanceNode(
        id: NodeId('inst-1'),
        symbolDefinitionId: 'btn-def',
        variantSelections: {'size': 'small'}, // User override
      );

      // Default state: Should use definition defaults + instance overrides
      final defaultSelections = resolver.resolveSelections(
        definition,
        instance,
        InteractiveState.defaultState,
      );
      expect(defaultSelections['state'], 'default');
      expect(defaultSelections['shadow'], 'large');
      expect(defaultSelections['size'], 'small');

      // Hover state: Should apply state defaults
      final hoverSelections = resolver.resolveSelections(
        definition,
        instance,
        InteractiveState.hover,
      );
      expect(hoverSelections['state'], 'hover');
      expect(hoverSelections['shadow'], 'large');
      expect(hoverSelections['size'], 'small');

      // Instance override collision
      final overriddenInstance = SymbolInstanceNode(
        id: NodeId('inst-2'),
        symbolDefinitionId: 'btn-def',
        variantSelections: {'state': 'custom_override', 'size': 'small'},
      );

      final pressedSelections = resolver.resolveSelections(
        definition,
        overriddenInstance,
        InteractiveState.pressed,
      );
      expect(pressedSelections['state'], 'custom_override'); // Instance wins
      expect(pressedSelections['shadow'], 'none'); // From pressed state map
      expect(pressedSelections['size'], 'small');
    });

    test('resolveContent returns evaluated content', () {
      final instance = SymbolInstanceNode(
        id: NodeId('inst-1'),
        symbolDefinitionId: 'btn-def',
        variantSelections: {'size': 'small'},
      );

      final content = resolver.resolveContent(
        definition,
        instance,
        InteractiveState.hover,
      );

      expect(content, isA<GroupNode>());
      // From mock: expected keys: shadow=large, size=small, state=hover
      expect(content.name, 'shadow=large, size=small, state=hover');
    });

    test('previewAllStates returns map of node content', () {
      final instance = SymbolInstanceNode(
        id: NodeId('inst-1'),
        symbolDefinitionId: 'btn-def',
        variantSelections: {'size': 'large'},
      );

      final preview = resolver.previewAllStates(definition, instance);
      expect(preview.length, 3);
      expect(
        preview.keys,
        containsAll([
          InteractiveState.hover,
          InteractiveState.pressed,
          InteractiveState.disabled,
        ]),
      );

      expect(
        preview[InteractiveState.hover]!.name,
        'shadow=large, size=large, state=hover',
      );
    });
  });
}
