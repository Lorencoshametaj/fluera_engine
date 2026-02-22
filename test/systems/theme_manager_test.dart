import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/systems/theme_manager.dart';
import 'package:nebula_engine/src/systems/design_variables.dart';

void main() {
  group('ThemeManager Tests', () {
    test('addTheme, getTheme, removeTheme', () {
      final manager = ThemeManager();

      final theme = ThemeDefinition(
        name: 'Dark',
        modeSelections: {'coll-1': 'mode-dark'},
      );

      manager.addTheme(theme);

      expect(manager.hasTheme('Dark'), isTrue);
      expect(manager.getTheme('Dark')?.name, 'Dark');

      manager.removeTheme('Dark');
      expect(manager.hasTheme('Dark'), isFalse);
    });

    test('switchTheme changes active theme', () {
      final manager = ThemeManager();
      manager.addTheme(
        ThemeDefinition(name: 'Dark', modeSelections: {'coll-1': 'mode-dark'}),
      );

      final selections = manager.switchTheme('Dark');
      expect(selections, isNotNull);
      expect(selections!['coll-1'], 'mode-dark');
      expect(manager.activeThemeName, 'Dark');
    });

    test('applyTheme updates active modes map', () {
      final manager = ThemeManager();
      manager.addTheme(
        ThemeDefinition(
          name: 'Dark',
          modeSelections: {'coll-1': 'mode-dark', 'coll-2': 'mode-dark-alt'},
        ),
      );
      manager.switchTheme('Dark');

      final collections = [
        VariableCollection(
          id: 'coll-1',
          name: 'Core',
          modes: [
            VariableMode(id: 'mode-dark', name: 'Dark'),
            VariableMode(id: 'mode-light', name: 'Light'),
          ],
          variables: [],
        ),
      ];

      final activeModes = <String, String>{};

      final updated = manager.applyTheme(collections, activeModes);

      // Only coll-1 exists in collections list, so only it should be updated
      expect(updated, 1);
      expect(activeModes['coll-1'], 'mode-dark');
      expect(activeModes.containsKey('coll-2'), isFalse);
    });

    test('scaffoldLightDark generates themes automatically', () {
      final manager = ThemeManager();
      final collections = [
        VariableCollection(
          id: 'coll-1',
          name: 'Core',
          modes: [
            VariableMode(id: 'm1', name: 'Light'),
            VariableMode(id: 'm2', name: 'dark'), // Case insensitive check
            VariableMode(id: 'm3', name: 'High Contrast'),
          ],
          variables: [],
        ),
      ];

      final themes = manager.scaffoldLightDark(collections);

      expect(themes.length, 2);

      final lightTheme = themes.firstWhere((t) => t.name == 'light');
      expect(lightTheme.modeSelections['coll-1'], 'm1');

      final darkTheme = themes.firstWhere((t) => t.name == 'dark');
      expect(darkTheme.modeSelections['coll-1'], 'm2');
    });

    test('serialization roundtrip', () {
      final manager = ThemeManager();
      manager.addTheme(
        ThemeDefinition(
          name: 'Brand',
          description: 'Brand theme',
          modeSelections: {'coll-colors': 'brand-mode'},
        ),
      );
      manager.switchTheme('Brand');

      final json = manager.toJson();
      expect(json['activeTheme'], 'Brand');
      expect(json['themes'], isNotEmpty);

      final restored = ThemeManager.fromJson(json);
      expect(restored.activeThemeName, 'Brand');
      expect(restored.hasTheme('Brand'), isTrue);
      expect(
        restored.getTheme('Brand')!.modeSelections['coll-colors'],
        'brand-mode',
      );
    });
  });
}
