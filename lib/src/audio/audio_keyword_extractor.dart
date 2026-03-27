import '../reflow/content_cluster.dart';
import '../time_travel/models/synchronized_recording.dart';
import './transcription_result.dart';

// =============================================================================
// 🔑 AUDIO KEYWORD EXTRACTOR
//
// Extracts keywords from audio transcriptions correlated with cluster strokes.
// Uses temporal overlap to determine which words the professor was saying
// while the student was writing each cluster.
//
// ALGORITHM:
//   1. For each cluster, find its stroke IDs → look up SyncedStroke timestamps
//   2. Find TranscriptionSegments overlapping that time range
//   3. Tokenize overlapping segment text
//   4. Filter stop-words (IT + EN)
//   5. Score by frequency + position weighting
//   6. Return top keywords as semantic title
// =============================================================================

/// 🔑 Extracts keywords from audio transcriptions to generate cluster titles.
///
/// Pure Dart, zero dependencies. Correlates temporal overlap between
/// handwritten strokes and speech segments to determine what was being
/// said when each cluster was written.
class AudioKeywordExtractor {
  const AudioKeywordExtractor._();

  // ===========================================================================
  // PUBLIC API
  // ===========================================================================

  /// Build audio-derived titles for all clusters.
  ///
  /// Returns a map of cluster ID → keyword title string.
  /// Only clusters with temporal overlap to transcription segments get a title.
  ///
  /// [clusters] — all content clusters on the canvas.
  /// [recordings] — synchronized recordings with transcription data.
  /// [clusterTexts] — existing recognized text per cluster (for dedup).
  static Map<String, String> buildClusterAudioTitles({
    required List<ContentCluster> clusters,
    required List<SynchronizedRecording> recordings,
    Map<String, String>? clusterTexts,
  }) {
    if (clusters.isEmpty || recordings.isEmpty) return {};

    // Pre-parse all transcription segments from all recordings
    final parsedRecordings = <_ParsedRecording>[];
    for (final recording in recordings) {
      if (!recording.hasTranscription) continue;
      if (recording.transcriptionSegmentsJson == null) continue;

      try {
        final result = TranscriptionResult.fromJsonString(
          recording.transcriptionSegmentsJson!,
        );
        if (result.segments.isNotEmpty) {
          parsedRecordings.add(_ParsedRecording(
            recording: recording,
            transcription: result,
          ));
        }
      } catch (_) {
        // Malformed JSON — skip this recording
      }
    }

    if (parsedRecordings.isEmpty) return {};

    // Build stroke → timestamp lookup from all recordings
    final strokeTimestamps = <String, _StrokeTimeRange>{};
    for (final parsed in parsedRecordings) {
      for (final synced in parsed.recording.syncedStrokes) {
        strokeTimestamps[synced.stroke.id] = _StrokeTimeRange(
          startMs: synced.relativeStartMs,
          endMs: synced.relativeEndMs,
          recording: parsed,
        );
      }
    }

    // Extract keywords for each cluster
    final result = <String, String>{};
    for (final cluster in clusters) {
      // Skip clusters that already have recognized handwriting text
      final existingText = clusterTexts?[cluster.id];
      if (existingText != null && existingText.trim().isNotEmpty) continue;

      final title = _extractKeywordsForCluster(
        cluster: cluster,
        strokeTimestamps: strokeTimestamps,
      );
      if (title != null && title.isNotEmpty) {
        result[cluster.id] = title;
      }
    }

    return result;
  }

  // ===========================================================================
  // INTERNAL — Per-cluster extraction
  // ===========================================================================

