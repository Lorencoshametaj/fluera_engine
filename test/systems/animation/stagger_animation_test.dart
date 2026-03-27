import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/systems/stagger_animation.dart';
import 'package:fluera_engine/src/systems/animation_timeline.dart';
import 'dart:ui';

void main() {
  group('StaggerAnimation Tests', () {
    test('applyStagger offsets tracks sequentially', () {
      final t1 = AnimationTrack(nodeId: 'n1')..addKeyframe(
        Keyframe(time: Duration.zero, property: 'opacity', value: 1.0),
      );
      final t2 = AnimationTrack(nodeId: 'n2')..addKeyframe(
        Keyframe(time: Duration.zero, property: 'opacity', value: 1.0),
      );
      final t3 = AnimationTrack(nodeId: 'n3')..addKeyframe(
        Keyframe(time: Duration.zero, property: 'opacity', value: 1.0),
      );

      final tracks = [t1, t2, t3];

      final config = const StaggerConfig(
        baseDelay: Duration(milliseconds: 100),
        staggerDelay: Duration(milliseconds: 50),
        order: StaggerOrder.sequential,
      );

      final staggered = StaggerAnimation.applyStagger(tracks, config);

      expect(staggered.length, 3);
      expect(
        staggered[0].keyframes.first.time,
        const Duration(milliseconds: 100),
      );
      expect(
        staggered[1].keyframes.first.time,
        const Duration(milliseconds: 150),
      );
      expect(
        staggered[2].keyframes.first.time,
        const Duration(milliseconds: 200),
      );
    });

    test('applyStagger in reverse order', () {
      final t1 = AnimationTrack(nodeId: 'n1')..addKeyframe(
        Keyframe(time: Duration.zero, property: 'opacity', value: 1.0),
      );
      final t2 = AnimationTrack(nodeId: 'n2')..addKeyframe(
        Keyframe(time: Duration.zero, property: 'opacity', value: 1.0),
      );
      final t3 = AnimationTrack(nodeId: 'n3')..addKeyframe(
        Keyframe(time: Duration.zero, property: 'opacity', value: 1.0),
      );

      final config = const StaggerConfig(
        staggerDelay: Duration(milliseconds: 10),
        order: StaggerOrder.reverse,
      );

      final staggered = StaggerAnimation.applyStagger([t1, t2, t3], config);

      // t1 should be last (delay 20), t2 middle (10), t3 first (0)
      expect(
        staggered[0].keyframes.first.time,
        const Duration(milliseconds: 20),
      ); // index 2
      expect(
        staggered[1].keyframes.first.time,
        const Duration(milliseconds: 10),
      ); // index 1
      expect(
        staggered[2].keyframes.first.time,
        const Duration(milliseconds: 0),
      ); // index 0
    });

    test('computeDelays fromCenter', () {
      final config = const StaggerConfig(
        staggerDelay: Duration(milliseconds: 10),
        order: StaggerOrder.fromCenter,
      );

      // For 5 items: center is 2.5
      // Distances: [0]:2.5, [1]:1.5, [2]:0.5, [3]:0.5, [4]:1.5
      // Rank: [2] and [3] are first (0, 1) or (1, 0)
      //       [1] and [4] are next (2, 3) or (3, 2)
      //       [0] is last (4)
      final delays = StaggerAnimation.computeDelays(5, config);

      expect(delays.length, 5);

      // Index 2 should be the smallest or tied for smallest
      expect(delays[2]!.inMilliseconds, 0);
      expect(delays[3]!.inMilliseconds, 10);

      // Edges should have largest delays
      expect(delays[0]!.inMilliseconds, 40);
    });

    test('computeDelays fromEdges', () {
      final config = const StaggerConfig(
        staggerDelay: Duration(milliseconds: 10),
        order: StaggerOrder.fromEdges,
      );

      final delays = StaggerAnimation.computeDelays(5, config);

      // Edges should have smallest delays
      expect(delays[0]!.inMilliseconds, 0);

      // Center should have largest delays
      // For 5 items fromEdges: distances from center (2.5): [0]=2.5, [1]=1.5, [2]=0.5, [3]=0.5, [4]=1.5
      // fromEdges sorts desc by dist, so edges get rank 0 (smallest delay), center gets highest
      // But the exact ranks depend on stable sort of tied elements
      expect(delays[2]!.inMilliseconds, greaterThanOrEqualTo(30));
    });

    test('serialization roundtrip', () {
      final config = const StaggerConfig(
        baseDelay: Duration(milliseconds: 200),
        staggerDelay: Duration(milliseconds: 40),
        order: StaggerOrder.random,
        seed: 123,
      );

      final json = config.toJson();
      expect(json['baseDelay'], 200);
      expect(json['order'], 'random');

      final restored = StaggerConfig.fromJson(json);
      expect(restored.baseDelay.inMilliseconds, 200);
      expect(restored.staggerDelay.inMilliseconds, 40);
      expect(restored.order, StaggerOrder.random);
      expect(restored.seed, 123);
    });
  });
}
