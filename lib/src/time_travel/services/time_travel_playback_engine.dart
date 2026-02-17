import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../../history/models/canvas_branch.dart';
import '../../core/models/canvas_layer.dart';
import '../models/time_travel_session.dart';
import '../../history/canvas_delta_tracker.dart';
import '../../history/undo_redo_manager.dart';
import '../../collaboration/nebula_sync_interfaces.dart';
import './time_travel_compressor.dart';
import '../../history/branching_manager.dart';

/// ⏱️ Stato di riproduzione Time Travel
enum TimeTravelPlaybackState {
  idle, // Do not in mode time travel
  loading, // Loadmento storia in corso
  paused, // Timeline pronta, utente can scrubbare
  playing, // Riproduzione automatica in corso
}

/// 🎬 Time Travel Playback Engine
///
/// Motore di replay che ricostruisce lo stato of the canvas a qualsiasi punto
/// nel tempo. Usa una strategia di navigazione **ibrida** per garantire
/// integrità dei dati:
///
/// - **Avanti**: applica eventi uno a uno (safe, incrementale)
/// - **Indietro ≤ [_inverseThreshold] eventi**: applica delta inversi
/// - **Indietro > [_inverseThreshold] eventi**: snapshot reload + forward replay
///
/// The threshold is conservative: the delta inversi funzionano bene per pochi step
/// (come l'undo utente), ma accumulano rischio su sequenze lunghe because
/// `layerModified`, `textUpdated` e `imageUpdated` non salvano lo stato
/// precedente nel delta.
class TimeTravelPlaybackEngine {
  /// Soglia massima di step indietro con inverse delta
  static const int _inverseThreshold = 5;

  /// Storage service for loading sessions and snapshots
  final NebulaTimeTravelStorage _storage;

  // ============================================================================
  // STATE
  // ============================================================================

  /// Stato attuale della riproduzione
  TimeTravelPlaybackState _state = TimeTravelPlaybackState.idle;
  TimeTravelPlaybackState get state => _state;

  /// Current canvas ID
  String? _canvasId;

  /// Sessioni caricate (ordinate cronologicamente)
  List<TimeTravelSession> _sessions = [];
  List<TimeTravelSession> get sessions => List.unmodifiable(_sessions);

  /// All gli eventi appiattiti in ordine cronologico
  /// Loadti lazy per sessione: inizialmente vuoto, popolato on-demand
  final List<TimeTravelEvent> _allEvents = [];
  int get totalEventCount => _allEvents.length;

  /// Mappa evento → sessione: per ogni sessione, (startEventIndex, sessionRef)
  /// Usato per risalire al timestamp assoluto di qualsiasi evento
  final List<_SessionEventRange> _sessionEventRanges = [];

  /// Indice of the current event (0 = canvas vuoto, length = final state)
  int _currentEventIndex = 0;
  int get currentEventIndex => _currentEventIndex;

  // ============================================================================
  // BRANCH-AWARE COLOR OVERLAY
  // ============================================================================

  /// 🌿 Index where parent events end and branch events begin
  /// null when viewing main timeline (no branch context)
  int? _forkPointEventIndex;
  int? get forkPointEventIndex => _forkPointEventIndex;

  /// 🌿 Whether an event at [index] belongs to the parent (before fork)
  bool isParentEvent(int index) =>
      _forkPointEventIndex != null && index < _forkPointEventIndex!;

  /// 🌿 Active branch context (null = main timeline)
  CanvasBranch? _activeBranch;
  CanvasBranch? get activeBranch => _activeBranch;

  /// Stato canvas ricostruito alla current position
  List<CanvasLayer> _currentLayers = [];
  List<CanvasLayer> get currentLayers => List.unmodifiable(_currentLayers);

  /// Speed di playback (multiplo: 0.5x, 1x, 2x, 4x, 8x)
  double _playbackSpeed = 1.0;
  double get playbackSpeed => _playbackSpeed;
  set playbackSpeed(double value) {
    _playbackSpeed = value.clamp(0.5, 8.0);
  }

  // ============================================================================
  // PLAYBACK MODES
  // ============================================================================

