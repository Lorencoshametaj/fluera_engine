import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/systems/dev_handoff/token_resolver.dart';
import 'package:fluera_engine/src/systems/design_variables.dart';
import 'package:fluera_engine/src/core/nodes/frame_node.dart';
import 'package:fluera_engine/src/core/scene_graph/node_id.dart';
import 'dart:ui';

void main() {
  group('TokenResolver Tests', () {
    late List<VariableCollection> collections;
    late VariableCollection coreTokens;

    setUp(() {
      coreTokens = VariableCollection(
        id: 'collection-core',
        name: 'Core',
        modes: [VariableMode(id: 'mode-1', name: 'Default')],
        variables: [
          DesignVariable(
            id: 'var-blue',
            name: 'colors/blue500',
            type: DesignVariableType.color,
            values: {'mode-1': 0xFF0000FF},
          ),
          DesignVariable(
            id: 'var-spacing',
            name: 'spacing/large',
            type: DesignVariableType.number,
            values: {'mode-1': 24.0},
          ),
          DesignVariable(
            id: 'var-font',
            name: 'typography/fontFamily',
            type: DesignVariableType.string,
            values: {'mode-1': 'Inter'},
          ),
        ],
      );
      collections = [coreTokens];
    });

    test('resolveColor finds matching color token', () {
      final resolver = TokenResolver(collections: collections);

      final ref = resolver.resolveColor('fill-color', const Color(0xFF0000FF));

      expect(ref, isNotNull);
      expect(ref!.collectionName, 'Core');
      expect(ref.variableName, 'colors/blue500');
      expect(ref.modeId, 'mode-1');
      expect(ref.value, 0xFF0000FF);
    });

    test('resolveNumber finds matching number token within epsilon', () {
      final resolver = TokenResolver(collections: collections);

      final refExact = resolver.resolveNumber('spacing', 24.0);
      expect(refExact, isNotNull);
      expect(refExact!.variableName, 'spacing/large');

      final refApprox = resolver.resolveNumber('spacing', 24.004);
      expect(refApprox, isNotNull);
      expect(refApprox!.variableName, 'spacing/large');

      final refMiss = resolver.resolveNumber('spacing', 24.1);
      expect(refMiss, isNull);
    });

    test('resolveString finds matching string token', () {
      final resolver = TokenResolver(collections: collections);

      final ref = resolver.resolveString('font-family', 'Inter');
      expect(ref, isNotNull);
      expect(ref!.variableName, 'typography/fontFamily');
    });

    test('resolveAll extracts properties from FrameNode', () {
      final resolver = TokenResolver(collections: collections);

      final frame = FrameNode(id: NodeId('frame'));
      frame.fillColor = const Color(0xFF0000FF);
      frame.spacing = 24.0;
      frame.borderRadius = 24.0;

      final refs = resolver.resolveAll(frame);

      expect(refs.length, 3);

      final fillRef = refs.where((r) => r.property == 'fill-color').first;
      expect(fillRef.variableName, 'colors/blue500');

      final spacingRef = refs.where((r) => r.property == 'spacing').first;
      expect(spacingRef.variableName, 'spacing/large');

      final radiusRef = refs.where((r) => r.property == 'corner-radius').first;
      expect(radiusRef.variableName, 'spacing/large');
    });

    test('activeModes override default mode', () {
      // Create a new collection with both modes since modes list is unmodifiable
      final dualModeCollection = VariableCollection(
        id: 'collection-core',
        name: 'Core',
        modes: [
          VariableMode(id: 'mode-1', name: 'Default'),
          VariableMode(id: 'mode-2', name: 'Dark'),
        ],
        variables: [
          DesignVariable(
            id: 'var-blue',
            name: 'colors/blue500',
            type: DesignVariableType.color,
            values: {'mode-1': 0xFF0000FF, 'mode-2': 0xFF0000AA},
          ),
        ],
      );
      final dualCollections = [dualModeCollection];

      // No active mode specified -> uses Default (mode-1)
      final defaultResolver = TokenResolver(collections: dualCollections);
      expect(
        defaultResolver.resolveColor('c', const Color(0xFF0000AA)),
        isNull,
      );

      // Active mode specified -> uses Dark (mode-2)
      final darkResolver = TokenResolver(
        collections: dualCollections,
        activeModes: {'collection-core': 'mode-2'},
      );
      final darkRef = darkResolver.resolveColor('c', const Color(0xFF0000AA));
      expect(darkRef, isNotNull);
      expect(darkRef!.modeId, 'mode-2');
    });
  });
}