  /// Extract keywords for a single cluster by correlating stroke timestamps
  /// with transcription segments.
  static String? _extractKeywordsForCluster({
    required ContentCluster cluster,
    required Map<String, _StrokeTimeRange> strokeTimestamps,
  }) {
    // Find temporal range of this cluster's strokes
    int? clusterStartMs;
    int? clusterEndMs;
    _ParsedRecording? matchedRecording;

    for (final strokeId in cluster.strokeIds) {
      final ts = strokeTimestamps[strokeId];
      if (ts == null) continue;

      matchedRecording ??= ts.recording;
      // Only correlate within the same recording
      if (ts.recording != matchedRecording) continue;

      if (clusterStartMs == null || ts.startMs < clusterStartMs) {
        clusterStartMs = ts.startMs;
      }
      if (clusterEndMs == null || ts.endMs > clusterEndMs) {
        clusterEndMs = ts.endMs;
      }
    }

    if (clusterStartMs == null || clusterEndMs == null || matchedRecording == null) {
      return null;
    }

    // Expand the time window slightly (±2 seconds) to capture context
    final windowStartMs = (clusterStartMs - 2000).clamp(0, double.maxFinite.toInt());
    final windowEndMs = clusterEndMs + 2000;

    // Find overlapping transcription segments
    final overlappingText = StringBuffer();
    for (final segment in matchedRecording.transcription.segments) {
      final segStartMs = segment.start.inMilliseconds;
      final segEndMs = segment.end.inMilliseconds;

      // Check temporal overlap
      if (segStartMs <= windowEndMs && segEndMs >= windowStartMs) {
        if (overlappingText.isNotEmpty) overlappingText.write(' ');
        overlappingText.write(segment.text);
      }
    }

    if (overlappingText.isEmpty) return null;

    // Extract and score keywords
    return _extractTitle(overlappingText.toString());
  }

  // ===========================================================================
  // KEYWORD EXTRACTION PIPELINE
  // ===========================================================================

  /// Extract a title from raw text using tokenization, stop-word filtering,
  /// and frequency-based scoring.
  static String? _extractTitle(String rawText) {
    final tokens = _tokenize(rawText);
    if (tokens.isEmpty) return null;

    // Filter stop-words and very short tokens
    final keywords = tokens
        .where((t) => t.length >= 3 && !_isStopWord(t))
        .toList();

    if (keywords.isEmpty) return null;

    // Score keywords by frequency with position weighting
    final scores = _scoreKeywords(keywords);

    // Take top 3 keywords by score
    final sorted = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final topKeywords = sorted
        .take(3)
        .map((e) => _capitalize(e.key))
        .toList();

    if (topKeywords.isEmpty) return null;

    final title = topKeywords.join(' • ');

    // Truncate to 25 chars with ellipsis
    if (title.length <= 25) return title;
    return '${title.substring(0, 23)}…';
  }

  /// Tokenize raw text: lowercase, split on whitespace and punctuation.
  static List<String> _tokenize(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
  }

  /// Score keywords by frequency with position weighting.
  /// Earlier appearances get a slight boost (1.2× for first quarter).
  static Map<String, double> _scoreKeywords(List<String> keywords) {
    final scores = <String, double>{};
    final total = keywords.length;

    for (int i = 0; i < keywords.length; i++) {
      final word = keywords[i];
      // Position weight: first quarter gets 1.2×, last quarter gets 0.8×
      final positionRatio = i / total;
      final positionWeight = positionRatio < 0.25
          ? 1.2
          : positionRatio > 0.75
              ? 0.8
              : 1.0;

      scores[word] = (scores[word] ?? 0.0) + positionWeight;
    }

    return scores;
  }

  /// Capitalize first letter of a word.
  static String _capitalize(String word) {
    if (word.isEmpty) return word;
    return word[0].toUpperCase() + word.substring(1);
  }

  /// Check if a token is a stop-word (IT + EN).
  static bool _isStopWord(String token) {
    return _stopWordsIt.contains(token) || _stopWordsEn.contains(token);
  }

  // ===========================================================================
  // STOP-WORD LISTS
  // ===========================================================================