  /// 🎯 Modalità stroke-by-stroke: un evento at a time a intervalli fissi
  /// If false, usa la timeline compressa (gap max clampati)
  bool _strokeByStroke = false;
  bool get strokeByStroke => _strokeByStroke;
  set strokeByStroke(bool value) {
    _strokeByStroke = value;
  }

  /// Intervallo fisso tra eventi in mode stroke-by-stroke (ms)
  static const int _strokeInterval = 150;

  /// Timeline compressa: timestamps normalizzati con gap clampati
  final List<int> _compressedTimestamps = [];

  /// Durata totale della storia (ms) — usa timeline compressa
  int get totalDurationMs {
    if (_compressedTimestamps.isEmpty) return 0;
    return _compressedTimestamps.last;
  }

  /// Tempo corrente nella timeline (ms)
  int get currentTimeMs {
    if (_currentEventIndex <= 0 || _compressedTimestamps.isEmpty) return 0;
    if (_currentEventIndex >= _compressedTimestamps.length) {
      return _compressedTimestamps.last;
    }
    return _compressedTimestamps[_currentEventIndex - 1];
  }

  /// 📅 Timestamp assoluto of the current event
  ///
  /// Ricostruisce la data reale (giorno, mese, ora) combinando
  /// il startTime della sessione + offset relativo dell'evento.
  DateTime? get currentAbsoluteTime {
    return getAbsoluteTimeForIndex(_currentEventIndex);
  }

  /// 📅 Timestamp assoluto for a indice qualsiasi
  DateTime? getAbsoluteTimeForIndex(int eventIndex) {
    if (_allEvents.isEmpty || _sessionEventRanges.isEmpty) return null;
    if (eventIndex <= 0) {
      return _sessionEventRanges.first.session.startTime;
    }
    final clampedIndex = eventIndex.clamp(1, _allEvents.length) - 1;
    final event = _allEvents[clampedIndex];

    // Find the session this event belongs to
    _SessionEventRange? ownerRange;
    for (int i = _sessionEventRanges.length - 1; i >= 0; i--) {
      if (clampedIndex >= _sessionEventRanges[i].startIndex) {
        ownerRange = _sessionEventRanges[i];
        break;
      }
    }
    if (ownerRange == null) return null;

    // cumulative timestampMs - offset cumulativo della sessione = ms relativo nella sessione
    final relativeMs = event.timestampMs - ownerRange.cumulativeOffsetMs;
    return ownerRange.session.startTime.add(
      Duration(
        milliseconds: relativeMs.clamp(
          0,
          ownerRange.session.duration.inMilliseconds,
        ),
      ),
    );
  }

  /// Progresso come frazione 0.0 - 1.0
  double get progress {
    if (_allEvents.isEmpty) return 0.0;
    return _currentEventIndex / _allEvents.length;
  }

  // ============================================================================
  // CALLBACKS (per UI update)
  // ============================================================================

  /// Callback when the canvas state changes during replay
  VoidCallback? onStateChanged;

  /// Callback when the playback state changes
  ValueChanged<TimeTravelPlaybackState>? onPlaybackStateChanged;

  // ============================================================================
  // PLAYBACK TICKER
  // ============================================================================

  Ticker? _ticker;
  int _lastTickTimeMs = 0;
  int _accumulatedMs = 0;

  // ============================================================================
  // CONSTRUCTOR
  // ============================================================================

  TimeTravelPlaybackEngine({required NebulaTimeTravelStorage storage})
    : _storage = storage;

  // ============================================================================
  // LIFECYCLE
  // ============================================================================

