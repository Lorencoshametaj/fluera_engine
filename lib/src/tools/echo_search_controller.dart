import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../drawing/models/pro_drawing_point.dart';
import '../services/digital_ink_service.dart';
import '../services/handwriting_index_service.dart';

// =============================================================================
// 🔍 ECHO SEARCH CONTROLLER — Jarvis-style Spatial Search State Machine
//
// State: idle → drawing → recognizing → previewing → flyingTo → idle
//        ↘ fadingOut → idle
//
// Final Boss enhancements:
//   ⚡ Live OCR Preview (debounced partial recognition)
//   📐 Smart Auto-Trigger (velocity-based writing completion)
//   📌 Pin Results (persistent markers)
//   🔄 Search History (recent queries)
//   🎨 Adaptive Glow (brush color passthrough)
// =============================================================================

enum EchoSearchPhase {
  idle, drawing, recognizing, previewing, flyingTo, fadingOut,
}

typedef EchoNavigateCallback = void Function(HandwritingSearchResult result);
typedef EchoToastCallback = void Function(String message);

/// A pinned search result marker that persists after echo search dismisses.
class EchoPinMarker {
  final ui.Offset center;
  final ui.Rect bounds;
  final String text;
  final int createdMs;

  EchoPinMarker({
    required this.center,
    required this.bounds,
    required this.text,
    int? createdMs,
  }) : createdMs = createdMs ?? DateTime.now().millisecondsSinceEpoch;
}

class EchoSearchController extends ChangeNotifier {
  EchoSearchController({
    required this.canvasId,
    required this.onNavigate,
    required this.onToast,
    this.onDismiss,
    this.autoTriggerDelay = const Duration(seconds: 2),
    this.accentColor,
  });

  final String? canvasId;
  final EchoNavigateCallback onNavigate;
  final EchoToastCallback onToast;
  final VoidCallback? onDismiss;
  final Duration autoTriggerDelay;

  /// 🎨 Adaptive glow: brush color passed from canvas.
  ui.Color? accentColor;

  // ── State ──────────────────────────────────────────────────────────────────

  EchoSearchPhase _phase = EchoSearchPhase.idle;
  EchoSearchPhase get phase => _phase;

  final List<List<ProDrawingPoint>> _strokeSets = [];
  List<ProDrawingPoint> _currentStrokePoints = [];

  String? _recognizedQuery;
  String? get recognizedQuery => _recognizedQuery;

  /// ⚡ Live OCR preview text (updates during writing).
  String? _livePreviewText;
  String? get livePreviewText => _livePreviewText;

  List<HandwritingSearchResult> _results = [];
  List<HandwritingSearchResult> get results => _results;

  int _activeResultIndex = 0;
  int get activeResultIndex => _activeResultIndex;
  int get resultCount => _results.length;

  Timer? _autoTriggerTimer;
  Timer? _liveOcrTimer;

  /// Throttle counter: only notify every Nth addPoint call.
  int _pointThrottleCount = 0;
  static const int _pointNotifyInterval = 3;

  int _fadeOutStartMs = 0;
  int get fadeOutStartMs => _fadeOutStartMs;

  ui.Offset? _sonarTarget;
  ui.Offset? get sonarTarget => _sonarTarget;
  int _sonarStartMs = 0;
  int get sonarStartMs => _sonarStartMs;

  List<String> _alternatives = [];
  List<String> get alternatives => _alternatives;

  bool _showKeyboardFallback = false;
  bool get showKeyboardFallback => _showKeyboardFallback;

  /// 📌 Pinned result markers.
  final List<EchoPinMarker> _pins = [];
  List<EchoPinMarker> get pins => List.unmodifiable(_pins);

  /// 🔄 Search history (static, persists across sessions).
  static final List<String> _searchHistory = [];
  List<String> get searchHistory => List.unmodifiable(_searchHistory);

  /// 📐 Smart auto-trigger: stroke velocity tracking.
  double _lastStrokeVelocity = 0;
  int _lastStrokeEndMs = 0;

  String get resultSnippet {
    if (_results.isEmpty || _activeResultIndex >= _results.length) return '';
    final r = _results[_activeResultIndex];
    final text = r.recognizedText;
    if (text.length <= 40) return text;
    return '...${text.substring(0, 37)}...';
  }

