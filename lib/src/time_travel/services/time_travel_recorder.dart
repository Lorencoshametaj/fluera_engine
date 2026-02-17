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
/// A differenza del `CanvasDeltaTracker` (WAL transiente consumato dal
/// salvataggio locale e from the RTDB sync), il recorder **non perde mai
/// gli eventi** — li accumula per tutta la durata della sessione e li
/// scrive to disk al termine (canvas close).
///
/// **Performance impact during drawing: ~0ms**
/// - `recordEvent()` fa un singolo `List.add()` → O(1) amortized
/// - Nessuna serializzazione, nessun I/O, nessuna compressione
/// - Costo memoria: ~200 byte/evento × 500 stroke = ~100 KB per sessione
class TimeTravelRecorder {
  /// Buffer di eventi della sessione corrente (mai consumato)
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

  /// Numero totale di eventi registrati nella sessione
  int get eventCount => _sessionEvents.length;

  /// Indica if the recorder is active
  bool get isRecording => _isRecording;

  /// Lista immutabile degli eventi della sessione corrente
  List<TimeTravelEvent> get sessionEvents =>
      List<TimeTravelEvent>.unmodifiable(_sessionEvents);

  // ============================================================================
  // RECORDING CONTROL
  // ============================================================================

  /// 🟢 Avvia la registrazione (chiamato dopo check Pro subscription)
  void startRecording() {
    _isRecording = true;
    debugPrint(
      '🎬 [TimeTravelRecorder] Recording started at ${sessionStart.toIso8601String()}',
    );
  }

  /// 🔴 Ferma la registrazione (gli eventi restano in memoria)
  void stopRecording() {
    _isRecording = false;
    debugPrint(
      '🎬 [TimeTravelRecorder] Recording stopped. Events: ${_sessionEvents.length}',
    );
  }

  // ============================================================================
  // EVENT RECORDING
  // ============================================================================

  /// 🎬 Registra un evento — chiamato dal LayerController dopo ogni modifica
  ///
  /// This metodo is intenzionalmente leggero: solo un `List.add()`.
  /// The [type] and parameters correspond to those of `CanvasDeltaTracker`,
  /// ma i dati vengono accumulati in un buffer separato e permanente.
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
            type == CanvasDeltaType.layerRemoved ||
            type == CanvasDeltaType.pageRemoved);

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

    // Log ogni 100 eventi per debug (non ad ogni evento)
    if (_sessionEvents.length % 100 == 0) {
      debugPrint(
        '🎬 [TimeTravelRecorder] ${_sessionEvents.length} events recorded',
      );
    }
  }

  // ============================================================================
  // FLUSH TO DISK
  // ============================================================================

  /// 💾 Scrive gli eventi della sessione to disk in formato JSONL compresso
  ///
  /// Called at the closing of the canvas. The heavy operation (serialization
  /// + GZIP) avviene in un isolate per non bloccare la UI.
  ///
  /// Returns la [TimeTravelSession] creata, o null if not ci sono eventi.
  Future<TimeTravelSession?> flushToDisk(
    String canvasId,
    String basePath,
  ) async {
    if (_sessionEvents.isEmpty) {
      debugPrint('🎬 [TimeTravelRecorder] No events to flush');
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

      debugPrint(
        '🎬 [TimeTravelRecorder] Flushed ${_sessionEvents.length} events '
        'to $fileName (${compressed.length} bytes compressed)',
      );

      return session;
    } catch (e) {
      debugPrint('🎬 [TimeTravelRecorder] Flush error: $e');
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
