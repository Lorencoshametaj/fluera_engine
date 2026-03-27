import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/fluera_engine.dart';

void main() {
  // ===========================================================================
  // Helpers
  // ===========================================================================

  GroupNode _emptyGroup() => GroupNode(id: NodeId('empty-group'));
  GroupNode _namedGroup(String name) =>
      GroupNode(id: NodeId('group-$name'), name: name);

  SymbolDefinition _buildButtonDef() {
    final def = SymbolDefinition(
      id: NodeId('btn'),
      name: 'Button',
      content: _namedGroup('base'),
      variantProperties: [
        VariantProperty.variant(
          name: 'Size',
          options: ['small', 'large'],
          defaultValue: 'small',
        ),
        VariantProperty.variant(
          name: 'State',
          options: ['default', 'hover'],
          defaultValue: 'default',
        ),
      ],
    );
    def.setVariant({
      'Size': 'small',
      'State': 'default',
    }, _namedGroup('small-default'));
    def.setVariant({
      'Size': 'small',
      'State': 'hover',
    }, _namedGroup('small-hover'));
    def.setVariant({
      'Size': 'large',
      'State': 'default',
    }, _namedGroup('large-default'));
    def.setVariant({
      'Size': 'large',
      'State': 'hover',
    }, _namedGroup('large-hover'));
    return def;
  }

  // ===========================================================================
  // API Surface: Each command — execute + undo + redo
  // ===========================================================================

  group('AddVariantPropertyCommand', () {
    test('execute adds property', () {
      final def = SymbolDefinition(id: NodeId('x'), name: 'X', content: _emptyGroup());
      final prop = VariantProperty.variant(
        name: 'Color',
        options: ['red', 'blue'],
      );
      final cmd = AddVariantPropertyCommand(definition: def, property: prop);
      cmd.execute();
      expect(def.variantProperties.length, 1);
      expect(def.variantProperties.first.name, 'Color');
    });

    test('undo removes property', () {
      final def = SymbolDefinition(id: NodeId('x'), name: 'X', content: _emptyGroup());
      final prop = VariantProperty.variant(
        name: 'Color',
        options: ['red', 'blue'],
      );
      final cmd = AddVariantPropertyCommand(definition: def, property: prop);
      cmd.execute();
      cmd.undo();
      expect(def.variantProperties, isEmpty);
    });

    test('redo re-adds property', () {
      final def = SymbolDefinition(id: NodeId('x'), name: 'X', content: _emptyGroup());
      final prop = VariantProperty.variant(
        name: 'Color',
        options: ['red', 'blue'],
      );
      final cmd = AddVariantPropertyCommand(definition: def, property: prop);
      cmd.execute();
      cmd.undo();
      cmd.redo();
      expect(def.variantProperties.length, 1);
    });
  });

  group('RemoveVariantPropertyCommand', () {
    test('execute removes property and related variants', () {
      final def = _buildButtonDef();
      final stateProp = def.variantProperties.firstWhere(
        (p) => p.name == 'State',
      );
      final cmd = RemoveVariantPropertyCommand(
        definition: def,
        propertyId: stateProp.id,
      );
      cmd.execute();
      expect(def.variantProperties.length, 1);
      expect(def.variants, isEmpty);
    });

    test('undo restores property and variants', () {
      final def = _buildButtonDef();
      final stateProp = def.variantProperties.firstWhere(
        (p) => p.name == 'State',
      );
      final cmd = RemoveVariantPropertyCommand(
        definition: def,
        propertyId: stateProp.id,
      );
      cmd.execute();
      cmd.undo();
      expect(def.variantProperties.length, 2);
      expect(def.variants.length, 4);
    });

    test('redo re-removes', () {
      final def = _buildButtonDef();
      final stateProp = def.variantProperties.firstWhere(
        (p) => p.name == 'State',
      );
      final cmd = RemoveVariantPropertyCommand(
        definition: def,
        propertyId: stateProp.id,
      );
      cmd.execute();
      cmd.undo();
      cmd.redo();
      expect(def.variantProperties.length, 1);
    });
  });

  group('RenameVariantAxisCommand', () {
    test('execute renames axis and rebuilds keys', () {
      final def = _buildButtonDef();
      final sizeProp = def.variantProperties.firstWhere(
        (p) => p.name == 'Size',
      );
      final cmd = RenameVariantAxisCommand(
        definition: def,
        propertyId: sizeProp.id,
        newName: 'Dimension',
      );
      cmd.execute();
      expect(sizeProp.name, 'Dimension');
      expect(def.variants.keys.any((k) => k.contains('Dimension=')), true);
    });

    test('undo restores original name', () {
      final def = _buildButtonDef();
      final sizeProp = def.variantProperties.firstWhere(
        (p) => p.name == 'Size',
      );
      final cmd = RenameVariantAxisCommand(
        definition: def,
        propertyId: sizeProp.id,
        newName: 'Dimension',
      );
      cmd.execute();
      cmd.undo();
      expect(sizeProp.name, 'Size');
      expect(def.variants.keys.any((k) => k.contains('Size=')), true);
    });

    test('redo re-renames', () {
      final def = _buildButtonDef();
      final sizeProp = def.variantProperties.firstWhere(
        (p) => p.name == 'Size',
      );
      final cmd = RenameVariantAxisCommand(
        definition: def,
        propertyId: sizeProp.id,
        newName: 'Dimension',
      );
      cmd.execute();
      cmd.undo();
      cmd.redo();
      expect(sizeProp.name, 'Dimension');
    });
  });

  group('RenameVariantOptionCommand', () {
    test('execute renames option and rebuilds keys', () {
      final def = _buildButtonDef();
      final sizeProp = def.variantProperties.firstWhere(
        (p) => p.name == 'Size',
      );
      final cmd = RenameVariantOptionCommand(
        definition: def,
        propertyId: sizeProp.id,
        oldValue: 'small',
        newValue: 'tiny',
      );
      cmd.execute();
      expect(sizeProp.options.contains('tiny'), true);
      expect(sizeProp.options.contains('small'), false);
    });

    test('undo restores original option', () {
      final def = _buildButtonDef();
      final sizeProp = def.variantProperties.firstWhere(
        (p) => p.name == 'Size',
      );
      final cmd = RenameVariantOptionCommand(
        definition: def,
        propertyId: sizeProp.id,
        oldValue: 'small',
        newValue: 'tiny',
      );
      cmd.execute();
      cmd.undo();
      expect(sizeProp.options.contains('small'), true);
      expect(sizeProp.options.contains('tiny'), false);
    });

    test('redo re-renames option', () {
      final def = _buildButtonDef();
      final sizeProp = def.variantProperties.firstWhere(
        (p) => p.name == 'Size',
      );
      final cmd = RenameVariantOptionCommand(
        definition: def,
        propertyId: sizeProp.id,
        oldValue: 'small',
        newValue: 'tiny',
      );
      cmd.execute();
      cmd.undo();
      cmd.redo();
      expect(sizeProp.options.contains('tiny'), true);
    });
  });

  group('ReorderVariantPropertyCommand', () {
    test('execute moves property to new index', () {
      final def = _buildButtonDef();
      final sizeProp = def.variantProperties.firstWhere(
        (p) => p.name == 'Size',
      );
      expect(def.variantProperties[0].name, 'Size');

      final cmd = ReorderVariantPropertyCommand(
        definition: def,
        propertyId: sizeProp.id,
        newIndex: 1,
      );
      cmd.execute();
      expect(def.variantProperties[1].name, 'Size');
    });

    test('undo moves property back', () {
      final def = _buildButtonDef();
      final sizeProp = def.variantProperties.firstWhere(
        (p) => p.name == 'Size',
      );
      final cmd = ReorderVariantPropertyCommand(
        definition: def,
        propertyId: sizeProp.id,
        newIndex: 1,
      );
      cmd.execute();
      cmd.undo();
      expect(def.variantProperties[0].name, 'Size');
    });
  });

  group('AddVariantOptionCommand', () {
    test('execute adds option', () {
      final def = _buildButtonDef();
      final sizeProp = def.variantProperties.firstWhere(
        (p) => p.name == 'Size',
      );
      final cmd = AddVariantOptionCommand(
        definition: def,
        propertyId: sizeProp.id,
        value: 'medium',
      );
      cmd.execute();
      expect(sizeProp.options, contains('medium'));
    });

    test('undo removes option', () {
      final def = _buildButtonDef();
      final sizeProp = def.variantProperties.firstWhere(
        (p) => p.name == 'Size',
      );
      final cmd = AddVariantOptionCommand(
        definition: def,
        propertyId: sizeProp.id,
        value: 'medium',
      );
      cmd.execute();
      cmd.undo();
      expect(sizeProp.options, isNot(contains('medium')));
    });
  });

  group('RemoveVariantOptionCommand', () {
    test('execute removes option', () {
      final def = _buildButtonDef();
      final sizeProp = def.variantProperties.firstWhere(
        (p) => p.name == 'Size',
      );
      final cmd = RemoveVariantOptionCommand(
        definition: def,
        propertyId: sizeProp.id,
        value: 'large',
      );
      cmd.execute();
      expect(sizeProp.options, isNot(contains('large')));
    });

    test('undo restores option at original index', () {
      final def = _buildButtonDef();
      final sizeProp = def.variantProperties.firstWhere(
        (p) => p.name == 'Size',
      );
      final cmd = RemoveVariantOptionCommand(
        definition: def,
        propertyId: sizeProp.id,
        value: 'large',
      );
      cmd.execute();
      cmd.undo();
      expect(sizeProp.options, contains('large'));
      // 'large' was at index 1, should be restored there.
      expect(sizeProp.options.indexOf('large'), 1);
    });
  });

  group('SetVariantContentCommand', () {
    test('execute sets new content', () {
      final def = _buildButtonDef();
      final newContent = _namedGroup('replaced');
      final cmd = SetVariantContentCommand(
        definition: def,
        propertyValues: {'Size': 'small', 'State': 'default'},
        content: newContent,
      );
      cmd.execute();
      final resolved = def.resolveContent({
        'Size': 'small',
        'State': 'default',
      });
      expect(resolved.name, 'replaced');
    });

    test('undo restores old content', () {
      final def = _buildButtonDef();
      final cmd = SetVariantContentCommand(
        definition: def,
        propertyValues: {'Size': 'small', 'State': 'default'},
        content: _namedGroup('replaced'),
      );
      cmd.execute();
      cmd.undo();
      final resolved = def.resolveContent({
        'Size': 'small',
        'State': 'default',
      });
      expect(resolved.name, 'small-default');
    });

    test('undo removes entry when it was new', () {
      final def = _buildButtonDef();
      // 3-axis scenario: add a property first to create missing combos.
      final prop = VariantProperty.variant(
        name: 'Theme',
        options: ['light', 'dark'],
      );
      def.addVariantProperty(prop);

      final cmd = SetVariantContentCommand(
        definition: def,
        propertyValues: {'Size': 'small', 'State': 'default', 'Theme': 'dark'},
        content: _namedGroup('new-entry'),
      );
      cmd.execute();
      cmd.undo();
      final key = VariantContent.buildVariantKey({
        'Size': 'small',
        'State': 'default',
        'Theme': 'dark',
      });
      expect(def.variants.containsKey(key), false);
    });
  });

  group('RemoveVariantContentCommand', () {
    test('execute removes content', () {
      final def = _buildButtonDef();
      final key = VariantContent.buildVariantKey({
        'Size': 'small',
        'State': 'default',
      });
      final cmd = RemoveVariantContentCommand(definition: def, variantKey: key);
      cmd.execute();
      expect(def.variants.containsKey(key), false);
    });

    test('undo restores content', () {
      final def = _buildButtonDef();
      final key = VariantContent.buildVariantKey({
        'Size': 'small',
        'State': 'default',
      });
      final cmd = RemoveVariantContentCommand(definition: def, variantKey: key);
      cmd.execute();
      cmd.undo();
      expect(def.variants.containsKey(key), true);
      expect(def.variants[key]!.content.name, 'small-default');
    });
  });

  group('SetVariantSelectionCommand', () {
    test('execute sets selection', () {
      final instance = SymbolInstanceNode(id: NodeId('i1'), symbolDefinitionId: 'btn');
      final cmd = SetVariantSelectionCommand(
        instance: instance,
        propertyName: 'Size',
        newValue: 'large',
      );
      cmd.execute();
      expect(instance.variantSelections['Size'], 'large');
    });

    test('undo removes new selection', () {
      final instance = SymbolInstanceNode(id: NodeId('i1'), symbolDefinitionId: 'btn');
      final cmd = SetVariantSelectionCommand(
        instance: instance,
        propertyName: 'Size',
        newValue: 'large',
      );
      cmd.execute();
      cmd.undo();
      expect(instance.variantSelections.containsKey('Size'), false);
    });

    test('undo restores old selection', () {
      final instance = SymbolInstanceNode(
        id: NodeId('i1'),
        symbolDefinitionId: 'btn',
        variantSelections: {'Size': 'small'},
      );
      final cmd = SetVariantSelectionCommand(
        instance: instance,
        propertyName: 'Size',
        newValue: 'large',
      );
      cmd.execute();
      cmd.undo();
      expect(instance.variantSelections['Size'], 'small');
    });

    test('merge coalescing works', () {
      final instance = SymbolInstanceNode(id: NodeId('i1'), symbolDefinitionId: 'btn');
      final cmd1 = SetVariantSelectionCommand(
        instance: instance,
        propertyName: 'Size',
        newValue: 'medium',
      );
      final cmd2 = SetVariantSelectionCommand(
        instance: instance,
        propertyName: 'Size',
        newValue: 'large',
      );
      expect(cmd1.canMergeWith(cmd2), true);
      cmd1.mergeWith(cmd2);
      expect(cmd1.newValue, 'large');
    });

    test('merge rejects different properties', () {
      final instance = SymbolInstanceNode(id: NodeId('i1'), symbolDefinitionId: 'btn');
      final cmd1 = SetVariantSelectionCommand(
        instance: instance,
        propertyName: 'Size',
        newValue: 'large',
      );
      final cmd2 = SetVariantSelectionCommand(
        instance: instance,
        propertyName: 'State',
        newValue: 'hover',
      );
      expect(cmd1.canMergeWith(cmd2), false);
    });
  });

  group('SetInstanceOverrideCommand', () {
    test('execute sets override', () {
      final instance = SymbolInstanceNode(id: NodeId('i1'), symbolDefinitionId: 'btn');
      final cmd = SetInstanceOverrideCommand(
        instance: instance,
        key: 'color',
        newValue: '#FF0000',
      );
      cmd.execute();
      expect(instance.overrides['color'], '#FF0000');
    });

    test('undo removes new override', () {
      final instance = SymbolInstanceNode(id: NodeId('i1'), symbolDefinitionId: 'btn');
      final cmd = SetInstanceOverrideCommand(
        instance: instance,
        key: 'color',
        newValue: '#FF0000',
      );
      cmd.execute();
      cmd.undo();
      expect(instance.overrides.containsKey('color'), false);
    });

    test('undo restores old override', () {
      final instance = SymbolInstanceNode(
        id: NodeId('i1'),
        symbolDefinitionId: 'btn',
        overrides: {'color': '#00FF00'},
      );
      final cmd = SetInstanceOverrideCommand(
        instance: instance,
        key: 'color',
        newValue: '#FF0000',
      );
      cmd.execute();
      cmd.undo();
      expect(instance.overrides['color'], '#00FF00');
    });
  });

  // ===========================================================================
  // Integration: Transaction recipes
  // ===========================================================================

  group('VariantTransactions.renameAxis', () {
    test('atomic rename + undo', () {
      final def = _buildButtonDef();
      final sizeProp = def.variantProperties.firstWhere(
        (p) => p.name == 'Size',
      );
      final composite = VariantTransactions.renameAxis(
        def: def,
        propertyId: sizeProp.id,
        newName: 'Dimension',
      );

      // Already executed by transaction.
      expect(sizeProp.name, 'Dimension');
      expect(def.variants.length, 4);

      // Undo entire transaction.
      composite.undo();
      expect(sizeProp.name, 'Size');
      expect(def.variants.length, 4);

      // Redo.
      composite.redo();
      expect(sizeProp.name, 'Dimension');
    });
  });

  group('VariantTransactions.removeProperty', () {
    test('atomic remove + undo', () {
      final def = _buildButtonDef();
      final stateProp = def.variantProperties.firstWhere(
        (p) => p.name == 'State',
      );
      final composite = VariantTransactions.removeProperty(
        def: def,
        propertyId: stateProp.id,
      );

      expect(def.variantProperties.length, 1);
      expect(def.variants, isEmpty);

      composite.undo();
      expect(def.variantProperties.length, 2);
      expect(def.variants.length, 4);
    });
  });

  group('VariantTransactions.duplicateDefinition', () {
    test('atomic duplicate + undo', () {
      final def = _buildButtonDef();
      final registry = SymbolRegistry()..register(def);
      final composite = VariantTransactions.duplicateDefinition(
        source: def,
        registry: registry,
        newId: 'btn-copy',
        newName: 'Button Copy',
      );

      expect(registry.lookup('btn-copy'), isNotNull);
      expect(registry.lookup('btn-copy')!.name, 'Button Copy');
      expect(registry.lookup('btn-copy')!.variants.length, 4);

      composite.undo();
      expect(registry.lookup('btn-copy'), isNull);

      composite.redo();
      expect(registry.lookup('btn-copy'), isNotNull);
    });
  });

  group('VariantTransactions.fillMissingVariants', () {
    test('fills missing matrix entries atomically', () {
      final def = SymbolDefinition(
        id: NodeId('x'),
        name: 'X',
        content: _emptyGroup(),
        variantProperties: [
          VariantProperty.variant(name: 'Size', options: ['small', 'large']),
          VariantProperty.variant(name: 'State', options: ['default', 'hover']),
        ],
      );
      // No variants set yet → 4 missing.
      expect(def.missingVariantKeys.length, 4);

      final composite = VariantTransactions.fillMissingVariants(
        def: def,
        contentFactory: (pv) => _namedGroup('${pv['Size']}-${pv['State']}'),
      );

      expect(def.missingVariantKeys, isEmpty);
      expect(def.variants.length, 4);

      // Undo removes all 4.
      composite!.undo();
      expect(def.variants, isEmpty);
    });
  });

  // ===========================================================================
  // Edge Cases
  // ===========================================================================

  group('CommandTransaction edge cases', () {
    test('rollback reverses all commands', () {
      final def = SymbolDefinition(id: NodeId('x'), name: 'X', content: _emptyGroup());
      final txn = CommandTransaction(label: 'Test rollback');
      txn.add(
        AddVariantPropertyCommand(
          definition: def,
          property: VariantProperty.variant(name: 'A', options: ['1', '2']),
        ),
      );
      txn.add(
        AddVariantPropertyCommand(
          definition: def,
          property: VariantProperty.variant(name: 'B', options: ['x', 'y']),
        ),
      );
      expect(def.variantProperties.length, 2);

      txn.rollback();
      expect(def.variantProperties, isEmpty);
    });

    test('double commit throws', () {
      final txn = CommandTransaction(label: 'Test');
      txn.commit();
      expect(() => txn.commit(), throwsStateError);
    });

    test('add after commit throws', () {
      final txn = CommandTransaction(label: 'Test');
      txn.commit();
      expect(
        () => txn.add(
          AddVariantPropertyCommand(
            definition: SymbolDefinition(
              id: NodeId('x'),
              name: 'X',
              content: _emptyGroup(),
            ),
            property: VariantProperty.variant(name: 'A', options: ['1']),
          ),
        ),
        throwsStateError,
      );
    });

    test('empty transaction produces empty composite', () {
      final txn = CommandTransaction(label: 'Empty');
      final composite = txn.commit();
      composite.execute(); // no-op
      composite.undo(); // no-op
    });
  });

  // ===========================================================================
  // CommandHistory roundtrip
  // ===========================================================================

  group('CommandHistory roundtrip', () {
    test('execute → undo → redo via CommandHistory', () {
      final history = CommandHistory();
      final def = _buildButtonDef();
      final sizeProp = def.variantProperties.firstWhere(
        (p) => p.name == 'Size',
      );

      history.execute(
        RenameVariantAxisCommand(
          definition: def,
          propertyId: sizeProp.id,
          newName: 'Dimension',
        ),
      );
      expect(sizeProp.name, 'Dimension');
      expect(history.canUndo, true);

      history.undo();
      expect(sizeProp.name, 'Size');
      expect(history.canRedo, true);

      history.redo();
      expect(sizeProp.name, 'Dimension');
    });

    test('transaction composite via pushWithoutExecute', () {
      final history = CommandHistory();
      final def = _buildButtonDef();
      final sizeProp = def.variantProperties.firstWhere(
        (p) => p.name == 'Size',
      );

      final composite = VariantTransactions.renameAxis(
        def: def,
        propertyId: sizeProp.id,
        newName: 'Dim',
      );
      history.pushWithoutExecute(composite);

      expect(sizeProp.name, 'Dim');
      expect(history.undoLabel, 'Rename axis → "Dim"');

      history.undo();
      expect(sizeProp.name, 'Size');

      history.redo();
      expect(sizeProp.name, 'Dim');
    });

    test('merge coalescing in CommandHistory', () {
      final history = CommandHistory();
      final instance = SymbolInstanceNode(id: NodeId('i1'), symbolDefinitionId: 'btn');

      history.execute(
        SetVariantSelectionCommand(
          instance: instance,
          propertyName: 'Size',
          newValue: 'small',
        ),
      );
      history.execute(
        SetVariantSelectionCommand(
          instance: instance,
          propertyName: 'Size',
          newValue: 'medium',
        ),
      );
      history.execute(
        SetVariantSelectionCommand(
          instance: instance,
          propertyName: 'Size',
          newValue: 'large',
        ),
      );

      // All three should merge into one undo entry.
      expect(history.undoCount, 1);
      expect(instance.variantSelections['Size'], 'large');

      history.undo();
      // Should go back to no selection.
      expect(instance.variantSelections.containsKey('Size'), false);
    });

    test('clear removes all history', () {
      final history = CommandHistory();
      final def = _buildButtonDef();
      final sizeProp = def.variantProperties.firstWhere(
        (p) => p.name == 'Size',
      );

      history.execute(
        RenameVariantAxisCommand(
          definition: def,
          propertyId: sizeProp.id,
          newName: 'Dim',
        ),
      );
      history.clear();
      expect(history.canUndo, false);
      expect(history.canRedo, false);
    });
  });

  // ===========================================================================
  // Enterprise Gaps: New tests
  // ===========================================================================

  group('RemoveVariantOptionCommand (enterprise)', () {
    test('cascades orphaned variant entries (Gap 1)', () {
      final def = _buildButtonDef();
      final sizeProp = def.variantProperties.firstWhere(
        (p) => p.name == 'Size',
      );
      expect(def.variants.length, 4);

      final cmd = RemoveVariantOptionCommand(
        definition: def,
        propertyId: sizeProp.id,
        value: 'large',
      );
      cmd.execute();
      // Only 'small' variants remain.
      expect(def.variants.length, 2);
      expect(
        def.variants.values.every((v) => v.propertyValues['Size'] == 'small'),
        true,
      );
    });

    test('undo restores orphaned variants (Gap 1)', () {
      final def = _buildButtonDef();
      final sizeProp = def.variantProperties.firstWhere(
        (p) => p.name == 'Size',
      );
      final cmd = RemoveVariantOptionCommand(
        definition: def,
        propertyId: sizeProp.id,
        value: 'large',
      );
      cmd.execute();
      cmd.undo();
      expect(def.variants.length, 4);
    });

    test('restores default value when it was the removed option (Gap 2)', () {
      final def = _buildButtonDef();
      final sizeProp = def.variantProperties.firstWhere(
        (p) => p.name == 'Size',
      );
      // Default is 'small'. Remove it.
      final cmd = RemoveVariantOptionCommand(
        definition: def,
        propertyId: sizeProp.id,
        value: 'small',
      );
      cmd.execute();
      // After undo, default should be restored to 'small'.
      cmd.undo();
      expect(sizeProp.defaultValue, 'small');
    });

    test('redo re-removes and re-cascades', () {
      final def = _buildButtonDef();
      final sizeProp = def.variantProperties.firstWhere(
        (p) => p.name == 'Size',
      );
      final cmd = RemoveVariantOptionCommand(
        definition: def,
        propertyId: sizeProp.id,
        value: 'large',
      );
      cmd.execute();
      cmd.undo();
      cmd.redo();
      expect(def.variants.length, 2);
    });
  });

  group('RemoveInstanceOverrideCommand (Gap 3)', () {
    test('execute removes override', () {
      final instance = SymbolInstanceNode(
        id: NodeId('i1'),
        symbolDefinitionId: 'btn',
        overrides: {'color': '#FF0000'},
      );
      final cmd = RemoveInstanceOverrideCommand(
        instance: instance,
        key: 'color',
      );
      cmd.execute();
      expect(instance.overrides.containsKey('color'), false);
    });

    test('undo restores override', () {
      final instance = SymbolInstanceNode(
        id: NodeId('i1'),
        symbolDefinitionId: 'btn',
        overrides: {'color': '#FF0000'},
      );
      final cmd = RemoveInstanceOverrideCommand(
        instance: instance,
        key: 'color',
      );
      cmd.execute();
      cmd.undo();
      expect(instance.overrides['color'], '#FF0000');
    });

    test('redo re-removes override', () {
      final instance = SymbolInstanceNode(
        id: NodeId('i1'),
        symbolDefinitionId: 'btn',
        overrides: {'color': '#FF0000'},
      );
      final cmd = RemoveInstanceOverrideCommand(
        instance: instance,
        key: 'color',
      );
      cmd.execute();
      cmd.undo();
      cmd.redo();
      expect(instance.overrides.containsKey('color'), false);
    });
  });

  group('ClearVariantSelectionsCommand (Gap 4)', () {
    test('execute clears all selections', () {
      final instance = SymbolInstanceNode(
        id: NodeId('i1'),
        symbolDefinitionId: 'btn',
        variantSelections: {'Size': 'large', 'State': 'hover'},
      );
      final cmd = ClearVariantSelectionsCommand(instance: instance);
      cmd.execute();
      expect(instance.variantSelections, isEmpty);
    });

    test('undo restores all selections', () {
      final instance = SymbolInstanceNode(
        id: NodeId('i1'),
        symbolDefinitionId: 'btn',
        variantSelections: {'Size': 'large', 'State': 'hover'},
      );
      final cmd = ClearVariantSelectionsCommand(instance: instance);
      cmd.execute();
      cmd.undo();
      expect(instance.variantSelections['Size'], 'large');
      expect(instance.variantSelections['State'], 'hover');
    });

    test('redo re-clears', () {
      final instance = SymbolInstanceNode(
        id: NodeId('i1'),
        symbolDefinitionId: 'btn',
        variantSelections: {'Size': 'large', 'State': 'hover'},
      );
      final cmd = ClearVariantSelectionsCommand(instance: instance);
      cmd.execute();
      cmd.undo();
      cmd.redo();
      expect(instance.variantSelections, isEmpty);
    });
  });

  group('VariantTransactions.renameOptionAcrossInstances (Gap 5)', () {
    test('propagates rename to instances', () {
      final def = _buildButtonDef();
      final sizeProp = def.variantProperties.firstWhere(
        (p) => p.name == 'Size',
      );
      final i1 = SymbolInstanceNode(
        id: NodeId('i1'),
        symbolDefinitionId: 'btn',
        variantSelections: {'Size': 'small'},
      );
      final i2 = SymbolInstanceNode(
        id: NodeId('i2'),
        symbolDefinitionId: 'btn',
        variantSelections: {'Size': 'large'},
      );

      final composite = VariantTransactions.renameOptionAcrossInstances(
        def: def,
        propertyId: sizeProp.id,
        oldValue: 'small',
        newValue: 'tiny',
        instances: [i1, i2],
      );

      expect(sizeProp.options.contains('tiny'), true);
      expect(i1.variantSelections['Size'], 'tiny');
      expect(i2.variantSelections['Size'], 'large'); // unaffected

      composite.undo();
      expect(sizeProp.options.contains('small'), true);
      expect(i1.variantSelections['Size'], 'small');
    });
  });

  group('VariantTransactions.removeOptionAcrossInstances (Gap 6)', () {
    test('sanitizes instances selecting deleted value', () {
      final def = _buildButtonDef();
      final sizeProp = def.variantProperties.firstWhere(
        (p) => p.name == 'Size',
      );
      final i1 = SymbolInstanceNode(
        id: NodeId('i1'),
        symbolDefinitionId: 'btn',
        variantSelections: {'Size': 'large'},
      );
      final i2 = SymbolInstanceNode(
        id: NodeId('i2'),
        symbolDefinitionId: 'btn',
        variantSelections: {'Size': 'small'},
      );

      final composite = VariantTransactions.removeOptionAcrossInstances(
        def: def,
        propertyId: sizeProp.id,
        value: 'large',
        instances: [i1, i2],
      );

      expect(sizeProp.options.contains('large'), false);
      expect(i1.variantSelections['Size'], 'small'); // sanitized to fallback
      expect(i2.variantSelections['Size'], 'small'); // unaffected

      composite.undo();
      expect(sizeProp.options.contains('large'), true);
      expect(i1.variantSelections['Size'], 'large'); // restored
    });
  });

  group('SetVariantSelectionCommand label (Gap 7)', () {
    test('label updates after merge', () {
      final instance = SymbolInstanceNode(id: NodeId('i1'), symbolDefinitionId: 'btn');
      final cmd = SetVariantSelectionCommand(
        instance: instance,
        propertyName: 'Size',
        newValue: 'small',
      );
      expect(cmd.label, contains('small'));

      cmd.mergeWith(
        SetVariantSelectionCommand(
          instance: instance,
          propertyName: 'Size',
          newValue: 'large',
        ),
      );
      expect(cmd.label, contains('large'));
      expect(cmd.label, isNot(contains('small')));
    });
  });

  group('SetVariantContent redo', () {
    test('redo re-sets content', () {
      final def = _buildButtonDef();
      final cmd = SetVariantContentCommand(
        definition: def,
        propertyValues: {'Size': 'small', 'State': 'default'},
        content: _namedGroup('replaced'),
      );
      cmd.execute();
      cmd.undo();
      cmd.redo();
      final resolved = def.resolveContent({
        'Size': 'small',
        'State': 'default',
      });
      expect(resolved.name, 'replaced');
    });
  });

  group('RemoveVariantContent redo', () {
    test('redo re-removes content', () {
      final def = _buildButtonDef();
      final key = VariantContent.buildVariantKey({
        'Size': 'small',
        'State': 'default',
      });
      final cmd = RemoveVariantContentCommand(definition: def, variantKey: key);
      cmd.execute();
      cmd.undo();
      cmd.redo();
      expect(def.variants.containsKey(key), false);
    });
  });

  group('AddVariantOption redo', () {
    test('redo re-adds option', () {
      final def = _buildButtonDef();
      final sizeProp = def.variantProperties.firstWhere(
        (p) => p.name == 'Size',
      );
      final cmd = AddVariantOptionCommand(
        definition: def,
        propertyId: sizeProp.id,
        value: 'medium',
      );
      cmd.execute();
      cmd.undo();
      cmd.redo();
      expect(sizeProp.options, contains('medium'));
    });
  });

  group('ReorderVariantProperty redo', () {
    test('redo re-reorders', () {
      final def = _buildButtonDef();
      final sizeProp = def.variantProperties.firstWhere(
        (p) => p.name == 'Size',
      );
      final cmd = ReorderVariantPropertyCommand(
        definition: def,
        propertyId: sizeProp.id,
        newIndex: 1,
      );
      cmd.execute();
      cmd.undo();
      cmd.redo();
      expect(def.variantProperties[1].name, 'Size');
    });
  });

  group('SetInstanceOverride redo', () {
    test('redo re-sets override', () {
      final instance = SymbolInstanceNode(id: NodeId('i1'), symbolDefinitionId: 'btn');
      final cmd = SetInstanceOverrideCommand(
        instance: instance,
        key: 'color',
        newValue: '#FF0000',
      );
      cmd.execute();
      cmd.undo();
      cmd.redo();
      expect(instance.overrides['color'], '#FF0000');
    });
  });

  // ===========================================================================
  // Top-Tier Enterprise Tests (v2)
  // ===========================================================================

  group('modifiedAt fidelity', () {
    test('undo restores modifiedAt on AddVariantPropertyCommand', () {
      final def = _buildButtonDef();
      final originalModifiedAt = def.modifiedAt;
      final prop = VariantProperty.variant(
        name: 'Color',
        options: ['red', 'blue'],
        defaultValue: 'red',
      );
      final cmd = AddVariantPropertyCommand(definition: def, property: prop);
      cmd.execute();
      expect(def.modifiedAt, isNot(equals(originalModifiedAt)));
      cmd.undo();
      expect(def.modifiedAt, equals(originalModifiedAt));
    });

    test('undo restores modifiedAt on RenameVariantAxisCommand', () {
      final def = _buildButtonDef();
      final originalModifiedAt = def.modifiedAt;
      final sizeProp = def.variantProperties.firstWhere(
        (p) => p.name == 'Size',
      );
      final cmd = RenameVariantAxisCommand(
        definition: def,
        propertyId: sizeProp.id,
        newName: 'Dimension',
      );
      cmd.execute();
      cmd.undo();
      expect(def.modifiedAt, equals(originalModifiedAt));
    });

    test('undo restores modifiedAt on RemoveVariantOptionCommand', () {
      final def = _buildButtonDef();
      final originalModifiedAt = def.modifiedAt;
      final sizeProp = def.variantProperties.firstWhere(
        (p) => p.name == 'Size',
      );
      final cmd = RemoveVariantOptionCommand(
        definition: def,
        propertyId: sizeProp.id,
        value: 'large',
      );
      cmd.execute();
      cmd.undo();
      expect(def.modifiedAt, equals(originalModifiedAt));
    });

    test('undo restores modifiedAt on SetVariantContentCommand', () {
      final def = _buildButtonDef();
      final originalModifiedAt = def.modifiedAt;
      final cmd = SetVariantContentCommand(
        definition: def,
        propertyValues: {'Size': 'small', 'State': 'default'},
        content: _namedGroup('replaced'),
      );
      cmd.execute();
      cmd.undo();
      expect(def.modifiedAt, equals(originalModifiedAt));
    });
  });

  group('SetInstanceOverrideCommand merge coalescing', () {
    test('coalesces rapid changes on same key', () {
      final history = CommandHistory();
      final instance = SymbolInstanceNode(id: NodeId('i1'), symbolDefinitionId: 'btn');
      history.execute(
        SetInstanceOverrideCommand(
          instance: instance,
          key: 'color',
          newValue: '#FF0000',
        ),
      );
      history.execute(
        SetInstanceOverrideCommand(
          instance: instance,
          key: 'color',
          newValue: '#00FF00',
        ),
      );
      history.execute(
        SetInstanceOverrideCommand(
          instance: instance,
          key: 'color',
          newValue: '#0000FF',
        ),
      );
      // Should be merged into a single undo entry.
      expect(history.canUndo, true);
      history.undo();
      // All three coalesced — one undo reverts to no override.
      expect(instance.overrides.containsKey('color'), false);
    });

    test('does not coalesce different keys', () {
      final history = CommandHistory();
      final instance = SymbolInstanceNode(id: NodeId('i1'), symbolDefinitionId: 'btn');
      history.execute(
        SetInstanceOverrideCommand(
          instance: instance,
          key: 'color',
          newValue: '#FF0000',
        ),
      );
      history.execute(
        SetInstanceOverrideCommand(
          instance: instance,
          key: 'fontSize',
          newValue: 16,
        ),
      );
      // Two separate entries.
      history.undo();
      expect(instance.overrides['color'], '#FF0000');
      expect(instance.overrides.containsKey('fontSize'), false);
    });
  });

  group('RenameVariantAxisCommand merge coalescing', () {
    test('coalesces keystroke-by-keystroke renames', () {
      final history = CommandHistory();
      final def = _buildButtonDef();
      final sizeProp = def.variantProperties.firstWhere(
        (p) => p.name == 'Size',
      );
      history.execute(
        RenameVariantAxisCommand(
          definition: def,
          propertyId: sizeProp.id,
          newName: 'S',
        ),
      );
      history.execute(
        RenameVariantAxisCommand(
          definition: def,
          propertyId: sizeProp.id,
          newName: 'Si',
        ),
      );
      history.execute(
        RenameVariantAxisCommand(
          definition: def,
          propertyId: sizeProp.id,
          newName: 'Siz',
        ),
      );
      // Single undo entry.
      history.undo();
      expect(sizeProp.name, 'Size'); // restored to original
    });

    test('label reflects final name after merge', () {
      final def = _buildButtonDef();
      final sizeProp = def.variantProperties.firstWhere(
        (p) => p.name == 'Size',
      );
      final cmd = RenameVariantAxisCommand(
        definition: def,
        propertyId: sizeProp.id,
        newName: 'Dim',
      );
      cmd.mergeWith(
        RenameVariantAxisCommand(
          definition: def,
          propertyId: sizeProp.id,
          newName: 'Dimension',
        ),
      );
      expect(cmd.label, contains('Dimension'));
    });
  });

  group('RenameVariantOptionCommand merge coalescing', () {
    test('coalesces chained renames', () {
      final history = CommandHistory();
      final def = _buildButtonDef();
      final sizeProp = def.variantProperties.firstWhere(
        (p) => p.name == 'Size',
      );
      // small → sm
      history.execute(
        RenameVariantOptionCommand(
          definition: def,
          propertyId: sizeProp.id,
          oldValue: 'small',
          newValue: 'sm',
        ),
      );
      // sm → s (chained: oldValue == previous newValue)
      history.execute(
        RenameVariantOptionCommand(
          definition: def,
          propertyId: sizeProp.id,
          oldValue: 'sm',
          newValue: 's',
        ),
      );
      // Single undo: reverts to 'small'.
      history.undo();
      expect(sizeProp.options, contains('small'));
    });
  });

  group('Validation guards', () {
    test('AddVariantOptionCommand rejects duplicate', () {
      final def = _buildButtonDef();
      final sizeProp = def.variantProperties.firstWhere(
        (p) => p.name == 'Size',
      );
      expect(
        () => AddVariantOptionCommand(
          definition: def,
          propertyId: sizeProp.id,
          value: 'small', // already exists
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws StateError for missing propertyId', () {
      final def = _buildButtonDef();
      expect(
        () => AddVariantOptionCommand(
          definition: def,
          propertyId: 'non-existent-id',
          value: 'medium',
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('VariantTransactions.removePropertyAcrossInstances', () {
    test('cleans instance selections', () {
      final def = _buildButtonDef();
      final sizeProp = def.variantProperties.firstWhere(
        (p) => p.name == 'Size',
      );
      final i1 = SymbolInstanceNode(
        id: NodeId('i1'),
        symbolDefinitionId: 'btn',
        variantSelections: {'Size': 'large', 'State': 'hover'},
      );
      final i2 = SymbolInstanceNode(
        id: NodeId('i2'),
        symbolDefinitionId: 'btn',
        variantSelections: {'State': 'default'},
      );

      final composite = VariantTransactions.removePropertyAcrossInstances(
        def: def,
        propertyId: sizeProp.id,
        instances: [i1, i2],
      );

      expect(def.variantProperties.any((p) => p.name == 'Size'), false);
      // i1's Size selection was cleaned.
      expect(i1.variantSelections.containsKey('Size'), true); // set to ''

      composite.undo();
      expect(def.variantProperties.any((p) => p.name == 'Size'), true);
    });
  });

  group('fillMissingVariants empty guard', () {
    test('returns null when no missing variants', () {
      final def = _buildButtonDef(); // Already has all 4 combos.
      final result = VariantTransactions.fillMissingVariants(
        def: def,
        contentFactory: (pv) => _namedGroup('fill'),
      );
      expect(result, isNull);
    });
  });

  group('Double undo-redo idempotency', () {
    test('all commands survive double undo-redo cycle', () {
      final def = _buildButtonDef();
      final sizeProp = def.variantProperties.firstWhere(
        (p) => p.name == 'Size',
      );
      final cmd = RemoveVariantOptionCommand(
        definition: def,
        propertyId: sizeProp.id,
        value: 'large',
      );
      // First cycle.
      cmd.execute();
      cmd.undo();
      cmd.redo();
      cmd.undo();
      // Second cycle.
      cmd.redo();
      cmd.undo();
      // State is back to original.
      expect(def.variants.length, 4);
      expect(sizeProp.options, contains('large'));
    });
  });

  group('Stress: 100× rapid merge coalescing', () {
    test('100 SetVariantSelection merges coalesce correctly', () {
      final history = CommandHistory();
      final instance = SymbolInstanceNode(id: NodeId('i1'), symbolDefinitionId: 'btn');
      for (var i = 0; i < 100; i++) {
        history.execute(
          SetVariantSelectionCommand(
            instance: instance,
            propertyName: 'Size',
            newValue: 'val-$i',
          ),
        );
      }
      expect(instance.variantSelections['Size'], 'val-99');
      // Single undo undoes all 100 coalesced changes.
      history.undo();
      expect(instance.variantSelections.containsKey('Size'), false);
    });
  });

  group('Composite undo order (5-command chain)', () {
    test('undo reverses 5 commands in correct order', () {
      final def = _buildButtonDef();
      final sizeProp = def.variantProperties.firstWhere(
        (p) => p.name == 'Size',
      );
      final stateProp = def.variantProperties.firstWhere(
        (p) => p.name == 'State',
      );

      final composite = CompositeCommand(
        label: 'Multi-step',
        commands: [
          AddVariantOptionCommand(
            definition: def,
            propertyId: sizeProp.id,
            value: 'medium',
          ),
          AddVariantOptionCommand(
            definition: def,
            propertyId: sizeProp.id,
            value: 'xl',
          ),
          AddVariantOptionCommand(
            definition: def,
            propertyId: stateProp.id,
            value: 'pressed',
          ),
          AddVariantOptionCommand(
            definition: def,
            propertyId: stateProp.id,
            value: 'disabled',
          ),
          AddVariantOptionCommand(
            definition: def,
            propertyId: stateProp.id,
            value: 'focus',
          ),
        ],
      );

      composite.execute();
      expect(sizeProp.options.length, 4); // small, large, medium, xl
      expect(
        stateProp.options.length,
        5,
      ); // default, hover, pressed, disabled, focus

      composite.undo();
      expect(sizeProp.options.length, 2); // back to small, large
      expect(stateProp.options.length, 2); // back to default, hover

      composite.redo();
      expect(sizeProp.options.length, 4);
      expect(stateProp.options.length, 5);
    });
  });
}
