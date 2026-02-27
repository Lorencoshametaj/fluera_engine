import 'dart:convert';
import '../../drawing/models/pro_drawing_point.dart';

/// Synchronized stroke with timestamps relative to the recording.
/// Contains the start and end timestamps of the stroke relative to the recording start.
class SyncedStroke {
  /// The complete original stroke
  final ProStroke stroke;

  /// Start timestamp relative to the recording (milliseconds)
  /// When the user started drawing this stroke
  final int relativeStartMs;

  /// End timestamp relative to the recording (milliseconds)
  /// When the user completed this stroke
  final int relativeEndMs;

  /// 📄 Index of the page on which the stroke was drawn
  final int pageIndex;

  const SyncedStroke({
    required this.stroke,
    required this.relativeStartMs,
    required this.relativeEndMs,
    this.pageIndex = 0,
  });

  /// Duration of the stroke in milliseconds
  int get durationMs => relativeEndMs - relativeStartMs;

  /// Calculates how many points of the stroke are visible at a given playback time.
  /// [playbackTimeMs] - current playback time in ms
  /// Returns: number of points to show (0 if the stroke has not started yet)
  int visiblePointsAtTime(int playbackTimeMs) {
    // If playback has not yet reached the start of the stroke
    if (playbackTimeMs < relativeStartMs) return 0;

    // If playback has passed the end of the stroke, show everything
    if (playbackTimeMs >= relativeEndMs) return stroke.points.length;

    // Calculate progress percentage through the stroke
    final elapsed = playbackTimeMs - relativeStartMs;
    final progress = elapsed / durationMs;

    // Calculate how many points to show
    return (stroke.points.length * progress).ceil().clamp(
      0,
      stroke.points.length,
    );
  }

  /// Creates a partial version of the stroke with only visible points.
  /// [playbackTimeMs] - current playback time in ms
  ProStroke? getPartialStroke(int playbackTimeMs) {
    final visibleCount = visiblePointsAtTime(playbackTimeMs);
    if (visibleCount == 0) return null;
    if (visibleCount >= stroke.points.length) return stroke;

    return stroke.copyWith(points: stroke.points.sublist(0, visibleCount));
  }

  /// Checks if the stroke is completely visible
  bool isFullyVisible(int playbackTimeMs) => playbackTimeMs >= relativeEndMs;

  /// Checks if the stroke has started
  bool isStarted(int playbackTimeMs) => playbackTimeMs >= relativeStartMs;

  Map<String, dynamic> toJson() => {
    'stroke': stroke.toJson(),
    'relativeStartMs': relativeStartMs,
    'relativeEndMs': relativeEndMs,
    'pageIndex': pageIndex,
  };

  factory SyncedStroke.fromJson(Map<String, dynamic> json) => SyncedStroke(
    stroke: ProStroke.fromJson(json['stroke'] as Map<String, dynamic>),
    relativeStartMs: json['relativeStartMs'] as int,
    relativeEndMs: json['relativeEndMs'] as int,
    pageIndex: json['pageIndex'] as int? ?? 0,
  );
}

/// Synchronized recording that links audio and strokes with precise timing.
/// Allows playback of audio together with strokes that "draw" in real-time.
class SynchronizedRecording {
  /// Unique ID of the recording
  final String id;

  /// Path to the audio file
  final String audioPath;

  /// Total duration of the recording
  final Duration totalDuration;

  /// Start timestamp of the recording
  final DateTime startTime;

  /// List of synchronized strokes with relative timestamps
  final List<SyncedStroke> syncedStrokes;

  /// ID of the source canvas
  final String? canvasId;

  /// Source note title
  final String? noteTitle;

  /// 🏷️ Recording type ('note', 'mixed')
  final String? recordingType;

  /// 📂 Local path to the JSON file (optional, for reference)
  final String? strokesPath;

  /// ☁️ Cloud Storage URL for the audio file (remote sync)
  final String? audioStorageUrl;

  /// ☁️ Cloud Storage URL for the JSON strokes file (remote sync)
  final String? strokesStorageUrl;

  const SynchronizedRecording({
    required this.id,
    required this.audioPath,
    required this.totalDuration,
    required this.startTime,
    required this.syncedStrokes,
    this.canvasId,
    this.noteTitle,
    this.recordingType,
    this.strokesPath,
    this.audioStorageUrl,
    this.strokesStorageUrl,
  });

