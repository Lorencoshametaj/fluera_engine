import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import './sherpa_model_manager.dart';
import './platform_channels/audio_recorder_channel.dart';
import './punctuation_processor.dart';

// =============================================================================
// 🎤 STREAMING TRANSCRIPTION SERVICE (v3 — Architectural Optimizations)
//
// Real-time speech-to-text using Sherpa-ONNX OnlineRecognizer.
//
// Optimizations:
// v1: Basic streaming
// v2: Buffer pooling, text throttle, Italian endpoints
// v3: VAD gating, event-driven decode, chunk accumulation, model pre-warming
// =============================================================================

/// Live streaming transcription service using Sherpa-ONNX OnlineRecognizer.
class StreamingTranscriptionService {
  StreamingTranscriptionService._();

  static final StreamingTranscriptionService instance =
      StreamingTranscriptionService._();

  // =========================================================================
  // State
  // =========================================================================
  bool _isActive = false;
  sherpa.OnlineRecognizer? _recognizer;
  sherpa.OnlineStream? _stream;
  NativeAudioRecorderChannel? _recorderChannel;
  StreamSubscription? _pcmSubscription;

  // 🚀 v2: Pre-allocated Float32 buffer pool (3200 samples = 200ms @ 16kHz)
  static const int _maxChunkSamples = 3200;
  final Float32List _float32Pool = Float32List(_maxChunkSamples);

  // 🚀 v2: Throttled text emission (200ms debounce)
  DateTime _lastTextEmit = DateTime.now();
  static const Duration _textThrottleInterval = Duration(milliseconds: 200);
  String _pendingText = '';

  // 🚀 v3: Chunk accumulation buffer (min 80ms = 1280 samples @ 16kHz)
  static const int _minChunkSamples = 1280;
  final Float32List _accumBuffer = Float32List(_maxChunkSamples * 2);
  int _accumCount = 0;

  // 🚀 v3: VAD gating — skip feeding silence to recognizer
  // 🔧 DISABLED: was blocking all audio after decimation fix
  // static const double _vadThreshold = 0.015;
  int _silentChunks = 0;
  // static const int _maxSilentChunksBeforeGate = 15;
  int _debugChunkCount = 0;

  // 🚀 v3: Model pre-warming cache
  static sherpa.OnlineRecognizerConfig? _cachedConfig;
  static String? _cachedModelDir;

  // ✏️ v4: Automatic punctuation
  final PunctuationProcessor _punctuation = PunctuationProcessor();

  // Output
  final _textController = StreamController<String>.broadcast();
  String _currentText = '';
  String _committedText = '';

  /// Whether the streaming service is currently active.
  bool get isActive => _isActive;

  /// Stream of live transcription text updates (throttled to ~5/sec).
  Stream<String> get textStream => _textController.stream;

  /// The current accumulated transcription text.
  String get currentText => _committedText + _currentText;

  // =========================================================================
  // 🔥 v3: Model Pre-warming
  // =========================================================================

  /// Pre-warm the streaming model after download.
  /// Call this after model download completes to eliminate cold-start latency.
  /// Creates and caches the recognizer config (but not the recognizer itself,
  /// since FFI resources should be created fresh per session).
  static Future<void> prewarmModel() async {
    final modelManager = SherpaModelManager.instance;
    final modelDir = await modelManager.getModelDirectory(
      SherpaModelType.zipformerStreaming,
    );
    if (modelDir == null) return;

    _cachedModelDir = modelDir;
    _cachedConfig = sherpa.OnlineRecognizerConfig(
      model: sherpa.OnlineModelConfig(
        transducer: sherpa.OnlineTransducerModelConfig(
          encoder: '$modelDir/encoder-epoch-99-avg-1.onnx',
          decoder: '$modelDir/decoder-epoch-99-avg-1.onnx',
          joiner: '$modelDir/joiner-epoch-99-avg-1.onnx',
        ),
        tokens: '$modelDir/tokens.txt',
        numThreads: 2,
        provider: 'cpu',
        debug: false,
      ),
      enableEndpoint: true,
      rule1MinTrailingSilence: 2.8,
      rule2MinTrailingSilence: 1.4,
      rule3MinUtteranceLength: 25,
    );

    debugPrint('🎤 Streaming model pre-warmed: $modelDir');
  }

  // =========================================================================
  // Start / Stop
  // =========================================================================

