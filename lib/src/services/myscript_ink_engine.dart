import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../drawing/models/pro_drawing_point.dart';
import 'ink_recognition_engine.dart';

// =============================================================================
// 🧮 MyScript Ink Engine — On-device formula + text recognition via iink SDK
//
// Implements [InkRecognitionEngine] using MyScript Interactive Ink SDK
// through a native Kotlin bridge (MethodChannel).
//
// Supports two content types:
//   - "math" → LaTeX output (x^{2}+1)
//   - "text" → plain text output (hello world)
//
// ARCHITECTURE:
//   Dart stroke data → MethodChannel → Kotlin MyScriptInkPlugin
//   → iink Engine (dual Math/Text editors) → result → Dart
// =============================================================================

class MyScriptInkEngine implements InkRecognitionEngine {
  static const MethodChannel _channel = MethodChannel(
    'fluera_engine/myscript_ink',
  );

  bool _available = false;
  bool _initialized = false;

  /// Single-flight guard: when an init() invocation is in progress, all
  /// subsequent callers share the same Future. This prevents the race
  /// where two concurrent `init()` calls both pass the synchronous
  /// `_initialized` check, both fire the native `initialize` method, and
  /// the second native call fails with "package already exists" —
  /// overwriting `_available = false` on what was a successful init.
  Future<void>? _inFlightInit;

  @override
  bool get isAvailable => _available;

  @override
  bool get isReady => _initialized && _available;

  @override
  String get languageCode => 'math'; // MyScript Math is language-agnostic

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  Future<void> init({String languageCode = 'en'}) {
    if (_initialized) return Future.value();
    final existing = _inFlightInit;
    if (existing != null) return existing;
    final future = _doInit();
    _inFlightInit = future;
    return future;
  }

  /// Hard ceiling on how long the native `initialize` call may take.
  /// First-run on a new device includes license unpacking, package creation,
  /// and editor warm-up — MyScript typically completes in 300-800ms but
  /// has been observed up to ~3s on older hardware. 10s is a generous
  /// safety net: if we hit it, the native side is almost certainly hung
  /// (corrupt package, disk full, revoked permission) and we must unblock
  /// the UI rather than wait forever.
  static const Duration _initTimeout = Duration(seconds: 10);

  Future<void> _doInit() async {
    try {
      final result = await _channel
          .invokeMethod<Map>('initialize')
          .timeout(_initTimeout);
      _available = result?['available'] as bool? ?? false;
      _initialized = true;
      if (_available) {
        debugPrint('[MyScriptInk] ✅ Engine initialized successfully');
      } else {
        final error = result?['error'] as String?;
        debugPrint('[MyScriptInk] ⚠️ Engine not available: $error');
      }
    } on TimeoutException {
      debugPrint(
        '[MyScriptInk] ⏱️ Init timed out after ${_initTimeout.inSeconds}s — '
        'native plugin unresponsive. Flagging engine unavailable so the UI '
        'can proceed without OCR. Future init() calls may retry since '
        '_initialized stays false.',
      );
      // Keep _initialized = false so the next caller can retry — a
      // transient native hang (e.g. license server slow) shouldn't
      // permanently disable OCR for the app session.
      _available = false;
    } on PlatformException catch (e) {
      debugPrint('[MyScriptInk] ❌ Init failed: ${e.message}');
      _initialized = true;
      _available = false;
    } on MissingPluginException {
      debugPrint('[MyScriptInk] ❌ Plugin not registered (wrong platform?)');
      _initialized = true;
      _available = false;
    } finally {
      _inFlightInit = null;
    }
  }

  // ── Recognition ────────────────────────────────────────────────────────────

  /// Recognize strokes. Auto-detects Math vs Text by default.
  @override
  Future<String?> recognizeStroke(
    List<ProDrawingPoint> points, {
    InkRecognitionContext context = InkRecognitionContext.empty,
  }) async {
    return _recognize([points], contentType: 'auto');
  }