  /// Creates an empty recording
  factory SynchronizedRecording.empty({
    required String id,
    required String audioPath,
    required DateTime startTime,
    String? canvasId,
    String? noteTitle,
    String? recordingType,
  }) {
    return SynchronizedRecording(
      id: id,
      audioPath: audioPath,
      totalDuration: Duration.zero,
      startTime: startTime,
      syncedStrokes: [],
      canvasId: canvasId,
      noteTitle: noteTitle,
      recordingType: recordingType,
      strokesPath: null,
    );
  }

  /// Creates a copy with modifications
  SynchronizedRecording copyWith({
    String? id,
    String? audioPath,
    Duration? totalDuration,
    DateTime? startTime,
    List<SyncedStroke>? syncedStrokes,
    String? canvasId,
    String? noteTitle,
    String? recordingType,
    String? strokesPath,
    String? audioStorageUrl,
    String? strokesStorageUrl,
  }) {
    return SynchronizedRecording(
      id: id ?? this.id,
      audioPath: audioPath ?? this.audioPath,
      totalDuration: totalDuration ?? this.totalDuration,
      startTime: startTime ?? this.startTime,
      syncedStrokes: syncedStrokes ?? this.syncedStrokes,
      canvasId: canvasId ?? this.canvasId,
      noteTitle: noteTitle ?? this.noteTitle,
      recordingType: recordingType ?? this.recordingType,
      strokesPath: strokesPath ?? this.strokesPath,
      audioStorageUrl: audioStorageUrl ?? this.audioStorageUrl,
      strokesStorageUrl: strokesStorageUrl ?? this.strokesStorageUrl,
    );
  }

  /// Total number of strokes in the recording
  int get strokeCount => syncedStrokes.length;

  /// Checks if the recording has strokes
  bool get hasStrokes => syncedStrokes.isNotEmpty;

  /// Gets all partial strokes visible at a given time.
  /// [playbackTimeMs] - current playback time in ms
  /// Returns: list of strokes (partial or complete) to render
  List<ProStroke> getVisibleStrokesAtTime(int playbackTimeMs) {
    final result = <ProStroke>[];

    for (final synced in syncedStrokes) {
      final partial = synced.getPartialStroke(playbackTimeMs);
      if (partial != null) {
        result.add(partial);
      }
    }

    return result;
  }

  /// Gets all "ghost" strokes (not yet started) with reduced opacity.
  /// [playbackTimeMs] - current playback time in ms
  /// [ghostOpacity] - opacity for ghost strokes (default 0.1)
  List<ProStroke> getGhostStrokesAtTime(
    int playbackTimeMs, {
    double ghostOpacity = 0.1,
  }) {
    final result = <ProStroke>[];

    for (final synced in syncedStrokes) {
      if (!synced.isStarted(playbackTimeMs)) {
        // Create ghost version with semi-transparent color
        result.add(
          synced.stroke.copyWith(
            color: synced.stroke.color.withValues(alpha: ghostOpacity),
          ),
        );
      }
    }

    return result;
  }

  /// JSON serialization
  Map<String, dynamic> toJson() => {
    'id': id,
    'audioPath': audioPath,
    'totalDurationMs': totalDuration.inMilliseconds,
    'startTime': startTime.toIso8601String(),
    'syncedStrokes': syncedStrokes.map((s) => s.toJson()).toList(),
    if (canvasId != null) 'canvasId': canvasId,
    if (noteTitle != null) 'noteTitle': noteTitle,
    if (recordingType != null) 'recordingType': recordingType,
    if (audioStorageUrl != null) 'audioStorageUrl': audioStorageUrl,
    if (strokesStorageUrl != null) 'strokesStorageUrl': strokesStorageUrl,
  };

  /// JSON serialization as compressed string
  String toJsonString() => jsonEncode(toJson());

  /// JSON deserialization
  factory SynchronizedRecording.fromJson(Map<String, dynamic> json) {
    return SynchronizedRecording(
      id: json['id'] as String,
      audioPath: json['audioPath'] as String,
      totalDuration: Duration(milliseconds: json['totalDurationMs'] as int),
      startTime: DateTime.parse(json['startTime'] as String),
      syncedStrokes:
          (json['syncedStrokes'] as List<dynamic>)
              .map((s) => SyncedStroke.fromJson(s as Map<String, dynamic>))
              .toList(),
      canvasId: json['canvasId'] as String?,
      noteTitle: json['noteTitle'] as String?,
      recordingType: json['recordingType'] as String?,
      audioStorageUrl: json['audioStorageUrl'] as String?,
      strokesStorageUrl: json['strokesStorageUrl'] as String?,
    );
  }

  /// Deserialization from JSON string
  factory SynchronizedRecording.fromJsonString(String jsonString) {
    return SynchronizedRecording.fromJson(
      jsonDecode(jsonString) as Map<String, dynamic>,
    );
  }

