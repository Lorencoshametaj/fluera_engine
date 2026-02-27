import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../../history/models/canvas_branch.dart';
import '../../core/models/canvas_layer.dart';
import '../models/time_travel_session.dart';
import '../../history/canvas_delta_tracker.dart';
import '../../history/undo_redo_manager.dart';
import '../../services/phase2_service_stubs.dart';
import './time_travel_compressor.dart';
import '../../history/branching_manager.dart';

/// ⏱️ Time Travel playback state
enum TimeTravelPlaybackState {
  idle, // Not in time travel mode
  loading, // History loading in progress
  paused, // Timeline ready, user can scrub
  playing, // Automatic playback in progress
}

/// 🎬 Time Travel Playback Engine
///
/// Replay engine that reconstructs the canvas state at any point
/// in time. Uses a **hybrid** navigation strategy to ensure
/// data integrity:
///
/// - **Forward**: applies events one by one (safe, incremental)
/// - **Backward ≤ [_inverseThreshold] events**: apply inverse deltas
/// - **Backward > [_inverseThreshold] events**: snapshot reload + forward replay
///
/// The threshold is conservative: inverse deltas work well for few steps
/// (like user undo), but accumulate risk on long sequences because
/// `layerModified`, `textUpdated` e `imageUpdated` do not save the state
/// previous state in the delta.
class TimeTravelPlaybackEngine {
  /// Maximum backward step threshold with inverse delta
  static const int _inverseThreshold = 5;

  /// Storage service for loading sessions and snapshots
  final FlueraTimeTravelStorage _storage;

  // ============================================================================
  // STATE
  // ============================================================================

  /// Current playback state
  TimeTravelPlaybackState _state = TimeTravelPlaybackState.idle;
  TimeTravelPlaybackState get state => _state;

  /// Current canvas ID
  String? _canvasId;

  /// Loaded sessions (chronologically ordered)
  List<TimeTravelSession> _sessions = [];
  List<TimeTravelSession> get sessions => List.unmodifiable(_sessions);

  /// All events flattened in chronological order
  /// Lazy loaded per session: initially empty, populated on-demand
  final List<TimeTravelEvent> _allEvents = [];
  int get totalEventCount => _allEvents.length;

  /// Event → session map: for each session, (startEventIndex, sessionRef)
  /// Used to trace back the absolute timestamp of any event
  final List<_SessionEventRange> _sessionEventRanges = [];

  /// Index of the current event (0 = empty canvas, length = final state)
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

  /// Canvas state reconstructed at current position
  List<CanvasLayer> _currentLayers = [];
  List<CanvasLayer> get currentLayers => List.unmodifiable(_currentLayers);

  /// Playback speed (multiple: 0.5x, 1x, 2x, 4x, 8x)
  double _playbackSpeed = 1.0;
  double get playbackSpeed => _playbackSpeed;
  set playbackSpeed(double value) {
    _playbackSpeed = value.clamp(0.5, 8.0);
  }

  // ============================================================================
  // PLAYBACK MODES
  // ============================================================================

  /// 🎯 Stroke-by-stroke mode: one event at a time at fixed intervals
  /// If false, uses compressed timeline (max gaps clamped)
  bool _strokeByStroke = false;
  bool get strokeByStroke => _strokeByStroke;
  set strokeByStroke(bool value) {
    _strokeByStroke = value;
  }

  /// Fixed interval between events in stroke-by-stroke mode (ms)
  static const int _strokeInterval = 150;

  /// Compressed timeline: normalized timestamps with clamped gaps
  final List<int> _compressedTimestamps = [];

  /// Total history duration (ms) — uses compressed timeline
  int get totalDurationMs {
    if (_compressedTimestamps.isEmpty) return 0;
    return _compressedTimestamps.last;
  }

  /// Current time in timeline (ms)
  int get currentTimeMs {
    if (_currentEventIndex <= 0 || _compressedTimestamps.isEmpty) return 0;
    if (_currentEventIndex >= _compressedTimestamps.length) {
      return _compressedTimestamps.last;
    }
    return _compressedTimestamps[_currentEventIndex - 1];
  }

  /// 📅 Absolute timestamp of the current event
  ///
  /// Reconstructs real date (day, month, hour) combining
  /// session startTime + event relative offset.
  DateTime? get currentAbsoluteTime {
    return getAbsoluteTimeForIndex(_currentEventIndex);
  }

