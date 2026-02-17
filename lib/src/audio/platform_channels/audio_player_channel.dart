import 'package:flutter/services.dart';
import 'dart:async';
import '../native_audio_models.dart';
import '../../core/engine_scope.dart';

/// 🎵 NATIVE AUDIO PLAYER CHANNEL
///
/// Platform channel per comunicare con il player nativo (iOS/Android)
class NativeAudioPlayerChannel {
  static const MethodChannel _channel = MethodChannel(
    'com.looponia.audio/player',
  );
  static const EventChannel _eventChannel = EventChannel(
    'com.looponia.audio/player_events',
  );

  /// Legacy singleton accessor — delegates to [EngineScope.current].
  static NativeAudioPlayerChannel get instance =>
      EngineScope.current.audioPlayerChannel;

  /// Creates a new instance (used by [EngineScope]).
  NativeAudioPlayerChannel.create();

  Stream<Map<String, dynamic>>? _eventStream;
  StreamSubscription? _eventSubscription;
  final _stateController = StreamController<AudioPlayerStateInfo>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration?>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  /// Initializes il player
  Future<void> initialize() async {
    try {
      await _channel.invokeMethod('initialize');
      _setupEventStream();
    } catch (e) {
      throw Exception('Failed to initialize audio player: $e');
    }
  }

  /// Setup stream di eventi dal nativo
  void _setupEventStream() {
    _eventStream ??= _eventChannel.receiveBroadcastStream().map(
      (event) => Map<String, dynamic>.from(event),
    );

    _eventSubscription = _eventStream!.listen((event) {
      final eventType = event['event'] as String?;

      switch (eventType) {
        case 'state':
          final state = AudioPlayerStateInfo.fromMap(event);
          if (!_stateController.isClosed) {
            _stateController.add(state);
          }
          break;

        case 'position':
          final position = Duration(milliseconds: event['position'] ?? 0);
          if (!_positionController.isClosed) {
            _positionController.add(position);
          }
          break;

        case 'duration':
          final duration =
              event['duration'] != null
                  ? Duration(milliseconds: event['duration'])
                  : null;
          if (!_durationController.isClosed) {
            _durationController.add(duration);
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

  /// Streams
  Stream<AudioPlayerStateInfo> get stateStream => _stateController.stream;
  Stream<Duration> get positionStream => _positionController.stream;
  Stream<Duration?> get durationStream => _durationController.stream;
  Stream<String> get errorStream => _errorController.stream;

  /// Loads audio da file path
  Future<void> setFilePath(String filePath) async {
    try {
      await _channel.invokeMethod('setFilePath', {'path': filePath});
    } catch (e) {
      throw Exception('Failed to set file path: $e');
    }
  }

  /// Loads audio da asset
  Future<void> setAsset(String assetPath) async {
    try {
      await _channel.invokeMethod('setAsset', {'path': assetPath});
    } catch (e) {
      throw Exception('Failed to set asset: $e');
    }
  }

  /// Loads audio da URL
  Future<void> setUrl(String url, {Map<String, String>? headers}) async {
    try {
      await _channel.invokeMethod('setUrl', {
        'url': url,
        'headers': headers ?? {},
      });
    } catch (e) {
      throw Exception('Failed to set URL: $e');
    }
  }

  /// Play
  Future<void> play() async {
    try {
      await _channel.invokeMethod('play');
    } catch (e) {
      throw Exception('Failed to play: $e');
    }
  }

  /// Pause
  Future<void> pause() async {
    try {
      await _channel.invokeMethod('pause');
    } catch (e) {
      throw Exception('Failed to pause: $e');
    }
  }

  /// Stop
  Future<void> stop() async {
    try {
      await _channel.invokeMethod('stop');
    } catch (e) {
      throw Exception('Failed to stop: $e');
    }
  }

  /// Seek
  Future<void> seek(Duration position) async {
    try {
      await _channel.invokeMethod('seek', {
        'position': position.inMilliseconds,
      });
    } catch (e) {
      throw Exception('Failed to seek: $e');
    }
  }

  /// Set volume (0.0 - 1.0)
  Future<void> setVolume(double volume) async {
    try {
      await _channel.invokeMethod('setVolume', {
        'volume': volume.clamp(0.0, 1.0),
      });
    } catch (e) {
      throw Exception('Failed to set volume: $e');
    }
  }

  /// Set speed (0.5 - 2.0)
  Future<void> setSpeed(double speed) async {
    try {
      await _channel.invokeMethod('setSpeed', {'speed': speed.clamp(0.5, 2.0)});
    } catch (e) {
      throw Exception('Failed to set speed: $e');
    }
  }

  /// Set loop mode
  Future<void> setLoopMode(AudioLoopMode mode) async {
    try {
      await _channel.invokeMethod('setLoopMode', {'mode': mode.name});
    } catch (e) {
      throw Exception('Failed to set loop mode: $e');
    }
  }

  /// Get current position
  Future<Duration> getPosition() async {
    try {
      final result = await _channel.invokeMethod<int>('getPosition');
      return Duration(milliseconds: result ?? 0);
    } catch (e) {
      throw Exception('Failed to get position: $e');
    }
  }

  /// Get duration
  Future<Duration?> getDuration() async {
    try {
      final result = await _channel.invokeMethod<int?>('getDuration');
      return result != null ? Duration(milliseconds: result) : null;
    } catch (e) {
      throw Exception('Failed to get duration: $e');
    }
  }

  /// Get current state
  Future<AudioPlayerStateInfo> getState() async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getState',
      );
      return AudioPlayerStateInfo.fromMap(
        Map<String, dynamic>.from(result ?? {}),
      );
    } catch (e) {
      throw Exception('Failed to get state: $e');
    }
  }

  /// Release player
  Future<void> release() async {
    try {
      await _channel.invokeMethod('release');
    } catch (e) {
      throw Exception('Failed to release player: $e');
    }
  }

  /// Dispose
  Future<void> dispose() async {
    await _eventSubscription?.cancel();
    await _stateController.close();
    await _positionController.close();
    await _durationController.close();
    await _errorController.close();
    await release();
  }

  /// Reset all state for testing.
  void resetForTesting() {
    _eventSubscription?.cancel();
    _eventSubscription = null;
    _eventStream = null;
  }
}
