import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../core/latex/ink_stroke_data.dart';
import '../drawing/models/pro_drawing_point.dart';
import '../services/digital_ink_service.dart';
import '../services/myscript_ink_engine.dart';
import 'hme_latex_recognizer.dart';
import 'latex_recognition_bridge.dart';

// =============================================================================
// 🧮 MyScript LaTeX Bridge — Dual-backend recognition adapter
//
// Combines MyScript iink SDK (stroke-native math recognition) with the HME
// ONNX model (image-based OCR) into a unified LatexRecognitionBridge.
//
// ARCHITECTURE:
//   - recognize(InkData)       → MyScript Math editor (stroke-native, ~95% acc)
//   - recognizeImage(bytes)    → HME ONNX encoder-decoder (image OCR)
//
// IMPORTANT: Reuses DigitalInkService.instance.engine (the app-wide singleton)
// to avoid creating a second native iink Engine, which would crash because
// the `.iink` temp package file is already locked by the first engine.
//
// Falls back gracefully: if MyScript is unavailable (Web, missing native
// plugin), recognition attempts return empty results instead of crashing.
// =============================================================================

class MyScriptLatexBridge implements LatexRecognitionBridge {
  final HmeLatexRecognizer _hmeRecognizer = HmeLatexRecognizer();

  bool _initialized = false;

  /// Cached reference to the shared MyScript engine from DigitalInkService.
  MyScriptInkEngine? _myScript;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // ── Reuse the shared MyScript engine from DigitalInkService ──
    // The DigitalInkService already creates & initializes a MyScriptInkEngine
    // singleton that holds the native iink Engine. Creating a second one would
    // crash because the .iink package file is locked.
    final diService = DigitalInkService.instance;
    if (!diService.isReady) {
      try {
        await diService.init(languageCode: 'en');
      } catch (_) {}
    }

    // Grab the engine reference — it's a MyScriptInkEngine by default
    final engine = diService.engine;
    if (engine is MyScriptInkEngine && engine.isReady) {
      _myScript = engine;
    }

    // Initialize HME as fallback (non-fatal)
    await _hmeRecognizer.initialize().catchError((_) {});

    debugPrint(
      '[MyScriptLatexBridge] ✅ Initialized — '
      'MyScript: ${_myScript?.isReady == true ? "ready" : "unavailable"}, '
      'HME: ${await _hmeRecognizer.isAvailable() ? "ready" : "unavailable"}',
    );
  }

  // ── Ink Recognition (MyScript) ──────────────────────────────────────────

  @override
  Future<LatexRecognitionResult> recognize(InkData inkData) async {
    if (inkData.isEmpty) {
      return const LatexRecognitionResult(latexString: '', confidence: 0.0);
    }

    // ── Primary: MyScript iink Math recognition ──
    final myScript = _myScript;
    if (myScript != null && myScript.isReady) {
      try {
        final sw = Stopwatch()..start();
        final strokeSets = _convertInkDataToStrokes(inkData);
        final latex = await myScript.recognizeMath(strokeSets);
        sw.stop();

        if (latex != null && latex.isNotEmpty) {
          final normalized = _normalizeMyScriptLatex(latex);
          debugPrint(
            '[MyScriptLatexBridge] 📝 MyScript Math: "$normalized" '
            '(${sw.elapsedMilliseconds}ms)',
          );
          return LatexRecognitionResult(
            latexString: normalized,
            confidence: 0.95, // MyScript iink Math is very accurate
            inferenceTimeMs: sw.elapsedMilliseconds,
          );
        }
      } catch (e) {
        debugPrint('[MyScriptLatexBridge] ⚠️ MyScript failed: $e');
      }
    }

    // ── Fallback: HME ONNX (rasterize ink → image → decode) ──
    try {
      return await _hmeRecognizer.recognize(inkData);
    } catch (e) {
      debugPrint('[MyScriptLatexBridge] ⚠️ HME fallback failed: $e');
      return const LatexRecognitionResult(latexString: '', confidence: 0.0);
    }
  }

  // ── Image Recognition (HME ONNX) ──────────────────────────────────────

  @override
  Future<LatexRecognitionResult> recognizeImage(Uint8List imageBytes) async {
    // Images always go through HME (MyScript doesn't accept raster input)
    return _hmeRecognizer.recognizeImage(imageBytes);
  }

  // ── Availability ──────────────────────────────────────────────────────

  @override
  Future<bool> isAvailable() async {
    // Available if either backend is ready
    if (_myScript?.isReady == true) return true;
    return _hmeRecognizer.isAvailable();
  }

  // ── Cleanup ───────────────────────────────────────────────────────────

  @override
  void dispose() {
    // DON'T dispose _myScript — it's shared via DigitalInkService
    _hmeRecognizer.dispose();
    _myScript = null;
    _initialized = false;
  }

  // ── Internal: Convert InkData → ProDrawingPoint strokes ───────────────

  /// Converts [InkData] (from the LaTeX ink overlay) to the stroke format
  /// expected by [MyScriptInkEngine.recognizeMath()].
  ///
  /// Each [InkStroke] maps to a `List<ProDrawingPoint>`, preserving
  /// coordinates, pressure, and timestamps for accurate recognition.
  static List<List<ProDrawingPoint>> _convertInkDataToStrokes(InkData inkData) {
    return inkData.strokes
        .where((s) => s.isValid) // skip single-point strokes
        .map(
          (stroke) => stroke.points
              .map(
                (p) => ProDrawingPoint(
                  position: Offset(p.x, p.y),
                  pressure: p.pressure,
                  timestamp: p.timestamp,
                ),
              )
              .toList(),
        )
        .toList();
  }

  // ── Internal: Normalize MyScript LaTeX output ─────────────────────────

  /// MyScript iink exports amsmath display-style commands that Fluera's
  /// LaTeX renderer may not support. Normalize to standard equivalents.
  ///
  /// Conversions:
  ///   \dfrac → \frac   (display-style fraction → standard)
  ///   \dbinom → \binom  (display-style binomial → standard)
  ///   \tfrac → \frac   (text-style fraction → standard)
  ///   \tbinom → \binom  (text-style binomial → standard)
  static String _normalizeMyScriptLatex(String latex) {
    return latex
        .replaceAll(r'\dfrac', r'\frac')
        .replaceAll(r'\tfrac', r'\frac')
        .replaceAll(r'\dbinom', r'\binom')
        .replaceAll(r'\tbinom', r'\binom');
  }
}
