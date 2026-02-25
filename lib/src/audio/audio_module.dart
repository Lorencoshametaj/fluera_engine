import '../core/modules/canvas_module.dart';
import '../tools/base/tool_interface.dart';
import 'platform_channels/audio_player_channel.dart';
import 'platform_channels/audio_recorder_channel.dart';

// =============================================================================
// AUDIO MODULE
// =============================================================================

/// 🎵 Self-contained audio module for the Nebula Engine canvas.
///
/// Encapsulates all audio functionality:
/// - [AudioPlayerChannel]: native platform audio playback
/// - [AudioRecorderChannel]: native platform audio recording
/// - Audio node types (future: AudioNode in scene graph)
///
/// ## Usage
///
/// ```dart
/// await EngineScope.current.moduleRegistry.register(AudioModule());
///
/// final audio = EngineScope.current.moduleRegistry.findModule<AudioModule>()!;
/// await audio.player.play('asset://sounds/click.wav');
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
  late final AudioPlayerChannel player;

  /// Native audio recording channel.
  late final AudioRecorderChannel recorder;

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

    player = AudioPlayerChannel();
    recorder = AudioRecorderChannel();

    _initialized = true;
  }

  @override
  Future<void> dispose() async {
    if (!_initialized) return;
    player.dispose();
    recorder.dispose();
    _initialized = false;
  }
}
