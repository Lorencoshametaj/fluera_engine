import '../scene_graph/canvas_node.dart';
import '../scene_graph/scene_graph_interceptor.dart';
import 'engine_permission.dart';
import 'permission_service.dart';

/// 🔐 PERMISSION INTERCEPTOR — RBAC enforcement at the scene-graph level.
///
/// Plugs into the [InterceptorChain] to enforce [PermissionService]
/// authorization on every scene graph mutation. Runs at priority 5
/// (after [LockInterceptor] at 0, before user interceptors at 100).
///
/// Maps each mutation type to the required [EnginePermission]:
///
/// | Mutation | Required Permission |
/// |---|---|
/// | `beforeAdd` | [EnginePermission.addNodes] |
/// | `beforeRemove` | [EnginePermission.removeNodes] |
/// | `beforePropertyChange` | [EnginePermission.editContent] |
/// | `beforeReorder` | [EnginePermission.reorderNodes] |
///
/// ```dart
/// final interceptor = PermissionInterceptor(
///   permissionService: scope.permissionService,
/// );
/// scope.interceptorChain.add(interceptor);
/// ```
class PermissionInterceptor extends SceneGraphInterceptor {
  /// The permission service used for authorization checks.
  final PermissionService permissionService;

  /// Create a permission interceptor.
  PermissionInterceptor({required this.permissionService});

  @override
  String get name => 'PermissionInterceptor';

  /// Priority 5 — runs after LockInterceptor (0) but before user
  /// interceptors (default 100).
  @override
  int get priority => 5;

  @override
  InterceptorResult beforeAdd(CanvasNode node, String parentId) {
    if (!permissionService.hasPermission(
      EnginePermission.addNodes,
      attributes: _nodeAttributes(node),
    )) {
      return InterceptorResult.reject(
        'Permission denied: cannot add nodes '
        '(role: ${permissionService.currentRole.name})',
      );
    }
    return const InterceptorResult.allow();
  }

  @override
  InterceptorResult beforeRemove(CanvasNode node, String parentId) {
    if (!permissionService.hasPermission(
      EnginePermission.removeNodes,
      attributes: _nodeAttributes(node),
    )) {
      return InterceptorResult.reject(
        'Permission denied: cannot remove node "${node.name}" '
        '(role: ${permissionService.currentRole.name})',
      );
    }
    return const InterceptorResult.allow();
  }

  @override
  InterceptorResult beforePropertyChange(
    CanvasNode node,
    String property,
    dynamic newValue,
  ) {
    // Lock/unlock uses lockNodes permission
    final permission =
        property == 'isLocked'
            ? EnginePermission.lockNodes
            : EnginePermission.editContent;

    if (!permissionService.hasPermission(
      permission,
      attributes: {..._nodeAttributes(node), 'property': property},
    )) {
      return InterceptorResult.reject(
        'Permission denied: cannot modify "$property" on "${node.name}" '
        '(role: ${permissionService.currentRole.name})',
      );
    }
    return const InterceptorResult.allow();
  }

  @override
  InterceptorResult beforeReorder(String parentId, int oldIndex, int newIndex) {
    if (!permissionService.hasPermission(
      EnginePermission.reorderNodes,
      attributes: {
        'parent.id': parentId,
        'actor.role': permissionService.currentRole.id,
      },
    )) {
      return InterceptorResult.reject(
        'Permission denied: cannot reorder nodes '
        '(role: ${permissionService.currentRole.name})',
      );
    }
    return const InterceptorResult.allow();
  }

  /// Build attribute map from a node for ABAC evaluation.
  Map<String, dynamic> _nodeAttributes(CanvasNode node) => {
    'node.type': node.runtimeType.toString(),
    'node.id': node.id.toString(),
    'node.isLocked': node.isLocked,
    'actor.role': permissionService.currentRole.id,
  };
}