  String get hudStatusText {
    switch (_phase) {
      case EchoSearchPhase.idle:
        if (_livePreviewText != null && _livePreviewText!.isNotEmpty) {
          return '✍️ "$_livePreviewText"';
        }
        return '🔍 Query Pen Ready';
      case EchoSearchPhase.drawing:
        if (_livePreviewText != null && _livePreviewText!.isNotEmpty) {
          return '✍️ "$_livePreviewText"';
        }
        return '✍️ Writing...';
      case EchoSearchPhase.recognizing:
        return '🧠 Recognizing...';
      case EchoSearchPhase.previewing:
        return '📝 "$_recognizedQuery"';
      case EchoSearchPhase.flyingTo:
        final idx = _activeResultIndex + 1;
        final total = _results.length;
        return '🚀 Result $idx/$total';
      case EchoSearchPhase.fadingOut:
        return '✨ Clearing...';
    }
  }

  /// Direct references (no defensive copy — painter is read-only).
  List<List<ProDrawingPoint>> get committedStrokes => _strokeSets;
  List<ProDrawingPoint> get currentPoints => _currentStrokePoints;
  bool get isActive => _phase != EchoSearchPhase.idle || _strokeSets.isNotEmpty;

  // ── Stroke Input ──────────────────────────────────────────────────────────

  void startStroke(ProDrawingPoint point) {
    _phase = EchoSearchPhase.drawing;
    _currentStrokePoints = [point];
    _autoTriggerTimer?.cancel();
    _liveOcrTimer?.cancel(); // Cancel pending live OCR on new stroke
    _pointThrottleCount = 0;
    _showKeyboardFallback = false;
    _alternatives = [];
    HapticFeedback.lightImpact();
    notifyListeners();
  }

  void addPoint(ProDrawingPoint point) {
    if (_phase != EchoSearchPhase.drawing) return;
    _currentStrokePoints.add(point);
    // Throttle: only notify every Nth point to reduce repaints
    _pointThrottleCount++;
    if (_pointThrottleCount % _pointNotifyInterval != 0) return;
    notifyListeners();
  }

  void endStroke() {
    if (_currentStrokePoints.length >= 3) {
      _strokeSets.add(List.from(_currentStrokePoints));

      // 📐 Compute stroke velocity for smart auto-trigger
      _computeStrokeVelocity(_currentStrokePoints);
    }
    _currentStrokePoints = [];
    notifyListeners();

    // ⚡ Debounced live OCR preview (500ms after stroke end)
    _liveOcrTimer?.cancel();
    _liveOcrTimer = Timer(const Duration(milliseconds: 500), _liveOcrPreview);

    // 📐 Smart auto-trigger: use velocity-based delay
    _autoTriggerTimer?.cancel();
    final smartDelay = _computeSmartDelay();
    _autoTriggerTimer = Timer(smartDelay, _triggerRecognition);
  }

  void triggerNow() {
    _autoTriggerTimer?.cancel();
    _liveOcrTimer?.cancel();
    _triggerRecognition();
  }

  // ── 📐 Smart Auto-Trigger ────────────────────────────────────────────────

  void _computeStrokeVelocity(List<ProDrawingPoint> points) {
    if (points.length < 5) {
      _lastStrokeVelocity = 0;
      _lastStrokeEndMs = DateTime.now().millisecondsSinceEpoch;
      return;
    }

    // Compute average velocity from last 5 points
    double totalDist = 0;
    int totalTime = 0;
    final tail = points.sublist(math.max(0, points.length - 6));
    for (int i = 1; i < tail.length; i++) {
      totalDist += (tail[i].position - tail[i - 1].position).distance;
      totalTime += (tail[i].timestamp - tail[i - 1].timestamp).abs();
    }
    _lastStrokeVelocity = totalTime > 0 ? totalDist / totalTime : 0;
    _lastStrokeEndMs = DateTime.now().millisecondsSinceEpoch;
  }

  /// Calculate smart delay based on writing velocity.
  /// Fast writing → longer delay (user is still going).
  /// Slow/pause → shorter delay (user is done).
  Duration _computeSmartDelay() {
    if (_lastStrokeVelocity <= 0) return autoTriggerDelay;

    // velocity in px/ms: typical fast writing is ~0.5-1.0, slow is ~0.1-0.3
    if (_lastStrokeVelocity > 0.6) {
      // Fast writing: wait longer (user is still going)
      return const Duration(milliseconds: 2500);
    } else if (_lastStrokeVelocity > 0.3) {
      // Medium pace
      return const Duration(milliseconds: 1800);
    } else {
      // Slow/deliberate: trigger sooner
      return const Duration(milliseconds: 1200);
    }
  }

