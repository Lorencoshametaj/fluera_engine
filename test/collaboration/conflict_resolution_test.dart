import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/collaboration/conflict_resolution.dart';
import 'package:nebula_engine/src/collaboration/nebula_realtime_adapter.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // TEXT OT ENGINE
  // ═══════════════════════════════════════════════════════════════════════════

  group('TextOTEngine — apply', () {
    test('retain preserves text', () {
      final result = TextOTEngine.apply('hello', [const RetainOp(5)]);
      expect(result, 'hello');
    });

    test('insert at start', () {
      final result = TextOTEngine.apply('world', [
        const InsertOp('hello '),
        const RetainOp(5),
      ]);
      expect(result, 'hello world');
    });

    test('insert in middle', () {
      final result = TextOTEngine.apply('helo', [
        const RetainOp(2),
        const InsertOp('l'),
        const RetainOp(2),
      ]);
      expect(result, 'hello');
    });

    test('delete characters', () {
      final result = TextOTEngine.apply('hello world', [
        const RetainOp(5),
        const DeleteOp(6),
      ]);
      expect(result, 'hello');
    });

    test('replace text', () {
      final result = TextOTEngine.apply('hello', [
        const DeleteOp(5),
        const InsertOp('world'),
      ]);
      expect(result, 'world');
    });

    test('complex operations', () {
      final result = TextOTEngine.apply('the cat sat on the mat', [
        const RetainOp(4), // "the "
        const DeleteOp(3), // remove "cat"
        const InsertOp('dog'), // insert "dog"
        const RetainOp(15), // " sat on the mat"
      ]);
      expect(result, 'the dog sat on the mat');
    });

    test('throws on retain past end', () {
      expect(
        () => TextOTEngine.apply('hi', [const RetainOp(10)]),
        throwsA(isA<OTException>()),
      );
    });
  });

  group('TextOTEngine — diff', () {
    test('identical strings', () {
      final ops = TextOTEngine.diff('hello', 'hello');
      expect(ops, hasLength(1));
      expect(ops.first, isA<RetainOp>());
    });

    test('insert at end', () {
      final ops = TextOTEngine.diff('hello', 'hello world');
      final result = TextOTEngine.apply('hello', ops);
      expect(result, 'hello world');
    });

    test('delete from end', () {
      final ops = TextOTEngine.diff('hello world', 'hello');
      final result = TextOTEngine.apply('hello world', ops);
      expect(result, 'hello');
    });

    test('replace middle', () {
      final ops = TextOTEngine.diff('the cat sat', 'the dog sat');
      final result = TextOTEngine.apply('the cat sat', ops);
      expect(result, 'the dog sat');
    });

    test('from empty', () {
      final ops = TextOTEngine.diff('', 'hello');
      final result = TextOTEngine.apply('', ops);
      expect(result, 'hello');
    });

    test('to empty', () {
      final ops = TextOTEngine.diff('hello', '');
      final result = TextOTEngine.apply('hello', ops);
      expect(result, '');
    });
  });

  group('TextOTEngine — transform', () {
    test('convergence: both insert at different positions', () {
      // Base: "hello"
      // A inserts " world" at end → "hello world"
      // B inserts "dear " at pos 5 is really pos 0 → "dear hello"
      final base = 'hello';
      final opsA = TextOTEngine.diff(base, 'hello world');
      final opsB = TextOTEngine.diff(base, 'dear hello');

      final (aPrime, bPrime) = TextOTEngine.transform(opsA, opsB);

      // Apply: base → A → B' should equal base → B → A'
      final viaA = TextOTEngine.apply(TextOTEngine.apply(base, opsA), bPrime);
      final viaB = TextOTEngine.apply(TextOTEngine.apply(base, opsB), aPrime);
      expect(viaA, viaB); // Convergence!
    });

    test('convergence: one inserts, one deletes', () {
      final base = 'hello world';
      final opsA = TextOTEngine.diff(base, 'hello beautiful world');
      final opsB = TextOTEngine.diff(base, 'hello');

      final (aPrime, bPrime) = TextOTEngine.transform(opsA, opsB);

      final viaA = TextOTEngine.apply(TextOTEngine.apply(base, opsA), bPrime);
      final viaB = TextOTEngine.apply(TextOTEngine.apply(base, opsB), aPrime);
      expect(viaA, viaB);
    });

    test('convergence: both insert at same position', () {
      final base = 'ac';
      final opsA = TextOTEngine.diff(base, 'abc');
      final opsB = TextOTEngine.diff(base, 'axc');

      final (aPrime, bPrime) = TextOTEngine.transform(opsA, opsB);

      final viaA = TextOTEngine.apply(TextOTEngine.apply(base, opsA), bPrime);
      final viaB = TextOTEngine.apply(TextOTEngine.apply(base, opsB), aPrime);
      expect(viaA, viaB);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // CONFLICT STRATEGIES
  // ═══════════════════════════════════════════════════════════════════════════

  group('LastWriteWinsStrategy', () {
    late LastWriteWinsStrategy strategy;

    setUp(() => strategy = LastWriteWinsStrategy());

    test('remote wins with later timestamp', () async {
      final conflict = ConflictRecord(
        id: '1',
        localEvent: CanvasRealtimeEvent(
          type: RealtimeEventType.imageUpdated,
          senderId: 'u1',
          payload: {'x': 10},
          timestamp: 100,
        ),
        remoteEvent: CanvasRealtimeEvent(
          type: RealtimeEventType.imageUpdated,
          senderId: 'u2',
          payload: {'x': 20},
          timestamp: 200,
        ),
      );

      final result = await strategy.resolve(conflict);
      expect(result, isNotNull);
      expect(result!.resolution, ConflictResolution.lastWriteWins);
      expect(result.resolvedEvent.payload['x'], 20);
    });

    test('local wins with later timestamp', () async {
      final conflict = ConflictRecord(
        id: '2',
        localEvent: CanvasRealtimeEvent(
          type: RealtimeEventType.imageUpdated,
          senderId: 'u1',
          payload: {'x': 10},
          timestamp: 300,
        ),
        remoteEvent: CanvasRealtimeEvent(
          type: RealtimeEventType.imageUpdated,
          senderId: 'u2',
          payload: {'x': 20},
          timestamp: 200,
        ),
      );

      final result = await strategy.resolve(conflict);
      expect(result!.resolvedEvent.payload['x'], 10);
    });

    test('deterministic tie-break on equal timestamps', () async {
      final conflict = ConflictRecord(
        id: '3',
        localEvent: CanvasRealtimeEvent(
          type: RealtimeEventType.imageUpdated,
          senderId: 'aaa',
          payload: {'v': 'local'},
          timestamp: 100,
        ),
        remoteEvent: CanvasRealtimeEvent(
          type: RealtimeEventType.imageUpdated,
          senderId: 'zzz',
          payload: {'v': 'remote'},
          timestamp: 100,
        ),
      );

      final result = await strategy.resolve(conflict);
      expect(result, isNotNull);
      // "zzz" > "aaa" → remote wins
      expect(result!.resolvedEvent.payload['v'], 'remote');
    });
  });

  group('PositionAutoMergeStrategy', () {
    late PositionAutoMergeStrategy strategy;

    setUp(() => strategy = PositionAutoMergeStrategy());

    test('averages x and y coordinates', () async {
      final conflict = ConflictRecord(
        id: '1',
        localEvent: CanvasRealtimeEvent(
          type: RealtimeEventType.imageUpdated,
          senderId: 'u1',
          payload: {'x': 10.0, 'y': 20.0, 'width': 100.0, 'height': 50.0},
          timestamp: 100,
        ),
        remoteEvent: CanvasRealtimeEvent(
          type: RealtimeEventType.imageUpdated,
          senderId: 'u2',
          payload: {'x': 30.0, 'y': 40.0, 'width': 200.0, 'height': 100.0},
          timestamp: 200,
        ),
      );

      final result = await strategy.resolve(conflict);
      expect(result, isNotNull);
      expect(result!.resolution, ConflictResolution.autoMerged);
      expect(result.resolvedEvent.payload['x'], 20.0); // avg(10, 30)
      expect(result.resolvedEvent.payload['y'], 30.0); // avg(20, 40)
      expect(result.resolvedEvent.payload['width'], 150.0);
      expect(result.resolvedEvent.payload['height'], 75.0);
    });

    test('returns null for non-position data', () async {
      final conflict = ConflictRecord(
        id: '2',
        localEvent: CanvasRealtimeEvent(
          type: RealtimeEventType.strokeAdded,
          senderId: 'u1',
          payload: {'color': 0xFF0000},
          timestamp: 100,
        ),
        remoteEvent: CanvasRealtimeEvent(
          type: RealtimeEventType.strokeAdded,
          senderId: 'u2',
          payload: {'color': 0x00FF00},
          timestamp: 200,
        ),
      );

      final result = await strategy.resolve(conflict);
      expect(result, isNull); // Can't merge non-position data
    });
  });

  group('TextOTConflictStrategy', () {
    late TextOTConflictStrategy strategy;

    setUp(() => strategy = TextOTConflictStrategy());

    test('merges concurrent text edits', () async {
      final conflict = ConflictRecord(
        id: '1',
        localEvent: CanvasRealtimeEvent(
          type: RealtimeEventType.textChanged,
          senderId: 'u1',
          elementId: 't1',
          payload: {'text': 'hello world', 'baseText': 'hello'},
          timestamp: 100,
        ),
        remoteEvent: CanvasRealtimeEvent(
          type: RealtimeEventType.textChanged,
          senderId: 'u2',
          elementId: 't1',
          payload: {'text': 'dear hello', 'baseText': 'hello'},
          timestamp: 200,
        ),
      );

      final result = await strategy.resolve(conflict);
      expect(result, isNotNull);
      expect(result!.resolution, ConflictResolution.autoMerged);
      // Both changes should be preserved
      expect(result.resolvedEvent.payload['text'], isNotEmpty);
    });

    test('returns null for non-text events', () async {
      final conflict = ConflictRecord(
        id: '2',
        localEvent: CanvasRealtimeEvent(
          type: RealtimeEventType.imageUpdated,
          senderId: 'u1',
          payload: {'x': 10},
          timestamp: 100,
        ),
        remoteEvent: CanvasRealtimeEvent(
          type: RealtimeEventType.imageUpdated,
          senderId: 'u2',
          payload: {'x': 20},
          timestamp: 200,
        ),
      );

      final result = await strategy.resolve(conflict);
      expect(result, isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // CONFLICT RESOLVER (orchestrator)
  // ═══════════════════════════════════════════════════════════════════════════

  group('ConflictResolver', () {
    late ConflictResolver resolver;

    setUp(() => resolver = ConflictResolver());
    tearDown(() => resolver.dispose());

    test('uses strategy chain: TextOT → PositionMerge → LWW', () async {
      // Position conflict → should use PositionAutoMergeStrategy
      final result = await resolver.resolveConflict(
        localEvent: CanvasRealtimeEvent(
          type: RealtimeEventType.imageUpdated,
          senderId: 'u1',
          elementId: 'img1',
          payload: {'x': 10.0, 'y': 20.0},
          timestamp: 100,
        ),
        remoteEvent: CanvasRealtimeEvent(
          type: RealtimeEventType.imageUpdated,
          senderId: 'u2',
          elementId: 'img1',
          payload: {'x': 30.0, 'y': 40.0},
          timestamp: 200,
        ),
      );

      expect(result, isNotNull);
      expect(result!.resolution, ConflictResolution.autoMerged);
    });

    test('falls through to LWW for non-mergeable events', () async {
      final result = await resolver.resolveConflict(
        localEvent: CanvasRealtimeEvent(
          type: RealtimeEventType.strokeAdded,
          senderId: 'u1',
          elementId: 's1',
          payload: {'color': 0xFF},
          timestamp: 100,
        ),
        remoteEvent: CanvasRealtimeEvent(
          type: RealtimeEventType.strokeAdded,
          senderId: 'u2',
          elementId: 's1',
          payload: {'color': 0x00},
          timestamp: 200,
        ),
      );

      expect(result, isNotNull);
      expect(result!.resolution, ConflictResolution.lastWriteWins);
    });

    test('tracks conflict history', () async {
      await resolver.resolveConflict(
        localEvent: CanvasRealtimeEvent(
          type: RealtimeEventType.strokeAdded,
          senderId: 'u1',
          payload: {},
          timestamp: 100,
        ),
        remoteEvent: CanvasRealtimeEvent(
          type: RealtimeEventType.strokeAdded,
          senderId: 'u2',
          payload: {},
          timestamp: 200,
        ),
      );

      expect(resolver.conflictHistory, hasLength(1));
      expect(resolver.stats.total, 1);
      expect(resolver.stats.autoResolutionRate, greaterThan(0));
    });

    test('emits on onDetected and onResolved streams', () async {
      final detected = <ConflictRecord>[];
      final resolved = <ConflictRecord>[];
      resolver.onDetected.listen(detected.add);
      resolver.onResolved.listen(resolved.add);

      await resolver.resolveConflict(
        localEvent: CanvasRealtimeEvent(
          type: RealtimeEventType.strokeAdded,
          senderId: 'u1',
          payload: {},
          timestamp: 100,
        ),
        remoteEvent: CanvasRealtimeEvent(
          type: RealtimeEventType.strokeAdded,
          senderId: 'u2',
          payload: {},
          timestamp: 200,
        ),
      );

      await Future.delayed(const Duration(milliseconds: 50));
      expect(detected, hasLength(1));
      expect(resolved, hasLength(1));
    });

    test('fires onUnresolved when all strategies return null', () async {
      final unresolved = <ConflictRecord>[];
      final alwaysNullResolver = ConflictResolver(
        strategies: [UserPickStrategy()],
        onUnresolved: unresolved.add,
      );

      final result = await alwaysNullResolver.resolveConflict(
        localEvent: CanvasRealtimeEvent(
          type: RealtimeEventType.strokeAdded,
          senderId: 'u1',
          payload: {},
          timestamp: 100,
        ),
        remoteEvent: CanvasRealtimeEvent(
          type: RealtimeEventType.strokeAdded,
          senderId: 'u2',
          payload: {},
          timestamp: 200,
        ),
      );

      expect(result, isNull);
      expect(unresolved, hasLength(1));
      alwaysNullResolver.dispose();
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // ELEMENT STATE TRACKER
  // ═══════════════════════════════════════════════════════════════════════════

  group('ElementStateTracker', () {
    late ElementStateTracker tracker;

    setUp(() => tracker = ElementStateTracker());

    test('marks elements as locally dirty', () {
      final event = CanvasRealtimeEvent(
        type: RealtimeEventType.imageUpdated,
        senderId: 'u1',
        elementId: 'img1',
        payload: {'x': 10},
        timestamp: 100,
      );
      tracker.markLocallyModified('img1', event);
      expect(tracker.dirtyCount, 1);
    });

    test('detects conflict on dirty element', () {
      final localEvent = CanvasRealtimeEvent(
        type: RealtimeEventType.imageUpdated,
        senderId: 'u1',
        elementId: 'img1',
        payload: {'x': 10},
        timestamp: 100,
      );
      tracker.markLocallyModified('img1', localEvent);

      final remoteEvent = CanvasRealtimeEvent(
        type: RealtimeEventType.imageUpdated,
        senderId: 'u2',
        elementId: 'img1',
        payload: {'x': 20},
        timestamp: 200,
      );
      expect(tracker.hasConflict(remoteEvent), isTrue);
    });

    test('no conflict on clean element', () {
      final event = CanvasRealtimeEvent(
        type: RealtimeEventType.imageUpdated,
        senderId: 'u2',
        elementId: 'img1',
        payload: {'x': 20},
        timestamp: 200,
      );
      expect(tracker.hasConflict(event), isFalse);
    });

    test('markRemoteApplied clears dirty flag', () {
      final event = CanvasRealtimeEvent(
        type: RealtimeEventType.imageUpdated,
        senderId: 'u1',
        elementId: 'img1',
        payload: {'x': 10},
        timestamp: 100,
      );
      tracker.markLocallyModified('img1', event);
      tracker.markRemoteApplied('img1', event);
      expect(tracker.dirtyCount, 0);
    });

    test('clear resets all state', () {
      tracker.markLocallyModified(
        'a',
        CanvasRealtimeEvent(
          type: RealtimeEventType.strokeAdded,
          senderId: 'u1',
          elementId: 'a',
          payload: {},
          timestamp: 1,
        ),
      );
      tracker.markLocallyModified(
        'b',
        CanvasRealtimeEvent(
          type: RealtimeEventType.strokeAdded,
          senderId: 'u1',
          elementId: 'b',
          payload: {},
          timestamp: 2,
        ),
      );
      expect(tracker.dirtyCount, 2);
      tracker.clear();
      expect(tracker.dirtyCount, 0);
    });
  });
}
