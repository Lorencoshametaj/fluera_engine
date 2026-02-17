import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Easing curve types for keyframe interpolation.
enum EasingType { linear, easeIn, easeOut, easeInOut, spring }

/// A single keyframe in an animation track.
///
/// Defines the value of a property at a specific point in time,
/// with an easing curve controlling interpolation to the next keyframe.
class Keyframe {
  /// Time position within the timeline.
  final Duration time;

  /// Property path being animated (e.g. "opacity", "transform.x",
  /// "fillColor", "strokeWidth").
  final String property;

  /// The value at this keyframe.
  ///
  /// Supported types: `double`, `int`, `Color` (as int), `Offset`,
  /// `Matrix4` (as storage list).
  final dynamic value;

  /// Easing curve for interpolation from THIS keyframe to the next.
  final EasingType easing;

  const Keyframe({
    required this.time,
    required this.property,
    required this.value,
    this.easing = EasingType.easeInOut,
  });

  /// Time in milliseconds (for easier math).
  int get timeMs => time.inMilliseconds;

  // -------------------------------------------------------------------------
  // Serialization
  // -------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
    'timeMs': time.inMilliseconds,
    'property': property,
    'value': _serializeValue(value),
    'valueType': _valueTypeName(value),
    'easing': easing.name,
  };

  factory Keyframe.fromJson(Map<String, dynamic> json) {
    return Keyframe(
      time: Duration(milliseconds: json['timeMs'] as int),
      property: json['property'] as String,
      value: _deserializeValue(json['value'], json['valueType'] as String),
      easing: EasingType.values.firstWhere(
        (e) => e.name == json['easing'],
        orElse: () => EasingType.easeInOut,
      ),
    );
  }

  static dynamic _serializeValue(dynamic value) {
    if (value is ui.Color) return value.toARGB32();
    if (value is Offset) return {'dx': value.dx, 'dy': value.dy};
    if (value is Matrix4) return value.storage.toList();
    return value; // double, int, String
  }

  static dynamic _deserializeValue(dynamic raw, String type) {
    switch (type) {
      case 'double':
        return (raw as num).toDouble();
      case 'int':
        return raw as int;
      case 'color':
        return ui.Color((raw as int).toUnsigned(32));
      case 'offset':
        final m = raw as Map<String, dynamic>;
        return Offset((m['dx'] as num).toDouble(), (m['dy'] as num).toDouble());
      case 'matrix4':
        return Matrix4.fromList(
          (raw as List).map((n) => (n as num).toDouble()).toList(),
        );
      default:
        return raw;
    }
  }

  static String _valueTypeName(dynamic value) {
    if (value is double) return 'double';
    if (value is int) return 'int';
    if (value is ui.Color) return 'color';
    if (value is Offset) return 'offset';
    if (value is Matrix4) return 'matrix4';
    return 'dynamic';
  }
}

// ---------------------------------------------------------------------------
// Animation Track
// ---------------------------------------------------------------------------

/// Ordered sequence of keyframes for a single node.
///
/// A track contains keyframes for potentially multiple properties
/// of the same node, sorted by time.
class AnimationTrack {
  /// Node ID this track animates.
  final String nodeId;

  /// Keyframes sorted by time.
  final List<Keyframe> keyframes;

  AnimationTrack({required this.nodeId, List<Keyframe>? keyframes})
    : keyframes = keyframes ?? [];

  /// Add a keyframe, maintaining time order.
  void addKeyframe(Keyframe kf) {
    final idx = keyframes.indexWhere((k) => k.timeMs >= kf.timeMs);
    if (idx < 0) {
      keyframes.add(kf);
    } else {
      keyframes.insert(idx, kf);
    }
  }

  /// Remove keyframes at a specific time for a property.
  void removeKeyframe(Duration time, String property) {
    keyframes.removeWhere((k) => k.time == time && k.property == property);
  }

  /// Get all keyframes for a specific property.
  List<Keyframe> forProperty(String property) {
    return keyframes.where((k) => k.property == property).toList();
  }

  /// Get the set of all animated properties in this track.
  Set<String> get animatedProperties {
    return keyframes.map((k) => k.property).toSet();
  }

  /// Duration of this track (time of last keyframe).
  Duration get duration {
    if (keyframes.isEmpty) return Duration.zero;
    return keyframes.last.time;
  }

