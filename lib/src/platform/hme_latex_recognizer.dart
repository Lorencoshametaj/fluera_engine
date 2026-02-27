import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'onnx_stub_web.dart'
    if (dart.library.ffi) 'package:onnxruntime_v2/onnxruntime_v2.dart';
import '../utils/safe_path_provider.dart';

import '../core/latex/ink_stroke_data.dart';
import 'ink_rasterizer.dart';
import 'latex_recognition_bridge.dart';

/// 🧮 HME LaTeX Recognizer — Encoder-Decoder with Attention.
///
/// Uses two ONNX models for on-device handwritten math recognition:
///   - **Encoder**: image [1,1,H,W] → features [1,N,D]
///   - **Decoder**: (features, tokens) → next-token logits (autoregressive)
///
/// The autoregressive loop runs in Dart — each decoder step is a single
/// ONNX call with fixed-shape I/O.
///
/// ```dart
/// final recognizer = HmeLatexRecognizer();
/// await recognizer.initialize();
/// final result = await recognizer.recognizeImage(pngBytes);
/// print(result.latexString); // e.g. "x ^ 2 + y ^ 2 = r ^ 2"
/// ```
class HmeLatexRecognizer implements LatexRecognitionBridge {
  static const String _tag = 'HmeLatexRecognizer';
  static const String _packageName = 'fluera_engine';

  /// Model input dimensions (must match training).
  static const int _imgHeight = 128;
  static const int _imgWidth = 512;

  /// Max decode steps (prevents infinite loops).
  static const int _maxDecodeLen = 64;

  /// Special token indices (must match training vocab).
  static const int _padIdx = 0;
  static const int _sosIdx = 1;
  static const int _eosIdx = 2;

  /// Asset paths.
  static const String _encoderAsset = 'assets/models/hme/hme_encoder.onnx';
  static const String _decoderAsset = 'assets/models/hme/hme_decoder.onnx';
  static const String _vocabAsset = 'assets/models/hme/hme_attn_vocab.json';

  /// Model version — bump to force re-write of cached models on disk.
  static const int _modelVersion = 4;

  // Internal state
  OrtSession? _encoderSession;
  OrtSession? _decoderSession;
  Map<int, String> _idx2token = {};
  bool _initialized = false;
  bool _modelAvailable = false;

  @override
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      debugPrint('[$_tag] Step 1: OrtEnv.init...');
      OrtEnv.instance.init();

      // Load vocabulary
      debugPrint('[$_tag] Step 2: Loading vocab...');
      await _loadVocab();
      debugPrint('[$_tag] Step 2 done: ${_idx2token.length} tokens');

      // Write model files to disk
      debugPrint('[$_tag] Step 3: Writing models to disk...');
      final paths = await _writeModelsToDisk();
      if (paths == null) {
        throw const LatexRecognitionException('HME models not found');
      }
      debugPrint('[$_tag] Step 3 done');

      // Create ONNX sessions
      debugPrint('[$_tag] Step 4: Creating ORT sessions...');
      final opts = OrtSessionOptions();

      _encoderSession = OrtSession.fromFile(File(paths.$1), opts);
      debugPrint('[$_tag]   Encoder: ${_encoderSession != null ? "✓" : "✗"}');

      _decoderSession = OrtSession.fromFile(File(paths.$2), opts);
      debugPrint('[$_tag]   Decoder: ${_decoderSession != null ? "✓" : "✗"}');

      _modelAvailable =
          _encoderSession != null &&
          _decoderSession != null &&
          _idx2token.isNotEmpty;
      _initialized = true;

