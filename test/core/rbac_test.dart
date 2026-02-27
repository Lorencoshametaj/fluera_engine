import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/rbac/engine_permission.dart';
import 'package:fluera_engine/src/core/rbac/permission_interceptor.dart';
import 'package:fluera_engine/src/core/rbac/permission_policy.dart';
import 'package:fluera_engine/src/core/rbac/permission_service.dart';
import 'package:fluera_engine/src/core/scene_graph/scene_graph_interceptor.dart';
import 'package:fluera_engine/src/core/engine_scope.dart';

import '../helpers/test_helpers.dart';

void main() {
  // ===========================================================================
  // ENGINE ROLE
  // ===========================================================================

  group('EngineRole', () {
    test('viewer has only viewCanvas', () {
      expect(EngineRole.viewer.has(EnginePermission.viewCanvas), isTrue);
      expect(EngineRole.viewer.has(EnginePermission.editContent), isFalse);
      expect(EngineRole.viewer.has(EnginePermission.addNodes), isFalse);
    });

    test('commenter has viewCanvas and exportCanvas', () {
      expect(EngineRole.commenter.has(EnginePermission.viewCanvas), isTrue);
      expect(EngineRole.commenter.has(EnginePermission.exportCanvas), isTrue);
      expect(EngineRole.commenter.has(EnginePermission.editContent), isFalse);
    });

    test('editor has full content editing but no admin', () {
      expect(EngineRole.editor.has(EnginePermission.editContent), isTrue);
      expect(EngineRole.editor.has(EnginePermission.addNodes), isTrue);
      expect(EngineRole.editor.has(EnginePermission.removeNodes), isTrue);
      expect(EngineRole.editor.has(EnginePermission.reorderNodes), isTrue);
      expect(EngineRole.editor.has(EnginePermission.manageVariables), isTrue);
      expect(EngineRole.editor.has(EnginePermission.exportCanvas), isTrue);
      expect(EngineRole.editor.has(EnginePermission.managePlugins), isFalse);
      expect(EngineRole.editor.has(EnginePermission.manageRoles), isFalse);
    });

    test('admin has everything except manageRoles', () {
      expect(EngineRole.admin.has(EnginePermission.managePlugins), isTrue);
      expect(EngineRole.admin.has(EnginePermission.configureEngine), isTrue);
      expect(EngineRole.admin.has(EnginePermission.manageRoles), isFalse);
    });

    test('owner has all permissions', () {
      for (final perm in EnginePermission.values) {
        expect(
          EngineRole.owner.has(perm),
          isTrue,
          reason: '${perm.name} should be granted to owner',
        );
      }
    });

    test('priorities are ordered correctly', () {
      final roles = EngineRole.builtInRoles;
      for (int i = 1; i < roles.length; i++) {
        expect(roles[i].priority, greaterThan(roles[i - 1].priority));
      }
    });

    test('hasAll checks all permissions', () {
      expect(
        EngineRole.editor.hasAll({
          EnginePermission.editContent,
          EnginePermission.addNodes,
        }),
        isTrue,
      );
      expect(
        EngineRole.editor.hasAll({
          EnginePermission.editContent,
          EnginePermission.manageRoles,
        }),
        isFalse,
      );
    });

    test('hasAny checks any permission', () {
      expect(
        EngineRole.viewer.hasAny({
          EnginePermission.viewCanvas,
          EnginePermission.manageRoles,
        }),
        isTrue,
      );
      expect(
        EngineRole.viewer.hasAny({
          EnginePermission.editContent,
          EnginePermission.manageRoles,
        }),
        isFalse,
      );
    });

    test('fromId finds built-in roles', () {
      expect(EngineRole.fromId('viewer'), EngineRole.viewer);
      expect(EngineRole.fromId('owner'), EngineRole.owner);
      expect(EngineRole.fromId('nonexistent'), isNull);
    });

    test('custom role creation', () {
      final custom = EngineRole(
        id: 'custom',
        name: 'Custom',
        permissions: {
          EnginePermission.viewCanvas,
          EnginePermission.exportCanvas,
        },
        priority: 15,
      );
      expect(custom.has(EnginePermission.viewCanvas), isTrue);
      expect(custom.has(EnginePermission.editContent), isFalse);
      expect(custom.priority, 15);
    });

    test('equality is by id', () {
      final a = EngineRole(
        id: 'test',
        name: 'Test A',
        permissions: {EnginePermission.viewCanvas},
      );
      final b = EngineRole(
        id: 'test',
        name: 'Test B',
        permissions: {EnginePermission.editContent},
      );
      expect(a, equals(b));
    });
  });

  // ===========================================================================
  // ATTRIBUTE CONDITION
  // ===========================================================================

  group('AttributeCondition', () {
    test('evaluates simple match', () {
      final cond = AttributeCondition('node.type', 'ShapeNode');
      expect(cond.evaluate({'node.type': 'ShapeNode'}), isTrue);
      expect(cond.evaluate({'node.type': 'TextNode'}), isFalse);
    });

    test('returns false for missing attribute', () {
      final cond = AttributeCondition('node.type', 'ShapeNode');
      expect(cond.evaluate({}), isFalse);
    });

    test('evaluates Set membership', () {
      final cond = AttributeCondition('actor.role', {'viewer', 'commenter'});
      expect(cond.evaluate({'actor.role': 'viewer'}), isTrue);
      expect(cond.evaluate({'actor.role': 'editor'}), isFalse);
    });

    test('evaluates boolean match', () {
      final cond = AttributeCondition('node.isLocked', true);
      expect(cond.evaluate({'node.isLocked': true}), isTrue);
      expect(cond.evaluate({'node.isLocked': false}), isFalse);
    });
  });

  // ===========================================================================
  // PERMISSION POLICY
  // ===========================================================================

  group('PermissionPolicy', () {
    test('empty policy returns null for all', () {
      final policy = PermissionPolicy.standard();
      expect(policy.evaluate(EnginePermission.editContent, {}), isNull);
    });

    test('readOnly policy denies all writes', () {
      final policy = PermissionPolicy.readOnly();
      expect(policy.evaluate(EnginePermission.editContent, {}), isFalse);
      expect(policy.evaluate(EnginePermission.addNodes, {}), isFalse);
      expect(policy.evaluate(EnginePermission.removeNodes, {}), isFalse);
      expect(policy.evaluate(EnginePermission.manageRoles, {}), isFalse);
      // viewCanvas and exportCanvas should not be blocked
      expect(policy.evaluate(EnginePermission.viewCanvas, {}), isNull);
      expect(policy.evaluate(EnginePermission.exportCanvas, {}), isNull);
    });

    test('conditional rule matches attributes', () {
      final policy = PermissionPolicy(
        rules: [
          PermissionRule(
            permission: EnginePermission.removeNodes,
            allow: false,
            conditions: [AttributeCondition('node.type', 'PdfPageNode')],
            priority: 100,
          ),
        ],
      );

      expect(
        policy.evaluate(EnginePermission.removeNodes, {
          'node.type': 'PdfPageNode',
        }),
        isFalse,
      );
      expect(
        policy.evaluate(EnginePermission.removeNodes, {
          'node.type': 'ShapeNode',
        }),
        isNull, // No match — falls through
      );
    });

    test('higher priority rule wins', () {
      final policy = PermissionPolicy(
        rules: [
          PermissionRule(
            permission: EnginePermission.editContent,
            allow: true,
            priority: 10,
          ),
          PermissionRule(
            permission: EnginePermission.editContent,
            allow: false,
            priority: 100,
          ),
        ],
      );

      // Higher priority (100) is evaluated first → deny
      expect(policy.evaluate(EnginePermission.editContent, {}), isFalse);
    });

    test('multiple conditions are ANDed', () {
      final policy = PermissionPolicy(
        rules: [
          PermissionRule(
            permission: EnginePermission.editContent,
            allow: false,
            conditions: [
              AttributeCondition('node.type', 'PdfPageNode'),
              AttributeCondition('actor.role', 'viewer'),
            ],
          ),
        ],
      );

      // Both match → rule applies
      expect(
        policy.evaluate(EnginePermission.editContent, {
          'node.type': 'PdfPageNode',
          'actor.role': 'viewer',
        }),
        isFalse,
      );

      // Only one matches → rule doesn't apply
      expect(
        policy.evaluate(EnginePermission.editContent, {
          'node.type': 'PdfPageNode',
          'actor.role': 'editor',
        }),
        isNull,
      );
    });
  });

  // ===========================================================================
  // PERMISSION SERVICE
  // ===========================================================================

  group('PermissionService', () {
    late PermissionService service;

    setUp(() {
      service = PermissionService(role: EngineRole.editor);
    });

    tearDown(() {
      service.dispose();
    });

    test('defaults to editor role', () {
      final svc = PermissionService();
      expect(svc.currentRole, EngineRole.editor);
      svc.dispose();
    });

    test('hasPermission respects role', () {
      expect(service.hasPermission(EnginePermission.editContent), isTrue);
      expect(service.hasPermission(EnginePermission.managePlugins), isFalse);
    });

    test('setRole changes permissions', () {
      service.setRole(EngineRole.viewer);
      expect(service.hasPermission(EnginePermission.editContent), isFalse);
      expect(service.hasPermission(EnginePermission.viewCanvas), isTrue);
    });

    test('ABAC policy overrides RBAC', () {
      service.setPolicy(
        PermissionPolicy(
          rules: [
            PermissionRule(
              permission: EnginePermission.editContent,
              allow: false,
              priority: 100,
            ),
          ],
        ),
      );

      // Editor normally has editContent, but policy denies
      expect(service.hasPermission(EnginePermission.editContent), isFalse);
      // Other permissions fall through to RBAC
      expect(service.hasPermission(EnginePermission.addNodes), isTrue);
    });

    test('canMutateNode builds correct attributes', () {
      // Editor can edit ShapeNode
      expect(
        service.canMutateNode('ShapeNode', EnginePermission.editContent),
        isTrue,
      );

      // Editor cannot managePlugins
      expect(
        service.canMutateNode('ShapeNode', EnginePermission.managePlugins),
        isFalse,
      );
    });

    test('requirePermission throws on denial', () {
      service.setRole(EngineRole.viewer);
      expect(
        () => service.requirePermission(EnginePermission.editContent),
        throwsA(isA<PermissionDeniedError>()),
      );
    });

    test('requirePermission does not throw when granted', () {
      expect(
        () => service.requirePermission(EnginePermission.editContent),
        returnsNormally,
      );
    });

    test('denials stream emits on rejection', () async {
      service.setRole(EngineRole.viewer);

      final denials = <PermissionDenial>[];
      final sub = service.denials.listen(denials.add);

      try {
        service.requirePermission(EnginePermission.editContent);
      } catch (_) {}

      await Future.delayed(Duration.zero);

      expect(denials.length, 1);
      expect(denials.first.permission, EnginePermission.editContent);
      expect(denials.first.role, EngineRole.viewer);

      await sub.cancel();
    });

    test('dispose closes denial stream', () {
      service.dispose();
      expect(service.isDisposed, isTrue);
    });
  });

  // ===========================================================================
  // PERMISSION INTERCEPTOR
  // ===========================================================================

  group('PermissionInterceptor', () {
    late PermissionService permService;
    late PermissionInterceptor interceptor;

    setUp(() {
      permService = PermissionService(role: EngineRole.editor);
      interceptor = PermissionInterceptor(permissionService: permService);
    });

    tearDown(() {
      permService.dispose();
    });

    test('has priority 5', () {
      expect(interceptor.priority, 5);
    });

    test('allows add when editor', () {
      final node = testShapeNode();
      final result = interceptor.beforeAdd(node, 'root');
      expect(result.isAllowed, isTrue);
    });

    test('rejects add when viewer', () {
      permService.setRole(EngineRole.viewer);
      final node = testShapeNode();
      final result = interceptor.beforeAdd(node, 'root');
      expect(result.isAllowed, isFalse);
      expect(result.reason, contains('Permission denied'));
    });

    test('allows remove when editor', () {
      final node = testShapeNode();
      final result = interceptor.beforeRemove(node, 'root');
      expect(result.isAllowed, isTrue);
    });

    test('rejects remove when viewer', () {
      permService.setRole(EngineRole.viewer);
      final node = testShapeNode();
      final result = interceptor.beforeRemove(node, 'root');
      expect(result.isAllowed, isFalse);
    });

    test('allows property change when editor', () {
      final node = testShapeNode();
      final result = interceptor.beforePropertyChange(node, 'opacity', 0.5);
      expect(result.isAllowed, isTrue);
    });

    test('rejects property change when viewer', () {
      permService.setRole(EngineRole.viewer);
      final node = testShapeNode();
      final result = interceptor.beforePropertyChange(node, 'opacity', 0.5);
      expect(result.isAllowed, isFalse);
    });

    test('isLocked property change uses lockNodes permission', () {
      permService.setRole(EngineRole.editor);
      final node = testShapeNode();
      // Editor has lockNodes permission
      final result = interceptor.beforePropertyChange(node, 'isLocked', true);
      expect(result.isAllowed, isTrue);

      // Viewer does not
      permService.setRole(EngineRole.viewer);
      final result2 = interceptor.beforePropertyChange(node, 'isLocked', true);
      expect(result2.isAllowed, isFalse);
    });

    test('allows reorder when editor', () {
      final result = interceptor.beforeReorder('group-1', 0, 2);
      expect(result.isAllowed, isTrue);
    });

    test('rejects reorder when viewer', () {
      permService.setRole(EngineRole.viewer);
      final result = interceptor.beforeReorder('group-1', 0, 2);
      expect(result.isAllowed, isFalse);
    });

    test('works in InterceptorChain', () {
      final chain = InterceptorChain()..add(interceptor);

      permService.setRole(EngineRole.viewer);
      final node = testShapeNode();

      expect(
        () => chain.runBeforeAdd(node, 'root'),
        throwsA(isA<MutationRejectedError>()),
      );
    });
  });

  // ===========================================================================
  // ENGINE SCOPE INTEGRATION
  // ===========================================================================

  group('EngineScope RBAC integration', () {
    tearDown(() {
      EngineScope.reset();
    });

    test('permissionService is accessible', () {
      expect(EngineScope.current.permissionService, isNotNull);
    });

    test('interceptorChain includes PermissionInterceptor', () {
      final chain = EngineScope.current.interceptorChain;
      final hasPermInterceptor = chain.interceptors.any(
        (i) => i is PermissionInterceptor,
      );
      expect(hasPermInterceptor, isTrue);
    });

    test('health check includes PermissionService', () {
      final report = EngineScope.current.healthCheck();
      final permHealth = report.services.where(
        (s) => s.name == 'PermissionService',
      );
      expect(permHealth, isNotEmpty);
      expect(permHealth.first.healthy, isTrue);
    });

    test('scope disposal disposes permission service', () {
      final scope = EngineScope();
      scope.permissionService;
      scope.dispose();
      expect(scope.permissionService.isDisposed, isTrue);
    });
  });
}
