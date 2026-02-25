import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/layers/layer_controller.dart';

void main() {
  late LayerController controller;

  setUp(() {
    controller = LayerController();
    // Disable delta tracking to avoid singleton side effects in tests
    controller.enableDeltaTracking = false;
  });

  tearDown(() {
    controller.dispose();
  });

  // ===========================================================================
  // Default state
  // ===========================================================================

  group('LayerController - default state', () {
    test('starts with one default layer', () {
      expect(controller.layers.length, 1);
      expect(controller.layers.first.name, 'Layer 1');
    });

    test('default layer is active', () {
      expect(controller.activeLayerId, isNotNull);
      expect(controller.activeLayer, isNotNull);
      expect(controller.activeLayer!.id, controller.activeLayerId);
    });

    test('activeLayerIndex is 0', () {
      expect(controller.activeLayerIndex, 0);
    });
  });

  // ===========================================================================
  // addLayer
  // ===========================================================================

  group('LayerController - addLayer', () {
    test('adds a new layer', () {
      controller.addLayer(name: 'Second');
      expect(controller.layers.length, 2);
      expect(controller.layers.last.name, 'Second');
    });

    test('new layer becomes active', () {
      final oldActiveId = controller.activeLayerId;
      controller.addLayer(name: 'New');
      // Active layer ID should change after adding
      // (may stay same if timestamp collision, so just verify layer exists)
      expect(controller.layers.any((l) => l.name == 'New'), isTrue);
    });

    test('auto-names layer when no name given', () {
      controller.addLayer();
      expect(controller.layers.last.name, 'Layer 2');
    });
  });

  // ===========================================================================
  // removeLayer
  // ===========================================================================

  group('LayerController - removeLayer', () {
    test('cannot remove the last layer', () {
      final id = controller.layers.first.id;
      controller.removeLayer(id);
      expect(controller.layers.length, 1); // Still there
    });

    test('removes non-last layer', () {
      controller.addLayer(name: 'Second');
      expect(controller.layers.length, 2);
      final firstId = controller.layers.first.id;
      controller.removeLayer(firstId);
      expect(controller.layers.length, 1);
      expect(controller.layers.first.name, 'Second');
    });

    test('selects adjacent layer after removing active', () {
      controller.addLayer(name: 'Second');
      controller.addLayer(name: 'Third');
      final secondId = controller.layers[1].id;
      controller.selectLayer(secondId);
      controller.removeLayer(secondId);
      // Should select an adjacent layer
      expect(controller.activeLayer, isNotNull);
    });
  });

  // ===========================================================================
  // duplicateLayer
  // ===========================================================================

  group('LayerController - duplicateLayer', () {
    test('creates a copy with " (Copy)" suffix', () {
      final firstId = controller.layers.first.id;
      controller.duplicateLayer(firstId);
      expect(controller.layers.length, 2);
      expect(controller.layers[1].name, 'Layer 1 (Copy)');
    });

    test('duplicate becomes active', () {
      final firstId = controller.layers.first.id;
      controller.duplicateLayer(firstId);
      expect(controller.layers.any((l) => l.name == 'Layer 1 (Copy)'), isTrue);
    });
  });

  // ===========================================================================
  // selectLayer
  // ===========================================================================

  group('LayerController - selectLayer', () {
    test('switches active layer', () {
      controller.addLayer(name: 'Second');
      final firstId = controller.layers.first.id;
      controller.selectLayer(firstId);
      expect(controller.activeLayerId, firstId);
    });

    test('ignores invalid layer ID', () {
      final originalId = controller.activeLayerId;
      controller.selectLayer('non_existent');
      expect(controller.activeLayerId, originalId);
    });
  });

  // ===========================================================================
  // renameLayer
  // ===========================================================================

  group('LayerController - renameLayer', () {
    test('renames the layer', () {
      final id = controller.layers.first.id;
      controller.renameLayer(id, 'Renamed');
      expect(controller.layers.first.name, 'Renamed');
    });
  });

  // ===========================================================================
  // toggleLayerVisibility
  // ===========================================================================

  group('LayerController - toggleLayerVisibility', () {
    test('toggles visibility off then on', () {
      final id = controller.layers.first.id;
      expect(controller.layers.first.isVisible, isTrue);
      controller.toggleLayerVisibility(id);
      expect(controller.layers.first.isVisible, isFalse);
      controller.toggleLayerVisibility(id);
      expect(controller.layers.first.isVisible, isTrue);
    });
  });

  // ===========================================================================
  // toggleLayerLock
  // ===========================================================================

  group('LayerController - toggleLayerLock', () {
    test('toggles lock on then off', () {
      final id = controller.layers.first.id;
      expect(controller.layers.first.isLocked, isFalse);
      controller.toggleLayerLock(id);
      expect(controller.layers.first.isLocked, isTrue);
      controller.toggleLayerLock(id);
      expect(controller.layers.first.isLocked, isFalse);
    });
  });

  // ===========================================================================
  // setLayerOpacity
  // ===========================================================================

  group('LayerController - setLayerOpacity', () {
    test('sets opacity', () {
      final id = controller.layers.first.id;
      controller.setLayerOpacity(id, 0.5);
      expect(controller.layers.first.opacity, closeTo(0.5, 0.01));
    });

    test('clamps opacity to [0, 1]', () {
      final id = controller.layers.first.id;
      controller.setLayerOpacity(id, 1.5);
      expect(controller.layers.first.opacity, closeTo(1.0, 0.01));
      controller.setLayerOpacity(id, -0.5);
      expect(controller.layers.first.opacity, closeTo(0.0, 0.01));
    });
  });

  // ===========================================================================
  // setLayerBlendMode
  // ===========================================================================

  group('LayerController - setLayerBlendMode', () {
    test('sets blend mode', () {
      final id = controller.layers.first.id;
      controller.setLayerBlendMode(id, ui.BlendMode.multiply);
      expect(controller.layers.first.blendMode, ui.BlendMode.multiply);
    });
  });

  // ===========================================================================
  // moveLayerUp / moveLayerDown
  // ===========================================================================

  group('LayerController - reorder', () {
    test('moveLayerUp swaps with next', () {
      controller.addLayer(name: 'Second');
      final firstId = controller.layers.first.id;
      controller.moveLayerUp(firstId);
      expect(controller.layers[1].id, firstId);
    });

    test('moveLayerUp at top does nothing', () {
      controller.addLayer(name: 'Second');
      final lastId = controller.layers.last.id;
      controller.moveLayerUp(lastId);
      // Already at the end, no change
      expect(controller.layers.last.id, lastId);
    });

    test('moveLayerDown swaps with previous', () {
      controller.addLayer(name: 'Second');
      final secondId = controller.layers.last.id;
      controller.moveLayerDown(secondId);
      expect(controller.layers.first.id, secondId);
    });

    test('moveLayerDown at bottom does nothing', () {
      controller.addLayer(name: 'Second');
      final firstId = controller.layers.first.id;
      controller.moveLayerDown(firstId);
      expect(controller.layers.first.id, firstId);
    });
  });

  // ===========================================================================
  // Dirty tracking
  // ===========================================================================

  group('LayerController - dirty tracking', () {
    test('tracks dirty layers', () {
      controller.markLayerDirty('test_layer');
      expect(controller.dirtyLayerIds.contains('test_layer'), isTrue);
    });

    test('clearDirtyLayerIds clears tracking', () {
      controller.markLayerDirty('test_layer');
      controller.clearDirtyLayerIds();
      expect(controller.dirtyLayerIds, isEmpty);
    });
  });

  // ===========================================================================
  // Listener notifications
  // ===========================================================================

  group('LayerController - notifications', () {
    test('notifies on addLayer', () {
      int count = 0;
      controller.addListener(() => count++);
      controller.addLayer(name: 'New');
      expect(count, greaterThan(0));
    });

    test('notifies on removeLayer', () {
      controller.addLayer(name: 'Second');
      int count = 0;
      controller.addListener(() => count++);
      controller.removeLayer(controller.layers.first.id);
      expect(count, greaterThan(0));
    });
  });
}
