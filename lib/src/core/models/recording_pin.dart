import 'dart:ui';

/// 📌 A recording pinned to a specific position on the canvas.
///
/// Tapping the pin starts playback of the associated recording.
/// This is a lightweight model — the actual audio/stroke data lives
/// in [SynchronizedRecording] (referenced by [recordingId]).
class RecordingPin {
  final String id;
  final String recordingId;
  final Offset position;
  final String label;
  final Duration? duration;
  final bool hasStrokes;
  final DateTime createdAt;

  const RecordingPin({
    required this.id,
    required this.recordingId,
    required this.position,
    required this.label,
    this.duration,
    this.hasStrokes = false,
    required this.createdAt,
  });

  RecordingPin copyWith({
    String? id,
    String? recordingId,
    Offset? position,
    String? label,
    Duration? duration,
    bool? hasStrokes,
    DateTime? createdAt,
  }) {
    return RecordingPin(
      id: id ?? this.id,
      recordingId: recordingId ?? this.recordingId,
      position: position ?? this.position,
      label: label ?? this.label,
      duration: duration ?? this.duration,
      hasStrokes: hasStrokes ?? this.hasStrokes,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'recordingId': recordingId,
    'position': {'dx': position.dx, 'dy': position.dy},
    'label': label,
    if (duration != null) 'durationMs': duration!.inMilliseconds,
    'hasStrokes': hasStrokes,
    'createdAt': createdAt.toIso8601String(),
  };

  factory RecordingPin.fromJson(Map<String, dynamic> json) {
    return RecordingPin(
      id: json['id'] as String,
      recordingId: json['recordingId'] as String,
      position: Offset(
        (json['position']['dx'] as num).toDouble(),
        (json['position']['dy'] as num).toDouble(),
      ),
      label: json['label'] as String,
      duration:
          json['durationMs'] != null
              ? Duration(milliseconds: (json['durationMs'] as num).toInt())
              : null,
      hasStrokes: json['hasStrokes'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  @override
  String toString() =>
      'RecordingPin(id: $id, recording: $recordingId, pos: $position)';
}