  /// Start live streaming transcription.
  Future<void> start({
    required NativeAudioRecorderChannel recorderChannel,
    String language = 'auto',
  }) async {
    if (_isActive) return;

    // Use cached config or build fresh
    sherpa.OnlineRecognizerConfig config;
    if (_cachedConfig != null) {
      config = _cachedConfig!;
    } else {
      final modelManager = SherpaModelManager.instance;
      final modelDir = await modelManager.getModelDirectory(
        SherpaModelType.zipformerStreaming,
      );
      if (modelDir == null) {
        throw StateError(
          'Streaming model not downloaded. Call SherpaModelManager.downloadModel() first.',
        );
      }
      _cachedModelDir = modelDir;
      config = sherpa.OnlineRecognizerConfig(
        model: sherpa.OnlineModelConfig(
          transducer: sherpa.OnlineTransducerModelConfig(
            encoder: '$modelDir/encoder-epoch-99-avg-1.onnx',
            decoder: '$modelDir/decoder-epoch-99-avg-1.onnx',
            joiner: '$modelDir/joiner-epoch-99-avg-1.onnx',
          ),
          tokens: '$modelDir/tokens.txt',
          numThreads: 2,
          provider: 'cpu',
          debug: false,
        ),
        enableEndpoint: true,
        rule1MinTrailingSilence: 2.8,
        rule2MinTrailingSilence: 1.4,
        rule3MinUtteranceLength: 25,
      );
      _cachedConfig = config;
    }

    _recorderChannel = recorderChannel;
    _committedText = '';
    _currentText = '';
    _pendingText = '';
    _accumCount = 0;
    _silentChunks = 0;
    _punctuation.reset();

    try {
      // 🔧 Ensure sherpa-onnx FFI bindings are initialized
      sherpa.initBindings();

      _recognizer = sherpa.OnlineRecognizer(config);
      _stream = _recognizer!.createStream();

      // Enable native PCM stream
      await recorderChannel.enablePcmStream();

      // Listen for PCM chunks — event-driven (no timer!)
      _pcmSubscription = recorderChannel.pcmStream.listen(
        _onPcmChunk,
        onError: (e) {
          debugPrint('🎤 PCM stream error: $e');
        },
      );

      _isActive = true;
      _lastTextEmit = DateTime.now();
      debugPrint('🎤 Streaming transcription started (v3 optimized)');
    } catch (e) {
      _cleanup();
      rethrow;
    }
  }

  /// Stop streaming transcription and return the final accumulated text.
  Future<String> stop() async {
    if (!_isActive) return currentText;

    // Flush any accumulated samples
    _flushAccumBuffer();

    // Final decode pass
    _stream?.inputFinished();
    _runDecode(force: true);

    final finalText = currentText;

    // Disable native PCM stream
    try {
      await _recorderChannel?.disablePcmStream();
    } catch (_) {}

    _cleanup();
    _isActive = false;

    debugPrint('🎤 Streaming transcription stopped. Final: $finalText');
    return finalText;
  }

  // =========================================================================
  // 🎤 PCM Processing Pipeline (v3: VAD → Accumulate → Decode)
  // =========================================================================

