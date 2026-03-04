import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../utils/safe_path_provider.dart';
import './native_audio_recorder.dart';
import './native_audio_player.dart';
import './native_audio_models.dart';
import '../canvas/fluera_canvas_config.dart';

// =============================================================================
// 🎤 DEFAULT VOICE RECORDING PROVIDER
//
// Built-in implementation of [FlueraVoiceRecordingProvider] that uses
// the SDK's native audio recorder and player. Provides zero-config
// recording capability — just press the mic button.
// =============================================================================

/// Default voice recording provider using the SDK's native audio stack.
///
/// Uses [NativeAudioRecorder] for capture and [NativeAudioPlayer] for playback.
/// Records in M4A format (AAC, 44100 Hz, 128kbps mono) to temporary storage.
///
/// This provider is used automatically when no custom [FlueraVoiceRecordingProvider]
/// is passed via [FlueraCanvasConfig.voiceRecording].
class DefaultVoiceRecordingProvider implements FlueraVoiceRecordingProvider {
  late final NativeAudioRecorder _recorder;
  late final NativeAudioPlayer _player;

  /// Access the underlying recorder (for setting pen intervals before stop).
  NativeAudioRecorder get recorder => _recorder;

  final _durationController = StreamController<Duration>.broadcast();
  final _playbackCompletedController = StreamController<void>.broadcast();
  StreamSubscription? _recorderDurationSub;
  StreamSubscription? _playerStateSub;
  bool _disposed = false;

  DefaultVoiceRecordingProvider() {
    _recorder = NativeAudioRecorder();
    _player = NativeAudioPlayer();

    // Forward recorder duration stream
    _recorderDurationSub = _recorder.durationStream.listen((duration) {
      if (!_durationController.isClosed) {
        _durationController.add(duration);
      }
    });

    // Listen for playback completion
    _playerStateSub = _player.stateStream.listen((stateInfo) {
      if (stateInfo.state == AudioPlayerState.completed &&
          !_playbackCompletedController.isClosed) {
        _playbackCompletedController.add(null);
      }
    });
  }

  // ===========================================================================
  // FlueraVoiceRecordingProvider implementation
  // ===========================================================================

  @override
  Future<void> startRecording({AudioRecordConfig? config}) async {
    // Check and request permission first
    var hasPermission = await _recorder.checkPermission();
    if (!hasPermission) {
      hasPermission = await _recorder.requestPermission();
      if (!hasPermission) {
        throw Exception(
          'Microphone permission denied. '
          'Please grant microphone access in your device settings.',
        );
      }
    }

    await _recorder.start(config: config ?? AudioRecordConfig.high);
  }

  @override
  Future<String?> stopRecording() async {
    return await _recorder.stop();
  }

  @override
  bool get isRecording => _recorder.isRecording;

  @override
  Stream<Duration> get recordingDuration => _durationController.stream;

  /// 🎵 Live amplitude stream for waveform visualization during recording.
  Stream<AudioAmplitude> get amplitudeStream => _recorder.amplitudeStream;

  /// 🎵 Current amplitude snapshot.
  AudioAmplitude get currentAmplitude => _recorder.amplitude;

  @override
  Future<void> playRecording(String path) async {
    try {
      await _player.setFilePath(path);
      await _player.play();
    } catch (e) {
    }
  }

  @override
  Future<void> stopPlayback() async {
    try {
      await _player.stop();
    } catch (e) {
    }
  }

  /// 🎵 Pause playback.
  Future<void> pausePlayback() async {
    try {
      await _player.pause();
    } catch (e) {
    }
  }

  /// 🎵 Resume playback.
  Future<void> resumePlayback() async {
    try {
      await _player.play();
    } catch (e) {
    }
  }

  /// 🎵 Seek to position.
  Future<void> seekPlayback(Duration position) async {
    try {
      await _player.seek(position);
    } catch (e) {
    }
  }

  /// 🎵 Whether the player is currently playing.
  bool get isPlaying => _player.isPlaying;

  /// 🎵 Set playback speed.
  Future<void> setSpeed(double speed) async {
    try {
      await _player.setSpeed(speed);
    } catch (e) {
    }
  }

  /// 🔊 Set playback volume (0.0–1.0).
  Future<void> setVolume(double volume) async {
    try {
      await _player.setVolume(volume.clamp(0.0, 1.0));
    } catch (e) {
    }
  }

  @override
  Stream<void> get playbackCompleted => _playbackCompletedController.stream;

  /// 🎵 Position stream for playback progress tracking.
  Stream<Duration> get positionStream => _player.positionStream;

  /// 🎵 Duration stream — emits when the player resolves the media duration.
  Stream<Duration?> get durationStream => _player.durationStream;

  /// 🎵 Get the current playback duration.
  Duration? getDuration() => _player.duration;

  /// 🎵 Get the playback position via method channel (reliable polling).
  Future<Duration> getPositionAsync() async {
    try {
      return await _player.getPositionAsync();
    } catch (_) {
      return _player.position;
    }
  }

  /// 🎵 Get the media duration via method channel (reliable polling).
  Future<Duration?> getDurationAsync() async {
    try {
      return await _player.getDurationAsync();
    } catch (_) {
      return _player.duration;
    }
  }

  // ===========================================================================
  // Lifecycle
  // ===========================================================================

  /// Dispose all resources.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    await _recorderDurationSub?.cancel();
    await _playerStateSub?.cancel();
    await _durationController.close();
    await _playbackCompletedController.close();
    await _recorder.dispose();
    await _player.dispose();
  }

  // ===========================================================================
  // Temp File Cleanup
  // ===========================================================================

  /// Delete old temporary recording files from the cache directory.
  ///
  /// Call periodically or on app start to prevent temp files from accumulating.
  /// Only deletes files matching the `fluera_recording_*` pattern.
  static Future<int> cleanupTempRecordings({
    Duration olderThan = const Duration(hours: 24),
  }) async {
    try {
      final tempDir = await _getTempDir();
      if (tempDir == null) return 0;

      final dir = Directory(tempDir);
      if (!await dir.exists()) return 0;

      final cutoff = DateTime.now().subtract(olderThan);
      int deleted = 0;

      await for (final entity in dir.list()) {
        if (entity is File) {
          final name = entity.path.split('/').last;
          if (name.startsWith('fluera_recording_')) {
            final stat = await entity.stat();
            if (stat.modified.isBefore(cutoff)) {
              await entity.delete();
              deleted++;
            }
          }
        }
      }

      if (deleted > 0) {
      }
      return deleted;
    } catch (e) {
      return 0;
    }
  }

  static Future<String?> _getTempDir() async {
    try {
      // 🔧 FIX: Recordings are now in filesDir/recordings (persistent)
      // instead of cacheDir (volatile). Use app support dir which maps to
      // Context.getFilesDir on Android.
      final dir = await getSafeAppSupportDirectory();
      if (dir == null) {
        // Fallback: try temp dir for legacy files
        final tempDir = await getSafeTempDirectory();
        return tempDir?.path;
      }
      final recordingsDir = Directory('${dir.path}/recordings');
      if (!recordingsDir.existsSync()) {
        recordingsDir.createSync(recursive: true);
      }
      return recordingsDir.path;
    } catch (_) {
      try {
        return Directory.systemTemp.path;
      } catch (_) {
        return null;
      }
    }
  }
}
