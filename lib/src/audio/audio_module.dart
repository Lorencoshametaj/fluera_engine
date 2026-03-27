import '../core/modules/canvas_module.dart';
import '../tools/base/tool_interface.dart';
import 'platform_channels/audio_player_channel.dart';
import 'platform_channels/audio_recorder_channel.dart';

// =============================================================================
// AUDIO MODULE
// =============================================================================

/// 🎵 Self-contained audio module for the Fluera Engine canvas.
///
/// Encapsulates all audio functionality:
/// - [NativeAudioPlayerChannel]: native platform audio playback
/// - [NativeAudioRecorderChannel]: native platform audio recording
///
/// ## Usage
///
/// ```dart
/// final audio = EngineScope.current.audioModule!;
/// await audio.player.play();
/// ```
class AudioModule extends CanvasModule {
  @override
  String get moduleId => 'audio';

  @override
  String get displayName => 'Audio';

  // ---------------------------------------------------------------------------
  // Module-owned services
  // ---------------------------------------------------------------------------

  /// Native audio playback channel.
  late final NativeAudioPlayerChannel player;

  /// Native audio recording channel.
  late final NativeAudioRecorderChannel recorder;

  // ---------------------------------------------------------------------------
  // CanvasModule contract
  // ---------------------------------------------------------------------------

  @override
  List<NodeDescriptor> get nodeDescriptors => const [];

  @override
  List<DrawingTool> createTools() => const [];

  @override
  bool get isInitialized => _initialized;
  bool _initialized = false;

  @override
  Future<void> initialize(ModuleContext context) async {
    if (_initialized) return;

    player = NativeAudioPlayerChannel.create();
    recorder = NativeAudioRecorderChannel.create();

    _initialized = true;
  }

  @override
  Future<void> dispose() async {
    if (!_initialized) return;
    await player.dispose();
    await recorder.dispose();
    _initialized = false;
  }
}