  // ── ⚡ Live OCR Preview ───────────────────────────────────────────────────

  Future<void> _liveOcrPreview() async {
    if (_strokeSets.isEmpty || _phase != EchoSearchPhase.drawing) return;

    try {
      final inkService = DigitalInkService.instance;
      if (!inkService.isAvailable || !inkService.isReady) return;

      String? text;
      if (_strokeSets.length == 1) {
        text = await inkService.recognizeStroke(_strokeSets.first);
      } else {
        text = await inkService.recognizeMultiStroke(_strokeSets);
      }

      if (text != null && text.trim().isNotEmpty &&
          _phase == EchoSearchPhase.drawing) {
        _livePreviewText = text.trim();
        notifyListeners();
      }
    } catch (_) {
      // Silently ignore live preview errors
    }
  }

  // ── Multi-Result Navigation ───────────────────────────────────────────────

  void nextResult() {
    if (_results.isEmpty) return;
    _activeResultIndex = (_activeResultIndex + 1) % _results.length;
    _triggerSonar(_results[_activeResultIndex]);
    HapticFeedback.selectionClick();
    notifyListeners();
    onNavigate(_results[_activeResultIndex]);
  }

  void previousResult() {
    if (_results.isEmpty) return;
    _activeResultIndex = (_activeResultIndex - 1 + _results.length) % _results.length;
    _triggerSonar(_results[_activeResultIndex]);
    HapticFeedback.selectionClick();
    notifyListeners();
    onNavigate(_results[_activeResultIndex]);
  }

  // ── 📌 Pin Results ────────────────────────────────────────────────────────

  /// Pin the current result as a persistent marker.
  void pinCurrentResult() {
    if (_results.isEmpty || _activeResultIndex >= _results.length) return;
    if (_pins.length >= 10) _pins.removeAt(0); // Cap at 10 pins
    final r = _results[_activeResultIndex];
    _pins.add(EchoPinMarker(
      center: r.bounds.center,
      bounds: r.bounds,
      text: r.recognizedText,
    ));
    HapticFeedback.mediumImpact();
    notifyListeners();
  }

  /// Remove a pin by index.
  void removePin(int index) {
    if (index >= 0 && index < _pins.length) {
      _pins.removeAt(index);
      notifyListeners();
    }
  }

  /// Clear all pins.
  void clearPins() {
    _pins.clear();
    notifyListeners();
  }

  // ── 🔄 Search History ─────────────────────────────────────────────────────

  /// Search a query from history.
  void searchFromHistory(String query) {
    _recognizedQuery = query;
    _showKeyboardFallback = false;
    _alternatives = [];
    _phase = EchoSearchPhase.previewing;
    notifyListeners();
    Future.delayed(const Duration(milliseconds: 500), _searchAndNavigate);
  }

  void _addToHistory(String query) {
    _searchHistory.remove(query); // Dedupe
    _searchHistory.insert(0, query);
    if (_searchHistory.length > 5) {
      _searchHistory.removeRange(5, _searchHistory.length);
    }
  }

  // ── Query Alternatives ────────────────────────────────────────────────────

  void searchAlternative(String text) {
    _recognizedQuery = text;
    _alternatives = [];
    _showKeyboardFallback = false;
    notifyListeners();
    _searchAndNavigate();
  }

  void searchKeyboard(String text) {
    if (text.trim().isEmpty) return;
    _recognizedQuery = text.trim();
    _showKeyboardFallback = false;
    _alternatives = [];
    _phase = EchoSearchPhase.previewing;
    HapticFeedback.selectionClick();
    notifyListeners();
    Future.delayed(const Duration(milliseconds: 500), _searchAndNavigate);
  }

  // ── Recognition & Search ──────────────────────────────────────────────────

