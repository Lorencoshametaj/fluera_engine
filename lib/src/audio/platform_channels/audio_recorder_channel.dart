import 'package:flutter/services.dart';
import 'dart:async';
import '../native_audio_models.dart';
import '../../core/engine_scope.dart';

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
    'nebulaengine.audio/recorder',
  );
  static const EventChannel _eventChannel = EventChannel(
    'nebulaengine.audio/recorder_events',
  );

  /// Legacy singleton accessor — delegates to [EngineScope.current].
  static NativeAudioRecorderChannel get instance =>
      EngineScope.current.audioRecorderChannel;

  /// Creates a new instance (used by [EngineScope]).
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
  }
}
