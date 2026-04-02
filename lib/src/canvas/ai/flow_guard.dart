// ============================================================================
// 🛡️ FLOW GUARD — Cognitive flow protection during active writing
//
// Per specifica P1-25: "No popup/notifica/tooltip mentre la penna è
// a contatto con lo schermo o entro 2 secondi dall'ultimo tratto."
//
// This controller tracks the user's writing state and provides a
// single boolean query (`isFlowProtected`) that all overlay/popup
// systems use to self-suppress during the cognitive flow window.
//
// ARCHITECTURE:
//   - Drawing start    → guard ACTIVE (pen down)
//   - Drawing end      → start 2s cooldown timer
//   - Timer expires    → guard INACTIVE (overlays allowed)
//   - New drawing start → cancel timer, guard stays ACTIVE
//
// THREAD SAFETY: Main isolate only (Flutter UI). No sync needed.
// ============================================================================

import 'dart:async';
import 'package:flutter/foundation.dart';

/// 🛡️ Protects cognitive flow by suppressing non-critical overlays
/// during active writing and for 2 seconds after the last stroke.
///
/// Usage:
/// ```dart
/// if (flowGuard.isFlowProtected) return; // Don't show popup
/// ```
class FlowGuard extends ChangeNotifier {
  /// Duration of the post-stroke cooldown. After the user lifts the pen,
  /// overlays remain suppressed for this duration.
  ///
  /// Spec reference: P1-25 mandates 2 seconds.
  static const Duration cooldownDuration = Duration(seconds: 2);

  bool _isPenDown = false;
  Timer? _cooldownTimer;
  int _lastStrokeEndMs = 0;

  // ─────────────────────────────────────────────────────────────────────────
  // STATE
  // ─────────────────────────────────────────────────────────────────────────

  /// Whether the flow is currently protected.
  ///
  /// Returns `true` if:
  ///   1. The pen is currently touching the screen, OR
  ///   2. Less than [cooldownDuration] has elapsed since the last stroke ended.
  ///
  /// Overlays/popups MUST check this before showing. If `true`, they
  /// should either defer or silently discard the trigger.
  bool get isFlowProtected {
    if (_isPenDown) return true;
    if (_cooldownTimer?.isActive ?? false) return true;
    // Fallback: check elapsed time directly (handles timer disposal edge cases)
    final elapsed = DateTime.now().millisecondsSinceEpoch - _lastStrokeEndMs;
    return elapsed < cooldownDuration.inMilliseconds;
  }

  /// Whether the pen is currently touching the screen.
  bool get isPenDown => _isPenDown;

  /// Milliseconds since the last stroke ended.
  /// Returns a very large value if no stroke has been drawn yet.
  int get millisSinceLastStroke {
    if (_lastStrokeEndMs == 0) return 999999;
    return DateTime.now().millisecondsSinceEpoch - _lastStrokeEndMs;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // EVENTS — called by the drawing pipeline
  // ─────────────────────────────────────────────────────────────────────────

  /// Called when the user starts drawing (pen down / touch start).
  ///
  /// Cancels any active cooldown timer and activates protection.
  void onDrawingStarted() {
    _isPenDown = true;
    _cooldownTimer?.cancel();
    _cooldownTimer = null;
    notifyListeners();
  }

  /// Called when the user finishes a stroke (pen up / touch end).
  ///
  /// Starts the 2-second cooldown timer. Protection remains active
  /// until the timer expires.
  void onDrawingEnded() {
    _isPenDown = false;
    _lastStrokeEndMs = DateTime.now().millisecondsSinceEpoch;

    // Start cooldown
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer(cooldownDuration, () {
      _cooldownTimer = null;
      notifyListeners(); // Protection ended — overlays may now show
    });
  }

  /// Called when drawing is cancelled (e.g., zoom gesture interrupts stroke).
  ///
  /// Same behavior as [onDrawingEnded] — protection continues through cooldown.
  void onDrawingCancelled() {
    onDrawingEnded();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LIFECYCLE
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _cooldownTimer = null;
    super.dispose();
  }

  @override
  String toString() =>
      'FlowGuard(protected: $isFlowProtected, penDown: $_isPenDown, '
      'sinceLastStroke: ${millisSinceLastStroke}ms)';
}
