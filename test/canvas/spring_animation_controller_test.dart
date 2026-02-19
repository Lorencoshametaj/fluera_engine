import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/canvas/spring_animation_controller.dart';

void main() {
  group('SpringAnimationController — Scalar Spring', () {
    late SpringAnimationController controller;

    setUp(() {
      controller = SpringAnimationController();
    });

    tearDown(() {
      controller.dispose();
    });

    test('animateTo does nothing without ticker', () {
      controller.animateTo(100.0);
      expect(controller.isAnimating, isFalse);
      expect(controller.value, 0.0);
    });

    test('animateTo activates with ticker', () async {
      await _withTicker((vsync) {
        controller.attachTicker(vsync);
        controller.animateTo(100.0);
        expect(controller.isAnimating, isTrue);
        controller.stop();
        controller.detachTicker();
      });
    });

    test('snapTo updates value immediately without animation', () {
      controller.snapTo(42.0);
      expect(controller.value, 42.0);
      expect(controller.isAnimating, isFalse);
    });

    test('snapTo fires onUpdate callback', () {
      double? received;
      controller.onUpdate = (v) => received = v;
      controller.snapTo(99.0);
      expect(received, 99.0);
    });

    test('stop cancels running scalar animation', () async {
      await _withTicker((vsync) {
        controller.attachTicker(vsync);
        controller.animateTo(100.0);
        expect(controller.isAnimating, isTrue);
        controller.stop();
        expect(controller.isAnimating, isFalse);
        controller.detachTicker();
      });
    });
  });

  group('SpringAnimationController — Offset Spring (2D)', () {
    late SpringAnimationController controller;

    setUp(() {
      controller = SpringAnimationController();
    });

    tearDown(() {
      controller.dispose();
    });

    test('animateOffsetTo does nothing without ticker', () {
      controller.animateOffsetTo(const Offset(100, 200));
      expect(controller.isAnimating, isFalse);
      expect(controller.offsetValue, Offset.zero);
    });

    test('animateOffsetTo activates with ticker', () async {
      await _withTicker((vsync) {
        controller.attachTicker(vsync);
        controller.animateOffsetTo(const Offset(100, 200));
        expect(controller.isAnimating, isTrue);
        controller.stop();
        controller.detachTicker();
      });
    });

    test('snapOffsetTo updates offset immediately', () {
      controller.snapOffsetTo(const Offset(50, 75));
      expect(controller.offsetValue, const Offset(50, 75));
      expect(controller.isAnimating, isFalse);
    });

    test('snapOffsetTo fires onOffsetUpdate callback', () {
      Offset? received;
      controller.onOffsetUpdate = (o) => received = o;
      controller.snapOffsetTo(const Offset(10, 20));
      expect(received, const Offset(10, 20));
    });

    test('fling state is cleared by stop before animateOffsetTo', () async {
      await _withTicker((vsync) {
        controller.attachTicker(vsync);
        controller.snapOffsetTo(Offset.zero);
        controller.fling(const Offset(1000, 500));
        expect(controller.isAnimating, isTrue);
        // Stop clears fling
        controller.stop();
        expect(controller.isAnimating, isFalse);
        controller.detachTicker();
      });
    });
  });

  group('SpringAnimationController — Fling', () {
    late SpringAnimationController controller;

    setUp(() {
      controller = SpringAnimationController();
    });

    tearDown(() {
      controller.dispose();
    });

    test('fling does nothing without ticker', () {
      controller.fling(const Offset(1000, 500));
      expect(controller.isAnimating, isFalse);
    });

    test('fling activates with sufficient velocity', () async {
      await _withTicker((vsync) {
        controller.attachTicker(vsync);
        controller.fling(const Offset(1000, 500));
        expect(controller.isAnimating, isTrue);
        controller.stop();
        controller.detachTicker();
      });
    });

    test('fling ignores tiny velocity', () async {
      await _withTicker((vsync) {
        controller.attachTicker(vsync);
        controller.fling(const Offset(0.1, 0.1)); // Below stopVelocity default
        expect(controller.isAnimating, isFalse);
        controller.detachTicker();
      });
    });
  });

  group('SpringAnimationController — Lifecycle', () {
    test('dispose is safe to call multiple times', () {
      final controller = SpringAnimationController();
      controller.dispose();
      controller.dispose(); // Should not throw
    });

    test('detachTicker without attach is safe', () {
      final controller = SpringAnimationController();
      controller.detachTicker(); // Should not throw
      controller.dispose();
    });

    test('dispose cleans up running animation', () async {
      final controller = SpringAnimationController();
      await _withTicker((vsync) {
        controller.attachTicker(vsync);
        controller.animateTo(100.0);
        expect(controller.isAnimating, isTrue);
        controller.dispose();
        expect(controller.isAnimating, isFalse);
      });
    });

    test('onComplete is null after dispose', () async {
      final controller = SpringAnimationController();
      controller.onComplete = () {};
      controller.dispose();
      expect(controller.onComplete, isNull);
    });
  });

  group('SpringAnimationController — Presets', () {
    test('snappy preset has expected stiffness', () {
      expect(SpringAnimationController.snappy.stiffness, 400.0);
    });

    test('smooth preset has expected stiffness', () {
      expect(SpringAnimationController.smooth.stiffness, 200.0);
    });

    test('bouncy preset has lower damping for oscillation', () {
      expect(SpringAnimationController.bouncy.damping, 15.0);
    });
  });
}

/// Helper to run code that needs a TickerProvider within a widget test context.
Future<void> _withTicker(void Function(TickerProvider) body) async {
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
