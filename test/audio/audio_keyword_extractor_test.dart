import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/audio/audio_keyword_extractor.dart';
import 'package:fluera_engine/src/audio/transcription_result.dart';
import 'package:fluera_engine/src/time_travel/models/synchronized_recording.dart';
import 'package:fluera_engine/src/drawing/models/pro_drawing_point.dart';
import 'package:fluera_engine/src/reflow/content_cluster.dart';

// =============================================================================
// 🔑 AUDIO KEYWORD EXTRACTOR — UNIT TESTS
// =============================================================================

/// Helper: create a minimal ProStroke with a given ID and timestamp range.
ProStroke _makeStroke(String id, int startMs, int endMs) {
  return ProStroke(
    id: id,
    points: [
      ProDrawingPoint(
        position: const Offset(10, 10),
        pressure: 0.5,
        timestamp: startMs,
      ),
      ProDrawingPoint(
        position: const Offset(20, 20),
        pressure: 0.5,
        timestamp: endMs,
      ),
    ],
    color: const Color(0xFF000000),
    baseWidth: 2.0,
    penType: ProPenType.ballpoint,
    createdAt: DateTime(2026, 1, 1),
  );
}

/// Helper: create a SynchronizedRecording with strokes and transcription.
SynchronizedRecording _makeRecording({
  required List<SyncedStroke> syncedStrokes,
  required TranscriptionResult transcription,
}) {
  return SynchronizedRecording(
    id: 'rec-1',
    audioPath: '/tmp/test.m4a',
    totalDuration: const Duration(minutes: 5),
    startTime: DateTime(2026, 1, 1),
    syncedStrokes: syncedStrokes,
    canvasId: 'canvas-1',
    transcriptionText: transcription.text,
    transcriptionLanguage: transcription.language,
    transcriptionSegmentsJson: transcription.toJsonString(),
  );
}

/// Helper: create a ContentCluster with given stroke IDs.
ContentCluster _makeCluster(String id, List<String> strokeIds) {
  return ContentCluster(
    id: id,
    strokeIds: strokeIds,
    bounds: const Rect.fromLTWH(0, 0, 100, 100),
    centroid: const Offset(50, 50),
  );
}

