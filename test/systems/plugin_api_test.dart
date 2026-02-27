import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/systems/plugin_api.dart';

void main() {
  // ===========================================================================
  // PluginManifest
  // ===========================================================================

  group('PluginManifest', () {
    test('stores all fields', () {
      final manifest = PluginManifest(
        id: 'com.example.myplugin',
        name: 'My Plugin',
        version: '1.0.0',
        description: 'Does great things',
        author: 'Test Author',
        capabilities: {PluginCapability.readSceneGraph},
        permission: PluginPermission.readOnly,
      );

      expect(manifest.id, 'com.example.myplugin');
      expect(manifest.name, 'My Plugin');
      expect(manifest.version, '1.0.0');
      expect(manifest.description, 'Does great things');
      expect(manifest.author, 'Test Author');
      expect(manifest.capabilities, contains(PluginCapability.readSceneGraph));
      expect(manifest.permission, PluginPermission.readOnly);
    });

    test('JSON serialization', () {
      final manifest = PluginManifest(
        id: 'test.plugin',
        name: 'Test',
        version: '0.1.0',
        capabilities: {
          PluginCapability.readSceneGraph,
          PluginCapability.writeNodeProperties,
        },
        permission: PluginPermission.readWrite,
      );

      final json = manifest.toJson();
      expect(json['id'], 'test.plugin');
      expect(json['name'], 'Test');
      expect(json['version'], '0.1.0');
      expect(json['capabilities'], isA<List>());
      expect(json['permission'], 'readWrite');
    });
  });

  // ===========================================================================
  // PluginCapability
  // ===========================================================================

  group('PluginCapability', () {
    test('has expected values', () {
      expect(
        PluginCapability.values,
        contains(PluginCapability.readSceneGraph),
      );
      expect(
        PluginCapability.values,
        contains(PluginCapability.writeNodeProperties),
      );
      expect(
        PluginCapability.values,
        contains(PluginCapability.modifySceneGraph),
      );
      expect(PluginCapability.values, contains(PluginCapability.selection));
      expect(
        PluginCapability.values,
        contains(PluginCapability.customExporters),
      );
      expect(PluginCapability.values, contains(PluginCapability.preferences));
      expect(PluginCapability.values, contains(PluginCapability.network));
      expect(PluginCapability.values, contains(PluginCapability.listenEvents));
      expect(
        PluginCapability.values,
        contains(PluginCapability.executeCommands),
      );
    });
  });

  // ===========================================================================
  // PluginPermission
  // ===========================================================================

  group('PluginPermission', () {
    test('has three levels', () {
      expect(PluginPermission.values, hasLength(3));
      expect(PluginPermission.values, contains(PluginPermission.readOnly));
      expect(PluginPermission.values, contains(PluginPermission.readWrite));
      expect(PluginPermission.values, contains(PluginPermission.full));
    });
  });
}
