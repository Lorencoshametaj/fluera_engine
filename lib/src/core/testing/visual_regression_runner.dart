/// 🧪 VISUAL REGRESSION RUNNER — Orchestrates golden image testing.
///
/// Captures rendered output, compares against golden snapshots, and
/// produces structured reports for CI/CD pipelines.
///
/// ```dart
/// final runner = VisualRegressionRunner(
///   goldenStore: goldenStore,
///   diffConfig: PixelDiffConfig.lenient,
/// );
///
/// final result = runner.runCase(
///   RegressionTestCase(id: 'button_primary', label: 'Primary button'),
///   actualImage: capturedRgba,
///   width: 200,
///   height: 48,
/// );
///
/// if (result.status == TestStatus.failed) {
///   print('Visual regression: ${result.summary}');
/// }
/// ```
library;

import 'dart:typed_data';

import 'golden_snapshot.dart';
import 'pixel_diff_engine.dart';

// =============================================================================
// TEST CASE
// =============================================================================

/// Definition of a single visual regression test.
class RegressionTestCase {
  /// Unique test identifier (must match golden store keys).
  final String id;

  /// Human-readable label.
  final String label;

  /// Optional test tags for filtering.
  final Set<String> tags;

  const RegressionTestCase({
    required this.id,
    required this.label,
    this.tags = const {},
  });

  @override
  String toString() => 'RegressionTestCase($id)';
}

// =============================================================================
// TEST STATUS
// =============================================================================

/// Status of a single visual regression test.
enum TestStatus {
  /// Image matches the golden within thresholds.
  passed,

  /// Image differs from the golden beyond thresholds.
  failed,

  /// No golden exists — this is a new baseline.
  newGolden,

  /// Test encountered an error (e.g. dimension mismatch).
  error,
}

// =============================================================================
// TEST RESULT
// =============================================================================

/// Result of a single visual regression test case.
class RegressionTestResult {
  /// The test case that was run.
  final RegressionTestCase testCase;

  /// Test outcome status.
  final TestStatus status;

  /// Pixel diff result (null for new goldens or errors).
  final PixelDiffResult? diffResult;

  /// Human-readable summary.
  final String summary;

  /// Error message if status is [TestStatus.error].
  final String? error;

  /// Timestamp of this test run.
  final DateTime timestamp;

  RegressionTestResult({
    required this.testCase,
    required this.status,
    this.diffResult,
    required this.summary,
    this.error,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now().toUtc();

  /// Serialize to JSON (excludes diff image bytes for reports).
  Map<String, dynamic> toJson() => {
    'id': testCase.id,
    'label': testCase.label,
    'status': status.name,
    'summary': summary,
    'timestamp': timestamp.toIso8601String(),
    if (diffResult != null)
      'diff': {
        'diffPercent': diffResult!.diffPercent,
        'differentPixels': diffResult!.differentPixels,
        'totalPixels': diffResult!.totalPixels,
        'maxChannelDiff': diffResult!.maxChannelDiff,
      },
    if (error != null) 'error': error,
  };

  @override
  String toString() => 'RegressionTestResult(${testCase.id}, ${status.name})';
}

// =============================================================================
// REGRESSION REPORT
// =============================================================================

/// Aggregated report of all visual regression test results.
class RegressionReport {
  /// Individual test results.
  final List<RegressionTestResult> results;

  /// When this report was generated.
  final DateTime timestamp;

  RegressionReport({required this.results, DateTime? timestamp})
    : timestamp = timestamp ?? DateTime.now().toUtc();

  /// Number of tests that passed.
  int get passed => results.where((r) => r.status == TestStatus.passed).length;

  /// Number of tests that failed.
  int get failed => results.where((r) => r.status == TestStatus.failed).length;

  /// Number of new goldens created.
  int get newGoldens =>
      results.where((r) => r.status == TestStatus.newGolden).length;

  /// Number of tests that errored.
  int get errors => results.where((r) => r.status == TestStatus.error).length;

  /// Total number of tests.
  int get total => results.length;

  /// Whether all tests passed (no failures or errors).
  bool get allPassed => failed == 0 && errors == 0;

  /// Generate a markdown report.
  String toMarkdown() {
    final buf = StringBuffer();
    buf.writeln('# Visual Regression Report');
    buf.writeln();
    buf.writeln('**Generated:** ${timestamp.toIso8601String()}');
    buf.writeln();
    buf.writeln('| Metric | Count |');
    buf.writeln('|--------|-------|');
    buf.writeln('| ✅ Passed | $passed |');
    buf.writeln('| ❌ Failed | $failed |');
    buf.writeln('| 🆕 New | $newGoldens |');
    buf.writeln('| ⚠️ Errors | $errors |');
    buf.writeln('| **Total** | **$total** |');
    buf.writeln();

    if (failed > 0) {
      buf.writeln('## Failures');
      buf.writeln();
      for (final r in results.where((r) => r.status == TestStatus.failed)) {
        buf.writeln('### ${r.testCase.label}');
        buf.writeln('- **ID:** `${r.testCase.id}`');
        buf.writeln(
          '- **Diff:** ${r.diffResult?.diffPercent.toStringAsFixed(2)}%',
        );
        buf.writeln(
          '- **Pixels:** ${r.diffResult?.differentPixels}/${r.diffResult?.totalPixels}',
        );
        buf.writeln();
      }
    }

    return buf.toString();
  }

  /// Serialize to JSON.
  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'summary': {
      'total': total,
      'passed': passed,
      'failed': failed,
      'newGoldens': newGoldens,
      'errors': errors,
    },
    'results': results.map((r) => r.toJson()).toList(),
  };

  @override
  String toString() =>
      'RegressionReport(total=$total, passed=$passed, '
      'failed=$failed, new=$newGoldens)';
}

// =============================================================================
// VISUAL REGRESSION RUNNER
// =============================================================================

/// Orchestrates visual regression testing.
///
/// Compares captured images against golden snapshots stored in a
/// [GoldenStore]. Automatically creates new goldens on first run.
class VisualRegressionRunner {
  /// Store for golden reference images.
  final GoldenStore goldenStore;

