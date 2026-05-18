// ============================================================================
// ✏️ SocraticInlineScratchpad — Ephemeral sketch surface inline under
// the Socratic bubble.
//
// IDENTITÀ vs MiniCanvasScratchpad (Atlas Exam):
//   • Atlas Exam: fullscreen, persistito su disco, score-driven
//   • Socratic V2: INLINE ~280px, EPHEMERAL (stroke scartati), riflessivo
//
// Architettura di isolamento (no contaminazione canvas reale):
//   • Stroke vivono in lista LOCALE `_strokes` — mai in `LayerController`
//   • CustomPainter standalone — non passa dal `_clusterDetector`
//   • Nessuna persistenza (mounted → dispose, gli stroke svaniscono)
//   • Niente CRDT sync, niente time travel, niente tile cache
//
// UX:
//   • Header con domanda corrente + turn index
//   • Area di disegno bianca-soffusa con pen/stylus
//   • Toolbar: [🗑️ Cancella] [Conferma →]
//   • OCR debounce 800ms via `DigitalInkService.engine.recognizeTextMode()`
//   • Su confirm: OCR text passato al parent, stroke scartati
//
// Pattern riusato da MiniCanvasScratchpad ma senza zoom/pan/auto-save —
// la superficie è piccola e l'output è effimero per design.
// ============================================================================

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../drawing/models/pro_drawing_point.dart';
import '../../l10n/fluera_localizations.dart';
import '../../services/digital_ink_service.dart';
import '../../utils/uid.dart';

class SocraticInlineScratchpad extends StatefulWidget {
  /// Question text shown in the header (compact).
  final String questionText;

  /// Display turn index (1 = first follow-up, 2 = aporetic). Used for
  /// the "Turno X di 2" label.
  final int displayTurnIndex;

  /// Total dialog turns expected — used for the progress label.
  final int totalTurns;

  /// Called when student taps "Annulla" or back-gestures.
  final VoidCallback onCancel;

  /// Called when student taps "Conferma". Receives the OCR'd text from
  /// the strokes (may be empty if MyScript returned nothing).
  final void Function(String ocr) onConfirm;

  const SocraticInlineScratchpad({
    super.key,
    required this.questionText,
    required this.displayTurnIndex,
    required this.totalTurns,
    required this.onCancel,
    required this.onConfirm,
  });

  @override
  State<SocraticInlineScratchpad> createState() =>
      _SocraticInlineScratchpadState();
}

class _SocraticInlineScratchpadState extends State<SocraticInlineScratchpad> {
  // ── Stroke state ────────────────────────────────────────────────────────
  /// LOCAL stroke list — NEVER touches LayerController.
  final List<ProStroke> _strokes = [];
  final List<ProDrawingPoint> _activePoints = [];
  int? _drawingPointerId;

  /// Path cache for repaint perf — recomputed only when a stroke commits.
  final Map<String, ui.Path> _pathCache = {};

  /// Repaint trigger for the painter.
  final ValueNotifier<int> _repaintTrigger = ValueNotifier<int>(0);

  // ── OCR state ───────────────────────────────────────────────────────────
  Timer? _ocrDebounce;
  bool _ocrPending = false;
  String _latestOcr = '';
  bool _confirming = false;

  // ── Visual constants ────────────────────────────────────────────────────
  static const _bgColor = Color(0xFF15151F);
  static const _surfaceColor = Color(0xFF1F1F2E);
  static const _borderColor = Color(0xFFFFB347); // amber, consistent with Socratic
  static const _strokeColor = Color(0xFFFFE7B5);
  static const _strokeWidth = 2.5;
  // Device 2026-05-10 fix: 280 → 340 (+60 drawing area). User reported
  // "lo spazio per scrivere è piccolo".
  static const _height = 340.0;

  @override
  void dispose() {
    _ocrDebounce?.cancel();
    _repaintTrigger.dispose();
    super.dispose();
  }

  // ── Drawing handlers ────────────────────────────────────────────────────

