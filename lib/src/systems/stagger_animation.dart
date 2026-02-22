/// ⏳ STAGGER ANIMATION — Sequential delays for groups of nodes.
///
/// Applies staggered timing offsets to animation tracks, enabling
/// cascade and wave-like animation effects across multiple nodes.
///
/// ```dart
/// final config = StaggerConfig(
///   baseDelay: Duration(milliseconds: 100),
///   staggerDelay: Duration(milliseconds: 50),
///   order: StaggerOrder.sequential,
/// );
/// StaggerAnimation.applyStagger(tracks, config);
/// ```
library;

import 'dart:math' as math;
import 'animation_timeline.dart';

/// How children are ordered in the stagger sequence.
enum StaggerOrder {
  /// First to last in the list order.
  sequential,

  /// Last to first.
  reverse,

  /// Random order (seeded for reproducibility).
  random,

  /// Center outward (middle elements first).
  fromCenter,

  /// Edges inward (first and last elements first).
  fromEdges,
}

/// Configuration for stagger animation timing.
class StaggerConfig {
  /// Delay before the first element starts.
  final Duration baseDelay;

  /// Delay between each successive element.
  final Duration staggerDelay;

  /// Order in which elements receive delays.
  final StaggerOrder order;

  /// Random seed (only used for [StaggerOrder.random]).
  final int seed;

  const StaggerConfig({
    this.baseDelay = Duration.zero,
    required this.staggerDelay,
    this.order = StaggerOrder.sequential,
    this.seed = 42,
  });

  Map<String, dynamic> toJson() => {
    'baseDelay': baseDelay.inMilliseconds,
    'staggerDelay': staggerDelay.inMilliseconds,
    'order': order.name,
    'seed': seed,
  };

  factory StaggerConfig.fromJson(Map<String, dynamic> json) => StaggerConfig(
    baseDelay: Duration(milliseconds: json['baseDelay'] as int? ?? 0),
    staggerDelay: Duration(milliseconds: json['staggerDelay'] as int? ?? 50),
    order: StaggerOrder.values.byName(json['order'] as String? ?? 'sequential'),
    seed: json['seed'] as int? ?? 42,
  );
}

/// Applies stagger delays to animation tracks.
class StaggerAnimation {
  const StaggerAnimation._();

  /// Apply stagger delays to a list of tracks.
  ///
  /// Offsets all keyframes in each track by the computed stagger delay.
  /// Returns a new list of tracks with adjusted timing.
  static List<AnimationTrack> applyStagger(
    List<AnimationTrack> tracks,
    StaggerConfig config,
  ) {
    if (tracks.isEmpty) return tracks;

    final indices = _computeOrder(tracks.length, config);
    final result = <AnimationTrack>[];

    for (int i = 0; i < tracks.length; i++) {
      final orderIndex = indices[i];
      final delay = config.baseDelay + config.staggerDelay * orderIndex;
      result.add(_offsetTrack(tracks[i], delay));
    }

    return result;
  }

  /// Compute the delay offsets for each track based on ordering.
  static Map<int, Duration> computeDelays(int count, StaggerConfig config) {
    final indices = _computeOrder(count, config);
    return {
      for (int i = 0; i < count; i++)
        i: config.baseDelay + config.staggerDelay * indices[i],
    };
  }

  static List<int> _computeOrder(int count, StaggerConfig config) {
    switch (config.order) {
      case StaggerOrder.sequential:
        return List.generate(count, (i) => i);
      case StaggerOrder.reverse:
        return List.generate(count, (i) => count - 1 - i);
      case StaggerOrder.random:
        final indices = List.generate(count, (i) => i);
        final rng = math.Random(config.seed);
        indices.shuffle(rng);
        return indices;
      case StaggerOrder.fromCenter:
        final center = count / 2.0;
        final sorted = List.generate(count, (i) => i);
        sorted.sort((a, b) => (a - center).abs().compareTo((b - center).abs()));
        final result = List.filled(count, 0);
        for (int rank = 0; rank < sorted.length; rank++) {
          result[sorted[rank]] = rank;
        }
        return result;
      case StaggerOrder.fromEdges:
        final center = count / 2.0;
        final sorted = List.generate(count, (i) => i);
        sorted.sort((a, b) => (b - center).abs().compareTo((a - center).abs()));
        final result = List.filled(count, 0);
        for (int rank = 0; rank < sorted.length; rank++) {
          result[sorted[rank]] = rank;
        }
        return result;
    }
  }

  static AnimationTrack _offsetTrack(AnimationTrack track, Duration offset) {
    final newTrack = AnimationTrack(nodeId: track.nodeId);
    for (final kf in track.keyframes) {
      newTrack.addKeyframe(
        Keyframe(
          time: kf.time + offset,
          property: kf.property,
          value: kf.value,
          easing: kf.easing,
        ),
      );
    }
    return newTrack;
  }
}
