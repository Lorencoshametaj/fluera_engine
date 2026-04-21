import 'package:flutter/material.dart';

/// 🧘 Reduced Motion — WCAG 2.3.3 compliance helper.
///
/// When the OS-level reduce-motion preference is on (iOS "Reduce Motion",
/// Android "Remove animations", macOS "Reduce motion"), animations should
/// not be theatrical. Fluera's ethos (Assioma 2: silenzio) aligns: users
/// who opt out of motion do so because motion distracts from work.
///
/// Usage:
///
/// ```dart
/// _ctrl = AnimationController(
///   vsync: this,
///   duration: effectiveDuration(context, const Duration(milliseconds: 240)),
/// );
/// ```
///
/// When reduce-motion is on, the returned duration is [Duration.zero], so
/// the animation snaps to its end state on `forward()` / `reverse()`.
Duration effectiveDuration(BuildContext context, Duration full) {
  return MediaQuery.maybeDisableAnimationsOf(context) == true
      ? Duration.zero
      : full;
}

/// Shortcut for the common case where the animation should still take *some*
/// time (e.g. a fade that would be jarring if instant) but shorter than full.
Duration shortenedDuration(
  BuildContext context,
  Duration full, {
  Duration reduced = const Duration(milliseconds: 60),
}) {
  return MediaQuery.maybeDisableAnimationsOf(context) == true ? reduced : full;
}