  void _onPointerDown(PointerDownEvent event) {
    if (_drawingPointerId != null) return;
    _drawingPointerId = event.pointer;
    _activePoints.clear();
    _activePoints.add(ProDrawingPoint(
      position: event.localPosition,
      pressure: event.pressure,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    ));
    _repaintTrigger.value++;
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _drawingPointerId) return;
    _activePoints.add(ProDrawingPoint(
      position: event.localPosition,
      pressure: event.pressure,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    ));
    _repaintTrigger.value++;
  }

  void _onPointerUp(PointerUpEvent event) {
    if (event.pointer != _drawingPointerId) return;
    _drawingPointerId = null;
    if (_activePoints.length < 2) {
      _activePoints.clear();
      _repaintTrigger.value++;
      return;
    }
    // Commit the stroke.
    final stroke = ProStroke(
      id: 'ssp_${generateUid()}',
      points: List.from(_activePoints),
      color: _strokeColor,
      baseWidth: _strokeWidth,
      penType: ProPenType.ballpoint,
      createdAt: DateTime.now(),
    );
    _strokes.add(stroke);
    _activePoints.clear();
    _rebuildPathCache(stroke);
    _repaintTrigger.value++;
    _scheduleOcr();
  }

  void _rebuildPathCache(ProStroke s) {
    final path = ui.Path();
    if (s.points.isEmpty) return;
    path.moveTo(s.points[0].position.dx, s.points[0].position.dy);
    for (int i = 1; i < s.points.length; i++) {
      path.lineTo(s.points[i].position.dx, s.points[i].position.dy);
    }
    _pathCache[s.id] = path;
  }

  // ── OCR ─────────────────────────────────────────────────────────────────

  void _scheduleOcr() {
    _ocrDebounce?.cancel();
    _ocrPending = true;
    _ocrDebounce = Timer(const Duration(milliseconds: 800), _runOcr);
  }

  Future<void> _runOcr() async {
    if (_strokes.isEmpty) {
      _latestOcr = '';
      _ocrPending = false;
      if (mounted) setState(() {});
      return;
    }
    try {
      final ink = DigitalInkService.instance;
      if (!ink.isAvailable) {
        _ocrPending = false;
        return;
      }
      final strokeSets = _strokes
          .where((s) => s.points.length >= 2)
          .map((s) => s.points)
          .toList(growable: false);
      if (strokeSets.isEmpty) {
        _ocrPending = false;
        return;
      }
      final recognized = await ink.engine.recognizeTextMode(strokeSets);
      _latestOcr = (recognized ?? '').trim();
    } catch (e) {
      _latestOcr = '';
    } finally {
      _ocrPending = false;
      if (mounted) setState(() {});
    }
  }

  /// Force-runs the pending OCR before confirm so the latest stroke
  /// is captured even if the debounce hasn't fired yet.
  Future<void> _flushOcr() async {
    _ocrDebounce?.cancel();
    if (_strokes.isEmpty) {
      _latestOcr = '';
      return;
    }
    await _runOcr();
  }

  // ── Actions ─────────────────────────────────────────────────────────────

  void _onClear() {
    HapticFeedback.lightImpact();
    setState(() {
      _strokes.clear();
      _activePoints.clear();
      _pathCache.clear();
      _latestOcr = '';
    });
    _repaintTrigger.value++;
  }

  Future<void> _onConfirm() async {
    if (_confirming) return;
    setState(() => _confirming = true);
    await _flushOcr();
    if (!mounted) return;
    widget.onConfirm(_latestOcr);
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _height,
      decoration: BoxDecoration(
        color: _bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borderColor.withValues(alpha: 0.4), width: 1),
        boxShadow: [
          BoxShadow(
            color: _borderColor.withValues(alpha: 0.15),
            blurRadius: 16,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        children: [
          _buildHeader(),
          Expanded(child: _buildDrawingArea()),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _borderColor.withValues(alpha: 0.08),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
      ),
      child: Row(
        children: [
          Text(
            '✏️ Turno ${widget.displayTurnIndex}/${widget.totalTurns}',
            style: TextStyle(
              color: _borderColor,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          if (_ocrPending)
            const SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(
                strokeWidth: 1.3,
                valueColor: AlwaysStoppedAnimation<Color>(_borderColor),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDrawingArea() {
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: (e) {
        if (e.pointer == _drawingPointerId) {
          _drawingPointerId = null;
          _activePoints.clear();
          _repaintTrigger.value++;
        }
      },
      child: Container(
        // Edge-to-edge — device fix: maximize drawing area within
        // the 280px-wide bubble. Side borders come from the panel
        // outer border, not from inner margin.
        margin: EdgeInsets.zero,
        decoration: const BoxDecoration(
          color: _surfaceColor,
        ),
        clipBehavior: Clip.hardEdge,
        child: Stack(
          children: [
            CustomPaint(
              painter: _ScratchpadPainter(
                strokes: _strokes,
                pathCache: _pathCache,
                activePoints: _activePoints,
                repaint: _repaintTrigger,
              ),
              size: Size.infinite,
            ),
            if (_strokes.isEmpty && _activePoints.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'Schizza parole, frecce, concetti — qualsiasi cosa ti venga in mente.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF6E6E80),
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    // Device 2026-05-10 fix: removed "Annulla" button (redundant — the
    // user can close the bubble via the × in the header or tap outside).
    // "Cancella" is icon-only when there are strokes (no label crowding).
    // "Conferma" gets the remaining width as a primary action.
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: _confirming || _strokes.isEmpty ? null : _onClear,
            icon: const Icon(Icons.delete_outline,
                size: 16, color: Colors.white60),
            tooltip: FlueraLocalizations.of(context)!.socraticScratchpad_clear,
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            onPressed: _confirming ? null : widget.onCancel,
            icon: const Icon(Icons.close, size: 16, color: Colors.white54),
            tooltip: FlueraLocalizations.of(context)!.socraticScratchpad_cancel,
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: FilledButton.icon(
              onPressed:
                  (_confirming || _strokes.isEmpty) ? null : _onConfirm,
              icon: _confirming
                  ? const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.arrow_forward, size: 14),
              label: const Text(
                'Conferma',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: _borderColor,
                foregroundColor: const Color(0xFF0A0A1A),
                padding: const EdgeInsets.symmetric(vertical: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScratchpadPainter extends CustomPainter {
  final List<ProStroke> strokes;
  final Map<String, ui.Path> pathCache;
  final List<ProDrawingPoint> activePoints;

  _ScratchpadPainter({
    required this.strokes,
    required this.pathCache,
    required this.activePoints,
    required Listenable repaint,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFFE7B5)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Committed strokes from cache.
    for (final s in strokes) {
      final p = pathCache[s.id];
      if (p != null) canvas.drawPath(p, paint);
    }

    // Active (in-progress) stroke.
    if (activePoints.length >= 2) {
      final path = ui.Path()
        ..moveTo(activePoints[0].position.dx, activePoints[0].position.dy);
      for (int i = 1; i < activePoints.length; i++) {
        path.lineTo(activePoints[i].position.dx, activePoints[i].position.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_ScratchpadPainter oldDelegate) => false; // Listenable drives it
}
