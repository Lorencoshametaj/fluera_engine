import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../audio/native_audio_player.dart';
import '../../audio/native_audio_models.dart';
import '../../core/engine_logger.dart';
import '../../drawing/models/pro_drawing_point.dart';
import '../models/synchronized_recording.dart';

/// 🎵 Synchronized playback state
enum SyncedPlaybackState {
  idle, // Do not caricato
  loading, // In caricamento
  ready, // Pronto, in pausa
  playing, // In riproduzione
  paused, // In pausa
  completed, // Completeto
  error, // Errore
}

/// 🎵 SYNCHRONIZED PLAYBACK CONTROLLER
///
/// Controller that manages synchronized playback of audio and strokes.
/// While the audio plays, strokes are progressively "drawn"
/// following the original recording timing.
class SynchronizedPlaybackController extends ChangeNotifier {
  final NativeAudioPlayer _audioPlayer = NativeAudioPlayer();

  // 🐛 DEBUG: unique ID to track multiple instances
  static int _instanceCounter = 0;
  final int _instanceId;

  // Stato interno
  SynchronizedRecording? _recording;
  SyncedPlaybackState _state = SyncedPlaybackState.idle;
  Duration _duration = Duration.zero;
  double _ghostOpacity = 0.15; // Ghost stroke opacity (not yet drawn)
  bool _showGhostStrokes = true; // Show ghost strokes semi-trasparenti
  int _currentPageIndex = 0; // 📄 Current page to filter strokes
  double _speed = 1.0; // 🏎️ Playback speed (0.5x - 2.0x)

  // 🕐 Stopwatch for precise time tracking (fallback if stream doesn't work)
  final Stopwatch _stopwatch = Stopwatch();
  Duration _pausedPosition = Duration.zero; // Position at the moment of pause
  int _lastNotifiedPositionMs = -1; // Cache to skip unchanged frames

  // Stream subscriptions
  StreamSubscription? _positionSubscription;
  StreamSubscription? _stateSubscription;
  StreamSubscription? _durationSubscription;

  // Callback for UI update
  Timer? _updateTimer;

  // ⚡ Stroke cache — computed once per positionMs change
  int _cachedPositionMs = -1;
  final Map<int, List<ProStroke>> _activeStrokeCache = {};
  final Map<int, List<ProStroke>> _ghostStrokeCache = {};
  int _completedStrokeCount = 0; // How many active strokes are fully visible

  /// Costruttore
  SynchronizedPlaybackController() : _instanceId = ++_instanceCounter {}

  // ============================================================================
  // GETTERS
  // ============================================================================

  /// Current playback state
  SyncedPlaybackState get state => _state;

  /// Current position in milliseconds - uses stopwatch for precision
  int get positionMs {
    if (_state == SyncedPlaybackState.playing) {
      // While playing, use stopwatch + start position (adjusted for speed)
      final currentMs =
          _pausedPosition.inMilliseconds +
          (_stopwatch.elapsedMilliseconds * _speed).toInt();
      // Limit to maximum duration
      return currentMs.clamp(0, _duration.inMilliseconds);
    }
    // When paused, use the saved position
    return _pausedPosition.inMilliseconds;
  }

  /// Position corrente
  Duration get position => Duration(milliseconds: positionMs);

  /// Durata totale
  Duration get duration => _duration;

  /// Progresso (0.0 - 1.0)
  double get progress =>
      _duration.inMilliseconds > 0
          ? (positionMs / _duration.inMilliseconds).clamp(0.0, 1.0)
          : 0.0;

  /// Current playback speed multiplier (0.5x–3.0x).
  double get playbackSpeed => _speed;

  /// Set playback speed multiplier.
  ///
  /// The stopwatch-based timing already accounts for [_speed] in [positionMs],
  /// so this just updates the multiplier. Audio player speed must be set
  /// separately by the caller.
  void setPlaybackSpeed(double speed) {
    final clamped = speed.clamp(0.5, 3.0);
    if (clamped == _speed) return;

    // Preserve current position before changing speed
    final currentPos = Duration(milliseconds: positionMs);
    _pausedPosition = currentPos;
    _stopwatch.reset();
    if (_state == SyncedPlaybackState.playing) {
      _stopwatch.start();
    }

    _speed = clamped;
    debugPrint('🏎️ [SyncPlayback] Speed set to ${_speed}x');
  }

  /// Registrazione caricata
  SynchronizedRecording? get recording => _recording;

  /// Opacity ghost strokes
  double get ghostOpacity => _ghostOpacity;

  /// Shows ghost strokes
  bool get showGhostStrokes => _showGhostStrokes;

  /// È in riproduzione
  bool get isPlaying => _state == SyncedPlaybackState.playing;

  /// È caricato
  bool get isLoaded => _recording != null && _state != SyncedPlaybackState.idle;