      debugPrint('[$_tag] initialized — ready=$_modelAvailable');
    } catch (e, st) {
      _initialized = true;
      _modelAvailable = false;
      debugPrint('[$_tag] initialization failed: $e');
      debugPrint('[$_tag] stack: $st');
    }
  }

  @override
  Future<LatexRecognitionResult> recognize(InkData inkData) async {
    _ensureInitialized();

    if (inkData.isEmpty) {
      return const LatexRecognitionResult(latexString: '', confidence: 0.0);
    }

    final pngBytes = await InkRasterizer.rasterize(
      inkData,
      width: _imgWidth,
      height: _imgHeight,
    );
    if (pngBytes == null) {
      return const LatexRecognitionResult(latexString: '', confidence: 0.0);
    }

    return recognizeImage(pngBytes);
  }

  @override
  Future<LatexRecognitionResult> recognizeImage(Uint8List imageBytes) async {
    _ensureInitialized();

    if (!_modelAvailable) {
      throw const LatexRecognitionException(
        'HME model not available. Add encoder/decoder ONNX to assets.',
      );
    }

    final sw = Stopwatch()..start();

    // 1. Preprocess: PNG → grayscale float tensor [1, 1, H, W]
    final imageData = await _preprocessImage(imageBytes);

    // 2. Encode: image → features [1, N, D]
    final features = await _runEncoder(imageData);

    // 3. Decode: autoregressive loop → token sequence
    final (tokens, confidences) = await _autoregressiveDecode(features);

    // 4. Convert tokens to LaTeX string
    final latex = _tokensToLatex(tokens);

    sw.stop();
    debugPrint(
      '[$_tag] recognized in ${sw.elapsedMilliseconds}ms: "$latex" '
      '(${tokens.length} tokens)',
    );

    // Per-symbol confidence
    final perSymbol = <SymbolConfidence>[];
    int charIdx = 0;
    for (int i = 0; i < tokens.length; i++) {
      final token = _idx2token[tokens[i]] ?? '';
      if (token.isEmpty) continue;
      final endIdx = charIdx + token.length;
      perSymbol.add(
        SymbolConfidence(
          token: token,
          startIndex: charIdx,
          endIndex: endIdx,
          confidence: i < confidences.length ? confidences[i] : 0.0,
        ),
      );
      charIdx = endIdx + 1;
    }

    // Overall confidence (geometric mean)
    double confidence = 0.0;
    if (confidences.isNotEmpty) {
      final logSum = confidences.fold<double>(
        0.0,
        (sum, c) => sum + math.log(c + 1e-10),
      );
      confidence = math.exp(logSum / confidences.length);
    }

    return LatexRecognitionResult(
      latexString: latex,
      confidence: confidence,
      perSymbolConfidence: perSymbol,
      inferenceTimeMs: sw.elapsedMilliseconds,
    );
  }

  @override
  Future<bool> isAvailable() async {
    if (!_initialized) {
      try {
        await initialize();
      } catch (_) {
        return false;
      }
    }
    return _modelAvailable;
  }

  @override
  void dispose() {
    _encoderSession?.release();
    _decoderSession?.release();
    _encoderSession = null;
    _decoderSession = null;
    _modelAvailable = false;
    _initialized = false;
    _idx2token.clear();
    try {
      OrtEnv.instance.release();
    } catch (_) {}
  }

  // ─── Internal ──────────────────────────────────────────────────────────────

  void _ensureInitialized() {
    if (!_initialized) {
      throw const LatexRecognitionException(
        'HmeLatexRecognizer not initialized. Call initialize() first.',
      );
    }
  }

  /// Load asset with package prefix fallback.
  Future<Uint8List?> _loadAsset(String assetPath) async {
    final packagePath = 'packages/$_packageName/$assetPath';
    try {
      final data = await rootBundle.load(packagePath);
      return data.buffer.asUint8List();
    } catch (_) {
      try {
        final data = await rootBundle.load(assetPath);
        return data.buffer.asUint8List();
      } catch (e) {
        debugPrint('[$_tag] Asset not found: $assetPath ($e)');
        return null;
      }
    }
  }

  /// Write model files to disk (ORT needs file path).
  Future<(String, String)?> _writeModelsToDisk() async {
    try {
      final dir = await getSafeDocumentsDirectory();
      if (dir == null) return null; // Web: no filesystem
      final modelDir = Directory('${dir.path}/hme_attn_models_v$_modelVersion');
      if (!modelDir.existsSync()) {
        modelDir.createSync(recursive: true);
      }

      // Encoder
      final encFile = File('${modelDir.path}/hme_encoder.onnx');
      if (!encFile.existsSync()) {
        final bytes = await _loadAsset(_encoderAsset);
        if (bytes == null) return null;
        await encFile.writeAsBytes(bytes);
        debugPrint('[$_tag] Wrote encoder: ${bytes.length} bytes');
      }

      // Decoder
      final decFile = File('${modelDir.path}/hme_decoder.onnx');
      if (!decFile.existsSync()) {
        final bytes = await _loadAsset(_decoderAsset);
        if (bytes == null) return null;
        await decFile.writeAsBytes(bytes);
        debugPrint('[$_tag] Wrote decoder: ${bytes.length} bytes');
      }

      return (encFile.path, decFile.path);
    } catch (e) {
      debugPrint('[$_tag] Failed to write models: $e');
      return null;
    }
  }

  /// Load vocabulary from JSON.
  Future<void> _loadVocab() async {
    final bytes = await _loadAsset(_vocabAsset);
    if (bytes == null) {
      debugPrint('[$_tag] vocab not found');
      return;
    }

    final jsonStr = utf8.decode(bytes);
    final map = json.decode(jsonStr) as Map<String, dynamic>;

    // Format: { "idx2token": { "0": "<pad>", ... }, "token2idx": {...} }
    if (map.containsKey('idx2token')) {
      final idx2tok = map['idx2token'] as Map<String, dynamic>;
      _idx2token = idx2tok.map((k, v) => MapEntry(int.parse(k), v as String));
    }

    debugPrint('[$_tag] vocab loaded: ${_idx2token.length} tokens');
  }

  /// Preprocess PNG → grayscale float tensor [1, 1, H, W].
  Future<Float32List> _preprocessImage(Uint8List pngBytes) async {
    final codec = await ui.instantiateImageCodec(pngBytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final origW = image.width;
    final origH = image.height;
    image.dispose();
    codec.dispose();

    if (byteData == null) {
      throw const LatexRecognitionException('Failed to decode image');
    }

    final rgba = byteData.buffer.asUint8List();
    final pixels = Float32List(_imgHeight * _imgWidth);

    for (int y = 0; y < _imgHeight; y++) {
      for (int x = 0; x < _imgWidth; x++) {
        final srcX = (x * origW / _imgWidth).floor().clamp(0, origW - 1);
        final srcY = (y * origH / _imgHeight).floor().clamp(0, origH - 1);
        final idx = (srcY * origW + srcX) * 4;

        final r = rgba[idx];
        final g = rgba[idx + 1];
        final b = rgba[idx + 2];

        // Normalize to [-1, 1]
        final gray = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0;
        pixels[y * _imgWidth + x] = (gray - 0.5) / 0.5;
      }
    }

    return pixels;
  }

  /// Run encoder: image → features.
  Future<List<double>> _runEncoder(Float32List imageData) async {
    final inputTensor = OrtValueTensor.createTensorWithDataList(imageData, [
      1,
      1,
      _imgHeight,
      _imgWidth,
    ]);

    final runOptions = OrtRunOptions();
    final outputs = await _encoderSession!.runAsync(runOptions, {
      'image': inputTensor,
    });

    inputTensor.release();
    runOptions.release();

    if (outputs == null || outputs.isEmpty || outputs.first == null) {
      throw const LatexRecognitionException('Encoder produced no output');
    }

    final rawOutput = outputs.first!.value;
    final flat = _flattenToDoubles(rawOutput);

    for (final o in outputs) {
      o?.release();
    }

    return flat;
  }

  /// Autoregressive decode: run decoder step by step.
  ///
  /// Each step: (features, tokens_so_far) → next_token_logits
  /// Take argmax of last position → append to tokens.
  /// Stop at EOS or max length.
  Future<(List<int>, List<double>)> _autoregressiveDecode(
    List<double> encoderFeatures,
  ) async {
    final tokens = <int>[_sosIdx];
    final confidences = <double>[];

    // Determine feature shape: [1, N, D]
    // The encoder outputs a flat list — we need to know D (d_model=256)
    const dModel = 256;
    final seqLen = encoderFeatures.length ~/ dModel;

    // Fixed sequence length — ONNX decoder was exported with this shape.
    // Tokens are padded to this length; the causal mask ensures PAD positions
    // don't affect the output at active positions.
    const maxSeqLen = 64;

    for (int step = 0; step < _maxDecodeLen; step++) {
      // Build padded token tensor [1, maxSeqLen]
      final tokenData = Int64List(maxSeqLen);
      // Fill with PAD
      for (int i = 0; i < maxSeqLen; i++) {
        tokenData[i] = _padIdx;
      }
      // Copy active tokens
      for (int i = 0; i < tokens.length && i < maxSeqLen; i++) {
        tokenData[i] = tokens[i];
      }
      final tokenTensor = OrtValueTensor.createTensorWithDataList(tokenData, [
        1,
        maxSeqLen,
      ]);

      // Build feature tensor [1, N, D]
      final featureData = Float32List(encoderFeatures.length);
      for (int i = 0; i < encoderFeatures.length; i++) {
        featureData[i] = encoderFeatures[i].toDouble();
      }
      final featureTensor = OrtValueTensor.createTensorWithDataList(
        featureData,
        [1, seqLen, dModel],
      );

      final runOptions = OrtRunOptions();
      final outputs = await _decoderSession!.runAsync(runOptions, {
        'tokens': tokenTensor,
        'memory': featureTensor,
      });

      tokenTensor.release();
      featureTensor.release();
      runOptions.release();

      if (outputs == null || outputs.isEmpty || outputs.first == null) {
        break;
      }

      // Output: [1, maxSeqLen, V] — take the logits at the ACTIVE position
      // (the last non-PAD position = tokens.length - 1)
      final rawOutput = outputs.first!.value;
      final flat = _flattenToDoubles(rawOutput);

      for (final o in outputs) {
        o?.release();
      }

      final vocabSize = _idx2token.length;
      final activePos = tokens.length - 1; // current last token position
      final logitStart = activePos * vocabSize;
      if (logitStart + vocabSize > flat.length) break;

      final logits = flat.sublist(logitStart, logitStart + vocabSize).toList();

      // EOS suppression: force model to generate at least 2 content tokens
      // before allowing EOS/PAD/SOS. This matches the training fix that
      // boosted accuracy from 0% to 68%.
      if (step < 2) {
        logits[_eosIdx] = -1e9;
        logits[_padIdx] = -1e9;
        logits[_sosIdx] = -1e9;
      }

      final probs = _softmaxDouble(logits);

      int bestIdx = 0;
      double bestProb = probs[0];
      for (int i = 1; i < probs.length; i++) {
        if (probs[i] > bestProb) {
          bestProb = probs[i];
          bestIdx = i;
        }
      }

      // Stop conditions
      if (bestIdx == _eosIdx || bestIdx == _padIdx) break;

      tokens.add(bestIdx);
      confidences.add(bestProb);
    }

    // Remove SOS
    return (tokens.sublist(1), confidences);
  }

  /// Convert token IDs to LaTeX string.
  String _tokensToLatex(List<int> tokenIds) {
    final parts = <String>[];
    for (final id in tokenIds) {
      final token = _idx2token[id];
      if (token != null &&
          token != '<pad>' &&
          token != '<sos>' &&
          token != '<eos>') {
        parts.add(token);
      }
    }
    return parts.join(' ');
  }

  /// Softmax over doubles.
  List<double> _softmaxDouble(List<double> logits) {
    double maxVal = double.negativeInfinity;
    for (final v in logits) {
      if (v > maxVal) maxVal = v;
    }

    final result = List<double>.filled(logits.length, 0.0);
    double sum = 0.0;
    for (int i = 0; i < logits.length; i++) {
      result[i] = math.exp(logits[i] - maxVal);
      sum += result[i];
    }

    if (sum > 0) {
      for (int i = 0; i < result.length; i++) {
        result[i] /= sum;
      }
    }

    return result;
  }

  /// Flatten nested ONNX output to a list of doubles.
  List<double> _flattenToDoubles(dynamic value) {
    if (value is num) return [value.toDouble()];
    if (value is List) {
      final result = <double>[];
      for (final item in value) {
        result.addAll(_flattenToDoubles(item));
      }
      return result;
    }
    return [];
  }
}
