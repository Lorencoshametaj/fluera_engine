// ============================================================================
// 🎤✋ AUDIO-INK SEEK OVERLAY — Long-press → seek-to-stroke gesture surface
//
// Transparent overlay wrapped around the canvas while the user is in
// Time Travel playback (Pro pillar #3, V1 split 2026-05-14). Long-press
// at a canvas point is forwarded to [AudioInkGestureHandler.handleLongPress]
// which hit-tests against the recorded strokes and seeks the audio
// playback to the matching timestamp.
//
// USAGE (host-side, e.g. inside FlueraCanvasScreen build):
// ```dart
// AudioInkSeekModeOverlay(
//   handler: audioInkGestureHandler,
//   active: tier == FlueraSubscriptionTier.pro && isTimeTravelActive,
//   child: canvasWidget,
// )
// ```
//
// When `active` is false the overlay is a pass-through — the long-press
// detector is removed so the default canvas gestures (drag-to-pan,
// long-press-context-menu) work unchanged on Free / Plus tiers and
// outside Time Travel mode.
// ============================================================================

import 'package:flutter/material.dart';

import '../controllers/audio_ink_gesture_handler.dart';

/// 🎤✋ Drop-in wrapper that adds a long-press → audio-seek gesture on
/// top of any [child] (typically the canvas widget).
///
/// The overlay does NOT visually decorate the child — its only purpose
/// is to route long-press gestures to the handler. Use the
/// `_StrokeCompass` / playback-overlay UI for visual feedback (already
/// wired separately in [SynchronizedPlaybackOverlay]).
class AudioInkSeekModeOverlay extends StatelessWidget {
  /// The handler that owns the seek logic (instantiated by the host
  /// when entering Time Travel mode).
  final AudioInkGestureHandler handler;

  /// Whether the gesture surface is active. False → pass-through.
  /// Typical wiring: `tier == Pro && isTimeTravelActive`.
  final bool active;

  /// Local-to-canvas coordinate converter. The host passes the inverse
  /// transform of its viewport (pan + zoom) so the overlay can translate
  /// the screen-space long-press position into canvas-space before
  /// feeding the handler. Identity when the canvas is not zoomable.
  final Offset Function(Offset localPosition) screenToCanvas;

  /// The wrapped canvas widget.
  final Widget child;

  /// Optional callback fired when a long-press is consumed by the
  /// handler. Hosts can use this for haptic feedback or analytics.
  final VoidCallback? onSeekConsumed;

  const AudioInkSeekModeOverlay({
    super.key,
    required this.handler,
    required this.child,
    required this.screenToCanvas,
    this.active = false,
    this.onSeekConsumed,
  });

  @override
  Widget build(BuildContext context) {
    if (!active) return child;

    // 🎤 Use a behavior that lets the canvas keep receiving its own
    // pointer events while we intercept the long-press at the source.
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _maybeEnableSeekMode,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onLongPressStart: (details) {
          final canvasPoint = screenToCanvas(details.localPosition);
          final consumed = handler.handleLongPress(canvasPoint);
          if (consumed && onSeekConsumed != null) {
            onSeekConsumed!();
          }
        },
        child: child,
      ),
    );
  }

  /// Ensures the handler's `seekModeActive` matches the [active] flag.
  /// Triggered on first pointer-down so the handler is ready before the
  /// long-press timer fires.
  void _maybeEnableSeekMode(PointerDownEvent _) {
    if (active && !handler.seekModeActive) {
      handler.enableSeekMode();
    }
  }
}
