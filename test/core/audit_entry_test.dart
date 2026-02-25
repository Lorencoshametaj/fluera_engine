import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/audit/audit_entry.dart';

void main() {
  // ===========================================================================
  // Enums
  // ===========================================================================

  group('AuditAction', () {
    test('has expected values', () {
      expect(AuditAction.values, contains(AuditAction.create));
      expect(AuditAction.values, contains(AuditAction.update));
      expect(AuditAction.values, contains(AuditAction.delete));
      expect(AuditAction.values, contains(AuditAction.undo));
      expect(AuditAction.values, contains(AuditAction.custom));
    });
  });

  group('AuditSeverity', () {
    test('has 3 levels', () {
      expect(AuditSeverity.values.length, 3);
    });
  });

  // ===========================================================================
  // Construction
  // ===========================================================================

  group('AuditEntry - construction', () {
    test('creates with required fields', () {
      final entry = AuditEntry(
        action: AuditAction.create,
        source: 'SceneGraph',
      );
      expect(entry.action, AuditAction.create);
      expect(entry.source, 'SceneGraph');
      expect(entry.actor, 'system');
      expect(entry.severity, AuditSeverity.info);
    });

    test('auto-generates ID', () {
      final entry = AuditEntry(action: AuditAction.update, source: 'History');
      expect(entry.id, isNotEmpty);
    });

    test('auto-generates timestamp', () {
      final entry = AuditEntry(action: AuditAction.delete, source: 'Test');
      expect(entry.timestamp, isNotNull);
    });

    test('stores target info', () {
      final entry = AuditEntry(
        action: AuditAction.update,
        source: 'SceneGraph',
        targetId: 'node-123',
        targetType: 'GroupNode',
      );
      expect(entry.targetId, 'node-123');
      expect(entry.targetType, 'GroupNode');
    });

    test('stores diff snapshots', () {
      final entry = AuditEntry(
        action: AuditAction.update,
        source: 'Properties',
        before: {'opacity': 1.0},
        after: {'opacity': 0.5},
      );
      expect(entry.before!['opacity'], 1.0);
      expect(entry.after!['opacity'], 0.5);
    });
  });

  // ===========================================================================
  // Serialization
  // ===========================================================================

  group('AuditEntry - toJson/fromJson', () {
    test('round-trips', () {
      final entry = AuditEntry(
        action: AuditAction.create,
        actor: 'user-42',
        source: 'SceneGraph',
        targetId: 'node-abc',
        targetType: 'GroupNode',
        description: 'Created a group',
      );
      final json = entry.toJson();
      final restored = AuditEntry.fromJson(json);
      expect(restored.action, AuditAction.create);
      expect(restored.actor, 'user-42');
      expect(restored.targetId, 'node-abc');
      expect(restored.description, 'Created a group');
    });

    test('fromJson with unknown action falls back to custom', () {
      final json = {
        'id': 'test-id',
        'timestamp': DateTime.utc(2024).toIso8601String(),
        'action': 'nonexistent',
        'severity': 'info',
        'source': 'Test',
      };
      final entry = AuditEntry.fromJson(json);
      expect(entry.action, AuditAction.custom);
    });
  });

  // ===========================================================================
  // toString
  // ===========================================================================

  group('AuditEntry - toString', () {
    test('is readable', () {
      final entry = AuditEntry(
        action: AuditAction.create,
        source: 'SceneGraph',
        actor: 'user-1',
      );
      expect(entry.toString(), contains('create'));
      expect(entry.toString(), contains('user-1'));
    });
  });
}