  /// 📄 Current page (to filter strokes)
  int get currentPageIndex => _currentPageIndex;

  /// 🏎️ Current playback speed
  double get speed => _speed;

  /// 📄 Set the current page
  void setCurrentPage(int pageIndex) {
    if (_currentPageIndex != pageIndex) {
      _currentPageIndex = pageIndex;
      notifyListeners();
    }
  }

  /// 📄 Page where active drawing is occurring
  /// Returns the page of the stroke being drawn right now,
  /// or null if there is no active stroke
  int? get activeDrawingPage {
    if (_recording == null) return null;
    final currentMs = positionMs;

    // Find the stroke being drawn right now
    // (started but not yet completed)
    for (final synced in _recording!.syncedStrokes) {
      if (synced.isStarted(currentMs) && !synced.isFullyVisible(currentMs)) {
        return synced.pageIndex;
      }
    }

    // If there is no stroke in progress, find the last started stroke
    int? lastActivePage;
    for (final synced in _recording!.syncedStrokes) {
      if (synced.isStarted(currentMs)) {
        lastActivePage = synced.pageIndex;
      }
    }
    return lastActivePage;
  }

  /// 📄 Check if playback is occurring on a different page
  bool get isPlayingOnDifferentPage {
    // 🐛 FIX: If it is a 'note' type recording, ignore page logic
    if (_recording?.recordingType == 'note') return false;

    final activePage = activeDrawingPage;
    return activePage != null && activePage != _currentPageIndex;
  }

  /// Total number of strokes
  int get totalStrokes => _recording?.strokeCount ?? 0;

  /// Number of visible strokes (completely or partially)
  int get visibleStrokesCount {
    if (_recording == null) return 0;
    int count = 0;
    for (final synced in _recording!.syncedStrokes) {
      if (synced.isStarted(positionMs)) count++;
    }
    return count;
  }

  // ============================================================================
  // STROKES DA RENDERIZZARE
  // ============================================================================

  /// Gets i active strokes (parziali o completi) da renderizzare
  /// These are the strokes being "drawn" or already complete
  /// 📄 Filtered for the current page
  /// Gets active strokes for a specific page
  /// Gets active strokes for a specific page — ⚡ CACHED
  List<ProStroke> getActiveStrokesForPage(int pageIndex) {
    if (_recording == null) return const [];
    _ensureStrokeCacheValid();
    return _activeStrokeCache[pageIndex] ?? const [];
  }

  /// Gets i active strokes (parziali o completi) da renderizzare
  /// These are the strokes being "drawn" or already complete
  /// 📄 Filtered for the current page (or specific page if helper is used)
  List<ProStroke> get activeStrokes =>
      getActiveStrokesForPage(_currentPageIndex);

  /// Gets ghost strokes (not yet started) with reduced opacity
  /// They show a "preview" of what will be drawn
  /// 📄 Filtered for the current page
  /// Gets ghost strokes for a specific page
  /// Gets ghost strokes for a specific page — ⚡ CACHED
  List<ProStroke> getGhostStrokesForPage(int pageIndex) {
    if (_recording == null || !_showGhostStrokes) return const [];
    _ensureStrokeCacheValid();
    return _ghostStrokeCache[pageIndex] ?? const [];
  }

  /// ⚡ Number of fully-completed active strokes (for Picture caching in painter)
  int get completedStrokeCount => _completedStrokeCount;

  /// ⚡ Rebuild stroke cache if positionMs has changed
  void _ensureStrokeCacheValid() {
    final currentPos = positionMs;
    if (currentPos == _cachedPositionMs) return;
    _cachedPositionMs = currentPos;

    _activeStrokeCache.clear();
    _ghostStrokeCache.clear();
    _completedStrokeCount = 0;

    for (final synced in _recording!.syncedStrokes) {
      final page = synced.pageIndex;
      if (synced.isStarted(currentPos)) {
        final partial = synced.getPartialStroke(currentPos);
        if (partial != null) {
          _activeStrokeCache.putIfAbsent(page, () => []).add(partial);
          if (synced.isFullyVisible(currentPos)) {
            _completedStrokeCount++;
          }
        }
      } else if (_showGhostStrokes) {
        _ghostStrokeCache
            .putIfAbsent(page, () => [])
            .add(
              synced.stroke.copyWith(
                color: synced.stroke.color.withValues(
                  alpha: _ghostOpacity.clamp(0.0, 1.0),
                ),
              ),
            );
      }
    }
  }

  /// Gets ghost strokes (not yet started) with reduced opacity
  /// They show a "preview" of what will be drawn
  /// 📄 Filtered for the current page
  List<ProStroke> get ghostStrokes => getGhostStrokesForPage(_currentPageIndex);

  /// Gets all strokes to render (ghost + active)
  List<ProStroke> get allStrokesToRender {
    return [...ghostStrokes, ...activeStrokes];
  }

