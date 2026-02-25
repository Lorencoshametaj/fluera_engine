import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/nodes/group_node.dart';
import 'package:nebula_engine/src/core/nodes/symbol_system.dart';
import 'package:nebula_engine/src/core/nodes/variant_property.dart';
import 'package:nebula_engine/src/core/scene_graph/node_id.dart';

// =============================================================================
// Helpers
// =============================================================================

GroupNode _makeGroup(String id) => GroupNode(id: NodeId(id));

VariantProperty _enumProp(
  String name,
  List<String> options, [
  String? defaultValue,
]) {
  return VariantProperty(
    name: name,
    type: VariantPropertyType.variant,
    options: options,
    defaultValue: defaultValue ?? options.first,
  );
}

SymbolDefinition _makeSymbol({
  String id = 'sym1',
  String name = 'Button',
  List<VariantProperty> variantProperties = const [],
}) {
  return SymbolDefinition(
    id: id,
    name: name,
    content: _makeGroup('content'),
    overridableProps: ['text', 'fillColor'],
    description: 'A test symbol',
    tags: ['ui', 'button'],
    variantProperties: variantProperties,
  );
}

// =============================================================================
// Tests
// =============================================================================

void main() {
  // ===========================================================================
  // SymbolDefinition — basic
  // ===========================================================================

  group('SymbolDefinition - basic', () {
    test('construction sets all fields', () {
      final sym = _makeSymbol();
      expect(sym.id, 'sym1');
      expect(sym.name, 'Button');
      expect(sym.overridableProps, ['text', 'fillColor']);
      expect(sym.description, 'A test symbol');
      expect(sym.tags, ['ui', 'button']);
      expect(sym.hasVariants, isFalse);
    });

    test('resolveContent returns base content when no variants', () {
      final sym = _makeSymbol();
      final resolved = sym.resolveContent({});
      expect(resolved.id, 'content');
    });

    test('toJson includes all fields', () {
      final sym = _makeSymbol();
      final json = sym.toJson();
      expect(json['id'], 'sym1');
      expect(json['name'], 'Button');
      expect(json['overridableProps'], ['text', 'fillColor']);
      expect(json['tags'], ['ui', 'button']);
    });
  });

  // ===========================================================================
  // SymbolDefinition — variant management
  // ===========================================================================

  group('SymbolDefinition - variant management', () {
    test('addVariantProperty adds axis', () {
      final sym = _makeSymbol();
      final prop = _enumProp('Size', ['small', 'medium', 'large'], 'medium');
      sym.addVariantProperty(prop);
      expect(sym.hasVariants, isTrue);
      expect(sym.variantProperties.length, 1);
      expect(sym.variantProperties.first.name, 'Size');
    });

    test('addVariantProperty rejects duplicate name', () {
      final sym = _makeSymbol();
      sym.addVariantProperty(_enumProp('Size', ['s', 'm']));
      sym.addVariantProperty(_enumProp('Size', ['a', 'b']));
      expect(sym.variantProperties.length, 1); // No duplicate
    });

    test('setVariant and resolveContent', () {
      final sym = _makeSymbol(
        variantProperties: [
          _enumProp('Size', ['small', 'large'], 'small'),
        ],
      );

      final largeContent = _makeGroup('large-content');
      sym.setVariant({'Size': 'large'}, largeContent);

      final resolved = sym.resolveContent({'Size': 'large'});
      expect(resolved.id, 'large-content');
    });

    test('resolveContent falls back to default variant', () {
      final sym = _makeSymbol(
        variantProperties: [
          _enumProp('Size', ['small', 'large'], 'small'),
        ],
      );

      final defaultContent = _makeGroup('default-content');
      sym.setVariant({'Size': 'small'}, defaultContent);

      // Request unknown combo → falls back to default
      final resolved = sym.resolveContent({'Size': 'unknown'});
      expect(resolved.id, 'default-content');
    });

    test('resolveContent falls back to base content if no variants match', () {
      final sym = _makeSymbol(
        variantProperties: [
          _enumProp('Size', ['small', 'large'], 'small'),
        ],
      );

      // No variants set, falls back to base content
      final resolved = sym.resolveContent({'Size': 'large'});
      expect(resolved.id, 'content');
    });

    test('removeVariant removes entry', () {
      final sym = _makeSymbol(
        variantProperties: [
          _enumProp('Size', ['small', 'large']),
        ],
      );
      sym.setVariant({'Size': 'small'}, _makeGroup('small-g'));
      expect(sym.variants.length, 1);

      final removed = sym.removeVariant({'Size': 'small'});
      expect(removed, isTrue);
      expect(sym.variants.length, 0);
    });

    test('removeVariantProperty removes axis and related variants', () {
      final sym = _makeSymbol(
        variantProperties: [
          _enumProp('Size', ['small', 'large']),
        ],
      );
      sym.setVariant({'Size': 'small'}, _makeGroup('g'));

      final propId = sym.variantProperties.first.id;
      final removed = sym.removeVariantProperty(propId);
      expect(removed, isTrue);
      expect(sym.variantProperties, isEmpty);
      expect(sym.variants, isEmpty);
    });
  });

  // ===========================================================================
  // SymbolDefinition — variant matrix
  // ===========================================================================

  group('SymbolDefinition - variant matrix', () {
    test('allCombinations generates Cartesian product', () {
      final sym = _makeSymbol(
        variantProperties: [
          _enumProp('Size', ['small', 'large']),
          _enumProp('State', ['default', 'hover']),
        ],
      );
      final combos = sym.allCombinations;
      // 2 x 2 = 4
      expect(combos.length, 4);
    });

    test('missingVariantKeys detects incomplete matrix', () {
      final sym = _makeSymbol(
        variantProperties: [
          _enumProp('Size', ['small', 'large']),
        ],
      );
      sym.setVariant({'Size': 'small'}, _makeGroup('g'));
      expect(sym.missingVariantKeys.length, 1); // 'large' is missing
      expect(sym.isMatrixComplete, isFalse);
    });

    test('isMatrixComplete when all combos present', () {
      final sym = _makeSymbol(
        variantProperties: [
          _enumProp('Size', ['small', 'large']),
        ],
      );
      sym.setVariant({'Size': 'small'}, _makeGroup('g1'));
      sym.setVariant({'Size': 'large'}, _makeGroup('g2'));
      expect(sym.isMatrixComplete, isTrue);
    });
  });

  // ===========================================================================
  // SymbolDefinition — rename and reorder
  // ===========================================================================

  group('SymbolDefinition - rename/reorder', () {
    test('renameVariantOption updates keys', () {
      final sym = _makeSymbol(
        variantProperties: [
          _enumProp('Size', ['small', 'large']),
        ],
      );
      sym.setVariant({'Size': 'small'}, _makeGroup('g'));
      final propId = sym.variantProperties.first.id;

      final ok = sym.renameVariantOption(propId, 'small', 'tiny');
      expect(ok, isTrue);
      expect(sym.variantProperties.first.options, contains('tiny'));
      expect(sym.variantProperties.first.options, isNot(contains('small')));
      // Old key gone, new key present
      expect(
        sym.lookupVariant(VariantContent.buildVariantKey({'Size': 'small'})),
        isNull,
      );
      expect(
        sym.lookupVariant(VariantContent.buildVariantKey({'Size': 'tiny'})),
        isNotNull,
      );
    });

    test('renameVariantPropertyAxis updates keys', () {
      final sym = _makeSymbol(
        variantProperties: [
          _enumProp('Size', ['small', 'large']),
        ],
      );
      sym.setVariant({'Size': 'small'}, _makeGroup('g'));
      final propId = sym.variantProperties.first.id;

      final ok = sym.renameVariantPropertyAxis(propId, 'Dimension');
      expect(ok, isTrue);
      expect(sym.variantProperties.first.name, 'Dimension');
      // Key should now use 'Dimension=small'
      expect(
        sym.lookupVariant(
          VariantContent.buildVariantKey({'Dimension': 'small'}),
        ),
        isNotNull,
      );
    });

    test('reorderVariantProperty moves property', () {
      final sym = _makeSymbol(
        variantProperties: [
          _enumProp('A', ['a1', 'a2']),
          _enumProp('B', ['b1', 'b2']),
        ],
      );
      final bId = sym.variantProperties[1].id;
      sym.reorderVariantProperty(bId, 0);
      expect(sym.variantProperties[0].name, 'B');
      expect(sym.variantProperties[1].name, 'A');
    });
  });

  // ===========================================================================
  // SymbolDefinition — copyWith
  // ===========================================================================

  group('SymbolDefinition - copyWith', () {
    test('creates independent copy', () {
      final sym = _makeSymbol(
        variantProperties: [
          _enumProp('Size', ['small', 'large']),
        ],
      );
      sym.setVariant({'Size': 'small'}, _makeGroup('g'));

      final copy = sym.copyWith(id: 'copy1', name: 'Button Copy');
      expect(copy.id, 'copy1');
      expect(copy.name, 'Button Copy');
      expect(copy.variants.length, sym.variants.length);
      // Independent: modifying copy doesn't affect original
      copy.setVariant({'Size': 'large'}, _makeGroup('g2'));
      expect(copy.variants.length, 2);
      expect(sym.variants.length, 1);
    });
  });

  // ===========================================================================
  // SymbolInstanceNode
  // ===========================================================================

  group('SymbolInstanceNode', () {
    test('construction and defaults', () {
      final instance = SymbolInstanceNode(
        id: NodeId('inst1'),
        symbolDefinitionId: 'sym1',
      );
      expect(instance.symbolDefinitionId, 'sym1');
      expect(instance.overrides, isEmpty);
      expect(instance.variantSelections, isEmpty);
      expect(instance.localBounds.width, 100); // default fallback
    });

    test('clone creates independent copy', () {
      final instance = SymbolInstanceNode(
        id: NodeId('inst1'),
        symbolDefinitionId: 'sym1',
        overrides: {'text': 'Buy'},
        variantSelections: {'Size': 'large'},
      );

      final clone = instance.clone(id: 'inst2');
      expect(clone.id, 'inst2');
      expect(clone.symbolDefinitionId, 'sym1');
      expect(clone.overrides['text'], 'Buy');
      expect(clone.variantSelections['Size'], 'large');

      // Independent
      clone.overrides['text'] = 'Sell';
      expect(instance.overrides['text'], 'Buy');
    });

    test('toJson and fromJson roundtrip', () {
      final instance = SymbolInstanceNode(
        id: NodeId('inst1'),
        symbolDefinitionId: 'sym1',
        overrides: {'text': 'Hello'},
        variantSelections: {'Size': 'large'},
      );

      final json = instance.toJson();
      expect(json['nodeType'], 'symbolInstance');
      expect(json['symbolDefinitionId'], 'sym1');

      final restored = SymbolInstanceNode.fromJson(json);
      expect(restored.id, 'inst1');
      expect(restored.symbolDefinitionId, 'sym1');
      expect(restored.overrides['text'], 'Hello');
      expect(restored.variantSelections['Size'], 'large');
    });

    test('validateSelections finds invalid selections', () {
      final def = _makeSymbol(
        variantProperties: [
          _enumProp('Size', ['small', 'large']),
        ],
      );

      final instance = SymbolInstanceNode(
        id: NodeId('inst1'),
        symbolDefinitionId: 'sym1',
        variantSelections: {'Size': 'invalid', 'Ghost': 'x'},
      );

      final invalid = instance.validateSelections(def);
      expect(invalid, contains('Size'));
      expect(invalid, contains('Ghost'));
    });

    test('sanitizeSelections corrects invalid selections', () {
      final def = _makeSymbol(
        variantProperties: [
          _enumProp('Size', ['small', 'large']),
        ],
      );

      final instance = SymbolInstanceNode(
        id: NodeId('inst1'),
        symbolDefinitionId: 'sym1',
        variantSelections: {'Size': 'invalid', 'Ghost': 'x'},
      );

      final corrected = instance.sanitizeSelections(def);
      expect(corrected, 2); // 'Ghost' removed, 'Size' reset to default
      expect(instance.variantSelections.containsKey('Ghost'), isFalse);
      expect(instance.variantSelections['Size'], 'small'); // default
    });
  });

  // ===========================================================================
  // SymbolRegistry
  // ===========================================================================

  group('SymbolRegistry', () {
    test('register and lookup', () {
      final registry = SymbolRegistry();
      final sym = _makeSymbol(id: 'sym1');
      registry.register(sym);

      expect(registry.count, 1);
      expect(registry.lookup('sym1'), isNotNull);
      expect(registry.lookup('sym1')!.name, 'Button');
      expect(registry.contains('sym1'), isTrue);
    });

    test('remove definition', () {
      final registry = SymbolRegistry();
      registry.register(_makeSymbol(id: 'sym1'));
      expect(registry.remove('sym1'), isTrue);
      expect(registry.count, 0);
      expect(registry.lookup('sym1'), isNull);
    });

    test('isOrphan detects missing definitions', () {
      final registry = SymbolRegistry();
      final instance = SymbolInstanceNode(
        id: NodeId('inst1'),
        symbolDefinitionId: 'missing',
      );
      expect(registry.isOrphan(instance), isTrue);

      registry.register(_makeSymbol(id: 'missing'));
      expect(registry.isOrphan(instance), isFalse);
    });

    test('resolveInstance returns resolved content', () {
      final registry = SymbolRegistry();
      final sym = _makeSymbol(
        id: 'sym1',
        variantProperties: [
          _enumProp('Size', ['small', 'large']),
        ],
      );
      sym.setVariant({'Size': 'large'}, _makeGroup('large-g'));
      registry.register(sym);

      final instance = SymbolInstanceNode(
        id: NodeId('inst1'),
        symbolDefinitionId: 'sym1',
        variantSelections: {'Size': 'large'},
      );
      final resolved = registry.resolveInstance(instance);
      expect(resolved, isNotNull);
      expect(resolved!.id, 'large-g');
    });

    test('resolveInstance returns null for orphan', () {
      final registry = SymbolRegistry();
      final instance = SymbolInstanceNode(
        id: NodeId('inst1'),
        symbolDefinitionId: 'missing',
      );
      expect(registry.resolveInstance(instance), isNull);
    });
  });

  // ===========================================================================
  // VariantContent
  // ===========================================================================

  group('VariantContent', () {
    test('buildVariantKey sorts alphabetically', () {
      final key = VariantContent.buildVariantKey({
        'state': 'hover',
        'size': 'medium',
      });
      expect(key, 'size=medium,state=hover');
    });

    test('buildVariantKey with single property', () {
      final key = VariantContent.buildVariantKey({'size': 'large'});
      expect(key, 'size=large');
    });

    test('buildVariantKey empty map', () {
      final key = VariantContent.buildVariantKey({});
      expect(key, '');
    });
  });
}