  /// 🎬 Initialize il motore for a canvas specifico
  ///
  /// Loads l'indice delle sessioni e tutti gli eventi. Questo potrebbe
  /// richiedere qualche centinaio di ms per canvas con molta storia.
  Future<bool> initialize(
    String canvasId,
    TickerProvider vsync, {
    String? branchId,
  }) async {
    _canvasId = canvasId;
    _setState(TimeTravelPlaybackState.loading);

    try {
      // 1. Load indice sessioni
      _sessions = await _storage.loadSessionIndex(canvasId, branchId: branchId);

      debugPrint(
        '🎬 [PlaybackEngine] Sessions found: ${_sessions.length} for $canvasId',
      );

      if (_sessions.isEmpty) {
        debugPrint('🎬 [PlaybackEngine] No sessions found for $canvasId');
        _setState(TimeTravelPlaybackState.idle);
        return false;
      }

      // 2. Load all events from all sessions
      _allEvents.clear();
      _sessionEventRanges.clear();
      int cumulativeOffsetMs = 0;

      for (final session in _sessions) {
        final events = await _storage.loadSessionEvents(
          session,
          branchId: branchId,
        );

        debugPrint(
          '🎬 [PlaybackEngine] Session ${session.id}: '
          '${events.length} events loaded (file: ${session.deltaFilePath})',
        );

        // Registra range sessione → eventi
        _sessionEventRanges.add(
          _SessionEventRange(
            session: session,
            startIndex: _allEvents.length,
            cumulativeOffsetMs: cumulativeOffsetMs,
          ),
        );

        // Offset i timestamp relativi alla sessione per renderli globali
        for (final event in events) {
          _allEvents.add(
            TimeTravelEvent(
              type: event.type,
              layerId: event.layerId,
              pageIndex: event.pageIndex,
              timestampMs: cumulativeOffsetMs + event.timestampMs,
              elementData: event.elementData,
              elementId: event.elementId,
            ),
          );
        }

        cumulativeOffsetMs += session.duration.inMilliseconds;
      }

      // ⚠️ Se le sessioni esistono ma nessun evento was caricato,
      // probabilmente i file sono corrotti o nel path sbagliato
      if (_allEvents.isEmpty) {
        debugPrint(
          '🎬 [PlaybackEngine] ⚠️ ${_sessions.length} sessions in index '
          'but 0 events loaded — files may be missing or corrupted',
        );
        _setState(TimeTravelPlaybackState.idle);
        return false;
      }

      // 🕐 Costruisci timeline compressa (clamp gap massimo)
      _buildCompressedTimeline();

      // 3. Position at the end (complete state)
      _currentEventIndex = _allEvents.length;
      _currentLayers = [];

      // 4. Rebuild final state
      await _reconstructStateAtIndex(_allEvents.length);

      // 5. Crea ticker per playback
      _ticker?.dispose();
      _ticker = vsync.createTicker(_onTick);

      debugPrint(
        '🎬 [PlaybackEngine] Initialized: ${_sessions.length} sessions, '
        '${_allEvents.length} events, ${totalDurationMs}ms total',
      );

      _setState(TimeTravelPlaybackState.paused);
      return true;
    } catch (e) {
      debugPrint('🎬 [PlaybackEngine] Initialize error: $e');
      _setState(TimeTravelPlaybackState.idle);
      return false;
    }
  }