  // -------------------------------------------------------------------------
  // Serialization
  // -------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
    'nodeId': nodeId,
    'keyframes': keyframes.map((k) => k.toJson()).toList(),
  };

  factory AnimationTrack.fromJson(Map<String, dynamic> json) {
    return AnimationTrack(
      nodeId: json['nodeId'] as String,
      keyframes:
          (json['keyframes'] as List<dynamic>)
              .map((k) => Keyframe.fromJson(k as Map<String, dynamic>))
              .toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// Animation Timeline
// ---------------------------------------------------------------------------

/// Top-level container for all animation tracks in a canvas.
///
/// The timeline defines the total duration and frame rate, and
/// contains one [AnimationTrack] per animated node.
///
/// Usage:
/// ```dart
/// final timeline = AnimationTimeline(
///   totalDuration: Duration(seconds: 5),
///   fps: 30,
/// );
/// timeline.addTrack(AnimationTrack(nodeId: 'star1'));
/// timeline.tracks['star1']!.addKeyframe(
///   Keyframe(time: Duration.zero, property: 'opacity', value: 0.0),
/// );
/// timeline.tracks['star1']!.addKeyframe(
///   Keyframe(time: Duration(seconds: 2), property: 'opacity', value: 1.0),
/// );
/// ```
class AnimationTimeline {
  /// Total duration of the animation.
  Duration totalDuration;

  /// Frames per second for playback/export.
  int fps;

  /// Animation tracks indexed by node ID.
  final Map<String, AnimationTrack> tracks;

  /// Whether the animation loops.
  bool loop;

  AnimationTimeline({
    this.totalDuration = const Duration(seconds: 5),
    this.fps = 30,
    Map<String, AnimationTrack>? tracks,
    this.loop = false,
  }) : tracks = tracks ?? {};

  /// Add a track for a node.
  void addTrack(AnimationTrack track) {
    tracks[track.nodeId] = track;
  }

  /// Remove a track by node ID.
  void removeTrack(String nodeId) {
    tracks.remove(nodeId);
  }

  /// Total frame count.
  int get totalFrames => (totalDuration.inMilliseconds * fps / 1000).ceil();

  /// Duration per frame.
  Duration get frameDuration => Duration(milliseconds: (1000 / fps).round());

  /// Evaluate the value of a property at a given time.
  ///
  /// Returns null if no keyframes exist for the property.
  dynamic evaluate(String nodeId, String property, Duration time) {
    final track = tracks[nodeId];
    if (track == null) return null;

    final kfs = track.forProperty(property);
    if (kfs.isEmpty) return null;

    return PropertyInterpolator.interpolate(kfs, time);
  }

  // -------------------------------------------------------------------------
  // Serialization
  // -------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
    'totalDurationMs': totalDuration.inMilliseconds,
    'fps': fps,
    'loop': loop,
    'tracks': tracks.values.map((t) => t.toJson()).toList(),
  };

  factory AnimationTimeline.fromJson(Map<String, dynamic> json) {
    final trackList =
        (json['tracks'] as List<dynamic>?)
            ?.map((t) => AnimationTrack.fromJson(t as Map<String, dynamic>))
            .toList() ??
        [];

    final trackMap = <String, AnimationTrack>{};
    for (final t in trackList) {
      trackMap[t.nodeId] = t;
    }

    return AnimationTimeline(
      totalDuration: Duration(
        milliseconds: json['totalDurationMs'] as int? ?? 5000,
      ),
      fps: json['fps'] as int? ?? 30,
      loop: json['loop'] as bool? ?? false,
      tracks: trackMap,
    );
  }
}

// ---------------------------------------------------------------------------
// Property Interpolator
// ---------------------------------------------------------------------------

/// Interpolates between keyframes based on time and easing.
class PropertyInterpolator {
  PropertyInterpolator._();

  /// Interpolate a value at [time] from sorted [keyframes].
  static dynamic interpolate(List<Keyframe> keyframes, Duration time) {
    if (keyframes.isEmpty) return null;

    final timeMs = time.inMilliseconds;

    // Before first keyframe → return first value.
    if (timeMs <= keyframes.first.timeMs) return keyframes.first.value;

    // After last keyframe → return last value.
    if (timeMs >= keyframes.last.timeMs) return keyframes.last.value;

    // Find the surrounding keyframes.
    for (int i = 0; i < keyframes.length - 1; i++) {
      final a = keyframes[i];
      final b = keyframes[i + 1];

      if (timeMs >= a.timeMs && timeMs <= b.timeMs) {
        final range = b.timeMs - a.timeMs;
        if (range == 0) return a.value;

        final linearT = (timeMs - a.timeMs) / range;
        final easedT = _applyEasing(linearT, a.easing);

        return _lerpValue(a.value, b.value, easedT);
      }
    }

    return keyframes.last.value;
  }

  /// Apply easing curve to a linear t value.
  static double _applyEasing(double t, EasingType easing) {
    switch (easing) {
      case EasingType.linear:
        return t;
      case EasingType.easeIn:
        return t * t;
      case EasingType.easeOut:
        return 1 - (1 - t) * (1 - t);
      case EasingType.easeInOut:
        return t < 0.5 ? 2 * t * t : 1 - (-2 * t + 2) * (-2 * t + 2) / 2;
      case EasingType.spring:
        // Damped spring approximation.
        return 1 -
            (1 - t) *
                (1 - t) *
                (2.75 * (1 - t) * (1 - t) * (1 - t) - 1.75 * (1 - t) + 1);
    }
  }

  /// Lerp between two values of the same type.
  static dynamic _lerpValue(dynamic a, dynamic b, double t) {
    if (a is double && b is double) {
      return a + (b - a) * t;
    }
    if (a is int && b is int) {
      return (a + (b - a) * t).round();
    }
    if (a is ui.Color && b is ui.Color) {
      return ui.Color.lerp(a, b, t) ?? a;
    }
    if (a is Offset && b is Offset) {
      return Offset.lerp(a, b, t) ?? a;
    }
    // For non-interpolable types, snap at t=0.5.
    return t < 0.5 ? a : b;
  }
}
