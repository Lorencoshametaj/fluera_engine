// ============================================================================
// 🖋️ MINI CANVAS SCRATCHPAD — Stylus-first answer surface for the exam.
//
// Replaces [HandwritingScratchpad] in the ExamAnswerFullscreen. Adds three
// behaviours that align with Fluera's main canvas promise:
//
//   1. **Two-finger pinch zoom** + **two-finger pan** — the answer area is
//      no longer "small". A student writing a long derivation can zoom out
//      to fit, zoom in for clean lettering, pan to find space.
//   2. **One-finger pan** when no stylus is engaged — same as the main
//      canvas. Stylus down → drawing; finger down without stylus → pan.
//   3. **Strokes persist** — no more fade-out after OCR. The stroke list
//      is preserved across rebuilds and (when [persistKey] is set) across
//      app restarts via [ExamStrokeStorage]. Students can revisit prior
//      handwritten answers later.
//
// Architecture choices (vs. main canvas):
//   • Local _scale + _offset state (no [InfiniteCanvasController] physics) —
//     simpler, no momentum or spring needed in a small embedded surface.
//   • Lightweight painter — no LOD, no R-tree, no tile caching. The stroke
//     count per question is bounded (~200-500 strokes max per answer).
//   • [PointerDeviceKind]-only palm rejection. The full canvas's adaptive
//     palm filter (HandednessSettings) is overkill for an embedded area.
//
// Public API mirrors [HandwritingScratchpad] so callers can swap with a
// minimal diff:
//   • [hasUnconfirmedStrokes] — true when strokes drew but OCR debounce
//     hasn't fired yet → ExamAnswerFullscreen guards "Conferma" with this.
//   • [flushPendingRecognition] — force-runs OCR (cancels debounce) and
//     awaits the result so the caller can submit the freshest text.
// New API:
//   • [currentStrokes] — read-only list for persistence.
//   • [loadStrokes] — replaces the stroke list (used on initial mount when
//     resuming a previously-saved answer).
// ============================================================================

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../drawing/models/pro_drawing_point.dart';
import '../../../services/digital_ink_service.dart';
import '../../../utils/uid.dart';

