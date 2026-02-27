/// 🎵 NATIVE AUDIO MODELS
/// Models for the native audio system
library;

/// Player states
enum AudioPlayerState {
  idle,
  loading,
  ready,
  playing,
  paused,
  stopped,
  completed,
  error,
}

/// Recorder states
enum AudioRecorderState { idle, recording, paused, stopped, error }

/// Supported audio formats
enum AudioFormat { mp3, m4a, aac, wav, opus }

/// Loop modes
enum AudioLoopMode { off, one, all }

/// iOS audio session configuration
enum AudioSessionCategory {
  ambient,
  soloAmbient,
  playback,
  record,
  playAndRecord,
  multiRoute,
}

/// iOS audio session category options
enum AudioSessionCategoryOption {
  mixWithOthers,
  duckOthers,
  allowBluetooth,
  allowBluetoothA2DP,
  allowAirPlay,
  defaultToSpeaker,
}

/// Configuration for recording
class AudioRecordConfig {
  final AudioFormat format;
  final int sampleRate;
  final int bitRate;
  final int numChannels;
  final bool noiseSuppression;
  final bool echoCancellation;
  final bool autoGain;

  /// High-pass filter cutoff frequency in Hz (0 = disabled).
  /// Cuts low-frequency noise like pen/finger contact on screen.
  final int highPassFilterHz;

  /// Compressor — evens out volume dynamics (quiet ↑, loud ↓).
  final bool compressor;

  /// Normalization — brings overall volume to a standard level (-3dB).
  final bool normalization;

  const AudioRecordConfig({
    this.format = AudioFormat.m4a,
    this.sampleRate = 48000,
    this.bitRate = 256000,
    this.numChannels = 1,
    this.noiseSuppression = true,
    this.echoCancellation = true,
    this.autoGain = true,
    this.highPassFilterHz = 250,
    this.compressor = true,
    this.normalization = true,
  });

  /// 🎙️ Standard quality (smaller files, basic noise reduction)
  static const standard = AudioRecordConfig(
    sampleRate: 44100,
    bitRate: 128000,
    noiseSuppression: true,
    echoCancellation: false,
    autoGain: false,
    highPassFilterHz: 0,
    compressor: false,
    normalization: false,
  );

  /// 🎵 High quality (recommended — balanced quality + noise reduction)
  static const high = AudioRecordConfig(
    sampleRate: 48000,
    bitRate: 256000,
    noiseSuppression: true,
    echoCancellation: true,
    autoGain: true,
  );

  /// 🎤 Studio quality (maximum fidelity, all filters enabled)
  static const studio = AudioRecordConfig(
    sampleRate: 48000,
    bitRate: 320000,
    noiseSuppression: true,
    echoCancellation: true,
    autoGain: true,
  );

  /// Whether any post-processing is needed.
  bool get needsPostProcessing =>
      highPassFilterHz > 0 || compressor || normalization;

  AudioRecordConfig copyWith({
    AudioFormat? format,
    int? sampleRate,
    int? bitRate,
    int? numChannels,
    bool? noiseSuppression,
    bool? echoCancellation,
    bool? autoGain,
    int? highPassFilterHz,
    bool? compressor,
    bool? normalization,
  }) {
    return AudioRecordConfig(
      format: format ?? this.format,
      sampleRate: sampleRate ?? this.sampleRate,
      bitRate: bitRate ?? this.bitRate,
      numChannels: numChannels ?? this.numChannels,
      noiseSuppression: noiseSuppression ?? this.noiseSuppression,
      echoCancellation: echoCancellation ?? this.echoCancellation,
      autoGain: autoGain ?? this.autoGain,
      highPassFilterHz: highPassFilterHz ?? this.highPassFilterHz,
      compressor: compressor ?? this.compressor,
      normalization: normalization ?? this.normalization,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'format': format.name,
      'sampleRate': sampleRate,
      'bitRate': bitRate,
      'numChannels': numChannels,
      'noiseSuppression': noiseSuppression,
      'echoCancellation': echoCancellation,
      'autoGain': autoGain,
      'highPassFilterHz': highPassFilterHz,
      'compressor': compressor,
      'normalization': normalization,
    };
  }

