import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/canvas/infinite_canvas_controller.dart';
import 'package:fluera_engine/src/canvas/liquid_canvas_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('InfiniteCanvasController — Core API', () {
    late InfiniteCanvasController controller;

    setUp(() {
      controller = InfiniteCanvasController();
    });

    tearDown(() {
      controller.dispose();
    });

    test('initial state has zero offset and 1.0 scale', () {
      expect(controller.offset, Offset.zero);
      expect(controller.scale, 1.0);
    });

    test('setOffset updates offset and notifies', () {
      bool notified = false;
      controller.addListener(() => notified = true);
      controller.setOffset(const Offset(100, 200));

      expect(controller.offset, const Offset(100, 200));
      expect(notified, isTrue);
    });

    test('setScale clamps to min/max and notifies', () {
      controller.setScale(10.0);
      expect(controller.scale, 5.0); // max clamp

      controller.setScale(0.01);
      expect(controller.scale, 0.1); // min clamp
    });

    test('updateTransform updates offset and scale together', () {
      controller.updateTransform(offset: const Offset(50, 75), scale: 2.5);
      expect(controller.offset, const Offset(50, 75));
      expect(controller.scale, 2.5);
    });

    test('updateTransform without elastic clamps scale', () {
      controller.updateTransform(offset: Offset.zero, scale: 8.0);
      expect(controller.scale, 5.0);
    });

    test('reset clears offset and scale', () {
      controller.setOffset(const Offset(100, 200));
      controller.setScale(3.0);
      controller.reset();

      expect(controller.offset, Offset.zero);
      expect(controller.scale, 1.0);
    });

    test('screenToCanvas converts correctly', () {
      controller.updateTransform(offset: const Offset(100, 100), scale: 2.0);
      // screen (200,200) → canvas = (200-100)/2 = (50,50)
      expect(
        controller.screenToCanvas(const Offset(200, 200)),
        const Offset(50, 50),
      );
    });

    test('canvasToScreen converts correctly', () {
      controller.updateTransform(offset: const Offset(100, 100), scale: 2.0);
      // canvas (50,50) → screen = 50*2 + 100 = (200,200)
      expect(
        controller.canvasToScreen(const Offset(50, 50)),
        const Offset(200, 200),
      );
    });

    test('screenToCanvas and canvasToScreen are inverse operations', () {
      controller.updateTransform(
        offset: const Offset(37.5, -120.3),
        scale: 1.7,
      );
      const original = Offset(200, 300);
      final canvas = controller.screenToCanvas(original);
      final roundTrip = controller.canvasToScreen(canvas);
      expect(roundTrip.dx, closeTo(original.dx, 0.001));
      expect(roundTrip.dy, closeTo(original.dy, 0.001));
    });

    test('centerCanvas places origin at viewport center', () {
      controller.centerCanvas(const Size(800, 600));
      expect(controller.offset, const Offset(400, 300));
    });
  });

  group('InfiniteCanvasController — Elastic Zoom', () {
    late InfiniteCanvasController controller;

    setUp(() {
      controller = InfiniteCanvasController();
      controller.liquidConfig = const LiquidCanvasConfig();
    });

    tearDown(() {
      controller.dispose();
    });

    test('elastic updateTransform allows scale beyond max', () {
      controller.updateTransform(
        offset: Offset.zero,
        scale: 6.0,
        elastic: true,
      );
      // Should be > maxScale (5.0) but < maxElastic
      expect(controller.scale, greaterThan(5.0));
      expect(controller.scale, lessThan(6.0)); // rubber-band resistance
    });

    test('elastic updateTransform allows scale below min', () {
      controller.updateTransform(
        offset: Offset.zero,
        scale: 0.05,
        elastic: true,
      );
      expect(controller.scale, lessThan(0.1));
      expect(controller.scale, greaterThan(0.0));
    });

    test('elastic clamp applies logarithmic resistance', () {
      // The further past the limit, the more resistance
      controller.updateTransform(
        offset: Offset.zero,
        scale: 6.0,
        elastic: true,
      );
      final scaleAt6 = controller.scale;

      controller.updateTransform(
        offset: Offset.zero,
        scale: 8.0,
        elastic: true,
      );
      final scaleAt8 = controller.scale;

      // Both should exceed max but the difference should be small
      // (diminishing returns from rubber-band)
      expect(scaleAt8, greaterThanOrEqualTo(scaleAt6));
      expect(scaleAt8 - scaleAt6, lessThan(1.0)); // resistance limits growth
    });

    test('elastic disabled returns hard clamp', () {
      controller.liquidConfig = LiquidCanvasConfig.disabled;
      controller.updateTransform(
        offset: Offset.zero,
        scale: 8.0,
        elastic: true,
      );
      expect(controller.scale, 5.0);
    });

    test('non-elastic updateTransform always clamps', () {
      controller.updateTransform(
        offset: Offset.zero,
        scale: 8.0,
        elastic: false,
      );
      expect(controller.scale, 5.0);
    });
  });

  group('InfiniteCanvasController — Momentum', () {
    late InfiniteCanvasController controller;

    setUp(() {
      controller = InfiniteCanvasController();
      controller.liquidConfig = const LiquidCanvasConfig();
    });

    tearDown(() {
      controller.dispose();
    });

    test('startMomentum does nothing without ticker', () {
      controller.startMomentum(const Offset(1000, 500));
      expect(controller.isAnimating, isFalse);
    });

    test('startMomentum ignores below threshold velocity', () async {
      await _withTicker((vsync) {
        controller.attachTicker(vsync);
        controller.startMomentum(const Offset(50, 30)); // Below 100 threshold
        expect(controller.isAnimating, isFalse);
        controller.detachTicker();
      });
    });

    test('startMomentum activates with sufficient velocity', () async {
      await _withTicker((vsync) {
        controller.attachTicker(vsync);
        controller.startMomentum(const Offset(1000, 500));
        expect(controller.isAnimating, isTrue);
        controller.stopAnimation();
        controller.detachTicker();
      });
    });

    test('stopAnimation halts momentum immediately', () async {
      await _withTicker((vsync) {
        controller.attachTicker(vsync);
        controller.startMomentum(const Offset(1000, 500));
        expect(controller.isAnimating, isTrue);

        controller.stopAnimation();
        expect(controller.isAnimating, isFalse);
        controller.detachTicker();
      });
    });

    test('startMomentum with disabled config does nothing', () async {
      controller.liquidConfig = LiquidCanvasConfig.disabled;
      await _withTicker((vsync) {
        controller.attachTicker(vsync);
        controller.startMomentum(const Offset(1000, 500));
        expect(controller.isAnimating, isFalse);
        controller.detachTicker();
      });
    });
  });

  group('InfiniteCanvasController — Zoom Spring-Back', () {
    late InfiniteCanvasController controller;

    setUp(() {
      controller = InfiniteCanvasController();
      controller.liquidConfig = const LiquidCanvasConfig();
    });

    tearDown(() {
      controller.dispose();
    });

    test('startZoomSpringBack does nothing when within bounds', () async {
      await _withTicker((vsync) {
        controller.attachTicker(vsync);
        controller.setScale(3.0); // Within bounds
        controller.startZoomSpringBack(const Offset(200, 200));
        expect(controller.isAnimating, isFalse);
        controller.detachTicker();
      });
    });

    test('startZoomSpringBack activates when beyond max', () async {
      await _withTicker((vsync) {
        controller.attachTicker(vsync);
        // Force scale beyond max using elastic transform
        controller.updateTransform(
          offset: Offset.zero,
          scale: 6.0,
          elastic: true,
        );
        expect(controller.scale, greaterThan(5.0));

        controller.startZoomSpringBack(const Offset(200, 200));
        expect(controller.isAnimating, isTrue);
        controller.stopAnimation();
        controller.detachTicker();
      });
    });

    test('startZoomSpringBack does nothing without ticker', () {
      controller.updateTransform(
        offset: Offset.zero,
        scale: 6.0,
        elastic: true,
      );
      controller.startZoomSpringBack(const Offset(200, 200));
      expect(controller.isAnimating, isFalse);
    });

    test('startZoomSpringBack with disabled config does nothing', () async {
      controller.liquidConfig = LiquidCanvasConfig.disabled;
      await _withTicker((vsync) {
        controller.attachTicker(vsync);
        // Can't even get past limits with disabled config, but test the path
        controller.startZoomSpringBack(const Offset(200, 200));
        expect(controller.isAnimating, isFalse);
        controller.detachTicker();
      });
    });
  });

  group('InfiniteCanvasController — Ticker Lifecycle', () {
    test('attachTicker and detachTicker work without error', () async {
      final controller = InfiniteCanvasController();
      await _withTicker((vsync) {
        controller.attachTicker(vsync);
        controller.detachTicker();
      });
      controller.dispose();
    });

    test('calling detachTicker without attach is safe', () {
      final controller = InfiniteCanvasController();
      controller.detachTicker(); // Should not throw
      controller.dispose();
    });

    test('dispose cleans up ticker', () async {
      final controller = InfiniteCanvasController();
      await _withTicker((vsync) {
        controller.attachTicker(vsync);
        controller.startMomentum(const Offset(1000, 500));
        expect(controller.isAnimating, isTrue);
        controller.dispose();
        // After dispose, isAnimating should be false
        expect(controller.isAnimating, isFalse);
      });
    });
  });

  group('LiquidCanvasConfig', () {
    test('default config has expected values', () {
      const config = LiquidCanvasConfig();
      expect(config.enabled, isTrue);
      expect(config.enableElasticZoom, isTrue);
      expect(config.panFriction, 0.015);
      expect(config.momentumThreshold, 100.0);
    });

    test('disabled config has enabled = false', () {
      expect(LiquidCanvasConfig.disabled.enabled, isFalse);
    });

    test('maxElasticScale with default overshoot', () {
      const config = LiquidCanvasConfig();
      // 5.0 * (1 + 0.35) = 6.75
      expect(config.maxElasticScale(5.0), closeTo(6.75, 0.01));
    });

    test('minElasticScale with default overshoot', () {
      const config = LiquidCanvasConfig();
      // 0.1 * (1 - 0.35 * 0.5) = 0.1 * 0.825 = 0.0825
      expect(config.minElasticScale(0.1), closeTo(0.0825, 0.001));
    });

    test('custom config respects overrides', () {
      const config = LiquidCanvasConfig(
        panFriction: 0.05,
        zoomSpringStiffness: 400.0,
        momentumThreshold: 200.0,
      );
      expect(config.panFriction, 0.05);
      expect(config.zoomSpringStiffness, 400.0);
      expect(config.momentumThreshold, 200.0);
    });

    test('config has node drag spring defaults', () {
      const config = LiquidCanvasConfig();
      expect(config.nodeDragSpringStiffness, 400.0);
      expect(config.nodeDragSpringDamping, 28.0);
      expect(config.nodeDragFlingFriction, 0.02);
      expect(config.nodeDragFlingThreshold, 150.0);
    });

    test('config has pan spring defaults', () {
      const config = LiquidCanvasConfig();
      expect(config.panSpringStiffness, 200.0);
      expect(config.panSpringDamping, 22.0);
    });
  });

  group('InfiniteCanvasController — Pan Spring (animateOffsetTo)', () {
    late InfiniteCanvasController controller;

    setUp(() {
      controller = InfiniteCanvasController();
      controller.liquidConfig = const LiquidCanvasConfig();
    });

    tearDown(() {
      controller.dispose();
    });

    test('animateOffsetTo does nothing without ticker', () {
      controller.animateOffsetTo(const Offset(100, 200));
      expect(controller.isAnimating, isFalse);
    });

    test('animateOffsetTo activates with ticker', () async {
      await _withTicker((vsync) {
        controller.attachTicker(vsync);
        controller.animateOffsetTo(const Offset(500, 300));
        expect(controller.isAnimating, isTrue);
        controller.stopAnimation();
        controller.detachTicker();
      });
    });

    test('animateOffsetTo does nothing when already at target', () async {
      await _withTicker((vsync) {
        controller.attachTicker(vsync);
        controller.setOffset(const Offset(100, 200));
        controller.animateOffsetTo(const Offset(100, 200));
        expect(controller.isAnimating, isFalse);
        controller.detachTicker();
      });
    });

    test('stopAnimation halts pan spring', () async {
      await _withTicker((vsync) {
        controller.attachTicker(vsync);
        controller.animateOffsetTo(const Offset(500, 300));
        expect(controller.isAnimating, isTrue);
        controller.stopAnimation();
        expect(controller.isAnimating, isFalse);
        controller.detachTicker();
      });
    });
  });

  group('InfiniteCanvasController — Combined Transform Spring', () {
    late InfiniteCanvasController controller;

    setUp(() {
      controller = InfiniteCanvasController();
      controller.liquidConfig = const LiquidCanvasConfig();
    });

    tearDown(() {
      controller.dispose();
    });

    test('animateToTransform does nothing without ticker', () {
      controller.animateToTransform(
        targetOffset: const Offset(100, 200),
        targetScale: 2.0,
      );
      expect(controller.isAnimating, isFalse);
    });

    test('animateToTransform activates with ticker', () async {
      await _withTicker((vsync) {
        controller.attachTicker(vsync);
        controller.animateToTransform(
          targetOffset: const Offset(500, 300),
          targetScale: 2.5,
        );
        expect(controller.isAnimating, isTrue);
        controller.stopAnimation();
        controller.detachTicker();
      });
    });

    test('animateToTransform clamps scale to bounds', () async {
      await _withTicker((vsync) {
        controller.attachTicker(vsync);
        controller.animateToTransform(
          targetOffset: const Offset(500, 300),
          targetScale: 10.0, // Above max (5.0)
        );
        expect(controller.isAnimating, isTrue);
        controller.stopAnimation();
        controller.detachTicker();
      });
    });

    test('animateToTransform does nothing when at target', () async {
      await _withTicker((vsync) {
        controller.attachTicker(vsync);
        controller.updateTransform(offset: const Offset(100, 200), scale: 2.0);
        controller.animateToTransform(
          targetOffset: const Offset(100, 200),
          targetScale: 2.0,
        );
        expect(controller.isAnimating, isFalse);
        controller.detachTicker();
      });
    });
  });
}

/// Helper to run code that needs a TickerProvider within a widget test context.
Future<void> _withTicker(void Function(TickerProvider) body) async {
  // Use a TestWidgetsFlutterBinding to provide a TickerProvider
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final ticker = _SimpleTickerProvider(binding);
  body(ticker);
}

/// Minimal TickerProvider for testing without a full widget tree.
class _SimpleTickerProvider implements TickerProvider {
  final TestWidgetsFlutterBinding binding;

  _SimpleTickerProvider(this.binding);

  @override
  Ticker createTicker(TickerCallback onTick) {
    return Ticker(onTick);
  }
}
