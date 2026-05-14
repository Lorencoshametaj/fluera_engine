// ============================================================================
// 🧪 ExperimentManager + VariantOverridesProvider — Integration tests
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/ai/experiments/active_experiments.dart';
import 'package:fluera_engine/src/ai/experiments/experiment_definition.dart';
import 'package:fluera_engine/src/ai/experiments/experiment_manager.dart';
import 'package:fluera_engine/src/ai/experiments/variant_overrides_provider.dart';

ExperimentDefinition _exp50({String id = 'e1'}) => ExperimentDefinition(
      id: id,
      name: 'E1',
      hypothesis: 'h',
      variants: const [
        VariantConfig(id: 'control', label: 'A', trafficPercent: 50),
        VariantConfig(id: 'variant_b', label: 'B', trafficPercent: 50),
      ],
      primaryMetric: 'm',
      startedAt: DateTime(2026, 1, 1),
    );

void main() {
  setUp(() => ActiveExperiments.clearForTests());
  tearDown(() => ActiveExperiments.clearForTests());

  group('ExperimentManager', () {
    test('Without userId → all variants resolve to control', () {
      ActiveExperiments.load([_exp50()]);
      final mgr = ExperimentManager();
      expect(mgr.evaluateVariant('e1'), 'control');
    });

    test('With userId → deterministic variant assignment', () {
      ActiveExperiments.load([_exp50()]);
      final mgr = ExperimentManager();
      mgr.userId = 'user-deterministic';
      final v1 = mgr.evaluateVariant('e1');
      final v2 = mgr.evaluateVariant('e1');
      expect(v1, v2);
      expect(['control', 'variant_b'], contains(v1));
    });

    test('Unregistered experimentId returns control', () {
      ActiveExperiments.load([_exp50()]);
      final mgr = ExperimentManager();
      mgr.userId = 'u1';
      expect(mgr.evaluateVariant('unknown'), 'control');
    });

    test('userId change clears cache', () {
      ActiveExperiments.load([_exp50()]);
      final mgr = ExperimentManager();
      mgr.userId = 'u1';
      mgr.evaluateVariant('e1');
      mgr.userId = 'u2';
      // Cache cleared — next call recomputes.
      final v = mgr.evaluateVariant('e1');
      expect(['control', 'variant_b'], contains(v));
    });

    test('currentAssignmentsMap returns flat map per experiment', () {
      ActiveExperiments.load([_exp50(id: 'a'), _exp50(id: 'b')]);
      final mgr = ExperimentManager();
      mgr.userId = 'u1';
      final map = mgr.currentAssignmentsMap();
      expect(map, hasLength(2));
      expect(map.containsKey('a'), isTrue);
      expect(map.containsKey('b'), isTrue);
    });

    test('assignmentsNotifier emits on userId change', () {
      ActiveExperiments.load([_exp50()]);
      final mgr = ExperimentManager();
      var notifications = 0;
      mgr.assignments.addListener(() => notifications++);
      mgr.userId = 'u1';
      mgr.userId = 'u2';
      expect(notifications, 2);
    });
  });

  group('MapVariantOverridesProvider', () {
    test('Returns override when user in variant', () {
      // Same user always lands in same bucket. Use 10 users to find one
      // who lands in variant_b for the test experiment.
      ActiveExperiments.load([_exp50()]);
      final mgr = ExperimentManager();
      final provider = MapVariantOverridesProvider(
        manager: mgr,
        overrides: {
          'e1': {
            'variant_b': {
              'socratic': {
                'anchor': {'it': 'OVERRIDE TEXT IT'},
              },
            },
          },
        },
      );
      String? foundOverride;
      for (var i = 0; i < 50; i++) {
        mgr.userId = 'user-$i';
        final override = provider.cellOverrideFor(
          feature: 'socratic',
          unit: 'anchor',
          langCode: 'it',
        );
        if (override == 'OVERRIDE TEXT IT') {
          foundOverride = override;
          break;
        }
      }
      expect(foundOverride, 'OVERRIDE TEXT IT',
          reason: 'at least one user must land in variant_b within 50 tries');
    });

    test('Returns null for control users', () {
      ActiveExperiments.load([_exp50()]);
      final mgr = ExperimentManager();
      final provider = MapVariantOverridesProvider(
        manager: mgr,
        overrides: {
          'e1': {
            'variant_b': {
              'socratic': {
                'anchor': {'it': 'OVERRIDE'},
              },
            },
          },
        },
      );
      // Find a user who lands in 'control' (50/50 split, expected ~half).
      String? controlVariant;
      mgr.userId = 'user-find-control';
      for (var i = 0; i < 50; i++) {
        mgr.userId = 'user-$i';
        if (mgr.evaluateVariant('e1') == 'control') {
          controlVariant = mgr.userId;
          break;
        }
      }
      expect(controlVariant, isNotNull);
      mgr.userId = controlVariant;
      expect(
        provider.cellOverrideFor(
          feature: 'socratic',
          unit: 'anchor',
          langCode: 'it',
        ),
        isNull,
      );
    });

    test('Returns null when no userId set', () {
      ActiveExperiments.load([_exp50()]);
      final mgr = ExperimentManager();
      final provider = MapVariantOverridesProvider(
        manager: mgr,
        overrides: {
          'e1': {
            'variant_b': {
              'socratic': {
                'anchor': {'it': 'OVERRIDE'},
              },
            },
          },
        },
      );
      expect(
        provider.cellOverrideFor(
            feature: 'socratic', unit: 'anchor', langCode: 'it'),
        isNull,
      );
    });

    test('NoopVariantOverridesProvider always returns null', () {
      const provider = NoopVariantOverridesProvider();
      expect(
        provider.cellOverrideFor(
            feature: 'anything', unit: 'anything', langCode: 'any'),
        isNull,
      );
    });
  });
}
