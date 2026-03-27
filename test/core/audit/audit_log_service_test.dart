import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/audit/audit_log_service.dart';
import 'package:fluera_engine/src/core/audit/audit_entry.dart';

AuditEntry _entry({
  AuditAction action = AuditAction.create,
  String actor = 'user-1',
  String source = 'TestSource',
  AuditSeverity severity = AuditSeverity.info,
  String? targetId,
  DateTime? timestamp,
}) {
  return AuditEntry(
    action: action,
    actor: actor,
    source: source,
    severity: severity,
    targetId: targetId,
    timestamp: timestamp,
  );
}

void main() {
  group('AuditLogService', () {
    late AuditLogService service;

    setUp(() {
      service = AuditLogService();
    });

    tearDown(() {
      service.dispose();
    });

    group('record', () {
      test('adds entries', () {
        service.record(_entry());
        expect(service.entries.length, 1);
      });

      test('multiple entries accumulate', () {
        for (int i = 0; i < 10; i++) {
          service.record(_entry(actor: 'user-$i'));
        }
        expect(service.entries.length, 10);
      });

      test('evicts oldest when buffer full', () {
        final small = AuditLogService(config: AuditLogConfig(maxEntries: 5));
        for (int i = 0; i < 10; i++) {
          small.record(_entry(actor: 'user-$i'));
        }
        expect(small.entries.length, 5);
        // Oldest entries (user-0 .. user-4) should be evicted
        final recent = small.recentEntries(5);
        expect(recent.any((e) => e.actor == 'user-0'), isFalse);
        expect(recent.any((e) => e.actor == 'user-9'), isTrue);
        small.dispose();
      });

      test('ignored actions are filtered out', () {
        final filtered = AuditLogService(
          config: AuditLogConfig(ignoredActions: {AuditAction.custom}),
        );
        filtered.record(_entry(action: AuditAction.custom));
        expect(filtered.entries.length, 0);
        filtered.record(_entry(action: AuditAction.create));
        expect(filtered.entries.length, 1);
        filtered.dispose();
      });

      test('silently ignored after dispose', () {
        service.dispose();
        service.record(_entry());
        expect(service.entries.length, 0);
      });
    });

    group('recentEntries', () {
      test('returns newest first', () {
        for (int i = 0; i < 5; i++) {
          service.record(_entry(actor: 'user-$i'));
        }
        final recent = service.recentEntries(3);
        expect(recent.length, 3);
        // Most recent first
        expect(recent[0].actor, 'user-4');
        expect(recent[1].actor, 'user-3');
        expect(recent[2].actor, 'user-2');
      });

      test('returns all when count exceeds entries', () {
        service.record(_entry());
        final recent = service.recentEntries(100);
        expect(recent.length, 1);
      });
    });

    group('getById', () {
      test('finds existing entry', () {
        final entry = _entry();
        service.record(entry);
        final found = service.getById(entry.id);
        expect(found, isNotNull);
        expect(found!.id, entry.id);
      });

      test('returns null for missing entry', () {
        expect(service.getById('nonexistent'), isNull);
      });
    });

    group('query', () {
      setUp(() {
        service.record(
          _entry(
            action: AuditAction.create,
            actor: 'alice',
            source: 'SceneGraph',
            severity: AuditSeverity.info,
          ),
        );
        service.record(
          _entry(
            action: AuditAction.update,
            actor: 'bob',
            source: 'History',
            severity: AuditSeverity.warning,
          ),
        );
        service.record(
          _entry(
            action: AuditAction.delete,
            actor: 'alice',
            source: 'SceneGraph',
            severity: AuditSeverity.critical,
          ),
        );
        service.record(
          _entry(
            action: AuditAction.error,
            actor: 'system',
            source: 'ErrorRecovery',
            severity: AuditSeverity.critical,
          ),
        );
      });

      test('filter by action', () {
        final result = service.query(AuditQuery(actions: {AuditAction.create}));
        expect(result.length, 1);
        expect(result[0].action, AuditAction.create);
      });

      test('filter by actor', () {
        final result = service.query(AuditQuery(actor: 'alice'));
        expect(result.length, 2);
      });

      test('filter by source', () {
        final result = service.query(AuditQuery(source: 'SceneGraph'));
        expect(result.length, 2);
      });

      test('filter by min severity', () {
        final result = service.query(
          AuditQuery(minSeverity: AuditSeverity.warning),
        );
        expect(result.length, 3); // warning + 2 critical
      });

      test('combine filters (AND logic)', () {
        final result = service.query(
          AuditQuery(actor: 'alice', minSeverity: AuditSeverity.critical),
        );
        expect(result.length, 1);
        expect(result[0].action, AuditAction.delete);
      });

      test('limit results', () {
        final result = service.query(AuditQuery(limit: 2));
        expect(result.length, 2);
      });

      test('empty query returns all', () {
        final result = service.query(AuditQuery());
        expect(result.length, 4);
      });
    });

    group('applyRetention', () {
      test('purges old entries', () {
        final svc = AuditLogService(
          config: AuditLogConfig(retentionPeriod: const Duration(days: 30)),
        );
        // Add an old entry
        svc.record(
          _entry(timestamp: DateTime.now().subtract(const Duration(days: 60))),
        );
        // Add a recent entry
        svc.record(_entry());
        expect(svc.entries.length, 2);

        final purged = svc.applyRetention();
        expect(purged, 1);
        expect(svc.entries.length, 1);
        svc.dispose();
      });

      test('returns 0 when no retention configured', () {
        final purged = service.applyRetention();
        expect(purged, 0);
      });
    });

    group('clear', () {
      test('removes all entries', () {
        service.record(_entry());
        service.record(_entry());
        expect(service.entries.length, 2);
        service.clear();
        expect(service.entries.length, 0);
      });
    });

    group('stats', () {
      test('reports correct counts', () {
        service.record(_entry(action: AuditAction.create));
        service.record(_entry(action: AuditAction.error));
        service.record(_entry(action: AuditAction.error));
        final s = service.stats;
        expect(s.totalEntries, 3);
      });
    });

    group('stream', () {
      test('emits entries as they are recorded', () async {
        final entries = <AuditEntry>[];
        final sub = service.stream.listen(entries.add);

        service.record(_entry(actor: 'streamed'));
        await Future.delayed(Duration.zero); // let stream deliver

        expect(entries.length, 1);
        expect(entries[0].actor, 'streamed');
        await sub.cancel();
      });
    });
  });

  group('AuditEntry', () {
    test('auto-generates id if not provided', () {
      final e = AuditEntry(action: AuditAction.create, source: 'Test');
      expect(e.id, isNotEmpty);
    });

    test('auto-generates timestamp if not provided', () {
      final e = AuditEntry(action: AuditAction.create, source: 'Test');
      expect(e.timestamp, isNotNull);
    });

    test('toJson/fromJson roundtrip', () {
      final entry = AuditEntry(
        action: AuditAction.update,
        actor: 'user-42',
        source: 'SceneGraph',
        severity: AuditSeverity.warning,
        targetId: 'node-abc',
        targetType: 'GroupNode',
        description: 'Changed color',
      );
      final json = entry.toJson();
      final restored = AuditEntry.fromJson(json);
      expect(restored.action, AuditAction.update);
      expect(restored.actor, 'user-42');
      expect(restored.severity, AuditSeverity.warning);
      expect(restored.targetId, 'node-abc');
      expect(restored.description, 'Changed color');
    });

    test('toString is readable', () {
      final e = AuditEntry(
        action: AuditAction.create,
        actor: 'user-1',
        source: 'Test',
        targetId: 'node-abc',
      );
      expect(e.toString(), contains('create'));
      expect(e.toString(), contains('user-1'));
    });
  });

  group('AuditLogConfig', () {
    test('defaults', () {
      final config = AuditLogConfig();
      expect(config.maxEntries, greaterThan(0));
    });
  });
}
