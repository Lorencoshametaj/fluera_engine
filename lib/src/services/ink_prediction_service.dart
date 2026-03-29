import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../drawing/models/pro_drawing_point.dart';
import 'word_completion_dictionary.dart';

// =============================================================================
// 🔮 INK PREDICTION SERVICE v5 — Advanced performance optimizations
//
// v5 OPTIMIZATIONS:
//   🚀 Skip duplicate predictions (same label → no emit, no UI rebuild)
//   🚀 Cancellation token (new stroke cancels in-flight native call)
//   🚀 Compute isolate for RDP on large strokes (>100 pts)
//   🚀 Debounce warm words persistence (max 1x per 5s, not every accept)
//   ✅ All v4 features preserved
// =============================================================================

/// Prediction result from the incremental recognition pipeline.
class InkPrediction {
  final String label;
  final List<String> candidates;
  final List<double> confidences;
  final double confidence;

  const InkPrediction({
    required this.label,
    required this.candidates,
    this.confidences = const [],
    this.confidence = 0.0,
  });

  bool get isEmpty => label.isEmpty && candidates.isEmpty;
  bool get isNotEmpty => !isEmpty;

  List<String> topCandidates({int max = 5, double minConfidence = 0.0}) {
    if (confidences.isEmpty) return candidates.take(max).toList();
    final filtered = <String>[];
    for (int i = 0; i < candidates.length && filtered.length < max; i++) {
      final conf = i < confidences.length ? confidences[i] : 0.5;
      if (conf >= minConfidence) filtered.add(candidates[i]);
    }
    return filtered;
  }

  @override
  String toString() =>
      'InkPrediction("$label", ${candidates.length} cands, conf=${confidence.toStringAsFixed(2)})';
}

/// Writing direction detected from stroke trajectory.
enum WritingDirection { ltr, rtl }

/// 🔮 Ink Prediction Service v5 — advanced-optimized singleton.
class InkPredictionService {
  InkPredictionService._();
  static final InkPredictionService instance = InkPredictionService._();

  static const MethodChannel _channel = MethodChannel(
    'fluera_engine/myscript_ink',
  );

  // ── Configuration ──────────────────────────────────────────────────────

  double confidenceThreshold = 0.25;
  double autoDistanceDismissThreshold = 300.0;
  static const double _rdpEpsilon = 2.0;
  static const int _maxWarmWords = 50;
  static const String _warmWordsFile = 'ink_pred_warm_words.txt';

  /// Threshold for offloading RDP to compute isolate.
  static const int _isolateThreshold = 100;

  // ── State ──────────────────────────────────────────────────────────────

  Timer? _debounceTimer;
  Timer? _autoClearTimer;

  bool _hasAccumulatedInk = false;
  bool get hasAccumulatedInk => _hasAccumulatedInk;

  int _strokeCount = 0;
  int get strokeCount => _strokeCount;

  InkPrediction? _lastPrediction;
  InkPrediction? get lastPrediction => _lastPrediction;

  Offset? _lastAnchorCanvas;
  Offset? get lastAnchorCanvas => _lastAnchorCanvas;

  WritingDirection _writingDirection = WritingDirection.ltr;
  WritingDirection get writingDirection => _writingDirection;

  final _predictionController = StreamController<InkPrediction?>.broadcast();
  Stream<InkPrediction?> get predictions => _predictionController.stream;

  // ── Cancellation Token ─────────────────────────────────────────────────

  /// Monotonically incrementing generation counter.
  /// If a new feedStroke arrives before the previous native call completes,
  /// the old result is discarded (stale generation).
  int _feedGeneration = 0;

  // ── Adaptive Debounce ──────────────────────────────────────────────────

  int _lastFeedTimeMs = 0;

  Duration get _adaptiveDebounce {
    final now = DateTime.now().millisecondsSinceEpoch;
    final delta = now - _lastFeedTimeMs;
    _lastFeedTimeMs = now;

    if (delta > 2000) {
      return const Duration(milliseconds: 120);
    }
    final t = ((delta - 300) / 500).clamp(0.0, 1.0);
    final ms = (200 - t * 120).round();
    return Duration(milliseconds: ms);
  }

  // ── Warm Words Cache + Debounced Persistence ──────────────────────────

  final _warmWords = LinkedHashMap<String, int>();
  Timer? _persistTimer;
  bool _persistDirty = false;

  void _recordWarmWord(String word) {
    final key = word.toLowerCase().trim();
    if (key.length < 2) return;
    _warmWords[key] = (_warmWords[key] ?? 0) + 1;
    while (_warmWords.length > _maxWarmWords) {
      _warmWords.remove(_warmWords.keys.first);
    }
    // 🚀 Debounced persistence: mark dirty, save at most 1x per 5s
    _persistDirty = true;
    _persistTimer ??= Timer(const Duration(seconds: 5), _flushWarmWords);
  }

