import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/rbac/permission_service.dart';
import 'package:nebula_engine/src/core/rbac/engine_permission.dart';

void main() {
  late PermissionService service;

  setUp(() {
    service = PermissionService(role: EngineRole.editor);
  });

  tearDown(() {
    service.dispose();
  });

  // ===========================================================================
  // Role management
  // ===========================================================================

  group('PermissionService - roles', () {
    test('defaults to editor', () {
      expect(service.currentRole, EngineRole.editor);
    });

    test('setRole changes role', () {
      service.setRole(EngineRole.viewer);
      expect(service.currentRole, EngineRole.viewer);
    });
  });

  // ===========================================================================
  // hasPermission
  // ===========================================================================

  group('PermissionService - hasPermission', () {
    test('editor can add nodes', () {
      expect(service.hasPermission(EnginePermission.addNodes), isTrue);
    });

    test('viewer cannot add nodes', () {
      service.setRole(EngineRole.viewer);
      expect(service.hasPermission(EnginePermission.addNodes), isFalse);
    });
  });

  // ===========================================================================
  // requirePermission
  // ===========================================================================

  group('PermissionService - requirePermission', () {
    test('throws PermissionDeniedError when denied', () {
      service.setRole(EngineRole.viewer);
      expect(
        () => service.requirePermission(EnginePermission.addNodes),
        throwsA(isA<PermissionDeniedError>()),
      );
    });

    test('does not throw when permitted', () {
      expect(
        () => service.requirePermission(EnginePermission.addNodes),
        returnsNormally,
      );
    });
  });

  // ===========================================================================
  // Denial stream
  // ===========================================================================

  group('PermissionService - denials', () {
    test('emits denial event', () async {
      service.setRole(EngineRole.viewer);
      final future = service.denials.first;
      try {
        service.requirePermission(EnginePermission.addNodes);
      } catch (_) {}
      final denial = await future;
      expect(denial.permission, EnginePermission.addNodes);
    });
  });

  // ===========================================================================
  // canMutateNode
  // ===========================================================================

  group('PermissionService - canMutateNode', () {
    test('editor can mutate node', () {
      expect(service.canMutateNode('path', EnginePermission.addNodes), isTrue);
    });
  });

  // ===========================================================================
  // Lifecycle
  // ===========================================================================

  group('PermissionService - lifecycle', () {
    test('dispose marks as disposed', () {
      service.dispose();
      expect(service.isDisposed, isTrue);
    });
  });

  // ===========================================================================
  // Models
  // ===========================================================================

  group('PermissionDeniedError', () {
    test('toString is readable', () {
      final error = PermissionDeniedError(
        permission: EnginePermission.addNodes,
        role: EngineRole.viewer,
      );
      expect(error.toString(), contains('PermissionDeniedError'));
    });
  });

  group('PermissionDenial', () {
    test('toString is readable', () {
      final denial = PermissionDenial(
        permission: EnginePermission.addNodes,
        role: EngineRole.viewer,
        timestamp: DateTime.utc(2024),
      );
      expect(denial.toString(), contains('PermissionDenial'));
    });
  });
}