/// Public state class — exposed so callers can grab a [GlobalKey] and
/// invoke the imperative methods ([flushPendingRecognition], [loadStrokes],
/// [currentStrokes], [hasUnconfirmedStrokes]).
class MiniCanvasScratchpadState extends State<MiniCanvasScratchpad>
    with TickerProviderStateMixin {
  // ── Stroke state ─────────────────────────────────────────────────────────
  final List<ProStroke> _strokes = [];
  /// Currently-drawn (incomplete) stroke. Stored separately so the painter
  /// can render the incomplete polyline efficiently.
  final List<ProDrawingPoint> _activePoints = [];
  /// Identity of the pointer that started the active stroke. Other pointers
  /// arriving while this one is down are treated as palm/touch — used for
  /// pinch zoom resolution but never for drawing.
  int? _drawingPointerId;

  // ── Camera state (zoom/pan) ──────────────────────────────────────────────
  double _scale = 1.0;
  Offset _offset = Offset.zero;
  static const double _minScale = 0.5;
  static const double _maxScale = 4.0;

  // ── Path cache for repaint perf ──────────────────────────────────────────
  // Each [ProStroke] is immutable post-commit, so its rendered Path can be
  // computed once and reused on every pan/zoom frame. Without this, the
  // painter rebuilds N polylines × M segments per frame, allocating a
  // fresh [Paint] per segment — hot path during fluent pinch-zoom on a
  // canvas with 100+ strokes.
  // Keyed by stroke.id; entries removed on undo/clear.
  final Map<String, ui.Path> _pathCache = {};

  // ── Repaint trigger ──────────────────────────────────────────────────────
  // Drives the painter's `repaint:` Listenable. Bumped on every mutation of
  // [_strokes] or [_activePoints]. Fixes a class of bug where `shouldRepaint`
  // returns false because both `old` and `new` painters hold the SAME list
  // reference — comparing `length` or identity yields no diff. Same pattern
  // as [CurrentStrokePainter] in the main canvas (current_stroke_painter.dart
  // lines 111-114): a `ValueNotifier<int>` whose `value++` cycles trigger a
  // repaint via the framework, bypassing `shouldRepaint` entirely.
  final ValueNotifier<int> _repaintTrigger = ValueNotifier<int>(0);
  void _bumpRepaint() => _repaintTrigger.value++;

  // Multi-touch: track all active pointers for pinch detection.
  final Map<int, Offset> _activePointers = {};
  // Captured at the start of a pinch gesture.
  double? _pinchStartDistance;
  Offset? _pinchStartFocal;
  double _pinchStartScale = 1.0;
  Offset _pinchStartOffset = Offset.zero;

  // ── OCR debounce ─────────────────────────────────────────────────────────
  Timer? _debounceTimer;
  bool _isRecognizing = false;
  late final AnimationController _countdownController;
  /// Hash of the stroke set captured at the last successful OCR call.
  /// Used to skip redundant Gemini/MyScript invocations when the user
  /// pans/zooms during a debounce window without modifying the strokes.
  /// `null` means "never recognised yet — always run the next OCR".
  int? _lastRecognizedHash;
  String? _lastRecognizedText;

  // ── Auto-save throttle ───────────────────────────────────────────────────
  // Coalesces bursts of pen-up events into one I/O call per second so
  // fluent writing doesn't hammer the disk. The trailing-edge call after
  // the last change is guaranteed via [_savePendingChanges].
  Timer? _saveThrottleTimer;
  bool _savePending = false;
  static const _saveThrottle = Duration(seconds: 1);

  void _scheduleAutoSave() {
    if (widget.onStrokesChanged == null) return;
    _savePending = true;
    if (_saveThrottleTimer?.isActive ?? false) return;
    // Fire immediately (leading edge) for the first save in a burst, then
    // throttle subsequent saves.
    _flushAutoSave();
    _saveThrottleTimer = Timer(_saveThrottle, () {
      if (!mounted) return;
      if (_savePending) _flushAutoSave();
    });
  }

  void _flushAutoSave() {
    if (!_savePending || widget.onStrokesChanged == null) return;
    _savePending = false;
    widget.onStrokesChanged!(List<ProStroke>.from(_strokes));
  }

  // ── Lifecycle ────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _countdownController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..addListener(() {
        if (mounted) setState(() {}); // for the progress bar
      });
    if (widget.initialStrokes != null && widget.initialStrokes!.isNotEmpty) {
      _strokes.addAll(widget.initialStrokes!);
      _bumpRepaint();
      // Defer fit-to-content until after first layout so we have a real
      // surface size to compute the bbox-to-viewport mapping.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fitToContent();
      });
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _saveThrottleTimer?.cancel();
    // Final flush so any pending strokes from the trailing-edge window
    // hit disk before the parent unmounts. Caller's onStrokesChanged is
    // expected to be safe to call from dispose (fire-and-forget I/O).
    if (_savePending) _flushAutoSave();
    _countdownController.dispose();
    _repaintTrigger.dispose();
    super.dispose();
  }

  // ── Public API ───────────────────────────────────────────────────────────

  /// True while strokes have been drawn but the OCR debounce hasn't fired
  /// (or is in flight). Guards "submit" so the last word isn't lost.
  bool get hasUnconfirmedStrokes =>
      _activePoints.isNotEmpty ||
      _isRecognizing ||
      (_debounceTimer?.isActive ?? false);

  /// Force-runs OCR (skipping the 1.2s debounce) and awaits completion.
  /// No-op if no strokes are pending. Used by ExamAnswerFullscreen before
  /// the user taps "Conferma" so the freshest text reaches `_answerCtrl`.
  Future<void> flushPendingRecognition() async {
    _debounceTimer?.cancel();
    _countdownController.reset();
    if (_strokes.isEmpty && _activePoints.isEmpty) return;
    await _recognize();
  }

  /// Snapshot of every committed stroke. Used by the storage layer to
  /// persist on submit / dispose. Excludes the in-flight stroke (if any) —
  /// it'll be persisted automatically on pen-up.
  List<ProStroke> get currentStrokes => List.unmodifiable(_strokes);

  /// Replaces the stroke list. Use this on initial mount to restore a
  /// previously-saved answer. Triggers a debounced OCR pass on the loaded
  /// strokes so `_answerCtrl` is hydrated. Defers an auto-fit pass to the
  /// next frame so strokes drawn off-screen in a prior session aren't
  /// "invisible" — the camera reframes to show all loaded strokes.
  void loadStrokes(List<ProStroke> strokes) {
    _pathCache.clear();
    setState(() {
      _strokes
        ..clear()
        ..addAll(strokes);
    });
    _bumpRepaint();
    if (_strokes.isNotEmpty) {
      _scheduleRecognition();
      // Wait for layout so we know our paint surface size.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fitToContent();
      });
    }
  }

  /// Reframes the camera so every committed stroke is visible with a 10%
  /// padding margin. Called after [loadStrokes] and exposed as a public
  /// gesture (button "fit") for the user. No-op on empty stroke list.
  void _fitToContent() {
    if (_strokes.isEmpty) return;
    // Aggregate bounds in canvas-space (strokes are stored in canvas-space).
    Rect? union;
    for (final s in _strokes) {
      final b = s.bounds;
      union = union == null ? b : union.expandToInclude(b);
    }
    if (union == null || union.isEmpty) return;
    // Need the surface size — read from the rendered context.
    final rb = context.findRenderObject();
    if (rb is! RenderBox || !rb.hasSize) return;
    final size = rb.size;
    if (size.width <= 0 || size.height <= 0) return;
    // 10% padding on each side.
    const padding = 0.10;
    final viewW = size.width * (1 - 2 * padding);
    final viewH = size.height * (1 - 2 * padding);
    final scaleX = viewW / union.width;
    final scaleY = viewH / union.height;
    final newScale = math.min(scaleX, scaleY).clamp(_minScale, _maxScale);
    // Centre the union rect in the view: viewport_centre = union_centre * scale + offset.
    final viewCentre = Offset(size.width / 2, size.height / 2);
    final newOffset = viewCentre - union.center * newScale;
    setState(() {
      _scale = newScale.toDouble();
      _offset = newOffset;
    });
  }

  // ── Pointer dispatch ─────────────────────────────────────────────────────

  void _beginPinch() {
    final pts = _activePointers.values.toList();
    _pinchStartDistance = (pts[0] - pts[1]).distance;
    _pinchStartFocal = (pts[0] + pts[1]) / 2;
    _pinchStartScale = _scale;
    _pinchStartOffset = _offset;
  }

  /// Resolves the in-flight stroke when a pinch starts mid-write.
  /// If the user had already drawn ≥2 points, COMMIT the stroke instead
  /// of discarding it — losing a half-finished formula because the user
  /// rested a thumb on the tablet to stabilise it is a worse failure
  /// than a stray short stroke. Single-point in-flight strokes (taps
  /// before pinch) are still discarded — they're never meaningful
  /// handwriting.
  void _cancelActiveStroke() {
    if (_drawingPointerId == null) return;
    _drawingPointerId = null;
    if (_activePoints.isEmpty) return;
    if (_activePoints.length >= 2) {
      // Promote to a committed stroke. Mirrors the commit path in
      // _onPointerUp so cache + autosave + OCR fire as expected.
      final stroke = ProStroke(
        id: 'exam_${generateUid()}',
        points: List<ProDrawingPoint>.from(_activePoints),
        color: widget.inkColor,
        baseWidth: 2.5,
        penType: ProPenType.ballpoint,
        createdAt: DateTime.now(),
      );
      setState(() {
        _strokes.add(stroke);
        _activePoints.clear();
      });
      // Mirror _onPointerUp: pre-warm the path cache with the painter's
      // own polyline build to avoid first-paint hitch + visual jump.
      _pathCache[stroke.id] = _MiniCanvasPainter._buildPath(stroke.points);
      _bumpRepaint();
      _scheduleRecognition();
      _scheduleAutoSave();
    } else {
      setState(() => _activePoints.clear());
      _bumpRepaint();
    }
  }

  void _onPointerDown(PointerDownEvent event) {
    _activePointers[event.pointer] = event.localPosition;

    // Two-finger pinch — preempts drawing, even if a stroke had just
    // started with the first finger. The first-finger contact was
    // probably the user about to pinch, not actual handwriting.
    if (_activePointers.length == 2) {
      if (_drawingPointerId != null) _cancelActiveStroke();
      _beginPinch();
      return;
    }

    // Read-only viewer: pinch + pan stay enabled, drawing is suppressed.
    if (widget.readOnly) return;

    // Single pointer → start drawing, regardless of [PointerDeviceKind].
    //
    // Why we accept finger touches in addition to stylus:
    //   • On Apple iPad with Pencil, kind == stylus reliably — perfect.
    //   • On Android tablets (Xiaomi tested 2026-05-08), the stylus
    //     driver often reports kind == touch. A strict stylus filter
    //     means the student can write but no strokes appear → the
    //     feature looks broken. The legacy `HandwritingScratchpad`
    //     accepted any kind for this reason.
    //   • On a non-stylus device, finger drawing is the only option.
    // We trade 1-finger pan for 1-finger draw; 2-finger pan still works.
    if (_drawingPointerId == null) {
      _drawingPointerId = event.pointer;
      _debounceTimer?.cancel();
      _countdownController.stop();
      _countdownController.reset();
      final canvasPt = _viewToCanvas(event.localPosition);
      setState(() {
        _activePoints
          ..clear()
          ..add(ProDrawingPoint(
            position: canvasPt,
            // event.pressure is 1.0 on touch devices (no sensor); on
            // stylus the real value flows through. Treat 0 as "no
            // signal" → fall back to 1.0 so width modulation looks ok.
            pressure: event.pressure > 0 ? event.pressure : 1.0,
            timestamp: DateTime.now().millisecondsSinceEpoch,
          ));
      });
      _bumpRepaint();
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    _activePointers[event.pointer] = event.localPosition;

    // Two-finger pinch / pan in progress.
    if (_activePointers.length >= 2) {
      final pts = _activePointers.values.toList();
      final newDistance = (pts[0] - pts[1]).distance;
      final newFocal = (pts[0] + pts[1]) / 2;
      if (_pinchStartDistance != null &&
          _pinchStartDistance! > 0 &&
          _pinchStartFocal != null) {
        final scaleFactor = newDistance / _pinchStartDistance!;
        final newScale = (_pinchStartScale * scaleFactor)
            .clamp(_minScale, _maxScale);
        // Pinch about the focal point: the canvas point under the focal
        // should remain under the focal after zoom.
        final focalCanvas = (_pinchStartFocal! - _pinchStartOffset) /
            _pinchStartScale;
        final newOffset = newFocal - focalCanvas * newScale;
        setState(() {
          _scale = newScale;
          _offset = newOffset;
        });
      }
      return;
    }

    // Active drawing stroke.
    if (event.pointer == _drawingPointerId) {
      final canvasPt = _viewToCanvas(event.localPosition);
      // Deduplicate sub-pixel moves to keep the stroke list lean.
      if (_activePoints.isNotEmpty) {
        final last = _activePoints.last.position;
        if ((canvasPt - last).distance < 0.5 / _scale) return;
      }
      // Hot path during fluent writing — bypass setState (which forces a
      // full widget rebuild for every move event) and bump the painter's
      // repaint listenable directly. Same pattern as `CurrentStrokePainter`
      // in the main canvas: list mutation + repaint bump, no widget tree
      // churn. Buttons / hints / progress indicators driven by setState
      // re-render only when their actual state changes (pen-up, pen-down).
      _activePoints.add(ProDrawingPoint(
        position: canvasPt,
        // Same fallback as in _onPointerDown: Android touch reports
        // pressure=0 (no sensor); without the fallback the first point
        // would render at width 5.0 (down handler's fallback) and every
        // subsequent point at width 1.5 — visibly "fat dot then thin
        // line".
        pressure: event.pressure > 0 ? event.pressure : 1.0,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ));
      _bumpRepaint();
      return;
    }

    // Single-finger pan (no stylus active). Disabled in readOnly mode so
    // the parent ListView in [ExamReviewScreen] can scroll vertically
    // through past answers — otherwise dragging a finger inside the
    // canvas captured the gesture and the page felt "stuck". 2-finger
    // pan + pinch still work for inspecting strokes.
    if (!widget.readOnly &&
        _drawingPointerId == null &&
        _activePointers.length == 1) {
      final delta = event.delta;
      setState(() => _offset += delta);
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    _activePointers.remove(event.pointer);

    // Drawing stroke ended.
    if (event.pointer == _drawingPointerId) {
      _drawingPointerId = null;
      if (_activePoints.length >= 2) {
        // Commit as a ProStroke.
        final stroke = ProStroke(
          id: 'exam_${generateUid()}',
          points: List<ProDrawingPoint>.from(_activePoints),
          color: widget.inkColor,
          baseWidth: 2.5,
          penType: ProPenType.ballpoint,
          createdAt: DateTime.now(),
        );
        setState(() {
          _strokes.add(stroke);
          _activePoints.clear();
        });
        // Pre-warm the path cache. Without this, the next paint runs
        // _MiniCanvasPainter._buildPath inline (~5-15ms on long
        // strokes) → visible hitch right after pen-up. We mirror the
        // painter's polyline algorithm exactly so the cached Path is
        // pixel-identical to what it would have built lazily — using
        // ProStroke.cachedPath would substitute a Catmull-Rom curve,
        // causing a "polyline → smooth curve" visual jump at commit.
        _pathCache[stroke.id] = _MiniCanvasPainter._buildPath(stroke.points);
        _bumpRepaint();
        _scheduleRecognition();
        _scheduleAutoSave();
      } else {
        setState(() => _activePoints.clear());
        _bumpRepaint();
      }
      return;
    }

    // Reset pinch baselines once we're back below 2 pointers.
    if (_activePointers.length < 2) {
      _pinchStartDistance = null;
      _pinchStartFocal = null;
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _activePointers.remove(event.pointer);
    if (event.pointer == _drawingPointerId) {
      _drawingPointerId = null;
      setState(() => _activePoints.clear());
      _bumpRepaint();
    }
    if (_activePointers.length < 2) {
      _pinchStartDistance = null;
      _pinchStartFocal = null;
    }
  }

  // ── Coordinate transforms ────────────────────────────────────────────────

  Offset _viewToCanvas(Offset view) => (view - _offset) / _scale;

  // ── OCR ──────────────────────────────────────────────────────────────────

  void _scheduleRecognition() {
    if (widget.readOnly) return; // viewer mode never runs OCR
    _debounceTimer?.cancel();
    _countdownController.reset();
    _countdownController.forward();
    _debounceTimer = Timer(const Duration(milliseconds: 1200), _recognize);
  }

  /// Hashes the stroke list cheaply: combines stroke ids + point counts.
  /// Two stroke lists with identical structure produce the same hash → we
  /// skip OCR. Adding/removing/extending a stroke perturbs the hash → re-run.
  int _strokeSetHash() {
    var h = 17;
    for (final s in _strokes) {
      h = 0x1fffffff & (h * 31 + s.id.hashCode);
      h = 0x1fffffff & (h * 31 + s.points.length);
    }
    return h;
  }

  Future<void> _recognize() async {
    _countdownController.reset();
    if (_strokes.isEmpty) return;
    final inkService = DigitalInkService.instance;
    if (!inkService.isAvailable) return;

    // Delta skip: if the stroke set hasn't changed since the last
    // recognition, just re-emit the cached text. Avoids burning a Gemini
    // call when the user only panned/zoomed during the debounce window.
    final hash = _strokeSetHash();
    if (hash == _lastRecognizedHash && _lastRecognizedText != null) {
      // Re-emit so callers that overwrite their TextField on every recog
      // still get the right value (defensive — usually a no-op).
      if (mounted) widget.onRecognizedText(_lastRecognizedText!);
      return;
    }

    final strokeSets = _strokes
        .where((s) => s.points.length >= 2)
        .map((s) => List<ProDrawingPoint>.from(s.points))
        .toList();
    if (strokeSets.isEmpty) return;
    setState(() => _isRecognizing = true);
    try {
      final result = await inkService.recognizeMultiStrokeWithAutoDetect(
        strokeSets,
      );
      if (result != null && result.text.trim().isNotEmpty && mounted) {
        _lastRecognizedHash = hash;
        _lastRecognizedText = result.text;
        widget.onRecognizedText(result.text);
      }
    } catch (e) {
      debugPrint('🖋️ MiniCanvasScratchpad: OCR error: $e');
    } finally {
      if (mounted) setState(() => _isRecognizing = false);
    }
  }

  // ── Stroke editing controls ──────────────────────────────────────────────

  void _undo() {
    if (_strokes.isEmpty || _isRecognizing) return;
    final removed = _strokes.last;
    _pathCache.remove(removed.id);
    setState(() => _strokes.removeLast());
    _bumpRepaint();
    if (_strokes.isNotEmpty) {
      _scheduleRecognition();
    } else {
      _debounceTimer?.cancel();
      _countdownController.reset();
    }
    _scheduleAutoSave();
  }

  void _clear() {
    _debounceTimer?.cancel();
    _countdownController.reset();
    _pathCache.clear();
    setState(() {
      _strokes.clear();
      _activePoints.clear();
    });
    _bumpRepaint();
    _scheduleAutoSave();
  }

  /// "Fit content" — smarter than the old "Reset zoom" (scale=1, offset=0).
  /// Centers + zooms to inquadrate ALL committed strokes with 10% padding.
  /// Falls back to an absolute reset when there are no strokes to fit.
  void _fitOrResetView() {
    if (_strokes.isEmpty) {
      setState(() {
        _scale = 1.0;
        _offset = Offset.zero;
      });
      return;
    }
    _fitToContent();
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: widget.inkColor.withValues(alpha: 0.2)),
        boxShadow: _isRecognizing
            ? [
                BoxShadow(
                  color: widget.inkColor.withValues(alpha: 0.05),
                  blurRadius: 15,
                  spreadRadius: 2,
                )
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(children: [
          Positioned.fill(
            child: Listener(
              onPointerDown: _onPointerDown,
              onPointerMove: _onPointerMove,
              onPointerUp: _onPointerUp,
              onPointerCancel: _onPointerCancel,
              behavior: HitTestBehavior.opaque,
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _MiniCanvasPainter(
                    strokes: _strokes,
                    activePoints: _activePoints,
                    activeColor: widget.inkColor,
                    scale: _scale,
                    offset: _offset,
                    pathCache: _pathCache,
                    repaint: _repaintTrigger,
                  ),
                  size: Size.infinite,
                ),
              ),
            ),
          ),

          // Empty hint (only when truly empty + not in read-only mode —
          // a read-only viewer with no strokes shouldn't say "scrivi qui").
          if (_strokes.isEmpty && _activePoints.isEmpty && !widget.readOnly)
            IgnorePointer(
              child: Center(
                child: Text(
                  'Scrivi qui la tua risposta a mano…',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),

          // OCR debounce countdown bar
          if (_countdownController.isAnimating)
            Positioned(
              left: 16,
              right: 16,
              bottom: 0,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                child: LinearProgressIndicator(
                  value: _countdownController.value,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    widget.inkColor.withValues(alpha: 0.5),
                  ),
                  minHeight: 3,
                ),
              ),
            ),

          // Top-right toolbar: zoom %, reset zoom, undo, clear, OCR spinner.
          Positioned(
            top: 8,
            right: 8,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_scale != 1.0 || _offset != Offset.zero)
                  GestureDetector(
                    onTap: _fitOrResetView,
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: widget.inkColor.withValues(alpha: 0.3)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.center_focus_strong_rounded,
                            color: widget.inkColor.withValues(alpha: 0.85), size: 14),
                        const SizedBox(width: 4),
                        Text(
                          '${(_scale * 100).round()}%',
                          style: TextStyle(
                            color: widget.inkColor.withValues(alpha: 0.9),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ]),
                    ),
                  ),
                if (_isRecognizing)
                  Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(widget.inkColor),
                      ),
                    ),
                  ),
                if (!widget.readOnly && _strokes.isNotEmpty && !_isRecognizing)
                  GestureDetector(
                    onTap: _undo,
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.4),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.undo, color: Colors.white54, size: 18),
                    ),
                  ),
                if (!widget.readOnly && _strokes.isNotEmpty)
                  GestureDetector(
                    onTap: _clear,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.4),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.delete_outline, color: Colors.white54, size: 18),
                    ),
                  ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

