import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/testing/golden_snapshot.dart';
import 'package:fluera_engine/src/core/testing/performance_baseline.dart';
import 'package:fluera_engine/src/core/testing/pixel_diff_engine.dart';
import 'package:fluera_engine/src/core/testing/visual_regression_runner.dart';

/// Create a solid RGBA image of the given color.
Uint8List _solidImage(int w, int h, int r, int g, int b, [int a = 255]) {
  final bytes = Uint8List(w * h * 4);
  for (int i = 0; i < w * h; i++) {
    bytes[i * 4] = r;
    bytes[i * 4 + 1] = g;
    bytes[i * 4 + 2] = b;
    bytes[i * 4 + 3] = a;
  }
  return bytes;
}

void main() {
  // ===========================================================================
  // GOLDEN SNAPSHOT
  // ===========================================================================

  group('GoldenSnapshot', () {
    test('creates with defaults', () {
      final snap = GoldenSnapshot(
        id: 'test-1',
        imageBytes: Uint8List(100),
        width: 10,
        height: 10,
      );
      expect(snap.id, 'test-1');
      expect(snap.fileSizeBytes, 100);
      expect(snap.capturedAt.isUtc, isTrue);
    });

    test('toJson/fromJson round-trips', () {
      final original = GoldenSnapshot(
        id: 'btn-primary',
        imageBytes: Uint8List.fromList([1, 2, 3, 4]),
        width: 200,
        height: 48,
        label: 'Primary button',
        metadata: {'os': 'linux', 'dpr': 2.0},
      );

      final json = original.toJson();
      final restored = GoldenSnapshot.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.imageBytes, original.imageBytes);
      expect(restored.width, original.width);
      expect(restored.height, original.height);
      expect(restored.label, original.label);
      expect(restored.metadata, original.metadata);
    });
  });

  // ===========================================================================
  // GOLDEN STORE
  // ===========================================================================

  group('GoldenStore', () {
    late GoldenStore store;

    setUp(() => store = GoldenStore());

    test('save and load', () {
      final snap = GoldenSnapshot(
        id: 'a',
        imageBytes: Uint8List(4),
        width: 1,
        height: 1,
      );
      store.save(snap);
      expect(store.load('a'), isNotNull);
      expect(store.load('a')!.id, 'a');
    });

    test('delete returns true if existed', () {
      store.save(
        GoldenSnapshot(id: 'x', imageBytes: Uint8List(4), width: 1, height: 1),
      );
      expect(store.delete('x'), isTrue);
      expect(store.delete('x'), isFalse);
    });

    test('allIds and count', () {
      store.save(
        GoldenSnapshot(id: 'a', imageBytes: Uint8List(4), width: 1, height: 1),
      );
      store.save(
        GoldenSnapshot(id: 'b', imageBytes: Uint8List(4), width: 1, height: 1),
      );
      expect(store.count, 2);
      expect(store.allIds, containsAll(['a', 'b']));
    });

    test('exportAll/importAll round-trips', () {
      store.save(
        GoldenSnapshot(
          id: 'x',
          imageBytes: Uint8List.fromList([1, 2, 3, 4]),
          width: 1,
          height: 1,
        ),
      );

      final exported = store.exportAll();
      final store2 = GoldenStore();
      store2.importAll(exported);

      expect(store2.count, 1);
      expect(store2.load('x')!.imageBytes, Uint8List.fromList([1, 2, 3, 4]));
    });

    test('importAll respects overwrite flag', () {
      store.save(
        GoldenSnapshot(
          id: 'x',
          imageBytes: Uint8List.fromList([1]),
          width: 1,
          height: 1,
        ),
      );

      final data = {
        'snapshots': {
          'x':
              GoldenSnapshot(
                id: 'x',
                imageBytes: Uint8List.fromList([9, 9]),
                width: 1,
                height: 1,
              ).toJson(),
        },
      };

      // Without overwrite — original preserved
      store.importAll(data, overwrite: false);
      expect(store.load('x')!.imageBytes, Uint8List.fromList([1]));

      // With overwrite — replaced
      store.importAll(data, overwrite: true);
      expect(store.load('x')!.imageBytes, Uint8List.fromList([9, 9]));
    });
  });

  // ===========================================================================
  // PIXEL DIFF ENGINE
  // ===========================================================================

  group('PixelDiffEngine', () {
    const engine = PixelDiffEngine();

    test('identical images pass', () {
      final img = _solidImage(4, 4, 255, 0, 0);
      final result = engine.compare(
        actual: img,
        expected: Uint8List.fromList(img),
        width: 4,
        height: 4,
      );

      expect(result.passed, isTrue);
      expect(result.differentPixels, 0);
      expect(result.diffPercent, 0.0);
    });

    test('completely different images fail', () {
      final red = _solidImage(4, 4, 255, 0, 0);
      final blue = _solidImage(4, 4, 0, 0, 255);

      final result = engine.compare(
        actual: red,
        expected: blue,
        width: 4,
        height: 4,
      );

      expect(result.passed, isFalse);
      expect(result.differentPixels, 16);
      expect(result.diffPercent, 100.0);
    });

    test('tolerance allows minor differences', () {
      final a = _solidImage(2, 2, 100, 100, 100);
      final b = _solidImage(2, 2, 103, 100, 100); // 3/255 ≈ 0.012

      final result = engine.compare(
        actual: a,
        expected: b,
        width: 2,
        height: 2,
        config: const PixelDiffConfig(tolerance: 0.02),
      );

      expect(result.passed, isTrue);
      expect(result.differentPixels, 0);
    });

    test('maxDiffPercent allows some failed pixels', () {
      final a = _solidImage(10, 10, 100, 100, 100);
      // Change 5 pixels (5% of 100)
      for (int i = 0; i < 5; i++) {
        a[i * 4] = 0; // drastically different
      }

      final result = engine.compare(
        actual: a,
        expected: _solidImage(10, 10, 100, 100, 100),
        width: 10,
        height: 10,
        config: const PixelDiffConfig(maxDiffPercent: 10.0),
      );

      expect(result.passed, isTrue);
      expect(result.differentPixels, 5);
    });

    test('generates diff image', () {
      final a = _solidImage(2, 2, 255, 0, 0);
      final b = _solidImage(2, 2, 0, 255, 0);

      final result = engine.compare(
        actual: a,
        expected: b,
        width: 2,
        height: 2,
        generateDiffImage: true,
      );

      expect(result.diffImageRgba, isNotNull);
      expect(result.diffImageRgba!.length, 2 * 2 * 4);
      // Diff pixels should be red (R=255)
      expect(result.diffImageRgba![0], 255);
    });

    test('no diff image when not requested', () {
      final img = _solidImage(2, 2, 0, 0, 0);
      final result = engine.compare(
        actual: img,
        expected: Uint8List.fromList(img),
        width: 2,
        height: 2,
        generateDiffImage: false,
      );

      expect(result.diffImageRgba, isNull);
    });

    test('preset configs have expected values', () {
      expect(PixelDiffConfig.exact.tolerance, 0.0);
      expect(PixelDiffConfig.lenient.tolerance, 0.02);
      expect(PixelDiffConfig.generous.maxDiffPercent, 5.0);
      expect(PixelDiffConfig.generous.ignoreAntialiasing, isTrue);
    });
  });

  // ===========================================================================
  // VISUAL REGRESSION RUNNER
  // ===========================================================================

  group('VisualRegressionRunner', () {
    late GoldenStore store;
    late VisualRegressionRunner runner;

    setUp(() {
      store = GoldenStore();
      runner = VisualRegressionRunner(
        goldenStore: store,
        diffConfig: PixelDiffConfig.exact,
      );
    });

    test('creates new golden on first run', () {
      final result = runner.runCase(
        const RegressionTestCase(id: 'new-test', label: 'New test'),
        actualImage: _solidImage(2, 2, 255, 0, 0),
        width: 2,
        height: 2,
      );

      expect(result.status, TestStatus.newGolden);
      expect(store.contains('new-test'), isTrue);
    });

    test('passes when images match', () {
      final img = _solidImage(2, 2, 0, 255, 0);
      store.save(
        GoldenSnapshot(id: 'match', imageBytes: img, width: 2, height: 2),
      );

      final result = runner.runCase(
        const RegressionTestCase(id: 'match', label: 'Match test'),
        actualImage: Uint8List.fromList(img),
        width: 2,
        height: 2,
      );

      expect(result.status, TestStatus.passed);
    });

    test('fails when images differ', () {
      store.save(
        GoldenSnapshot(
          id: 'diff',
          imageBytes: _solidImage(2, 2, 0, 0, 0),
          width: 2,
          height: 2,
        ),
      );

      final result = runner.runCase(
        const RegressionTestCase(id: 'diff', label: 'Diff test'),
        actualImage: _solidImage(2, 2, 255, 255, 255),
        width: 2,
        height: 2,
      );

      expect(result.status, TestStatus.failed);
      expect(result.diffResult, isNotNull);
    });

    test('errors on dimension mismatch', () {
      store.save(
        GoldenSnapshot(
          id: 'dim',
          imageBytes: _solidImage(2, 2, 0, 0, 0),
          width: 2,
          height: 2,
        ),
      );

      final result = runner.runCase(
        const RegressionTestCase(id: 'dim', label: 'Dim test'),
        actualImage: _solidImage(4, 4, 0, 0, 0),
        width: 4,
        height: 4,
      );

      expect(result.status, TestStatus.error);
      expect(result.error, 'dimension_mismatch');
    });

    test('runAll produces report', () {
      final captures = [
        RegressionCapture(
          testCase: const RegressionTestCase(id: 'a', label: 'A'),
          imageRgba: _solidImage(2, 2, 100, 100, 100),
          width: 2,
          height: 2,
        ),
        RegressionCapture(
          testCase: const RegressionTestCase(id: 'b', label: 'B'),
          imageRgba: _solidImage(2, 2, 200, 200, 200),
          width: 2,
          height: 2,
        ),
      ];

      final report = runner.runAll(captures);
      expect(report.total, 2);
      expect(report.newGoldens, 2);
      expect(report.allPassed, isTrue);
    });

    test('report generates markdown', () {
      final report = RegressionReport(
        results: [
          RegressionTestResult(
            testCase: const RegressionTestCase(id: 't1', label: 'Test 1'),
            status: TestStatus.passed,
            summary: 'OK',
          ),
        ],
      );

      final md = report.toMarkdown();
      expect(md, contains('Visual Regression Report'));
      expect(md, contains('Passed'));
    });

    test('updateGolden replaces existing', () {
      store.save(
        GoldenSnapshot(
          id: 'upd',
          imageBytes: _solidImage(2, 2, 0, 0, 0),
          width: 2,
          height: 2,
        ),
      );

      runner.updateGolden(
        'upd',
        imageBytes: _solidImage(2, 2, 255, 255, 255),
        width: 2,
        height: 2,
      );

      expect(store.load('upd')!.imageBytes[0], 255);
    });
  });

  // ===========================================================================
  // PERFORMANCE BASELINE
  // ===========================================================================

  group('PerformanceBaseline', () {
    late PerformanceBaseline baseline;

    setUp(() => baseline = PerformanceBaseline());

    test('record and stats', () {
      baseline.recordAll('render_ms', [8.0, 9.0, 10.0, 11.0]);
      final s = baseline.stats('render_ms')!;

      expect(s.count, 4);
      expect(s.mean, 9.5);
      expect(s.min, 8.0);
      expect(s.max, 11.0);
    });

    test('stats returns null for unknown metric', () {
      expect(baseline.stats('unknown'), isNull);
    });

    test('check detects regression', () {
      baseline.recordAll('fps', [60.0, 60.0, 60.0]);
      final result = baseline.check('fps', 70.0, threshold: 0.1);

      // 70 > 60 * 1.1 = 66 → regression
      expect(result.isRegression, isTrue);
      expect(result.changePercent, closeTo(16.67, 0.1));
    });

    test('check passes within threshold', () {
      baseline.recordAll('fps', [60.0, 60.0, 60.0]);
      final result = baseline.check('fps', 63.0, threshold: 0.1);

      // 63 < 60 * 1.1 = 66 → OK
      expect(result.isRegression, isFalse);
    });

    test('check handles no baseline', () {
      final result = baseline.check('unknown', 42.0);
      expect(result.isRegression, isFalse);
      expect(result.summary, contains('No baseline'));
    });

    test('checkAll processes multiple metrics', () {
      baseline.recordAll('a', [10.0, 10.0]);
      baseline.recordAll('b', [20.0, 20.0]);

      final results = baseline.checkAll({
        'a': 10.5, // within 10%
        'b': 30.0, // 50% regression
      });

      expect(results['a']!.isRegression, isFalse);
      expect(results['b']!.isRegression, isTrue);
    });

    test('p95 calculation', () {
      baseline.recordAll('latency', [
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
        9,
        10,
        11,
        12,
        13,
        14,
        15,
        16,
        17,
        18,
        19,
        20,
      ]);
      final s = baseline.stats('latency')!;
      expect(s.p95, closeTo(19.0, 1.0));
    });

    test('toJson/fromJson round-trips', () {
      baseline.record('render_ms', 8.5);
      baseline.record('render_ms', 9.0);
      baseline.record('memory_mb', 120.0);

      final json = baseline.toJson();
      final restored = PerformanceBaseline.fromJson(json);

      expect(restored.metricNames, containsAll(['render_ms', 'memory_mb']));
      expect(restored.stats('render_ms')!.count, 2);
      expect(restored.stats('memory_mb')!.mean, 120.0);
    });

    test('clear removes all metrics', () {
      baseline.record('x', 1.0);
      baseline.clear();
      expect(baseline.metricNames, isEmpty);
    });
  });
}
