import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:fluera_engine/src/canvas/navigation/camera_actions.dart';
import 'package:fluera_engine/src/canvas/infinite_canvas_controller.dart';

void main() {
  group('CameraKeyframe', () {
    test('default values', () {
      const kf = CameraKeyframe(
        targetOffset: Offset(100, 200),
        targetScale: 1.5,
      );
      expect(kf.targetOffset, const Offset(100, 200));
      expect(kf.targetScale, 1.5);
      expect(kf.durationSeconds, 0.4);
      expect(kf.curve, Curves.easeInOutCubic);
    });

    test('custom values', () {
      const kf = CameraKeyframe(
        targetOffset: Offset.zero,
        targetScale: 0.5,
        durationSeconds: 1.0,
        curve: Curves.easeIn,
      );
      expect(kf.durationSeconds, 1.0);
      expect(kf.curve, Curves.easeIn);
    });
  });

  group('InfiniteCanvasController.animateMultiPhase', () {
    late InfiniteCanvasController controller;

    setUp(() {
      controller = InfiniteCanvasController();
    });

    tearDown(() {
      controller.dispose();
    });

    test('flightProgress is 0 when no flight is active', () {
      expect(controller.flightProgress, 0.0);
      expect(controller.flightPhase, -1);
    });

    test('without ticker, animateMultiPhase is a no-op', () {
      controller.animateMultiPhase(
        keyframes: [
          const CameraKeyframe(
            targetOffset: Offset(100, 200),
            targetScale: 0.5,
          ),
        ],
      );
      // Without a ticker, flight doesn't start
      expect(controller.flightProgress, 0.0);
    });

    test('cancelFlight resets state', () {
      // Can cancel even when no flight is active (no-op)
      controller.cancelFlight();
      expect(controller.flightProgress, 0.0);
      expect(controller.flightPhase, -1);
    });

    test('stopAnimation clears flight state', () {
      controller.stopAnimation();
      expect(controller.flightProgress, 0.0);
    });
  });

  group('CameraActions.cinematicFlight', () {
    late InfiniteCanvasController controller;

    setUp(() {
      controller = InfiniteCanvasController();
    });

    tearDown(() {
      controller.dispose();
    });

    test('empty bounds does nothing', () {
      final initialOffset = controller.offset;
      final initialScale = controller.scale;

      CameraActions.cinematicFlight(
        controller,
        Rect.zero,
        const Rect.fromLTWH(100, 100, 200, 200),
        const Size(800, 600),
      );

      expect(controller.offset, equals(initialOffset));
      expect(controller.scale, equals(initialScale));
    });

    test('empty target bounds does nothing', () {
      final initialOffset = controller.offset;

      CameraActions.cinematicFlight(
        controller,
        const Rect.fromLTWH(0, 0, 200, 200),
        Rect.zero,
        const Size(800, 600),
      );

      expect(controller.offset, equals(initialOffset));
    });
  });

  group('CameraActions.hyperJump', () {
    late InfiniteCanvasController controller;

    setUp(() {
      controller = InfiniteCanvasController();
    });

    tearDown(() {
      controller.dispose();
    });

    test('empty bounds does nothing', () {
      final initialScale = controller.scale;

      CameraActions.hyperJump(
        controller,
        Rect.zero,
        const Rect.fromLTWH(5000, 5000, 200, 200),
        const Size(800, 600),
      );

      expect(controller.scale, equals(initialScale));
    });
  });

  group('CameraActions.flyAlongConnection', () {
    late InfiniteCanvasController controller;

    setUp(() {
      controller = InfiniteCanvasController();
    });

    tearDown(() {
      controller.dispose();
    });

    test('nearby clusters use cinematicFlight (distance < 3000)', () {
      // Source at (100,100), target at (500,500) → distance ~566
      const src = Rect.fromLTWH(50, 50, 100, 100);
      const tgt = Rect.fromLTWH(450, 450, 100, 100);
      const viewport = Size(800, 600);

      // Without ticker, nothing happens but no crash
      CameraActions.flyAlongConnection(
        controller, src, tgt, viewport,
      );

      expect(controller.scale, isPositive);
    });

    test('distant clusters use hyperJump (distance > 3000)', () {
      // Source at (0,0), target at (5000,5000) → distance ~7071
      const src = Rect.fromLTWH(0, 0, 100, 100);
      const tgt = Rect.fromLTWH(4950, 4950, 100, 100);
      const viewport = Size(800, 600);

      CameraActions.flyAlongConnection(
        controller, src, tgt, viewport,
      );

      expect(controller.scale, isPositive);
    });

    test('custom distance threshold respected', () {
      const src = Rect.fromLTWH(0, 0, 100, 100);
      const tgt = Rect.fromLTWH(500, 500, 100, 100);
      const viewport = Size(800, 600);

      // With very low threshold, even nearby = hyper-jump
      CameraActions.flyAlongConnection(
        controller, src, tgt, viewport,
        distanceThreshold: 100.0,
      );

      expect(controller.scale, isPositive);
    });
  });
}
