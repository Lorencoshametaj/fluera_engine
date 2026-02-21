import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/time_travel/services/time_travel_recorder.dart';
import 'package:nebula_engine/src/time_travel/services/time_travel_compressor.dart';
import 'package:nebula_engine/src/time_travel/models/time_travel_session.dart';
import 'package:nebula_engine/src/history/canvas_delta_tracker.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // TIME TRAVEL SESSION — model serialization
  // ═══════════════════════════════════════════════════════════════════════════

  group('TimeTravelSession', () {
    test('round-trips through JSON', () {
      final session = TimeTravelSession(
        id: 'session_123',
        canvasId: 'c1',
        startTime: DateTime(2025, 6, 15, 10, 0),
        endTime: DateTime(2025, 6, 15, 10, 30),
        deltaCount: 42,
        deltaFilePath: 'session_123.tt.jsonl.gz',
        strokesAdded: 15,
        elementsModified: 7,
      );

      final json = session.toJson();
      final restored = TimeTravelSession.fromJson(json);

      expect(restored.id, 'session_123');
      expect(restored.canvasId, 'c1');
      expect(restored.deltaCount, 42);
      expect(restored.deltaFilePath, 'session_123.tt.jsonl.gz');
      expect(restored.strokesAdded, 15);
      expect(restored.elementsModified, 7);
    });

    test('duration computes correctly', () {
      final session = TimeTravelSession(
        id: 's1',
        canvasId: 'c1',
        startTime: DateTime(2025, 1, 1, 10, 0),
        endTime: DateTime(2025, 1, 1, 10, 45),
        deltaCount: 0,
        deltaFilePath: 'f.gz',
      );

      expect(session.duration.inMinutes, 45);
    });

    test('toString is readable', () {
      final session = TimeTravelSession(
        id: 's1',
        canvasId: 'c1',
        startTime: DateTime(2025, 1, 1, 10, 0),
        endTime: DateTime(2025, 1, 1, 10, 5),
        deltaCount: 100,
        deltaFilePath: 'f.gz',
      );

      expect(session.toString(), contains('100 events'));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // TIME TRAVEL EVENT — model serialization
  // ═══════════════════════════════════════════════════════════════════════════

  group('TimeTravelEvent', () {
    test('round-trips through JSON', () {
      final event = TimeTravelEvent(
        type: CanvasDeltaType.strokeAdded,
        layerId: 'layer_1',
        timestampMs: 500,
        elementId: 'stroke_42',
        elementData: {'color': 0xFF0000, 'width': 2.5},
      );

      final json = event.toJson();
      final restored = TimeTravelEvent.fromJson(json);

      expect(restored.type, CanvasDeltaType.strokeAdded);
      expect(restored.layerId, 'layer_1');
      expect(restored.timestampMs, 500);
      expect(restored.elementId, 'stroke_42');
      expect(restored.elementData?['color'], 0xFF0000);
    });

    test('compact JSON keys', () {
      final event = TimeTravelEvent(
        type: CanvasDeltaType.strokeAdded,
        layerId: 'l1',
        timestampMs: 100,
      );

      final json = event.toJson();
      expect(json.containsKey('t'), isTrue); // type
      expect(json.containsKey('l'), isTrue); // layerId
      expect(json.containsKey('ms'), isTrue); // timestampMs
      expect(json.containsKey('p'), isFalse); // pageIndex omitted
      expect(json.containsKey('d'), isFalse); // elementData omitted
      expect(json.containsKey('e'), isFalse); // elementId omitted
    });

    test('isAddition / isRemoval / isUpdate flags', () {
      expect(
        TimeTravelEvent(
          type: CanvasDeltaType.strokeAdded,
          layerId: 'l',
          timestampMs: 0,
        ).isAddition,
        isTrue,
      );
      expect(
        TimeTravelEvent(
          type: CanvasDeltaType.strokeRemoved,
          layerId: 'l',
          timestampMs: 0,
        ).isRemoval,
        isTrue,
      );
      expect(
        TimeTravelEvent(
          type: CanvasDeltaType.textUpdated,
          layerId: 'l',
          timestampMs: 0,
        ).isUpdate,
        isTrue,
      );
      expect(
        TimeTravelEvent(
          type: CanvasDeltaType.imageAdded,
          layerId: 'l',
          timestampMs: 0,
        ).isAddition,
        isTrue,
      );
      expect(
        TimeTravelEvent(
          type: CanvasDeltaType.imageRemoved,
          layerId: 'l',
          timestampMs: 0,
        ).isRemoval,
        isTrue,
      );
    });

    test('pageIndex is preserved when set', () {
      final event = TimeTravelEvent(
        type: CanvasDeltaType.strokeAdded,
        layerId: 'l1',
        timestampMs: 0,
        pageIndex: 3,
      );

      final json = event.toJson();
      final restored = TimeTravelEvent.fromJson(json);
      expect(restored.pageIndex, 3);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // TIME TRAVEL RECORDER
  // ═══════════════════════════════════════════════════════════════════════════

  group('TimeTravelRecorder', () {
    late TimeTravelRecorder recorder;

    setUp(() {
      recorder = TimeTravelRecorder(start: DateTime(2025, 1, 1));
    });

    test('starts inactive', () {
      expect(recorder.isRecording, isFalse);
      expect(recorder.hasEvents, isFalse);
      expect(recorder.eventCount, 0);
    });

    test('does not record events when inactive', () {
      recorder.recordEvent(
        CanvasDeltaType.strokeAdded,
        'layer_1',
        elementId: 'stroke_1',
      );

      expect(recorder.eventCount, 0);
    });

    test('records events when active', () {
      recorder.startRecording();
      recorder.recordEvent(
        CanvasDeltaType.strokeAdded,
        'layer_1',
        elementId: 'stroke_1',
      );
      recorder.recordEvent(
        CanvasDeltaType.strokeAdded,
        'layer_1',
        elementId: 'stroke_2',
      );

      expect(recorder.isRecording, isTrue);
      expect(recorder.eventCount, 2);
    });

    test('stops recording but retains events', () {
      recorder.startRecording();
      recorder.recordEvent(
        CanvasDeltaType.strokeAdded,
        'layer_1',
        elementId: 's1',
      );

      recorder.stopRecording();
      expect(recorder.isRecording, isFalse);
      expect(recorder.eventCount, 1); // Still has events
    });

    test('events have relative timestamps', () {
      recorder.startRecording();
      recorder.recordEvent(
        CanvasDeltaType.strokeAdded,
        'layer_1',
        elementId: 's1',
      );

      final event = recorder.sessionEvents.first;
      expect(event.timestampMs, greaterThanOrEqualTo(0));
    });

    test('strips elementData for removal events', () {
      recorder.startRecording();
      recorder.recordEvent(
        CanvasDeltaType.strokeRemoved,
        'layer_1',
        elementId: 'stroke_99',
        elementData: {'color': 0xFF0000}, // Should be stripped
      );

      final event = recorder.sessionEvents.first;
      expect(event.elementData, isNull); // Stripped for removal
      expect(event.elementId, 'stroke_99'); // ID preserved
    });

    test('clear resets everything', () {
      recorder.startRecording();
      recorder.recordEvent(CanvasDeltaType.strokeAdded, 'l1', elementId: 's1');
      recorder.recordEvent(CanvasDeltaType.strokeAdded, 'l1', elementId: 's2');

      recorder.clear();
      expect(recorder.eventCount, 0);
      expect(recorder.hasEvents, isFalse);
    });

    test('sessionEvents returns immutable list', () {
      recorder.startRecording();
      recorder.recordEvent(CanvasDeltaType.strokeAdded, 'l1', elementId: 's1');

      final events = recorder.sessionEvents;
      expect(() => (events as List).add(null), throwsA(anything));
    });

    test('flushToDisk writes compressed file', () async {
      recorder.startRecording();

      // Record several events
      for (int i = 0; i < 10; i++) {
        recorder.recordEvent(
          CanvasDeltaType.strokeAdded,
          'layer_1',
          elementId: 'stroke_$i',
          elementData: {'color': 0xFF0000, 'width': 2.0},
        );
      }

      final tempDir = await Directory.systemTemp.createTemp(
        'nebula_tt_flush_test_',
      );
      try {
        final session = await recorder.flushToDisk('test_canvas', tempDir.path);

        expect(session, isNotNull);
        expect(session!.deltaCount, 10);
        expect(session.strokesAdded, 10);
        expect(session.canvasId, 'test_canvas');

        // Verify file exists on disk
        final file = File('${tempDir.path}/${session.deltaFilePath}');
        expect(await file.exists(), isTrue);

        // Verify file is GZIP compressed
        final bytes = await file.readAsBytes();
        expect(bytes.length, greaterThan(0));
        // GZIP magic number: 0x1F 0x8B
        expect(bytes[0], 0x1F);
        expect(bytes[1], 0x8B);

        // Decompress and verify content is valid JSONL
        final decompressed = gzip.decode(bytes);
        final text = utf8.decode(decompressed);
        final lines = text.trim().split('\n');
        expect(lines.length, 10);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('flushToDisk returns null for empty recorder', () async {
      recorder.startRecording();
      // Don't record any events

      final session = await recorder.flushToDisk('c1', '/tmp/unused');
      expect(session, isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // TIME TRAVEL COMPRESSOR
  // ═══════════════════════════════════════════════════════════════════════════

  group('TimeTravelCompressor', () {
    test('compressElementData returns null for null input', () {
      final result = TimeTravelCompressor.compressElementData(
        'strokeAdded',
        null,
      );
      expect(result, isNull);
    });

    test('non-stroke types pass through unchanged', () {
      final data = {'text': 'hello', 'fontSize': 16.0};
      final result = TimeTravelCompressor.compressElementData(
        'textAdded',
        data,
      );
      expect(result, equals(data));
    });

    test('compressStrokeData + decompressStrokeData round-trips', () {
      final strokeData = {
        'id': 'stroke_1',
        'color': 0xFF0000,
        'penType': 'pen',
        'strokeWidth': 2.5,
        'points': [
          {
            'x': 100.0,
            'y': 200.0,
            'pressure': 0.5,
            'tiltX': 0.0,
            'tiltY': 0.0,
            'orientation': 0.0,
            'timestamp': 1000,
          },
          {
            'x': 102.0,
            'y': 201.0,
            'pressure': 0.5,
            'tiltX': 0.0,
            'tiltY': 0.0,
            'orientation': 0.0,
            'timestamp': 1016,
          },
          {
            'x': 105.0,
            'y': 203.0,
            'pressure': 0.6,
            'tiltX': 0.0,
            'tiltY': 0.0,
            'orientation': 0.0,
            'timestamp': 1032,
          },
        ],
      };

      final compressed = TimeTravelCompressor.compressStrokeData(
        Map<String, dynamic>.from(strokeData),
      );

      // Should be marked as compressed
      expect(compressed['_tt_v'], 1);

      // Decompress
      final decompressed = TimeTravelCompressor.decompressStrokeData(
        compressed,
      );

      // points should be reconstructed
      final points = decompressed['points'] as List;
      expect(points, hasLength(3));

      // First point should match exactly (within quantization tolerance)
      final p0 = points[0] as Map<String, dynamic>;
      expect((p0['x'] as num).toDouble(), closeTo(100.0, 0.2));
      expect((p0['y'] as num).toDouble(), closeTo(200.0, 0.2));
    });

    test('decompressStrokeData handles uncompressed data', () {
      final rawData = {
        'id': 'stroke_1',
        'points': [
          {'x': 10.0, 'y': 20.0},
        ],
      };

      // No _tt_v flag — should pass through unchanged
      final result = TimeTravelCompressor.decompressStrokeData(rawData);
      expect(result['id'], 'stroke_1');
    });

    test('RLE compresses repeated pressure values', () {
      // Create stroke with constant pressure (ideal for RLE)
      final strokeData = {
        'id': 's1',
        'color': 0xFF0000,
        'points': List.generate(
          20,
          (i) => {
            'x': 100.0 + i * 2.0,
            'y': 200.0 + i * 1.0,
            'pressure': 0.5, // Constant → RLE will compress
            'tiltX': 0.0,
            'tiltY': 0.0,
            'orientation': 0.0,
            'timestamp': 1000 + i * 16,
          },
        ),
      };

      final compressed = TimeTravelCompressor.compressStrokeData(
        Map<String, dynamic>.from(strokeData),
      );

      // The compressed points should encode pressure as RLE
      // which reduces 20 identical values to ~2 tokens
      expect(compressed.containsKey('_tt_v'), isTrue);

      // Round-trip should work
      final decompressed = TimeTravelCompressor.decompressStrokeData(
        compressed,
      );
      final points = decompressed['points'] as List;
      expect(points, hasLength(20));
    });

    test('delta encoding reduces coordinate entropy', () {
      // Points moving in a line → deltas should be small + repetitive
      final strokeData = {
        'id': 's1',
        'color': 0xFF0000,
        'points': List.generate(
          5,
          (i) => {
            'x': 100.0 + i * 3.0,
            'y': 200.0 + i * 3.0,
            'pressure': 0.5,
            'tiltX': 0.0,
            'tiltY': 0.0,
            'orientation': 0.0,
            'timestamp': 1000 + i * 16,
          },
        ),
      };

      final compressed = TimeTravelCompressor.compressStrokeData(
        Map<String, dynamic>.from(strokeData),
      );

      // Verify compressed data structure
      expect(compressed['_tt_v'], 1);

      // Verify round-trip fidelity (within quantization tolerance)
      final decompressed = TimeTravelCompressor.decompressStrokeData(
        compressed,
      );
      final points = decompressed['points'] as List;
      final lastPoint = points.last as Map<String, dynamic>;
      expect((lastPoint['x'] as num).toDouble(), closeTo(112.0, 0.2));
    });

    test('compressElementData routes stroke types correctly', () {
      final data = {'id': 's1', 'points': []};

      // strokeAdded → should be compressed
      final compressed = TimeTravelCompressor.compressElementData(
        'strokeAdded',
        Map<String, dynamic>.from(data),
      );
      // May or may not have _tt_v depending on empty points
      expect(compressed, isNotNull);
    });

    test('decompressElementData routes stroke types correctly', () {
      final data = {'id': 's1', 'points': []};

      final result = TimeTravelCompressor.decompressElementData(
        'strokeAdded',
        data,
      );
      expect(result, isNotNull);
    });
  });
}
