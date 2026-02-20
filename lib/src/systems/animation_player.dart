import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'animation_timeline.dart';
import '../core/scene_graph/scene_graph.dart';
import '../core/scene_graph/canvas_node.dart';

// ---------------------------------------------------------------------------
// Playback state
// ---------------------------------------------------------------------------

/// The playback state of an [AnimationPlayer].
enum AnimationPlaybackState {
  /// Player is stopped at `Duration.zero`.
  stopped,

  /// Player is actively advancing time and applying values.
  playing,

  /// Player is paused at the current time.
  paused,
}

// ---------------------------------------------------------------------------
// AnimationPlayer
// ---------------------------------------------------------------------------

/// Ticker-driven playback controller for [AnimationTimeline].
///
/// This is the **missing piece** in the animation subsystem:
/// `AnimationTimeline`, `AnimationTrack`, `Keyframe`, and
/// `PropertyInterpolator` all exist — but nothing drives playback.
/// `AnimationPlayer` fills that gap.
///
/// ## Usage
///
/// ```dart
/// final player = AnimationPlayer(
///   timeline: sceneGraph.timeline,
///   sceneGraph: sceneGraph,
/// );
/// player.attachTicker(vsync); // from TickerProviderStateMixin
///
/// player.play();    // start playback
/// player.pause();   // pause
/// player.seek(Duration(seconds: 1));   // jump to time
/// player.speed = 2.0; // 2× speed
/// player.loop = true; // loop continuously
///
/// // Later:
/// player.detachTicker();
/// player.dispose();
/// ```
class AnimationPlayer {
  /// The timeline containing tracks and keyframes.
  final AnimationTimeline timeline;

  /// The scene graph whose nodes receive animated values.
  final SceneGraph sceneGraph;

  /// Current playback state.
  final ValueNotifier<AnimationPlaybackState> state = ValueNotifier(
    AnimationPlaybackState.stopped,
  );

  /// Current playback time.
  final ValueNotifier<Duration> currentTime = ValueNotifier(Duration.zero);

  /// Playback speed multiplier (0.25× – 4×).
  double _speed = 1.0;
  double get speed => _speed;
  set speed(double v) {
    _speed = v.clamp(0.25, 4.0);
  }

  /// Whether playback loops back to start when reaching the end.
  bool loop = false;

  /// Callback fired on each frame tick with the current time.
  void Function(Duration time)? onFrame;

  /// Callback fired when playback completes (reaches end without loop).
  VoidCallback? onComplete;

  // -- Internal state -------------------------------------------------------

  Ticker? _ticker;
  Duration _tickerStartTime = Duration.zero;
  Duration _playbackOffset = Duration.zero;

  AnimationPlayer({required this.timeline, required this.sceneGraph});

  // -------------------------------------------------------------------------
  // Ticker lifecycle
  // -------------------------------------------------------------------------

  /// Attach a ticker from the widget tree.
  void attachTicker(TickerProvider vsync) {
    _ticker?.dispose();
    _ticker = vsync.createTicker(_onTick);
  }

  /// Detach and dispose the ticker.
  void detachTicker() {
    _ticker?.stop();
    _ticker?.dispose();
    _ticker = null;
  }

  // -------------------------------------------------------------------------
  // Playback controls
  // -------------------------------------------------------------------------

  /// Start or resume playback.
  void play() {
    if (state.value == AnimationPlaybackState.playing) return;
    if (_ticker == null) {
      throw StateError('AnimationPlayer: call attachTicker() first.');
    }

    state.value = AnimationPlaybackState.playing;

    // If stopped, start from beginning.
    if (currentTime.value >= timeline.totalDuration &&
        currentTime.value != Duration.zero) {
      _playbackOffset = Duration.zero;
      currentTime.value = Duration.zero;
    } else {
      _playbackOffset = currentTime.value;
    }

    _tickerStartTime = Duration.zero;
    _ticker!.start();
  }

  /// Pause playback at the current time.
  void pause() {
    if (state.value != AnimationPlaybackState.playing) return;
    _ticker?.stop();
    state.value = AnimationPlaybackState.paused;
  }

  /// Stop playback and reset to start.
  void stop() {
    _ticker?.stop();
    currentTime.value = Duration.zero;
    _playbackOffset = Duration.zero;
    state.value = AnimationPlaybackState.stopped;
    // Apply frame at t=0 to reset all animated properties.
    _applyFrame(Duration.zero);
  }

