import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_mlkit_digital_ink_recognition/google_mlkit_digital_ink_recognition.dart';
import '../drawing/models/pro_drawing_point.dart';
import 'ink_recognition_engine.dart';

// ============================================================================
// ✍️ ML Kit Ink Engine — Google ML Kit Digital Ink adapter
// ============================================================================

/// Ink recognition engine backed by Google ML Kit Digital Ink Recognition.
///
/// Runs entirely on-device (~15 MB model, one-time download per language).
/// Available on Android and iOS only.
///
/// This adapter isolates all ML Kit dependencies. To swap recognition
/// backend, implement [InkRecognitionEngine] with a different engine
/// and pass it to [DigitalInkService].
class MlKitInkEngine extends InkRecognitionEngine {
  String _languageCode = 'en';
  DigitalInkRecognizer? _recognizer;
  final DigitalInkRecognizerModelManager _modelManager =
      DigitalInkRecognizerModelManager();
  bool _modelReady = false;
  bool _initializing = false;

  @override
  bool get isAvailable {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid || Platform.isIOS;
    } catch (_) {
      return false;
    }
  }

  @override
  bool get isReady => _modelReady;

  @override
  String get languageCode => _languageCode;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  Future<void> init({String languageCode = 'en'}) async {
    if (!isAvailable) return;
    if (_modelReady && _languageCode == languageCode) return;

    // Wait for any in-progress init to finish (instead of silently returning)
    int waitMs = 0;
    while (_initializing && waitMs < 15000) {
      await Future.delayed(const Duration(milliseconds: 200));
      waitMs += 200;
    }
    // After waiting, check if the other init already handled our language
    if (_modelReady && _languageCode == languageCode) return;
    if (_initializing) return; // Still stuck after 15s — give up

    _initializing = true;

    try {
      _languageCode = languageCode;

      final isDownloaded = await _modelManager.isModelDownloaded(languageCode);
      print('🔤 MlKit model "$languageCode" downloaded: $isDownloaded');
      if (!isDownloaded) {
        print('🔤 Downloading model "$languageCode"...');
        // Timeout: Google Play Services may queue forever on mobile data
        await _modelManager.downloadModel(languageCode, isWifiRequired: false)
            .timeout(const Duration(seconds: 30));
        print('🔤 Download complete');
      }

      _recognizer?.close();
      _recognizer = DigitalInkRecognizer(languageCode: languageCode);
      _modelReady = true;
      print('🔤 ✅ MlKit engine ready (lang=$languageCode)');
    } catch (e, st) {
      print('❌ MlKitInkEngine.init($languageCode) FAILED: $e\n$st');
      _modelReady = false;
    } finally {
      _initializing = false;
    }
  }

  // ── Recognition ────────────────────────────────────────────────────────────

  @override
  Future<String?> recognizeStroke(List<ProDrawingPoint> points) async {
    if (!_modelReady || _recognizer == null) {
      await init(languageCode: _languageCode);
      if (!_modelReady || _recognizer == null) return null;
    }

    if (points.length < 5) return null;

    try {
      final inkPoints = <StrokePoint>[];
      for (final p in points) {
        inkPoints.add(
          StrokePoint(x: p.position.dx, y: p.position.dy, t: p.timestamp),
        );
      }

      final stroke = Stroke();
      stroke.points = inkPoints;

      final ink = Ink();
      ink.strokes = [stroke];

      final candidates = await _recognizer!.recognize(ink);
      if (candidates.isEmpty) return null;

      final best = candidates.first.text;
      return best;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String?> recognizeMultiStroke(
    List<List<ProDrawingPoint>> strokeSets,
  ) async {
    if (!_modelReady || _recognizer == null) {
      await init(languageCode: _languageCode);
      if (!_modelReady || _recognizer == null) return null;
    }

    final totalPoints = strokeSets.fold<int>(0, (sum, s) => sum + s.length);
    if (totalPoints < 5) return null;

    try {
      final mlStrokes = <Stroke>[];
      for (final points in strokeSets) {
        final inkPoints = <StrokePoint>[];
        for (final p in points) {
          inkPoints.add(
            StrokePoint(x: p.position.dx, y: p.position.dy, t: p.timestamp),
          );
        }
        mlStrokes.add(Stroke()..points = inkPoints);
      }

      final ink = Ink();
      ink.strokes = mlStrokes;
      final candidates = await _recognizer!.recognize(ink);

      if (candidates.isEmpty) return null;

      final best = candidates.first.text;
      return best;
    } catch (_) {
      return null;
    }
  }

  // ── Language Management ────────────────────────────────────────────────────

  @override
  Future<bool> switchLanguage(String languageCode) async {
    if (!isAvailable) return false;
    if (_languageCode == languageCode && _modelReady) return true;

    _modelReady = false;
    _recognizer?.close();
    _recognizer = null;

    await init(languageCode: languageCode);
    return _modelReady;
  }

  @override
  Future<bool> isModelDownloaded(String languageCode) async {
    if (!isAvailable) return false;
    try {
      return await _modelManager.isModelDownloaded(languageCode);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> downloadLanguage(String languageCode) async {
    if (!isAvailable) return false;
    try {
      await _modelManager.downloadModel(languageCode, isWifiRequired: false)
          .timeout(const Duration(seconds: 30));
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> deleteModel(String languageCode) async {
    if (!isAvailable) return;
    try {
      await _modelManager.deleteModel(languageCode);
      if (languageCode == _languageCode) {
        _modelReady = false;
      }
    } catch (_) {
    }
  }

  @override
  Future<Map<String, bool>> getDownloadStatus(
    List<String> languageCodes,
  ) async {
    if (!isAvailable) {
      return {for (final c in languageCodes) c: false};
    }
    final results = <String, bool>{};
    for (final code in languageCodes) {
      results[code] = await isModelDownloaded(code);
    }
    return results;
  }

  @override
  void dispose() {
    _recognizer?.close();
    _recognizer = null;
    _modelReady = false;
  }
}
