import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import './native_audio_recorder.dart';
import './native_audio_player.dart';
import './native_audio_models.dart';
import '../canvas/nebula_canvas_config.dart';

// =============================================================================
// 🎤 DEFAULT VOICE RECORDING PROVIDER
//
// Built-in implementation of [NebulaVoiceRecordingProvider] that uses
// the SDK's native audio recorder and player. Provides zero-config
// recording capability — just press the mic button.
// =============================================================================

/// Default voice recording provider using the SDK's native audio stack.
///
/// Uses [NativeAudioRecorder] for capture and [NativeAudioPlayer] for playback.
/// Records in M4A format (AAC, 44100 Hz, 128kbps mono) to temporary storage.
///
/// This provider is used automatically when no custom [NebulaVoiceRecordingProvider]
/// is passed via [NebulaCanvasConfig.voiceRecording].
class DefaultVoiceRecordingProvider implements NebulaVoiceRecordingProvider {
  late final NativeAudioRecorder _recorder;
  late final NativeAudioPlayer _player;

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
  // NebulaVoiceRecordingProvider implementation
  // ===========================================================================

  @override
  Future<void> startRecording() async {
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

    await _recorder.start();
  }

  @override
  Future<String?> stopRecording() async {
    return await _recorder.stop();
  }

  @override
  bool get isRecording => _recorder.isRecording;

  @override
  Stream<Duration> get recordingDuration => _durationController.stream;

  @override
  Future<void> playRecording(String path) async {
    try {
      await _player.setFilePath(path);
      await _player.play();
    } catch (e) {
      debugPrint('[DefaultVoiceRecordingProvider] Playback failed: $e');
    }
  }

  @override
  Future<void> stopPlayback() async {
    try {
      await _player.stop();
    } catch (e) {
      debugPrint('[DefaultVoiceRecordingProvider] Stop playback failed: $e');
    }
  }

  @override
  Stream<void> get playbackCompleted => _playbackCompletedController.stream;

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
  /// Only deletes files matching the `nebula_recording_*` pattern.
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
          if (name.startsWith('nebula_recording_')) {
            final stat = await entity.stat();
            if (stat.modified.isBefore(cutoff)) {
              await entity.delete();
              deleted++;
            }
          }
        }
      }

      if (deleted > 0) {
        debugPrint(
          '[DefaultVoiceRecordingProvider] Cleaned up $deleted temp recordings',
        );
      }
      return deleted;
    } catch (e) {
      debugPrint('[DefaultVoiceRecordingProvider] Cleanup failed: $e');
      return 0;
    }
  }

  static Future<String?> _getTempDir() async {
    try {
      // Use path_provider for cross-platform temp dir resolution.
      // On iOS: NSTemporaryDirectory, on Android: Context.getCacheDir
      final dir = await getTemporaryDirectory();
      return dir.path;
    } catch (_) {
      // Fallback to system temp (may not match native recorder output on Android)
      try {
        return Directory.systemTemp.path;
      } catch (_) {
        return null;
      }
    }
  }
}
