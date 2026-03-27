import 'package:flutter/services.dart';
import 'dart:async';
import '../native_audio_models.dart';

// =============================================================================
// 🎤 NATIVE AUDIO RECORDER CHANNEL
//
// Platform channel for communicating with the native audio recorder (iOS/Android).
// iOS: AVAudioRecorder | Android: MediaRecorder
// =============================================================================

/// Platform channel interface for native audio recording.
///
/// Mirrors the pattern of [NativeAudioPlayerChannel] but for recording.
/// Uses MethodChannel for commands and EventChannel for state/amplitude updates.
class NativeAudioRecorderChannel {
  static const MethodChannel _channel = MethodChannel(
    'flueraengine.audio/recorder',
  );
  static const EventChannel _eventChannel = EventChannel(
    'flueraengine.audio/recorder_events',
  );

  /// Creates a new instance (used by modules).
  NativeAudioRecorderChannel.create();

  Stream<Map<String, dynamic>>? _eventStream;
  StreamSubscription? _eventSubscription;

  final _stateController = StreamController<AudioRecorderState>.broadcast();
  final _amplitudeController = StreamController<AudioAmplitude>.broadcast();
  final _durationController = StreamController<Duration>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  /// Initialize the native recorder
  Future<void> initialize() async {
    try {
      await _channel.invokeMethod('initialize');
      _setupEventStream();
    } catch (e) {
      throw Exception('Failed to initialize audio recorder: $e');
    }
  }

  /// Setup event stream from native side
  void _setupEventStream() {
    _eventStream ??= _eventChannel.receiveBroadcastStream().map(
      (event) => Map<String, dynamic>.from(event),
    );

    _eventSubscription = _eventStream!.listen((event) {
      final eventType = event['event'] as String?;

      switch (eventType) {
        case 'state':
          final stateName = event['state'] as String? ?? 'idle';
          final state = AudioRecorderState.values.firstWhere(
            (e) => e.name == stateName,
            orElse: () => AudioRecorderState.idle,
          );
          if (!_stateController.isClosed) {
            _stateController.add(state);
          }
          break;

        case 'amplitude':
          final amplitude = AudioAmplitude.fromMap(event);
          if (!_amplitudeController.isClosed) {
            _amplitudeController.add(amplitude);
          }
          break;

        case 'duration':
          final durationMs = event['duration'] as int? ?? 0;
          if (!_durationController.isClosed) {
            _durationController.add(Duration(milliseconds: durationMs));
          }
          break;

        case 'error':
          final error = event['error'] as String? ?? 'Unknown error';
          if (!_errorController.isClosed) {
            _errorController.add(error);
          }
          break;
      }
    });
  }

  // ===========================================================================
  // Streams
  // ===========================================================================

  Stream<AudioRecorderState> get stateStream => _stateController.stream;
  Stream<AudioAmplitude> get amplitudeStream => _amplitudeController.stream;
  Stream<Duration> get durationStream => _durationController.stream;
  Stream<String> get errorStream => _errorController.stream;

  // ===========================================================================
  // Commands
  // ===========================================================================

  /// Start recording with the given configuration
  Future<void> startRecording(AudioRecordConfig config) async {
    try {
      await _channel.invokeMethod('startRecording', config.toMap());
    } catch (e) {
      throw Exception('Failed to start recording: $e');
    }
  }

  /// Stop recording and return the file path
  Future<String?> stopRecording() async {
    try {
      final result = await _channel.invokeMethod<String>('stopRecording');
      return result;
    } catch (e) {
      throw Exception('Failed to stop recording: $e');
    }
  }

  /// Pause recording (iOS 12+, Android API 24+)
  Future<void> pauseRecording() async {
    try {
      await _channel.invokeMethod('pauseRecording');
    } catch (e) {
      throw Exception('Failed to pause recording: $e');
    }
  }

  /// Resume recording after pause
  Future<void> resumeRecording() async {
    try {
      await _channel.invokeMethod('resumeRecording');
    } catch (e) {
      throw Exception('Failed to resume recording: $e');
    }
  }

