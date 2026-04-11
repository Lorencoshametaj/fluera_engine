// ============================================================================
// 🎵 PEDAGOGICAL SOUND ENGINE — Contextual audio feedback system
//
// Spec: A13.4 (Sound Design), A13-04 → A13-07
//
// The Fluera sound system is **almost silent** — but precisely calibrated
// in the few moments where audio appears. All sounds are synthesized tones
// generated in-memory (zero file I/O, zero network), pre-cached at startup.
//
// Rules:
//   - A13-04: Always disableable + respects device silent mode
//   - A13-05: ZERO sounds during active writing (FlowGuard)
//   - A13-06: Pre-loaded at startup (≤2MB budget)
//   - A13-07: Volume proportional to moment importance
//
// Architecture:
//   - PedagogicalSoundEngine: singleton service
//   - PedagogicalSound: enum of all 7 sound moments
//   - ToneSynthesizer: generates PCM WAV buffers from frequency/duration specs
//   - Uses SystemSound.play() for haptic click, and platform channel for
//     synthesized tones via a lightweight PCM playback API
// ============================================================================

import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/services.dart';

/// 🎵 The 7 canonical sound moments in Fluera's pedagogical experience.
///
/// Each sound is precisely designed with specific frequency, duration,
/// and volume to match its cognitive significance.
enum PedagogicalSound {
  /// Tool change click — different per tool type.
  /// 100ms, 20% volume. "I know which tool I have without looking."
  toolChange,

  /// Recall Mode activation — low tone "curtain drops."
  /// 300ms, 15% volume. Single 200Hz sine wave.
  recallActivation,

  /// AI arrives (Socratic Dialogue) — two ascending notes.
  /// 400ms, 15% volume. C4→E4 piano-like tones.
  aiArrives,

  /// Node reveal (correct) — open, bright tone.
  /// 200ms, 20% volume. C4 (262Hz).
  revealCorrect,

  /// Node reveal (forgotten) — closed, somber tone.
  /// 200ms, 20% volume. Ab3 (208Hz).
  revealForgotten,

  /// Ghost Map scanning — sweep ascending synth.
  /// 1000ms, 10% volume. 200→800Hz sweep.
  ghostMapScan,

  /// Fog of War reveal — musical chord opening.
  /// 3000ms, 25% volume. Am→C (strings).
  fogOfWarReveal,
}

// ─────────────────────────────────────────────────────────────────────────────
// SOUND CONFIGURATION
// ─────────────────────────────────────────────────────────────────────────────

/// Configuration for each sound moment.
class _SoundConfig {
  /// Volume relative to system volume (0.0–1.0).
  final double volume;

  /// Duration in milliseconds.
  final int durationMs;

  /// Generator function that produces PCM samples.
  final Float64List Function(int sampleRate, int durationMs) generator;

