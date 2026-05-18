import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../reflow/content_cluster.dart';

/// 🔁 RETURN RITUAL BLUR PAINTER — Transient blur on cluster ink when
/// the student reopens a canvas after a multi-day gap.
///
/// Pedagogical contract (§1047-1062, PASSO 6 — Active Recall Spaziale):
/// "ogni ritorno il canvas si apre leggermente più zoomato fuori, con
/// blur più intenso, lo studente deve ricostruire mentalmente prima di
/// vedere chiaramente". The blur dissolves on first interaction (any
/// stroke / pan / zoom) OR after an 8 second timeout — whichever comes
/// first. Total budget ≤ 8s per session, gated by host setting.
///
/// Sibling of `srs_blur_overlay_painter.dart` (same `saveLayer +
/// ImageFilter.blur` pattern) but pedagogically distinct: SRS is
/// per-cluster `isDue` reveal mechanic with self-eval; this is a
/// uniform "return blur" that just delays gratification on re-entry.
class ReturnRitualBlurPainter extends CustomPainter {
  ReturnRitualBlurPainter({
    required this.clusters,
    required this.controller,
  }) : super(repaint: controller);

  final List<ContentCluster> clusters;
  final ReturnRitualBlurController controller;

  @override
  void paint(Canvas canvas, Size size) {
    if (!controller.isActive) return;
    if (clusters.isEmpty) return;
    // intensity ∈ (0.0, 0.50] → sigma ∈ (0, 8] canvas-space pixels.
    final effectiveSigma = controller.currentSigma;
    if (effectiveSigma < 0.5) return;

    final blurPaint = Paint()
      ..imageFilter = ui.ImageFilter.blur(
        sigmaX: effectiveSigma,
        sigmaY: effectiveSigma,
        tileMode: TileMode.decal,
      );
    final stamp = Paint()..color = Colors.transparent;

    for (final cluster in clusters) {
      // Skip empty / tiny clusters — blur on them is invisible noise.
      if (cluster.strokeIds.length < 5) continue;
      final bounds = cluster.bounds;
      if (bounds.isEmpty || !bounds.isFinite) continue;

      final inflated = bounds.inflate(8.0);
      final rrect = RRect.fromRectAndRadius(
        inflated,
        const Radius.circular(12.0),
      );
      canvas.saveLayer(inflated.inflate(4.0), blurPaint);
      canvas.drawRRect(rrect, stamp);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant ReturnRitualBlurPainter old) =>
      !identical(old.clusters, clusters) ||
      !identical(old.controller, controller);
}

/// 🔁 RETURN RITUAL BLUR CONTROLLER — Drives the blur intensity through
/// its lifecycle: full at canvas open → dissolve on first interaction
/// or auto-timeout. Owns its own [Ticker]-driven animation via vsync.
///
/// State machine:
///   1. constructed with `intensity` (computed from days-since-last-visit)
///   2. blur shown at `_baseIntensity * 16` sigma immediately
///   3. on `dismiss()` OR 8s timeout: tween `_dissolveProgress` 0 → 1
///      over 1500ms, then `isActive` flips false
///
/// Host integration:
///   - call `dismiss()` from any gesture handler (pan/zoom/stroke/tap)
///   - dispose in screen state to release timer + animation
class ReturnRitualBlurController extends ChangeNotifier {
  ReturnRitualBlurController({
    required double intensity,
    required TickerProvider vsync,
    Duration autoDismissAfter = const Duration(seconds: 8),
    Duration dissolveDuration = const Duration(milliseconds: 1500),
  }) : _baseIntensity = intensity.clamp(0.0, 0.50) {
    _dissolveCtrl = AnimationController(
      vsync: vsync,
      duration: dissolveDuration,
    )..addListener(notifyListeners);
    _autoDismissTimer = Timer(autoDismissAfter, dismiss);
  }

  /// Base intensity computed from `daysSinceLastVisit`:
  /// - 1 day  → 0.07
  /// - 3 day  → 0.20
  /// - 7 day  → 0.35
  /// - 14+ day → 0.50 (capped)
  final double _baseIntensity;

  late final AnimationController _dissolveCtrl;
  Timer? _autoDismissTimer;
  bool _dismissed = false;

  /// True until the dissolve animation has fully completed.
  bool get isActive => _baseIntensity > 0.005 && _dissolveCtrl.value < 0.99;

  /// Current effective sigma in canvas pixels, modulated by dissolve.
  double get currentSigma =>
      _baseIntensity * 16.0 * (1.0 - _dissolveCtrl.value);

  /// Dismiss the ritual — fades out gracefully. Idempotent.
  void dismiss() {
    if (_dismissed) return;
    _dismissed = true;
    _autoDismissTimer?.cancel();
    _dissolveCtrl.forward();
  }

  /// Compute the canonical base intensity from days-since-last-visit.
  /// Capped at 0.50 to keep ink eventually visible.
  static double intensityFromDays(int daysSince) {
    if (daysSince < 1) return 0.0;
    if (daysSince >= 14) return 0.50;
    // Piecewise linear: 1→0.07, 3→0.20, 7→0.35, 14→0.50.
    if (daysSince <= 3) {
      return 0.07 + (daysSince - 1) * (0.20 - 0.07) / 2.0;
    }
    if (daysSince <= 7) {
      return 0.20 + (daysSince - 3) * (0.35 - 0.20) / 4.0;
    }
    return 0.35 + (daysSince - 7) * (0.50 - 0.35) / 7.0;
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    _dissolveCtrl.dispose();
    super.dispose();
  }
}
