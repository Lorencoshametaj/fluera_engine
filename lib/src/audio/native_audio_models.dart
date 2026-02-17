/// 🎵 NATIVE AUDIO MODELS
/// Modelli for the sistema audio nativo
library;

/// Stati del player
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

/// Stati del recorder
enum AudioRecorderState { idle, recording, paused, stopped, error }

/// Formati audio supportati
enum AudioFormat { mp3, m4a, aac, wav, opus }

/// Modalità di loop
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

/// Opzioni audio session iOS
enum AudioSessionCategoryOption {
  mixWithOthers,
  duckOthers,
  allowBluetooth,
  allowBluetoothA2DP,
  allowAirPlay,
  defaultToSpeaker,
}

/// Configuretion per recording
class AudioRecordConfig {
  final AudioFormat format;
  final int sampleRate;
  final int bitRate;
  final int numChannels;

  const AudioRecordConfig({
    this.format = AudioFormat.m4a,
    this.sampleRate = 44100,
    this.bitRate = 128000,
    this.numChannels = 1,
  });

  Map<String, dynamic> toMap() {
    return {
      'format': format.name,
      'sampleRate': sampleRate,
      'bitRate': bitRate,
      'numChannels': numChannels,
    };
  }

  factory AudioRecordConfig.fromMap(Map<String, dynamic> map) {
    return AudioRecordConfig(
      format: AudioFormat.values.firstWhere(
        (e) => e.name == map['format'],
        orElse: () => AudioFormat.m4a,
      ),
      sampleRate: map['sampleRate'] ?? 44100,
      bitRate: map['bitRate'] ?? 128000,
      numChannels: map['numChannels'] ?? 1,
    );
  }
}

/// Informazioni sulla traccia audio
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

/// Stato del player con tutte le info
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