  Future<void> _triggerRecognition() async {
    if (_strokeSets.isEmpty) {
      _phase = EchoSearchPhase.idle;
      notifyListeners();
      return;
    }

    _phase = EchoSearchPhase.recognizing;
    HapticFeedback.mediumImpact();
    notifyListeners();

    try {
      final inkService = DigitalInkService.instance;
      if (!inkService.isAvailable || !inkService.isReady) {
        await inkService.init();
        if (!inkService.isReady) {
          onToast('Digital Ink not available');
          _showKeyboardFallback = true;
          _phase = EchoSearchPhase.idle;
          notifyListeners();
          return;
        }
      }

      // Use live preview if available, otherwise recognize
      String? text = _livePreviewText;
      if (text == null || text.isEmpty) {
        if (_strokeSets.length == 1) {
          text = await inkService.recognizeStroke(_strokeSets.first);
        } else {
          text = await inkService.recognizeMultiStroke(_strokeSets);
        }
      }

      if (text == null || text.trim().isEmpty) {
        _showKeyboardFallback = true;
        _phase = EchoSearchPhase.idle;
        notifyListeners();
        onToast('Could not recognize — try typing');
        return;
      }

      _recognizedQuery = text.trim();
      _livePreviewText = null;
      debugPrint('🔍 [EchoSearch] Recognized: "$_recognizedQuery"');

      _alternatives = _generateAlternatives(_recognizedQuery!);

      _phase = EchoSearchPhase.previewing;
      HapticFeedback.selectionClick();
      notifyListeners();

      await Future.delayed(const Duration(milliseconds: 800));
      await _searchAndNavigate();

    } catch (e) {
      debugPrint('🔍 [EchoSearch] Error: $e');
      _showKeyboardFallback = true;
      _phase = EchoSearchPhase.idle;
      notifyListeners();
      onToast('Recognition failed — try typing');
    }
  }

  Future<void> _searchAndNavigate() async {
    try {
      // 🔄 Add to history
      if (_recognizedQuery != null) {
        _addToHistory(_recognizedQuery!);
      }

      final results = await HandwritingIndexService.instance.searchUnified(
        _recognizedQuery!,
        canvasId: canvasId,
        limit: 20,
        fuzzy: true,
      );

      if (results.isEmpty) {
        onToast('No results for "$_recognizedQuery"');
        _startFadeOut();
        return;
      }

      _results = results;
      _activeResultIndex = 0;
      _phase = EchoSearchPhase.flyingTo;
      HapticFeedback.heavyImpact();
      _triggerSonar(results.first);
      notifyListeners();
      onNavigate(results.first);

    } catch (e) {
      debugPrint('🔍 [EchoSearch] Search error: $e');
      onToast('Search failed');
      _startFadeOut();
    }
  }

  void _triggerSonar(HandwritingSearchResult result) {
    _sonarTarget = result.bounds.center;
    _sonarStartMs = DateTime.now().millisecondsSinceEpoch;
  }

  List<String> _generateAlternatives(String text) {
    if (text.length < 3) return [];
    final alts = <String>[];
    const confusions = {
      'l': 'i', 'i': 'l', 'o': '0', '0': 'o',
      'e': 'c', 'c': 'e', 'n': 'r', 'r': 'n',
      'a': 'o', 'u': 'v', 'v': 'u',
    };
    for (int i = 0; i < text.length && alts.length < 2; i++) {
      final ch = text[i].toLowerCase();
      if (confusions.containsKey(ch)) {
        final alt = text.substring(0, i) +
            (text[i] == text[i].toUpperCase()
                ? confusions[ch]!.toUpperCase()
                : confusions[ch]!) +
            text.substring(i + 1);
        if (alt != text && !alts.contains(alt)) alts.add(alt);
      }
    }
    return alts;
  }

  void _startFadeOut() {
    _phase = EchoSearchPhase.fadingOut;
    _fadeOutStartMs = DateTime.now().millisecondsSinceEpoch;
    notifyListeners();
    Future.delayed(const Duration(milliseconds: 600), () {
      if (_phase == EchoSearchPhase.fadingOut) _resetToIdle();
    });
  }

  void beginFadeOut() => _startFadeOut();

  void _resetToIdle() {
    _phase = EchoSearchPhase.idle;
    _strokeSets.clear();
    _currentStrokePoints = [];
    _recognizedQuery = null;
    _livePreviewText = null;
    _results = [];
    _activeResultIndex = 0;
    _fadeOutStartMs = 0;
    _sonarTarget = null;
    _sonarStartMs = 0;
    _alternatives = [];
    _showKeyboardFallback = false;
    _lastStrokeVelocity = 0;
    notifyListeners();
  }

  void dismiss() {
    _autoTriggerTimer?.cancel();
    _liveOcrTimer?.cancel();
    if (_strokeSets.isNotEmpty || _phase != EchoSearchPhase.idle) {
      _startFadeOut();
      Future.delayed(const Duration(milliseconds: 650), () {
        onDismiss?.call();
      });
    } else {
      _resetToIdle();
      onDismiss?.call();
    }
  }

  @override
  void dispose() {
    _autoTriggerTimer?.cancel();
    _liveOcrTimer?.cancel();
    super.dispose();
  }
}