  /// Pixel diff configuration.
  final PixelDiffConfig diffConfig;

  /// Whether to automatically save new goldens when no baseline exists.
  final bool autoCreateGoldens;

  /// The pixel diff engine.
  final PixelDiffEngine _engine;

  VisualRegressionRunner({
    required this.goldenStore,
    this.diffConfig = PixelDiffConfig.lenient,
    this.autoCreateGoldens = true,
  }) : _engine = const PixelDiffEngine();

  /// Run a single test case.
  ///
  /// [actualImage] must be raw RGBA bytes of size `width * height * 4`.
  RegressionTestResult runCase(
    RegressionTestCase testCase, {
    required Uint8List actualImage,
    required int width,
    required int height,
  }) {
    final golden = goldenStore.load(testCase.id);

    // No golden exists — create new baseline
    if (golden == null) {
      if (autoCreateGoldens) {
        goldenStore.save(
          GoldenSnapshot(
            id: testCase.id,
            imageBytes: actualImage,
            width: width,
            height: height,
            label: testCase.label,
          ),
        );
      }
      return RegressionTestResult(
        testCase: testCase,
        status: TestStatus.newGolden,
        summary: 'New golden created (${width}x$height)',
      );
    }

    // Dimension mismatch
    if (golden.width != width || golden.height != height) {
      return RegressionTestResult(
        testCase: testCase,
        status: TestStatus.error,
        summary:
            'Dimension mismatch: actual ${width}x$height '
            'vs golden ${golden.width}x${golden.height}',
        error: 'dimension_mismatch',
      );
    }

    // Compare pixels
    try {
      final diff = _engine.compare(
        actual: actualImage,
        expected: golden.imageBytes,
        width: width,
        height: height,
        config: diffConfig,
      );

      return RegressionTestResult(
        testCase: testCase,
        status: diff.passed ? TestStatus.passed : TestStatus.failed,
        diffResult: diff,
        summary:
            diff.passed
                ? 'Passed (${diff.diffPercent.toStringAsFixed(2)}% diff)'
                : 'FAILED: ${diff.diffPercent.toStringAsFixed(2)}% pixels differ '
                    '(${diff.differentPixels}/${diff.totalPixels})',
      );
    } catch (e) {
      return RegressionTestResult(
        testCase: testCase,
        status: TestStatus.error,
        summary: 'Error during comparison: $e',
        error: e.toString(),
      );
    }
  }

  /// Run all test cases and produce a report.
  ///
  /// [captures] maps test case IDs to their captured RGBA images + dimensions.
  RegressionReport runAll(List<RegressionCapture> captures) {
    final results = <RegressionTestResult>[];

    for (final capture in captures) {
      results.add(
        runCase(
          capture.testCase,
          actualImage: capture.imageRgba,
          width: capture.width,
          height: capture.height,
        ),
      );
    }

    return RegressionReport(results: results);
  }

  /// Update a golden with new reference data.
  void updateGolden(
    String id, {
    required Uint8List imageBytes,
    required int width,
    required int height,
    String? label,
  }) {
    goldenStore.save(
      GoldenSnapshot(
        id: id,
        imageBytes: imageBytes,
        width: width,
        height: height,
        label: label,
      ),
    );
  }
}

// =============================================================================
// REGRESSION CAPTURE
// =============================================================================

/// A captured image paired with its test case for batch running.
class RegressionCapture {
  /// The test case definition.
  final RegressionTestCase testCase;

  /// Raw RGBA pixel bytes.
  final Uint8List imageRgba;

  /// Image width in pixels.
  final int width;

  /// Image height in pixels.
  final int height;

  const RegressionCapture({
    required this.testCase,
    required this.imageRgba,
    required this.width,
    required this.height,
  });
}
