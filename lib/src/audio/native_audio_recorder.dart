import 'dart:async';
import 'package:flutter/foundation.dart';
import './native_audio_models.dart';
import './platform_channels/audio_recorder_channel.dart';
import '../core/engine_scope.dart';

// =============================================================================
// 🎤 NATIVE AUDIO RECORDER
//
// High-level Dart wrapper over the native audio recorder platform channel.
// Provides a clean API for recording audio with configurable format,
// sample rate, and bit rate. Handles initialization, state management,
// and graceful failure on unsupported platforms.
// =============================================================================

/// Native audio recorder that replaces third-party recording packages.
///
/// Uses AVAudioRecorder on iOS and MediaRecorder on Android via platform
/// channels owned by the SDK. Falls back gracefully on desktop/web.
///
/// ```dart
/// final recorder = NativeAudioRecorder();
/// await recorder.start();
/// // ... recording ...
/// final path = await recorder.stop(); // returns file path
/// ```
class NativeAudioRecorder {
  late final NativeAudioRecorderChannel _channel;

  NativeAudioRecorder({NativeAudioRecorderChannel? channel})
    : _channel =
          channel ??
          (EngineScope.hasScope
              ? EngineScope.current.audioModule?.recorder ??
                  NativeAudioRecorderChannel.create()
              : NativeAudioRecorderChannel.create()) {
    _initialize();
  }

  bool _isInitialized = false;
  Completer<void>? _initCompleter; // Guard against concurrent init
  AudioRecorderState _currentState = AudioRecorderState.idle;
  Duration _currentDuration = Duration.zero;
  AudioAmplitude _currentAmplitude = const AudioAmplitude(current: 0.0);
  AudioRecordConfig? _lastConfig;

  // Stream subscriptions
  StreamSubscription? _stateSubscription;
  StreamSubscription? _amplitudeSubscription;
  StreamSubscription? _durationSubscription;
  StreamSubscription? _errorSubscription;

  // Public stream controllers
  final _stateController = StreamController<AudioRecorderState>.broadcast();
  final _amplitudeController = StreamController<AudioAmplitude>.broadcast();
  final _durationController = StreamController<Duration>.broadcast();

  /// Initialize the recorder (guarded against concurrent calls)
  Future<void> _initialize() async {
    if (_isInitialized) return;
    if (_initCompleter != null) return _initCompleter!.future;

    _initCompleter = Completer<void>();
    try {
      await _channel.initialize();
      _setupListeners();
      _isInitialized = true;
      debugPrint('✅ NativeAudioRecorder initialized');
      _initCompleter!.complete();
    } catch (e) {
      // On desktop/web or if initialization fails, log and continue
      debugPrint(
        '⚠️ Failed to initialize NativeAudioRecorder (likely platform mismatch): $e',
      );
      _initCompleter!.complete(); // Complete even on error so awaits don't hang
    }
  }

  /// Setup listeners for native events
  void _setupListeners() {
    _stateSubscription = _channel.stateStream.listen((state) {
      _currentState = state;
      _stateController.add(state);
      debugPrint('🎤 Recorder state: ${state.name}');
    });

    _amplitudeSubscription = _channel.amplitudeStream.listen((amplitude) {
      _currentAmplitude = amplitude;
      _amplitudeController.add(amplitude);
    });

    _durationSubscription = _channel.durationStream.listen((duration) {
      _currentDuration = duration;
      _durationController.add(duration);
    });

    _errorSubscription = _channel.errorStream.listen((error) {
      debugPrint('🎤 Recorder error: $error');
      _currentState = AudioRecorderState.error;
      _stateController.add(AudioRecorderState.error);
    });
  }

  // ===========================================================================
  // Public Streams
  // ===========================================================================

  Stream<AudioRecorderState> get stateStream => _stateController.stream;
  Stream<AudioAmplitude> get amplitudeStream => _amplitudeController.stream;
  Stream<Duration> get durationStream => _durationController.stream;

  // ===========================================================================
  // Getters
  // ===========================================================================

  AudioRecorderState get state => _currentState;
  bool get isRecording => _currentState == AudioRecorderState.recording;
  bool get isPaused => _currentState == AudioRecorderState.paused;
  Duration get duration => _currentDuration;
  AudioAmplitude get amplitude => _currentAmplitude;

