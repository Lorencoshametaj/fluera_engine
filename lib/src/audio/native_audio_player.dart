import 'dart:async';
import 'package:flutter/foundation.dart';
import './native_audio_models.dart';
import './platform_channels/audio_player_channel.dart';

/// 🎵 NATIVE AUDIO PLAYER
///
/// Player audio nativo completo che sostituisce just_audio
/// con implementazione diretta iOS/Android via Platform Channels
class NativeAudioPlayer {
  final NativeAudioPlayerChannel _channel = NativeAudioPlayerChannel.instance;

  bool _isInitialized = false;
  AudioPlayerStateInfo _currentState = AudioPlayerStateInfo(
    state: AudioPlayerState.idle,
    position: Duration.zero,
  );

  // Stream subscriptions
  StreamSubscription? _stateSubscription;
  StreamSubscription? _positionSubscription;
  StreamSubscription? _durationSubscription;
  StreamSubscription? _errorSubscription;

  // Public streams
  final _stateController = StreamController<AudioPlayerStateInfo>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration?>.broadcast();
  final _playingController = StreamController<bool>.broadcast();

  NativeAudioPlayer() {
    _initialize();
  }

  /// Initializes il player
  Future<void> _initialize() async {
    if (_isInitialized) return;

    try {
      await _channel.initialize();
      _setupListeners();
      _isInitialized = true;
      debugPrint('✅ NativeAudioPlayer initialized');
    } catch (e) {
      // ⚠️ On desktop/web or if initialization fails, we just log and continue
      // to avoid crashing the app startup.
      debugPrint(
        '⚠️ Failed to initialize NativeAudioPlayer (likely platform mismatch): $e',
      );
      // Do NOT rethrow to prevent app crash on Linux
    }
  }

  /// Setup listeners per eventi dal nativo
  void _setupListeners() {
    _stateSubscription = _channel.stateStream.listen((state) {
      _currentState = state;
      _stateController.add(state);
      _playingController.add(state.isPlaying);

      debugPrint('🎵 Player state: ${state.state.name}');
    });

    _positionSubscription = _channel.positionStream.listen((position) {
      _positionController.add(position);
    });

    _durationSubscription = _channel.durationStream.listen((duration) {
      _durationController.add(duration);
    });

    _errorSubscription = _channel.errorStream.listen((error) {
      debugPrint('🎵 Player error: $error');
      _currentState = _currentState.copyWith(
        state: AudioPlayerState.error,
        error: error,
      );
      _stateController.add(_currentState);
    });
  }

  /// Streams pubblici
  Stream<AudioPlayerStateInfo> get stateStream => _stateController.stream;
  Stream<Duration> get positionStream => _positionController.stream;
  Stream<Duration?> get durationStream => _durationController.stream;
  Stream<bool> get playingStream => _playingController.stream;

  /// Getters for current state
  AudioPlayerState get state => _currentState.state;
  Duration get position => _currentState.position;
  Duration? get duration => _currentState.duration;
  bool get isPlaying => _currentState.isPlaying;
  bool get isPaused => _currentState.isPaused;
  double get volume => _currentState.volume;
  double get speed => _currentState.speed;
  AudioLoopMode get loopMode => _currentState.loopMode;

  /// Ensure initialized
  Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      await _initialize();
    }
  }

  /// ═══════════════════════════════════════════════════════════════
  /// 🎵 PLAYBACK CONTROLS
  /// ═══════════════════════════════════════════════════════════════

  /// Loads audio da file path
  Future<void> setFilePath(String filePath) async {
    await _ensureInitialized();
    try {
      debugPrint('📁 Loading file: $filePath');
      await _channel.setFilePath(filePath);
    } catch (e) {
      debugPrint('❌ Failed to load file: $e');
      rethrow;
    }
  }

  /// Loads audio da asset
  Future<void> setAsset(String assetPath) async {
    await _ensureInitialized();
    try {
      debugPrint('📦 Loading asset: $assetPath');
      await _channel.setAsset(assetPath);
    } catch (e) {
      debugPrint('❌ Failed to load asset: $e');
      rethrow;
    }
  }

  /// Loads audio da URL (con supporto streaming)
  Future<void> setUrl(String url, {Map<String, String>? headers}) async {
    await _ensureInitialized();
    try {
      debugPrint('🌐 Loading URL: $url');
      await _channel.setUrl(url, headers: headers);
    } catch (e) {
      debugPrint('❌ Failed to load URL: $e');
      rethrow;
    }
  }

  /// Play
  Future<void> play() async {
    await _ensureInitialized();
    try {
      await _channel.play();
      debugPrint('▶️ Playing');
    } catch (e) {
      debugPrint('❌ Failed to play: $e');
      rethrow;
    }
  }

  /// Pause
  Future<void> pause() async {
    await _ensureInitialized();
    try {
      await _channel.pause();
      debugPrint('⏸️ Paused');
    } catch (e) {
      debugPrint('❌ Failed to pause: $e');
      rethrow;
    }
  }

  /// Stop
  Future<void> stop() async {
    await _ensureInitialized();
    try {
      await _channel.stop();
      debugPrint('⏹️ Stopped');
    } catch (e) {
      debugPrint('❌ Failed to stop: $e');
      rethrow;
    }
  }

  /// Seek to position
  Future<void> seek(Duration position) async {
    await _ensureInitialized();
    try {
      await _channel.seek(position);
      debugPrint('⏩ Seeking to: ${position.inSeconds}s');
    } catch (e) {
      debugPrint('❌ Failed to seek: $e');
      rethrow;
    }
  }

  /// ═══════════════════════════════════════════════════════════════
  /// 🎚️ AUDIO SETTINGS
  /// ═══════════════════════════════════════════════════════════════

  /// Set volume (0.0 - 1.0)
  Future<void> setVolume(double volume) async {
    await _ensureInitialized();
    try {
      await _channel.setVolume(volume);
      debugPrint('🔊 Volume: ${(volume * 100).toInt()}%');
    } catch (e) {
      debugPrint('❌ Failed to set volume: $e');
      rethrow;
    }
  }

  /// Set playback speed (0.5 - 2.0)
  Future<void> setSpeed(double speed) async {
    await _ensureInitialized();
    try {
      await _channel.setSpeed(speed);
      debugPrint('⚡ Speed: ${speed}x');
    } catch (e) {
      debugPrint('❌ Failed to set speed: $e');
      rethrow;
    }
  }

  /// Set loop mode
  Future<void> setLoopMode(AudioLoopMode mode) async {
    await _ensureInitialized();
    try {
      await _channel.setLoopMode(mode);
      debugPrint('🔁 Loop mode: ${mode.name}');
    } catch (e) {
      debugPrint('❌ Failed to set loop mode: $e');
      rethrow;
    }
  }

  /// ═══════════════════════════════════════════════════════════════
  /// 🗑️ CLEANUP
  /// ═══════════════════════════════════════════════════════════════

  /// Release resources
  Future<void> release() async {
    try {
      await _channel.release();
      debugPrint('🗑️ Player released');
    } catch (e) {
      debugPrint('❌ Failed to release player: $e');
    }
  }

  /// Dispose player
  Future<void> dispose() async {
    await _stateSubscription?.cancel();
    await _positionSubscription?.cancel();
    await _durationSubscription?.cancel();
    await _errorSubscription?.cancel();

    await _stateController.close();
    await _positionController.close();
    await _durationController.close();
    await _playingController.close();

    await _channel.dispose();
    _isInitialized = false;

    debugPrint('🗑️ NativeAudioPlayer disposed');
  }
}
