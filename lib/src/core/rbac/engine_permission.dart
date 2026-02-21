/// 🔐 ENGINE PERMISSION — Granular permission enum and role model for RBAC.
///
/// Defines the permission atoms and role structure used by
/// [PermissionService] and [PermissionInterceptor] to enforce
/// access control at the scene-graph level.
///
/// ```dart
/// final editor = EngineRole.editor;
/// print(editor.has(EnginePermission.editContent)); // true
/// print(editor.has(EnginePermission.manageRoles)); // false
/// ```
library;

// =============================================================================
// ENGINE PERMISSION
// =============================================================================

/// Granular permission atoms for the Nebula Engine.
///
/// Each permission represents a single, indivisible capability.
/// Roles are composed from sets of permissions.
enum EnginePermission {
  /// View canvas content and scene graph (read-only access).
  viewCanvas,

  /// Modify existing node properties (opacity, color, text, transform).
  editContent,

  /// Create new nodes in the scene graph.
  addNodes,

  /// Delete nodes from the scene graph.
  removeNodes,

  /// Reorder children within group/layer nodes.
  reorderNodes,

  /// Lock or unlock nodes.
  lockNodes,

  /// Create, edit, delete design variables and tokens.
  manageVariables,

  /// Export canvas to PNG, SVG, PDF, or other formats.
  exportCanvas,

  /// Install, remove, or configure plugins.
  managePlugins,

  /// Create, modify, or assign roles (admin-only).
  manageRoles,

  /// Change engine or canvas configuration.
  configureEngine,
}

// =============================================================================
// ENGINE ROLE
// =============================================================================

/// A named set of [EnginePermission]s with a priority level.
///
/// Higher [priority] means more privileged. When conflicts arise,
/// the higher-priority role wins.
///
/// Five built-in roles are provided via static constants:
/// - [viewer] — read-only access
/// - [commenter] — view + export (collaboration observation)
/// - [editor] — full content editing (no admin)
/// - [admin] — all except role management
/// - [owner] — unrestricted access
class EngineRole {
  /// Unique identifier for this role.
  final String id;

  /// Human-readable display name.
  final String name;

  /// Set of granted permissions.
  final Set<EnginePermission> permissions;

  /// Priority level (higher = more privileged).
  ///
  /// Used for conflict resolution: if a user has multiple roles,
  /// the highest-priority one takes precedence.
  final int priority;

  const EngineRole({
    required this.id,
    required this.name,
    required this.permissions,
    this.priority = 0,
  });

  /// Check if this role grants a specific permission.
  bool has(EnginePermission permission) => permissions.contains(permission);

  /// Check if this role grants ALL of the given permissions.
  bool hasAll(Set<EnginePermission> required) =>
      required.every(permissions.contains);

  /// Check if this role grants ANY of the given permissions.
  bool hasAny(Set<EnginePermission> candidates) =>
      candidates.any(permissions.contains);

  // ===========================================================================
  // BUILT-IN ROLES
  // ===========================================================================

  /// Read-only access — can view content but not modify anything.
  static const viewer = EngineRole(
    id: 'viewer',
    name: 'Viewer',
    priority: 10,
    permissions: {EnginePermission.viewCanvas},
  );

  /// View + export — for collaboration observers who need to export.
  static const commenter = EngineRole(
    id: 'commenter',
    name: 'Commenter',
    priority: 20,
    permissions: {EnginePermission.viewCanvas, EnginePermission.exportCanvas},
  );

  /// Full content editing — can modify the scene graph but not admin tasks.
  static const editor = EngineRole(
    id: 'editor',
    name: 'Editor',
    priority: 50,
    permissions: {
      EnginePermission.viewCanvas,
      EnginePermission.editContent,
      EnginePermission.addNodes,
      EnginePermission.removeNodes,
      EnginePermission.reorderNodes,
      EnginePermission.lockNodes,
      EnginePermission.manageVariables,
      EnginePermission.exportCanvas,
    },
  );

  /// Administrative access — everything except role management.
  static const admin = EngineRole(
    id: 'admin',
    name: 'Admin',
    priority: 90,
    permissions: {
      EnginePermission.viewCanvas,
      EnginePermission.editContent,
      EnginePermission.addNodes,
      EnginePermission.removeNodes,
      EnginePermission.reorderNodes,
      EnginePermission.lockNodes,
      EnginePermission.manageVariables,
      EnginePermission.exportCanvas,
      EnginePermission.managePlugins,
      EnginePermission.configureEngine,
    },
  );

  /// Unrestricted access — all permissions including role management.
  static const owner = EngineRole(
    id: 'owner',
    name: 'Owner',
    priority: 100,
    permissions: {
      EnginePermission.viewCanvas,
      EnginePermission.editContent,
      EnginePermission.addNodes,
      EnginePermission.removeNodes,
      EnginePermission.reorderNodes,
      EnginePermission.lockNodes,
      EnginePermission.manageVariables,
      EnginePermission.exportCanvas,
      EnginePermission.managePlugins,
      EnginePermission.manageRoles,
      EnginePermission.configureEngine,
    },
  );

  /// All built-in roles, ordered by priority (lowest first).
  static const builtInRoles = [viewer, commenter, editor, admin, owner];

  /// Look up a built-in role by [id], or `null` if not found.
  static EngineRole? fromId(String id) {
    for (final role in builtInRoles) {
      if (role.id == id) return role;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is EngineRole && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'EngineRole($id, priority=$priority, '
      'permissions=${permissions.length})';
}