  @override
  String toString() =>
      'SynchronizedRecording(id: $id, strokes: ${syncedStrokes.length}, duration: $totalDuration)';
}

/// Builder to construct a SynchronizedRecording during recording
class SynchronizedRecordingBuilder {
  final String id;
  final String audioPath;
  final DateTime startTime;
  final String? canvasId;
  final String? noteTitle;

  // Mutable recording type inferred during recording
  String? _recordingType;

  final List<SyncedStroke> _strokes = [];
  int _recordingStartEpoch = 0;

  SynchronizedRecordingBuilder({
    required this.id,
    required this.audioPath,
    required this.startTime,
    this.canvasId,
    this.noteTitle,
  }) {
    _recordingStartEpoch = startTime.millisecondsSinceEpoch;
  }

  /// Adds a stroke to the recording.
  /// [stroke] - the completed stroke
  /// [strokeStartTime] - start timestamp of the stroke (DateTime.now() when the user started)
  /// [strokeEndTime] - end timestamp of the stroke (DateTime.now() when the user finished)
  /// [pageIndex] - index of the page on which it was drawn
  void addStroke(
    ProStroke stroke,
    DateTime strokeStartTime,
    DateTime strokeEndTime, {
    int pageIndex = 0,
  }) {
    final relativeStart =
        strokeStartTime.millisecondsSinceEpoch - _recordingStartEpoch;
    final relativeEnd =
        strokeEndTime.millisecondsSinceEpoch - _recordingStartEpoch;

    _strokes.add(
      SyncedStroke(
        stroke: stroke,
        relativeStartMs: relativeStart.clamp(0, double.maxFinite.toInt()),
        relativeEndMs: relativeEnd.clamp(0, double.maxFinite.toInt()),
        pageIndex: pageIndex,
      ),
    );
  }

  /// Adds a stroke using timestamps of points.
  /// Automatically calculates start/end from the stroke's point timestamps.
  void addStrokeWithPointTimestamps(ProStroke stroke) {
    if (stroke.points.isEmpty) return;

    // Use the timestamp of the first and last point
    final firstPointTimestamp = stroke.points.first.timestamp;
    final lastPointTimestamp = stroke.points.last.timestamp;

    // If adding strokes with points, assume 'note' type if not already set
    _recordingType ??= 'note';

    final relativeStart = firstPointTimestamp - _recordingStartEpoch;
    final relativeEnd = lastPointTimestamp - _recordingStartEpoch;

    _strokes.add(
      SyncedStroke(
        stroke: stroke,
        relativeStartMs: relativeStart.clamp(0, double.maxFinite.toInt()),
        relativeEndMs: relativeEnd.clamp(0, double.maxFinite.toInt()),
      ),
    );
  }

  /// Number of strokes added so far
  int get strokeCount => _strokes.length;

  /// Checks if there are strokes
  bool get hasStrokes => _strokes.isNotEmpty;

  /// Access the strokes list (read-only, for pen interval extraction).
  List<SyncedStroke> get strokes => _strokes;

  /// Builds the final recording.
  /// [duration] - total duration of the audio recording
  SynchronizedRecording build(Duration duration) {
    return SynchronizedRecording(
      id: id,
      audioPath: audioPath,
      totalDuration: duration,
      startTime: startTime,
      syncedStrokes: List.unmodifiable(_strokes),
      canvasId: canvasId,
      noteTitle: noteTitle,
      recordingType: _recordingType,
    );
  }

  /// Explicitly sets the recording type
  void setRecordingType(String type) {
    // 🧠 Be more tolerant: if type is already set but we DO NOT have strokes yet,
    // allow changing one's mind
    if (_strokes.isEmpty) {
      _recordingType = type;
      return;
    }

    // If already set and different, it becomes 'mixed'
    if (_recordingType != null && _recordingType != type) {
      _recordingType = 'mixed';
    } else {
      _recordingType = type;
    }
  }

  /// Remove a stroke from the builder by its ID.
  ///
  /// Called when the user performs undo during an active recording session,
  /// so the undone stroke doesn't appear as a ghost during playback.
  /// Returns true if a stroke was found and removed.
  bool removeStrokeById(String strokeId) {
    final index = _strokes.indexWhere((s) => s.stroke.id == strokeId);
    if (index < 0) return false;
    _strokes.removeAt(index);
    return true;
  }

  /// Resets the builder for a new recording
  void reset() {
    _strokes.clear();
    _recordingStartEpoch = DateTime.now().millisecondsSinceEpoch;
  }
}