  /// Italian stop-words (~80 most common).
  static const _stopWordsIt = <String>{
    'il', 'lo', 'la', 'le', 'gli', 'un', 'uno', 'una',
    'di', 'del', 'dello', 'della', 'dei', 'degli', 'delle',
    'da', 'dal', 'dallo', 'dalla', 'dai', 'dagli', 'dalle',
    'in', 'nel', 'nello', 'nella', 'nei', 'negli', 'nelle',
    'su', 'sul', 'sullo', 'sulla', 'sui', 'sugli', 'sulle',
    'con', 'per', 'tra', 'fra',
    'che', 'chi', 'cui', 'come', 'dove', 'quando', 'quanto',
    'non', 'più', 'piu', 'anche', 'solo', 'già', 'gia',
    'molto', 'poco', 'tanto', 'tutto', 'tutti', 'tutte',
    'questo', 'questa', 'questi', 'queste', 'quello', 'quella',
    'quelli', 'quelle', 'quel',
    'suo', 'sua', 'suoi', 'sue', 'mio', 'mia', 'miei', 'mie',
    'tuo', 'tua', 'tuoi', 'tue', 'nostro', 'nostra', 'vostro', 'vostra',
    'sono', 'sei', 'siamo', 'siete', 'era', 'ero', 'eravamo',
    'essere', 'stato', 'stata', 'stati', 'state', 'avere',
    'avuto', 'aveva', 'avevo', 'abbiamo', 'avete', 'hanno',
    'fare', 'fatto', 'dire', 'detto', 'potere', 'volere',
    'dovere', 'sapere', 'stare', 'andare',
    'cosa', 'perché', 'perche', 'ancora', 'dopo', 'prima',
    'qui', 'ora', 'poi', 'sempre', 'mai', 'bene', 'male',
    'parte', 'modo', 'caso', 'anno', 'tempo',
    'altro', 'altra', 'altri', 'altre',
    'ogni', 'quale', 'quali', 'stesso', 'stessa',
    'proprio', 'propria', 'cioè', 'cioe', 'invece', 'dunque',
    'oppure', 'quindi', 'allora', 'però', 'pero',
  };

  /// English stop-words (~80 most common).
  static const _stopWordsEn = <String>{
    'the', 'a', 'an', 'and', 'or', 'but', 'in', 'on', 'at',
    'to', 'for', 'of', 'with', 'by', 'from', 'as', 'is', 'was',
    'are', 'were', 'be', 'been', 'being', 'have', 'has', 'had',
    'do', 'does', 'did', 'will', 'would', 'could', 'should',
    'may', 'might', 'must', 'shall', 'can',
    'not', 'no', 'nor', 'so', 'if', 'then', 'than', 'too',
    'very', 'just', 'about', 'also', 'more', 'most', 'some',
    'any', 'each', 'every', 'all', 'both', 'few', 'many',
    'much', 'own', 'other', 'such', 'only',
    'that', 'this', 'these', 'those', 'what', 'which', 'who',
    'whom', 'when', 'where', 'why', 'how',
    'its', 'his', 'her', 'our', 'your', 'their', 'my',
    'him', 'she', 'they', 'them', 'we', 'you',
    'up', 'out', 'into', 'over', 'after', 'before',
    'between', 'under', 'again', 'further', 'here', 'there',
    'once', 'during', 'while', 'through',
    'same', 'because', 'until', 'against', 'above', 'below',
    'get', 'got', 'make', 'made', 'say', 'said', 'going',
  };
}

// =============================================================================
// INTERNAL HELPER TYPES
// =============================================================================

/// Parsed recording with pre-decoded transcription.
class _ParsedRecording {
  final SynchronizedRecording recording;
  final TranscriptionResult transcription;

  const _ParsedRecording({
    required this.recording,
    required this.transcription,
  });
}

/// Temporal range of a single stroke relative to its recording.
class _StrokeTimeRange {
  final int startMs;
  final int endMs;
  final _ParsedRecording recording;

  const _StrokeTimeRange({
    required this.startMs,
    required this.endMs,
    required this.recording,
  });
}
