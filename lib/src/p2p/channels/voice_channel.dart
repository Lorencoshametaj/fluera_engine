// ============================================================================
// 🎙️ VOICE CHANNEL — Audio state management for P2P teaching (A4-05, P7-14)
//
// Manages voice channel state during Mode 7b (Teaching Reciprocal):
//   - Mute/unmute toggle
//   - Speaking indicator (VAD — Voice Activity Detection)
//   - Audio level metering
//   - Push-to-talk option
//
// No audio processing — the host app provides the actual WebRTC audio
// via P2PTransport. This controller manages the UI state.
//
// Spec constraints:
//   - Latency ≤200ms (A4-05)
//   - Opus codec, 24kbps (A4-05)
//   - No recording allowed (P7-18)
//
// ARCHITECTURE: Pure model — no audio, no platform dependencies.
// THREAD SAFETY: Main isolate only.
// ============================================================================

import 'package:flutter/foundation.dart';

/// 🎙️ Voice channel state.
enum VoiceChannelState {
  /// Not initialized / unavailable.
  unavailable,

  /// Ready but not started.
  ready,

  /// Active — audio flowing.
  active,

  /// Temporarily muted by local user.
  muted,

  /// Error (permission denied, hardware failure).
  error,
}

/// 🎙️ Voice channel input mode.
enum VoiceInputMode {
  /// Always-on voice (default for 7b).
  openMic,

  /// Push-to-talk (accessibility option).
  pushToTalk,
}

/// 🎙️ Voice Channel Controller (A4-05, P7-14).
///
/// Manages the UI state of the voice channel during P2P teaching.
/// The actual audio is handled by the host app's WebRTC implementation.
///
/// Usage:
/// ```dart
/// final voice = VoiceChannelController();
///
/// // Start the voice channel
/// voice.start();
///
/// // Toggle mute
/// voice.toggleMute();
///
/// // Update speaking indicator (from WebRTC VAD callback)
/// voice.updateLocalSpeaking(true);
///
/// // Listen to state changes
/// voice.addListener(() {
///   print('Muted: ${voice.isLocalMuted}');
///   print('Speaking: ${voice.isLocalSpeaking}');
/// });
/// ```
class VoiceChannelController extends ChangeNotifier {
  /// Current state.
  VoiceChannelState _state = VoiceChannelState.unavailable;
  VoiceChannelState get state => _state;

  /// Input mode.
  VoiceInputMode _inputMode = VoiceInputMode.openMic;
  VoiceInputMode get inputMode => _inputMode;

  /// Whether local microphone is muted.
  bool _isLocalMuted = false;
  bool get isLocalMuted => _isLocalMuted;

  /// Whether remote peer is muted (their choice).
  bool _isRemoteMuted = false;
  bool get isRemoteMuted => _isRemoteMuted;

  /// Whether local user is speaking (from VAD).
  bool _isLocalSpeaking = false;
  bool get isLocalSpeaking => _isLocalSpeaking;

  /// Whether remote peer is speaking (from VAD).
  bool _isRemoteSpeaking = false;
  bool get isRemoteSpeaking => _isRemoteSpeaking;

  /// Local audio level (0.0 – 1.0).
  double _localAudioLevel = 0.0;
  double get localAudioLevel => _localAudioLevel;

  /// Remote audio level (0.0 – 1.0).
  double _remoteAudioLevel = 0.0;
  double get remoteAudioLevel => _remoteAudioLevel;

  /// Whether push-to-talk is currently pressed (only in PTT mode).
  bool _isPttPressed = false;
  bool get isPttPressed => _isPttPressed;

  /// Whether the channel is currently active and transmitting.
  bool get isActive => _state == VoiceChannelState.active;

  /// Whether audio is effectively flowing from local mic.
  bool get isTransmitting {
    if (_state != VoiceChannelState.active &&
        _state != VoiceChannelState.muted) {
      return false;
    }
    if (_isLocalMuted) return false;
    if (_inputMode == VoiceInputMode.pushToTalk && !_isPttPressed) return false;
    return true;
  }

  // ─── Lifecycle ──────────────────────────────────────────────────────

  /// Mark the voice channel as ready (permission granted, hardware available).
  void setReady() {
    _state = VoiceChannelState.ready;
    notifyListeners();
  }

  /// Start the voice channel.
  void start() {
    if (_state == VoiceChannelState.unavailable ||
        _state == VoiceChannelState.error) {
      return;
    }
    _state = VoiceChannelState.active;
    _isLocalMuted = false;
    notifyListeners();
  }

  /// Stop the voice channel.
  void stop() {
    _state = VoiceChannelState.ready;
    _isLocalSpeaking = false;
    _isRemoteSpeaking = false;
    _localAudioLevel = 0;
    _remoteAudioLevel = 0;
    notifyListeners();
  }

  /// Report an error.
  void setError() {
    _state = VoiceChannelState.error;
    notifyListeners();
  }

  // ─── Mute / Unmute ─────────────────────────────────────────────────

  /// Toggle local mute.
  void toggleMute() {
    _isLocalMuted = !_isLocalMuted;
    _state = _isLocalMuted
        ? VoiceChannelState.muted
        : VoiceChannelState.active;
    notifyListeners();
  }

  /// Set local mute explicitly.
  void setMuted(bool muted) {
    if (_isLocalMuted == muted) return;
    _isLocalMuted = muted;
    _state = muted ? VoiceChannelState.muted : VoiceChannelState.active;
    notifyListeners();
  }

  /// Update remote mute state (received from peer).
  void updateRemoteMuted(bool muted) {
    if (_isRemoteMuted == muted) return;
    _isRemoteMuted = muted;
    notifyListeners();
  }

  // ─── Speaking / Audio Level ────────────────────────────────────────

  /// Update local speaking indicator (from WebRTC VAD callback).
  void updateLocalSpeaking(bool speaking) {
    if (_isLocalSpeaking == speaking) return;
    _isLocalSpeaking = speaking;
    notifyListeners();
  }

  /// Update remote speaking indicator.
  void updateRemoteSpeaking(bool speaking) {
    if (_isRemoteSpeaking == speaking) return;
    _isRemoteSpeaking = speaking;
    notifyListeners();
  }

  /// Update local audio level (0.0 – 1.0).
  void updateLocalAudioLevel(double level) {
    _localAudioLevel = level.clamp(0.0, 1.0);
    // Don't notify on every level change (too frequent).
    // UI should poll localAudioLevel in animation frame.
  }

  /// Update remote audio level (0.0 – 1.0).
  void updateRemoteAudioLevel(double level) {
    _remoteAudioLevel = level.clamp(0.0, 1.0);
  }

  // ─── Push-to-Talk ──────────────────────────────────────────────────

  /// Set input mode.
  void setInputMode(VoiceInputMode mode) {
    _inputMode = mode;
    notifyListeners();
  }

  /// Press push-to-talk (start transmitting).
  void pttPress() {
    _isPttPressed = true;
    notifyListeners();
  }

  /// Release push-to-talk (stop transmitting).
  void pttRelease() {
    _isPttPressed = false;
    notifyListeners();
  }

  // ─── Reset ─────────────────────────────────────────────────────────

  /// Reset all state.
  void reset() {
    _state = VoiceChannelState.unavailable;
    _isLocalMuted = false;
    _isRemoteMuted = false;
    _isLocalSpeaking = false;
    _isRemoteSpeaking = false;
    _localAudioLevel = 0;
    _remoteAudioLevel = 0;
    _isPttPressed = false;
    _inputMode = VoiceInputMode.openMic;
    notifyListeners();
  }
}
