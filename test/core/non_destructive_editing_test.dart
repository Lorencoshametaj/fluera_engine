import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/editing/adjustment_layer.dart';
import 'package:fluera_engine/src/core/editing/smart_filter_stack.dart';
import 'package:fluera_engine/src/core/editing/blend_mode_engine.dart';
import 'package:fluera_engine/src/core/editing/mask_channel.dart';

void main() {
  // ===========================================================================
  // ADJUSTMENT LAYER
  // ===========================================================================

  group('AdjustmentLayer', () {
    test('brightness increases channels', () {
      const adj = AdjustmentLayer(
        type: AdjustmentType.brightness,
        parameters: {'amount': 0.2},
      );
      final result = adj.apply(0.5, 0.3, 0.8);
      expect(result.r, closeTo(0.7, 0.01));
      expect(result.g, closeTo(0.5, 0.01));
      expect(result.b, closeTo(1.0, 0.01)); // clamped
    });

    test('contrast expands range', () {
      const adj = AdjustmentLayer(
        type: AdjustmentType.contrast,
        parameters: {'factor': 2.0},
      );
      final result = adj.apply(0.7, 0.3, 0.5);
      expect(result.r, greaterThan(0.7));
      expect(result.g, lessThan(0.3));
      expect(result.b, closeTo(0.5, 0.01)); // midpoint unchanged
    });

    test('saturation 0 produces grayscale', () {
      const adj = AdjustmentLayer(
        type: AdjustmentType.saturation,
        parameters: {'factor': 0.0},
      );
      final result = adj.apply(1.0, 0.0, 0.0);
      expect(result.r, closeTo(result.g, 0.01));
      expect(result.g, closeTo(result.b, 0.01));
    });

    test('invert flips values', () {
      const adj = AdjustmentLayer(type: AdjustmentType.invert);
      final result = adj.apply(0.8, 0.2, 0.6);
      expect(result.r, closeTo(0.2, 0.01));
      expect(result.g, closeTo(0.8, 0.01));
      expect(result.b, closeTo(0.4, 0.01));
    });

    test('threshold produces binary', () {
      const adj = AdjustmentLayer(
        type: AdjustmentType.threshold,
        parameters: {'threshold': 0.5},
      );
      final bright = adj.apply(0.8, 0.8, 0.8);
      final dark = adj.apply(0.1, 0.1, 0.1);
      expect(bright.r, 1.0);
      expect(dark.r, 0.0);
    });

    test('sepia applies warm tone', () {
      const adj = AdjustmentLayer(
        type: AdjustmentType.sepia,
        parameters: {'intensity': 1.0},
      );
      final result = adj.apply(0.5, 0.5, 0.5);
      // Sepia: R > G > B
      expect(result.r, greaterThan(result.g));
      expect(result.g, greaterThan(result.b));
    });

    test('disabled layer passes through', () {
      const adj = AdjustmentLayer(type: AdjustmentType.invert, enabled: false);
      final result = adj.apply(0.5, 0.3, 0.8);
      expect(result.r, 0.5);
      expect(result.g, 0.3);
    });

    test('opacity blends with original', () {
      const adj = AdjustmentLayer(type: AdjustmentType.invert, opacity: 0.5);
      final result = adj.apply(0.8, 0.2, 0.6);
      expect(result.r, closeTo(0.5, 0.01)); // lerp(0.8, 0.2, 0.5)
    });

    test('exposure in stops', () {
      const adj = AdjustmentLayer(
        type: AdjustmentType.exposure,
        parameters: {'stops': 1.0},
      );
      final result = adj.apply(0.25, 0.25, 0.25);
      expect(result.r, closeTo(0.5, 0.01)); // 2^1 = 2x
    });

    test('hue shift rotates color', () {
      const adj = AdjustmentLayer(
        type: AdjustmentType.hueShift,
        parameters: {'degrees': 180.0},
      );
      final result = adj.apply(1.0, 0.0, 0.0); // pure red
      // 180° shift → cyan area
      expect(result.r, lessThan(0.2));
    });

    test('serialization round-trip', () {
      const adj = AdjustmentLayer(
        type: AdjustmentType.contrast,
        parameters: {'factor': 1.5},
        opacity: 0.8,
      );
      final json = adj.toJson();
      final restored = AdjustmentLayer.fromJson(json);
      expect(restored.type, adj.type);
      expect(restored.parameters['factor'], 1.5);
      expect(restored.opacity, 0.8);
    });
  });

  group('AdjustmentStack', () {
    test('stacking brightens then inverts', () {
      final stack = AdjustmentStack([
        const AdjustmentLayer(
          type: AdjustmentType.brightness,
          parameters: {'amount': 0.2},
        ),
        const AdjustmentLayer(type: AdjustmentType.invert),
      ]);
      final result = stack.apply(0.5, 0.3, 0.8);
      // brightness: 0.7, 0.5, 1.0 → invert: 0.3, 0.5, 0.0
      expect(result.r, closeTo(0.3, 0.01));
    });

    test('reorder changes result', () {
      final stack = AdjustmentStack([
        const AdjustmentLayer(
          type: AdjustmentType.brightness,
          parameters: {'amount': 0.5},
        ),
        const AdjustmentLayer(type: AdjustmentType.invert),
      ]);
      final before = stack.apply(0.3, 0.3, 0.3);
      stack.reorder(0, 1);
      final after = stack.apply(0.3, 0.3, 0.3);
      expect(before.r, isNot(closeTo(after.r, 0.01)));
    });
  });

  // ===========================================================================
  // SMART FILTER STACK
  // ===========================================================================

  group('SmartFilterStack', () {
    test('add/remove filters', () {
      final stack = SmartFilterStack();
      stack.add(
        SmartFilter(id: 'f1', name: 'Blur', type: SmartFilterType.gaussianBlur),
      );
      expect(stack.count, 1);
      expect(stack.version, 1);
      stack.removeById('f1');
      expect(stack.count, 0);
      expect(stack.version, 2);
    });

    test('reorder changes position', () {
      final stack = SmartFilterStack();
      stack.add(SmartFilter(id: 'a', name: 'A', type: SmartFilterType.sharpen));
      stack.add(SmartFilter(id: 'b', name: 'B', type: SmartFilterType.denoise));
      stack.reorder(0, 1);
      expect(stack.filters[0].id, 'b');
      expect(stack.filters[1].id, 'a');
    });

    test('toggle filter', () {
      final stack = SmartFilterStack();
      stack.add(
        SmartFilter(id: 'f', name: 'F', type: SmartFilterType.pixelate),
      );
      stack.toggleFilter('f');
      expect(stack.findById('f')!.enabled, isFalse);
    });

    test('active filters excludes disabled', () {
      final stack = SmartFilterStack();
      stack.add(SmartFilter(id: 'a', name: 'A', type: SmartFilterType.sharpen));
      stack.add(
        SmartFilter(
          id: 'b',
          name: 'B',
          type: SmartFilterType.denoise,
          enabled: false,
        ),
      );
      expect(stack.activeFilters.length, 1);
    });

    test('serialization round-trip', () {
      final stack = SmartFilterStack();
      stack.add(
        SmartFilter(
          id: 'blur',
          name: 'Blur',
          type: SmartFilterType.gaussianBlur,
          parameters: {'radius': 4.0},
        ),
      );
      final json = stack.toJson();
      final restored = SmartFilterStack.fromJson(json);
      expect(restored.count, 1);
      expect(restored.filters[0].param('radius'), 4.0);
    });

    test('content hash changes on mutation', () {
      final stack = SmartFilterStack();
      final h1 = stack.contentHash;
      stack.add(
        SmartFilter(id: 'x', name: 'X', type: SmartFilterType.vignette),
      );
      final h2 = stack.contentHash;
      expect(h1, isNot(h2));
    });
  });

  // ===========================================================================
  // BLEND MODE ENGINE
  // ===========================================================================

  group('BlendModeEngine', () {
    test('normal mode uses source', () {
      final result = BlendModeEngine.blend(
        srcR: 0.8,
        srcG: 0.2,
        srcB: 0.1,
        srcA: 1.0,
        dstR: 0.5,
        dstG: 0.5,
        dstB: 0.5,
        dstA: 1.0,
        mode: EngineBlendMode.normal,
      );
      expect(result.r, closeTo(0.8, 0.01));
    });

    test('multiply darkens', () {
      final result = BlendModeEngine.blend(
        srcR: 0.5,
        srcG: 0.5,
        srcB: 0.5,
        srcA: 1.0,
        dstR: 0.8,
        dstG: 0.8,
        dstB: 0.8,
        dstA: 1.0,
        mode: EngineBlendMode.multiply,
      );
      expect(result.r, closeTo(0.4, 0.01));
    });

    test('screen lightens', () {
      final result = BlendModeEngine.blend(
        srcR: 0.5,
        srcG: 0.5,
        srcB: 0.5,
        srcA: 1.0,
        dstR: 0.5,
        dstG: 0.5,
        dstB: 0.5,
        dstA: 1.0,
        mode: EngineBlendMode.screen,
      );
      expect(result.r, closeTo(0.75, 0.01));
    });

    test('difference of same colors is 0', () {
      final result = BlendModeEngine.blend(
        srcR: 0.5,
        srcG: 0.5,
        srcB: 0.5,
        srcA: 1.0,
        dstR: 0.5,
        dstG: 0.5,
        dstB: 0.5,
        dstA: 1.0,
        mode: EngineBlendMode.difference,
      );
      expect(result.r, closeTo(0, 0.01));
    });

    test('transparent source passes destination', () {
      final result = BlendModeEngine.blend(
        srcR: 1.0,
        srcG: 0.0,
        srcB: 0.0,
        srcA: 0.0,
        dstR: 0.5,
        dstG: 0.5,
        dstB: 0.5,
        dstA: 1.0,
        mode: EngineBlendMode.normal,
      );
      expect(result.r, closeTo(0.5, 0.01));
    });

    test('category grouping works', () {
      expect(
        BlendModeEngine.categoryOf(EngineBlendMode.multiply),
        BlendModeCategory.darken,
      );
      expect(
        BlendModeEngine.categoryOf(EngineBlendMode.screen),
        BlendModeCategory.lighten,
      );
      expect(
        BlendModeEngine.categoryOf(EngineBlendMode.overlay),
        BlendModeCategory.contrast,
      );
    });

    test('modesInCategory returns correct modes', () {
      final darkenModes = BlendModeEngine.modesInCategory(
        BlendModeCategory.darken,
      );
      expect(darkenModes, contains(EngineBlendMode.multiply));
      expect(darkenModes, isNot(contains(EngineBlendMode.screen)));
    });

    test('all blend modes produce valid output', () {
      for (final mode in EngineBlendMode.values) {
        final result = BlendModeEngine.blend(
          srcR: 0.7,
          srcG: 0.3,
          srcB: 0.5,
          srcA: 0.8,
          dstR: 0.4,
          dstG: 0.6,
          dstB: 0.2,
          dstA: 0.9,
          mode: mode,
        );
        expect(
          result.r,
          inInclusiveRange(0.0, 1.0),
          reason: '${mode.name} R out of range',
        );
        expect(
          result.g,
          inInclusiveRange(0.0, 1.0),
          reason: '${mode.name} G out of range',
        );
        expect(
          result.b,
          inInclusiveRange(0.0, 1.0),
          reason: '${mode.name} B out of range',
        );
        expect(
          result.a,
          inInclusiveRange(0.0, 1.0),
          reason: '${mode.name} A out of range',
        );
      }
    });
  });

  // ===========================================================================
  // MASK CHANNEL
  // ===========================================================================

  group('MaskChannel', () {
    test('sample returns density value', () {
      final mask = MaskChannel(
        type: MaskType.raster,
        width: 2,
        height: 2,
        density: [0.0, 0.5, 1.0, 0.25],
      );
      expect(mask.sample(0, 0), 0.0);
      expect(mask.sample(1, 0), 0.5);
      expect(mask.sample(0, 1), 1.0);
    });

    test('inverted mask flips values', () {
      final mask = MaskChannel(
        type: MaskType.raster,
        width: 1,
        height: 1,
        density: [0.3],
        inverted: true,
      );
      expect(mask.sample(0, 0), closeTo(0.7, 0.01));
    });

    test('disabled mask returns 1.0', () {
      final mask = MaskChannel(
        type: MaskType.raster,
        width: 1,
        height: 1,
        density: [0.5],
        enabled: false,
      );
      expect(mask.sample(0, 0), 1.0);
    });

    test('opacity multiplies density', () {
      final mask = MaskChannel(
        type: MaskType.raster,
        width: 1,
        height: 1,
        density: [1.0],
        opacity: 0.5,
      );
      expect(mask.sample(0, 0), closeTo(0.5, 0.01));
    });

    test('out of bounds returns 0', () {
      final mask = MaskChannel(
        type: MaskType.raster,
        width: 2,
        height: 2,
        density: [1, 1, 1, 1],
      );
      expect(mask.sample(-1, 0), 0.0);
      expect(mask.sample(5, 5), 0.0);
    });

    test('filledRect creates mask with rectangle', () {
      final mask = MaskChannel.filledRect(10, 10, 2, 2, 5, 5);
      expect(mask.sample(0, 0), 0.0);
      expect(mask.sample(3, 3), 1.0);
      expect(mask.sample(9, 9), 0.0);
    });

    test('opaque mask returns all 1s', () {
      final mask = MaskChannel.opaque(5, 5);
      expect(mask.sample(2, 2), 1.0);
    });

    test('fromLuminosity derives from RGB', () {
      final mask = MaskChannel.fromLuminosity(
        [1.0, 0.0],
        [1.0, 0.0],
        [1.0, 0.0],
        2,
        1,
      );
      expect(mask.sample(0, 0), closeTo(1.0, 0.01));
      expect(mask.sample(1, 0), closeTo(0.0, 0.01));
    });

    test('feathering smooths edges', () {
      final mask = MaskChannel(
        type: MaskType.raster,
        width: 5,
        height: 5,
        density: [
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
        ],
        featherRadius: 1.0,
      );
      final feathered = mask.applyFeather();
      // Center should be less than 1.0 (blurred)
      expect(feathered.sample(2, 2), lessThan(1.0));
      expect(feathered.sample(2, 2), greaterThan(0.0));
      // Edge should be non-zero (spread from center)
      expect(feathered.sample(2, 1), greaterThan(0.0));
    });

    test('serialization round-trip', () {
      final mask = MaskChannel(
        type: MaskType.luminosity,
        width: 10,
        height: 10,
        inverted: true,
        featherRadius: 3.0,
        opacity: 0.8,
      );
      final json = mask.toJson();
      final restored = MaskChannel.fromJson(json);
      expect(restored.type, MaskType.luminosity);
      expect(restored.inverted, isTrue);
      expect(restored.featherRadius, 3.0);
    });
  });

  group('MaskCompositor', () {
    test('intersect multiplies masks', () {
      final m1 = MaskChannel(
        type: MaskType.raster,
        width: 2,
        height: 1,
        density: [1.0, 0.5],
      );
      final m2 = MaskChannel(
        type: MaskType.raster,
        width: 2,
        height: 1,
        density: [0.5, 1.0],
      );
      final result = MaskCompositor.intersect([m1, m2]);
      expect(result.sample(0, 0), closeTo(0.5, 0.01));
      expect(result.sample(1, 0), closeTo(0.5, 0.01));
    });

    test('unite takes maximum', () {
      final m1 = MaskChannel(
        type: MaskType.raster,
        width: 2,
        height: 1,
        density: [0.8, 0.2],
      );
      final m2 = MaskChannel(
        type: MaskType.raster,
        width: 2,
        height: 1,
        density: [0.3, 0.9],
      );
      final result = MaskCompositor.unite([m1, m2]);
      expect(result.sample(0, 0), closeTo(0.8, 0.01));
      expect(result.sample(1, 0), closeTo(0.9, 0.01));
    });
  });
}