  /// 🌿 Initialize for a specific branch
  ///
  /// Loads parent events up to [branch.forkPointEventIndex], then appends
  /// the branch's own sessions. The [forkPointEventIndex] is set so the
  /// color overlay knows where parent ends and branch begins.
  Future<bool> initializeForBranch(
    String canvasId,
    CanvasBranch branch,
    BranchingManager branchingManager,
    TickerProvider vsync,
  ) async {
    _canvasId = canvasId;
    _activeBranch = branch;
    _setState(TimeTravelPlaybackState.loading);

    try {
      // 1. Load ALL parent sessions (main timeline)
      final parentSessions = await _storage.loadSessionIndex(canvasId);

      debugPrint(
        '🌿 [PlaybackEngine] Loading branch "${branch.name}" — '
        '${parentSessions.length} parent sessions, '
        'fork at event index ${branch.forkPointEventIndex}',
      );

      // 2. Load parent events and take only up to forkPointEventIndex
      _allEvents.clear();
      _sessionEventRanges.clear();
      _sessions = [];
      int cumulativeOffsetMs = 0;
      int parentEventsLoaded = 0;

      for (final session in parentSessions) {
        if (parentEventsLoaded >= branch.forkPointEventIndex) break;

        final events = await _storage.loadSessionEvents(session);
        _sessions.add(session);

        _sessionEventRanges.add(
          _SessionEventRange(
            session: session,
            startIndex: _allEvents.length,
            cumulativeOffsetMs: cumulativeOffsetMs,
          ),
        );

        for (final event in events) {
          if (parentEventsLoaded >= branch.forkPointEventIndex) break;

          _allEvents.add(
            TimeTravelEvent(
              type: event.type,
              layerId: event.layerId,
              pageIndex: event.pageIndex,
              timestampMs: cumulativeOffsetMs + event.timestampMs,
              elementData: event.elementData,
              elementId: event.elementId,
            ),
          );
          parentEventsLoaded++;
        }

        cumulativeOffsetMs += session.duration.inMilliseconds;
      }

      // 🌿 Mark the fork point
      _forkPointEventIndex = _allEvents.length;

      debugPrint(
        '🌿 [PlaybackEngine] Parent events loaded: $_forkPointEventIndex',
      );

      // 3. Load branch sessions and append
      final branchSessions = await branchingManager.loadBranchSessions(
        canvasId,
        branch.id,
      );

      for (final session in branchSessions) {
        final events = await _storage.loadSessionEvents(session);
        _sessions.add(session);

        _sessionEventRanges.add(
          _SessionEventRange(
            session: session,
            startIndex: _allEvents.length,
            cumulativeOffsetMs: cumulativeOffsetMs,
          ),
        );

        for (final event in events) {
          _allEvents.add(
            TimeTravelEvent(
              type: event.type,
              layerId: event.layerId,
              pageIndex: event.pageIndex,
              timestampMs: cumulativeOffsetMs + event.timestampMs,
              elementData: event.elementData,
              elementId: event.elementId,
            ),
          );
        }

        cumulativeOffsetMs += session.duration.inMilliseconds;
      }

      if (_allEvents.isEmpty) {
        debugPrint('🌿 [PlaybackEngine] No events for branch');
        _setState(TimeTravelPlaybackState.idle);
        return false;
      }

      // Build compressed timeline
      _buildCompressedTimeline();

      // Position at end (full state)
      _currentEventIndex = _allEvents.length;
      _currentLayers = [];
      await _reconstructStateAtIndex(_allEvents.length);

      // Create ticker
      _ticker?.dispose();
      _ticker = vsync.createTicker(_onTick);

      debugPrint(
        '🌿 [PlaybackEngine] Branch initialized: '
        '${_allEvents.length} total events '
        '(${_forkPointEventIndex} parent + '
        '${_allEvents.length - _forkPointEventIndex!} branch)',
      );

      _setState(TimeTravelPlaybackState.paused);
      return true;
    } catch (e) {
      debugPrint('🌿 [PlaybackEngine] Branch init error: $e');
      _setState(TimeTravelPlaybackState.idle);
      return false;
    }
  }

  /// 🗑️ Rilascia risorse
  void dispose() {
    _ticker?.stop();
    _ticker?.dispose();
    _ticker = null;
    _allEvents.clear();
    _sessions.clear();
    _currentLayers.clear();
    _setState(TimeTravelPlaybackState.idle);
  }

  // ============================================================================
  // PLAYBACK CONTROLS
  // ============================================================================

  /// ▶️ Avvia playback automatico from the current position
  void play() {
    if (_state != TimeTravelPlaybackState.paused) return;
    if (_currentEventIndex >= _allEvents.length) {
      // If at the end, riparti from the beginning
      seekToIndex(0);
    }

    _lastTickTimeMs = 0;
    _accumulatedMs = 0;
    _ticker?.start();
    _setState(TimeTravelPlaybackState.playing);
  }

  /// ⏸️ Pausa playback
  void pause() {
    if (_state != TimeTravelPlaybackState.playing) return;
    _ticker?.stop();
    _setState(TimeTravelPlaybackState.paused);
  }

  /// ⏭️ Salta alla next session
  void skipToNextSession() {
    if (_sessions.isEmpty || _allEvents.isEmpty) return;

    // Find the start of the next session
    int cumulativeEvents = 0;
    for (final session in _sessions) {
      cumulativeEvents += session.deltaCount;
      if (cumulativeEvents > _currentEventIndex) {
        seekToIndex(cumulativeEvents);
        return;
      }
    }
  }

