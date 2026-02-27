
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/engine_event_bus.dart';
import 'package:fluera_engine/src/core/engine_event.dart';
import 'package:fluera_engine/src/core/engine_error.dart';

void main() {
  late EngineEventBus bus;

  setUp(() {
    bus = EngineEventBus();
  });

  tearDown(() {
    bus.dispose();
  });

  // ===========================================================================
  // EMIT & STREAM
  // ===========================================================================

  group('emit and stream', () {
    test('emitted events are delivered to stream listeners', () async {
      final events = <EngineEvent>[];
      bus.stream.listen(events.add);

      final event = SelectionChangedEngineEvent(
        changeType: 'selected',
        affectedIds: ['n1'],
        totalSelected: 1,
      );
      bus.emit(event);

      // Allow microtask to process (broadcast stream is async)
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(1));
      expect(events.first, isA<SelectionChangedEngineEvent>());
    });

    test('totalEmitted tracks emitted count', () {
      expect(bus.totalEmitted, 0);

      bus.emit(
        SelectionChangedEngineEvent(
          changeType: 'cleared',
          affectedIds: [],
          totalSelected: 0,
        ),
      );

      expect(bus.totalEmitted, 1);
    });

    test('eventCountByType tracks per-type counts', () {
      bus.emit(
        SelectionChangedEngineEvent(
          changeType: 'selected',
          affectedIds: ['a'],
          totalSelected: 1,
        ),
      );
      bus.emit(
        SelectionChangedEngineEvent(
          changeType: 'cleared',
          affectedIds: [],
          totalSelected: 0,
        ),
      );

      final counts = bus.eventCountByType;
      expect(counts['SelectionChangedEngineEvent'], 2);
    });
  });

  // ===========================================================================
  // TYPED SUBSCRIPTIONS
  // ===========================================================================

  group('typed subscriptions', () {
    test('on<T>() filters to specific event type', () async {
      final selection = <SelectionChangedEngineEvent>[];
      bus.on<SelectionChangedEngineEvent>().listen(selection.add);

      bus.emit(
        SelectionChangedEngineEvent(
          changeType: 'selected',
          affectedIds: ['a'],
          totalSelected: 1,
        ),
      );
      bus.emit(
        CommandExecutedEngineEvent(
          commandLabel: 'Move',
          commandType: 'MoveCommand',
        ),
      );

      await Future<void>.delayed(Duration.zero);

      expect(selection, hasLength(1));
      expect(selection.first.changeType, 'selected');
    });

    test('whereSource filters by source string', () async {
      final fromSG = <EngineEvent>[];
      bus.whereSource('SceneGraph').listen(fromSG.add);

      bus.emit(
        NodeReorderedEngineEvent(parentId: 'layer1', oldIndex: 0, newIndex: 1),
      );
      bus.emit(
        SelectionChangedEngineEvent(
          changeType: 'cleared',
          affectedIds: [],
          totalSelected: 0,
        ),
      );

      await Future<void>.delayed(Duration.zero);

      expect(fromSG, hasLength(1));
      expect(fromSG.first, isA<NodeReorderedEngineEvent>());
    });

    test('whereDomain filters by domain', () async {
      final commandEvents = <EngineEvent>[];
      bus.whereDomain(EventDomain.command).listen(commandEvents.add);

      bus.emit(
        CommandExecutedEngineEvent(
          commandLabel: 'Delete',
          commandType: 'DeleteCommand',
        ),
      );
      bus.emit(
        SelectionChangedEngineEvent(
          changeType: 'cleared',
          affectedIds: [],
          totalSelected: 0,
        ),
      );

      await Future<void>.delayed(Duration.zero);

      expect(commandEvents, hasLength(1));
      expect(commandEvents.first, isA<CommandExecutedEngineEvent>());
    });
  });

  // ===========================================================================
  // PAUSE / RESUME
  // ===========================================================================

  group('pause and resume', () {
    test('paused bus suppresses best-effort events', () async {
      final events = <EngineEvent>[];
      bus.stream.listen(events.add);

      bus.pause();
      expect(bus.isPaused, true);

      bus.emit(
        SelectionChangedEngineEvent(
          changeType: 'selected',
          affectedIds: ['a'],
          totalSelected: 1,
        ),
      );

      await Future<void>.delayed(Duration.zero);

      // Suppressed event + no BatchComplete yet
      expect(events, isEmpty);
    });

    test(
      'resume emits BatchCompleteEngineEvent with suppressed count',
      () async {
        final events = <EngineEvent>[];
        bus.stream.listen(events.add);

        bus.pause();
        bus.emit(
          SelectionChangedEngineEvent(
            changeType: 'selected',
            affectedIds: ['a'],
            totalSelected: 1,
          ),
        );
        bus.emit(
          SelectionChangedEngineEvent(
            changeType: 'cleared',
            affectedIds: [],
            totalSelected: 0,
          ),
        );
        bus.resume();

        await Future<void>.delayed(Duration.zero);

        expect(bus.isPaused, false);
        expect(events, hasLength(1));
        expect(events.first, isA<BatchCompleteEngineEvent>());
        final batch = events.first as BatchCompleteEngineEvent;
        expect(batch.suppressedCount, 2);
        expect(batch.pauseDuration, isA<Duration>());
      },
    );

    test(
      'resume without suppressed events does not emit BatchComplete',
      () async {
        final events = <EngineEvent>[];
        bus.stream.listen(events.add);

        bus.pause();
        bus.resume();

        await Future<void>.delayed(Duration.zero);

        expect(events, isEmpty);
      },
    );

    test('double pause is idempotent', () {
      bus.pause();
      bus.pause();
      expect(bus.isPaused, true);
    });

    test('resume without pause is idempotent', () {
      bus.resume(); // Should not throw
      expect(bus.isPaused, false);
    });
  });

  // ===========================================================================
  // CRITICAL EVENTS DURING PAUSE
  // ===========================================================================

  group('critical events during pause', () {
    test(
      'critical events are buffered during pause and flushed on resume',
      () async {
        final events = <EngineEvent>[];
        bus.stream.listen(events.add);

        bus.pause();

        // ErrorReportedEngineEvent is a CriticalEvent
        final error = EngineError(
          severity: ErrorSeverity.fatal,
          domain: ErrorDomain.sceneGraph,
          source: 'test',
          original: 'test error',
        );
        bus.emit(ErrorReportedEngineEvent(error: error));

        // Non-critical event — suppressed
        bus.emit(
          SelectionChangedEngineEvent(
            changeType: 'cleared',
            affectedIds: [],
            totalSelected: 0,
          ),
        );

        bus.resume();

        await Future<void>.delayed(Duration.zero);

        // Critical event + BatchComplete event
        expect(events, hasLength(2));
        expect(events[0], isA<ErrorReportedEngineEvent>());
        expect(events[1], isA<BatchCompleteEngineEvent>());
        final batch = events[1] as BatchCompleteEngineEvent;
        // Both the critical and non-critical count as suppressed
        expect(batch.suppressedCount, 2);
      },
    );
  });

  // ===========================================================================
  // BATCHING
  // ===========================================================================

  group('batching', () {
    test('enableBatching delays delivery to microtask', () async {
      bus.enableBatching = true;
      final events = <EngineEvent>[];
      bus.stream.listen(events.add);

      bus.emit(
        SelectionChangedEngineEvent(
          changeType: 'selected',
          affectedIds: ['a'],
          totalSelected: 1,
        ),
      );
      bus.emit(
        SelectionChangedEngineEvent(
          changeType: 'selected',
          affectedIds: ['b'],
          totalSelected: 2,
        ),
      );

      // Not delivered synchronously
      // (stream is async broadcast, so even without batching delivery
      //  happens in microtask — but batching coalesces them)

      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(2));
      expect(bus.totalEmitted, 2);
    });
  });

  // ===========================================================================
  // DISPOSE
  // ===========================================================================

  group('dispose', () {
    test('emit after dispose is a no-op', () {
      bus.dispose();

      // Should not throw
      bus.emit(
        SelectionChangedEngineEvent(
          changeType: 'cleared',
          affectedIds: [],
          totalSelected: 0,
        ),
      );

      expect(bus.totalEmitted, 0);
    });
  });
}
