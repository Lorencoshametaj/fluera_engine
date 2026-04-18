import 'dart:math' as math;

import '../../rendering/lod_config.dart';

/// 🎥 SRS CAMERA POLICY — pure function that maps a student's review
/// history to a target initial zoom scale on session open.
///
/// Teoria cognitiva §1010, §1549-1554:
///   > "Ad ogni ritorno, lo zoom iniziale è più ampio: prima vede i titoli,
///     deve ricostruire i dettagli mentalmente prima di zoomare."
///
/// This policy implements the **progressive zoom-out on return**: at each
/// SRS return the canvas opens at a wider zoom than before. The effect
/// forces the student to mentally reconstruct details from titles and
/// spatial position (Active Recall + Place Cells §22).
///
/// Curve design:
///   - Review #0 (first time / no history): scale = userBaseScale (unchanged)
///   - Review #1 (first return)           : scale = baseScale × 0.85
///   - Review #2                          : scale = baseScale × 0.72
///   - ...
///   - Asymptotes to [minScale] so the student never gets pushed below the
///     LOD 2 threshold ([kLodTier2Threshold]) by accident — they can still
///     zoom *further* out manually, but the auto-opener stops there.
///
/// The decay factor is geometric so it stays meaningful even after many
/// returns, without requiring tuning per-user.
class SrsCameraPolicy {
  /// Per-review geometric decay factor.
  /// 0.85 → about 10 returns to go from 1.0 to the LOD 2 threshold (0.25).
  static const double decayPerReview = 0.85;

  /// Floor scale: the auto-opener never pulls below this.
  /// Set strictly *inside* the LOD 2 tier — [kLodTier2Threshold] itself
  /// rounds up to LOD 1 because the tier predicate is `scale < threshold`.
  /// 0.20 guarantees the student lands comfortably in the satellite view.
  static const double minAutoScale = 0.20;

  /// Ceiling scale: the auto-opener never pushes *in* beyond this.
  static const double maxAutoScale = 1.5;

  /// Compute the target zoom scale to open the canvas at for this SRS return.
  ///
  /// [reviewCount]: total completed SRS review sessions for this canvas.
  ///   0 = first study session ever → returns [userBaseScale] unchanged.
  /// [userBaseScale]: the scale the student was at when they last closed the
  ///   canvas. We derive *relative* zoom-out from this, respecting the
  ///   student's own last-known orientation.
  ///
  /// Returns a scale in [minAutoScale, maxAutoScale].
  static double targetScaleForReturn({
    required int reviewCount,
    required double userBaseScale,
  }) {
    if (reviewCount <= 0) {
      return userBaseScale.clamp(minAutoScale, maxAutoScale);
    }

    final decay = math.pow(decayPerReview, reviewCount).toDouble();
    final target = userBaseScale * decay;
    return target.clamp(minAutoScale, maxAutoScale);
  }

  /// Which LOD tier the student will land in after this return.
  /// Useful for UX hints ("today you start from satellite view").
  static int targetLodTier({
    required int reviewCount,
    required double userBaseScale,
  }) {
    final scale = targetScaleForReturn(
      reviewCount: reviewCount,
      userBaseScale: userBaseScale,
    );
    return computeLodTier(scale);
  }

  /// Human-readable hint for the UI overlay shown on session open
  /// (§1549: "prima vede i titoli, deve ricostruire i dettagli").
  ///
  /// Italian defaults. Pass a custom [messages] to localize for other
  /// locales — the engine itself has no generated l10n for pedagogical
  /// strings, so this is the integration seam for the app layer.
  static String hintForTier(
    int tier, {
    SrsCameraMessages messages = SrsCameraMessages.italian,
  }) {
    switch (tier) {
      case 0:
        return messages.detail;
      case 1:
        return messages.concepts;
      case 2:
      default:
        return messages.satellite;
    }
  }
}

/// Localized strings for the progressive zoom-out hint.
///
/// The app layer can instantiate this with translations pulled from its own
/// l10n pipeline (e.g. generated ARB files) and pass it to
/// [SrsCameraPolicy.hintForTier]. The engine ships an Italian default.
class SrsCameraMessages {
  /// Hint shown when the student lands in LOD 0 (full detail).
  final String detail;

  /// Hint shown when the student lands in LOD 1 (concept level).
  final String concepts;

  /// Hint shown when the student lands in LOD 2 (satellite view).
  final String satellite;

  const SrsCameraMessages({
    required this.detail,
    required this.concepts,
    required this.satellite,
  });

  /// Italian defaults — pedagogical copy matching §1549 of the theory.
  static const italian = SrsCameraMessages(
    detail: 'Vista dettaglio',
    concepts: 'Vista concetti',
    satellite:
        'Vista satellite — ricostruisci i dettagli dalla posizione',
  );

  /// English translation for non-Italian locales.
  static const english = SrsCameraMessages(
    detail: 'Detail view',
    concepts: 'Concept view',
    satellite: 'Satellite view — reconstruct details from position',
  );
}
