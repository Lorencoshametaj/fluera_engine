import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/latex/ink_stroke_data.dart';
import 'ink_rasterizer.dart';
import 'latex_recognition_bridge.dart';
import 'onnx_latex_recognizer.dart';
import 'pix2tex_config.dart';

/// 🧮 Pix2Tex Recognizer — smart [LatexRecognitionBridge] with dual backend.
///
/// Tries recognition in this order:
/// 1. **On-device ONNX** (if models are bundled) — offline, fast, ~10-15MB
/// 2. **HTTP API fallback** (if server configured) — full accuracy, needs network
///
/// ## Usage
/// ```dart
/// // On-device only (no server needed)
/// final recognizer = Pix2TexRecognizer();
/// await recognizer.initialize();
/// final result = await recognizer.recognizeImage(pngBytes);
///
/// // With HTTP fallback
/// final recognizer = Pix2TexRecognizer(
///   config: Pix2TexConfig(host: '192.168.1.10'),
/// );
/// ```
class Pix2TexRecognizer implements LatexRecognitionBridge {
  /// Server configuration for HTTP API fallback.
  final Pix2TexConfig config;

  /// On-device ONNX recognizer (tried first).
  OnnxLatexRecognizer? _onnxRecognizer;

  /// Whether ONNX on-device is available.
  bool _onnxAvailable = false;

  /// HTTP client with keep-alive (for API fallback).
  HttpClient? _httpClient;

  /// Whether the recognizer has been initialized.
  bool _initialized = false;

  /// LRU cache for recent results (max 32 entries).
  final Map<int, LatexRecognitionResult> _cache = {};
  static const int _maxCacheSize = 32;

  Pix2TexRecognizer({this.config = const Pix2TexConfig()});

  @override
  Future<void> initialize() async {
    if (_initialized) return;

    // Try on-device ONNX first
    try {
      _onnxRecognizer = OnnxLatexRecognizer();
      await _onnxRecognizer!.initialize();
      _onnxAvailable = await _onnxRecognizer!.isAvailable();
    } catch (_) {
      _onnxAvailable = false;
    }

    if (_onnxAvailable) {
      _initialized = true;
      return;
    }

    // Fall back to HTTP API
    _httpClient =
        HttpClient()
          ..connectionTimeout = config.timeout
          ..idleTimeout = const Duration(seconds: 30);

    // Verify server is reachable (non-fatal — may start later)
    try {
      final available = await isAvailable();
      if (!available) {
      }
    } catch (_) {
      // Non-fatal
    }

    _initialized = true;
  }

  @override
  Future<LatexRecognitionResult> recognize(InkData inkData) async {
    _ensureInitialized();

    if (inkData.isEmpty) {
      return const LatexRecognitionResult(latexString: '', confidence: 0.0);
    }

    // Try ONNX on-device first
    if (_onnxAvailable) {
      return _onnxRecognizer!.recognize(inkData);
    }

    // Fall back to HTTP API
    final pngBytes = await InkRasterizer.rasterize(inkData, size: 400);
    if (pngBytes == null) {
      return const LatexRecognitionResult(latexString: '', confidence: 0.0);
    }

    return _recognizeViaHttp(pngBytes);
  }

  @override
  Future<LatexRecognitionResult> recognizeImage(Uint8List imageBytes) async {
    _ensureInitialized();

    // Try ONNX on-device first
    if (_onnxAvailable) {
      return _onnxRecognizer!.recognizeImage(imageBytes);
    }

    // Fall back to HTTP API
    return _recognizeViaHttp(imageBytes);
  }

  /// HTTP API recognition with caching and retry.
  Future<LatexRecognitionResult> _recognizeViaHttp(Uint8List imageBytes) async {
    // Check cache
    final cacheKey = _computeHash(imageBytes);
    final cached = _cache[cacheKey];
    if (cached != null) return cached;

    // Send to API with retry
    final sw = Stopwatch()..start();
    final result = await _sendWithRetry(imageBytes);
    sw.stop();

    final finalResult = LatexRecognitionResult(
      latexString: result,
      confidence: result.isNotEmpty ? 0.85 : 0.0,
      inferenceTimeMs: sw.elapsedMilliseconds,
    );

    // Cache result
    _putCache(cacheKey, finalResult);

    return finalResult;
  }