class MiniCanvasScratchpad extends StatefulWidget {
  /// Fired with the recognized text after each OCR pass. Caller appends to
  /// the answer TextField. The strokes themselves stay on the canvas.
  final void Function(String text) onRecognizedText;

  /// Stroke colour. Defaults to Fluera cyan.
  final Color inkColor;

  /// Strokes to load on initial mount (e.g. resuming a prior answer). May
  /// be null or empty.
  final List<ProStroke>? initialStrokes;

  /// Optional auto-save callback fired after each completed stroke (pen-up)
  /// and after undo/clear. The implementation should debounce I/O — the
  /// caller may receive bursts during a fluent writing session. Used so
  /// the strokes survive a kill-app crash without waiting for `dispose`.
  final void Function(List<ProStroke> strokes)? onStrokesChanged;

  /// Read-only mode: input is ignored, toolbar buttons hidden, OCR
  /// disabled. Pinch zoom + pan still work so the user can inspect a
  /// past answer. Used by the dashboard's "View past answers" feature.
  final bool readOnly;

  const MiniCanvasScratchpad({
    super.key,
    required this.onRecognizedText,
    this.inkColor = const Color(0xFF00FFCC),
    this.initialStrokes,
    this.onStrokesChanged,
    this.readOnly = false,
  });

