import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/drawing/models/wetness_state.dart';

void main() {
  // ===========================================================================
  // WetnessState
  // ===========================================================================

  group('WetnessState', () {
    // ── Construction ────────────────────────────────────────────────

    test('starts dry by default', () {
      final ws = WetnessState();
      expect(ws.getWetness(nowMs: 0), 0.0);
    });

    test('starts with initial wetness', () {
      final ws = WetnessState(initialWetness: 0.5, initialTimeMs: 0);
      expect(ws.getWetness(nowMs: 0), 0.5);
    });

    test('clamps initial wetness to [0, 1]', () {
      final ws = WetnessState(initialWetness: 1.5);
      expect(ws.getWetness(nowMs: 0), 1.0);

      final ws2 = WetnessState(initialWetness: -0.5);
      expect(ws2.getWetness(nowMs: 0), 0.0);
    });

    // ── Deposit ─────────────────────────────────────────────────────

    test('deposit increases wetness', () {
      final ws = WetnessState();
      ws.deposit(0.5, nowMs: 0);
      expect(ws.getWetness(nowMs: 0), 0.5);
    });

    test('multiple deposits accumulate', () {
      final ws = WetnessState();
      ws.deposit(0.3, nowMs: 0);
      ws.deposit(0.4, nowMs: 0);
      expect(ws.getWetness(nowMs: 0), closeTo(0.7, 0.01));
    });

    test('deposits saturate at 1.0', () {
      final ws = WetnessState();
      ws.deposit(0.8, nowMs: 0);
      ws.deposit(0.5, nowMs: 0);
      expect(ws.getWetness(nowMs: 0), 1.0);
    });

    // ── Exponential Decay ───────────────────────────────────────────

    test('wetness decays over time', () {
      final ws = WetnessState(decayRate: 0.001);
      ws.deposit(1.0, nowMs: 0);

      final w100 = ws.getWetness(nowMs: 100);
      expect(w100, lessThan(1.0));
      expect(w100, greaterThan(0.8)); // ~0.905
    });

    test('decay follows e^(-λΔt) formula', () {
      final ws = WetnessState(decayRate: 0.001);
      ws.deposit(1.0, nowMs: 0);

      // At t=1000ms with λ=0.001: e^(-1) ≈ 0.368
      final w1000 = ws.getWetness(nowMs: 1000);
      expect(w1000, closeTo(0.368, 0.01));
    });

    test('wetness decays to near-zero after long time', () {
      final ws = WetnessState(decayRate: 0.001);
      ws.deposit(1.0, nowMs: 0);

      // At t=10000ms: e^(-10) ≈ 0.00005
      final wLate = ws.getWetness(nowMs: 10000);
      expect(wLate, 0.0); // snapped to zero
    });

    test('faster decay rate dries faster', () {
      final slow = WetnessState(decayRate: 0.0005);
      final fast = WetnessState(decayRate: 0.005);
      slow.deposit(1.0, nowMs: 0);
      fast.deposit(1.0, nowMs: 0);

      final wSlow = slow.getWetness(nowMs: 500);
      final wFast = fast.getWetness(nowMs: 500);
      expect(wFast, lessThan(wSlow));
    });

    test('deposit after partial decay adds correctly', () {
      final ws = WetnessState(decayRate: 0.001);
      ws.deposit(1.0, nowMs: 0);

      // Wait 1000ms → ~0.368
      // Then deposit 0.3
      ws.deposit(0.3, nowMs: 1000);
      final w = ws.getWetness(nowMs: 1000);
      expect(w, closeTo(0.668, 0.01));
    });

    // ── isDry ────────────────────────────────────────────────────────

    test('isDry returns true for zero wetness', () {
      final ws = WetnessState();
      expect(ws.isDry(nowMs: 0), isTrue);
    });

    test('isDry returns false after deposit', () {
      final ws = WetnessState();
      ws.deposit(0.5, nowMs: 0);
      expect(ws.isDry(nowMs: 0), isFalse);
    });

    test('isDry returns true after full decay', () {
      final ws = WetnessState(decayRate: 0.01);
      ws.deposit(1.0, nowMs: 0);
      expect(ws.isDry(nowMs: 10000), isTrue);
    });

    // ── Reset ────────────────────────────────────────────────────────

    test('reset clears wetness', () {
      final ws = WetnessState();
      ws.deposit(0.8, nowMs: 0);
      ws.reset();
      expect(ws.getWetness(nowMs: 0), 0.0);
    });

    // ── Serialization ────────────────────────────────────────────────

    test('toJson/fromJson round-trips', () {
      final ws = WetnessState(
        initialWetness: 0.7,
        initialTimeMs: 500,
        decayRate: 0.002,
      );
      final json = ws.toJson();
      final restored = WetnessState.fromJson(json);
      expect(restored.getWetness(nowMs: 500), closeTo(0.7, 0.01));
      expect(restored.decayRate, 0.002);
    });

    test('fromJson with null returns defaults', () {
      final ws = WetnessState.fromJson(null);
      expect(ws.getWetness(nowMs: 0), 0.0);
      expect(ws.decayRate, 0.001);
    });

    // ── toString ─────────────────────────────────────────────────────

    test('toString contains key info', () {
      final ws = WetnessState();
      final str = ws.toString();
      expect(str, contains('WetnessState'));
      expect(str, contains('decayRate'));
    });
  });
}
