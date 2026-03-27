import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/systems/component_state_machine.dart';

void main() {
  group('ComponentStateMachine Tests', () {
    test('registerStates and resolveState', () {
      final machine = ComponentStateMachine();

      machine.registerStates('btn-primary', {
        InteractiveState.hover: {'state': 'hover', 'brightness': 'light'},
        InteractiveState.pressed: {'state': 'pressed'},
        InteractiveState.disabled: {'state': 'disabled'},
      });

      expect(machine.hasStates('btn-primary'), isTrue);

      final hoverSelections = machine.resolveState(
        'btn-primary',
        InteractiveState.hover,
      );
      expect(hoverSelections, {'state': 'hover', 'brightness': 'light'});

      final pressedSelections = machine.resolveState(
        'btn-primary',
        InteractiveState.pressed,
      );
      expect(pressedSelections, {'state': 'pressed'});

      // Non-existent state should return empty map
      final focusSelections = machine.resolveState(
        'btn-primary',
        InteractiveState.focused,
      );
      expect(focusSelections, isEmpty);

      // Non-existent definition should return empty map
      final unknownSelections = machine.resolveState(
        'unknown',
        InteractiveState.hover,
      );
      expect(unknownSelections, isEmpty);

      final available = machine.availableStates('btn-primary');
      expect(
        available,
        containsAll([
          InteractiveState.hover,
          InteractiveState.pressed,
          InteractiveState.disabled,
        ]),
      );
    });

    test('unregister removes state config', () {
      final machine = ComponentStateMachine();
      machine.registerStates('btn-primary', {
        InteractiveState.hover: {'state': 'hover'},
      });

      expect(machine.hasStates('btn-primary'), isTrue);

      final removed = machine.unregister('btn-primary');
      expect(removed, isTrue);
      expect(machine.hasStates('btn-primary'), isFalse);
    });

    test('serialization roundtrip', () {
      final machine = ComponentStateMachine();
      machine.registerStates('checkbox', {
        InteractiveState.hover: {'state': 'hover'},
        InteractiveState.focused: {'focus': 'true'},
      });

      final config = machine.configFor('checkbox');
      expect(config, isNotNull);

      final json = config!.toJson();
      expect(json['definitionId'], 'checkbox');
      expect(json['stateSelections'], contains('hover'));
      expect(json['stateSelections'], contains('focused'));

      final restoredConfig = ComponentStateConfig.fromJson(json);
      expect(restoredConfig.definitionId, 'checkbox');
      expect(
        restoredConfig.stateSelections.keys,
        containsAll([InteractiveState.hover, InteractiveState.focused]),
      );
      expect(restoredConfig.stateSelections[InteractiveState.hover], {
        'state': 'hover',
      });
    });
  });
}
