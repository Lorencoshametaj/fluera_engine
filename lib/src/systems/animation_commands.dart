import 'animation_timeline.dart';
import '../history/command_history.dart';

// ---------------------------------------------------------------------------
// AddKeyframeCommand
// ---------------------------------------------------------------------------

/// Adds a [Keyframe] to an [AnimationTrack]. Undoable.
class AddKeyframeCommand extends Command {
  final AnimationTimeline timeline;
  final String nodeId;
  final Keyframe keyframe;

  AddKeyframeCommand({
    required this.timeline,
    required this.nodeId,
    required this.keyframe,
  }) : super(label: 'Add keyframe (${keyframe.property} @ ${keyframe.time})');

  @override
  void execute() {
    final track = timeline.tracks.putIfAbsent(
      nodeId,
      () => AnimationTrack(nodeId: nodeId),
    );
    track.addKeyframe(keyframe);
  }

  @override
  void undo() {
    timeline.tracks[nodeId]?.removeKeyframe(keyframe.time, keyframe.property);
    // Remove empty tracks.
    if (timeline.tracks[nodeId]?.keyframes.isEmpty ?? false) {
      timeline.tracks.remove(nodeId);
    }
  }
}

// ---------------------------------------------------------------------------
// RemoveKeyframeCommand
// ---------------------------------------------------------------------------

/// Removes a [Keyframe] from an [AnimationTrack]. Undoable.
class RemoveKeyframeCommand extends Command {
  final AnimationTimeline timeline;
  final String nodeId;
  final Duration time;
  final String property;
  Keyframe? _removedKeyframe;

  RemoveKeyframeCommand({
    required this.timeline,
    required this.nodeId,
    required this.time,
    required this.property,
  }) : super(label: 'Remove keyframe ($property @ $time)');

  @override
  void execute() {
    final track = timeline.tracks[nodeId];
    if (track == null) return;
    // Find and save the keyframe being removed.
    _removedKeyframe = track.keyframes.cast<Keyframe?>().firstWhere(
      (kf) => kf!.time == time && kf.property == property,
      orElse: () => null,
    );
    track.removeKeyframe(time, property);
  }

  @override
  void undo() {
    if (_removedKeyframe == null) return;
    final track = timeline.tracks.putIfAbsent(
      nodeId,
      () => AnimationTrack(nodeId: nodeId),
    );
    track.addKeyframe(_removedKeyframe!);
  }
}

// ---------------------------------------------------------------------------
// AddTrackCommand
// ---------------------------------------------------------------------------

/// Adds an [AnimationTrack] for a node. Undoable.
class AddTrackCommand extends Command {
  final AnimationTimeline timeline;
  final AnimationTrack track;

  AddTrackCommand({required this.timeline, required this.track})
    : super(label: 'Add animation track (${track.nodeId})');

  @override
  void execute() {
    timeline.addTrack(track);
  }

  @override
  void undo() {
    timeline.removeTrack(track.nodeId);
  }
}

// ---------------------------------------------------------------------------
// RemoveTrackCommand
// ---------------------------------------------------------------------------

/// Removes an [AnimationTrack] by node ID. Undoable.
class RemoveTrackCommand extends Command {
  final AnimationTimeline timeline;
  final String nodeId;
  AnimationTrack? _removedTrack;

  RemoveTrackCommand({required this.timeline, required this.nodeId})
    : super(label: 'Remove animation track ($nodeId)');

  @override
  void execute() {
    _removedTrack = timeline.tracks[nodeId];
    timeline.removeTrack(nodeId);
  }

  @override
  void undo() {
    if (_removedTrack != null) {
      timeline.addTrack(_removedTrack!);
    }
  }
}