  @override
  State<MiniCanvasScratchpad> createState() => MiniCanvasScratchpadState();
}

// ─── Painter ──────────────────────────────────────────────────────────────────

class _MiniCanvasPainter extends CustomPainter {
  final List<ProStroke> strokes;
  final List<ProDrawingPoint> activePoints;
  final Color activeColor;
  final double scale;
  final Offset offset;
  /// Cache of pre-built paths keyed by stroke.id. Built lazily per stroke
  /// on first paint, reused on subsequent frames (pan/zoom only re-runs
  /// `canvas.translate + canvas.scale`, not the path rebuild).
  final Map<String, ui.Path> pathCache;

  _MiniCanvasPainter({
    required this.strokes,
    required this.activePoints,
    required this.activeColor,
    required this.scale,
    required this.offset,
    required this.pathCache,
    required Listenable repaint,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Ruled background (in viewport space — doesn't scroll with the canvas)
    final bgPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    const lineSpacing = 40.0;
    for (double y = 40.0; y < size.height; y += lineSpacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), bgPaint);
    }

    // 2. Apply camera transform for the strokes layer.
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.scale(scale);

    // 3. Committed strokes — single drawPath per stroke using cached
    // [ui.Path] (built once, reused forever). One [Paint] allocation per
    // stroke instead of per-segment. Stroke width uses the average
    // pressure of the stroke's points; per-segment pressure variation is
    // sacrificed for the ~50× perf win during pan/zoom on heavy answers.
    for (final stroke in strokes) {
      if (stroke.points.length < 2) continue;
      final cached = pathCache[stroke.id] ?? _buildPath(stroke.points);
      pathCache[stroke.id] = cached;
      final avgPressure = _averagePressure(stroke.points);
      final w = math.max(0.6, (1.5 + avgPressure * 3.5) / scale);
      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = w
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      canvas.drawPath(cached, paint);
    }

    // 4. In-flight stroke — NOT cached because it's growing every frame.
    // Built fresh from current `_activePoints`. Once the user pen-ups,
    // the stroke is committed to `_strokes` and the next paint caches it.
    if (activePoints.length >= 2) {
      final liveAvg = _averagePressure(activePoints);
      final w = math.max(0.6, (1.5 + liveAvg * 3.5) / scale);
      final livePaint = Paint()
        ..color = activeColor
        ..strokeWidth = w
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      canvas.drawPath(_buildPath(activePoints), livePaint);
    } else if (activePoints.length == 1) {
      // Single-point tap: render a tiny dot so the user sees feedback.
      final p = activePoints.first;
      canvas.drawCircle(
        p.position,
        (1.5 + p.pressure * 2.5) / scale,
        Paint()..color = activeColor,
      );
    }

    canvas.restore();
  }

