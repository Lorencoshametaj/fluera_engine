import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/systems/semantic_token.dart';
import 'package:nebula_engine/src/systems/design_variables.dart';

void main() {
  group('SemanticTokenRegistry Tests', () {
    late List<VariableCollection> collections;

    setUp(() {
      final coreTokens = VariableCollection(
        id: 'collection-core',
        name: 'Core',
        modes: [VariableMode(id: 'mode-1', name: 'Default')],
        variables: [
          DesignVariable(
            id: 'var-blue',
            name: 'blue-500',
            type: DesignVariableType.color,
            values: {'mode-1': 0xFF0000FF},
          ),
        ],
      );
      collections = [coreTokens];
    });

    test('resolve alias to concrete value', () {
      final registry = SemanticTokenRegistry();
      registry.addAlias(
        SemanticTokenAlias(
          name: 'color.primary',
          targetCollectionId: 'collection-core',
          targetVariableId: 'var-blue',
        ),
      );

      final activeModes = {'collection-core': 'mode-1'};
      final resolved = registry.resolve(
        'color.primary',
        collections,
        activeModes,
      );

      expect(resolved, isNotNull);
      expect(resolved!.value, 0xFF0000FF);
      expect(resolved.type, DesignVariableType.color);
      expect(resolved.resolutionChain, ['color.primary']);
    });

    test('resolve chained aliases', () {
      final registry = SemanticTokenRegistry();

      // Alias 1 points to core variable
      registry.addAlias(
        SemanticTokenAlias(
          name: 'sys.color.primary',
          targetCollectionId: 'collection-core',
          targetVariableId: 'var-blue',
        ),
      );

      // Alias 2 points to Alias 1
      // Note: Target collection/variable ID in an alias-to-alias link usually uses a convention.
      // Based on implementation, targetKey is '${alias.targetCollectionId}/${alias.targetVariableId}'
      // So Alias 2 sets them such that collection/var = 'sys.color.primary'
      registry.addAlias(
        SemanticTokenAlias(
          name: 'comp.button.bg',
          targetCollectionId: 'sys.color',
          targetVariableId: 'primary',
        ),
      );

      // We need to re-add Alias 1 with the exact key matching target
      registry.removeAlias('sys.color.primary');
      registry.addAlias(
        SemanticTokenAlias(
          name:
              'sys.color/primary', // This matches the format `${collection}/${variable}`
          targetCollectionId: 'collection-core',
          targetVariableId: 'var-blue',
        ),
      );

      final activeModes = {'collection-core': 'mode-1'};
      final resolved = registry.resolve(
        'comp.button.bg',
        collections,
        activeModes,
      );

      expect(resolved, isNotNull);
      expect(resolved!.value, 0xFF0000FF);
      expect(
        resolved.resolutionChain,
        containsAll(['comp.button.bg', 'sys.color/primary']),
      );
    });

    test('circular reference detection', () {
      final registry = SemanticTokenRegistry();

      // A -> B
      registry.addAlias(
        SemanticTokenAlias(
          name: 'A',
          targetCollectionId: 'B_coll',
          targetVariableId: 'B_var',
        ),
      );
      // B -> C
      registry.addAlias(
        SemanticTokenAlias(
          name: 'B_coll/B_var',
          targetCollectionId: 'C_coll',
          targetVariableId: 'C_var',
        ),
      );
      // C -> A
      registry.addAlias(
        SemanticTokenAlias(
          name: 'C_coll/C_var',
          targetCollectionId:
              'A', // For simplicity, let's say the target key format parses to A
          targetVariableId:
              '', // So 'A/' which won't match. We need exact loop.
        ),
      );

      // Create a direct loop A -> A
      registry.addAlias(
        SemanticTokenAlias(
          name: 'LoopA',
          targetCollectionId: 'Loop',
          targetVariableId: 'A',
        ),
      );
      registry.addAlias(
        SemanticTokenAlias(
          name: 'Loop/A',
          targetCollectionId: 'Loop',
          targetVariableId: 'A',
        ),
      );

      final circles = registry.detectCircles();
      expect(circles, contains('LoopA'));

      final resolved = registry.resolve('LoopA', collections, {});
      expect(resolved, isNull); // Protected by circular reference check
    });

    test('validate finds broken references', () {
      final registry = SemanticTokenRegistry();
      registry.addAlias(
        SemanticTokenAlias(
          name: 'broken',
          targetCollectionId: 'nonexistent',
          targetVariableId: 'var',
        ),
      );

      final broken = registry.validate(collections);
      expect(broken, contains('broken'));
    });
  });
}