  /// Ensure initialized before operations
  Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      await _initialize();
    }
  }

  // ===========================================================================
  // 🎤 RECORDING CONTROLS
  // ===========================================================================

  /// Start recording with optional configuration.
  ///
  /// Default config: M4A format, 48000 Hz sample rate, 256kbps, mono.
  Future<void> start({AudioRecordConfig? config}) async {
    await _ensureInitialized();
    try {
      final recordConfig = config ?? const AudioRecordConfig();
      _lastConfig = recordConfig;
      debugPrint(
        '🎤 _lastConfig set: hpf=${recordConfig.highPassFilterHz} comp=${recordConfig.compressor} norm=${recordConfig.normalization} needsPost=${recordConfig.needsPostProcessing}',
      );
      await _channel.startRecording(recordConfig);
      _currentState = AudioRecorderState.recording;
      _currentDuration = Duration.zero;
      debugPrint('🎤 Recording started');
    } catch (e) {
      debugPrint('❌ Failed to start recording: $e');
      rethrow;
    }
  }

  /// Stop recording and return the file path.
  ///
  /// Returns the raw (unprocessed) audio path immediately so the UI
  /// can show the save dialog without waiting for post-processing.
  /// Call [applyPendingPostProcessing] afterwards to apply RNNoise
  /// denoising and other DSP if configured.
  ///
  /// Returns `null` if recording was not active or failed.
  Future<String?> stop() async {
    await _ensureInitialized();
    try {
      final path = await _channel.stopRecording();
      _currentState = AudioRecorderState.stopped;

      debugPrint(
        '🎛️ stop() check: path=$path _lastConfig=${_lastConfig != null} needsPost=${_lastConfig?.needsPostProcessing}',
      );
      debugPrint('⏹️ Recording stopped (raw): $path');
      return path;
    } catch (e) {
      debugPrint('❌ Failed to stop recording: $e');
      rethrow;
    }
  }

  /// Whether the last recording needs post-processing (RNNoise, HPF, etc.).
  bool get hasPendingPostProcessing =>
      _lastConfig != null && _lastConfig!.needsPostProcessing;

  /// Apply audio post-processing (RNNoise denoising, high-pass filter,
  /// compressor, normalization) to a previously stopped recording.
  ///
  /// Call this AFTER the user confirms save in the dialog to avoid
  /// blocking the UI thread for several seconds.
  ///
  /// Returns the processed file path, or [rawPath] unchanged if no
  /// processing is needed.
  Future<String?> applyPendingPostProcessing(String rawPath) async {
    if (_lastConfig == null || !_lastConfig!.needsPostProcessing) {
      return rawPath;
    }
    try {
      debugPrint('🎛️ Applying audio processing pipeline...');
      final processed = await _channel.applyAudioProcessing(
        filePath: rawPath,
        sampleRate: _lastConfig!.sampleRate,
        highPassFilterHz: _lastConfig!.highPassFilterHz,
        compressor: _lastConfig!.compressor,
        normalization: _lastConfig!.normalization,
      );
      debugPrint('🎛️ Audio processing complete');
      return processed;
    } catch (e) {
      debugPrint('❌ Audio post-processing failed: $e');
      // Return raw path as fallback — better than losing the recording
      return rawPath;
    }
  }

  /// Pause recording (iOS 12+, Android API 24+).
  Future<void> pause() async {
    await _ensureInitialized();
    try {
      await _channel.pauseRecording();
      _currentState = AudioRecorderState.paused;
      debugPrint('⏸️ Recording paused');
    } catch (e) {
      debugPrint('❌ Failed to pause recording: $e');
      rethrow;
    }
  }

  /// Resume recording after pause.
  Future<void> resume() async {
    await _ensureInitialized();
    try {
      await _channel.resumeRecording();
      _currentState = AudioRecorderState.recording;
      debugPrint('▶️ Recording resumed');
    } catch (e) {
      debugPrint('❌ Failed to resume recording: $e');
      rethrow;
    }
  }

  /// Cancel recording (stops and deletes temporary file).
  Future<void> cancel() async {
    await _ensureInitialized();
    try {
      await _channel.cancelRecording();
      _currentState = AudioRecorderState.idle;
      _currentDuration = Duration.zero;
      debugPrint('🗑️ Recording cancelled');
    } catch (e) {
      debugPrint('❌ Failed to cancel recording: $e');
      rethrow;
    }
  }

  // ===========================================================================
  // 🔒 PERMISSIONS
  // ===========================================================================

  /// Check if microphone permission is granted.
  Future<bool> checkPermission() async {
    await _ensureInitialized();
    try {
      return await _channel.hasPermission();
    } catch (e) {
      debugPrint('❌ Failed to check permission: $e');
      return false;
    }
  }

  /// Request microphone permission.
  ///
  /// On iOS, shows the system permission dialog.
  /// On Android, returns false — the host app must handle runtime permission
  /// requests at the Activity level.
  Future<bool> requestPermission() async {
    await _ensureInitialized();
    try {
      return await _channel.requestPermission();
    } catch (e) {
      debugPrint('❌ Failed to request permission: $e');
      return false;
    }
  }

  // ===========================================================================
  // 🗑️ CLEANUP
  // ===========================================================================

  /// Dispose the recorder and release all resources.
  Future<void> dispose() async {
    await _stateSubscription?.cancel();
    await _amplitudeSubscription?.cancel();
    await _durationSubscription?.cancel();
    await _errorSubscription?.cancel();

    await _stateController.close();
    await _amplitudeController.close();
    await _durationController.close();

    await _channel.dispose();
    _isInitialized = false;

    debugPrint('🗑️ NativeAudioRecorder disposed');
  }
}