  /// Process an incoming PCM chunk.
  /// Pipeline: Int16→Float32 → VAD gate → accumulate → acceptWaveform → decode
  void _onPcmChunk(dynamic data) {
    if (!_isActive || _stream == null) return;

    try {
      final Uint8List bytes;
      if (data is Uint8List) {
        bytes = data;
      } else if (data is List<int>) {
        bytes = Uint8List.fromList(data);
      } else {
        return;
      }

      // ⚠️ CRITICAL: EventChannel sends bytes as VIEWS with non-aligned offsets
      // (e.g. offset=5). Int16 requires 2-byte alignment.
      // bytes.buffer.asInt16List() reads from offset 0 = WRONG DATA.
      // bytes.buffer.asInt16List(bytes.offsetInBytes, ...) crashes on odd offsets.
      // FIX: copy to aligned buffer first, then interpret as Int16.
      final alignedBytes = Uint8List.fromList(bytes);
      final int16Data = alignedBytes.buffer.asInt16List();
      final sampleCount = int16Data.length;
      if (sampleCount == 0) return;

      // ─── Step 1: Convert Int16 → Float32 + downsample 48kHz → 16kHz ───
      // Audio is recorded at 48kHz but model expects 16kHz.
      // Simple 3:1 decimation (take every 3rd sample) — works well for speech.
      final int convertCount;
      final decimationFactor = 3; // 48000 / 16000 = 3
      final decimatedCount = sampleCount ~/ decimationFactor;
      if (decimatedCount <= _maxChunkSamples && decimatedCount > 0) {
        for (int i = 0; i < decimatedCount; i++) {
          _float32Pool[i] = int16Data[i * decimationFactor] / 32768.0;
        }
        convertCount = decimatedCount;
      } else if (decimatedCount > _maxChunkSamples) {
        // Shouldn't happen, but handle gracefully — process first chunk
        for (int i = 0; i < _maxChunkSamples; i++) {
          _float32Pool[i] = int16Data[i * decimationFactor] / 32768.0;
        }
        convertCount = _maxChunkSamples;
      } else {
        return; // Too few samples
      }

      // ─── Step 2: Debug logging (VAD disabled for now) ───
      _debugChunkCount++;
      if (_debugChunkCount % 50 == 1) {
        debugPrint('🎤 Chunk #$_debugChunkCount: $convertCount samples (from ${int16Data.length} raw)');
      }

      // ─── Step 3: Feed directly to recognizer (no accumulation) ───
      // Create a fresh copy — pool/view may get invalidated before FFI copies
      final samples = Float32List(convertCount);
      for (int i = 0; i < convertCount; i++) {
        samples[i] = _float32Pool[i];
      }
      _stream!.acceptWaveform(samples: samples, sampleRate: 16000);
      _flushCount++;

      // ─── Step 4: Decode ───
      _runDecode();
    } catch (e) {
      debugPrint('🎤 PCM processing error: $e');
    }
  }

  int _flushCount = 0;

  /// Flush the accumulation buffer into the recognizer stream.
  void _flushAccumBuffer() {
    if (_accumCount == 0 || _stream == null) return;

    final samples = Float32List.sublistView(_accumBuffer, 0, _accumCount);
    _stream!.acceptWaveform(samples: samples, sampleRate: 16000);
    _flushCount++;
    if (_flushCount % 20 == 1) {
      debugPrint('🎤 Flush #$_flushCount: $_accumCount samples fed to recognizer');
    }
    _accumCount = 0;
  }

  /// Run decode + result extraction + endpoint check.
  /// Event-driven (called after each acceptWaveform, not on a timer).
  void _runDecode({bool force = false}) {
    if (!_isActive || _recognizer == null || _stream == null) return;

    try {
      while (_recognizer!.isReady(_stream!)) {
        _recognizer!.decode(_stream!);
      }

      final result = _recognizer!.getResult(_stream!);
      final text = result.text.trim();

      // Debug: log decode results periodically
      if (_flushCount % 10 == 1) {
        debugPrint('🎤 Decode @$_flushCount: isReady=${_recognizer!.isReady(_stream!)} text="$text"');
      }

      if (text.isNotEmpty) {
        // ✏️ Apply punctuation to partial result (capitalization only)
        _currentText = _punctuation.onPartial(text);

        // Throttled text emission
        final now = DateTime.now();
        final fullText = currentText;
        if (force ||
            now.difference(_lastTextEmit) >= _textThrottleInterval ||
            fullText != _pendingText) {
          _pendingText = fullText;
          _lastTextEmit = now;
          if (!_textController.isClosed) {
            _textController.add(fullText);
          }
        }
      }

      // Check for endpoint (utterance boundary)
      if (_recognizer!.isEndpoint(_stream!)) {
        if (_currentText.isNotEmpty) {
          // ✏️ Apply full punctuation at endpoint
          final punctuated = _punctuation.onEndpoint(_currentText);
          _committedText += '$punctuated ';
          _currentText = '';
        }
        _recognizer!.reset(_stream!);
      }
    } catch (e) {
      debugPrint('🎤 Decode error: $e');
    }
  }

  // =========================================================================
  // Cleanup
  // =========================================================================

  void _cleanup() {
    _pcmSubscription?.cancel();
    _pcmSubscription = null;

    _stream?.free();
    _stream = null;

    _recognizer?.free();
    _recognizer = null;

    _recorderChannel = null;
    _accumCount = 0;
    _silentChunks = 0;
  }

  void dispose() {
    _cleanup();
    _textController.close();
  }
}