  /// ⏮️ Salta alla sessione precedente
  void skipToPreviousSession() {
    if (_sessions.isEmpty || _allEvents.isEmpty) return;

    int cumulativeEvents = 0;
    int previousSessionStart = 0;
    for (final session in _sessions) {
      if (cumulativeEvents >= _currentEventIndex) {
        seekToIndex(previousSessionStart);
        return;
      }
      previousSessionStart = cumulativeEvents;
      cumulativeEvents += session.deltaCount;
    }

    // If at the end, vai all'inizio dell'ultima sessione
    seekToIndex(previousSessionStart);
  }

  // ============================================================================
  // SCRUBBING (NAVIGAZIONE TIMELINE)
  // ============================================================================

  /// 🎯 Naviga a un indice specifico nella timeline
  ///
  /// Implementa la strategia ibrida:
  /// - Avanti: applica eventi incrementalmente
  /// - Indietro ≤ 5 step: inverse delta
  /// - Indietro > 5 step: snapshot reload + forward replay
  Future<void> seekToIndex(int targetIndex) async {
    final clampedTarget = targetIndex.clamp(0, _allEvents.length);
    if (clampedTarget == _currentEventIndex) return;

    final delta = clampedTarget - _currentEventIndex;

    if (delta > 0) {
      // ➡️ AVANTI: applica eventi uno a uno (sempre sicuro)
      _applyEventsForward(_currentEventIndex, clampedTarget);
    } else if (delta.abs() <= _inverseThreshold) {
      // ⬅️ INDIETRO PICCOLO: inverse delta (sicuro per pochi step)
      _applyEventsBackward(_currentEventIndex, clampedTarget);
    } else {
      // ⬅️⬅️ INDIETRO GRANDE: snapshot reload + forward replay
      await _reconstructStateAtIndex(clampedTarget);
    }

    _currentEventIndex = clampedTarget;
    onStateChanged?.call();
  }

  /// 🎯 Naviga a una position percentuale (0.0 - 1.0)
  Future<void> seekToProgress(double progress) async {
    final targetIndex = (progress * _allEvents.length).round();
    await seekToIndex(targetIndex);
  }

  // ============================================================================
  // FORWARD REPLAY
  // ============================================================================

  /// ➡️ Applica eventi in avanti (incrementale, sicuro)
  void _applyEventsForward(int fromIndex, int toIndex) {
    for (int i = fromIndex; i < toIndex; i++) {
      _applyEventForward(_allEvents[i]);
    }
  }

  /// Applica un singolo evento in avanti
  void _applyEventForward(TimeTravelEvent event) {
    // Convert TimeTravelEvent → CanvasDelta per riusare applyDeltas
    final delta = _eventToDelta(event);
    _currentLayers = CanvasDeltaTracker.applyDeltas(_currentLayers, [delta]);
  }

  // ============================================================================
  // BACKWARD REPLAY (solo per piccoli step)
  // ============================================================================

  /// ⬅️ Applica inverse delta per tornare indietro
  void _applyEventsBackward(int fromIndex, int toIndex) {
    // Applica inverse delta dal more recente al meno recente
    for (int i = fromIndex - 1; i >= toIndex; i--) {
      _applyEventBackward(_allEvents[i]);
    }
  }

  /// Applica inverse di un singolo evento
  void _applyEventBackward(TimeTravelEvent event) {
    final delta = _eventToDelta(event);
    _currentLayers = UndoRedoManager.applyInverseDelta(_currentLayers, delta);
  }

  // ============================================================================
  // STATE RECONSTRUCTION (per salti grandi)
  // ============================================================================