  /// 📅 Absolute timestamp for any index
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

    // cumulative timestampMs - session cumulative offset = relative ms in session
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

  /// Progress as fraction 0.0 - 1.0
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

  TimeTravelPlaybackEngine({required FlueraTimeTravelStorage storage})
    : _storage = storage;

  // ============================================================================
  // LIFECYCLE
  // ============================================================================

  /// 🎬 Initialize engine for a specific canvas
  ///
  /// Loads session index and all events. This might
  /// take a few hundred ms for canvas with lots of history.
  Future<bool> initialize(
    String canvasId,
    TickerProvider vsync, {
    String? branchId,
  }) async {
    _canvasId = canvasId;
    _setState(TimeTravelPlaybackState.loading);

    try {
      // 1. Load session index
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

        // Register session → event range
        _sessionEventRanges.add(
          _SessionEventRange(
            session: session,
            startIndex: _allEvents.length,
            cumulativeOffsetMs: cumulativeOffsetMs,
          ),
        );

        // Offset session-relative timestamps to make them global
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

      // ⚠️ If sessions exist but no event was loaded,
      // probably files are corrupt or in wrong path
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

      // 5. Create playback ticker
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

  /// 🗑️ Release resources
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

  /// ▶️ Start automatic playback from the current position
  void play() {
    if (_state != TimeTravelPlaybackState.paused) return;
    if (_currentEventIndex >= _allEvents.length) {
      // If at the end, restart from the beginning
      seekToIndex(0);
    }

    _lastTickTimeMs = 0;
    _accumulatedMs = 0;
    _ticker?.start();
    _setState(TimeTravelPlaybackState.playing);
  }

  /// ⏸️ Pause playback
  void pause() {
    if (_state != TimeTravelPlaybackState.playing) return;
    _ticker?.stop();
    _setState(TimeTravelPlaybackState.paused);
  }

  /// ⏭️ Skip to next session
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

  /// ⏮️ Skip to previous session
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

    // If at the end, go to start of last session
    seekToIndex(previousSessionStart);
  }

  // ============================================================================
  // SCRUBBING (NAVIGAZIONE TIMELINE)
  // ============================================================================

  /// 🎯 Navigate to a specific index in the timeline
  ///
  /// Implements hybrid strategy:
  /// - Forward: apply events incrementally
  /// - Backward ≤ 5 step: inverse delta
  /// - Backward > 5 step: snapshot reload + forward replay
  Future<void> seekToIndex(int targetIndex) async {
    final clampedTarget = targetIndex.clamp(0, _allEvents.length);
    if (clampedTarget == _currentEventIndex) return;

    final delta = clampedTarget - _currentEventIndex;

    if (delta > 0) {
      // ➡️ FORWARD: apply events one by one (always safe)
      _applyEventsForward(_currentEventIndex, clampedTarget);
    } else if (delta.abs() <= _inverseThreshold) {
      // ⬅️ SMALL BACKWARD: inverse delta (safe for few steps)
      _applyEventsBackward(_currentEventIndex, clampedTarget);
    } else {
      // ⬅️⬅️ LARGE BACKWARD: snapshot reload + forward replay
      await _reconstructStateAtIndex(clampedTarget);
    }

    _currentEventIndex = clampedTarget;
    onStateChanged?.call();
  }

  /// 🎯 Navigate to a percentage position (0.0 - 1.0)
  Future<void> seekToProgress(double progress) async {
    final targetIndex = (progress * _allEvents.length).round();
    await seekToIndex(targetIndex);
  }

  // ============================================================================
  // FORWARD REPLAY
  // ============================================================================

  /// ➡️ Apply events forward (incremental, safe)
  void _applyEventsForward(int fromIndex, int toIndex) {
    for (int i = fromIndex; i < toIndex; i++) {
      _applyEventForward(_allEvents[i]);
    }
  }

  /// Apply a single event forwards
  void _applyEventForward(TimeTravelEvent event) {
    // Convert TimeTravelEvent → CanvasDelta to reuse applyDeltas
    final delta = _eventToDelta(event);
    _currentLayers = CanvasDeltaTracker.applyDeltas(_currentLayers, [delta]);
  }

  // ============================================================================
  // BACKWARD REPLAY (solo per piccoli step)
  // ============================================================================

  /// ⬅️ Apply inverse delta to go back
  void _applyEventsBackward(int fromIndex, int toIndex) {
    // Apply inverse delta from most recent to least recent
    for (int i = fromIndex - 1; i >= toIndex; i--) {
      _applyEventBackward(_allEvents[i]);
    }
  }

  /// Apply inverse of a single event
  void _applyEventBackward(TimeTravelEvent event) {
    final delta = _eventToDelta(event);
    _currentLayers = UndoRedoManager.applyInverseDelta(_currentLayers, delta);
  }

  // ============================================================================
  // STATE RECONSTRUCTION (per salti grandi)
  // ============================================================================

  /// 🔄 Rebuild state from a snapshot + forward replay
  ///
  /// Strategy:
  /// 1. Find the nearest snapshot ≤ targetIndex
  /// 2. Load the snapshot (layers)
  /// 3. Apply events from snapshot to targetIndex forwards
  Future<void> _reconstructStateAtIndex(int targetIndex) async {
    if (_canvasId == null) return;

    // Find which session targetIndex belongs to
    int sessionIndex = 0;
    int eventsSoFar = 0;
    for (int i = 0; i < _sessions.length; i++) {
      eventsSoFar += _sessions[i].deltaCount;
      if (eventsSoFar >= targetIndex) {
        sessionIndex = i;
        break;
      }
    }

    // Search nearest snapshot
    List<CanvasLayer> baseLayers = [];
    int startIndex = 0;

    final snapshot = await _storage.loadNearestSnapshot(
      _canvasId!,
      sessionIndex,
    );

    if (snapshot != null) {
      baseLayers = snapshot.$1;
      // Calculate index of first event after snapshot
      int eventsBeforeSnapshot = 0;
      for (int i = 0; i < snapshot.$2 && i < _sessions.length; i++) {
        eventsBeforeSnapshot += _sessions[i].deltaCount;
      }
      startIndex = eventsBeforeSnapshot;
    }

    // Forward replay from snapshot to target
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

  /// Ticker callback — advances in time based on speed
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
      // 🎯 Stroke-by-stroke mode: one event at a time at fixed intervals
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

    // If we reached the end, pause
    if (_currentEventIndex >= _allEvents.length) {
      pause();
    }
  }

  // ============================================================================
  // COMPRESSED TIMELINE
  // ============================================================================

  /// 🕐 Builds compressed timeline: groups temporally close events
  ///
  /// "Block" mode: events with gap < [_blockGapThreshold] ms
  /// receive the SAME compressed timestamp → appear together.
  /// Between distinct blocks, fixed interval of [_blockInterval] ms.
  ///
  /// Stroke-by-stroke mode bypasses this timeline completely.
  static const int _blockGapThreshold = 1000; // ms — max gap within a block
  static const int _blockInterval = 200; // ms — pausa tra blocchi

  void _buildCompressedTimeline() {
    _compressedTimestamps.clear();
    if (_allEvents.isEmpty) return;

    int compressedTime = 0;
    int prevRawTs = _allEvents[0].timestampMs;
    int blockCount = 1;

    // First event: timestamp 0
    _compressedTimestamps.add(0);

    for (int i = 1; i < _allEvents.length; i++) {
      final rawTs = _allEvents[i].timestampMs;
      final gap = rawTs - prevRawTs;

      if (gap > _blockGapThreshold) {
        // New block → insert fixed interval
        compressedTime += _blockInterval;
        blockCount++;
      }
      // Same block → same timestamp (will appear all together)

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

  /// Convert TimeTravelEvent → CanvasDelta (to reuse applyDeltas/applyInverse)
  ///
  /// 📦 Automatically decompresses elementData if it was compressed
  /// by TimeTravelRecorder.
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

  /// 📊 Info for timeline heatmap (event density per segment)
  ///
  /// Divide timeline into [segments] segments and count events for each.
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

  /// 📊 Returns session markers as 0.0-1.0 positions
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

  /// 📅 Marker with date for heatmap — deduplicate per day
  ///
  /// Returns 0.0-1.0 positions with date of first session of that day.
  List<({double position, DateTime date})> getSessionDateMarkers() {
    if (_sessions.isEmpty || _allEvents.isEmpty) return [];

    final markers = <({double position, DateTime date})>[];
    int cumulativeEvents = 0;
    String? lastDayKey;

    for (final session in _sessions) {
      final dayKey =
          '${session.startTime.year}-${session.startTime.month}-${session.startTime.day}';

      if (dayKey != lastDayKey) {
        // New day — add marker
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

/// Range of events belonging to a session
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
