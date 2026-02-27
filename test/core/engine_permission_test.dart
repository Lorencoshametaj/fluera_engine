import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/rbac/engine_permission.dart';

void main() {
  // ===========================================================================
  // EnginePermission enum
  // ===========================================================================

  group('EnginePermission', () {
    test('has 11 values', () {
      expect(EnginePermission.values.length, 11);
    });
  });

  // ===========================================================================
  // Built-in roles
  // ===========================================================================

  group('EngineRole - built-in roles', () {
    test('viewer can only view', () {
      expect(EngineRole.viewer.has(EnginePermission.viewCanvas), isTrue);
      expect(EngineRole.viewer.has(EnginePermission.editContent), isFalse);
      expect(EngineRole.viewer.has(EnginePermission.addNodes), isFalse);
    });

    test('commenter can view and export', () {
      expect(EngineRole.commenter.has(EnginePermission.viewCanvas), isTrue);
      expect(EngineRole.commenter.has(EnginePermission.exportCanvas), isTrue);
      expect(EngineRole.commenter.has(EnginePermission.editContent), isFalse);
    });

    test('editor can edit but not manage roles', () {
      expect(EngineRole.editor.has(EnginePermission.editContent), isTrue);
      expect(EngineRole.editor.has(EnginePermission.addNodes), isTrue);
      expect(EngineRole.editor.has(EnginePermission.manageRoles), isFalse);
      expect(EngineRole.editor.has(EnginePermission.managePlugins), isFalse);
    });

    test('admin has plugins but not manageRoles', () {
      expect(EngineRole.admin.has(EnginePermission.managePlugins), isTrue);
      expect(EngineRole.admin.has(EnginePermission.manageRoles), isFalse);
    });

    test('owner has all permissions', () {
      for (final perm in EnginePermission.values) {
        expect(
          EngineRole.owner.has(perm),
          isTrue,
          reason: 'Owner should have ${perm.name}',
        );
      }
    });

    test('priority increases: viewer < commenter < editor < admin < owner', () {
      expect(
        EngineRole.viewer.priority,
        lessThan(EngineRole.commenter.priority),
      );
      expect(
        EngineRole.commenter.priority,
        lessThan(EngineRole.editor.priority),
      );
      expect(EngineRole.editor.priority, lessThan(EngineRole.admin.priority));
      expect(EngineRole.admin.priority, lessThan(EngineRole.owner.priority));
    });
  });

  // ===========================================================================
  // hasAll / hasAny
  // ===========================================================================

  group('EngineRole - hasAll/hasAny', () {
    test('hasAll checks all permissions', () {
      expect(
        EngineRole.editor.hasAll({
          EnginePermission.addNodes,
          EnginePermission.removeNodes,
        }),
        isTrue,
      );
      expect(
        EngineRole.viewer.hasAll({
          EnginePermission.viewCanvas,
          EnginePermission.editContent,
        }),
        isFalse,
      );
    });

    test('hasAny checks any permission', () {
      expect(
        EngineRole.viewer.hasAny({
          EnginePermission.viewCanvas,
          EnginePermission.editContent,
        }),
        isTrue,
      );
      expect(
        EngineRole.viewer.hasAny({
          EnginePermission.editContent,
          EnginePermission.addNodes,
        }),
        isFalse,
      );
    });
  });

  // ===========================================================================
  // fromId
  // ===========================================================================

  group('EngineRole - fromId', () {
    test('finds built-in roles', () {
      expect(EngineRole.fromId('viewer'), EngineRole.viewer);
      expect(EngineRole.fromId('owner'), EngineRole.owner);
    });

    test('returns null for unknown ID', () {
      expect(EngineRole.fromId('superadmin'), isNull);
    });
  });

  // ===========================================================================
  // builtInRoles
  // ===========================================================================

  group('EngineRole - builtInRoles', () {
    test('contains 5 roles', () {
      expect(EngineRole.builtInRoles.length, 5);
    });
  });

  // ===========================================================================
  // Equality & toString
  // ===========================================================================

  group('EngineRole - equality', () {
    test('same id equals', () {
      expect(EngineRole.editor, EngineRole.editor);
    });

    test('toString is readable', () {
      expect(EngineRole.editor.toString(), contains('editor'));
    });
  });
}