void main() {
  group('AudioKeywordExtractor', () {
    // ─────────────────────────────────────────────────────────────────────
    // BASIC FUNCTIONALITY
    // ─────────────────────────────────────────────────────────────────────

    test('extracts keywords from overlapping transcription segments', () {
      final stroke = _makeStroke('s1', 5000, 8000);
      final synced = SyncedStroke(
        stroke: stroke,
        relativeStartMs: 5000,
        relativeEndMs: 8000,
      );

      final transcription = TranscriptionResult(
        text: 'Dobbiamo analizzare la derivata della funzione logaritmica',
        segments: [
          TranscriptionSegment(
            text: 'Dobbiamo analizzare la derivata della funzione logaritmica',
            start: const Duration(milliseconds: 4500),
            end: const Duration(milliseconds: 9000),
          ),
        ],
        language: 'it',
        audioDuration: const Duration(minutes: 5),
        transcribedAt: DateTime(2026, 1, 1),
      );

      final recording = _makeRecording(
        syncedStrokes: [synced],
        transcription: transcription,
      );

      final cluster = _makeCluster('c1', ['s1']);

      final result = AudioKeywordExtractor.buildClusterAudioTitles(
        clusters: [cluster],
        recordings: [recording],
      );

      expect(result, isNotEmpty);
      expect(result.containsKey('c1'), isTrue);
      final title = result['c1']!;
      expect(title, isNotEmpty);
      // Should NOT contain Italian stop-words
      expect(title.toLowerCase().contains(' la '), isFalse);
      expect(title.toLowerCase().contains(' della '), isFalse);
    });

    // ─────────────────────────────────────────────────────────────────────
    // STOP-WORD FILTERING
    // ─────────────────────────────────────────────────────────────────────

    test('filters Italian stop-words correctly', () {
      final stroke = _makeStroke('s1', 1000, 3000);
      final synced = SyncedStroke(
        stroke: stroke,
        relativeStartMs: 1000,
        relativeEndMs: 3000,
      );

      final transcription = TranscriptionResult(
        text: 'il gatto è sul tavolo nella stanza',
        segments: [
          TranscriptionSegment(
            text: 'il gatto è sul tavolo nella stanza',
            start: const Duration(milliseconds: 500),
            end: const Duration(milliseconds: 4000),
          ),
        ],
        language: 'it',
        audioDuration: const Duration(seconds: 10),
        transcribedAt: DateTime(2026, 1, 1),
      );

      final recording = _makeRecording(
        syncedStrokes: [synced],
        transcription: transcription,
      );

      final cluster = _makeCluster('c1', ['s1']);
      final result = AudioKeywordExtractor.buildClusterAudioTitles(
        clusters: [cluster],
        recordings: [recording],
      );

      expect(result, isNotEmpty);
      final title = result['c1']!;
      // "gatto", "tavolo", "stanza" should survive
      expect(title.toLowerCase(), contains('gatto'));
    });

    test('filters English stop-words correctly', () {
      final stroke = _makeStroke('s1', 1000, 3000);
      final synced = SyncedStroke(
        stroke: stroke,
        relativeStartMs: 1000,
        relativeEndMs: 3000,
      );

      final transcription = TranscriptionResult(
        text: 'the function derivative logarithm analysis',
        segments: [
          TranscriptionSegment(
            text: 'the function derivative logarithm analysis',
            start: const Duration(milliseconds: 500),
            end: const Duration(milliseconds: 4000),
          ),
        ],
        language: 'en',
        audioDuration: const Duration(seconds: 10),
        transcribedAt: DateTime(2026, 1, 1),
      );

      final recording = _makeRecording(
        syncedStrokes: [synced],
        transcription: transcription,
      );

      final cluster = _makeCluster('c1', ['s1']);
      final result = AudioKeywordExtractor.buildClusterAudioTitles(
        clusters: [cluster],
        recordings: [recording],
      );

      expect(result, isNotEmpty);
      final title = result['c1']!;
      // "the" should be filtered
      expect(title.toLowerCase(), isNot(startsWith('the')));
    });

    // ─────────────────────────────────────────────────────────────────────
    // TEMPORAL CORRELATION
    // ─────────────────────────────────────────────────────────────────────

    test('only matches segments overlapping with stroke timestamps', () {
      final stroke = _makeStroke('s1', 5000, 8000);
      final synced = SyncedStroke(
        stroke: stroke,
        relativeStartMs: 5000,
        relativeEndMs: 8000,
      );

      // Two segments: one overlaps (4000-9000), one doesn't (20000-25000)
      final transcription = TranscriptionResult(
        text: 'derivata funzione algebra equazione',
        segments: [
          TranscriptionSegment(
            text: 'derivata funzione',
            start: const Duration(milliseconds: 4000),
            end: const Duration(milliseconds: 9000),
          ),
          TranscriptionSegment(
            text: 'algebra equazione',
            start: const Duration(milliseconds: 20000),
            end: const Duration(milliseconds: 25000),
          ),
        ],
        language: 'it',
        audioDuration: const Duration(minutes: 1),
        transcribedAt: DateTime(2026, 1, 1),
      );

      final recording = _makeRecording(
        syncedStrokes: [synced],
        transcription: transcription,
      );

      final cluster = _makeCluster('c1', ['s1']);
      final result = AudioKeywordExtractor.buildClusterAudioTitles(
        clusters: [cluster],
        recordings: [recording],
      );

      expect(result, isNotEmpty);
      final title = result['c1']!.toLowerCase();
      // Should contain words from overlapping segment
      expect(
        title.contains('derivata') || title.contains('funzione'),
        isTrue,
      );
      // Should NOT contain words from non-overlapping segment
      expect(title.contains('algebra'), isFalse);
      expect(title.contains('equazione'), isFalse);
    });

    // ─────────────────────────────────────────────────────────────────────
    // FREQUENCY SCORING
    // ─────────────────────────────────────────────────────────────────────

    test('repeated words rank higher', () {
      final stroke = _makeStroke('s1', 1000, 10000);
      final synced = SyncedStroke(
        stroke: stroke,
        relativeStartMs: 1000,
        relativeEndMs: 10000,
      );

      final transcription = TranscriptionResult(
        text: 'derivata derivata logaritmo derivata integrale',
        segments: [
          TranscriptionSegment(
            text: 'derivata derivata logaritmo derivata integrale',
            start: const Duration(milliseconds: 500),
            end: const Duration(milliseconds: 11000),
          ),
        ],
        language: 'it',
        audioDuration: const Duration(seconds: 15),
        transcribedAt: DateTime(2026, 1, 1),
      );

      final recording = _makeRecording(
        syncedStrokes: [synced],
        transcription: transcription,
      );

      final cluster = _makeCluster('c1', ['s1']);
      final result = AudioKeywordExtractor.buildClusterAudioTitles(
        clusters: [cluster],
        recordings: [recording],
      );

      expect(result, isNotEmpty);
      final title = result['c1']!;
      // "Derivata" should be the first keyword (highest score)
      expect(title, startsWith('Derivata'));
    });

    // ─────────────────────────────────────────────────────────────────────
    // EDGE CASES
    // ─────────────────────────────────────────────────────────────────────

    test('returns empty on empty recordings', () {
      final result = AudioKeywordExtractor.buildClusterAudioTitles(
        clusters: [_makeCluster('c1', ['s1'])],
        recordings: [],
      );
      expect(result, isEmpty);
    });

    test('returns empty on empty clusters', () {
      final transcription = TranscriptionResult(
        text: 'test',
        segments: [
          TranscriptionSegment(
            text: 'test',
            start: Duration.zero,
            end: const Duration(seconds: 1),
          ),
        ],
        language: 'en',
        audioDuration: const Duration(seconds: 5),
        transcribedAt: DateTime(2026, 1, 1),
      );

      final recording = _makeRecording(
        syncedStrokes: [],
        transcription: transcription,
      );

      final result = AudioKeywordExtractor.buildClusterAudioTitles(
        clusters: [],
        recordings: [recording],
      );
      expect(result, isEmpty);
    });

    test('skips clusters that already have recognized text', () {
      final stroke = _makeStroke('s1', 1000, 3000);
      final synced = SyncedStroke(
        stroke: stroke,
        relativeStartMs: 1000,
        relativeEndMs: 3000,
      );

      final transcription = TranscriptionResult(
        text: 'derivata funzione',
        segments: [
          TranscriptionSegment(
            text: 'derivata funzione',
            start: const Duration(milliseconds: 500),
            end: const Duration(milliseconds: 4000),
          ),
        ],
        language: 'it',
        audioDuration: const Duration(seconds: 10),
        transcribedAt: DateTime(2026, 1, 1),
      );

      final recording = _makeRecording(
        syncedStrokes: [synced],
        transcription: transcription,
      );

      final cluster = _makeCluster('c1', ['s1']);
      final result = AudioKeywordExtractor.buildClusterAudioTitles(
        clusters: [cluster],
        recordings: [recording],
        clusterTexts: {'c1': 'Existing OCR text'},
      );

      // Should not produce audio title (OCR text takes priority)
      expect(result.containsKey('c1'), isFalse);
    });

    test('handles title truncation to 25 chars', () {
      final stroke = _makeStroke('s1', 1000, 10000);
      final synced = SyncedStroke(
        stroke: stroke,
        relativeStartMs: 1000,
        relativeEndMs: 10000,
      );

      final transcription = TranscriptionResult(
        text: 'termodinamica elettromagnetismo cristallografia',
        segments: [
          TranscriptionSegment(
            text: 'termodinamica elettromagnetismo cristallografia',
            start: const Duration(milliseconds: 500),
            end: const Duration(milliseconds: 11000),
          ),
        ],
        language: 'it',
        audioDuration: const Duration(seconds: 15),
        transcribedAt: DateTime(2026, 1, 1),
      );

      final recording = _makeRecording(
        syncedStrokes: [synced],
        transcription: transcription,
      );

      final cluster = _makeCluster('c1', ['s1']);
      final result = AudioKeywordExtractor.buildClusterAudioTitles(
        clusters: [cluster],
        recordings: [recording],
      );

      if (result.containsKey('c1')) {
        expect(result['c1']!.length, lessThanOrEqualTo(25));
      }
    });

    test('handles malformed transcription JSON gracefully', () {
      final recording = SynchronizedRecording(
        id: 'rec-1',
        audioPath: '/tmp/test.m4a',
        totalDuration: const Duration(minutes: 5),
        startTime: DateTime(2026, 1, 1),
        syncedStrokes: [],
        transcriptionText: 'some text',
        transcriptionLanguage: 'en',
        transcriptionSegmentsJson: 'NOT VALID JSON {{{',
      );

      final cluster = _makeCluster('c1', ['s1']);

      // Should not throw
      final result = AudioKeywordExtractor.buildClusterAudioTitles(
        clusters: [cluster],
        recordings: [recording],
      );

      expect(result, isEmpty);
    });
  });
}