  static ui.Path _buildPath(List<ProDrawingPoint> pts) {
    final path = ui.Path();
    if (pts.isEmpty) return path;
    path.moveTo(pts[0].position.dx, pts[0].position.dy);
    for (var i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].position.dx, pts[i].position.dy);
    }
    return path;
  }

  static double _averagePressure(List<ProDrawingPoint> pts) {
    if (pts.isEmpty) return 0.5;
    var sum = 0.0;
    for (final p in pts) {
      sum += p.pressure;
    }
    return sum / pts.length;
  }

  @override
  bool shouldRepaint(covariant _MiniCanvasPainter old) {
    // List mutations (strokes / activePoints) are NOT comparable here —
    // both `old` and `new` reference the SAME live state list, so any
    // length / identity check returns no diff (the framework calls
    // shouldRepaint after the mutation, when both painter snapshots
    // already see the new contents). Repaints from list mutations are
    // driven by the `repaint:` Listenable bumped by `_bumpRepaint()`
    // in [_MiniCanvasScratchpadState] — that channel bypasses
    // shouldRepaint entirely.
    //
    // Here we only compare value-type fields that are copied by value
    // at painter construction (each painter instance gets its own
    // independent value): camera transform + ink colour. These cover
    // pinch-zoom, pan, and inkColor changes from the parent widget.
    return old.scale != scale ||
        old.offset != offset ||
        old.activeColor != activeColor;
  }
}
