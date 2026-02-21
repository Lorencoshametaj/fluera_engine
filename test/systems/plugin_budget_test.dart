import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/nebula_engine.dart';

class BadPlugin implements PluginEntryPoint {
  @override
  void onActivate(PluginContext context) {
    // Attempt to exceed lookup budget
    for (int i = 0; i < 1500; i++) {
      context.getAllNodes();
    }
  }

  @override
  void onDeactivate() {}
  @override
  void onSelectionChanged(Set<String> selectedIds) {}
  @override
  void onSceneChanged() {}
}

class ThrowingPlugin implements PluginEntryPoint {
  @override
  void onActivate(PluginContext context) {
    throw Exception('Intentional crash');
  }

  @override
  void onDeactivate() {}
  @override
  void onSelectionChanged(Set<String> selectedIds) {}
  @override
  void onSceneChanged() {}
}

class DummyBridge implements PluginBridge {
  @override
  List<FrozenNodeView> getAllNodes() => [];
  @override
  FrozenNodeView? findNode(String nodeId) => null;
  @override
  Set<String> getSelectedIds() => {};
  @override
  void setNodeOpacity(String nodeId, double opacity) {}
  @override
  void setNodeVisibility(String nodeId, bool visible) {}
  @override
  void setNodeName(String nodeId, String name) {}
  @override
  void removeNode(String nodeId) {}
  @override
  EngineEventBus get eventBus => EngineEventBus();
  @override
  CommandHistory get commandHistory => CommandHistory();
  @override
  void addNode(GroupNode parent, CanvasNode child) {}
  @override
  CanvasNode? cloneNode(String nodeId) => null;
  @override
  GroupNode? findParent(String nodeId) => null;
  @override
  void setNodePosition(String nodeId, Offset position) {}
  @override
  void batchModify(
    List<String> nodeIds,
    void Function(CanvasNode) modifier, {
    String label = '',
  }) {}
}

void main() {
  group('Plugin Sandboxing & Budgets', () {
    test(
      'enforces max node lookup budget per frame and deactivates bad plugin',
      () {
        final registry = PluginRegistry();
        final manifest = PluginManifest(
          id: 'test.budget',
          name: 'Budget Test',
          capabilities: {PluginCapability.readSceneGraph},
          budget: const PluginBudget(maxNodeLookupsPerFrame: 10),
        );
        final plugin = BadPlugin();
        final bridge = DummyBridge();

        registry.install(manifest, plugin);
        registry.activate(manifest.id, bridge);

        // Activation triggered the budget exception, which was caught by
        // runZonedGuarded, resulting in the plugin being forcibly deactivated.
        expect(registry.isActive(manifest.id), isFalse);
      },
    );

    test('runZonedGuarded catches synchronous unhandled errors', () {
      final registry = PluginRegistry();
      final manifest = const PluginManifest(
        id: 'test.crash',
        name: 'Crash Test',
      );
      final plugin = ThrowingPlugin();
      final bridge = DummyBridge();

      registry.install(manifest, plugin);
      registry.activate(manifest.id, bridge);

      expect(registry.isActive(manifest.id), isFalse);
    });
  });
}
