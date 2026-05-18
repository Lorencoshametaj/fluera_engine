// ============================================================================
// 💳 TIER GATE CONTROLLER — Tier × Feature matrix tests
//
// Locks the V1 launch contract: which feature is gated for which tier, and
// how quantity gates (cloud storage, voice minutes, multi-device) scale.
//
// Decision plan: .claude/plans/analizza-tutta-fluera-app-floating-pebble.md
// Spec: A17 (Free limits frequency, not access) + 2026-05-14 Plus/Pro split.
// ============================================================================

import 'package:fluera_engine/fluera_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Helper: instantiate a controller for the requested tier.
  TierGateController gate(FlueraSubscriptionTier tier) =>
      TierGateController(tier: tier);

  group('canUseFeature — Pro-only feature gates', () {
    for (final feature in [
      GatedFeature.timeTravel,
      GatedFeature.collaboration,
      GatedFeature.audioInkSync,
      GatedFeature.backgroundOcr,
    ]) {
      test('$feature is locked for Free + Plus, unlocked for Pro', () {
        expect(gate(FlueraSubscriptionTier.free).canUseFeature(feature),
            isFalse);
        expect(gate(FlueraSubscriptionTier.plus).canUseFeature(feature),
            isFalse);
        expect(gate(FlueraSubscriptionTier.pro).canUseFeature(feature), isTrue);
      });
    }
  });

  group('canUseFeature — Plus + Pro gates (paid tiers)', () {
    for (final feature in [
      GatedFeature.voiceRecording,
      GatedFeature.cloudStorage,
      GatedFeature.multiDevice,
    ]) {
      test('$feature is locked for Free, unlocked for Plus + Pro', () {
        expect(gate(FlueraSubscriptionTier.free).canUseFeature(feature),
            isFalse);
        expect(gate(FlueraSubscriptionTier.plus).canUseFeature(feature),
            isTrue);
        expect(gate(FlueraSubscriptionTier.pro).canUseFeature(feature), isTrue);
      });
    }
  });

  group('canUseFeature — frequency-scoped features (Free has access too)',
      () {
    for (final feature in [
      GatedFeature.socraticSession,
      GatedFeature.ghostMapComparison,
      GatedFeature.fogOfWarSession,
      GatedFeature.crossDomainInteractive,
      GatedFeature.deepReview,
      GatedFeature.examSession,
      GatedFeature.brushAccess,
      GatedFeature.exportFormat,
    ]) {
      test('$feature is accessible on every tier (cap lives in checkFeature)',
          () {
        for (final tier in FlueraSubscriptionTier.values) {
          expect(gate(tier).canUseFeature(feature), isTrue,
              reason: '$feature must be accessible on $tier');
        }
      });
    }
  });

  group('checkFeature — feature-scoped gates short-circuit on tier', () {
    test('Free hit on timeTravel → blocked, no frequency math', () {
      final g = gate(FlueraSubscriptionTier.free);
      final r = g.checkFeature(GatedFeature.timeTravel);
      expect(r.allowed, isFalse);
      expect(r.blockedFeature, GatedFeature.timeTravel);
      expect(r.upgradeMessage, contains('Pro'));
    });

    test('Plus hit on collaboration → blocked (collab is Pro pillar)', () {
      final g = gate(FlueraSubscriptionTier.plus);
      final r = g.checkFeature(GatedFeature.collaboration);
      expect(r.allowed, isFalse);
      expect(r.blockedFeature, GatedFeature.collaboration);
    });

    test('Pro hit on voiceRecording → allowed (paid tier)', () {
      final g = gate(FlueraSubscriptionTier.pro);
      final r = g.checkFeature(GatedFeature.voiceRecording);
      expect(r.allowed, isTrue);
      expect(r.remainingToday, isNull, reason: 'feature-scoped = unlimited');
    });
  });

  group('Quantity gates: cloudStorageQuotaBytes', () {
    test('Free has 0 bytes (local-only)', () {
      expect(gate(FlueraSubscriptionTier.free).cloudStorageQuotaBytes, 0);
    });
    test('Plus has 5 GB', () {
      expect(gate(FlueraSubscriptionTier.plus).cloudStorageQuotaBytes,
          5 * 1024 * 1024 * 1024);
    });
    test('Pro has 50 GB (10× Plus)', () {
      expect(gate(FlueraSubscriptionTier.pro).cloudStorageQuotaBytes,
          50 * 1024 * 1024 * 1024);
    });
    test('Pro quota is exactly 10× Plus quota', () {
      final plus = gate(FlueraSubscriptionTier.plus).cloudStorageQuotaBytes;
      final pro = gate(FlueraSubscriptionTier.pro).cloudStorageQuotaBytes;
      expect(pro, plus * 10);
    });
  });

  group('Quantity gates: maxDeviceCount', () {
    test('Free = 1 device', () {
      expect(gate(FlueraSubscriptionTier.free).maxDeviceCount, 1);
    });
    test('Plus = 2 devices', () {
      expect(gate(FlueraSubscriptionTier.plus).maxDeviceCount, 2);
    });
    test('Pro = unlimited (sentinel -1)', () {
      expect(gate(FlueraSubscriptionTier.pro).maxDeviceCount,
          TierGateController.maxDeviceUnlimited);
      expect(TierGateController.maxDeviceUnlimited, -1);
    });
  });

  group('Quantity gates: voiceMonthlyMinutes', () {
    test('Free = 0 (no voice recording)', () {
      expect(gate(FlueraSubscriptionTier.free).voiceMonthlyMinutes, 0);
    });
    test('Plus = unlimited (V1.5 promotion 2026-05-14)', () {
      // Voice was bumped from 60 min/month → ∞ on Plus so it stops being
      // a Plus→Pro upgrade lever. The Pro pillars (time travel, audio-ink,
      // collab, bg OCR) own that role now.
      expect(gate(FlueraSubscriptionTier.plus).voiceMonthlyMinutes,
          TierGateController.voiceMonthlyUnlimited);
    });
    test('Pro = unlimited (sentinel -1)', () {
      expect(gate(FlueraSubscriptionTier.pro).voiceMonthlyMinutes,
          TierGateController.voiceMonthlyUnlimited);
      expect(TierGateController.voiceMonthlyUnlimited, -1);
    });
  });

  group('Upgrade messages — every feature-scoped gate has a Pro-pointing copy',
      () {
    for (final feature in [
      GatedFeature.timeTravel,
      GatedFeature.collaboration,
      GatedFeature.audioInkSync,
      GatedFeature.voiceRecording,
      GatedFeature.multiDevice,
      GatedFeature.cloudStorage,
      GatedFeature.backgroundOcr,
    ]) {
      test('$feature has a non-empty upgrade message', () {
        // We can only access the message via the GateResult side door because
        // _upgradeMessage is private. Make Free hit each gate and inspect.
        final r = gate(FlueraSubscriptionTier.free).checkFeature(feature);
        expect(r.allowed, isFalse);
        expect(r.upgradeMessage, isNotNull);
        expect(r.upgradeMessage!.length, greaterThan(20),
            reason: 'Upgrade copy for $feature is too short');
      });
    }
  });

  group('Frequency-scoped contract regression (V1 launch caps)', () {
    test('Free + Socratic: 3/week, then blocked', () {
      final g = gate(FlueraSubscriptionTier.free);
      for (var i = 0; i < 3; i++) {
        expect(g.checkFeature(GatedFeature.socraticSession).allowed, isTrue,
            reason: 'Use #${i + 1} must still be allowed');
        g.recordUsage(GatedFeature.socraticSession);
      }
      final blocked = g.checkFeature(GatedFeature.socraticSession);
      expect(blocked.allowed, isFalse);
      expect(blocked.blockedFeature, GatedFeature.socraticSession);
    });

    test('Plus + Socratic: never blocked', () {
      final g = gate(FlueraSubscriptionTier.plus);
      for (var i = 0; i < 10; i++) {
        expect(g.checkFeature(GatedFeature.socraticSession).allowed, isTrue);
        g.recordUsage(GatedFeature.socraticSession);
      }
    });

    test('Pro + Ghost Map: never blocked even on heavy use', () {
      final g = gate(FlueraSubscriptionTier.pro);
      for (var i = 0; i < 50; i++) {
        expect(g.checkFeature(GatedFeature.ghostMapComparison).allowed,
            isTrue);
        g.recordUsage(GatedFeature.ghostMapComparison);
      }
    });
  });

  group('isUnlimited backward-compat', () {
    test('Plus + Pro report unlimited (frequency family)', () {
      expect(gate(FlueraSubscriptionTier.plus).isUnlimited, isTrue);
      expect(gate(FlueraSubscriptionTier.pro).isUnlimited, isTrue);
    });
    test('Free reports NOT unlimited', () {
      expect(gate(FlueraSubscriptionTier.free).isUnlimited, isFalse);
    });
  });

  group('updateTier reactivity', () {
    test('switching Free → Pro flips a Pro-only gate from blocked to allowed',
        () {
      final g = gate(FlueraSubscriptionTier.free);
      expect(g.canUseFeature(GatedFeature.timeTravel), isFalse);

      g.updateTier(FlueraSubscriptionTier.pro);
      expect(g.canUseFeature(GatedFeature.timeTravel), isTrue);
    });

    test('switching Pro → Free flips a Pro-only gate from allowed to blocked',
        () {
      final g = gate(FlueraSubscriptionTier.pro);
      expect(g.canUseFeature(GatedFeature.collaboration), isTrue);

      g.updateTier(FlueraSubscriptionTier.free);
      expect(g.canUseFeature(GatedFeature.collaboration), isFalse);
    });

    test('switching tier updates cloudStorageQuotaBytes', () {
      final g = gate(FlueraSubscriptionTier.free);
      expect(g.cloudStorageQuotaBytes, 0);

      g.updateTier(FlueraSubscriptionTier.plus);
      expect(g.cloudStorageQuotaBytes, 5 * 1024 * 1024 * 1024);

      g.updateTier(FlueraSubscriptionTier.pro);
      expect(g.cloudStorageQuotaBytes, 50 * 1024 * 1024 * 1024);
    });
  });
}
