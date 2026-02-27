import 'package:fluera_engine/src/core/scene_graph/node_id.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/scene_graph/canvas_node.dart';
import 'package:fluera_engine/src/core/scene_graph/node_visitor.dart';
import 'package:fluera_engine/src/core/scene_graph/scene_graph.dart';
import 'package:fluera_engine/src/systems/design_variables.dart';
import 'package:fluera_engine/src/systems/variable_binding.dart';
import 'package:fluera_engine/src/systems/variable_resolver.dart';

/// Concrete leaf node for testing.
class _TestNode extends CanvasNode {
  Color? fillColor;
  double? customSpacing;

  _TestNode({required super.id, super.name = ''});

  @override
  Rect get localBounds => Rect.zero;

  @override
  Map<String, dynamic> toJson() => {'id': id, 'nodeType': 'test'};

  @override
  R accept<R>(NodeVisitor<R> visitor) =>
      throw UnimplementedError('not needed for tests');
}

void main() {
  // =========================================================================
  // NodePropertySetter
  // =========================================================================

  group('NodePropertySetter', () {
    test('applies opacity', () {
      final node = _TestNode(id: NodeId('n1'));
      final result = NodePropertySetter.apply(node, 'opacity', 0.5);
      expect(result, isTrue);
      expect(node.opacity, 0.5);
    });

    test('applies isVisible', () {
      final node = _TestNode(id: NodeId('n1'));
      final result = NodePropertySetter.apply(node, 'isVisible', false);
      expect(result, isTrue);
      expect(node.isVisible, false);
    });

    test('applies isLocked', () {
      final node = _TestNode(id: NodeId('n1'));
      final result = NodePropertySetter.apply(node, 'isLocked', true);
      expect(result, isTrue);
      expect(node.isLocked, true);
    });

    test('applies blendMode from string', () {
      final node = _TestNode(id: NodeId('n1'));
      final result = NodePropertySetter.apply(node, 'blendMode', 'multiply');
      expect(result, isTrue);
      expect(node.blendMode, ui.BlendMode.multiply);
    });

    test('applies name', () {
      final node = _TestNode(id: NodeId('n1'));
      final result = NodePropertySetter.apply(node, 'name', 'New Name');
      expect(result, isTrue);
      expect(node.name, 'New Name');
    });

    test('returns false for unknown property', () {
      final node = _TestNode(id: NodeId('n1'));
      final result = NodePropertySetter.apply(node, 'fillColor', 0xFF0000FF);
      expect(result, isFalse);
    });

    test('returns false for wrong value type', () {
      final node = _TestNode(id: NodeId('n1'));
      final result = NodePropertySetter.apply(node, 'opacity', 'not-a-number');
      expect(result, isFalse);
    });
  });

  // =========================================================================
  // VariableResolver
  // =========================================================================

  group('VariableResolver', () {
    late VariableCollection collection;
    late VariableBindingRegistry bindings;

    setUp(() {
      collection = VariableCollection(
        id: NodeId('themes'),
        name: 'Themes',
        modes: [
          VariableMode(id: NodeId('light'), name: 'Light'),
          VariableMode(id: NodeId('dark'), name: 'Dark'),
        ],
        variables: [
          DesignVariable(
            id: NodeId('bg-opacity'),
            name: 'BG Opacity',
            type: DesignVariableType.number,
            values: {'light': 1.0, 'dark': 0.8},
          ),
          DesignVariable(
            id: NodeId('is-visible'),
            name: 'Is Visible',
            type: DesignVariableType.boolean,
            values: {'light': true, 'dark': false},
          ),
        ],
      );

      bindings = VariableBindingRegistry();
    });

    // ── Collection management ────────────────────────────────────────────

    test('initializes active mode to default', () {
      final resolver = VariableResolver(collections: [collection]);
      expect(resolver.getActiveMode('themes'), 'light');
    });

    test('addCollection and removeCollection', () {
      final resolver = VariableResolver();
      resolver.addCollection(collection);
      expect(resolver.collections.length, 1);
      expect(resolver.getActiveMode('themes'), 'light');

      resolver.removeCollection('themes');
      expect(resolver.collections, isEmpty);
      expect(resolver.getActiveMode('themes'), isNull);
    });

    test('addCollection skips duplicates', () {
      final resolver = VariableResolver(collections: [collection]);
      resolver.addCollection(collection);
      expect(resolver.collections.length, 1);
    });

    test('findCollection finds by id', () {
      final resolver = VariableResolver(collections: [collection]);
      expect(resolver.findCollection('themes'), isNotNull);
      expect(resolver.findCollection('nonexistent'), isNull);
    });

    // ── Mode switching ───────────────────────────────────────────────────

    test('setActiveMode changes the active mode', () {
      final resolver = VariableResolver(collections: [collection]);
      resolver.setActiveMode('themes', 'dark');
      expect(resolver.getActiveMode('themes'), 'dark');
    });

    test('setActiveMode ignores invalid mode', () {
      final resolver = VariableResolver(collections: [collection]);
      resolver.setActiveMode('themes', 'nonexistent');
      expect(resolver.getActiveMode('themes'), 'light'); // unchanged
    });

    test('setActiveMode ignores invalid collection', () {
      final resolver = VariableResolver(collections: [collection]);
      resolver.setActiveMode('nonexistent', 'dark');
      // No error thrown.
    });

    test('setActiveMode notifies listeners', () {
      final resolver = VariableResolver(collections: [collection]);
      int notifyCount = 0;
      resolver.addListener(() => notifyCount++);

      resolver.setActiveMode('themes', 'dark');
      expect(notifyCount, 1);
    });

    test('setActiveMode does not notify for same mode', () {
      final resolver = VariableResolver(collections: [collection]);
      int notifyCount = 0;
      resolver.addListener(() => notifyCount++);

      resolver.setActiveMode('themes', 'light'); // already active
      expect(notifyCount, 0);
    });

    // ── Resolution ───────────────────────────────────────────────────────

    test('resolveVariable returns value for active mode', () {
      final resolver = VariableResolver(collections: [collection]);
      expect(resolver.resolveVariable('bg-opacity'), 1.0);

      resolver.setActiveMode('themes', 'dark');
      expect(resolver.resolveVariable('bg-opacity'), 0.8);
    });

    test('resolveVariable returns null for unknown variable', () {
      final resolver = VariableResolver(collections: [collection]);
      expect(resolver.resolveVariable('nonexistent'), isNull);
    });

    // ── Resolve and Apply ────────────────────────────────────────────────

    test('resolveAndApply sets node properties', () {
      bindings.addBinding(
        const VariableBinding(
          variableId: 'bg-opacity',
          nodeId: 'n1',
          nodeProperty: 'opacity',
        ),
      );
      bindings.addBinding(
        const VariableBinding(
          variableId: 'is-visible',
          nodeId: 'n1',
          nodeProperty: 'isVisible',
        ),
      );

      final node = _TestNode(id: NodeId('n1'));
      final resolver = VariableResolver(
        collections: [collection],
        bindings: bindings,
      );

      // Light mode — opacity 1.0, isVisible true
      resolver.resolveAndApply((id) => id == 'n1' ? node : null);
      expect(node.opacity, 1.0);
      expect(node.isVisible, true);

      // Switch to dark mode — opacity 0.8, isVisible false
      resolver.setActiveMode('themes', 'dark');
      resolver.resolveAndApply((id) => id == 'n1' ? node : null);
      expect(node.opacity, 0.8);
      expect(node.isVisible, false);
    });

    test('resolveAndApply skips missing nodes gracefully', () {
      bindings.addBinding(
        const VariableBinding(
          variableId: 'bg-opacity',
          nodeId: 'missing-node',
          nodeProperty: 'opacity',
        ),
      );
      final resolver = VariableResolver(
        collections: [collection],
        bindings: bindings,
      );
      // Should not throw.
      resolver.resolveAndApply((_) => null);
    });

    // ── Custom Property Applier ──────────────────────────────────────────

    test('customPropertyApplier handles subclass properties', () {
      final colorCollection = VariableCollection(
        id: NodeId('colors'),
        name: 'Colors',
        modes: [VariableMode(id: NodeId('default'), name: 'Default')],
        variables: [
          DesignVariable(
            id: NodeId('fill'),
            name: 'Fill Color',
            type: DesignVariableType.color,
            values: {'default': 0xFF00FF00},
          ),
        ],
      );

      bindings.addBinding(
        const VariableBinding(
          variableId: 'fill',
          nodeId: 'n1',
          nodeProperty: 'fillColor',
        ),
      );

      final node = _TestNode(id: NodeId('n1'));
      final resolver = VariableResolver(
        collections: [colorCollection],
        bindings: bindings,
        customPropertyApplier: (n, property, value) {
          if (n is _TestNode && property == 'fillColor' && value is int) {
            n.fillColor = Color(value);
            return true;
          }
          return false;
        },
      );

      resolver.resolveAndApply((id) => id == 'n1' ? node : null);
      expect(node.fillColor, const Color(0xFF00FF00));
    });

    // ── resolveAndApplyForCollection ──────────────────────────────────────

    test('resolveAndApplyForCollection only applies for that collection', () {
      final otherCollection = VariableCollection(
        id: NodeId('spacing'),
        name: 'Spacing',
        modes: [VariableMode(id: NodeId('default'), name: 'Default')],
        variables: [
          DesignVariable(
            id: NodeId('space-1'),
            name: 'Spacing 1',
            type: DesignVariableType.number,
            values: {'default': 0.5},
          ),
        ],
      );

      bindings.addBinding(
        const VariableBinding(
          variableId: 'bg-opacity',
          nodeId: 'n1',
          nodeProperty: 'opacity',
        ),
      );
      bindings.addBinding(
        const VariableBinding(
          variableId: 'space-1',
          nodeId: 'n2',
          nodeProperty: 'opacity',
        ),
      );

      final n1 = _TestNode(id: NodeId('n1'));
      final n2 = _TestNode(id: NodeId('n2'));
      n1.opacity = 0.0;
      n2.opacity = 0.0;

      final resolver = VariableResolver(
        collections: [collection, otherCollection],
        bindings: bindings,
      );

      // Only apply for 'themes' collection.
      resolver.resolveAndApplyForCollection('themes', (id) {
        if (id == 'n1') return n1;
        if (id == 'n2') return n2;
        return null;
      });

      expect(n1.opacity, 1.0); // themes applied
      expect(n2.opacity, 0.0); // spacing NOT applied
    });

    // ── Active Modes Serialization ──────────────────────────────────────

    test('activeModesToJson / loadActiveModes round-trip', () {
      final resolver = VariableResolver(collections: [collection]);
      resolver.setActiveMode('themes', 'dark');

      final json = resolver.activeModesToJson();
      expect(json['themes'], 'dark');

      final resolver2 = VariableResolver(collections: [collection]);
      resolver2.loadActiveModes(json);
      expect(resolver2.getActiveMode('themes'), 'dark');
    });
  });

  // =========================================================================
  // SceneGraph Integration
  // =========================================================================

  group('SceneGraph variable integration', () {
    test('toJson / fromJson round-trips variable data', () {
      final sg = SceneGraph();

      // Add a collection with variables.
      sg.variableCollections.add(
        VariableCollection(
          id: NodeId('themes'),
          name: 'Themes',
          modes: [
            VariableMode(id: NodeId('light'), name: 'Light'),
            VariableMode(id: NodeId('dark'), name: 'Dark'),
          ],
          variables: [
            DesignVariable(
              id: NodeId('opacity-var'),
              name: 'Opacity',
              type: DesignVariableType.number,
              values: {'light': 1.0, 'dark': 0.7},
            ),
          ],
        ),
      );

      // Add a binding.
      sg.variableBindings.addBinding(
        const VariableBinding(
          variableId: 'opacity-var',
          nodeId: 'some-node',
          nodeProperty: 'opacity',
        ),
      );

      // Set active mode to dark.
      sg.variableResolver.setActiveMode('themes', 'dark');

      // Serialize.
      final json = sg.toJson();

      // Deserialize.
      final restored = SceneGraph.fromJson(json);

      expect(restored.variableCollections.length, 1);
      expect(restored.variableCollections.first.id, 'themes');
      expect(restored.variableCollections.first.variableCount, 1);
      expect(restored.variableBindings.bindingCount, 1);
      expect(restored.variableResolver.getActiveMode('themes'), 'dark');

      // Clean up.
      sg.dispose();
      restored.dispose();
    });

    test('toJson omits variables when empty', () {
      final sg = SceneGraph();
      final json = sg.toJson();
      expect(json.containsKey('variableCollections'), isFalse);
      expect(json.containsKey('variableBindings'), isFalse);
      expect(json.containsKey('variableActiveModes'), isFalse);
      sg.dispose();
    });

    test('dispose cleans up variable resources', () {
      final sg = SceneGraph();
      sg.variableCollections.add(VariableCollection(id: NodeId('c1'), name: 'Test'));
      sg.variableBindings.addBinding(
        const VariableBinding(
          variableId: 'v1',
          nodeId: 'n1',
          nodeProperty: 'opacity',
        ),
      );

      sg.dispose();
      expect(sg.variableCollections, isEmpty);
      expect(sg.variableBindings.bindingCount, 0);
    });
  });

  // =========================================================================
  // Alias Resolution
  // =========================================================================

  group('Alias resolution', () {
    test('resolveVariable follows alias chain', () {
      final collection = VariableCollection(
        id: NodeId('tokens'),
        name: 'Tokens',
        modes: [VariableMode(id: NodeId('default'), name: 'Default')],
        variables: [
          DesignVariable(
            id: NodeId('brand-blue'),
            name: 'Brand Blue',
            type: DesignVariableType.color,
            values: {'default': 0xFF0000FF},
          ),
          DesignVariable(
            id: NodeId('primary'),
            name: 'Primary',
            type: DesignVariableType.color,
            aliasVariableId: 'brand-blue', // → brand-blue
          ),
        ],
      );

      final resolver = VariableResolver(collections: [collection]);
      expect(resolver.resolveVariable('primary'), 0xFF0000FF);
    });

    test('resolveVariable handles multi-level alias', () {
      final collection = VariableCollection(
        id: NodeId('tokens'),
        name: 'Tokens',
        modes: [VariableMode(id: NodeId('default'), name: 'Default')],
        variables: [
          DesignVariable(
            id: NodeId('blue-500'),
            name: 'Blue 500',
            type: DesignVariableType.color,
            values: {'default': 0xFF0000FF},
          ),
          DesignVariable(
            id: NodeId('brand-primary'),
            name: 'Brand Primary',
            type: DesignVariableType.color,
            aliasVariableId: 'blue-500',
          ),
          DesignVariable(
            id: NodeId('button-bg'),
            name: 'Button BG',
            type: DesignVariableType.color,
            aliasVariableId: 'brand-primary', // → brand-primary → blue-500
          ),
        ],
      );

      final resolver = VariableResolver(collections: [collection]);
      expect(resolver.resolveVariable('button-bg'), 0xFF0000FF);
    });

    test('resolveVariable detects circular aliases and returns null', () {
      final collection = VariableCollection(
        id: NodeId('tokens'),
        name: 'Tokens',
        modes: [VariableMode(id: NodeId('default'), name: 'Default')],
        variables: [
          DesignVariable(
            id: NodeId('a'),
            name: 'A',
            type: DesignVariableType.color,
            aliasVariableId: 'b',
          ),
          DesignVariable(
            id: NodeId('b'),
            name: 'B',
            type: DesignVariableType.color,
            aliasVariableId: 'a', // circular: a → b → a
          ),
        ],
      );

      final resolver = VariableResolver(collections: [collection]);
      expect(resolver.resolveVariable('a'), isNull);
    });

    test('resolveVariable returns null for alias to missing variable', () {
      final collection = VariableCollection(
        id: NodeId('tokens'),
        name: 'Tokens',
        modes: [VariableMode(id: NodeId('default'), name: 'Default')],
        variables: [
          DesignVariable(
            id: NodeId('orphan'),
            name: 'Orphan',
            type: DesignVariableType.color,
            aliasVariableId: 'nonexistent',
          ),
        ],
      );

      final resolver = VariableResolver(collections: [collection]);
      expect(resolver.resolveVariable('orphan'), isNull);
    });

    test('resolveVariable follows alias across collections', () {
      final primitives = VariableCollection(
        id: NodeId('primitives'),
        name: 'Primitives',
        modes: [VariableMode(id: NodeId('default'), name: 'Default')],
        variables: [
          DesignVariable(
            id: NodeId('blue-500'),
            name: 'Blue 500',
            type: DesignVariableType.color,
            values: {'default': 0xFF0000FF},
          ),
        ],
      );

      final semantic = VariableCollection(
        id: NodeId('semantic'),
        name: 'Semantic',
        modes: [VariableMode(id: NodeId('default'), name: 'Default')],
        variables: [
          DesignVariable(
            id: NodeId('primary'),
            name: 'Primary',
            type: DesignVariableType.color,
            aliasVariableId: 'blue-500', // alias to primitive collection
          ),
        ],
      );

      final resolver = VariableResolver(collections: [primitives, semantic]);
      expect(resolver.resolveVariable('primary'), 0xFF0000FF);
    });
  });

  // =========================================================================
  // resolveAs<T>
  // =========================================================================

  group('resolveAs<T>', () {
    test('returns typed value when matching', () {
      final collection = VariableCollection(
        id: NodeId('c1'),
        name: 'Test',
        modes: [VariableMode(id: NodeId('default'), name: 'Default')],
        variables: [
          DesignVariable(
            id: NodeId('opacity'),
            name: 'Opacity',
            type: DesignVariableType.number,
            values: {'default': 0.75},
          ),
          DesignVariable(
            id: NodeId('color'),
            name: 'Color',
            type: DesignVariableType.color,
            values: {'default': 0xFF00FF00},
          ),
        ],
      );

      final resolver = VariableResolver(collections: [collection]);
      expect(resolver.resolveAs<double>('opacity'), 0.75);
      expect(resolver.resolveAs<int>('color'), 0xFF00FF00);
    });

    test('returns null for type mismatch', () {
      final collection = VariableCollection(
        id: NodeId('c1'),
        name: 'Test',
        modes: [VariableMode(id: NodeId('default'), name: 'Default')],
        variables: [
          DesignVariable(
            id: NodeId('color'),
            name: 'Color',
            type: DesignVariableType.color,
            values: {'default': 0xFF0000FF},
          ),
        ],
      );

      final resolver = VariableResolver(collections: [collection]);
      // int value requested as String → null
      expect(resolver.resolveAs<String>('color'), isNull);
    });

    test('returns null for missing variable', () {
      final resolver = VariableResolver();
      expect(resolver.resolveAs<double>('nonexistent'), isNull);
    });
  });

  // =========================================================================
  // Batch Mode Switching
  // =========================================================================

  group('Batch mode switching', () {
    test('beginBatch / endBatch fires single notification', () {
      final collection1 = VariableCollection(
        id: NodeId('themes'),
        name: 'Themes',
        modes: [
          VariableMode(id: NodeId('light'), name: 'Light'),
          VariableMode(id: NodeId('dark'), name: 'Dark'),
        ],
      );
      final collection2 = VariableCollection(
        id: NodeId('breakpoints'),
        name: 'Breakpoints',
        modes: [
          VariableMode(id: NodeId('desktop'), name: 'Desktop'),
          VariableMode(id: NodeId('mobile'), name: 'Mobile'),
        ],
      );

      final resolver = VariableResolver(
        collections: [collection1, collection2],
      );

      int notifyCount = 0;
      resolver.addListener(() => notifyCount++);

      resolver.beginBatch();
      resolver.setActiveMode('themes', 'dark');
      resolver.setActiveMode('breakpoints', 'mobile');
      expect(notifyCount, 0); // suppressed

      resolver.endBatch();
      expect(notifyCount, 1); // single notification
    });

    test('endBatch without changes does not notify', () {
      final collection = VariableCollection(
        id: NodeId('c1'),
        name: 'Test',
        modes: [
          VariableMode(id: NodeId('a'), name: 'A'),
          VariableMode(id: NodeId('b'), name: 'B'),
        ],
      );

      final resolver = VariableResolver(collections: [collection]);
      int notifyCount = 0;
      resolver.addListener(() => notifyCount++);

      resolver.beginBatch();
      // No mode changes inside batch.
      resolver.endBatch();
      expect(notifyCount, 0);
    });

    test('nested batches only fire on outermost endBatch', () {
      final collection = VariableCollection(
        id: NodeId('c1'),
        name: 'Test',
        modes: [
          VariableMode(id: NodeId('a'), name: 'A'),
          VariableMode(id: NodeId('b'), name: 'B'),
        ],
      );

      final resolver = VariableResolver(collections: [collection]);
      int notifyCount = 0;
      resolver.addListener(() => notifyCount++);

      resolver.beginBatch();
      resolver.beginBatch(); // nested
      resolver.setActiveMode('c1', 'b');
      resolver.endBatch(); // inner — no notify
      expect(notifyCount, 0);

      resolver.endBatch(); // outer — notify
      expect(notifyCount, 1);
    });

    test('extra endBatch calls are safe', () {
      final resolver = VariableResolver();
      // Should not throw.
      resolver.endBatch();
      resolver.endBatch();
    });
  });

  // =========================================================================
  // Mode Inheritance in Resolution
  // =========================================================================

  group('Mode inheritance resolution', () {
    test('falls back to parent mode value', () {
      final collection = VariableCollection(
        id: NodeId('themes'),
        name: 'Themes',
        modes: [
          VariableMode(id: NodeId('light'), name: 'Light'),
          VariableMode(id: NodeId('dark'), name: 'Dark', inheritsFrom: 'light'),
        ],
        variables: [
          DesignVariable(
            id: NodeId('color'),
            name: 'Color',
            type: DesignVariableType.color,
            values: {'light': 0xFFFFFFFF}, // only light has a value
          ),
        ],
      );

      final resolver = VariableResolver(collections: [collection]);
      resolver.setActiveMode('themes', 'dark');

      // Dark has no value — should inherit from light.
      expect(resolver.resolveVariable('color'), 0xFFFFFFFF);
    });

    test('child mode value overrides parent', () {
      final collection = VariableCollection(
        id: NodeId('themes'),
        name: 'Themes',
        modes: [
          VariableMode(id: NodeId('light'), name: 'Light'),
          VariableMode(id: NodeId('dark'), name: 'Dark', inheritsFrom: 'light'),
        ],
        variables: [
          DesignVariable(
            id: NodeId('color'),
            name: 'Color',
            type: DesignVariableType.color,
            values: {'light': 0xFFFFFFFF, 'dark': 0xFF000000},
          ),
        ],
      );

      final resolver = VariableResolver(collections: [collection]);
      resolver.setActiveMode('themes', 'dark');

      // Dark has its own value — should use it.
      expect(resolver.resolveVariable('color'), 0xFF000000);
    });

    test('multi-level inheritance: grandchild → child → parent', () {
      final collection = VariableCollection(
        id: NodeId('themes'),
        name: 'Themes',
        modes: [
          VariableMode(id: NodeId('base'), name: 'Base'),
          VariableMode(id: NodeId('dark'), name: 'Dark', inheritsFrom: 'base'),
          VariableMode(id: NodeId('dark-hc'), name: 'Dark HC', inheritsFrom: 'dark'),
        ],
        variables: [
          DesignVariable(
            id: NodeId('bg'),
            name: 'BG',
            type: DesignVariableType.color,
            values: {'base': 0xFFFFFFFF}, // only base has value
          ),
        ],
      );

      final resolver = VariableResolver(collections: [collection]);
      resolver.setActiveMode('themes', 'dark-hc');

      // dark-hc → dark → base
      expect(resolver.resolveVariable('bg'), 0xFFFFFFFF);
    });
  });

  // =========================================================================
  // onVariablesApplied
  // =========================================================================

  group('onVariablesApplied', () {
    test('fires after resolveAndApply', () {
      final resolver = VariableResolver(
        collections: [
          VariableCollection(
            id: NodeId('c1'),
            name: 'Test',
            modes: [VariableMode(id: NodeId('default'), name: 'Default')],
            variables: [
              DesignVariable(
                id: NodeId('v1'),
                name: 'V1',
                type: DesignVariableType.number,
                values: {'default': 1.0},
              ),
            ],
          ),
        ],
      );

      int callCount = 0;
      resolver.onVariablesApplied = () => callCount++;

      resolver.resolveAndApply((_) => null);
      expect(callCount, 1);
    });
  });

  // =========================================================================
  // Scope-Aware Apply
  // =========================================================================

  group('Scope-aware resolveAndApply', () {
    test('skips scoped variables when node is not a descendant', () {
      final collection = VariableCollection(
        id: NodeId('c1'),
        name: 'Test',
        modes: [VariableMode(id: NodeId('default'), name: 'Default')],
        variables: [
          DesignVariable(
            id: NodeId('scoped-opacity'),
            name: 'Scoped Opacity',
            type: DesignVariableType.number,
            scopeNodeId: 'frame-A',
            values: {'default': 0.5},
          ),
        ],
      );

      final bindings = VariableBindingRegistry();
      bindings.addBinding(
        const VariableBinding(
          variableId: 'scoped-opacity',
          nodeId: 'n1',
          nodeProperty: 'opacity',
        ),
      );

      final node = _TestNode(id: NodeId('n1'));
      node.opacity = 1.0;

      final resolver = VariableResolver(
        collections: [collection],
        bindings: bindings,
      );

      // n1 is NOT a descendant of frame-A.
      resolver.resolveAndApply(
        (id) => id == 'n1' ? node : null,
        ancestorChecker: (nodeId, ancestorId) => false,
      );

      // Opacity should NOT have been changed.
      expect(node.opacity, 1.0);
    });

    test('applies scoped variables when node IS a descendant', () {
      final collection = VariableCollection(
        id: NodeId('c1'),
        name: 'Test',
        modes: [VariableMode(id: NodeId('default'), name: 'Default')],
        variables: [
          DesignVariable(
            id: NodeId('scoped-opacity'),
            name: 'Scoped Opacity',
            type: DesignVariableType.number,
            scopeNodeId: 'frame-A',
            values: {'default': 0.5},
          ),
        ],
      );

      final bindings = VariableBindingRegistry();
      bindings.addBinding(
        const VariableBinding(
          variableId: 'scoped-opacity',
          nodeId: 'n1',
          nodeProperty: 'opacity',
        ),
      );

      final node = _TestNode(id: NodeId('n1'));
      node.opacity = 1.0;

      final resolver = VariableResolver(
        collections: [collection],
        bindings: bindings,
      );

      // n1 IS a descendant of frame-A.
      resolver.resolveAndApply(
        (id) => id == 'n1' ? node : null,
        ancestorChecker: (nodeId, ancestorId) => true,
      );

      expect(node.opacity, 0.5);
    });

    test('global variables apply regardless of scope checker', () {
      final collection = VariableCollection(
        id: NodeId('c1'),
        name: 'Test',
        modes: [VariableMode(id: NodeId('default'), name: 'Default')],
        variables: [
          DesignVariable(
            id: NodeId('global-opacity'),
            name: 'Global Opacity',
            type: DesignVariableType.number,
            // no scopeNodeId — global
            values: {'default': 0.3},
          ),
        ],
      );

      final bindings = VariableBindingRegistry();
      bindings.addBinding(
        const VariableBinding(
          variableId: 'global-opacity',
          nodeId: 'n1',
          nodeProperty: 'opacity',
        ),
      );

      final node = _TestNode(id: NodeId('n1'));
      node.opacity = 1.0;

      final resolver = VariableResolver(
        collections: [collection],
        bindings: bindings,
      );

      // Even with a strict ancestor checker, global variables apply.
      resolver.resolveAndApply(
        (id) => id == 'n1' ? node : null,
        ancestorChecker: (nodeId, ancestorId) => false,
      );

      expect(node.opacity, 0.3);
    });
  });

  // =========================================================================
  // Resolution Cache
  // =========================================================================

  group('Resolution cache', () {
    test('cached value is returned on second call', () {
      final collection = VariableCollection(
        id: NodeId('c1'),
        name: 'Test',
        modes: [VariableMode(id: NodeId('default'), name: 'Default')],
        variables: [
          DesignVariable(
            id: NodeId('v1'),
            name: 'V1',
            type: DesignVariableType.number,
            values: {'default': 42.0},
          ),
        ],
      );

      final resolver = VariableResolver(collections: [collection]);

      // First call — resolves.
      expect(resolver.resolveVariable('v1'), 42.0);
      // Second call — should hit cache (same result).
      expect(resolver.resolveVariable('v1'), 42.0);
    });

    test('cache is invalidated on mode change', () {
      final collection = VariableCollection(
        id: NodeId('themes'),
        name: 'Themes',
        modes: [
          VariableMode(id: NodeId('light'), name: 'Light'),
          VariableMode(id: NodeId('dark'), name: 'Dark'),
        ],
        variables: [
          DesignVariable(
            id: NodeId('bg'),
            name: 'BG',
            type: DesignVariableType.color,
            values: {'light': 0xFFFFFFFF, 'dark': 0xFF000000},
          ),
        ],
      );

      final resolver = VariableResolver(collections: [collection]);

      // Cache light value.
      expect(resolver.resolveVariable('bg'), 0xFFFFFFFF);

      // Switch to dark — cache should be invalidated.
      resolver.setActiveMode('themes', 'dark');
      expect(resolver.resolveVariable('bg'), 0xFF000000);
    });

    test('invalidateCache() forces re-resolve', () {
      final collection = VariableCollection(
        id: NodeId('c1'),
        name: 'Test',
        modes: [VariableMode(id: NodeId('default'), name: 'Default')],
        variables: [
          DesignVariable(
            id: NodeId('v1'),
            name: 'V1',
            type: DesignVariableType.number,
            values: {'default': 1.0},
          ),
        ],
      );

      final resolver = VariableResolver(collections: [collection]);
      expect(resolver.resolveVariable('v1'), 1.0);

      // Externally mutate the value.
      collection.findVariable('v1')!.setValue('default', 99.0);

      // Still returns cached value.
      expect(resolver.resolveVariable('v1'), 1.0);

      // Invalidate — now picks up the new value.
      resolver.invalidateCache();
      expect(resolver.resolveVariable('v1'), 99.0);
    });
  });
}
