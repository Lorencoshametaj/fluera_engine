import 'dart:async';

import 'engine_permission.dart';
import 'permission_policy.dart';

/// 🔐 PERMISSION SERVICE — Central authorization gate for the Fluera Engine.
///
/// Provides the single source of truth for "can this user do X?", combining:
/// 1. **RBAC** — role-based permissions from [currentRole]
/// 2. **ABAC** — attribute-based overrides from [policy]
///
/// The ABAC policy is evaluated first; if no rule matches, the decision
/// falls through to the role's permission set.
///
/// ```dart
/// final permService = PermissionService(role: EngineRole.editor);
///
/// // Simple check
/// if (permService.hasPermission(EnginePermission.addNodes)) {
///   sceneGraph.addNode(node, parentId);
/// }
///
/// // Throws PermissionDeniedError if denied
/// permService.requirePermission(EnginePermission.removeNodes);
///
/// // Audit integration
/// permService.denials.listen((event) {
///   auditLog.record(AuditEntry(
///     action: AuditAction.error,
///     severity: AuditSeverity.warning,
///     description: 'Permission denied: ${event.permission.name}',
///   ));
/// });
/// ```
class PermissionService {
  /// Current role of the active user/session.
  EngineRole _currentRole;

  /// Optional ABAC policy overlay.
  PermissionPolicy _policy;

  /// Stream of denied permission attempts (for audit integration).
  final StreamController<PermissionDenial> _denialController =
      StreamController<PermissionDenial>.broadcast(sync: false);

  /// Whether the service has been disposed.
  bool _disposed = false;

  /// Create a permission service with an initial [role].
  ///
  /// Defaults to [EngineRole.editor] if not specified.
  /// An optional [policy] provides ABAC overrides on top of RBAC.
  PermissionService({EngineRole? role, PermissionPolicy? policy})
    : _currentRole = role ?? EngineRole.editor,
      _policy = policy ?? const PermissionPolicy.empty();

  // ===========================================================================
  // ROLE MANAGEMENT
  // ===========================================================================

  /// The currently active role.
  EngineRole get currentRole => _currentRole;

  /// Switch to a different role.
  ///
  /// This immediately affects all subsequent permission checks.
  void setRole(EngineRole role) {
    _currentRole = role;
  }

  /// Set or replace the ABAC policy overlay.
  void setPolicy(PermissionPolicy policy) {
    _policy = policy;
  }

  /// The current ABAC policy.
  PermissionPolicy get policy => _policy;

  // ===========================================================================
  // AUTHORIZATION
  // ===========================================================================

  /// Check if the current role + policy grants a [permission].
  ///
  /// Optionally provide [attributes] for ABAC evaluation.
  ///
  /// Evaluation order:
  /// 1. ABAC policy rules (if any match)
  /// 2. RBAC role-based check (fallback)
  bool hasPermission(
    EnginePermission permission, {
    Map<String, dynamic> attributes = const {},
  }) {
    // 1. Check ABAC policy first
    final policyResult = _policy.evaluate(permission, attributes);
    if (policyResult != null) return policyResult;

    // 2. Fall through to RBAC
    return _currentRole.has(permission);
  }

  /// Check if the current role can perform [action] on [node].
  ///
  /// Convenience method that builds an attribute map from the node
  /// and delegates to [hasPermission].
  bool canMutateNode(
    String nodeType,
    EnginePermission action, {
    String? nodeId,
    bool isLocked = false,
  }) {
    final attributes = <String, dynamic>{
      'node.type': nodeType,
      if (nodeId != null) 'node.id': nodeId,
      'node.isLocked': isLocked,
      'actor.role': _currentRole.id,
    };
    return hasPermission(action, attributes: attributes);
  }

  /// Require a permission, throwing [PermissionDeniedError] if denied.
  ///
  /// Also emits a [PermissionDenial] on the [denials] stream.
  void requirePermission(
    EnginePermission permission, {
    Map<String, dynamic> attributes = const {},
    String? context,
  }) {
    if (!hasPermission(permission, attributes: attributes)) {
      final denial = PermissionDenial(
        permission: permission,
        role: _currentRole,
        context: context,
        timestamp: DateTime.now().toUtc(),
      );

      if (!_denialController.isClosed) {
        _denialController.add(denial);
      }

      throw PermissionDeniedError(
        permission: permission,
        role: _currentRole,
        context: context,
      );
    }
  }

  // ===========================================================================
  // DENIAL STREAM (AUDIT INTEGRATION)
  // ===========================================================================

  /// Stream of denied permission attempts.
  ///
  /// Subscribe to this for audit logging of authorization failures.
  Stream<PermissionDenial> get denials => _denialController.stream;

  // ===========================================================================
  // LIFECYCLE
  // ===========================================================================

  /// Dispose the permission service.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _denialController.close();
  }

  /// Whether this service has been disposed.
  bool get isDisposed => _disposed;
}

// =============================================================================
// PERMISSION DENIED ERROR
// =============================================================================

/// Thrown when a required permission is not granted.
class PermissionDeniedError extends Error {
  /// The permission that was denied.
  final EnginePermission permission;

  /// The role that attempted the action.
  final EngineRole role;

  /// Optional context about what was being attempted.
  final String? context;

  PermissionDeniedError({
    required this.permission,
    required this.role,
    this.context,
  });

  @override
  String toString() =>
      'PermissionDeniedError: ${permission.name} denied for role '
      '"${role.name}"${context != null ? ' ($context)' : ''}';
}

// =============================================================================
// PERMISSION DENIAL (EVENT)
// =============================================================================

/// Record of a denied permission attempt — emitted on [PermissionService.denials].
class PermissionDenial {
  /// The permission that was denied.
  final EnginePermission permission;

  /// The role that attempted the action.
  final EngineRole role;

  /// Optional context.
  final String? context;

  /// When the denial occurred.
  final DateTime timestamp;

  const PermissionDenial({
    required this.permission,
    required this.role,
    this.context,
    required this.timestamp,
  });

  @override
  String toString() =>
      'PermissionDenial(${permission.name}, role=${role.name}, '
      '${context ?? "no context"})';
}
