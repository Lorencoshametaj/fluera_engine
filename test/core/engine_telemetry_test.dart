import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/engine_telemetry.dart';
import 'package:nebula_engine/src/core/engine_scope.dart';

void main() {
  late EngineTelemetry telemetry;

  setUp(() {
    telemetry = EngineTelemetry();
  });

  group('TelemetryCounter', () {
    test('starts at zero', () {
      expect(telemetry.counter('a').value, 0);
    });

    test('increments by 1 default', () {
      telemetry.counter('a').increment();
      expect(telemetry.counter('a').value, 1);
    });

    test('increments by N', () {
      telemetry.counter('a').increment(5);
      expect(telemetry.counter('a').value, 5);
    });

    test('same name returns same counter', () {
      final c1 = telemetry.counter('x');
      final c2 = telemetry.counter('x');
      expect(identical(c1, c2), isTrue);
    });

    test('reset sets to zero', () {
      telemetry.counter('a').increment(10);
      telemetry.counter('a').reset();
      expect(telemetry.counter('a').value, 0);
    });
  });

  group('TelemetryGauge', () {
    test('starts at zero', () {
      expect(telemetry.gauge('mem').value, 0);
    });

    test('set updates value', () {
      telemetry.gauge('mem').set(280.5);
      expect(telemetry.gauge('mem').value, 280.5);
    });

    test('same name returns same gauge', () {
      final g1 = telemetry.gauge('y');
      final g2 = telemetry.gauge('y');
      expect(identical(g1, g2), isTrue);
    });
  });

  group('TelemetrySpan', () {
    test('records start and end timestamps', () {
      final span = telemetry.startSpan('render.frame');
      expect(span.startUs, greaterThan(0));
      expect(span.endUs, isNull);
      expect(span.durationUs, isNull);

      span.end();
      expect(span.endUs, isNotNull);
      expect(span.durationUs, greaterThanOrEqualTo(0));
    });

    test('end is idempotent', () {
      final span = telemetry.startSpan('io.save');
      span.end();
      final firstEnd = span.endUs;
      span.end(); // should not change
      expect(span.endUs, firstEnd);
    });

    test('completed spans appear in snapshot', () {
      final span = telemetry.startSpan('test.span');
      span.end();
      final snap = telemetry.snapshot();
      final spans = snap['spans'] as List;
      expect(spans, hasLength(1));
      expect(spans.first['name'], 'test.span');
      expect(spans.first['durationUs'], isNotNull);
    });

    test('toJson includes required fields', () {
      final span = telemetry.startSpan('x');
      span.end();
      final json = span.toJson();
      expect(json, containsPair('name', 'x'));
      expect(json, contains('startUs'));
      expect(json, contains('endUs'));
      expect(json, contains('durationUs'));
    });
  });

  group('TelemetryEvent', () {
    test('records event with data', () {
      telemetry.event('error.reported', {'domain': 'storage'});
      final snap = telemetry.snapshot();
      final events = snap['events'] as List;
      expect(events, hasLength(1));
      expect(events.first['name'], 'error.reported');
      expect(events.first['data'], {'domain': 'storage'});
    });

    test('records event without data', () {
      telemetry.event('canvas.opened');
      final snap = telemetry.snapshot();
      final events = snap['events'] as List;
      expect(events.first['name'], 'canvas.opened');
      expect(events.first.containsKey('data'), isFalse);
    });
  });

  group('snapshot', () {
    test('returns all primitives with timestamp', () {
      telemetry.counter('c').increment();
      telemetry.gauge('g').set(42);
      telemetry.startSpan('s').end();
      telemetry.event('e');

      final snap = telemetry.snapshot();
      expect(snap, contains('timestampUs'));
      expect(snap['timestampUs'], isA<int>());
      expect(snap['timestampUs'], greaterThan(0));
      expect(snap, contains('counters'));
      expect(snap, contains('gauges'));
      expect(snap, contains('spans'));
      expect(snap, contains('events'));
      expect((snap['counters'] as Map)['c'], 1);
      expect((snap['gauges'] as Map)['g'], 42.0);
      expect((snap['spans'] as List), hasLength(1));
      expect((snap['events'] as List), hasLength(1));
    });
  });

  group('ring buffer', () {
    test('spans are capped at maxSpans', () {
      for (int i = 0; i < EngineTelemetry.maxSpans + 50; i++) {
        telemetry.startSpan('s$i').end();
      }
      final spans = telemetry.snapshot()['spans'] as List;
      expect(spans.length, EngineTelemetry.maxSpans);
      // Oldest should have been evicted — first span should be s50
      expect(spans.first['name'], 's50');
    });

    test('events are capped at maxEvents', () {
      for (int i = 0; i < EngineTelemetry.maxEvents + 10; i++) {
        telemetry.event('e$i');
      }
      final events = telemetry.snapshot()['events'] as List;
      expect(events.length, EngineTelemetry.maxEvents);
      expect(events.first['name'], 'e10');
    });
  });

  group('reset', () {
    test('clears all data', () {
      telemetry.counter('c').increment();
      telemetry.gauge('g').set(1);
      telemetry.startSpan('s').end();
      telemetry.event('e');

      telemetry.reset();

      final snap = telemetry.snapshot();
      expect((snap['counters'] as Map), isEmpty);
      expect((snap['gauges'] as Map), isEmpty);
      expect((snap['spans'] as List), isEmpty);
      expect((snap['events'] as List), isEmpty);
    });
  });

  group('EngineScope integration', () {
    setUp(() {
      EngineScope.reset();
      EngineScope.bind(EngineScope());
    });

    tearDown(() {
      EngineScope.reset();
    });

    test('telemetry is accessible via EngineScope', () {
      final t = EngineScope.current.telemetry;
      expect(t, isA<EngineTelemetry>());
      t.counter('test').increment();
      expect(t.counter('test').value, 1);
    });
  });
}