  /// 🔄 Rebuild lo stato da uno snapshot + forward replay
  ///
  /// Strategia:
  /// 1. Find lo snapshot more vicino ≤ targetIndex
  /// 2. Load lo snapshot (layers)
  /// 3. Applica gli eventi da snapshot a targetIndex in avanti
  Future<void> _reconstructStateAtIndex(int targetIndex) async {
    if (_canvasId == null) return;

    // Find a quale sessione appartiene il targetIndex
    int sessionIndex = 0;
    int eventsSoFar = 0;
    for (int i = 0; i < _sessions.length; i++) {
      eventsSoFar += _sessions[i].deltaCount;
      if (eventsSoFar >= targetIndex) {
        sessionIndex = i;
        break;
      }
    }

    // Search lo snapshot more vicino
    List<CanvasLayer> baseLayers = [];
    int startIndex = 0;

    final snapshot = await _storage.loadNearestSnapshot(
      _canvasId!,
      sessionIndex,
    );

    if (snapshot != null) {
      baseLayers = snapshot.$1;
      // Calculate l'indice del primo evento dopo lo snapshot
      int eventsBeforeSnapshot = 0;
      for (int i = 0; i < snapshot.$2 && i < _sessions.length; i++) {
        eventsBeforeSnapshot += _sessions[i].deltaCount;
      }
      startIndex = eventsBeforeSnapshot;
    }

    // Forward replay da snapshot a target
    _currentLayers = baseLayers;
    final endIndex = targetIndex.clamp(0, _allEvents.length);
    _applyEventsForward(startIndex, endIndex);

    debugPrint(
      '🎬 [PlaybackEngine] Reconstructed state at index $targetIndex '
      '(from snapshot at $startIndex, applied ${endIndex - startIndex} events)',
    );
  }

  // ============================================================================
  // TICKER (playback automatico)
  // ============================================================================

  /// Callback del Ticker — avanza nel tempo basandosi sulla speed
  void _onTick(Duration elapsed) {
    if (_state != TimeTravelPlaybackState.playing) return;
    if (_currentEventIndex >= _allEvents.length) {
      pause();
      return;
    }

    final currentMs = elapsed.inMilliseconds;
    if (_lastTickTimeMs == 0) {
      _lastTickTimeMs = currentMs;
      return;
    }

    final deltaMs = ((currentMs - _lastTickTimeMs) * _playbackSpeed).round();
    _lastTickTimeMs = currentMs;
    _accumulatedMs += deltaMs;

    bool changed = false;

    if (_strokeByStroke) {
      // 🎯 Modalità stroke-by-stroke: un evento at a time a intervalli fissi
      if (_accumulatedMs >= _strokeInterval) {
        if (_currentEventIndex < _allEvents.length) {
          _applyEventForward(_allEvents[_currentEventIndex]);
          _currentEventIndex++;
          changed = true;
        }
        _accumulatedMs = 0;
      }
    } else {
      // 🕐 Modalità timeline compressa: usa timestamps normalizzati
      final baseTimeMs =
          _currentEventIndex > 0
              ? _compressedTimestamps[_currentEventIndex - 1]
              : 0;
      while (_currentEventIndex < _allEvents.length) {
        final nextCompressedTs = _compressedTimestamps[_currentEventIndex];
        if (nextCompressedTs <= baseTimeMs + _accumulatedMs) {
          _applyEventForward(_allEvents[_currentEventIndex]);
          _currentEventIndex++;
          changed = true;
        } else {
          break;
        }
      }
      if (changed) _accumulatedMs = 0;
    }

    if (changed) {
      onStateChanged?.call();
    }

    // If abbiamo raggiunto la fine, pausa
    if (_currentEventIndex >= _allEvents.length) {
      pause();
    }
  }

  // ============================================================================
  // COMPRESSED TIMELINE
  // ============================================================================

  /// 🕐 Builds la timeline compressa: raggruppa eventi temporalmente vicini
  ///
  /// Modalità "blocchi": eventi con gap < [_blockGapThreshold] ms
  /// ricevono lo STESSO timestamp compresso → appaiono insieme.
  /// Tra blocchi distinti, intervallo fisso di [_blockInterval] ms.
  ///
  /// Modalità stroke-by-stroke bypass questa timeline completamente.
  static const int _blockGapThreshold = 1000; // ms — gap max dentro un blocco
  static const int _blockInterval = 200; // ms — pausa tra blocchi

