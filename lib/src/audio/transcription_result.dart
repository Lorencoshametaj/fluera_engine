import 'dart:convert';

// =============================================================================
// 📝 TRANSCRIPTION RESULT
//
// Data model for speech-to-text transcription output from Sherpa-ONNX.
// Stores full text, time-stamped segments, language info, and metadata.
// =============================================================================

/// Result of transcribing an audio recording to text.
///
/// Contains the full transcribed text plus time-stamped segments that can
/// be aligned with audio playback and synchronized strokes.
class TranscriptionResult {
  /// Full transcribed text (all segments concatenated).
  final String text;

  /// Time-stamped segments with individual confidence scores.
  final List<TranscriptionSegment> segments;

  /// Detected or specified language code (e.g., 'en', 'it', 'de').
  final String language;

  /// Duration of the source audio.
  final Duration audioDuration;

  /// When the transcription was performed.
  final DateTime transcribedAt;

  /// Model used for transcription (e.g., 'whisper-base').
  final String? modelId;

  const TranscriptionResult({
    required this.text,
    required this.segments,
    required this.language,
    required this.audioDuration,
    required this.transcribedAt,
    this.modelId,
  });

  /// Whether the transcription produced any text.
  bool get isEmpty => text.trim().isEmpty;
  bool get isNotEmpty => !isEmpty;

  /// Total number of segments.
  int get segmentCount => segments.length;

  /// Average confidence across all segments (0.0–1.0).
  double get averageConfidence {
    if (segments.isEmpty) return 0.0;
    final total = segments.fold<double>(0.0, (sum, s) => sum + s.confidence);
    return total / segments.length;
  }

  /// Get the segment active at a given playback time.
  TranscriptionSegment? segmentAtTime(Duration playbackTime) {
    final ms = playbackTime.inMilliseconds;
    for (final segment in segments) {
      if (ms >= segment.start.inMilliseconds &&
          ms <= segment.end.inMilliseconds) {
        return segment;
      }
    }
    return null;
  }

  /// Get all text visible up to a given playback time.
  String textUpToTime(Duration playbackTime) {
    final ms = playbackTime.inMilliseconds;
    final buffer = StringBuffer();
    for (final segment in segments) {
      if (segment.start.inMilliseconds <= ms) {
        if (buffer.isNotEmpty) buffer.write(' ');
        buffer.write(segment.text);
      }
    }
    return buffer.toString();
  }

  // ===========================================================================
  // Serialization
  // ===========================================================================

  Map<String, dynamic> toJson() => {
    'text': text,
    'segments': segments.map((s) => s.toJson()).toList(),
    'language': language,
    'audioDurationMs': audioDuration.inMilliseconds,
    'transcribedAt': transcribedAt.toIso8601String(),
    if (modelId != null) 'modelId': modelId,
  };

  String toJsonString() => jsonEncode(toJson());

  factory TranscriptionResult.fromJson(Map<String, dynamic> json) {
    return TranscriptionResult(
      text: json['text'] as String? ?? '',
      segments: (json['segments'] as List<dynamic>?)
              ?.map(
                (s) =>
                    TranscriptionSegment.fromJson(s as Map<String, dynamic>),
              )
              .toList() ??
          [],
      language: json['language'] as String? ?? 'auto',
      audioDuration: Duration(
        milliseconds: json['audioDurationMs'] as int? ?? 0,
      ),
      transcribedAt:
          json['transcribedAt'] != null
              ? DateTime.parse(json['transcribedAt'] as String)
              : DateTime.now(),
      modelId: json['modelId'] as String?,
    );
  }

  factory TranscriptionResult.fromJsonString(String jsonString) {
    return TranscriptionResult.fromJson(
      jsonDecode(jsonString) as Map<String, dynamic>,
    );
  }

  /// Create an empty result (no transcription available).
  factory TranscriptionResult.empty() => TranscriptionResult(
    text: '',
    segments: [],
    language: 'auto',
    audioDuration: Duration.zero,
    transcribedAt: DateTime.now(),
  );

  TranscriptionResult copyWith({
    String? text,
    List<TranscriptionSegment>? segments,
    String? language,
    Duration? audioDuration,
    DateTime? transcribedAt,
    String? modelId,
  }) {
    return TranscriptionResult(
      text: text ?? this.text,
      segments: segments ?? this.segments,
      language: language ?? this.language,
      audioDuration: audioDuration ?? this.audioDuration,
      transcribedAt: transcribedAt ?? this.transcribedAt,
      modelId: modelId ?? this.modelId,
    );
  }

  @override
  String toString() =>
      'TranscriptionResult(lang: $language, segments: $segmentCount, '
      'text: "${text.length > 50 ? '${text.substring(0, 50)}...' : text}")';
}

/// A time-stamped segment of transcribed text.
///
/// Each segment corresponds to a chunk of speech detected by VAD
/// and transcribed by the ASR model.
class TranscriptionSegment {
  /// Transcribed text for this segment.
  final String text;

  /// Start time relative to the beginning of the audio.
  final Duration start;

  /// End time relative to the beginning of the audio.
  final Duration end;

  /// Confidence score from the model (0.0–1.0).
  final double confidence;

  const TranscriptionSegment({
    required this.text,
    required this.start,
    required this.end,
    this.confidence = 1.0,
  });

  /// Duration of this segment.
  Duration get duration => end - start;

  /// Whether a given playback time falls within this segment.
  bool containsTime(Duration time) {
    return time >= start && time <= end;
  }

  Map<String, dynamic> toJson() => {
    'text': text,
    'startMs': start.inMilliseconds,
    'endMs': end.inMilliseconds,
    'confidence': double.parse(confidence.toStringAsFixed(3)),
  };

  factory TranscriptionSegment.fromJson(Map<String, dynamic> json) {
    return TranscriptionSegment(
      text: json['text'] as String? ?? '',
      start: Duration(milliseconds: json['startMs'] as int? ?? 0),
      end: Duration(milliseconds: json['endMs'] as int? ?? 0),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
    );
  }

  @override
  String toString() =>
      'Segment(${start.inSeconds}s–${end.inSeconds}s: "$text")';
}
