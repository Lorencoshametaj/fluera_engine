import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/systems/design_variables.dart';

void main() {
  // =========================================================================
  // DesignVariableType
  // =========================================================================

  group('DesignVariableType', () {
    test('has all expected values', () {
      expect(DesignVariableType.values.length, 4);
      expect(DesignVariableType.values, contains(DesignVariableType.color));
      expect(DesignVariableType.values, contains(DesignVariableType.number));
      expect(DesignVariableType.values, contains(DesignVariableType.string));
      expect(DesignVariableType.values, contains(DesignVariableType.boolean));
    });
  });

  // =========================================================================
  // VariableMode
  // =========================================================================

  group('VariableMode', () {
    test('constructs with id and name', () {
      final mode = VariableMode(id: 'dark', name: 'Dark Mode');
      expect(mode.id, 'dark');
      expect(mode.name, 'Dark Mode');
    });

    test('equality by id', () {
      final a = VariableMode(id: 'light', name: 'Light');
      final b = VariableMode(id: 'light', name: 'Light Theme');
      expect(a, equals(b));
    });

    test('inequality for different ids', () {
      final a = VariableMode(id: 'light', name: 'Light');
      final b = VariableMode(id: 'dark', name: 'Dark');
      expect(a, isNot(equals(b)));
    });

    test('toJson / fromJson round-trip', () {
      final original = VariableMode(id: 'mobile', name: 'Mobile');
      final json = original.toJson();
      final restored = VariableMode.fromJson(json);
      expect(restored.id, 'mobile');
      expect(restored.name, 'Mobile');
    });
  });

  // =========================================================================
  // DesignVariable
  // =========================================================================

  group('DesignVariable', () {
    // ── Construction ────────────────────────────────────────────────────

    test('constructs with type and values', () {
      final v = DesignVariable(
        id: 'bg',
        name: 'Background',
        type: DesignVariableType.color,
        values: {'light': 0xFFFFFFFF, 'dark': 0xFF000000},
      );
      expect(v.id, 'bg');
      expect(v.name, 'Background');
      expect(v.type, DesignVariableType.color);
      expect(v.values.length, 2);
    });

    test('constructs with empty values', () {
      final v = DesignVariable(
        id: 'x',
        name: 'Test',
        type: DesignVariableType.number,
      );
      expect(v.values, isEmpty);
    });

    // ── Type Validation ─────────────────────────────────────────────────

    test('validates color type (int)', () {
      final v = DesignVariable(
        id: 'c1',
        name: 'Color',
        type: DesignVariableType.color,
      );
      v.setValue('mode1', 0xFF0000FF); // valid
      expect(v.getValue('mode1'), 0xFF0000FF);

      expect(
        () => v.setValue('mode1', 'not-a-color'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('validates number type', () {
      final v = DesignVariable(
        id: 'n1',
        name: 'Spacing',
        type: DesignVariableType.number,
      );
      v.setValue('default', 16.0);
      expect(v.getValue('default'), 16.0);

      v.setValue('default', 42); // int is also num, should be accepted
      expect(v.getValue('default'), 42);

      expect(
        () => v.setValue('default', 'string'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('validates string type', () {
      final v = DesignVariable(
        id: 's1',
        name: 'Label',
        type: DesignVariableType.string,
      );
      v.setValue('en', 'Hello');
      expect(v.getValue('en'), 'Hello');

      expect(() => v.setValue('en', 42), throwsA(isA<ArgumentError>()));
    });

    test('validates boolean type', () {
      final v = DesignVariable(
        id: 'b1',
        name: 'Visible',
        type: DesignVariableType.boolean,
      );
      v.setValue('default', true);
      expect(v.getValue('default'), true);

      expect(() => v.setValue('default', 1), throwsA(isA<ArgumentError>()));
    });

    // ── Resolution ──────────────────────────────────────────────────────

    test('resolve returns value for active mode', () {
      final v = DesignVariable(
        id: 'bg',
        name: 'BG',
        type: DesignVariableType.color,
        values: {'light': 0xFFFFFFFF, 'dark': 0xFF000000},
      );
      expect(v.resolve('dark'), 0xFF000000);
    });

    test('resolve falls back to first mode value', () {
      final v = DesignVariable(
        id: 'bg',
        name: 'BG',
        type: DesignVariableType.color,
        values: {'light': 0xFFFFFFFF},
      );
      expect(v.resolve('nonexistent'), 0xFFFFFFFF);
    });

    test('resolve returns null when no values', () {
      final v = DesignVariable(
        id: 'bg',
        name: 'BG',
        type: DesignVariableType.color,
      );
      expect(v.resolve('any'), isNull);
    });

    // ── Serialization ───────────────────────────────────────────────────

    test('toJson / fromJson round-trip for color variable', () {
      final original = DesignVariable(
        id: 'primary',
        name: 'Primary Color',
        type: DesignVariableType.color,
        description: 'Main brand color',
        values: {'light': 0xFF0000FF, 'dark': 0xFF00FFFF},
      );
      final json = original.toJson();
      final restored = DesignVariable.fromJson(json);

      expect(restored.id, 'primary');
      expect(restored.name, 'Primary Color');
      expect(restored.type, DesignVariableType.color);
      expect(restored.description, 'Main brand color');
      expect(restored.getValue('light'), 0xFF0000FF);
      expect(restored.getValue('dark'), 0xFF00FFFF);
    });

    test('toJson / fromJson round-trip for number variable', () {
      final original = DesignVariable(
        id: 'spacing',
        name: 'Large Spacing',
        type: DesignVariableType.number,
        values: {'mobile': 8.0, 'desktop': 24.0},
      );
      final json = original.toJson();
      final restored = DesignVariable.fromJson(json);

      expect(restored.type, DesignVariableType.number);
      expect(restored.getValue('mobile'), 8.0);
      expect(restored.getValue('desktop'), 24.0);
    });

    test('toJson / fromJson round-trip for boolean variable', () {
      final original = DesignVariable(
        id: 'showBadge',
        name: 'Show Badge',
        type: DesignVariableType.boolean,
        values: {'default': true, 'compact': false},
      );
      final json = original.toJson();
      final restored = DesignVariable.fromJson(json);

      expect(restored.type, DesignVariableType.boolean);
      expect(restored.getValue('default'), true);
      expect(restored.getValue('compact'), false);
    });

    // ---- CRUD ----

    test('removeValue removes value for mode', () {
      final v = DesignVariable(
        id: 'x',
        name: 'X',
        type: DesignVariableType.number,
        values: {'a': 1.0, 'b': 2.0},
      );
      v.removeValue('a');
      expect(v.hasValueForMode('a'), isFalse);
      expect(v.hasValueForMode('b'), isTrue);
    });
  });

  // =========================================================================
  // VariableCollection
  // =========================================================================

  group('VariableCollection', () {
    // ── Construction ────────────────────────────────────────────────────

    test('creates default mode when none provided', () {
      final c = VariableCollection(id: 'c1', name: 'Test');
      expect(c.modeCount, 1);
      expect(c.defaultModeId, 'default');
    });

    test('uses provided modes', () {
      final c = VariableCollection(
        id: 'themes',
        name: 'Themes',
        modes: [
          VariableMode(id: 'light', name: 'Light'),
          VariableMode(id: 'dark', name: 'Dark'),
        ],
      );
      expect(c.modeCount, 2);
      expect(c.defaultModeId, 'light');
    });

    // ── Mode CRUD ───────────────────────────────────────────────────────

    test('addMode adds a mode', () {
      final c = VariableCollection(id: 'c1', name: 'Test');
      c.addMode(VariableMode(id: 'dark', name: 'Dark'));
      expect(c.modeCount, 2);
    });

    test('addMode skips duplicates', () {
      final c = VariableCollection(id: 'c1', name: 'Test');
      c.addMode(VariableMode(id: 'default', name: 'Default Again'));
      expect(c.modeCount, 1);
    });

    test('removeMode removes and cleans up variable values', () {
      final c = VariableCollection(
        id: 'c1',
        name: 'Test',
        modes: [
          VariableMode(id: 'a', name: 'A'),
          VariableMode(id: 'b', name: 'B'),
        ],
      );
      final v = DesignVariable(
        id: 'v1',
        name: 'Var1',
        type: DesignVariableType.number,
        values: {'a': 10.0, 'b': 20.0},
      );
      c.addVariable(v);

      final removed = c.removeMode('b');
      expect(removed, isTrue);
      expect(c.modeCount, 1);
      expect(v.hasValueForMode('b'), isFalse);
    });

    test('removeMode refuses to remove last mode', () {
      final c = VariableCollection(id: 'c1', name: 'Test');
      final removed = c.removeMode('default');
      expect(removed, isFalse);
      expect(c.modeCount, 1);
    });

    test('findMode finds by id', () {
      final c = VariableCollection(
        id: 'c1',
        name: 'Test',
        modes: [VariableMode(id: 'dark', name: 'Dark')],
      );
      expect(c.findMode('dark'), isNotNull);
      expect(c.findMode('nonexistent'), isNull);
    });

    // ── Variable CRUD ───────────────────────────────────────────────────

    test('addVariable and findVariable', () {
      final c = VariableCollection(id: 'c1', name: 'Test');
      final v = DesignVariable(
        id: 'v1',
        name: 'Var',
        type: DesignVariableType.string,
      );
      c.addVariable(v);
      expect(c.variableCount, 1);
      expect(c.findVariable('v1'), isNotNull);
    });

    test('addVariable skips duplicates', () {
      final c = VariableCollection(id: 'c1', name: 'Test');
      final v = DesignVariable(
        id: 'v1',
        name: 'Var',
        type: DesignVariableType.string,
      );
      c.addVariable(v);
      c.addVariable(v);
      expect(c.variableCount, 1);
    });

    test('removeVariable removes by id', () {
      final c = VariableCollection(id: 'c1', name: 'Test');
      c.addVariable(
        DesignVariable(id: 'v1', name: 'Var', type: DesignVariableType.boolean),
      );
      final removed = c.removeVariable('v1');
      expect(removed, isTrue);
      expect(c.variableCount, 0);
    });

    test('removeVariable returns false for unknown id', () {
      final c = VariableCollection(id: 'c1', name: 'Test');
      expect(c.removeVariable('nope'), isFalse);
    });

    // ── Serialization ───────────────────────────────────────────────────

    test('toJson / fromJson round-trip', () {
      final original = VariableCollection(
        id: 'themes',
        name: 'Color Themes',
        modes: [
          VariableMode(id: 'light', name: 'Light'),
          VariableMode(id: 'dark', name: 'Dark'),
        ],
        variables: [
          DesignVariable(
            id: 'bg',
            name: 'Background',
            type: DesignVariableType.color,
            values: {'light': 0xFFFFFFFF, 'dark': 0xFF1A1A1A},
          ),
          DesignVariable(
            id: 'radius',
            name: 'Corner Radius',
            type: DesignVariableType.number,
            values: {'light': 8.0, 'dark': 12.0},
          ),
        ],
      );

      final json = original.toJson();
      final restored = VariableCollection.fromJson(json);

      expect(restored.id, 'themes');
      expect(restored.name, 'Color Themes');
      expect(restored.modeCount, 2);
      expect(restored.variableCount, 2);
      expect(restored.findVariable('bg'), isNotNull);
      expect(restored.findVariable('bg')!.getValue('dark'), 0xFF1A1A1A);
      expect(restored.findVariable('radius')!.getValue('light'), 8.0);
    });

    test('fromJson with missing modes creates default', () {
      final json = {'id': 'c1', 'name': 'Empty'};
      final c = VariableCollection.fromJson(json);
      expect(c.modeCount, 1);
      expect(c.defaultModeId, 'default');
    });

    // ── Grouping ────────────────────────────────────────────────────────

    test('variablesByGroup groups variables', () {
      final c = VariableCollection(
        id: 'c1',
        name: 'Test',
        variables: [
          DesignVariable(
            id: 'v1',
            name: 'A',
            type: DesignVariableType.color,
            group: 'colors/primary',
          ),
          DesignVariable(
            id: 'v2',
            name: 'B',
            type: DesignVariableType.color,
            group: 'colors/primary',
          ),
          DesignVariable(
            id: 'v3',
            name: 'C',
            type: DesignVariableType.number,
            group: 'spacing',
          ),
          DesignVariable(id: 'v4', name: 'D', type: DesignVariableType.boolean),
        ],
      );

      final groups = c.variablesByGroup();
      expect(groups.keys.length, 3);
      expect(groups['colors/primary']!.length, 2);
      expect(groups['spacing']!.length, 1);
      expect(groups['']!.length, 1); // ungrouped
    });
  });

  // =========================================================================
  // VariableConstraints
  // =========================================================================

  group('VariableConstraints', () {
    test('validates number min', () {
      const c = VariableConstraints(min: 0);
      expect(c.validate(-1, DesignVariableType.number), isNotNull);
      expect(c.validate(0, DesignVariableType.number), isNull);
      expect(c.validate(10, DesignVariableType.number), isNull);
    });

    test('validates number max', () {
      const c = VariableConstraints(max: 100);
      expect(c.validate(101, DesignVariableType.number), isNotNull);
      expect(c.validate(100, DesignVariableType.number), isNull);
      expect(c.validate(50, DesignVariableType.number), isNull);
    });

    test('validates number min and max together', () {
      const c = VariableConstraints(min: 0, max: 1);
      expect(c.validate(-0.1, DesignVariableType.number), isNotNull);
      expect(c.validate(1.1, DesignVariableType.number), isNotNull);
      expect(c.validate(0.5, DesignVariableType.number), isNull);
    });

    test('validates string allowedValues', () {
      const c = VariableConstraints(allowedValues: ['left', 'center', 'right']);
      expect(c.validate('top', DesignVariableType.string), isNotNull);
      expect(c.validate('center', DesignVariableType.string), isNull);
    });

    test('ignores constraints for non-matching types', () {
      const c = VariableConstraints(min: 0, max: 100);
      // Constraints for number don't apply to color
      expect(c.validate(0xFF000000, DesignVariableType.color), isNull);
    });

    test('null value always passes', () {
      const c = VariableConstraints(min: 0, max: 100);
      expect(c.validate(null, DesignVariableType.number), isNull);
    });

    test('toJson / fromJson round-trip', () {
      const original = VariableConstraints(
        min: 0,
        max: 255,
        allowedValues: ['a', 'b'],
      );
      final json = original.toJson();
      final restored = VariableConstraints.fromJson(json);
      expect(restored.min, 0);
      expect(restored.max, 255);
      expect(restored.allowedValues, ['a', 'b']);
    });

    test('DesignVariable enforces constraints on setValue', () {
      final v = DesignVariable(
        id: 'opacity',
        name: 'Opacity',
        type: DesignVariableType.number,
        constraints: const VariableConstraints(min: 0, max: 1),
      );

      v.setValue('default', 0.5); // valid
      expect(v.getValue('default'), 0.5);

      expect(() => v.setValue('default', 1.5), throwsA(isA<ArgumentError>()));
      expect(() => v.setValue('default', -0.1), throwsA(isA<ArgumentError>()));
    });

    test('DesignVariable enforces string allowedValues', () {
      final v = DesignVariable(
        id: 'align',
        name: 'Alignment',
        type: DesignVariableType.string,
        constraints: const VariableConstraints(
          allowedValues: ['left', 'center', 'right'],
        ),
      );

      v.setValue('default', 'center'); // valid
      expect(
        () => v.setValue('default', 'justify'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('DesignVariable serializes constraints and group', () {
      final original = DesignVariable(
        id: 'x',
        name: 'X',
        type: DesignVariableType.number,
        group: 'spacing/large',
        constraints: const VariableConstraints(min: 0, max: 100),
        values: {'default': 50.0},
      );

      final json = original.toJson();
      final restored = DesignVariable.fromJson(json);

      expect(restored.group, 'spacing/large');
      expect(restored.constraints, isNotNull);
      expect(restored.constraints!.min, 0);
      expect(restored.constraints!.max, 100);
    });
  });

  // =========================================================================
  // Mode Inheritance
  // =========================================================================

  group('Mode inheritance', () {
    test('VariableMode serializes inheritsFrom', () {
      final mode = VariableMode(
        id: 'dark-hc',
        name: 'Dark High Contrast',
        inheritsFrom: 'dark',
      );
      final json = mode.toJson();
      expect(json['inheritsFrom'], 'dark');

      final restored = VariableMode.fromJson(json);
      expect(restored.inheritsFrom, 'dark');
    });

    test('modeInheritanceChain walks parents', () {
      final c = VariableCollection(
        id: 'c1',
        name: 'Test',
        modes: [
          VariableMode(id: 'base', name: 'Base'),
          VariableMode(id: 'dark', name: 'Dark', inheritsFrom: 'base'),
          VariableMode(id: 'dark-hc', name: 'Dark HC', inheritsFrom: 'dark'),
        ],
      );

      final chain = c.modeInheritanceChain('dark-hc');
      expect(chain, ['dark-hc', 'dark', 'base']);
    });

    test('modeInheritanceChain detects cycles', () {
      final c = VariableCollection(
        id: 'c1',
        name: 'Test',
        modes: [
          VariableMode(id: 'a', name: 'A', inheritsFrom: 'b'),
          VariableMode(id: 'b', name: 'B', inheritsFrom: 'a'),
        ],
      );

      final chain = c.modeInheritanceChain('a');
      expect(chain, ['a', 'b']); // stops at cycle
    });

    test('modeInheritanceChain returns single element for root mode', () {
      final c = VariableCollection(
        id: 'c1',
        name: 'Test',
        modes: [VariableMode(id: 'default', name: 'Default')],
      );

      expect(c.modeInheritanceChain('default'), ['default']);
    });
  });

  // =========================================================================
  // Mode Completeness
  // =========================================================================

  group('Mode completeness', () {
    test('incompleteVariables returns variables missing values', () {
      final c = VariableCollection(
        id: 'c1',
        name: 'Test',
        modes: [
          VariableMode(id: 'light', name: 'Light'),
          VariableMode(id: 'dark', name: 'Dark'),
        ],
        variables: [
          DesignVariable(
            id: 'v1',
            name: 'Complete',
            type: DesignVariableType.color,
            values: {'light': 0xFFFFFFFF, 'dark': 0xFF000000},
          ),
          DesignVariable(
            id: 'v2',
            name: 'Missing Dark',
            type: DesignVariableType.color,
            values: {'light': 0xFFFFFFFF}, // no dark value
          ),
        ],
      );

      expect(c.incompleteVariables('light'), isEmpty);
      expect(c.incompleteVariables('dark'), ['v2']);
    });

    test('incompleteVariables skips aliases', () {
      final c = VariableCollection(
        id: 'c1',
        name: 'Test',
        modes: [VariableMode(id: 'default', name: 'Default')],
        variables: [
          DesignVariable(
            id: 'alias',
            name: 'Alias',
            type: DesignVariableType.color,
            aliasVariableId: 'target', // aliases don't need own values
          ),
          DesignVariable(
            id: 'no-value',
            name: 'No Value',
            type: DesignVariableType.number,
          ),
        ],
      );

      final incomplete = c.incompleteVariables('default');
      expect(incomplete, ['no-value']); // alias is excluded
    });
  });

  // =========================================================================
  // Variable Scoping
  // =========================================================================

  group('Variable scoping', () {
    test('scopeNodeId serializes round-trip', () {
      final v = DesignVariable(
        id: 'scoped',
        name: 'Scoped',
        type: DesignVariableType.number,
        scopeNodeId: 'frame-1',
        values: {'default': 16.0},
      );

      final json = v.toJson();
      expect(json['scopeNodeId'], 'frame-1');

      final restored = DesignVariable.fromJson(json);
      expect(restored.scopeNodeId, 'frame-1');
    });

    test('copyWith preserves scopeNodeId', () {
      final v = DesignVariable(
        id: 'v1',
        name: 'V1',
        type: DesignVariableType.number,
        scopeNodeId: 'frame-1',
      );
      final copy = v.copyWith(id: 'v2');
      expect(copy.scopeNodeId, 'frame-1');
    });
  });

  // =========================================================================
  // Alias Validation
  // =========================================================================

  group('Alias validation (brokenAliases)', () {
    test('returns empty list when all aliases are valid', () {
      final c = VariableCollection(
        id: 'c1',
        name: 'Test',
        modes: [VariableMode(id: 'default', name: 'Default')],
        variables: [
          DesignVariable(
            id: 'target',
            name: 'Target',
            type: DesignVariableType.color,
            values: {'default': 0xFFFF0000},
          ),
          DesignVariable(
            id: 'alias',
            name: 'Alias',
            type: DesignVariableType.color,
            aliasVariableId: 'target',
          ),
        ],
      );

      expect(c.brokenAliases(), isEmpty);
    });

    test('reports alias with missing target', () {
      final c = VariableCollection(
        id: 'c1',
        name: 'Test',
        variables: [
          DesignVariable(
            id: 'broken-alias',
            name: 'Broken',
            type: DesignVariableType.color,
            aliasVariableId: 'nonexistent',
          ),
        ],
      );

      final broken = c.brokenAliases();
      expect(broken, hasLength(1));
      expect(broken.first['variableId'], 'broken-alias');
      expect(broken.first['missingTarget'], 'nonexistent');
    });

    test('ignores non-alias variables', () {
      final c = VariableCollection(
        id: 'c1',
        name: 'Test',
        variables: [
          DesignVariable(
            id: 'normal',
            name: 'Normal',
            type: DesignVariableType.number,
          ),
        ],
      );

      expect(c.brokenAliases(), isEmpty);
    });
  });
}