  void _flushWarmWords() {
    _persistTimer = null;
    if (!_persistDirty) return;
    _persistDirty = false;
    _saveWarmWordsAsync();
  }

  List<String> _boostWarmCandidates(List<String> candidates) {
    if (_warmWords.isEmpty || candidates.length <= 1) return candidates;
    final boosted = List<String>.from(candidates);
    boosted.sort((a, b) {
      final fa = _warmWords[a.toLowerCase()] ?? 0;
      final fb = _warmWords[b.toLowerCase()] ?? 0;
      return fb.compareTo(fa);
    });
    return boosted;
  }

  /// 📖 Enrich prediction with dictionary word completions.
  /// If prefix is "Wor", adds ["World", "Working", "Workshop"] as top candidates.
  InkPrediction _enrichWithDictionary(InkPrediction prediction) {
    if (prediction.label.isEmpty) return prediction;

    // Look up completions from dictionary
    final completions = WordCompletionDictionary.instance.complete(
      prediction.label,
      maxResults: 5,
    );

    if (completions.isEmpty) return prediction;

    // Merge: dictionary completions FIRST, then MyScript alternatives
    final seen = <String>{};
    final merged = <String>[];
    final mergedConf = <double>[];

    // Add dictionary completions as top candidates (high confidence)
    for (final word in completions) {
      if (seen.add(word.toLowerCase())) {
        merged.add(word);
        mergedConf.add(0.92); // Dictionary matches → high confidence
      }
    }

    // Then add MyScript candidates (skip duplicates)
    for (int i = 0; i < prediction.candidates.length; i++) {
      if (seen.add(prediction.candidates[i].toLowerCase())) {
        merged.add(prediction.candidates[i]);
        mergedConf.add(i < prediction.confidences.length
            ? prediction.confidences[i]
            : 0.7);
      }
    }

    // Use the FIRST dictionary completion as the main label
    // (this is the "predicted word", not just what was recognized)
    final bestLabel = merged.isNotEmpty ? merged.first : prediction.label;

    return InkPrediction(
      label: bestLabel,
      candidates: merged.take(5).toList(),
      confidences: mergedConf.take(5).toList(),
      confidence: prediction.confidence,
    );
  }