  const _SoundConfig({
    required this.volume,
    required this.durationMs,
    required this.generator,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// TONE SYNTHESIZER — Pure Dart PCM generation
// ─────────────────────────────────────────────────────────────────────────────

/// 🔊 Generates PCM audio samples from mathematical waveforms.
///
/// All generation is pure Dart — no native calls, no file I/O.
/// Samples are 16-bit signed PCM at 44100Hz.
class ToneSynthesizer {
  static const int sampleRate = 44100;

  /// Generate a pure sine wave tone.
  static Float64List sine(int sampleRate, int durationMs, {
    required double frequency,
    double attack = 0.01,
    double release = 0.05,
  }) {
    final numSamples = (sampleRate * durationMs / 1000).round();
    final samples = Float64List(numSamples);
    final attackSamples = (sampleRate * attack).round();
    final releaseSamples = (sampleRate * release).round();

    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      double envelope = 1.0;

      // Attack envelope
      if (i < attackSamples) {
        envelope = i / attackSamples;
      }
      // Release envelope
      else if (i > numSamples - releaseSamples) {
        envelope = (numSamples - i) / releaseSamples;
      }

      samples[i] = math.sin(2 * math.pi * frequency * t) * envelope;
    }
    return samples;
  }

  /// Generate two sequential notes (for AI arrives: C4→E4).
  static Float64List twoNotes(int sampleRate, int durationMs, {
    required double freq1,
    required double freq2,
  }) {
    final half = durationMs ~/ 2;
    final note1 = sine(sampleRate, half, frequency: freq1, attack: 0.02, release: 0.04);
    final note2 = sine(sampleRate, half, frequency: freq2, attack: 0.02, release: 0.04);

    final combined = Float64List(note1.length + note2.length);
    combined.setAll(0, note1);
    combined.setAll(note1.length, note2);
    return combined;
  }

  /// Generate a frequency sweep (for Ghost Map scan: 200→800Hz).
  static Float64List sweep(int sampleRate, int durationMs, {
    required double startFreq,
    required double endFreq,
  }) {
    final numSamples = (sampleRate * durationMs / 1000).round();
    final samples = Float64List(numSamples);
    final attackSamples = (sampleRate * 0.05).round();
    final releaseSamples = (sampleRate * 0.2).round();

    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      final progress = i / numSamples;
      final freq = startFreq + (endFreq - startFreq) * progress;
      double envelope = 1.0;

      if (i < attackSamples) {
        envelope = i / attackSamples;
      } else if (i > numSamples - releaseSamples) {
        envelope = (numSamples - i) / releaseSamples;
      }

      // Softer synth pad: use lower harmonics
      samples[i] = (
        0.6 * math.sin(2 * math.pi * freq * t) +
        0.3 * math.sin(2 * math.pi * freq * 2 * t) * 0.3 +
        0.1 * math.sin(2 * math.pi * freq * 3 * t) * 0.1
      ) * envelope;
    }
    return samples;
  }

  /// Generate a chord (for Fog of War reveal: Am→C major).
  static Float64List chord(int sampleRate, int durationMs, {
    required List<double> frequencies,
    double attack = 0.1,
    double release = 0.5,
  }) {
    final numSamples = (sampleRate * durationMs / 1000).round();
    final samples = Float64List(numSamples);
    final attackSamples = (sampleRate * attack).round();
    final releaseSamples = (sampleRate * release).round();
    final freqCount = frequencies.length;
    final amplitude = 1.0 / freqCount; // Normalize

    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      double envelope = 1.0;

      if (i < attackSamples) {
        envelope = i / attackSamples;
      } else if (i > numSamples - releaseSamples) {
        final releasePos = (numSamples - i) / releaseSamples;
        envelope = releasePos * releasePos; // Quadratic release
      }

      double sum = 0.0;
      for (int f = 0; f < freqCount; f++) {
        sum += math.sin(2 * math.pi * frequencies[f] * t);
      }
      samples[i] = sum * amplitude * envelope;
    }
    return samples;
  }

