import 'package:fluera_engine/src/core/scene_graph/node_id.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/history/command_history.dart';
import 'package:fluera_engine/src/systems/design_variables.dart';
import 'package:fluera_engine/src/systems/variable_binding.dart';
import 'package:fluera_engine/src/systems/variable_commands.dart';
import 'package:fluera_engine/src/systems/variable_resolver.dart';

void main() {
  // =========================================================================
  // SetVariableValueCommand
  // =========================================================================

  group('SetVariableValueCommand', () {
    test('execute sets value, undo restores old value', () {
      final v = DesignVariable(
        id: NodeId('opacity'),
        name: 'Opacity',
        type: DesignVariableType.number,
        values: {'default': 0.5},
      );

      final cmd = SetVariableValueCommand(
        variable: v,
        modeId: 'default',
        newValue: 1.0,
      );

      cmd.execute();
      expect(v.getValue('default'), 1.0);

      cmd.undo();
      expect(v.getValue('default'), 0.5);
    });

    test('undo removes value if it was previously null', () {
      final v = DesignVariable(
        id: NodeId('color'),
        name: 'Color',
        type: DesignVariableType.color,
      );

      final cmd = SetVariableValueCommand(
        variable: v,
        modeId: 'dark',
        newValue: 0xFF000000,
      );

      cmd.execute();
      expect(v.getValue('dark'), 0xFF000000);

      cmd.undo();
      expect(v.getValue('dark'), isNull);
    });

    test('redo re-applies the value', () {
      final v = DesignVariable(
        id: NodeId('v1'),
        name: 'V1',
        type: DesignVariableType.number,
        values: {'default': 10.0},
      );

      final cmd = SetVariableValueCommand(
        variable: v,
        modeId: 'default',
        newValue: 20.0,
      );

      cmd.execute();
      cmd.undo();
      cmd.redo();
      expect(v.getValue('default'), 20.0);
    });
  });

  // =========================================================================
  // SetActiveModeCommand
  // =========================================================================

  group('SetActiveModeCommand', () {
    test('execute switches mode, undo restores', () {
      final collection = VariableCollection(
        id: NodeId('themes'),
        name: 'Themes',
        modes: [
          VariableMode(id: NodeId('light'), name: 'Light'),
          VariableMode(id: NodeId('dark'), name: 'Dark'),
        ],
      );
      final resolver = VariableResolver(collections: [collection]);

      final cmd = SetActiveModeCommand(
        resolver: resolver,
        collectionId: 'themes',
        newModeId: 'dark',
      );

      cmd.execute();
      expect(resolver.getActiveMode('themes'), 'dark');

      cmd.undo();
      expect(resolver.getActiveMode('themes'), 'light');
    });
  });

  // =========================================================================
  // Add/Remove Variable Commands
  // =========================================================================

  group('AddVariableCommand', () {
    test('execute adds, undo removes', () {
      final collection = VariableCollection(id: NodeId('c1'), name: 'Test');
      final variable = DesignVariable(
        id: NodeId('v1'),
        name: 'V1',
        type: DesignVariableType.number,
      );

      final cmd = AddVariableCommand(
        collection: collection,
        variable: variable,
      );

      cmd.execute();
      expect(collection.variableCount, 1);
      expect(collection.findVariable('v1'), isNotNull);

      cmd.undo();
      expect(collection.variableCount, 0);
    });
  });

  group('RemoveVariableCommand', () {
    test('execute removes variable and bindings, undo restores both', () {
      final collection = VariableCollection(
        id: NodeId('c1'),
        name: 'Test',
        variables: [
          DesignVariable(
            id: NodeId('v1'),
            name: 'V1',
            type: DesignVariableType.number,
            values: {'default': 42.0},
          ),
        ],
      );
      final bindings = VariableBindingRegistry();
      bindings.addBinding(
        const VariableBinding(
          variableId: 'v1',
          nodeId: 'n1',
          nodeProperty: 'opacity',
        ),
      );
      bindings.addBinding(
        const VariableBinding(
          variableId: 'v1',
          nodeId: 'n2',
          nodeProperty: 'opacity',
        ),
      );

      final cmd = RemoveVariableCommand(
        collection: collection,
        variable: collection.findVariable('v1')!,
        bindingRegistry: bindings,
      );

      cmd.execute();
      expect(collection.variableCount, 0);
      expect(bindings.isVariableBound('v1'), isFalse);

      cmd.undo();
      expect(collection.variableCount, 1);
      expect(collection.findVariable('v1'), isNotNull);
      expect(bindings.bindingsForVariable('v1').length, 2);
    });
  });

  // =========================================================================
  // Binding Commands
  // =========================================================================

  group('AddBindingCommand', () {
    test('execute adds, undo removes', () {
      final registry = VariableBindingRegistry();
      const binding = VariableBinding(
        variableId: 'v1',
        nodeId: 'n1',
        nodeProperty: 'opacity',
      );

      final cmd = AddBindingCommand(registry: registry, binding: binding);

      cmd.execute();
      expect(registry.bindingCount, 1);

      cmd.undo();
      expect(registry.bindingCount, 0);
    });
  });

  group('RemoveBindingCommand', () {
    test('execute removes, undo re-adds', () {
      final registry = VariableBindingRegistry();
      const binding = VariableBinding(
        variableId: 'v1',
        nodeId: 'n1',
        nodeProperty: 'opacity',
      );
      registry.addBinding(binding);

      final cmd = RemoveBindingCommand(registry: registry, binding: binding);

      cmd.execute();
      expect(registry.bindingCount, 0);

      cmd.undo();
      expect(registry.bindingCount, 1);
    });
  });

  // =========================================================================
  // RenameVariableCommand
  // =========================================================================

  group('RenameVariableCommand', () {
    test('execute renames variable and bindings, undo restores', () {
      final collection = VariableCollection(
        id: NodeId('c1'),
        name: 'Test',
        variables: [
          DesignVariable(
            id: NodeId('old-id'),
            name: 'My Var',
            type: DesignVariableType.number,
            values: {'default': 10.0},
          ),
        ],
      );
      final bindings = VariableBindingRegistry();
      bindings.addBinding(
        const VariableBinding(
          variableId: 'old-id',
          nodeId: 'n1',
          nodeProperty: 'opacity',
        ),
      );

      final cmd = RenameVariableCommand(
        collection: collection,
        bindingRegistry: bindings,
        oldId: 'old-id',
        newId: 'new-id',
      );

      cmd.execute();
      expect(collection.findVariable('old-id'), isNull);
      expect(collection.findVariable('new-id'), isNotNull);
      expect(collection.findVariable('new-id')!.name, 'My Var');
      expect(bindings.isVariableBound('new-id'), isTrue);
      expect(bindings.isVariableBound('old-id'), isFalse);

      cmd.undo();
      expect(collection.findVariable('new-id'), isNull);
      expect(collection.findVariable('old-id'), isNotNull);
      expect(bindings.isVariableBound('old-id'), isTrue);
      expect(bindings.isVariableBound('new-id'), isFalse);
    });
  });

  // =========================================================================
  // CompositeCommand
  // =========================================================================

  group('CompositeCommand', () {
    test('execute runs all sub-commands in order', () {
      final collection = VariableCollection(id: NodeId('c1'), name: 'Test');
      final v1 = DesignVariable(
        id: NodeId('v1'),
        name: 'V1',
        type: DesignVariableType.number,
      );
      final v2 = DesignVariable(
        id: NodeId('v2'),
        name: 'V2',
        type: DesignVariableType.number,
      );

      final composite = CompositeCommand(
        label: 'Add two vars',
        commands: [
          AddVariableCommand(collection: collection, variable: v1),
          AddVariableCommand(collection: collection, variable: v2),
        ],
      );

      composite.execute();
      expect(collection.variableCount, 2);
    });

    test('undo reverses all sub-commands in reverse order', () {
      final collection = VariableCollection(id: NodeId('c1'), name: 'Test');
      final v1 = DesignVariable(
        id: NodeId('v1'),
        name: 'V1',
        type: DesignVariableType.number,
      );
      final v2 = DesignVariable(
        id: NodeId('v2'),
        name: 'V2',
        type: DesignVariableType.number,
      );

      final composite = CompositeCommand(
        label: 'Add two vars',
        commands: [
          AddVariableCommand(collection: collection, variable: v1),
          AddVariableCommand(collection: collection, variable: v2),
        ],
      );

      composite.execute();
      composite.undo();
      expect(collection.variableCount, 0);
    });

    test('redo re-applies all sub-commands', () {
      final collection = VariableCollection(id: NodeId('c1'), name: 'Test');
      final v1 = DesignVariable(
        id: NodeId('v1'),
        name: 'V1',
        type: DesignVariableType.number,
      );

      final composite = CompositeCommand(
        label: 'Add var',
        commands: [AddVariableCommand(collection: collection, variable: v1)],
      );

      composite.execute();
      composite.undo();
      composite.redo();
      expect(collection.variableCount, 1);
    });
  });

  // =========================================================================
  // Variable Locking
  // =========================================================================

  group('Variable locking (isLocked)', () {
    test('locked variable throws StateError on setValue', () {
      final v = DesignVariable(
        id: NodeId('v1'),
        name: 'V1',
        type: DesignVariableType.number,
        values: {'default': 1.0},
        isLocked: true,
      );

      expect(() => v.setValue('default', 2.0), throwsStateError);
      expect(v.getValue('default'), 1.0); // unchanged
    });

    test('unlocked variable allows setValue', () {
      final v = DesignVariable(
        id: NodeId('v1'),
        name: 'V1',
        type: DesignVariableType.number,
        values: {'default': 1.0},
      );

      v.setValue('default', 2.0);
      expect(v.getValue('default'), 2.0);
    });

    test('isLocked round-trips through serialization', () {
      final v = DesignVariable(
        id: NodeId('v1'),
        name: 'V1',
        type: DesignVariableType.number,
        isLocked: true,
      );

      final json = v.toJson();
      expect(json['isLocked'], true);

      final restored = DesignVariable.fromJson(json);
      expect(restored.isLocked, true);
    });

    test('isLocked defaults to false', () {
      final v = DesignVariable(
        id: NodeId('v1'),
        name: 'V1',
        type: DesignVariableType.number,
      );
      expect(v.isLocked, false);
    });

    test('unlock then edit works', () {
      final v = DesignVariable(
        id: NodeId('v1'),
        name: 'V1',
        type: DesignVariableType.number,
        values: {'default': 1.0},
        isLocked: true,
      );

      v.isLocked = false;
      v.setValue('default', 2.0);
      expect(v.getValue('default'), 2.0);
    });
  });
}
