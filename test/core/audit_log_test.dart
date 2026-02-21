import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/audit/audit_entry.dart';
import 'package:nebula_engine/src/core/audit/audit_event_bridge.dart';
import 'package:nebula_engine/src/core/audit/audit_exporter.dart';
import 'package:nebula_engine/src/core/audit/audit_log_service.dart';
import 'package:nebula_engine/src/core/engine_error.dart';
import 'package:nebula_engine/src/core/engine_event.dart';
import 'package:nebula_engine/src/core/engine_event_bus.dart';
import 'package:nebula_engine/src/core/engine_scope.dart';
import 'package:nebula_engine/src/core/scene_graph/node_id.dart';

import '../helpers/test_helpers.dart';

void main() {
  // ===========================================================================
  // AUDIT ENTRY
  // ===========================================================================

  group('AuditEntry', () {
    test('creates with defaults', () {
      final entry = AuditEntry(action: AuditAction.create, source: 'Test');

      expect(entry.id, isNotEmpty);
      expect(entry.timestamp.isUtc, isTrue);
      expect(entry.action, AuditAction.create);
      expect(entry.severity, AuditSeverity.info);
      expect(entry.actor, 'system');
      expect(entry.source, 'Test');
      expect(entry.targetId, isNull);
      expect(entry.targetType, isNull);
      expect(entry.before, isNull);
      expect(entry.after, isNull);
      expect(entry.metadata, isNull);
      expect(entry.description, isNull);
    });

    test('creates with all fields', () {
      final ts = DateTime.utc(2025, 1, 1);
      final entry = AuditEntry(
        id: 'custom-id',
        timestamp: ts,
        action: AuditAction.delete,
        severity: AuditSeverity.critical,
        actor: 'user-42',
        source: 'SceneGraph',
        targetId: 'node-abc',
        targetType: 'GroupNode',
        before: {'name': 'old'},
        after: {'name': 'new'},
        metadata: {'reason': 'test'},
        description: 'Deleted node',
      );

      expect(entry.id, 'custom-id');
      expect(entry.timestamp, ts);
      expect(entry.action, AuditAction.delete);
      expect(entry.severity, AuditSeverity.critical);
      expect(entry.actor, 'user-42');
      expect(entry.targetId, 'node-abc');
      expect(entry.targetType, 'GroupNode');
      expect(entry.before, {'name': 'old'});
      expect(entry.after, {'name': 'new'});
      expect(entry.metadata, {'reason': 'test'});
      expect(entry.description, 'Deleted node');
    });

    test('generates unique IDs', () {
      final ids =
          List.generate(100, (_) {
            return AuditEntry(action: AuditAction.create, source: 'Test').id;
          }).toSet();

      expect(ids.length, 100, reason: 'All IDs should be unique');
    });

    test('toJson serializes all fields', () {
      final entry = AuditEntry(
        id: 'test-id',
        timestamp: DateTime.utc(2025, 6, 15, 10, 30),
        action: AuditAction.update,
        severity: AuditSeverity.warning,
        actor: 'admin',
        source: 'History',
        targetId: 'var-1',
        targetType: 'DesignVariable',
        before: {'v': 1},
        after: {'v': 2},
        metadata: {'mode': 'dark'},
        description: 'Updated variable',
      );

      final json = entry.toJson();

      expect(json['id'], 'test-id');
      expect(json['timestamp'], '2025-06-15T10:30:00.000Z');
      expect(json['action'], 'update');
      expect(json['severity'], 'warning');
      expect(json['actor'], 'admin');
      expect(json['source'], 'History');
      expect(json['targetId'], 'var-1');
      expect(json['targetType'], 'DesignVariable');
      expect(json['before'], {'v': 1});
      expect(json['after'], {'v': 2});
      expect(json['metadata'], {'mode': 'dark'});
      expect(json['description'], 'Updated variable');
    });

    test('toJson omits null fields', () {
      final entry = AuditEntry(action: AuditAction.create, source: 'Test');
      final json = entry.toJson();

      expect(json.containsKey('targetId'), isFalse);
      expect(json.containsKey('targetType'), isFalse);
      expect(json.containsKey('before'), isFalse);
      expect(json.containsKey('after'), isFalse);
      expect(json.containsKey('metadata'), isFalse);
      expect(json.containsKey('description'), isFalse);
    });

    test('fromJson round-trips correctly', () {
      final original = AuditEntry(
        id: 'rt-1',
        timestamp: DateTime.utc(2025, 3, 1),
        action: AuditAction.pluginEvent,
        severity: AuditSeverity.critical,
        actor: 'plugin-x',
        source: 'Plugin',
        targetId: 'target-1',
        targetType: 'Custom',
        before: {'a': 1},
        after: {'b': 2},
        metadata: {'c': 3},
        description: 'Test desc',
      );

      final json = original.toJson();
      final restored = AuditEntry.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.timestamp, original.timestamp);
      expect(restored.action, original.action);
      expect(restored.severity, original.severity);
      expect(restored.actor, original.actor);
      expect(restored.source, original.source);
      expect(restored.targetId, original.targetId);
      expect(restored.targetType, original.targetType);
      expect(restored.before, original.before);
      expect(restored.after, original.after);
      expect(restored.metadata, original.metadata);
      expect(restored.description, original.description);
    });

    test('fromJson handles unknown action gracefully', () {
      final json = {
        'id': 'x',
        'timestamp': DateTime.utc(2025).toIso8601String(),
        'action': 'nonexistent_action',
        'severity': 'info',
        'source': 'Test',
      };

      final entry = AuditEntry.fromJson(json);
      expect(entry.action, AuditAction.custom);
    });

    test('toString is readable', () {
      final entry = AuditEntry(
        action: AuditAction.create,
        actor: 'user-1',
        source: 'SceneGraph',
        targetId: 'node-1',
      );

      final str = entry.toString();
      expect(str, contains('create'));
      expect(str, contains('user-1'));
      expect(str, contains('SceneGraph'));
      expect(str, contains('node-1'));
    });
  });

  // ===========================================================================
  // AUDIT LOG SERVICE
  // ===========================================================================

  group('AuditLogService', () {
    late AuditLogService service;

    setUp(() {
      service = AuditLogService();
    });

    tearDown(() {
      service.dispose();
    });

    AuditEntry _entry({
      AuditAction action = AuditAction.create,
      String actor = 'system',
      String source = 'Test',
      String? targetId,
      AuditSeverity severity = AuditSeverity.info,
      DateTime? timestamp,
    }) => AuditEntry(
      action: action,
      actor: actor,
      source: source,
      targetId: targetId,
      severity: severity,
      timestamp: timestamp,
    );

    test('record appends entry', () {
      service.record(_entry());
      expect(service.stats.totalEntries, 1);
    });

    test('record ignores entry after dispose', () {
      service.dispose();
      service.record(_entry());
      expect(service.isDisposed, isTrue);
    });

    test('record respects ignoredActions', () {
      final svc = AuditLogService(
        config: AuditLogConfig(ignoredActions: {AuditAction.create}),
      );

      svc.record(_entry(action: AuditAction.create));
      svc.record(_entry(action: AuditAction.delete));

      expect(svc.stats.totalEntries, 1);
      expect(svc.entries.first.action, AuditAction.delete);
      svc.dispose();
    });

    test('record strips before/after when disabled', () {
      final svc = AuditLogService(
        config: AuditLogConfig(enableBeforeAfter: false),
      );

      svc.record(
        AuditEntry(
          action: AuditAction.update,
          source: 'Test',
          before: {'v': 1},
          after: {'v': 2},
        ),
      );

      expect(svc.entries.first.before, isNull);
      expect(svc.entries.first.after, isNull);
      svc.dispose();
    });

    test('ring buffer evicts oldest when at capacity', () {
      final svc = AuditLogService(config: AuditLogConfig(maxEntries: 3));

      svc.record(_entry(source: 'A'));
      svc.record(_entry(source: 'B'));
      svc.record(_entry(source: 'C'));
      svc.record(_entry(source: 'D'));

      expect(svc.stats.totalEntries, 3);
      expect(svc.entries.first.source, 'B');
      expect(svc.entries.last.source, 'D');
      svc.dispose();
    });

    test('getById returns entry', () {
      final entry = _entry();
      service.record(entry);
      expect(service.getById(entry.id), isNotNull);
      expect(service.getById(entry.id)!.id, entry.id);
    });

    test('getById returns null for evicted entry', () {
      final svc = AuditLogService(config: AuditLogConfig(maxEntries: 1));

      final first = _entry(source: 'First');
      svc.record(first);
      svc.record(_entry(source: 'Second'));

      expect(svc.getById(first.id), isNull);
      svc.dispose();
    });

    test('recentEntries returns newest first', () {
      service.record(_entry(source: 'A'));
      service.record(_entry(source: 'B'));
      service.record(_entry(source: 'C'));

      final recent = service.recentEntries(2);
      expect(recent.length, 2);
      expect(recent[0].source, 'C');
      expect(recent[1].source, 'B');
    });

    // --- Query ---

    test('query returns all when no filters', () {
      service.record(_entry(source: 'A'));
      service.record(_entry(source: 'B'));

      final results = service.query(AuditQuery());
      expect(results.length, 2);
    });

    test('query filters by action', () {
      service.record(_entry(action: AuditAction.create));
      service.record(_entry(action: AuditAction.delete));
      service.record(_entry(action: AuditAction.create));

      final results = service.query(AuditQuery(actions: {AuditAction.create}));
      expect(results.length, 2);
      expect(results.every((e) => e.action == AuditAction.create), isTrue);
    });

    test('query filters by actor', () {
      service.record(_entry(actor: 'user-1'));
      service.record(_entry(actor: 'user-2'));
      service.record(_entry(actor: 'user-1'));

      final results = service.query(AuditQuery(actor: 'user-1'));
      expect(results.length, 2);
    });

    test('query filters by source', () {
      service.record(_entry(source: 'SceneGraph'));
      service.record(_entry(source: 'History'));

      final results = service.query(AuditQuery(source: 'SceneGraph'));
      expect(results.length, 1);
    });

    test('query filters by targetId', () {
      service.record(_entry(targetId: 'node-1'));
      service.record(_entry(targetId: 'node-2'));

      final results = service.query(AuditQuery(targetId: 'node-1'));
      expect(results.length, 1);
    });

    test('query filters by minSeverity', () {
      service.record(_entry(severity: AuditSeverity.info));
      service.record(_entry(severity: AuditSeverity.warning));
      service.record(_entry(severity: AuditSeverity.critical));

      final results = service.query(
        AuditQuery(minSeverity: AuditSeverity.warning),
      );
      expect(results.length, 2);
    });

    test('query filters by timeRange', () {
      final t1 = DateTime.utc(2025, 1, 1);
      final t2 = DateTime.utc(2025, 6, 1);
      final t3 = DateTime.utc(2025, 12, 1);

      service.record(_entry(timestamp: t1));
      service.record(_entry(timestamp: t2));
      service.record(_entry(timestamp: t3));

      final results = service.query(
        AuditQuery(
          timeRange: (
            start: DateTime.utc(2025, 4, 1),
            end: DateTime.utc(2025, 8, 1),
          ),
        ),
      );
      expect(results.length, 1);
      expect(results.first.timestamp, t2);
    });

    test('query respects limit and offset', () {
      for (int i = 0; i < 10; i++) {
        service.record(_entry(source: 'S$i'));
      }

      final page1 = service.query(AuditQuery(limit: 3, offset: 0));
      expect(page1.length, 3);
      expect(page1[0].source, 'S0');

      final page2 = service.query(AuditQuery(limit: 3, offset: 3));
      expect(page2.length, 3);
      expect(page2[0].source, 'S3');
    });

    test('query composes multiple filters (AND)', () {
      service.record(
        _entry(
          action: AuditAction.create,
          actor: 'user-1',
          source: 'SceneGraph',
        ),
      );
      service.record(
        _entry(
          action: AuditAction.create,
          actor: 'user-2',
          source: 'SceneGraph',
        ),
      );
      service.record(
        _entry(
          action: AuditAction.delete,
          actor: 'user-1',
          source: 'SceneGraph',
        ),
      );

      final results = service.query(
        AuditQuery(actions: {AuditAction.create}, actor: 'user-1'),
      );
      expect(results.length, 1);
    });

    // --- Retention ---

    test('applyRetention purges old entries', () {
      final old = DateTime.utc(2020, 1, 1);
      final recent = DateTime.now().toUtc();

      service.record(_entry(timestamp: old));
      service.record(_entry(timestamp: recent));

      final purged = service.applyRetention();
      expect(purged, 1);
      expect(service.stats.totalEntries, 1);
    });

    test('applyRetention returns 0 when no retention period', () {
      final svc = AuditLogService(
        config: AuditLogConfig(retentionPeriod: null),
      );
      svc.record(_entry());

      expect(svc.applyRetention(), 0);
      svc.dispose();
    });

    // --- Stream ---

    test('stream emits recorded entries', () async {
      final entries = <AuditEntry>[];
      final sub = service.stream.listen(entries.add);

      service.record(_entry(source: 'A'));
      service.record(_entry(source: 'B'));

      // Allow microtask to flush
      await Future.delayed(Duration.zero);

      expect(entries.length, 2);
      expect(entries[0].source, 'A');
      expect(entries[1].source, 'B');

      await sub.cancel();
    });

    // --- Stats ---

    test('stats provides correct breakdown', () {
      service.record(
        _entry(action: AuditAction.create, severity: AuditSeverity.info),
      );
      service.record(
        _entry(action: AuditAction.create, severity: AuditSeverity.info),
      );
      service.record(
        _entry(action: AuditAction.error, severity: AuditSeverity.critical),
      );

      final stats = service.stats;
      expect(stats.totalEntries, 3);
      expect(stats.actionCounts[AuditAction.create], 2);
      expect(stats.actionCounts[AuditAction.error], 1);
      expect(stats.severityCounts[AuditSeverity.info], 2);
      expect(stats.severityCounts[AuditSeverity.critical], 1);
      expect(stats.oldestTimestamp, isNotNull);
      expect(stats.newestTimestamp, isNotNull);
    });

    test('stats empty log', () {
      final stats = service.stats;
      expect(stats.totalEntries, 0);
      expect(stats.oldestTimestamp, isNull);
      expect(stats.newestTimestamp, isNull);
    });

    // --- Lifecycle ---

    test('clear removes all entries', () {
      service.record(_entry());
      service.record(_entry());
      service.clear();
      expect(service.stats.totalEntries, 0);
    });

    test('totalRecorded tracks including evicted', () {
      final svc = AuditLogService(config: AuditLogConfig(maxEntries: 2));

      svc.record(_entry());
      svc.record(_entry());
      svc.record(_entry());

      expect(svc.totalRecorded, 3);
      expect(svc.stats.totalEntries, 2);
      svc.dispose();
    });
  });

  // ===========================================================================
  // AUDIT EVENT BRIDGE
  // ===========================================================================

  group('AuditEventBridge', () {
    late EngineEventBus eventBus;
    late AuditLogService auditLog;
    late AuditEventBridge bridge;

    setUp(() {
      eventBus = EngineEventBus();
      auditLog = AuditLogService();
      bridge = AuditEventBridge(
        eventBus: eventBus,
        auditLog: auditLog,
        actor: 'test-user',
      );
    });

    tearDown(() {
      bridge.dispose();
      auditLog.dispose();
      eventBus.dispose();
    });

    test('start subscribes to event bus', () {
      expect(bridge.isActive, isFalse);
      bridge.start();
      expect(bridge.isActive, isTrue);
    });

    test('stop unsubscribes', () {
      bridge.start();
      bridge.stop();
      expect(bridge.isActive, isFalse);
    });

    test('start is idempotent', () {
      bridge.start();
      bridge.start();
      expect(bridge.isActive, isTrue);
    });

    test('maps NodeAddedEngineEvent to create', () async {
      bridge.start();
      final node = testShapeNode(id: 'node-1');
      eventBus.emit(NodeAddedEngineEvent(node: node, parentId: 'root'));

      await Future.delayed(Duration.zero);

      expect(auditLog.stats.totalEntries, 1);
      final entry = auditLog.entries.first;
      expect(entry.action, AuditAction.create);
      expect(entry.targetId, 'node-1');
      expect(entry.actor, 'test-user');
      expect(entry.metadata?['parentId'], 'root');
    });

    test('maps NodeRemovedEngineEvent to delete', () async {
      bridge.start();
      final node = testShapeNode(id: 'node-2');
      eventBus.emit(NodeRemovedEngineEvent(node: node, parentId: 'root'));

      await Future.delayed(Duration.zero);

      final entry = auditLog.entries.first;
      expect(entry.action, AuditAction.delete);
      expect(entry.targetId, 'node-2');
    });

    test('maps NodePropertyChangedEngineEvent to update', () async {
      bridge.start();
      final node = testShapeNode(id: 'node-3');
      eventBus.emit(
        NodePropertyChangedEngineEvent(node: node, property: 'opacity'),
      );

      await Future.delayed(Duration.zero);

      final entry = auditLog.entries.first;
      expect(entry.action, AuditAction.update);
      expect(entry.targetId, 'node-3');
      expect(entry.metadata?['property'], 'opacity');
    });

    test('maps NodeReorderedEngineEvent to reorder', () async {
      bridge.start();
      eventBus.emit(
        NodeReorderedEngineEvent(parentId: 'group-1', oldIndex: 0, newIndex: 2),
      );

      await Future.delayed(Duration.zero);

      final entry = auditLog.entries.first;
      expect(entry.action, AuditAction.reorder);
      expect(entry.targetId, 'group-1');
      expect(entry.metadata?['oldIndex'], 0);
      expect(entry.metadata?['newIndex'], 2);
    });

    test('maps VariableChangedEngineEvent to update', () async {
      bridge.start();
      eventBus.emit(
        VariableChangedEngineEvent(
          variableId: 'color-primary',
          property: 'value',
          oldValue: '#fff',
          newValue: '#000',
        ),
      );

      await Future.delayed(Duration.zero);

      final entry = auditLog.entries.first;
      expect(entry.action, AuditAction.update);
      expect(entry.targetId, 'color-primary');
      expect(entry.targetType, 'DesignVariable');
      expect(entry.before, {'value': '#fff'});
      expect(entry.after, {'value': '#000'});
    });

    test(
      'maps ErrorReportedEngineEvent to error with critical severity',
      () async {
        bridge.start();
        eventBus.emit(
          ErrorReportedEngineEvent(
            error: EngineError(
              severity: ErrorSeverity.fatal,
              domain: ErrorDomain.storage,
              source: 'DiskManager',
              original: Exception('disk full'),
            ),
          ),
        );

        await Future.delayed(Duration.zero);

        final entry = auditLog.entries.first;
        expect(entry.action, AuditAction.error);
        expect(entry.severity, AuditSeverity.critical);
        expect(entry.metadata?['errorDomain'], 'storage');
      },
    );

    test('maps CustomPluginEngineEvent to pluginEvent', () async {
      bridge.start();
      eventBus.emit(
        CustomPluginEngineEvent(
          pluginId: 'my-plugin',
          name: 'activated',
          data: {'version': '1.0'},
        ),
      );

      await Future.delayed(Duration.zero);

      final entry = auditLog.entries.first;
      expect(entry.action, AuditAction.pluginEvent);
      expect(entry.actor, 'my-plugin');
      expect(entry.metadata?['version'], '1.0');
    });

    test('maps MemoryPressureEngineEvent to custom warning', () async {
      bridge.start();
      eventBus.emit(
        MemoryPressureEngineEvent(
          level: 'critical',
          totalEstimatedMB: 512.0,
          budgetCapMB: 256,
        ),
      );

      await Future.delayed(Duration.zero);

      final entry = auditLog.entries.first;
      expect(entry.action, AuditAction.custom);
      expect(entry.severity, AuditSeverity.warning);
      expect(entry.metadata?['level'], 'critical');
    });

    test('maps CommandUndoneEngineEvent to undo', () async {
      bridge.start();
      eventBus.emit(
        CommandUndoneEngineEvent(
          commandLabel: 'Move Node',
          commandType: 'MoveCommand',
        ),
      );

      await Future.delayed(Duration.zero);

      final entry = auditLog.entries.first;
      expect(entry.action, AuditAction.undo);
      expect(entry.description, contains('Move Node'));
    });

    test('filters out SelectionChangedEngineEvent', () async {
      bridge.start();
      eventBus.emit(
        SelectionChangedEngineEvent(
          changeType: 'selected',
          affectedIds: ['a'],
          totalSelected: 1,
        ),
      );

      await Future.delayed(Duration.zero);

      expect(auditLog.stats.totalEntries, 0);
    });

    test('filters out BatchCompleteEngineEvent', () async {
      bridge.start();
      eventBus.emit(
        BatchCompleteEngineEvent(
          suppressedCount: 5,
          pauseDuration: Duration(milliseconds: 100),
        ),
      );

      await Future.delayed(Duration.zero);

      expect(auditLog.stats.totalEntries, 0);
    });

    test('does not record after stop', () async {
      bridge.start();
      bridge.stop();

      eventBus.emit(
        NodeAddedEngineEvent(node: testShapeNode(id: 'x'), parentId: 'root'),
      );

      await Future.delayed(Duration.zero);

      expect(auditLog.stats.totalEntries, 0);
    });
  });

  // ===========================================================================
  // AUDIT EXPORTER
  // ===========================================================================

  group('AuditExporter', () {
    late List<AuditEntry> entries;

    setUp(() {
      entries = [
        AuditEntry(
          id: 'e1',
          timestamp: DateTime.utc(2025, 1, 1, 10, 0),
          action: AuditAction.create,
          actor: 'user-1',
          source: 'SceneGraph',
          targetId: 'node-1',
          description: 'Created node',
        ),
        AuditEntry(
          id: 'e2',
          timestamp: DateTime.utc(2025, 1, 1, 11, 0),
          action: AuditAction.error,
          severity: AuditSeverity.critical,
          actor: 'system',
          source: 'ErrorRecovery',
          description: 'Disk error',
        ),
      ];
    });

    test('exports valid JSON', () {
      final output = AuditExporter.export(entries);
      final parsed = jsonDecode(output) as List;

      expect(parsed.length, 2);
      expect(parsed[0]['id'], 'e1');
      expect(parsed[1]['id'], 'e2');
    });

    test('exports valid CSV with header', () {
      final output = AuditExporter.export(
        entries,
        format: AuditExportFormat.csv,
      );

      final lines = output.trim().split('\n');
      expect(lines.length, 3); // header + 2 rows
      expect(lines[0], contains('id,timestamp,action'));
      expect(lines[1], contains('e1'));
      expect(lines[2], contains('e2'));
    });

    test('CSV escapes commas and quotes', () {
      final tricky = [
        AuditEntry(
          id: 'tricky',
          action: AuditAction.custom,
          source: 'Test',
          description: 'Has "quotes" and, commas',
        ),
      ];

      final output = AuditExporter.export(
        tricky,
        format: AuditExportFormat.csv,
      );

      // The description field should be wrapped in double quotes
      expect(output, contains('"Has ""quotes"" and, commas"'));
    });

    test('exports valid JSONL', () {
      final output = AuditExporter.export(
        entries,
        format: AuditExportFormat.jsonLines,
      );

      final lines = output.trim().split('\n');
      expect(lines.length, 2);

      // Each line should be valid JSON
      for (final line in lines) {
        expect(() => jsonDecode(line), returnsNormally);
      }
    });

    test('generateComplianceReport has correct structure', () {
      final report = AuditExporter.generateComplianceReport(
        entries,
        documentId: 'doc-001',
        generatedBy: 'admin@co.com',
      );

      // Report metadata
      expect(report['report']['documentId'], 'doc-001');
      expect(report['report']['generatedBy'], 'admin@co.com');
      expect(report['report']['version'], '1.0.0');
      expect(report['report']['format'], 'nebula-audit-report');

      // Summary
      final summary = report['summary'] as Map<String, dynamic>;
      expect(summary['totalEntries'], 2);
      expect(summary['actors'], contains('user-1'));
      expect(summary['actors'], contains('system'));
      expect((summary['actionBreakdown'] as Map)['create'], 1);
      expect((summary['actionBreakdown'] as Map)['error'], 1);
      expect((summary['severityBreakdown'] as Map)['info'], 1);
      expect((summary['severityBreakdown'] as Map)['critical'], 1);

      // Time range
      final timeRange = summary['timeRange'] as Map<String, dynamic>;
      expect(timeRange['start'], isNotNull);
      expect(timeRange['end'], isNotNull);

      // Entries
      expect((report['entries'] as List).length, 2);
    });

    test('generateComplianceReport with empty entries', () {
      final report = AuditExporter.generateComplianceReport(
        [],
        documentId: 'doc-empty',
        generatedBy: 'admin',
      );

      expect(report['summary']['totalEntries'], 0);
      expect((report['entries'] as List).isEmpty, isTrue);
    });
  });

  // ===========================================================================
  // ENGINE SCOPE INTEGRATION
  // ===========================================================================

  group('EngineScope integration', () {
    tearDown(() {
      EngineScope.reset();
    });

    test('auditLog is accessible', () {
      expect(EngineScope.current.auditLog, isNotNull);
    });

    test('auditBridge is accessible and active', () {
      expect(EngineScope.current.auditBridge, isNotNull);
      expect(EngineScope.current.auditBridge.isActive, isTrue);
    });

    test('health check includes AuditLog', () {
      final report = EngineScope.current.healthCheck();
      final auditHealth = report.services.where((s) => s.name == 'AuditLog');
      expect(auditHealth, isNotEmpty);
      expect(auditHealth.first.healthy, isTrue);
    });

    test('scope disposal disposes audit services', () {
      final scope = EngineScope();
      // Touch services to trigger lazy init
      scope.auditLog;
      scope.auditBridge;
      scope.dispose();

      expect(scope.auditLog.isDisposed, isTrue);
      expect(scope.auditBridge.isActive, isFalse);
    });

    test('different scopes have independent audit logs', () {
      final scope1 = EngineScope();
      final scope2 = EngineScope();

      expect(identical(scope1.auditLog, scope2.auditLog), isFalse);
      scope1.dispose();
      scope2.dispose();
    });
  });
}