  /// 🧭 Gets the current drawing position (last point of the last active stroke)
  /// Returns null if there is no active stroke
  Offset? get currentDrawingPosition {
    final strokes = activeStrokes;
    if (strokes.isEmpty) return null;

    // Get the last active stroke
    final lastStroke = strokes.last;
    if (lastStroke.points.isEmpty) return null;

    // Return the position of the last point
    return lastStroke.points.last.position;
  }

  /// 🧭 Gets the bounding box of all active strokes
  /// Useful for understanding where drawing is happening
  Rect? get activeStrokesBounds {
    final strokes = activeStrokes;
    if (strokes.isEmpty) return null;

    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;

    for (final stroke in strokes) {
      for (final point in stroke.points) {
        if (point.position.dx < minX) minX = point.position.dx;
        if (point.position.dy < minY) minY = point.position.dy;
        if (point.position.dx > maxX) maxX = point.position.dx;
        if (point.position.dy > maxY) maxY = point.position.dy;
      }
    }

    if (minX == double.infinity) return null;
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  // ============================================================================
  // CARICAMENTO
  // ============================================================================

  /// Loads a synchronized recording
  Future<void> loadRecording(SynchronizedRecording recording) async {
    try {
      _state = SyncedPlaybackState.loading;
      notifyListeners();

      _recording = recording;

      // 🕐 Reset stopwatch
      _stopwatch.stop();
      _stopwatch.reset();
      _pausedPosition = Duration.zero;

      // Load audio file
      await _audioPlayer.setFilePath(recording.audioPath);

      // Setup listeners
      _setupListeners();

      _duration = recording.totalDuration;
      _state = SyncedPlaybackState.ready;

      // 🐛 DEBUG: Show stroke distribution by page
      final pageStats = <int, List<int>>{};
      for (final synced in recording.syncedStrokes) {
        pageStats.putIfAbsent(synced.pageIndex, () => []);
        pageStats[synced.pageIndex]!.add(synced.relativeStartMs);
      }
      for (final entry in pageStats.entries) {
        final times = entry.value..sort();
      }

      notifyListeners();
    } catch (e) {
      _state = SyncedPlaybackState.error;
      notifyListeners();
      rethrow;
    }
  }

  /// Loads a recording from JSON file
  Future<void> loadFromFile(String jsonPath, String audioPath) async {
    try {
      final file = File(jsonPath);
      if (!await file.exists()) {
        throw Exception('File JSON non trovato: $jsonPath');
      }

      final jsonString = await file.readAsString();
      var recording = SynchronizedRecording.fromJsonString(jsonString);

      // Update path audio se diverso
      if (recording.audioPath != audioPath) {
        recording = recording.copyWith(audioPath: audioPath);
      }

      await loadRecording(recording);
    } catch (e) {
      _state = SyncedPlaybackState.error;
      notifyListeners();
      rethrow;
    }
  }

  // ============================================================================
  // CONTROLLI PLAYBACK
  // ============================================================================

  /// Play
  Future<void> play() async {
    if (_recording == null) {
      return;
    }

    try {
      await _audioPlayer.play();

      // 🕐 Start stopwatch for precise time tracking
      _stopwatch.start();

      _state = SyncedPlaybackState.playing;
      _startUpdateTimer();
      notifyListeners();
    } catch (e, stack) {
      EngineLogger.warning(
        'Play failed',
        tag: 'SyncPlayback',
        error: e,
        stack: stack,
      );
    }
  }

  /// Pause
  Future<void> pause() async {
    try {
      await _audioPlayer.pause();

      // 🕐 Stop stopwatch and save position
      _stopwatch.stop();
      _pausedPosition = Duration(milliseconds: positionMs);

      _state = SyncedPlaybackState.paused;
      _stopUpdateTimer();
      notifyListeners();
    } catch (e, stack) {
      EngineLogger.warning(
        'Pause failed',
        tag: 'SyncPlayback',
        error: e,
        stack: stack,
      );
    }
  }

  /// Toggle play/pause
  Future<void> togglePlayPause() async {
    if (isPlaying) {
      await pause();
    } else {
      // 🔄 If playback is complete or we're at the end, restart from beginning
      if (_state == SyncedPlaybackState.completed ||
          positionMs >= _duration.inMilliseconds) {
        await seek(Duration.zero);
      }
      await play();
    }
  }

  /// Stop
  Future<void> stop() async {
    try {
      await _audioPlayer.stop();

      // 🕐 Reset stopwatch
      _stopwatch.stop();
      _stopwatch.reset();
      _pausedPosition = Duration.zero;

      _state = SyncedPlaybackState.ready;
      _stopUpdateTimer();
      notifyListeners();
    } catch (e, stack) {
      EngineLogger.warning(
        'Stop failed',
        tag: 'SyncPlayback',
        error: e,
        stack: stack,
      );
    }
  }

  /// Seek a position specifica
  Future<void> seek(Duration position) async {
    try {
      await _audioPlayer.seek(position);

      // 🕐 Update position stopwatch
      _stopwatch.reset();
      _pausedPosition = position;
      if (_state == SyncedPlaybackState.playing) {
        _stopwatch.start();
      }

      notifyListeners();
    } catch (e, stack) {
      EngineLogger.warning(
        'Seek failed',
        tag: 'SyncPlayback',
        error: e,
        stack: stack,
      );
    }
  }

  /// Seek a progresso (0.0 - 1.0)
  Future<void> seekToProgress(double progress) async {
    final newPosition = Duration(
      milliseconds:
          (duration.inMilliseconds * progress.clamp(0.0, 1.0)).toInt(),
    );
    await seek(newPosition);
  }

  /// Riavvia from the beginning
  Future<void> restart() async {
    await seek(Duration.zero);
    await play();
  }

  // ============================================================================
  // IMPOSTAZIONI
  // ============================================================================

  /// Sets opacity ghost strokes
  void setGhostOpacity(double opacity) {
    _ghostOpacity = opacity.clamp(0.0, 1.0);
    notifyListeners();
  }

  /// Sets visualizzazione ghost strokes
  void setShowGhostStrokes(bool show) {
    _showGhostStrokes = show;
    notifyListeners();
  }

  /// 🏎️ Sets playback speed (0.5x - 2.0x)
  Future<void> setSpeed(double newSpeed) async {
    _speed = newSpeed.clamp(0.5, 2.0);
    try {
      await _audioPlayer.setSpeed(_speed);
      // Reset stopwatch to resync with new speed
      if (_state == SyncedPlaybackState.playing) {
        _pausedPosition = Duration(milliseconds: positionMs);
        _stopwatch.reset();
        _stopwatch.start();
      }
    } catch (e) {
      EngineLogger.warning('SetSpeed failed', tag: 'SyncPlayback', error: e);
    }
    notifyListeners();
  }

  // ============================================================================
  // PRIVATE
  // ============================================================================

  /// Setup listeners per audio player
  void _setupListeners() {
    _positionSubscription?.cancel();
    _stateSubscription?.cancel();
    _durationSubscription?.cancel();

    _positionSubscription = _audioPlayer.positionStream.listen((pos) {
      // Note: we use internal stopwatch, this stream is not reliable
    });

    _stateSubscription = _audioPlayer.stateStream.listen((stateInfo) {
      if (stateInfo.state == AudioPlayerState.completed) {
        _state = SyncedPlaybackState.completed;
        _stopUpdateTimer();
        notifyListeners();
      } else if (stateInfo.state == AudioPlayerState.error) {
        _state = SyncedPlaybackState.error;
        _stopUpdateTimer();
        notifyListeners();
      }
    });

    _durationSubscription = _audioPlayer.durationStream.listen((dur) {
      if (dur != null) {
        _duration = dur;
        notifyListeners();
      }
    });
  }

  /// Avvia timer di aggiornamento per rendering fluido
  void _startUpdateTimer() {
    _stopUpdateTimer();
    // Update UI every 33ms (~30fps) — sufficient for smooth stroke animation
    // and drastically reduces widget rebuilds vs 16ms (60fps)
    _updateTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      final currentPos = positionMs;
      // 🕐 Check if we exceeded total duration
      if (currentPos >= _duration.inMilliseconds &&
          _duration.inMilliseconds > 0) {
        _stopwatch.stop();
        _state = SyncedPlaybackState.completed;
        _stopUpdateTimer();
        _lastNotifiedPositionMs = currentPos;
        notifyListeners();
        return;
      }
      // Skip notify if position hasn't changed (saves full rebuild)
      if (currentPos == _lastNotifiedPositionMs) return;
      _lastNotifiedPositionMs = currentPos;
      notifyListeners();
    });
  }

  /// Ferma timer di aggiornamento
  void _stopUpdateTimer() {
    _updateTimer?.cancel();
    _updateTimer = null;
  }

  // ============================================================================
  // CLEANUP
  // ============================================================================

  /// Scarica la registrazione corrente
  void unload() {
    _stopUpdateTimer();

    // 🕐 Reset stopwatch
    _stopwatch.stop();
    _stopwatch.reset();
    _pausedPosition = Duration.zero;

    _audioPlayer.stop();
    _recording = null;
    _duration = Duration.zero;
    _state = SyncedPlaybackState.idle;
    notifyListeners();
  }

  @override
  void dispose() {
    _stopUpdateTimer();
    _stopwatch.stop();
    _positionSubscription?.cancel();
    _stateSubscription?.cancel();
    _durationSubscription?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }
}
