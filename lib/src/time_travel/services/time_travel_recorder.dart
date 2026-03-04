import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/time_travel_session.dart';
import '../../history/canvas_delta_tracker.dart';
import './time_travel_compressor.dart';

/// 🎬 Time Travel Recorder — passive listener che accumula eventi
///
/// Si aggancia al `LayerController` tramite callback `onTimeTravelEvent`.
/// Unlike the `CanvasDeltaTracker` (transient WAL consumed by
/// local save and from RTDB sync), the recorder **never loses
/// events** — it accumulates them for the entire session duration and
/// scrive to disk al termine (canvas close).
///
/// **Performance impact during drawing: ~0ms**
/// - `recordEvent()` does a single `List.add()` → O(1) amortized
/// - No serialization, no I/O, no compression
/// - Memory cost: ~200 byte/evento × 500 stroke = ~100 KB per session
class TimeTravelRecorder {
  /// Event buffer of the current session (never consumed)
  final List<TimeTravelEvent> _sessionEvents = [];

  /// Timestamp di inizio sessione (per calcolo ms relativi)
  final DateTime sessionStart;

  /// If true, il recorder is active (utente Pro)
  bool _isRecording = false;

  /// 🌿 Branch context: if non-null, events go to this branch's storage path
  String? activeBranchId;

  /// Contatori rapidi per metadata sessione
  int _strokesAdded = 0;
  int _elementsModified = 0;

  TimeTravelRecorder({DateTime? start})
    : sessionStart = start ?? DateTime.now();

  /// Indica if the recorder ha eventi
  bool get hasEvents => _sessionEvents.isNotEmpty;

  /// Total number of events recorded in the session
  int get eventCount => _sessionEvents.length;

  /// Indica if the recorder is active
  bool get isRecording => _isRecording;

  /// Immutable list of events of the current session
  List<TimeTravelEvent> get sessionEvents =>
      List<TimeTravelEvent>.unmodifiable(_sessionEvents);

  // ============================================================================
  // RECORDING CONTROL
  // ============================================================================

  /// 🟢 Start recording (called after Pro subscription check)
  void startRecording() {
    _isRecording = true;
  }

  /// 🔴 Ferma la registrazione (gli eventi restano in memoria)
  void stopRecording() {
    _isRecording = false;
  }

  // ============================================================================
  // EVENT RECORDING
  // ============================================================================

  /// 🎬 Record an event — called by LayerController after each modification
  ///
  /// This metodo is intenzionalmente leggero: solo un `List.add()`.
  /// The [type] and parameters correspond to those of `CanvasDeltaTracker`,
  /// but the data is accumulated in a separate and permanent buffer.
  void recordEvent(
    CanvasDeltaType type,
    String layerId, {
    String? elementId,
    Map<String, dynamic>? elementData,
    int? pageIndex,
  }) {
    if (!_isRecording) return;

    final now = DateTime.now();
    final relativeMs = now.difference(sessionStart).inMilliseconds;

    // For eventi di tipo *Removed, non serve elementData (basta elementId)
    // This risparmia ~30% of storage for sessions with many deletions
    final shouldStripData =
        (type == CanvasDeltaType.strokeRemoved ||
            type == CanvasDeltaType.shapeRemoved ||
            type == CanvasDeltaType.textRemoved ||
            type == CanvasDeltaType.imageRemoved ||
            type == CanvasDeltaType.layerRemoved);

    // 📦 Compress elementData for stroke (delta encoding + quantization + RLE)
    final compressedData =
        shouldStripData
            ? null
            : TimeTravelCompressor.compressElementData(type.name, elementData);

    _sessionEvents.add(
      TimeTravelEvent(
        type: type,
        layerId: layerId,
        pageIndex: pageIndex,
        timestampMs: relativeMs,
        elementData: compressedData,
        elementId: elementId,
      ),
    );

    // Update contatori rapidi
    if (type == CanvasDeltaType.strokeAdded) {
      _strokesAdded++;
    }
    if (type == CanvasDeltaType.textUpdated ||
        type == CanvasDeltaType.imageUpdated ||
        type == CanvasDeltaType.layerModified) {
      _elementsModified++;
    }

    // Log every 100 events for debug (not every event)
    if (_sessionEvents.length % 100 == 0) {
    }
  }

  // ============================================================================
  // FLUSH TO DISK
  // ============================================================================

  /// 💾 Writes session events to disk in compressed JSONL format
  ///
  /// Called at the closing of the canvas. The heavy operation (serialization
  /// + GZIP) happens in an isolate to not block UI.
  ///
  /// Returns la [TimeTravelSession] creata, o null if not ci sono eventi.
  Future<TimeTravelSession?> flushToDisk(
    String canvasId,
    String basePath,
  ) async {
    if (_sessionEvents.isEmpty) {
      return null;
    }

    final sessionEnd = DateTime.now();
    final sessionId = 'session_${sessionStart.millisecondsSinceEpoch}';
    final fileName = '$sessionId.tt.jsonl.gz';
    final filePath = p.join(basePath, fileName);

    try {
      // Serialize + comprimi in isolate (non blocca UI)
      final jsonLines = await compute(_serializeEvents, _sessionEvents);
      final compressed = await compute(gzip.encode, jsonLines);

      // Scrivi to disk
      final file = File(filePath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(compressed);

      final session = TimeTravelSession(
        id: sessionId,
        canvasId: canvasId,
        startTime: sessionStart,
        endTime: sessionEnd,
        deltaCount: _sessionEvents.length,
        deltaFilePath: fileName,
        strokesAdded: _strokesAdded,
        elementsModified: _elementsModified,
      );


      return session;
    } catch (e) {
      return null;
    }
  }

  /// Worker isolate: serialize events in UTF-8 JSONL bytes
  static List<int> _serializeEvents(List<TimeTravelEvent> events) {
    final buffer = StringBuffer();
    for (final event in events) {
      buffer.writeln(jsonEncode(event.toJson()));
    }
    return utf8.encode(buffer.toString());
  }

  /// Resets il recorder (per nuovo ciclo di vita, normalmente non usato)
  void clear() {
    _sessionEvents.clear();
    _strokesAdded = 0;
    _elementsModified = 0;
  }
}
