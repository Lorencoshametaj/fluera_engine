// ============================================================================
// 🧪 SampleSizeCalculator — pre-experiment power analysis.
//
// Computes the minimum number of samples per branch required to detect
// a given lift in a proportion metric (e.g. `uncertain_reflections_rate`,
// `correct_answer_rate`) with specified statistical power and significance.
//
// Formula (2-sample proportion test, normal approximation):
//   n = (z_α/2 * sqrt(2*p*(1-p)) + z_β * sqrt(p1*(1-p1) + p2*(1-p2)))² / (p1-p2)²
//
// Where:
//   p   = pooled baseline rate
//   p1  = baseline rate
//   p2  = baseline rate * (1 + minDetectableLift)
//   α   = significance level (e.g. 0.05 → z_α/2 = 1.96)
//   β   = 1 - power (e.g. 0.2 → z_β = 0.84)
//
// Reference: Fleiss, Levin, Paik (2003), "Statistical Methods for Rates
// and Proportions", 3rd ed., chapter 4.
//
// Pure function, no I/O. Run via `SampleSizeCalculator.proportion(...)`.
// ============================================================================

import 'dart:math' as math;

class SampleSizeCalculator {
  SampleSizeCalculator._();

  /// Required sample size PER BRANCH for a 2-sample proportion test.
  ///
  /// [baselineRate] — current value of the metric (e.g. 0.42 for 42%
  /// uncertain_reflections).
  /// [minDetectableLift] — relative lift to detect (e.g. 0.05 = 5% relative).
  ///   The new rate is `baselineRate * (1 + minDetectableLift)`.
  /// [power] — statistical power, typically 0.80 (default).
  /// [alpha] — significance level, typically 0.05 (default).
  ///
  /// Returns the rounded-up sample size. For a 2-branch test, total
  /// participants = 2 × this value.
  static int proportion({
    required double baselineRate,
    required double minDetectableLift,
    double power = 0.80,
    double alpha = 0.05,
  }) {
    if (baselineRate <= 0 || baselineRate >= 1) {
      throw ArgumentError('baselineRate must be in (0, 1), got $baselineRate');
    }
    if (minDetectableLift <= 0) {
      throw ArgumentError(
          'minDetectableLift must be > 0, got $minDetectableLift');
    }
    if (power <= 0 || power >= 1) {
      throw ArgumentError('power must be in (0, 1), got $power');
    }
    if (alpha <= 0 || alpha >= 1) {
      throw ArgumentError('alpha must be in (0, 1), got $alpha');
    }

    final p1 = baselineRate;
    final p2 = baselineRate * (1 + minDetectableLift);
    if (p2 >= 1) {
      throw ArgumentError(
          'p2 = baseline * (1+lift) = $p2 must be < 1. Try smaller lift or baseline.');
    }
    final pooledP = (p1 + p2) / 2;
    final zAlpha = _inverseNormalCDF(1 - alpha / 2);
    final zBeta = _inverseNormalCDF(power);
    final delta = (p1 - p2).abs();

    final numerator = math.pow(
      zAlpha * math.sqrt(2 * pooledP * (1 - pooledP)) +
          zBeta * math.sqrt(p1 * (1 - p1) + p2 * (1 - p2)),
      2,
    );
    final denominator = math.pow(delta, 2);
    return (numerator / denominator).ceil();
  }

  /// Inverse standard normal CDF (probit function).
  /// Beasley-Springer-Moro approximation, accurate to ~10^-7 within
  /// the (1e-15, 1-1e-15) interval. Good enough for sample-size calc.
  static double _inverseNormalCDF(double p) {
    if (p <= 0 || p >= 1) {
      throw ArgumentError('p must be in (0, 1) for inverseNormalCDF');
    }
    // Coefficients for Beasley-Springer-Moro
    const a = [
      -3.969683028665376e+01,
      2.209460984245205e+02,
      -2.759285104469687e+02,
      1.383577518672690e+02,
      -3.066479806614716e+01,
      2.506628277459239e+00,
    ];
    const b = [
      -5.447609879822406e+01,
      1.615858368580409e+02,
      -1.556989798598866e+02,
      6.680131188771972e+01,
      -1.328068155288572e+01,
    ];
    const c = [
      -7.784894002430293e-03,
      -3.223964580411365e-01,
      -2.400758277161838e+00,
      -2.549732539343734e+00,
      4.374664141464968e+00,
      2.938163982698783e+00,
    ];
    const d = [
      7.784695709041462e-03,
      3.224671290700398e-01,
      2.445134137142996e+00,
      3.754408661907416e+00,
    ];
    const pLow = 0.02425;
    const pHigh = 1 - pLow;
    double q, r;
    if (p < pLow) {
      q = math.sqrt(-2 * math.log(p));
      return (((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) *
                  q +
              c[5]) /
          ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1);
    } else if (p <= pHigh) {
      q = p - 0.5;
      r = q * q;
      return (((((a[0] * r + a[1]) * r + a[2]) * r + a[3]) * r + a[4]) *
                  r +
              a[5]) *
          q /
          (((((b[0] * r + b[1]) * r + b[2]) * r + b[3]) * r + b[4]) * r + 1);
    } else {
      q = math.sqrt(-2 * math.log(1 - p));
      return -(((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) *
                  q +
              c[5]) /
          ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1);
    }
  }
}
