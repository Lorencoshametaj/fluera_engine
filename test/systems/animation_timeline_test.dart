import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/systems/animation_timeline.dart';

void main() {
  // ===========================================================================
  // Keyframe
  // ===========================================================================

  group('Keyframe', () {
    test('stores all fields', () {
      final kf = Keyframe(
        time: const Duration(seconds: 1),
        property: 'opacity',
        value: 0.5,
        easing: EasingType.easeIn,
      );

      expect(kf.time, const Duration(seconds: 1));
      expect(kf.property, 'opacity');
      expect(kf.value, 0.5);
      expect(kf.easing, EasingType.easeIn);
      expect(kf.timeMs, 1000);
    });

    test('JSON roundtrip for double value', () {
      final kf = Keyframe(
        time: const Duration(milliseconds: 500),
        property: 'opacity',
        value: 0.75,
      );

      final json = kf.toJson();
      final restored = Keyframe.fromJson(json);

      expect(restored.timeMs, 500);
      expect(restored.property, 'opacity');
      expect(restored.value, closeTo(0.75, 0.001));
    });

    test('JSON roundtrip for Color value', () {
      final kf = Keyframe(
        time: Duration.zero,
        property: 'fillColor',
        value: const ui.Color(0xFFFF0000),
      );

      final json = kf.toJson();
      expect(json['valueType'], 'color');

      final restored = Keyframe.fromJson(json);
      expect(restored.value, isA<ui.Color>());
    });

    test('JSON roundtrip for Offset value', () {
      final kf = Keyframe(
        time: Duration.zero,
        property: 'position',
        value: const Offset(10, 20),
      );

      final json = kf.toJson();
      expect(json['valueType'], 'offset');

      final restored = Keyframe.fromJson(json);
      expect(restored.value, isA<Offset>());
      expect((restored.value as Offset).dx, 10);
      expect((restored.value as Offset).dy, 20);
    });

    test('JSON roundtrip for int value', () {
      final kf = Keyframe(time: Duration.zero, property: 'count', value: 42);

      final json = kf.toJson();
      final restored = Keyframe.fromJson(json);
      expect(restored.value, 42);
    });

    test('default easing is easeInOut', () {
      final kf = Keyframe(time: Duration.zero, property: 'x', value: 0.0);
      expect(kf.easing, EasingType.easeInOut);
    });
  });

  // ===========================================================================
  // AnimationTrack
  // ===========================================================================

  group('AnimationTrack', () {
    test('addKeyframe maintains time ordering', () {
      final track = AnimationTrack(nodeId: 'n1');
      track.addKeyframe(
        Keyframe(
          time: const Duration(seconds: 2),
          property: 'opacity',
          value: 1.0,
        ),
      );
      track.addKeyframe(
        Keyframe(time: Duration.zero, property: 'opacity', value: 0.0),
      );
      track.addKeyframe(
        Keyframe(
          time: const Duration(seconds: 1),
          property: 'opacity',
          value: 0.5,
        ),
      );

      expect(track.keyframes[0].timeMs, 0);
      expect(track.keyframes[1].timeMs, 1000);
      expect(track.keyframes[2].timeMs, 2000);
    });

    test('removeKeyframe removes by time and property', () {
      final track = AnimationTrack(nodeId: 'n1');
      track.addKeyframe(
        Keyframe(time: Duration.zero, property: 'opacity', value: 0.0),
      );
      track.addKeyframe(
        Keyframe(time: Duration.zero, property: 'x', value: 10.0),
      );
      track.addKeyframe(
        Keyframe(
          time: const Duration(seconds: 1),
          property: 'opacity',
          value: 1.0,
        ),
      );

      track.removeKeyframe(Duration.zero, 'opacity');

      expect(track.keyframes, hasLength(2));
      expect(track.keyframes[0].property, 'x');
    });

    test('forProperty filters keyframes', () {
      final track = AnimationTrack(nodeId: 'n1');
      track.addKeyframe(
        Keyframe(time: Duration.zero, property: 'opacity', value: 0.0),
      );
      track.addKeyframe(
        Keyframe(time: Duration.zero, property: 'x', value: 10.0),
      );
      track.addKeyframe(
        Keyframe(
          time: const Duration(seconds: 1),
          property: 'opacity',
          value: 1.0,
        ),
      );

      final opacityKFs = track.forProperty('opacity');
      expect(opacityKFs, hasLength(2));
    });

    test('animatedProperties returns unique set', () {
      final track = AnimationTrack(nodeId: 'n1');
      track.addKeyframe(
        Keyframe(time: Duration.zero, property: 'opacity', value: 0.0),
      );
      track.addKeyframe(
        Keyframe(time: Duration.zero, property: 'x', value: 10.0),
      );
      track.addKeyframe(
        Keyframe(
          time: const Duration(seconds: 1),
          property: 'opacity',
          value: 1.0,
        ),
      );

      expect(track.animatedProperties, {'opacity', 'x'});
    });

    test('duration returns time of last keyframe', () {
      final track = AnimationTrack(nodeId: 'n1');
      expect(track.duration, Duration.zero);

      track.addKeyframe(
        Keyframe(
          time: const Duration(seconds: 3),
          property: 'opacity',
          value: 1.0,
        ),
      );
      expect(track.duration, const Duration(seconds: 3));
    });

    test('JSON roundtrip preserves keyframes', () {
      final track = AnimationTrack(nodeId: 'star1');
      track.addKeyframe(
        Keyframe(time: Duration.zero, property: 'opacity', value: 0.0),
      );
      track.addKeyframe(
        Keyframe(
          time: const Duration(seconds: 2),
          property: 'opacity',
          value: 1.0,
        ),
      );

      final json = track.toJson();
      final restored = AnimationTrack.fromJson(json);

      expect(restored.nodeId, 'star1');
      expect(restored.keyframes, hasLength(2));
    });
  });

  // ===========================================================================
  // AnimationTimeline
  // ===========================================================================

  group('AnimationTimeline', () {
    test('addTrack and removeTrack', () {
      final timeline = AnimationTimeline();
      final track = AnimationTrack(nodeId: 'n1');
      timeline.addTrack(track);

      expect(timeline.tracks, hasLength(1));
      expect(timeline.tracks['n1'], isNotNull);

      timeline.removeTrack('n1');
      expect(timeline.tracks, isEmpty);
    });

    test('totalFrames calculation', () {
      final timeline = AnimationTimeline(
        totalDuration: const Duration(seconds: 2),
        fps: 30,
      );

      expect(timeline.totalFrames, 60);
    });

    test('frameDuration calculation', () {
      final timeline = AnimationTimeline(fps: 60);
      expect(timeline.frameDuration.inMilliseconds, closeTo(17, 1));
    });

    test('evaluate returns null for missing track', () {
      final timeline = AnimationTimeline();
      expect(timeline.evaluate('nope', 'opacity', Duration.zero), isNull);
    });

    test('evaluate returns null for missing property', () {
      final timeline = AnimationTimeline();
      final track = AnimationTrack(nodeId: 'n1');
      track.addKeyframe(
        Keyframe(time: Duration.zero, property: 'x', value: 10.0),
      );
      timeline.addTrack(track);

      expect(timeline.evaluate('n1', 'opacity', Duration.zero), isNull);
    });

    test('evaluate interpolates double values', () {
      final timeline = AnimationTimeline();
      final track = AnimationTrack(nodeId: 'n1');
      track.addKeyframe(
        Keyframe(
          time: Duration.zero,
          property: 'opacity',
          value: 0.0,
          easing: EasingType.linear,
        ),
      );
      track.addKeyframe(
        Keyframe(
          time: const Duration(seconds: 2),
          property: 'opacity',
          value: 1.0,
          easing: EasingType.linear,
        ),
      );
      timeline.addTrack(track);

      // Midpoint with linear easing
      final mid = timeline.evaluate(
        'n1',
        'opacity',
        const Duration(seconds: 1),
      );
      expect(mid, closeTo(0.5, 0.01));
    });

    test('evaluate clamps at first keyframe before start', () {
      final timeline = AnimationTimeline();
      final track = AnimationTrack(nodeId: 'n1');
      track.addKeyframe(
        Keyframe(
          time: const Duration(seconds: 1),
          property: 'opacity',
          value: 0.5,
        ),
      );
      timeline.addTrack(track);

      expect(timeline.evaluate('n1', 'opacity', Duration.zero), 0.5);
    });

    test('evaluate clamps at last keyframe after end', () {
      final timeline = AnimationTimeline();
      final track = AnimationTrack(nodeId: 'n1');
      track.addKeyframe(
        Keyframe(time: Duration.zero, property: 'opacity', value: 0.0),
      );
      track.addKeyframe(
        Keyframe(
          time: const Duration(seconds: 1),
          property: 'opacity',
          value: 1.0,
        ),
      );
      timeline.addTrack(track);

      expect(
        timeline.evaluate('n1', 'opacity', const Duration(seconds: 5)),
        1.0,
      );
    });

    test('JSON roundtrip', () {
      final timeline = AnimationTimeline(
        totalDuration: const Duration(seconds: 3),
        fps: 24,
        loop: true,
      );
      final track = AnimationTrack(nodeId: 'n1');
      track.addKeyframe(
        Keyframe(time: Duration.zero, property: 'x', value: 0.0),
      );
      timeline.addTrack(track);

      final json = timeline.toJson();
      final restored = AnimationTimeline.fromJson(json);

      expect(restored.totalDuration.inMilliseconds, 3000);
      expect(restored.fps, 24);
      expect(restored.loop, true);
      expect(restored.tracks, hasLength(1));
    });
  });

  // ===========================================================================
  // PropertyInterpolator
  // ===========================================================================

  group('PropertyInterpolator', () {
    test('interpolates Offset values', () {
      final kfs = [
        Keyframe(
          time: Duration.zero,
          property: 'pos',
          value: const Offset(0, 0),
          easing: EasingType.linear,
        ),
        Keyframe(
          time: const Duration(seconds: 1),
          property: 'pos',
          value: const Offset(100, 200),
          easing: EasingType.linear,
        ),
      ];

      final result = PropertyInterpolator.interpolate(
        kfs,
        const Duration(milliseconds: 500),
      );
      expect(result, isA<Offset>());
      expect((result as Offset).dx, closeTo(50, 1));
      expect(result.dy, closeTo(100, 1));
    });

    test('returns null for empty keyframes', () {
      expect(PropertyInterpolator.interpolate([], Duration.zero), isNull);
    });

    test('returns first value before start', () {
      final kfs = [
        Keyframe(time: const Duration(seconds: 1), property: 'x', value: 42.0),
      ];
      expect(PropertyInterpolator.interpolate(kfs, Duration.zero), 42.0);
    });

    test('returns last value after end', () {
      final kfs = [
        Keyframe(time: Duration.zero, property: 'x', value: 0.0),
        Keyframe(time: const Duration(seconds: 1), property: 'x', value: 100.0),
      ];
      expect(
        PropertyInterpolator.interpolate(kfs, const Duration(seconds: 5)),
        100.0,
      );
    });

    test('easeIn produces slower start', () {
      final kfs = [
        Keyframe(
          time: Duration.zero,
          property: 'x',
          value: 0.0,
          easing: EasingType.easeIn,
        ),
        Keyframe(time: const Duration(seconds: 1), property: 'x', value: 100.0),
      ];

      final quarter = PropertyInterpolator.interpolate(
        kfs,
        const Duration(milliseconds: 250),
      );
      // With easeIn (t*t), at t=0.25 → 0.0625 → value ≈ 6.25
      expect((quarter as double), lessThan(25)); // Less than linear 25
    });

    test('int values are interpolated and rounded', () {
      final kfs = [
        Keyframe(
          time: Duration.zero,
          property: 'count',
          value: 0,
          easing: EasingType.linear,
        ),
        Keyframe(
          time: const Duration(seconds: 1),
          property: 'count',
          value: 10,
        ),
      ];

      final result = PropertyInterpolator.interpolate(
        kfs,
        const Duration(milliseconds: 500),
      );
      expect(result, isA<int>());
      expect(result, 5);
    });
  });
}