  /// Seek to a specific time without changing play/pause state.
  void seek(Duration time) {
    final clamped = Duration(
      microseconds: time.inMicroseconds.clamp(
        0,
        timeline.totalDuration.inMicroseconds,
      ),
    );
    currentTime.value = clamped;
    _playbackOffset = clamped;

    if (state.value == AnimationPlaybackState.playing) {
      // Reset ticker base so playback continues from the new time.
      _ticker?.stop();
      _tickerStartTime = Duration.zero;
      _ticker?.start();
    }

    _applyFrame(clamped);
  }

  /// Jump to a normalized position (0.0 = start, 1.0 = end).
  void seekNormalized(double t) {
    final clamped = t.clamp(0.0, 1.0);
    final micros = (clamped * timeline.totalDuration.inMicroseconds).round();
    seek(Duration(microseconds: micros));
  }

  /// Current normalized position (0.0 – 1.0).
  double get normalizedPosition {
    if (timeline.totalDuration.inMicroseconds == 0) return 0;
    return currentTime.value.inMicroseconds /
        timeline.totalDuration.inMicroseconds;
  }

  /// Whether the player is currently playing.
  bool get isPlaying => state.value == AnimationPlaybackState.playing;

  /// Whether the player is currently paused.
  bool get isPaused => state.value == AnimationPlaybackState.paused;

  /// Whether the player is currently stopped.
  bool get isStopped => state.value == AnimationPlaybackState.stopped;

  // -------------------------------------------------------------------------
  // Frame stepping
  // -------------------------------------------------------------------------

  void _onTick(Duration elapsed) {
    if (state.value != AnimationPlaybackState.playing) return;

    // Scale elapsed by speed.
    final scaledElapsed = Duration(
      microseconds: (elapsed.inMicroseconds * _speed).round(),
    );

    final newTime = _playbackOffset + scaledElapsed;

    if (newTime >= timeline.totalDuration) {
      if (loop) {
        // Wrap around.
        final wrapped = Duration(
          microseconds:
              newTime.inMicroseconds % timeline.totalDuration.inMicroseconds,
        );
        currentTime.value = wrapped;
        _playbackOffset = wrapped;
        _tickerStartTime = elapsed;
        _applyFrame(wrapped);
      } else {
        // Clamp to end and stop.
        currentTime.value = timeline.totalDuration;
        _applyFrame(timeline.totalDuration);
        _ticker?.stop();
        state.value = AnimationPlaybackState.stopped;
        onComplete?.call();
      }
    } else {
      currentTime.value = newTime;
      _applyFrame(newTime);
    }

    onFrame?.call(currentTime.value);
  }

  /// Evaluate all tracks at [time] and apply values to scene graph nodes.
  void _applyFrame(Duration time) {
    for (final entry in timeline.tracks.entries) {
      final nodeId = entry.key;
      final track = entry.value;
      final node = sceneGraph.findNodeById(nodeId);
      if (node == null) continue;

      // Collect animated properties for this track.
      final properties = <String>{};
      for (final kf in track.keyframes) {
        properties.add(kf.property);
      }

      for (final property in properties) {
        final value = timeline.evaluate(nodeId, property, time);
        if (value != null) {
          _applyPropertyValue(node, property, value);
        }
      }
    }
  }

  /// Apply an interpolated value to a node property.
  void _applyPropertyValue(CanvasNode node, String property, dynamic value) {
    switch (property) {
      case 'opacity':
        if (value is double) node.opacity = value;
        break;

      case 'position.x':
        if (value is double) {
          final pos = node.position;
          node.setPosition(value, pos.dy);
          node.invalidateTransformCache();
        }
        break;

      case 'position.y':
        if (value is double) {
          final pos = node.position;
          node.setPosition(pos.dx, value);
          node.invalidateTransformCache();
        }
        break;

      case 'scale':
        if (value is double) {
          final center = node.worldBounds.center;
          // Reset scale by re-building transform (simplified).
          node.scaleFrom(value, value, center);
          node.invalidateTransformCache();
        }
        break;

      case 'rotation':
        if (value is double) {
          final center = node.worldBounds.center;
          node.rotateAround(value, center);
          node.invalidateTransformCache();
        }
        break;

      case 'isVisible':
        if (value is bool) node.isVisible = value;
        break;

      default:
        // Unknown property — silently skip.
        break;
    }
  }

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  /// Dispose all resources.
  void dispose() {
    stop();
    _ticker?.dispose();
    _ticker = null;
    state.dispose();
    currentTime.dispose();
  }

  @override
  String toString() =>
      'AnimationPlayer(state: ${state.value}, time: ${currentTime.value}, '
      'speed: $_speed, loop: $loop)';
}
