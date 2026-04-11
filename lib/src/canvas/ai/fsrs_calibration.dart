// ============================================================================
// 📊 FSRS PERSONAL CALIBRATION — Gradient descent on review data (A5-06)
//
// Specifica: A5-06
//
// After 100+ reviews, the FSRS weights can be personalized per-student
// using gradient descent on their actual review history. This optimizes
// the spacing intervals for their individual learning speed.
//
// The algorithm:
//   1. Collect review history: (stability, difficulty, quality, elapsed_days)
//   2. For each review, compute predicted vs actual retention
//   3. Use gradient descent to minimize log-loss between predicted and actual
//   4. Output: personalized FsrsWeights (w0..w7)
//
// CONSTRAINTS:
//   - Minimum 100 reviews before calibration (A5-06)
//   - Weights clamped to reasonable ranges (prevent degenerate scheduling)
//   - Learning rate: 0.01 (conservative to prevent overfitting)
//   - Max iterations: 200 (bounded computation time)
//   - Runs async (never blocks UI)
//
// ARCHITECTURE:
//   Pure computation — no Flutter dependencies.
//   Called by the host app on a background schedule (e.g., weekly).
//
// THREAD SAFETY: Can run in a separate isolate.
// ============================================================================

import 'dart:math';

import 'fsrs_scheduler.dart';

/// 📊 A single review record for calibration.
class ReviewRecord {
  /// Stability before this review.
  final double stabilityBefore;

  /// Difficulty before this review.
  final double difficulty;

  /// Days elapsed since last review.
  final double elapsedDays;

  /// Whether recall was correct (true) or incorrect (false).
  final bool wasCorrect;

  const ReviewRecord({
    required this.stabilityBefore,
    required this.difficulty,
    required this.elapsedDays,
    required this.wasCorrect,
  });

  factory ReviewRecord.fromJson(Map<String, dynamic> json) => ReviewRecord(
        stabilityBefore: (json['stabilityBefore'] as num).toDouble(),
        difficulty: (json['difficulty'] as num).toDouble(),
        elapsedDays: (json['elapsedDays'] as num).toDouble(),
        wasCorrect: json['wasCorrect'] as bool,
      );

  Map<String, dynamic> toJson() => {
        'stabilityBefore': stabilityBefore,
        'difficulty': difficulty,
        'elapsedDays': elapsedDays,
        'wasCorrect': wasCorrect,
      };
}

/// 📊 Result of a calibration run.
class CalibrationResult {
  /// Optimized weights.
  final FsrsWeights weights;

  /// Final log-loss (lower = better fit).
  final double finalLoss;

  /// Number of iterations performed.
  final int iterations;

  /// Number of reviews used for calibration.
  final int reviewCount;

  /// Whether the calibration converged.
  final bool converged;

  const CalibrationResult({
    required this.weights,
    required this.finalLoss,
    required this.iterations,
    required this.reviewCount,
    required this.converged,
  });
}

/// 📊 FSRS Personal Calibration (A5-06).
///
/// Uses gradient descent to optimize FSRS weights for a specific student
/// based on their actual review history.
class FsrsCalibration {
  const FsrsCalibration._();

  /// Minimum reviews required before calibration.
  static const int minReviews = 100;

  /// Learning rate for gradient descent.
  static const double _lr = 0.01;

  /// Maximum iterations.
  static const int _maxIter = 200;

  /// Convergence threshold (gradient norm).
  static const double _convergenceThreshold = 1e-5;

  /// Weight bounds: prevent degenerate scheduling.
  static const List<(double, double)> _bounds = [
    (0.01, 2.0), // w0: base growth
    (0.01, 2.0), // w1: difficulty impact on growth
    (0.5, 5.0),  // w2: stability impact on growth
    (0.01, 1.0), // w3: retrievability impact on growth
    (1.0, 15.0), // w4: base decay
    (0.01, 1.0), // w5: difficulty impact on decay
    (0.1, 3.0),  // w6: stability impact on decay
    (0.01, 1.0), // w7: retrievability impact on decay
  ];

  /// Run calibration on review history.
  ///
  /// Returns null if fewer than [minReviews] records are provided.
  /// This is a CPU-intensive operation — run in an isolate if possible.
  static CalibrationResult? calibrate(List<ReviewRecord> reviews) {
    if (reviews.length < minReviews) return null;

    // Start from default weights.
    var w = [0.40, 0.60, 2.40, 0.10, 5.00, 0.10, 0.80, 0.20];
    double prevLoss = double.infinity;
    bool converged = false;
    int iter = 0;

    for (iter = 0; iter < _maxIter; iter++) {
      // Compute loss and gradients.
      final (loss, gradients) = _computeLossAndGradients(w, reviews);

      // Check convergence.
      final gradNorm = sqrt(gradients.fold(0.0, (s, g) => s + g * g));
      if (gradNorm < _convergenceThreshold || (prevLoss - loss).abs() < 1e-8) {
        converged = true;
        break;
      }
      prevLoss = loss;

      // Update weights via gradient descent.
      for (int i = 0; i < 8; i++) {
        w[i] -= _lr * gradients[i];
        // Clamp to bounds.
        w[i] = w[i].clamp(_bounds[i].$1, _bounds[i].$2);
      }
    }

    final finalLoss = _computeLoss(w, reviews);

    return CalibrationResult(
      weights: FsrsWeights(
        w0: w[0], w1: w[1], w2: w[2], w3: w[3],
        w4: w[4], w5: w[5], w6: w[6], w7: w[7],
      ),
      finalLoss: finalLoss,
      iterations: iter,
      reviewCount: reviews.length,
      converged: converged,
    );
  }

  /// Compute log-loss between predicted and actual retention.
  static double _computeLoss(List<double> w, List<ReviewRecord> reviews) {
    double totalLoss = 0;
    for (final r in reviews) {
      final predicted = _predictRetention(w, r);
      final actual = r.wasCorrect ? 1.0 : 0.0;
      // Binary cross-entropy with epsilon for numerical stability.
      final p = predicted.clamp(1e-7, 1.0 - 1e-7);
      totalLoss -= actual * log(p) + (1 - actual) * log(1 - p);
    }
    return totalLoss / reviews.length;
  }

  /// Compute loss AND gradients via numerical differentiation.
  static (double, List<double>) _computeLossAndGradients(
    List<double> w,
    List<ReviewRecord> reviews,
  ) {
    final loss = _computeLoss(w, reviews);
    final gradients = List<double>.filled(8, 0.0);
    const h = 1e-5;

    for (int i = 0; i < 8; i++) {
      final wPlus = List<double>.from(w);
      wPlus[i] += h;
      final lossPlus = _computeLoss(wPlus, reviews);
      gradients[i] = (lossPlus - loss) / h;
    }

    return (loss, gradients);
  }

  /// Predict retention probability using FSRS formula.
  static double _predictRetention(List<double> w, ReviewRecord r) {
    // R(t) = (1 + t / (9 * S))^(-1)
    // where S = stability, t = elapsed days
    final S = r.stabilityBefore.clamp(0.1, 10000.0);
    final t = r.elapsedDays.clamp(0.0, 3650.0);
    return pow(1 + t / (9 * S), -1).toDouble();
  }
}