  @override
  Future<String?> recognizeMultiStroke(
    List<List<ProDrawingPoint>> strokeSets, {
    InkRecognitionContext context = InkRecognitionContext.empty,
  }) async {
    return _recognize(strokeSets, contentType: 'auto');
  }

  @override
  Future<List<InkCandidate>> recognizeStrokeCandidates(
    List<ProDrawingPoint> points, {
    InkRecognitionContext context = InkRecognitionContext.empty,
    int maxCandidates = 5,
  }) async {
    final text = await _recognize([points], contentType: 'math');
    if (text == null || text.isEmpty) return [];
    return [InkCandidate(text: text, score: 1.0)];
  }

  @override
  Future<List<InkCandidate>> recognizeMultiStrokeCandidates(
    List<List<ProDrawingPoint>> strokeSets, {
    InkRecognitionContext context = InkRecognitionContext.empty,
    int maxCandidates = 5,
  }) async {
    final text = await _recognize(strokeSets, contentType: 'math');
    if (text == null || text.isEmpty) return [];
    return [InkCandidate(text: text, score: 1.0)];
  }

  // ── Public API: Text recognition ──────────────────────────────────────────

  /// Recognize strokes as handwritten text (multi-language Latin).
  Future<String?> recognizeText(List<List<ProDrawingPoint>> strokeSets) {
    return _recognize(strokeSets, contentType: 'text');
  }

  /// Override: force text mode for AI consumers (Ghost Map, Socratic).
  @override
  Future<String?> recognizeTextMode(
    List<List<ProDrawingPoint>> strokeSets, {
    InkRecognitionContext context = InkRecognitionContext.empty,
  }) {
    return recognizeText(strokeSets);
  }

  /// Recognize strokes as math formula (returns LaTeX).
  Future<String?> recognizeMath(List<List<ProDrawingPoint>> strokeSets) {
    return _recognize(strokeSets, contentType: 'math');
  }

  /// Recognize using Raw Content mode — auto-classifies ink blocks.
  ///
  /// Returns the recognized label with block classification (text/math/drawing).
  /// Useful for mixed content where text and shapes coexist.
  Future<String?> recognizeRaw(List<List<ProDrawingPoint>> strokeSets) {
    return _recognize(strokeSets, contentType: 'raw');
  }

  /// Core recognition pipeline.
  Future<String?> _recognize(
    List<List<ProDrawingPoint>> strokeSets, {
    String contentType = 'math',
  }) async {
    if (!_available) return null;
    if (strokeSets.isEmpty) return null;

    // ── Filter & cap strokes ──────────────────────────────────────────
    // Skip single-point strokes (can't form down→move→up sequence).
    // Cap at 50 strokes to avoid timeout on massive selections.
    final filtered = strokeSets
        .where((s) => s.length >= 2)
        .take(50)
        .toList();
    if (filtered.isEmpty) return null;

    // ── Normalize coordinates + DPI scaling ───────────────────────────
    // Scale canvas coordinates so stroke dimensions approximate natural
    // handwriting size. MyScript Engine runs at 96 DPI (≈ 0.265 mm/px).
    // Target: ~7mm per character height → ~26px at 96 DPI.
    // We compute the bounding box height and scale to a target of ~200px
    // (enough for multi-line formulas).
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final stroke in filtered) {
      for (final point in stroke) {
        final dx = point.position.dx, dy = point.position.dy;
        if (dx < minX) minX = dx;
        if (dy < minY) minY = dy;
        if (dx > maxX) maxX = dx;
        if (dy > maxY) maxY = dy;
      }
    }

    // ── Translate to origin — NO scaling ─────────────────────────────
    // The prediction editor uses raw coordinates and produces accurate
    // results. We match that approach: translate to origin (positive
    // coords for MyScript) but preserve original proportions.
    // MyScript's editor view is 10000×10000 — plenty of room.
    const padding = 10.0;
    final offsetX = -minX + padding;
    final offsetY = -minY + padding;

