import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/platform/display_capabilities_detector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // =========================================================================
  // RefreshRate Enum
  // =========================================================================

  group('RefreshRate enum', () {
    test('has 4 standard rates', () {
      expect(RefreshRate.values.length, 4);
    });

    test('hz60 value is 60', () {
      expect(RefreshRate.hz60.value, 60);
    });

    test('hz90 value is 90', () {
      expect(RefreshRate.hz90.value, 90);
    });

    test('hz120 value is 120', () {
      expect(RefreshRate.hz120.value, 120);
    });

    test('hz144 value is 144', () {
      expect(RefreshRate.hz144.value, 144);
    });

    test('toString shows Hz suffix', () {
      expect(RefreshRate.hz120.toString(), '120Hz');
    });
  });

  // =========================================================================
  // DisplayCapabilities
  // =========================================================================

  group('DisplayCapabilities', () {
    test('creates with required fields', () {
      const caps = DisplayCapabilities(
        refreshRate: RefreshRate.hz60,
        frameBudgetMs: 16.67,
        isHighRefreshRate: false,
      );
      expect(caps.refreshRate, RefreshRate.hz60);
      expect(caps.frameBudgetMs, closeTo(16.67, 0.01));
      expect(caps.isHighRefreshRate, isFalse);
    });

    test('high refresh rate at 120Hz', () {
      const caps = DisplayCapabilities(
        refreshRate: RefreshRate.hz120,
        frameBudgetMs: 8.33,
        isHighRefreshRate: true,
      );
      expect(caps.isHighRefreshRate, isTrue);
      expect(caps.frameBudgetMs, closeTo(8.33, 0.01));
    });

    test('toString is readable', () {
      const caps = DisplayCapabilities(
        refreshRate: RefreshRate.hz90,
        frameBudgetMs: 11.11,
        isHighRefreshRate: true,
      );
      final str = caps.toString();
      expect(str, contains('90Hz'));
      expect(str, contains('highRefresh: true'));
    });

    test('frame budget math is consistent', () {
      // 1000ms / 60Hz = 16.67ms
      const caps60 = DisplayCapabilities(
        refreshRate: RefreshRate.hz60,
        frameBudgetMs: 1000.0 / 60,
        isHighRefreshRate: false,
      );
      expect(caps60.frameBudgetMs, closeTo(16.67, 0.01));

      // 1000ms / 120Hz = 8.33ms
      const caps120 = DisplayCapabilities(
        refreshRate: RefreshRate.hz120,
        frameBudgetMs: 1000.0 / 120,
        isHighRefreshRate: true,
      );
      expect(caps120.frameBudgetMs, closeTo(8.33, 0.01));

      // 1000ms / 144Hz = 6.94ms
      const caps144 = DisplayCapabilities(
        refreshRate: RefreshRate.hz144,
        frameBudgetMs: 1000.0 / 144,
        isHighRefreshRate: true,
      );
      expect(caps144.frameBudgetMs, closeTo(6.94, 0.01));
    });
  });

  // =========================================================================
  // High Refresh Rate Threshold
  // =========================================================================

  group('high refresh rate threshold', () {
    test('90Hz is considered high refresh rate', () {
      expect(RefreshRate.hz90.value >= 90, isTrue);
    });

    test('60Hz is not high refresh rate', () {
      expect(RefreshRate.hz60.value >= 90, isFalse);
    });
  });
}
