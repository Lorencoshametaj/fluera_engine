import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/nodes/material_zone_node.dart';
import 'package:fluera_engine/src/core/scene_graph/node_id.dart';
import 'package:fluera_engine/src/drawing/models/surface_material.dart';

void main() {
  // ===========================================================================
  // MaterialZoneNode
  // ===========================================================================

  group('MaterialZoneNode', () {
    // ── Construction ────────────────────────────────────────────────

    test('constructs with default surface', () {
      final node = MaterialZoneNode(id: NodeId('test-1'));
      expect(node.surface, equals(const SurfaceMaterial()));
    });

    test('constructs with custom surface', () {
      final node = MaterialZoneNode(
        id: NodeId('test-2'),
        surface: const SurfaceMaterial.watercolorPaper(),
      );
      expect(node.surface.roughness, 0.6);
      expect(node.surface.absorption, 0.8);
    });

    test('nodeType is materialZone in JSON', () {
      final node = MaterialZoneNode(id: NodeId('test-3'));
      final json = node.toJson();
      expect(json['nodeType'], 'materialZone');
    });

    // ── Serialization ────────────────────────────────────────────────

    test('toJson includes surface', () {
      final node = MaterialZoneNode(
        id: NodeId('test-4'),
        surface: const SurfaceMaterial.canvas(),
      );
      final json = node.toJson();
      expect(json['surface'], isA<Map<String, dynamic>>());
      expect((json['surface'] as Map)['r'], 0.8); // canvas roughness
    });

    test('fromJson round-trips surface material', () {
      final original = MaterialZoneNode(
        id: NodeId('test-id'),
        name: 'My Zone',
        surface: const SurfaceMaterial.watercolorPaper(),
      );
      final json = original.toJson();
      final restored = MaterialZoneNode.fromJson(json);

      expect(restored.id.value, 'test-id');
      expect(restored.name, 'My Zone');
      expect(restored.surface.roughness, 0.6);
      expect(restored.surface.absorption, 0.8);
      expect(restored.surface.grainTexture, 'watercolor');
    });

    test('fromJson with null surface uses defaults', () {
      final json = {'id': 'test-id', 'nodeType': 'materialZone'};
      final node = MaterialZoneNode.fromJson(json);
      expect(node.surface.roughness, 0.15); // default
    });

    // ── Children ────────────────────────────────────────────────────

    test('serializes empty children list', () {
      final node = MaterialZoneNode(id: NodeId('test-5'));
      final json = node.toJson();
      expect(json['children'], isA<List>());
      expect((json['children'] as List).isEmpty, isTrue);
    });
  });

  // ===========================================================================
  // Wetness integration in computeModifiers
  // ===========================================================================

  group('computeModifiers with wetness', () {
    test('zero wetness has no extra effect', () {
      const s = SurfaceMaterial(absorption: 0.5);
      final dry = s.computeModifiers(
        pressure: 0.5,
        velocity: 500,
        wetness: 0.0,
      );
      final alsoDry = s.computeModifiers(pressure: 0.5, velocity: 500);
      expect(dry.spreadFactor, alsoDry.spreadFactor);
      expect(dry.opacityMultiplier, alsoDry.opacityMultiplier);
    });

    test('wetness increases spread', () {
      const s = SurfaceMaterial(absorption: 0.5);
      final dry = s.computeModifiers(
        pressure: 0.5,
        velocity: 500,
        wetness: 0.0,
      );
      final wet = s.computeModifiers(
        pressure: 0.5,
        velocity: 500,
        wetness: 1.0,
      );
      expect(wet.spreadFactor, greaterThan(dry.spreadFactor));
    });

    test('wetness slightly reduces opacity', () {
      const s = SurfaceMaterial(absorption: 0.5);
      final dry = s.computeModifiers(
        pressure: 0.5,
        velocity: 500,
        wetness: 0.0,
      );
      final wet = s.computeModifiers(
        pressure: 0.5,
        velocity: 500,
        wetness: 1.0,
      );
      expect(wet.opacityMultiplier, lessThan(dry.opacityMultiplier));
    });

    test('wetness does not affect grain intensity', () {
      const s = SurfaceMaterial(roughness: 0.8);
      final dry = s.computeModifiers(
        pressure: 0.5,
        velocity: 500,
        wetness: 0.0,
      );
      final wet = s.computeModifiers(
        pressure: 0.5,
        velocity: 500,
        wetness: 1.0,
      );
      expect(wet.grainIntensity, dry.grainIntensity);
    });
  });
}