  @override
  Future<bool> isAvailable() async {
    // ONNX on-device takes priority
    if (_onnxAvailable) return true;

    // Fall back to HTTP health check
    try {
      final client = _httpClient ?? HttpClient();
      final request = await client
          .getUrl(config.healthUri)
          .timeout(const Duration(seconds: 3));
      final response = await request.close().timeout(
        const Duration(seconds: 3),
      );
      await response.drain<void>();
      return response.statusCode == 200;
    } catch (_) {
      try {
        final client = _httpClient ?? HttpClient();
        final request = await client
            .openUrl('OPTIONS', config.predictUri)
            .timeout(const Duration(seconds: 3));
        final response = await request.close().timeout(
          const Duration(seconds: 3),
        );
        await response.drain<void>();
        return response.statusCode < 500;
      } catch (_) {
        return false;
      }
    }
  }

  @override
  void dispose() {
    _onnxRecognizer?.dispose();
    _onnxRecognizer = null;
    _onnxAvailable = false;
    _httpClient?.close(force: true);
    _httpClient = null;
    _initialized = false;
    _cache.clear();
  }

  // ---------------------------------------------------------------------------
  // Private
  // ---------------------------------------------------------------------------

  void _ensureInitialized() {
    if (!_initialized) {
      throw const LatexRecognitionException(
        'Pix2TexRecognizer not initialized. Call initialize() first.',
      );
    }
  }

  /// Send image to pix2tex API with exponential backoff retry.
  Future<String> _sendWithRetry(Uint8List imageBytes) async {
    Object? lastError;

    for (int attempt = 0; attempt < config.maxRetries; attempt++) {
      try {
        return await _sendRequest(imageBytes);
      } on SocketException catch (e) {
        lastError = e;
      } on TimeoutException catch (e) {
        lastError = e;
      } on HttpException catch (e) {
        lastError = e;
      } catch (e) {
        // Non-transient error — don't retry
        throw LatexRecognitionException('Pix2Tex recognition failed', cause: e);
      }

      // Exponential backoff: 500ms, 1s, 2s
      if (attempt < config.maxRetries - 1) {
        await Future<void>.delayed(
          Duration(milliseconds: 500 * (1 << attempt)),
        );
      }
    }

    throw LatexRecognitionException(
      'Pix2Tex recognition failed after ${config.maxRetries} attempts',
      cause: lastError,
    );
  }

  /// Send a single multipart POST request to the pix2tex API.
  Future<String> _sendRequest(Uint8List imageBytes) async {
    final boundary =
        '----FlueraPix2Tex${DateTime.now().millisecondsSinceEpoch}';

    final request = await _httpClient!
        .postUrl(config.predictUri)
        .timeout(config.timeout);

    // Set headers
    request.headers.set(
      HttpHeaders.contentTypeHeader,
      'multipart/form-data; boundary=$boundary',
    );
    if (config.apiKey != null) {
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${config.apiKey}',
      );
    }

    // Build multipart body
    final body = <int>[];
    body.addAll(utf8.encode('--$boundary\r\n'));
    body.addAll(
      utf8.encode(
        'Content-Disposition: form-data; name="file"; filename="equation.png"\r\n',
      ),
    );
    body.addAll(utf8.encode('Content-Type: image/png\r\n\r\n'));
    body.addAll(imageBytes);
    body.addAll(utf8.encode('\r\n--$boundary--\r\n'));

    request.contentLength = body.length;
    request.add(body);

    final response = await request.close().timeout(config.timeout);
    final responseBody = await response.transform(utf8.decoder).join();

    if (response.statusCode != 200) {
      throw HttpException(
        'Pix2Tex API returned ${response.statusCode}: $responseBody',
      );
    }

    // Parse response — pix2tex returns {"latex": "..."} or plain text
    try {
      final json = jsonDecode(responseBody) as Map<String, dynamic>;
      return (json['latex'] as String? ?? json['result'] as String? ?? '')
          .trim();
    } catch (_) {
      // Fallback: treat response as plain text
      return responseBody.trim();
    }
  }

  /// Simple hash for cache key.
  int _computeHash(Uint8List bytes) {
    // FNV-1a 32-bit hash
    int hash = 0x811c9dc5;
    for (int i = 0; i < bytes.length; i += 4) {
      hash ^= bytes[i];
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }

  /// Insert into LRU cache, evicting oldest if full.
  void _putCache(int key, LatexRecognitionResult value) {
    if (_cache.length >= _maxCacheSize) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = value;
  }
}
