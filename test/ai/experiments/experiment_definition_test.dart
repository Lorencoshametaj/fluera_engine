// ============================================================================
// 🧪 ExperimentDefinition — validation tests
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/ai/experiments/active_experiments.dart';
import 'package:fluera_engine/src/ai/experiments/experiment_definition.dart';

void main() {
  group('ExperimentDefinition.validate', () {
    test('Valid definition returns empty issues', () {
      final exp = ExperimentDefinition(
        id: 'test',
        name: 'Test',
        hypothesis: 'Hypothesis A',
        variants: const [
          VariantConfig(id: 'control', label: 'A', trafficPercent: 50),
          VariantConfig(id: 'b', label: 'B', trafficPercent: 50),
        ],
        primaryMetric: 'metric',
        startedAt: DateTime(2026, 1, 1),
      );
      expect(exp.validate(), isEmpty);
    });

    test('Traffic sum != 100 fails', () {
      final exp = ExperimentDefinition(
        id: 'test',
        name: 'Test',
        hypothesis: 'h',
        variants: const [
          VariantConfig(id: 'control', label: 'A', trafficPercent: 40),
          VariantConfig(id: 'b', label: 'B', trafficPercent: 30),
        ],
        primaryMetric: 'metric',
        startedAt: DateTime(2026, 1, 1),
      );
      expect(exp.validate(), contains('traffic sum is 70, must be 100'));
    });

    test('Missing control variant fails', () {
      final exp = ExperimentDefinition(
        id: 'test',
        name: 'Test',
        hypothesis: 'h',
        variants: const [
          VariantConfig(id: 'a', label: 'A', trafficPercent: 50),
          VariantConfig(id: 'b', label: 'B', trafficPercent: 50),
        ],
        primaryMetric: 'metric',
        startedAt: DateTime(2026, 1, 1),
      );
      expect(exp.validate().any((s) => s.contains('control')), isTrue);
    });

    test('Duplicate variant ids fails', () {
      final exp = ExperimentDefinition(
        id: 'test',
        name: 'Test',
        hypothesis: 'h',
        variants: const [
          VariantConfig(id: 'control', label: 'A', trafficPercent: 50),
          VariantConfig(id: 'control', label: 'A2', trafficPercent: 50),
        ],
        primaryMetric: 'metric',
        startedAt: DateTime(2026, 1, 1),
      );
      expect(exp.validate().any((s) => s.contains('duplicate')), isTrue);
    });

    test('endsAt before startedAt fails', () {
      final exp = ExperimentDefinition(
        id: 'test',
        name: 'Test',
        hypothesis: 'h',
        variants: const [
          VariantConfig(id: 'control', label: 'A', trafficPercent: 100),
        ],
        primaryMetric: 'metric',
        startedAt: DateTime(2026, 6, 1),
        endsAt: DateTime(2026, 1, 1),
      );
      expect(exp.validate(), contains('endsAt is before startedAt'));
    });
  });

  group('ExperimentDefinition.isLiveAt', () {
    final exp = ExperimentDefinition(
      id: 'test',
      name: 'Test',
      hypothesis: 'h',
      variants: const [
        VariantConfig(id: 'control', label: 'A', trafficPercent: 100),
      ],
      primaryMetric: 'metric',
      startedAt: DateTime(2026, 1, 1),
      endsAt: DateTime(2026, 12, 31),
    );

    test('Mid-window → live', () {
      expect(exp.isLiveAt(DateTime(2026, 6, 1)), isTrue);
    });

    test('Before window → not live', () {
      expect(exp.isLiveAt(DateTime(2025, 12, 1)), isFalse);
    });

    test('After window → not live', () {
      expect(exp.isLiveAt(DateTime(2027, 1, 1)), isFalse);
    });

    test('active=false at any time → not live', () {
      final dead = ExperimentDefinition(
        id: 'test',
        name: 'Test',
        hypothesis: 'h',
        variants: const [
          VariantConfig(id: 'control', label: 'A', trafficPercent: 100),
        ],
        primaryMetric: 'metric',
        startedAt: DateTime(2026, 1, 1),
        active: false,
      );
      expect(dead.isLiveAt(DateTime(2026, 6, 1)), isFalse);
    });
  });

  group('ActiveExperiments', () {
    setUp(() => ActiveExperiments.clearForTests());
    tearDown(() => ActiveExperiments.clearForTests());

    test('Default is empty', () {
      expect(ActiveExperiments.current, isEmpty);
    });

    test('load valid experiments populates registry', () {
      final exp = ExperimentDefinition(
        id: 'e1',
        name: 'E1',
        hypothesis: 'h',
        variants: const [
          VariantConfig(id: 'control', label: 'A', trafficPercent: 100),
        ],
        primaryMetric: 'm',
        startedAt: DateTime(2026, 1, 1),
      );
      ActiveExperiments.load([exp]);
      expect(ActiveExperiments.current, hasLength(1));
      expect(ActiveExperiments.byId('e1'), isNotNull);
      expect(ActiveExperiments.byId('nonexistent'), isNull);
    });

    test('load rejects invalid experiments', () {
      final bad = ExperimentDefinition(
        id: 'bad',
        name: 'Bad',
        hypothesis: 'h',
        variants: const [
          VariantConfig(id: 'a', label: 'A', trafficPercent: 70),
        ],
        primaryMetric: 'm',
        startedAt: DateTime(2026, 1, 1),
      );
      expect(() => ActiveExperiments.load([bad]), throwsStateError);
    });

    test('load rejects duplicate ids', () {
      final exp = ExperimentDefinition(
        id: 'e1',
        name: 'E1',
        hypothesis: 'h',
        variants: const [
          VariantConfig(id: 'control', label: 'A', trafficPercent: 100),
        ],
        primaryMetric: 'm',
        startedAt: DateTime(2026, 1, 1),
      );
      expect(() => ActiveExperiments.load([exp, exp]), throwsStateError);
    });
  });
}