  /// Generate a short click/pop (for tool change).
  static Float64List click(int sampleRate, int durationMs) {
    final numSamples = (sampleRate * durationMs / 1000).round();
    final samples = Float64List(numSamples);

    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      // Exponential decay click
      final decay = math.exp(-t * 40);
      // Mix of frequencies for a "click" sound
      samples[i] = (
        0.5 * math.sin(2 * math.pi * 1200 * t) +
        0.3 * math.sin(2 * math.pi * 2400 * t) +
        0.2 * math.sin(2 * math.pi * 4800 * t)
      ) * decay;
    }
    return samples;
  }

  /// Generate a C major triad with reverb (for "Sei pronto").
  static Float64List triad(int sampleRate, int durationMs) {
    // C4-E4-G4 with reverb-like decay
    const c4 = 261.63;
    const e4 = 329.63;
    const g4 = 392.0;

    final numSamples = (sampleRate * durationMs / 1000).round();
    final samples = Float64List(numSamples);
    final attackSamples = (sampleRate * 0.15).round();

    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      // Slow exponential decay (reverb-like)
      final decay = math.exp(-t * 1.2);
      double envelope = decay;

      if (i < attackSamples) {
        envelope *= i / attackSamples;
      }

      samples[i] = (
        0.35 * math.sin(2 * math.pi * c4 * t) +
        0.35 * math.sin(2 * math.pi * e4 * t) +
        0.30 * math.sin(2 * math.pi * g4 * t)
      ) * envelope;
    }
    return samples;
  }

  /// Convert Float64 samples to a WAV file byte buffer (16-bit PCM).
  ///
  /// Pre-generates the complete WAV at startup — zero allocation during play.
  static Uint8List toWav(Float64List samples, {double volume = 1.0}) {
    final numSamples = samples.length;
    final dataSize = numSamples * 2; // 16-bit = 2 bytes per sample
    final fileSize = 44 + dataSize;

    final buffer = ByteData(fileSize);
    int offset = 0;

    // WAV header
    // "RIFF"
    buffer.setUint8(offset++, 0x52);
    buffer.setUint8(offset++, 0x49);
    buffer.setUint8(offset++, 0x46);
    buffer.setUint8(offset++, 0x46);
    // File size - 8
    buffer.setUint32(offset, fileSize - 8, Endian.little);
    offset += 4;
    // "WAVE"
    buffer.setUint8(offset++, 0x57);
    buffer.setUint8(offset++, 0x41);
    buffer.setUint8(offset++, 0x56);
    buffer.setUint8(offset++, 0x45);
    // "fmt "
    buffer.setUint8(offset++, 0x66);
    buffer.setUint8(offset++, 0x6D);
    buffer.setUint8(offset++, 0x74);
    buffer.setUint8(offset++, 0x20);
    // Subchunk1 size (16 for PCM)
    buffer.setUint32(offset, 16, Endian.little);
    offset += 4;
    // Audio format (1 = PCM)
    buffer.setUint16(offset, 1, Endian.little);
    offset += 2;
    // Channels (1 = mono)
    buffer.setUint16(offset, 1, Endian.little);
    offset += 2;
    // Sample rate
    buffer.setUint32(offset, sampleRate, Endian.little);
    offset += 4;
    // Byte rate
    buffer.setUint32(offset, sampleRate * 2, Endian.little);
    offset += 4;
    // Block align
    buffer.setUint16(offset, 2, Endian.little);
    offset += 2;
    // Bits per sample
    buffer.setUint16(offset, 16, Endian.little);
    offset += 2;
    // "data"
    buffer.setUint8(offset++, 0x64);
    buffer.setUint8(offset++, 0x61);
    buffer.setUint8(offset++, 0x74);
    buffer.setUint8(offset++, 0x61);
    // Data size
    buffer.setUint32(offset, dataSize, Endian.little);
    offset += 4;

    // PCM data
    for (int i = 0; i < numSamples; i++) {
      final clamped = (samples[i] * volume * 32767).round().clamp(-32768, 32767);
      buffer.setInt16(offset, clamped, Endian.little);
      offset += 2;
    }

    return buffer.buffer.asUint8List();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PEDAGOGICAL SOUND ENGINE — Singleton service
// ─────────────────────────────────────────────────────────────────────────────

/// 🎵 Central sound engine for all pedagogical audio feedback.
///
/// **Usage:**
/// ```dart
/// // At startup:
/// await PedagogicalSoundEngine.instance.initialize();
///
/// // To play:
/// PedagogicalSoundEngine.instance.play(PedagogicalSound.recallActivation);
/// ```
///
/// **Integration with FlowGuard:**
/// The engine checks `isWritingSuppressed` before playing. The canvas
/// must set this flag via `suppressForWriting()` / `resumeFromWriting()`.
class PedagogicalSoundEngine {
  PedagogicalSoundEngine._();

  /// Singleton instance.
  static final PedagogicalSoundEngine instance = PedagogicalSoundEngine._();

  /// Platform channel for lightweight WAV playback.
  static const MethodChannel _channel = MethodChannel(
    'flueraengine.audio/sound_effects',
  );

  /// Whether sound effects are enabled (A13-04 toggle).
  bool _enabled = true;
  bool get isEnabled => _enabled;
  set isEnabled(bool value) => _enabled = value;

  /// Whether sounds are suppressed due to active writing (A13-05).
  bool _writingSuppressed = false;

  /// Pre-generated WAV buffers, keyed by [PedagogicalSound].
  final Map<PedagogicalSound, Uint8List> _cache = {};

  /// Whether the engine has been initialized.
  bool _initialized = false;
  bool get isInitialized => _initialized;

  /// Total bytes of cached audio.
  int _totalCacheBytes = 0;

  // ── PUBLIC API ──────────────────────────────────────────────────────────

  /// Initialize the sound engine — pre-generates all WAV buffers.
  ///
  /// This is idempotent and safe to call multiple times.
  /// Budget: ≤2MB total (A13-06).
  Future<void> initialize() async {
    if (_initialized) return;

    _totalCacheBytes = 0;

    // Generate all sounds
    for (final sound in PedagogicalSound.values) {
      final config = _configs[sound]!;
      final samples = config.generator(ToneSynthesizer.sampleRate, config.durationMs);
      final wav = ToneSynthesizer.toWav(samples, volume: config.volume);
      _cache[sound] = wav;
      _totalCacheBytes += wav.length;
    }

    _initialized = true;
  }

  /// Play a pedagogical sound effect.
  ///
  /// Respects:
  ///   - A13-04: `_enabled` toggle
  ///   - A13-05: `_writingSuppressed` (FlowGuard)
  ///   - A13-07: Volume is pre-baked into the WAV buffer
  ///
  /// This method is fire-and-forget — errors are silently swallowed.
  void play(PedagogicalSound sound) {
    if (!_enabled) return;
    if (!_initialized) return;
    if (_writingSuppressed) return;

    final wav = _cache[sound];
    if (wav == null) return;

    // Fire-and-forget playback via platform channel
    _channel.invokeMethod('playWav', {'data': wav}).catchError((_) {
      // Silent failure — sound effects are non-critical.
      // On platforms where the channel isn't implemented,
      // we degrade gracefully to silence.
    });
  }

  /// Suppress all sounds (called when pen touches canvas).
  ///
  /// Spec A13-05: "Nessun suono durante la scrittura attiva".
  void suppressForWriting() {
    _writingSuppressed = true;
  }

  /// Resume sounds after writing ends (2s cooldown via FlowGuard).
  void resumeFromWriting() {
    _writingSuppressed = false;
  }

  /// Total size of cached audio in bytes.
  int get totalCacheBytes => _totalCacheBytes;

  // ── SOUND CONFIGURATIONS ────────────────────────────────────────────────

  static final Map<PedagogicalSound, _SoundConfig> _configs = {
    // 1. Tool change — short click, barely audible
    PedagogicalSound.toolChange: _SoundConfig(
      volume: 0.20,
      durationMs: 100,
      generator: (sr, ms) => ToneSynthesizer.click(sr, ms),
    ),

    // 2. Recall activation — low 200Hz tone, slow attack
    PedagogicalSound.recallActivation: _SoundConfig(
      volume: 0.15,
      durationMs: 300,
      generator: (sr, ms) => ToneSynthesizer.sine(
        sr, ms, frequency: 200, attack: 0.08, release: 0.1,
      ),
    ),

    // 3. AI arrives — C4→E4 two ascending notes
    PedagogicalSound.aiArrives: _SoundConfig(
      volume: 0.15,
      durationMs: 400,
      generator: (sr, ms) => ToneSynthesizer.twoNotes(
        sr, ms, freq1: 261.63, freq2: 329.63,
      ),
    ),

    // 4. Reveal correct — C4 open tone
    PedagogicalSound.revealCorrect: _SoundConfig(
      volume: 0.20,
      durationMs: 200,
      generator: (sr, ms) => ToneSynthesizer.sine(
        sr, ms, frequency: 261.63, attack: 0.01, release: 0.06,
      ),
    ),

    // 5. Reveal forgotten — Ab3 closed tone
    PedagogicalSound.revealForgotten: _SoundConfig(
      volume: 0.20,
      durationMs: 200,
      generator: (sr, ms) => ToneSynthesizer.sine(
        sr, ms, frequency: 207.65, attack: 0.01, release: 0.06,
      ),
    ),

    // 6. Ghost Map scanning — ascending sweep
    PedagogicalSound.ghostMapScan: _SoundConfig(
      volume: 0.10,
      durationMs: 1000,
      generator: (sr, ms) => ToneSynthesizer.sweep(
        sr, ms, startFreq: 200, endFreq: 800,
      ),
    ),

    // 7. Fog of War reveal — Am→C chord opening
    PedagogicalSound.fogOfWarReveal: _SoundConfig(
      volume: 0.25,
      durationMs: 3000,
      generator: (sr, ms) {
        // Am chord (A3-C4-E4) transitioning to C major (C4-E4-G4)
        // Simple approach: blend both chords over time
        final numSamples = (sr * ms / 1000).round();
        final samples = Float64List(numSamples);
        final attackSamples = (sr * 0.2).round();
        final releaseSamples = (sr * 0.8).round();

        // Am: A3=220, C4=261.63, E4=329.63
        // C:  C4=261.63, E4=329.63, G4=392.0
        const a3 = 220.0, c4 = 261.63, e4 = 329.63, g4 = 392.0;

        for (int i = 0; i < numSamples; i++) {
          final t = i / sr;
          final progress = i / numSamples;
          // Crossfade: Am fades out, C fades in
          final amWeight = 1.0 - progress;
          final cWeight = progress;

          double envelope = 1.0;
          if (i < attackSamples) {
            envelope = i / attackSamples;
          } else if (i > numSamples - releaseSamples) {
            final r = (numSamples - i) / releaseSamples;
            envelope = r * r; // Quadratic release
          }

          final amChord =
            math.sin(2 * math.pi * a3 * t) * amWeight +
            math.sin(2 * math.pi * c4 * t) +
            math.sin(2 * math.pi * e4 * t);
          final cChord =
            math.sin(2 * math.pi * c4 * t) +
            math.sin(2 * math.pi * e4 * t) +
            math.sin(2 * math.pi * g4 * t) * cWeight;

          samples[i] = (amChord * amWeight + cChord * cWeight) / 3.0 * envelope;
        }
        return samples;
      },
    ),
  };
}