    // ── Generate synthetic timestamps ──────────────────────────────────
    int syntheticTime = 0;
    const msPerPoint = 10;
    const msGapBetweenStrokes = 100;

    final strokes = <List<Map<String, double>>>[];
    for (final stroke in filtered) {
      final points = <Map<String, double>>[];
      double prevX = double.nan, prevY = double.nan;

      for (final point in stroke) {
        final nx = point.position.dx + offsetX;
        final ny = point.position.dy + offsetY;
        // Skip duplicate consecutive points (waste recognition compute)
        if (nx == prevX && ny == prevY) continue;
        prevX = nx;
        prevY = ny;

        points.add(<String, double>{
          'x': nx,
          'y': ny,
          't': syntheticTime.toDouble(),
          'f': point.pressure,
        });
        syntheticTime += msPerPoint;
      }
      // After dedup, ensure at least 2 points remain
      if (points.length >= 2) {
        syntheticTime += msGapBetweenStrokes;
        strokes.add(points);
      }
    }

    if (strokes.isEmpty) return null;

    final totalPoints = strokes.fold<int>(0, (s, stroke) => s + stroke.length);
    debugPrint('[MyScriptInk] 🖊️ Recognizing ${strokes.length} strokes ($totalPoints pts)');

    try {
      final result = await _channel.invokeMethod<Map>('recognizeStrokes', {
        'strokes': strokes,
        'contentType': contentType,
      });

      final label = result?['latex'] as String?;
      final detectedType = result?['detectedType'] as String? ?? 'math';

      if (label != null && label.isNotEmpty) {
        debugPrint('[MyScriptInk] 📝 [$detectedType] $label');
        return label;
      }

      return null;
    } on PlatformException catch (e) {
      debugPrint('[MyScriptInk] ❌ ${e.message}');
      return null;
    }
  }

  // ── Language Management (Math is language-agnostic) ─────────────────────

  @override
  Future<bool> switchLanguage(String languageCode) async => true;

  @override
  Future<bool> isModelDownloaded(String languageCode) async => _available;

  @override
  Future<bool> downloadLanguage(String languageCode) async => _available;

  @override
  Future<void> deleteModel(String languageCode) async {}

  @override
  Future<Map<String, bool>> getDownloadStatus(
    List<String> languageCodes,
  ) async {
    return {for (final code in languageCodes) code: _available};
  }

  // ── Ink Prediction API ─────────────────────────────────────────────────────

  /// Feed a single stroke incrementally for prediction (no editor clear).
  /// Returns partial recognition + candidates + confidence.
  ///
  /// This is a thin convenience wrapper — delegates to [InkPredictionService].
  Future<Map<String, dynamic>?> feedStroke(
    List<ProDrawingPoint> points,
  ) async {
    if (!_available) return null;
    if (points.length < 2) return null;

    final strokeData = points.map((p) => {
      'x': p.position.dx,
      'y': p.position.dy,
      't': p.timestamp,
      'f': p.pressure,
    }).toList();

    try {
      final result = await _channel.invokeMethod<Map>('feedStroke', {
        'stroke': strokeData,
      });
      if (result == null) return null;
      return Map<String, dynamic>.from(result);
    } on PlatformException catch (e) {
      debugPrint('[MyScriptInk] ❌ feedStroke: ${e.message}');
      return null;
    }
  }

  /// Clear the prediction editor (resets accumulated ink).
  Future<void> clearPrediction() async {
    try {
      await _channel.invokeMethod('clearPrediction');
    } catch (e) {
      debugPrint('[MyScriptInk] ⚠️ clearPrediction: $e');
    }
  }

  // ── Cleanup ────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    if (_initialized) {
      try {
        _channel.invokeMethod<void>('dispose');
      } catch (_) {}
      _initialized = false;
      _available = false;
    }
  }
}