  Future<void> loadWarmWords() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_warmWordsFile');
      if (!file.existsSync()) return;
      final lines = await file.readAsLines();
      _warmWords.clear();
      for (final line in lines) {
        final parts = line.split(':');
        if (parts.length == 2) {
          _warmWords[parts[0]] = int.tryParse(parts[1]) ?? 1;
        }
      }
      debugPrint('[InkPrediction] 📂 Loaded ${_warmWords.length} warm words');
    } catch (_) {}
  }

  void _saveWarmWordsAsync() {
    getApplicationDocumentsDirectory().then((dir) {
      final file = File('${dir.path}/$_warmWordsFile');
      final data = _warmWords.entries
          .map((e) => '${e.key}:${e.value}')
          .join('\n');
      file.writeAsString(data);
    }).catchError((_) {});
  }

  // ── Writing Direction Detection ────────────────────────────────────────

  void _detectWritingDirection(List<ProDrawingPoint> points) {
    if (points.length < 3) return;
    final dx = points.last.position.dx - points.first.position.dx;
    if (dx.abs() > 20) {
      _writingDirection = dx > 0 ? WritingDirection.ltr : WritingDirection.rtl;
    }
  }

  // ── Stroke Downsampling (RDP + Isolate for large strokes) ──────────────

  /// Top-level static function for compute() isolate compatibility.
  static List<_SimplePoint> _rdpIsolateEntry(_RdpInput input) {
    final result = _downsampleRDPSimple(input.points, input.epsilon);
    return result;
  }

  /// Downsample with optional isolate offload for large strokes.
  Future<List<ProDrawingPoint>> _downsample(
    List<ProDrawingPoint> points,
  ) async {
    if (points.length <= 3) return points;

    // 🚀 Offload to isolate for large strokes (>100 pts)
    if (points.length > _isolateThreshold) {
      final simplePoints = points
          .map((p) => _SimplePoint(
                p.position.dx,
                p.position.dy,
                p.timestamp.toDouble(),
                p.pressure,
              ))
          .toList();

      final result = await compute(
        _rdpIsolateEntry,
        _RdpInput(simplePoints, _rdpEpsilon),
      );

      // Map back to ProDrawingPoint using original objects where possible
      return _mapBackFromSimple(points, result);
    }

    // Inline RDP for small strokes
    return _downsampleRDP(points, _rdpEpsilon);
  }

  /// Map simplified points back to original ProDrawingPoint references.
  static List<ProDrawingPoint> _mapBackFromSimple(
    List<ProDrawingPoint> original,
    List<_SimplePoint> simplified,
  ) {
    // Match by (x,y) — RDP preserves exact coordinates
    final result = <ProDrawingPoint>[];
    int oi = 0;
    for (final sp in simplified) {
      while (oi < original.length) {
        final op = original[oi];
        if (op.position.dx == sp.x && op.position.dy == sp.y) {
          result.add(op);
          oi++;
          break;
        }
        oi++;
      }
    }
    // Ensure we at least have first and last
    if (result.isEmpty && original.isNotEmpty) {
      return [original.first, original.last];
    }
    return result;
  }

  static List<ProDrawingPoint> _downsampleRDP(
    List<ProDrawingPoint> points,
    double epsilon,
  ) {
    if (points.length <= 3) return points;

    double maxDist = 0;
    int maxIdx = 0;
    final first = points.first.position;
    final last = points.last.position;
    final lineLen = (last - first).distance;

    for (int i = 1; i < points.length - 1; i++) {
      final d = lineLen > 0
          ? _perpendicularDistance(points[i].position, first, last)
          : (points[i].position - first).distance;
      if (d > maxDist) {
        maxDist = d;
        maxIdx = i;
      }
    }

    if (maxDist > epsilon) {
      final left = _downsampleRDP(points.sublist(0, maxIdx + 1), epsilon);
      final right = _downsampleRDP(points.sublist(maxIdx), epsilon);
      return [...left.sublist(0, left.length - 1), ...right];
    }

    return [points.first, points.last];
  }

  /// RDP on simple data (isolate-safe — no Flutter imports).
  static List<_SimplePoint> _downsampleRDPSimple(
    List<_SimplePoint> points,
    double epsilon,
  ) {
    if (points.length <= 3) return points;

    double maxDist = 0;
    int maxIdx = 0;
    final first = points.first;
    final last = points.last;
    final dx = last.x - first.x;
    final dy = last.y - first.y;
    final lineLen = math.sqrt(dx * dx + dy * dy);

    for (int i = 1; i < points.length - 1; i++) {
      final p = points[i];
      final d = lineLen > 0
          ? _perpDistSimple(p.x, p.y, first.x, first.y, last.x, last.y)
          : math.sqrt(
              (p.x - first.x) * (p.x - first.x) +
                  (p.y - first.y) * (p.y - first.y),
            );
      if (d > maxDist) {
        maxDist = d;
        maxIdx = i;
      }
    }

    if (maxDist > epsilon) {
      final left =
          _downsampleRDPSimple(points.sublist(0, maxIdx + 1), epsilon);
      final right = _downsampleRDPSimple(points.sublist(maxIdx), epsilon);
      return [...left.sublist(0, left.length - 1), ...right];
    }

    return [points.first, points.last];
  }

  static double _perpendicularDistance(Offset p, Offset a, Offset b) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final lenSq = dx * dx + dy * dy;
    if (lenSq == 0) return (p - a).distance;
    final t = ((p.dx - a.dx) * dx + (p.dy - a.dy) * dy) / lenSq;
    final proj = Offset(a.dx + t * dx, a.dy + t * dy);
    return (p - proj).distance;
  }

  static double _perpDistSimple(
    double px,
    double py,
    double ax,
    double ay,
    double bx,
    double by,
  ) {
    final dx = bx - ax;
    final dy = by - ay;
    final lenSq = dx * dx + dy * dy;
    if (lenSq == 0) return math.sqrt((px - ax) * (px - ax) + (py - ay) * (py - ay));
    final t = ((px - ax) * dx + (py - ay) * dy) / lenSq;
    final projX = ax + t * dx;
    final projY = ay + t * dy;
    return math.sqrt((px - projX) * (px - projX) + (py - projY) * (py - projY));
  }

  // ── Public API ─────────────────────────────────────────────────────────

  Future<InkPrediction?> feedStroke(
    List<ProDrawingPoint> points, {
    Offset? canvasAnchor,
  }) async {
    if (points.length < 2) return null;

    _detectWritingDirection(points);

    // Auto-dismiss on distant stroke
    if (canvasAnchor != null &&
        _lastAnchorCanvas != null &&
        _hasAccumulatedInk) {
      final dist = (canvasAnchor - _lastAnchorCanvas!).distance;
      if (dist > autoDistanceDismissThreshold) {
        await clear();
      }
    }
    if (canvasAnchor != null) _lastAnchorCanvas = canvasAnchor;

    _hasAccumulatedInk = true;
    _strokeCount++;

    _autoClearTimer?.cancel();
    _autoClearTimer = Timer(const Duration(seconds: 3), () => clear());

    // 🔮 Skip downsampling — Kotlin side accumulates and re-feeds ALL strokes.
    // Full point data is needed for accurate Text recognition.
    final strokeData = points;

    // 🚀 Cancellation: increment generation
    final generation = ++_feedGeneration;

    // 🔮 Fire prediction immediately — no debounce.
    // Kotlin side accumulates strokes and re-feeds efficiently.
    // Generation-based cancellation still prevents stale results.
    _debounceTimer?.cancel();
    final completer = Completer<InkPrediction?>();

    () async {
      try {
        // Check if this generation is still current
        if (generation != _feedGeneration) {
          completer.complete(null);
          return;
        }

        final result = await _feedStrokeNative(strokeData);

        // Note: We no longer discard stale results — every prediction
        // is valuable and updates the bubble progressively.

        if (result != null && result.confidence < confidenceThreshold) {
          _lastPrediction = null;
          _predictionController.add(null);
          completer.complete(null);
          return;
        }

        final boosted = result != null
            ? _enrichWithDictionary(InkPrediction(
                label: result.label,
                candidates: _boostWarmCandidates(result.candidates),
                confidences: result.confidences,
                confidence: result.confidence,
              ))
            : null;

        // 🚀 Skip duplicate: same label → don't re-emit → no UI rebuild
        if (boosted != null &&
            _lastPrediction != null &&
            boosted.label == _lastPrediction!.label &&
            boosted.confidence == _lastPrediction!.confidence) {
          completer.complete(boosted);
          return; // No stream emission — UI already shows this
        }

        // Haptic tick on label change
        if (boosted != null &&
            _lastPrediction != null &&
            boosted.label != _lastPrediction!.label) {
          HapticFeedback.selectionClick();
        }

        _lastPrediction = boosted;
        _predictionController.add(boosted);
        completer.complete(boosted);
      } catch (e) {
        debugPrint('[InkPrediction] ❌ Feed failed: $e');
        completer.complete(null);
      }
    }();

    return completer.future;
  }

  Future<String?> acceptPrediction() async {
    final label = _lastPrediction?.label;
    if (label != null && label.isNotEmpty) {
      _recordWarmWord(label);
    }
    await clear();
    return label;
  }

  Future<void> clear() async {
    _debounceTimer?.cancel();
    _autoClearTimer?.cancel();
    _feedGeneration++; // Cancel any in-flight native calls
    _hasAccumulatedInk = false;
    _strokeCount = 0;
    _lastPrediction = null;
    _lastAnchorCanvas = null;
    _predictionController.add(null);

    try {
      await _channel.invokeMethod('clearPrediction');
    } catch (e) {
      debugPrint('[InkPrediction] ⚠️ Clear failed: $e');
    }
  }

  void dispose() {
    _debounceTimer?.cancel();
    _autoClearTimer?.cancel();
    _persistTimer?.cancel();
    _flushWarmWords(); // Final flush
    _predictionController.close();
  }

  // ── Native Bridge ──────────────────────────────────────────────────────

  Future<InkPrediction?> _feedStrokeNative(
    List<ProDrawingPoint> points,
  ) async {
    final strokeData = points.map((p) => {
      'x': p.position.dx,
      'y': p.position.dy,
      't': p.timestamp,
      'f': p.pressure,
    }).toList();

    final result = await _channel.invokeMethod<Map>('feedStroke', {
      'stroke': strokeData,
    });

    if (result == null) return null;

    final label = result['label'] as String? ?? '';
    final candidatesRaw = result['candidates'] as List<dynamic>? ?? [];
    final candidates = candidatesRaw.cast<String>().toList();
    final confidencesRaw = result['confidences'] as List<dynamic>? ?? [];
    final confidences =
        confidencesRaw.map((c) => (c as num).toDouble()).toList();
    final confidence = (result['confidence'] as num?)?.toDouble() ?? 0.0;

    final prediction = InkPrediction(
      label: label,
      candidates: candidates,
      confidences: confidences,
      confidence: confidence,
    );
    return prediction.isEmpty ? null : prediction;
  }
}

// ── Isolate-safe data types ──────────────────────────────────────────────────

/// Minimal point representation for compute() isolate (no Offset dependency).
class _SimplePoint {
  final double x, y, t, f;
  const _SimplePoint(this.x, this.y, this.t, this.f);
}

/// Input for the RDP isolate computation.
class _RdpInput {
  final List<_SimplePoint> points;
  final double epsilon;
  const _RdpInput(this.points, this.epsilon);
}