  factory AudioRecordConfig.fromMap(Map<String, dynamic> map) {
    return AudioRecordConfig(
      format: AudioFormat.values.firstWhere(
        (e) => e.name == map['format'],
        orElse: () => AudioFormat.m4a,
      ),
      sampleRate: map['sampleRate'] ?? 48000,
      bitRate: map['bitRate'] ?? 256000,
      numChannels: map['numChannels'] ?? 1,
      noiseSuppression: map['noiseSuppression'] ?? true,
      echoCancellation: map['echoCancellation'] ?? true,
      autoGain: map['autoGain'] ?? true,
      highPassFilterHz: map['highPassFilterHz'] ?? 250,
      compressor: map['compressor'] ?? true,
      normalization: map['normalization'] ?? true,
    );
  }
}

/// Audio track information
class AudioTrackInfo {
  final String? title;
  final String? artist;
  final String? album;
  final Duration? duration;
  final String? artworkUrl;

  const AudioTrackInfo({
    this.title,
    this.artist,
    this.album,
    this.duration,
    this.artworkUrl,
  });

  factory AudioTrackInfo.fromMap(Map<String, dynamic> map) {
    return AudioTrackInfo(
      title: map['title'],
      artist: map['artist'],
      album: map['album'],
      duration:
          map['duration'] != null
              ? Duration(milliseconds: map['duration'])
              : null,
      artworkUrl: map['artworkUrl'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'artist': artist,
      'album': album,
      'duration': duration?.inMilliseconds,
      'artworkUrl': artworkUrl,
    };
  }
}

/// Player state with all info
class AudioPlayerStateInfo {
  final AudioPlayerState state;
  final Duration position;
  final Duration? duration;
  final double volume;
  final double speed;
  final AudioLoopMode loopMode;
  final bool isBuffering;
  final String? error;

  const AudioPlayerStateInfo({
    required this.state,
    required this.position,
    this.duration,
    this.volume = 1.0,
    this.speed = 1.0,
    this.loopMode = AudioLoopMode.off,
    this.isBuffering = false,
    this.error,
  });

  bool get isPlaying => state == AudioPlayerState.playing;
  bool get isPaused => state == AudioPlayerState.paused;
  bool get isIdle => state == AudioPlayerState.idle;
  bool get hasError => state == AudioPlayerState.error;

  AudioPlayerStateInfo copyWith({
    AudioPlayerState? state,
    Duration? position,
    Duration? duration,
    double? volume,
    double? speed,
    AudioLoopMode? loopMode,
    bool? isBuffering,
    String? error,
  }) {
    return AudioPlayerStateInfo(
      state: state ?? this.state,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      volume: volume ?? this.volume,
      speed: speed ?? this.speed,
      loopMode: loopMode ?? this.loopMode,
      isBuffering: isBuffering ?? this.isBuffering,
      error: error ?? this.error,
    );
  }

  factory AudioPlayerStateInfo.fromMap(Map<String, dynamic> map) {
    return AudioPlayerStateInfo(
      state: AudioPlayerState.values.firstWhere(
        (e) => e.name == map['state'],
        orElse: () => AudioPlayerState.idle,
      ),
      position: Duration(milliseconds: map['position'] ?? 0),
      duration:
          map['duration'] != null
              ? Duration(milliseconds: map['duration'])
              : null,
      volume: (map['volume'] ?? 1.0).toDouble(),
      speed: (map['speed'] ?? 1.0).toDouble(),
      loopMode: AudioLoopMode.values.firstWhere(
        (e) => e.name == map['loopMode'],
        orElse: () => AudioLoopMode.off,
      ),
      isBuffering: map['isBuffering'] ?? false,
      error: map['error'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'state': state.name,
      'position': position.inMilliseconds,
      'duration': duration?.inMilliseconds,
      'volume': volume,
      'speed': speed,
      'loopMode': loopMode.name,
      'isBuffering': isBuffering,
      'error': error,
    };
  }
}

/// Recording amplitude
class AudioAmplitude {
  final double current;
  final double max;

  const AudioAmplitude({required this.current, this.max = 0.0});

  factory AudioAmplitude.fromMap(Map<String, dynamic> map) {
    return AudioAmplitude(
      current: (map['current'] ?? 0.0).toDouble(),
      max: (map['max'] ?? 0.0).toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {'current': current, 'max': max};
  }
}