  /// Cancel recording (stops and deletes temp file)
  Future<void> cancelRecording() async {
    try {
      await _channel.invokeMethod('cancelRecording');
    } catch (e) {
      throw Exception('Failed to cancel recording: $e');
    }
  }

  /// Check if microphone permission is granted
  Future<bool> hasPermission() async {
    try {
      final result = await _channel.invokeMethod<bool>('hasPermission');
      return result ?? false;
    } catch (e) {
      throw Exception('Failed to check permission: $e');
    }
  }

  /// Request microphone permission
  Future<bool> requestPermission() async {
    try {
      final result = await _channel.invokeMethod<bool>('requestPermission');
      return result ?? false;
    } catch (e) {
      throw Exception('Failed to request permission: $e');
    }
  }

  /// 🎛️ Apply full audio processing pipeline to a recorded file.
  ///
  /// Runs: high-pass filter → RNNoise → compressor → normalization.
  /// Returns the processed file path (same file, processed in-place).
  Future<String?> applyAudioProcessing({
    required String filePath,
    required int sampleRate,
    int highPassFilterHz = 100,
    bool compressor = true,
    bool normalization = true,
  }) async {
    try {
      final result = await _channel
          .invokeMethod<String>('applyAudioProcessing', {
            'filePath': filePath,
            'sampleRate': sampleRate,
            'highPassFilterHz': highPassFilterHz,
            'compressor': compressor,
            'normalization': normalization,
          });
      return result;
    } catch (e) {
      // Non-fatal — return original file if processing fails
      return filePath;
    }
  }

  /// 🔄 Convert an audio file (M4A/AAC/MP3) to 16kHz mono WAV format.
  ///
  /// Used by [SherpaTranscriptionService] to prepare audio for ASR models.
  /// Native implementation:
  /// - **iOS**: AVAudioFile → AVAudioPCMBuffer → Linear PCM WAV
  /// - **Android**: MediaExtractor + MediaCodec → PCM → WAV header
  ///
  /// Returns the path to the converted WAV file, or `null` on failure.
  Future<String?> convertToWav({
    required String inputPath,
    int sampleRate = 16000,
  }) async {
    try {
      final result = await _channel.invokeMethod<String>('convertToWav', {
        'inputPath': inputPath,
        'sampleRate': sampleRate,
      });
      return result;
    } catch (e) {
      return null;
    }
  }

  // ===========================================================================
  // 🎤 Live PCM Streaming (for real-time transcription)
  // ===========================================================================

  static const EventChannel _pcmEventChannel = EventChannel(
    'flueraengine.audio/recorder_pcm',
  );

  Stream<dynamic>? _pcmEventStream;

  /// Enable live PCM streaming from the native recorder.
  /// Must be called AFTER recording has started.
  /// PCM data is 16kHz mono Int16LE, sent as Uint8List chunks (~100ms each).
  Future<void> enablePcmStream() async {
    try {
      await _channel.invokeMethod('enablePcmStream');
    } catch (e) {
      throw Exception('Failed to enable PCM stream: $e');
    }
  }

  /// Disable live PCM streaming.
  Future<void> disablePcmStream() async {
    try {
      await _channel.invokeMethod('disablePcmStream');
    } catch (e) {
      // Non-fatal
    }
  }

  /// Stream of raw PCM audio chunks (16kHz mono Int16LE as Uint8List).
  /// Listen to this after calling [enablePcmStream].
  Stream<dynamic> get pcmStream {
    _pcmEventStream ??= _pcmEventChannel.receiveBroadcastStream();
    return _pcmEventStream!;
  }

  /// Dispose the recorder channel
  Future<void> dispose() async {
    await _eventSubscription?.cancel();
    await _stateController.close();
    await _amplitudeController.close();
    await _durationController.close();
    await _errorController.close();
  }

  /// Reset all state for testing.
  void resetForTesting() {
    _eventSubscription?.cancel();
    _eventSubscription = null;
    _eventStream = null;
    _pcmEventStream = null;
  }
}
