import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/fluera_engine.dart';

void main() {
  // =========================================================================
  // VariantProperty
  // =========================================================================
  group('VariantProperty', () {
    test('variant factory requires at least one option', () {
      expect(
        () => VariantProperty.variant(name: 'Size', options: []),
        throwsArgumentError,
      );
    });

    test('variant factory creates with defaults', () {
      final prop = VariantProperty.variant(
        name: 'Size',
        options: ['small', 'medium', 'large'],
      );
      expect(prop.name, 'Size');
      expect(prop.type, VariantPropertyType.variant);
      expect(prop.options, ['small', 'medium', 'large']);
      expect(prop.defaultValue, 'small'); // First option.
      expect(prop.id, isNotEmpty);
    });

    test('variant factory respects explicit default', () {
      final prop = VariantProperty.variant(
        name: 'Size',
        options: ['small', 'medium', 'large'],
        defaultValue: 'medium',
      );
      expect(prop.defaultValue, 'medium');
    });

    test('boolean factory creates correct property', () {
      final prop = VariantProperty.boolean(name: 'hasIcon');
      expect(prop.type, VariantPropertyType.boolean);
      expect(prop.options, ['true', 'false']);
      expect(prop.defaultValue, 'false');
    });

    test('text factory creates correct property', () {
      final prop = VariantProperty.text(
        name: 'Label',
        defaultValue: 'Click me',
      );
      expect(prop.type, VariantPropertyType.text);
      expect(prop.defaultValue, 'Click me');
      expect(prop.options, isEmpty);
    });

    test('instanceSwap factory creates correct property', () {
      final prop = VariantProperty.instanceSwap(
        name: 'Icon',
        defaultSymbolId: 'sym-icon-star',
      );
      expect(prop.type, VariantPropertyType.instanceSwap);
      expect(prop.defaultValue, 'sym-icon-star');
    });

    test('isValidValue works for all types', () {
      final variant = VariantProperty.variant(
        name: 'Size',
        options: ['small', 'large'],
      );
      expect(variant.isValidValue('small'), true);
      expect(variant.isValidValue('huge'), false);

      final boolean = VariantProperty.boolean(name: 'x');
      expect(boolean.isValidValue('true'), true);
      expect(boolean.isValidValue('false'), true);
      expect(boolean.isValidValue('maybe'), false);

      final text = VariantProperty.text(name: 't');
      expect(text.isValidValue('anything'), true);

      final swap = VariantProperty.instanceSwap(
        name: 's',
        defaultSymbolId: 'id',
      );
      expect(swap.isValidValue('sym-1'), true);
      expect(swap.isValidValue(''), false);
    });

    test('serialization roundtrip', () {
      final original = VariantProperty.variant(
        name: 'State',
        options: ['default', 'hover', 'pressed'],
        defaultValue: 'default',
      );
      final json = original.toJson();
      final restored = VariantProperty.fromJson(json);

      expect(restored.name, 'State');
      expect(restored.type, VariantPropertyType.variant);
      expect(restored.options, ['default', 'hover', 'pressed']);
      expect(restored.defaultValue, 'default');
      expect(restored.id, original.id);
    });

    test('equality is by id', () {
      final a = VariantProperty.boolean(name: 'x');
      final b = VariantProperty.boolean(name: 'x');
      expect(a, isNot(equals(b))); // Different IDs.
      expect(a, equals(a));
    });
  });

  // =========================================================================
  // VariantContent
  // =========================================================================
  group('VariantContent', () {
    test('buildVariantKey sorts alphabetically', () {
      final key = VariantContent.buildVariantKey({
        'state': 'hover',
        'size': 'medium',
      });
      expect(key, 'size=medium,state=hover');
    });

    test('buildVariantKey handles empty map', () {
      expect(VariantContent.buildVariantKey({}), '');
    });

    test('buildVariantKey single property', () {
      expect(VariantContent.buildVariantKey({'size': 'large'}), 'size=large');
    });

    test('variantKey is auto-generated from propertyValues', () {
      final vc = VariantContent(
        propertyValues: {'size': 'small', 'state': 'default'},
        content: _emptyGroup(),
      );
      expect(vc.variantKey, 'size=small,state=default');
    });
  });

  // =========================================================================
  // SymbolDefinition with variants
  // =========================================================================
  group('SymbolDefinition variants', () {
    late SymbolDefinition def;
    late VariantProperty sizeProp;
    late VariantProperty stateProp;

    setUp(() {
      sizeProp = VariantProperty.variant(
        name: 'Size',
        options: ['small', 'large'],
        defaultValue: 'small',
      );
      stateProp = VariantProperty.variant(
        name: 'State',
        options: ['default', 'hover'],
        defaultValue: 'default',
      );

      def = SymbolDefinition(
        id: NodeId('btn-component'),
        name: 'Button',
        content: _namedGroup('base'),
        variantProperties: [sizeProp, stateProp],
      );

      // Populate the variant matrix.
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
    });

    test('hasVariants is true when properties exist', () {
      expect(def.hasVariants, true);
    });

    test('hasVariants is false for empty component', () {
      final empty = SymbolDefinition(
        id: NodeId('x'),
        name: 'X',
        content: _emptyGroup(),
      );
      expect(empty.hasVariants, false);
    });

    test('defaultVariantKey is correct', () {
      expect(def.defaultVariantKey, 'Size=small,State=default');
    });

    test('resolveContent returns exact match', () {
      final content = def.resolveContent({'Size': 'large', 'State': 'hover'});
      expect(content.name, 'large-hover');
    });

    test('resolveContent fills missing selections with defaults', () {
      // Only specify State, Size falls back to default 'small'.
      final content = def.resolveContent({'State': 'hover'});
      expect(content.name, 'small-hover');
    });

    test('resolveContent falls back to default variant on unknown key', () {
      final content = def.resolveContent({'Size': 'huge', 'State': 'hover'});
      // Key "Size=huge,State=hover" doesn't exist, falls back to default.
      expect(content.name, 'small-default');
    });

    test('resolveContent falls back to base content when no variants', () {
      final simple = SymbolDefinition(
        id: NodeId('x'),
        name: 'X',
        content: _namedGroup('base-only'),
      );
      expect(simple.resolveContent({}).name, 'base-only');
    });

    test('variantKeys lists all keys', () {
      expect(def.variantKeys.toList()..sort(), [
        'Size=large,State=default',
        'Size=large,State=hover',
        'Size=small,State=default',
        'Size=small,State=hover',
      ]);
    });

    test('removeVariant removes by property values', () {
      expect(def.variants.length, 4);
      final removed = def.removeVariant({'Size': 'large', 'State': 'hover'});
      expect(removed, true);
      expect(def.variants.length, 3);
      expect(def.lookupVariant('Size=large,State=hover'), isNull);
    });

    test('addVariantProperty adds a new axis', () {
      final disabled = VariantProperty.boolean(name: 'Disabled');
      def.addVariantProperty(disabled);
      expect(def.variantProperties.length, 3);
    });

    test('addVariantProperty ignores duplicates', () {
      def.addVariantProperty(sizeProp); // Already exists.
      expect(def.variantProperties.length, 2);
    });

    test('removeVariantProperty removes axis and related variants', () {
      def.removeVariantProperty(stateProp.id);
      expect(def.variantProperties.length, 1);
      // All variants reference 'State', so all should be removed.
      expect(def.variants, isEmpty);
    });
  });

  // =========================================================================
  // SymbolInstanceNode with variant selections
  // =========================================================================
  group('SymbolInstanceNode variantSelections', () {
    test('default variantSelections is empty', () {
      final instance = SymbolInstanceNode(
        id: NodeId('inst-1'),
        symbolDefinitionId: 'btn-component',
      );
      expect(instance.variantSelections, isEmpty);
    });

    test('variantSelections can be set', () {
      final instance = SymbolInstanceNode(
        id: NodeId('inst-1'),
        symbolDefinitionId: 'btn-component',
        variantSelections: {'Size': 'large', 'State': 'hover'},
      );
      expect(instance.variantSelections['Size'], 'large');
      expect(instance.variantSelections['State'], 'hover');
    });

    test('serialization roundtrip preserves variantSelections', () {
      final original = SymbolInstanceNode(
        id: NodeId('inst-1'),
        symbolDefinitionId: 'btn-component',
        variantSelections: {'Size': 'large', 'State': 'hover'},
        overrides: {'children.0.fillColor': 0xFF00FF00},
      );
      final json = original.toJson();
      final restored = SymbolInstanceNode.fromJson(json);

      expect(restored.symbolDefinitionId, 'btn-component');
      expect(restored.variantSelections, {'Size': 'large', 'State': 'hover'});
      expect(restored.overrides['children.0.fillColor'], 0xFF00FF00);
    });

    test('serialization omits empty variantSelections', () {
      final instance = SymbolInstanceNode(
        id: NodeId('inst-1'),
        symbolDefinitionId: 'btn-component',
      );
      final json = instance.toJson();
      expect(json.containsKey('variantSelections'), false);
    });
  });

  // =========================================================================
  // End-to-end resolution
  // =========================================================================
  group('End-to-end variant resolution', () {
    test('instance resolves correct content from definition', () {
      final def = SymbolDefinition(
        id: NodeId('card'),
        name: 'Card',
        content: _namedGroup('base'),
        variantProperties: [
          VariantProperty.variant(
            name: 'Style',
            options: ['flat', 'elevated'],
            defaultValue: 'flat',
          ),
        ],
      );
      def.setVariant({'Style': 'flat'}, _namedGroup('flat-card'));
      def.setVariant({'Style': 'elevated'}, _namedGroup('elevated-card'));

      final instance = SymbolInstanceNode(
        id: NodeId('inst-1'),
        symbolDefinitionId: 'card',
        variantSelections: {'Style': 'elevated'},
      );

      // Simulate renderer resolution.
      final resolved = def.resolveContent(instance.variantSelections);
      expect(resolved.name, 'elevated-card');
    });

    test('instance with no selections gets default variant', () {
      final def = SymbolDefinition(
        id: NodeId('toggle'),
        name: 'Toggle',
        content: _namedGroup('base'),
        variantProperties: [VariantProperty.boolean(name: 'isOn')],
      );
      def.setVariant({'isOn': 'false'}, _namedGroup('off'));
      def.setVariant({'isOn': 'true'}, _namedGroup('on'));

      final instance = SymbolInstanceNode(
        id: NodeId('inst-1'),
        symbolDefinitionId: 'toggle',
        // No selections — should fall back to default 'false'.
      );

      final resolved = def.resolveContent(instance.variantSelections);
      expect(resolved.name, 'off');
    });
  });

  // =========================================================================
  // VariantProperty mutations (enterprise fixes 1-2)
  // =========================================================================
  group('VariantProperty mutations', () {
    test('copyWith preserves id and changes fields', () {
      final prop = VariantProperty.variant(
        name: 'Size',
        options: ['s', 'm', 'l'],
        defaultValue: 's',
      );
      final copy = prop.copyWith(name: 'Dimensions', defaultValue: 'm');
      expect(copy.id, prop.id);
      expect(copy.name, 'Dimensions');
      expect(copy.defaultValue, 'm');
      expect(copy.options, ['s', 'm', 'l']);
    });

    test('addOption appends and is idempotent', () {
      final prop = VariantProperty.variant(name: 'Size', options: ['s', 'm']);
      prop.addOption('l');
      expect(prop.options, ['s', 'm', 'l']);
      prop.addOption('l'); // Idempotent.
      expect(prop.options, ['s', 'm', 'l']);
    });

    test('removeOption adjusts default', () {
      final prop = VariantProperty.variant(
        name: 'Size',
        options: ['s', 'm', 'l'],
        defaultValue: 's',
      );
      expect(prop.removeOption('s'), true);
      expect(prop.options, ['m', 'l']);
      expect(prop.defaultValue, 'm'); // Reset to first remaining.
    });

    test('removeOption returns false for missing', () {
      final prop = VariantProperty.variant(name: 'Size', options: ['s']);
      expect(prop.removeOption('x'), false);
    });

    test('renameOption updates options and default', () {
      final prop = VariantProperty.variant(
        name: 'Size',
        options: ['s', 'm', 'l'],
        defaultValue: 's',
      );
      expect(prop.renameOption('s', 'small'), true);
      expect(prop.options, ['small', 'm', 'l']);
      expect(prop.defaultValue, 'small');
    });

    test('renameOption fails for duplicate target', () {
      final prop = VariantProperty.variant(name: 'Size', options: ['s', 'm']);
      expect(prop.renameOption('s', 'm'), false);
    });

    test('renameOption fails for missing source', () {
      final prop = VariantProperty.variant(name: 'Size', options: ['s']);
      expect(prop.renameOption('x', 'y'), false);
    });
  });

  // =========================================================================
  // Matrix completeness (enterprise fix 4)
  // =========================================================================
  group('SymbolDefinition matrix completeness', () {
    test('isMatrixComplete is true when all combos covered', () {
      final def = _buildButtonDef();
      expect(def.isMatrixComplete, true);
      expect(def.missingVariantKeys, isEmpty);
    });

    test('isMatrixComplete is false when combos missing', () {
      final def = _buildButtonDef();
      def.removeVariant({'Size': 'large', 'State': 'hover'});
      expect(def.isMatrixComplete, false);
      expect(def.missingVariantKeys, ['Size=large,State=hover']);
    });

    test('allCombinations computes Cartesian product', () {
      final def = _buildButtonDef();
      expect(def.allCombinations.length, 4); // 2 × 2
    });

    test('allCombinations handles boolean properties', () {
      final def = SymbolDefinition(
        id: NodeId('x'),
        name: 'X',
        content: _emptyGroup(),
        variantProperties: [
          VariantProperty.boolean(name: 'A'),
          VariantProperty.boolean(name: 'B'),
        ],
      );
      expect(def.allCombinations.length, 4); // 2 × 2
    });
  });

  // =========================================================================
  // Rename propagation (enterprise fix 5)
  // =========================================================================
  group('SymbolDefinition rename propagation', () {
    test('renameVariantOption updates keys and property', () {
      final def = _buildButtonDef();
      final sizeProp = def.variantProperties.firstWhere(
        (p) => p.name == 'Size',
      );

      final result = def.renameVariantOption(sizeProp.id, 'small', 'tiny');
      expect(result, true);
      expect(sizeProp.options.contains('tiny'), true);
      expect(sizeProp.options.contains('small'), false);

      // Matrix keys should be updated.
      expect(def.lookupVariant('Size=tiny,State=default'), isNotNull);
      expect(def.lookupVariant('Size=tiny,State=hover'), isNotNull);
      expect(def.lookupVariant('Size=small,State=default'), isNull);
    });

    test('renameVariantOption preserves content', () {
      final def = _buildButtonDef();
      final sizeProp = def.variantProperties.firstWhere(
        (p) => p.name == 'Size',
      );

      def.renameVariantOption(sizeProp.id, 'small', 'tiny');
      final vc = def.lookupVariant('Size=tiny,State=default');
      expect(vc?.content.name, 'small-default');
    });

    test('renameVariantOption returns false for bad property', () {
      final def = _buildButtonDef();
      expect(def.renameVariantOption('bad-id', 'x', 'y'), false);
    });
  });

  // =========================================================================
  // Reorder (enterprise fix 6)
  // =========================================================================
  group('SymbolDefinition reorder', () {
    test('reorderVariantProperty moves axis', () {
      final def = _buildButtonDef();
      final sizeProp = def.variantProperties.firstWhere(
        (p) => p.name == 'Size',
      );

      expect(def.variantProperties[0].name, 'Size');
      def.reorderVariantProperty(sizeProp.id, 1);
      expect(def.variantProperties[0].name, 'State');
      expect(def.variantProperties[1].name, 'Size');
    });

    test('reorderVariantProperty no-op for same index', () {
      final def = _buildButtonDef();
      final sizeProp = def.variantProperties.firstWhere(
        (p) => p.name == 'Size',
      );

      def.reorderVariantProperty(sizeProp.id, 0);
      expect(def.variantProperties[0].name, 'Size');
    });

    test('reorderVariantProperty ignores invalid index', () {
      final def = _buildButtonDef();
      final sizeProp = def.variantProperties.firstWhere(
        (p) => p.name == 'Size',
      );

      def.reorderVariantProperty(sizeProp.id, 99);
      expect(def.variantProperties[0].name, 'Size');
    });
  });

  // =========================================================================
  // Instance validation (enterprise fix 3)
  // =========================================================================
  group('SymbolInstanceNode validation', () {
    test('validateSelections returns empty for valid selections', () {
      final def = _buildButtonDef();
      final instance = SymbolInstanceNode(
        id: NodeId('i1'),
        symbolDefinitionId: def.id,
        variantSelections: {'Size': 'small', 'State': 'hover'},
      );
      expect(instance.validateSelections(def), isEmpty);
    });

    test('validateSelections catches invalid value', () {
      final def = _buildButtonDef();
      final instance = SymbolInstanceNode(
        id: NodeId('i1'),
        symbolDefinitionId: def.id,
        variantSelections: {'Size': 'huge', 'State': 'hover'},
      );
      expect(instance.validateSelections(def), ['Size']);
    });

    test('validateSelections catches stale property', () {
      final def = _buildButtonDef();
      final instance = SymbolInstanceNode(
        id: NodeId('i1'),
        symbolDefinitionId: def.id,
        variantSelections: {'NonExistent': 'x'},
      );
      expect(instance.validateSelections(def), ['NonExistent']);
    });

    test('sanitizeSelections fixes invalid values', () {
      final def = _buildButtonDef();
      final instance = SymbolInstanceNode(
        id: NodeId('i1'),
        symbolDefinitionId: def.id,
        variantSelections: {'Size': 'huge', 'State': 'hover'},
      );
      final corrected = instance.sanitizeSelections(def);
      expect(corrected, 1);
      expect(instance.variantSelections['Size'], 'small'); // Reset to default.
      expect(instance.variantSelections['State'], 'hover'); // Unchanged.
    });

    test('sanitizeSelections removes stale properties', () {
      final def = _buildButtonDef();
      final instance = SymbolInstanceNode(
        id: NodeId('i1'),
        symbolDefinitionId: def.id,
        variantSelections: {'OldProp': 'x', 'Size': 'large'},
      );
      final corrected = instance.sanitizeSelections(def);
      expect(corrected, 1);
      expect(instance.variantSelections.containsKey('OldProp'), false);
      expect(instance.variantSelections['Size'], 'large');
    });

    test('sanitizeSelections returns 0 when all valid', () {
      final def = _buildButtonDef();
      final instance = SymbolInstanceNode(
        id: NodeId('i1'),
        symbolDefinitionId: def.id,
        variantSelections: {'Size': 'large'},
      );
      expect(instance.sanitizeSelections(def), 0);
    });
  });

  // =========================================================================
  // Round 2: Key escaping (Fix 7)
  // =========================================================================
  group('VariantContent key escaping', () {
    test('escapes = and , in property names and values', () {
      final key = VariantContent.buildVariantKey({'a=b': 'x,y'});
      // Should be escaped.
      expect(key.contains('a=b'), false);
      expect(key, 'a%3Db=x%2Cy');
    });

    test('escapes % itself first', () {
      final key = VariantContent.buildVariantKey({'a%b': 'c'});
      expect(key, 'a%25b=c');
    });

    test('unescapeKeyPart roundtrips', () {
      const original = 'value=with,special%chars';
      final escaped = VariantContent.buildVariantKey({'key': original});
      // Extract the value part.
      final valuePart = escaped.split('=').sublist(1).join('=');
      expect(VariantContent.unescapeKeyPart(valuePart), original);
    });

    test('normal values are not affected', () {
      final key = VariantContent.buildVariantKey({'size': 'large'});
      expect(key, 'size=large');
    });
  });

  // =========================================================================
  // Round 2: Mutable options (Fix 4)
  // =========================================================================
  group('VariantProperty mutable options', () {
    test('options are mutable after creation via variant factory', () {
      final prop = VariantProperty.variant(name: 'Size', options: ['s', 'm']);
      // Should NOT throw (was crashing with List.unmodifiable).
      prop.addOption('l');
      expect(prop.options, ['s', 'm', 'l']);
    });
  });

  // =========================================================================
  // Round 2: Duplicate name guard (Fix 5)
  // =========================================================================
  group('SymbolDefinition duplicate name guard', () {
    test('addVariantProperty rejects duplicate name', () {
      final def = _buildButtonDef();
      // Try to add another property with name 'Size' (already exists).
      final dupe = VariantProperty.variant(name: 'Size', options: ['xs']);
      def.addVariantProperty(dupe);
      // Should still be 2.
      expect(def.variantProperties.length, 2);
    });
  });

  // =========================================================================
  // Round 2: Axis rename propagation (Fix 6)
  // =========================================================================
  group('SymbolDefinition axis rename', () {
    test('renameVariantPropertyAxis updates keys', () {
      final def = _buildButtonDef();
      final sizeProp = def.variantProperties.firstWhere(
        (p) => p.name == 'Size',
      );

      final result = def.renameVariantPropertyAxis(sizeProp.id, 'Dimension');
      expect(result, true);
      expect(sizeProp.name, 'Dimension');

      // Matrix keys should use new axis name.
      expect(def.lookupVariant('Dimension=small,State=default'), isNotNull);
      expect(def.lookupVariant('Dimension=large,State=hover'), isNotNull);
      expect(def.lookupVariant('Size=small,State=default'), isNull);
    });

    test('renameVariantPropertyAxis rejects duplicate name', () {
      final def = _buildButtonDef();
      final sizeProp = def.variantProperties.firstWhere(
        (p) => p.name == 'Size',
      );

      // 'State' already exists.
      expect(def.renameVariantPropertyAxis(sizeProp.id, 'State'), false);
    });

    test('renameVariantPropertyAxis no-op for same name', () {
      final def = _buildButtonDef();
      final sizeProp = def.variantProperties.firstWhere(
        (p) => p.name == 'Size',
      );

      expect(def.renameVariantPropertyAxis(sizeProp.id, 'Size'), false);
    });
  });

  // =========================================================================
  // Round 2: SymbolDefinition.copyWith (Fix 8)
  // =========================================================================
  group('SymbolDefinition copyWith', () {
    test('creates independent copy with new id and name', () {
      final original = _buildButtonDef();
      final copy = original.copyWith(id: NodeId('btn-v2'), name: 'Button V2');

      expect(copy.id, 'btn-v2');
      expect(copy.name, 'Button V2');
      expect(copy.variants.length, original.variants.length);
      expect(copy.variantProperties.length, original.variantProperties.length);
    });

    test('copy has independent variant properties', () {
      final original = _buildButtonDef();
      final copy = original.copyWith();

      // Mutate copy's property.
      copy.variantProperties.first.addOption('xl');
      // Original should not be affected.
      expect(original.variantProperties.first.options.contains('xl'), false);
    });

    test('default id and name suffixes', () {
      final original = _buildButtonDef();
      final copy = original.copyWith();
      expect(copy.id, 'btn-copy');
      expect(copy.name, 'Button (Copy)');
    });
  });

  // =========================================================================
  // Round 2: SymbolInstanceNode.clone (Fix 3)
  // =========================================================================
  group('SymbolInstanceNode clone', () {
    test('clone creates independent copy', () {
      final original = SymbolInstanceNode(
        id: NodeId('inst-1'),
        symbolDefinitionId: 'btn',
        variantSelections: {'Size': 'large'},
        overrides: {'children.0.fillColor': 0xFF0000},
      );
      final copy = original.clone(id: NodeId('inst-2'));

      expect(copy.id, 'inst-2');
      expect(copy.symbolDefinitionId, 'btn');
      expect(copy.variantSelections, {'Size': 'large'});

      // Independence.
      copy.variantSelections['Size'] = 'small';
      expect(original.variantSelections['Size'], 'large');
    });

    test('clone default id suffix', () {
      final original = SymbolInstanceNode(
        id: NodeId('inst-1'),
        symbolDefinitionId: 'btn',
      );
      final copy = original.clone();
      expect(copy.id, 'inst-1-clone');
    });
  });

  // =========================================================================
  // Round 2: SymbolRegistry.resolveInstance (Fix 2)
  // =========================================================================
  group('SymbolRegistry resolveInstance', () {
    test('resolves correct variant content', () {
      final def = _buildButtonDef();
      final registry = SymbolRegistry()..register(def);

      final instance = SymbolInstanceNode(
        id: NodeId('i1'),
        symbolDefinitionId: def.id,
        variantSelections: {'Size': 'large', 'State': 'hover'},
      );

      final resolved = registry.resolveInstance(instance);
      expect(resolved, isNotNull);
      expect(resolved!.name, 'large-hover');
    });

    test('returns null for unknown definition', () {
      final registry = SymbolRegistry();
      final instance = SymbolInstanceNode(
        id: NodeId('i1'),
        symbolDefinitionId: 'nonexistent',
      );
      expect(registry.resolveInstance(instance), isNull);
    });
  });

  // =========================================================================
  // Round 3: SymbolDefinition serialization roundtrip (Fix 2)
  // =========================================================================
  group('SymbolDefinition serialization roundtrip', () {
    test('roundtrip preserves variant properties and matrix', () {
      final def = _buildButtonDef();
      final json = def.toJson();
      final restored = SymbolDefinition.fromJson(
        json,
        CanvasNodeFactory.fromJson,
      );

      expect(restored.id, def.id);
      expect(restored.name, def.name);
      expect(restored.variantProperties.length, 2);
      expect(restored.variantProperties[0].name, 'Size');
      expect(restored.variantProperties[1].name, 'State');
      expect(restored.variants.length, 4);
      expect(
        restored.resolveContent({'Size': 'large', 'State': 'hover'}).name,
        'large-hover',
      );
    });

    test('roundtrip preserves empty variant definition', () {
      final def = SymbolDefinition(
        id: NodeId('empty'),
        name: 'Empty',
        content: _emptyGroup(),
      );
      final json = def.toJson();
      final restored = SymbolDefinition.fromJson(
        json,
        CanvasNodeFactory.fromJson,
      );
      expect(restored.variantProperties, isEmpty);
      expect(restored.variants, isEmpty);
    });
  });

  // =========================================================================
  // Round 3: Graceful removeVariantProperty (Fix 3)
  // =========================================================================
  group('SymbolDefinition removeVariantProperty', () {
    test('returns false for missing property', () {
      final def = _buildButtonDef();
      expect(def.removeVariantProperty('nonexistent-id'), false);
      expect(def.variantProperties.length, 2);
    });

    test('returns true and removes property', () {
      final def = _buildButtonDef();
      final sizeProp = def.variantProperties.firstWhere(
        (p) => p.name == 'Size',
      );
      expect(def.removeVariantProperty(sizeProp.id), true);
      expect(def.variantProperties.length, 1);
    });
  });

  // =========================================================================
  // Round 3: allCombinations excludes text/instanceSwap (Fix 5)
  // =========================================================================
  group('allCombinations excludes free-form axes', () {
    test('text property does not multiply combinations', () {
      final def = SymbolDefinition(
        id: NodeId('x'),
        name: 'X',
        content: _emptyGroup(),
        variantProperties: [
          VariantProperty.variant(name: 'Size', options: ['small', 'large']),
          VariantProperty.text(name: 'Label', defaultValue: 'hi'),
        ],
      );
      // Only 2 combos from Size, text is ignored.
      expect(def.allCombinations.length, 2);
      // Combos should not contain 'Label'.
      for (final combo in def.allCombinations) {
        expect(combo.containsKey('Label'), false);
      }
    });

    test('instanceSwap property does not multiply combinations', () {
      final def = SymbolDefinition(
        id: NodeId('x'),
        name: 'X',
        content: _emptyGroup(),
        variantProperties: [
          VariantProperty.boolean(name: 'Active'),
          VariantProperty.instanceSwap(
            name: 'Icon',
            defaultSymbolId: 'sym-star',
          ),
        ],
      );
      // Only 2 combos from boolean, instanceSwap is ignored.
      expect(def.allCombinations.length, 2);
    });

    test('only free-form axes gives single empty combo', () {
      final def = SymbolDefinition(
        id: NodeId('x'),
        name: 'X',
        content: _emptyGroup(),
        variantProperties: [VariantProperty.text(name: 'T')],
      );
      expect(def.allCombinations.length, 1);
      expect(def.allCombinations.first, isEmpty);
    });
  });

  // =========================================================================
  // Round 3: Const map safety (Fix 6)
  // =========================================================================
  group('SymbolInstanceNode const map safety', () {
    test('default empty overrides are mutable', () {
      final instance = SymbolInstanceNode(id: NodeId('i1'), symbolDefinitionId: 'btn');
      // Should NOT throw (was const {} before).
      instance.overrides['key'] = 'value';
      expect(instance.overrides['key'], 'value');
    });

    test('default empty variantSelections are mutable', () {
      final instance = SymbolInstanceNode(id: NodeId('i1'), symbolDefinitionId: 'btn');
      instance.variantSelections['Size'] = 'large';
      expect(instance.variantSelections['Size'], 'large');
    });
  });

  // =========================================================================
  // Round 3: Orphan detection (Fix 7)
  // =========================================================================
  group('SymbolRegistry orphan detection', () {
    test('isOrphan returns true for missing definition', () {
      final registry = SymbolRegistry();
      final instance = SymbolInstanceNode(
        id: NodeId('i1'),
        symbolDefinitionId: 'deleted-def',
      );
      expect(registry.isOrphan(instance), true);
    });

    test('isOrphan returns false for registered definition', () {
      final def = _buildButtonDef();
      final registry = SymbolRegistry()..register(def);
      final instance = SymbolInstanceNode(id: NodeId('i1'), symbolDefinitionId: def.id);
      expect(registry.isOrphan(instance), false);
    });

    test('remove returns bool', () {
      final def = _buildButtonDef();
      final registry = SymbolRegistry()..register(def);
      expect(registry.remove(def.id), true);
      expect(registry.remove(def.id), false);
    });
  });

  // =========================================================================
  // Round 3: VariantContent key recomputation (Fix 8)
  // =========================================================================
  group('VariantContent key recomputation', () {
    test('fromJson recomputes key from propertyValues', () {
      // Simulate a stored JSON with a wrong variantKey.
      final json = {
        'variantKey': 'WRONG-KEY',
        'propertyValues': {'Size': 'large', 'State': 'hover'},
        'content': {'nodeType': 'group', 'id': 'g1'},
      };
      final vc = VariantContent.fromJson(json, CanvasNodeFactory.fromJson);
      // Should use computed key, not the stored one.
      expect(vc.variantKey, 'Size=large,State=hover');
    });
  });

  // =========================================================================
  // Round 3: Dynamic localBounds (Fix 1)
  // =========================================================================
  group('SymbolInstanceNode resolvedBounds', () {
    test('localBounds returns default when resolvedBounds is null', () {
      final instance = SymbolInstanceNode(id: NodeId('i1'), symbolDefinitionId: 'btn');
      expect(instance.localBounds, const Rect.fromLTWH(0, 0, 100, 100));
    });

    test('localBounds returns resolvedBounds when set', () {
      final instance = SymbolInstanceNode(id: NodeId('i1'), symbolDefinitionId: 'btn');
      instance.resolvedBounds = const Rect.fromLTWH(0, 0, 200, 50);
      expect(instance.localBounds, const Rect.fromLTWH(0, 0, 200, 50));
    });
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

GroupNode _emptyGroup() => GroupNode(id: NodeId('empty-group'));

GroupNode _namedGroup(String name) => GroupNode(id: NodeId('group-$name'), name: name);

/// Helper: builds a standard Button definition with 2×2 variant matrix.
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
