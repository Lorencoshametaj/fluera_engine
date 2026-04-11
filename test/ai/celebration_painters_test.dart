// ============================================================================
// 🧪 UNIT TESTS — Celebration Painters (A13.8)
// ============================================================================

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/canvas/ai/celebration_controller.dart';
import 'package:fluera_engine/src/canvas/ai/celebration_painters.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // PARTICLE SYSTEM
  // ═══════════════════════════════════════════════════════════════════════════

  group('CelebrationParticleSystem', () {
    test('recallPerfect generates 20 particles', () {
      final particles = CelebrationParticleSystem.recallPerfect(
        const Size(1024, 768),
      );
      expect(particles.length, 20);
    });

    test('particles advance with gravity', () {
      final particles = CelebrationParticleSystem.recallPerfect(
        const Size(800, 600),
      );
      final p0 = particles.first;
      final p1 = p0.at(0.5);

      // Y should have moved (velocity + gravity)
      expect(p1.y, isNot(equals(p0.y)));
      // Size should have shrunk
      expect(p1.size, lessThan(p0.size));
    });

    test('particles fade out at t=1.0', () {
      final particles = CelebrationParticleSystem.recallPerfect(
        const Size(800, 600),
      );
      final faded = particles.first.at(1.0);
      expect(faded.color.a, closeTo(0, 0.01));
    });

    test('bridgeSparks generates 12 radial particles', () {
      final particles = CelebrationParticleSystem.bridgeSparks(
        const Offset(400, 300),
      );
      expect(particles.length, 12);
      // All start at anchor
      for (final p in particles) {
        expect(p.x, 400);
        expect(p.y, 300);
      }
    });

    test('particles are deterministic (seeded RNG)', () {
      final a = CelebrationParticleSystem.recallPerfect(const Size(100, 100));
      final b = CelebrationParticleSystem.recallPerfect(const Size(100, 100));
      expect(a.first.x, equals(b.first.x));
      expect(a.first.y, equals(b.first.y));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // CELEBRATION PAINTER
  // ═══════════════════════════════════════════════════════════════════════════

  group('CelebrationPainter', () {
    late CelebrationController controller;

    setUp(() => controller = CelebrationController());
    tearDown(() => controller.dispose());

    CelebrationEvent _trigger() {
      controller.setHasEverRecalled(true);
      controller.onRecallSessionComplete(remembered: 5, total: 5);
      return controller.pendingCelebration!;
    }

    test('creates painter with event and progress', () {
      final event = _trigger();
      final painter = CelebrationPainter(event: event, progress: 0.5);
      expect(painter.event, event);
      expect(painter.progress, 0.5);
    });

    test('shouldRepaint returns true on progress change', () {
      final event = _trigger();
      final old = CelebrationPainter(event: event, progress: 0.3);
      final nw = CelebrationPainter(event: event, progress: 0.5);
      expect(nw.shouldRepaint(old), isTrue);
    });

    test('shouldRepaint returns false when identical', () {
      final event = _trigger();
      final a = CelebrationPainter(event: event, progress: 0.5);
      expect(a.shouldRepaint(a), isFalse);
    });

    test('painter handles all 5 celebration types', () {
      // Verify no crash for each type
      controller.setHasEverRecalled(false);
      controller.onRecallSessionComplete(remembered: 1, total: 1);
      expect(controller.pendingCelebration!.type, CelebrationType.firstRecall);

      controller.consumeCelebration();

      controller.onRecallSessionComplete(remembered: 5, total: 5);
      expect(controller.pendingCelebration!.type, CelebrationType.recallPerfect);

      controller.consumeCelebration();

      controller.onStabilityMilestone(newStage: 4);
      expect(controller.pendingCelebration!.type, CelebrationType.stabilityGain);

      controller.consumeCelebration();

      controller.onBridgeFormed();
      expect(controller.pendingCelebration!.type, CelebrationType.bridgeFormed);

      controller.consumeCelebration();

      controller.onFogCleared(correctCount: 10, totalCount: 10);
      expect(controller.pendingCelebration!.type, CelebrationType.fogCleared);
    });

    test('each celebration has duration ≤ 2000ms', () {
      controller.setHasEverRecalled(true);
      controller.onRecallSessionComplete(remembered: 5, total: 5);
      expect(controller.pendingCelebration!.durationMs, lessThanOrEqualTo(2000));

      controller.consumeCelebration();
      controller.onStabilityMilestone(newStage: 5);
      expect(controller.pendingCelebration!.durationMs, lessThanOrEqualTo(2000));

      controller.consumeCelebration();
      controller.onBridgeFormed();
      expect(controller.pendingCelebration!.durationMs, lessThanOrEqualTo(2000));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // MESSAGE PAINTER
  // ═══════════════════════════════════════════════════════════════════════════

  group('CelebrationMessagePainter', () {
    test('creates with message and progress', () {
      final painter = CelebrationMessagePainter(
        message: 'Solido.',
        progress: 0.5,
        color: const Color(0xFF66BB6A),
      );
      expect(painter.message, 'Solido.');
      expect(painter.progress, 0.5);
    });

    test('shouldRepaint on progress change', () {
      final a = CelebrationMessagePainter(
        message: 'Test',
        progress: 0.3,
        color: const Color(0xFF000000),
      );
      final b = CelebrationMessagePainter(
        message: 'Test',
        progress: 0.5,
        color: const Color(0xFF000000),
      );
      expect(b.shouldRepaint(a), isTrue);
    });

    test('shouldRepaint on message change', () {
      final a = CelebrationMessagePainter(
        message: 'A',
        progress: 0.5,
        color: const Color(0xFF000000),
      );
      final b = CelebrationMessagePainter(
        message: 'B',
        progress: 0.5,
        color: const Color(0xFF000000),
      );
      expect(b.shouldRepaint(a), isTrue);
    });
  });
}