  void _buildCompressedTimeline() {
    _compressedTimestamps.clear();
    if (_allEvents.isEmpty) return;

    int compressedTime = 0;
    int prevRawTs = _allEvents[0].timestampMs;
    int blockCount = 1;

    // Primo evento: timestamp 0
    _compressedTimestamps.add(0);

    for (int i = 1; i < _allEvents.length; i++) {
      final rawTs = _allEvents[i].timestampMs;
      final gap = rawTs - prevRawTs;

      if (gap > _blockGapThreshold) {
        // Nuovo blocco → inserisci intervallo fisso
        compressedTime += _blockInterval;
        blockCount++;
      }
      // Stesso blocco → stesso timestamp (appariranno tutti insieme)

      _compressedTimestamps.add(compressedTime);
      prevRawTs = rawTs;
    }

    debugPrint(
      '🎬 [PlaybackEngine] Compressed timeline: '
      '${_allEvents.length} events → $blockCount blocks, '
      'total ${compressedTime}ms '
      '(raw: ${_allEvents.last.timestampMs}ms)',
    );
  }

  // ============================================================================
  // HELPERS
  // ============================================================================

  /// Convert TimeTravelEvent → CanvasDelta (per riusare applyDeltas/applyInverse)
  ///
  /// 📦 Decomprime automaticamente elementData se era stato compresso
  /// dal TimeTravelRecorder.
  CanvasDelta _eventToDelta(TimeTravelEvent event) {
    return CanvasDelta(
      id: 'tt_${event.timestampMs}',
      type: event.type,
      layerId: event.layerId,
      pageIndex: event.pageIndex,
      timestamp: DateTime.fromMillisecondsSinceEpoch(event.timestampMs),
      elementData: TimeTravelCompressor.decompressElementData(
        event.type.name,
        event.elementData,
      ),
      elementId: event.elementId,
    );
  }

  /// Updates state and notifies listeners
  void _setState(TimeTravelPlaybackState newState) {
    if (_state == newState) return;
    _state = newState;
    onPlaybackStateChanged?.call(newState);
  }

  /// 📊 Info for the heatmap della timeline (density eventi per segmento)
  ///
  /// Divide la timeline in [segments] segmenti e conta gli eventi per ciascuno.
  List<int> getEventDensity({int segments = 100}) {
    if (_allEvents.isEmpty) return List.filled(segments, 0);

    final density = List.filled(segments, 0);
    final eventsPerSegment = _allEvents.length / segments;

    for (int i = 0; i < _allEvents.length; i++) {
      final segment = (i / eventsPerSegment).floor().clamp(0, segments - 1);
      density[segment]++;
    }
    return density;
  }

  /// 📊 Returns i marker delle sessioni come posizioni 0.0-1.0
  List<double> getSessionMarkers() {
    if (_sessions.isEmpty || _allEvents.isEmpty) return [];

    final markers = <double>[];
    int cumulativeEvents = 0;
    for (final session in _sessions) {
      cumulativeEvents += session.deltaCount;
      markers.add(cumulativeEvents / _allEvents.length);
    }
    return markers;
  }

  /// 📅 Marker con data for the heatmap — deduplicate per giorno
  ///
  /// Returns posizioni 0.0-1.0 with the data della prima sessione di quel giorno.
  List<({double position, DateTime date})> getSessionDateMarkers() {
    if (_sessions.isEmpty || _allEvents.isEmpty) return [];

    final markers = <({double position, DateTime date})>[];
    int cumulativeEvents = 0;
    String? lastDayKey;

    for (final session in _sessions) {
      final dayKey =
          '${session.startTime.year}-${session.startTime.month}-${session.startTime.day}';

      if (dayKey != lastDayKey) {
        // Nuovo giorno — aggiungi marker
        markers.add((
          position: cumulativeEvents / _allEvents.length,
          date: session.startTime,
        ));
        lastDayKey = dayKey;
      }

      cumulativeEvents += session.deltaCount;
    }

    return markers;
  }
}

/// Range di eventi appartenenti a una sessione
class _SessionEventRange {
  final TimeTravelSession session;
  final int startIndex;
  final int cumulativeOffsetMs;

  const _SessionEventRange({
    required this.session,
    required this.startIndex,
    required this.cumulativeOffsetMs,
  });
}
