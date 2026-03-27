import '../modules/canvas_module.dart';
import '../../tools/base/tool_interface.dart';
import '../rbac/permission_service.dart';

// =============================================================================
// ENTERPRISE MODULE
// =============================================================================

/// 🏢 Enterprise module for the Fluera Engine.
///
/// Provides enterprise-grade capabilities:
/// - **Feature flags** — runtime gate-checking for staged rollouts
/// - **Analytics** — lightweight event tracking contract
/// - **RBAC** — role-based access control (wraps [PermissionService])
///
/// ## Usage
///
/// ```dart
/// final enterprise = EngineScope.current.enterpriseModule!;
/// if (enterprise.featureFlags.isEnabled('fluid_topology')) {
///   // Feature is enabled
/// }
/// enterprise.analytics.trackEvent('stroke_completed', {'length': 42});
/// ```
class EnterpriseModule extends CanvasModule {
  @override
  String get moduleId => 'enterprise';

  @override
  String get displayName => 'Enterprise';

  // ---------------------------------------------------------------------------
  // Services
  // ---------------------------------------------------------------------------

  /// Runtime feature flag service.
  late final FeatureFlagService featureFlags;

  /// Lightweight analytics tracking.
  late final AnalyticsService analytics;

  /// Role-based access control (wraps existing PermissionService).
  late final EnterpriseRBACService rbac;

  /// The [PermissionService] to wrap — injected at initialization.
  final PermissionService? _permissionService;

  EnterpriseModule({PermissionService? permissionService})
    : _permissionService = permissionService;

  // ---------------------------------------------------------------------------
  // CanvasModule contract
  // ---------------------------------------------------------------------------

  @override
  List<NodeDescriptor> get nodeDescriptors => const [];

  @override
  List<DrawingTool> createTools() => const [];

  @override
  bool get isInitialized => _initialized;
  bool _initialized = false;

  @override
  Future<void> initialize(ModuleContext context) async {
    if (_initialized) return;

    featureFlags = FeatureFlagService();
    analytics = AnalyticsService();
    rbac = EnterpriseRBACService(
      permissionService: _permissionService ?? context.scope.permissionService,
    );

    _initialized = true;
  }

  @override
  Future<void> dispose() async {
    if (!_initialized) return;
    analytics.flush();
    _initialized = false;
  }
}

// =============================================================================
// FEATURE FLAG SERVICE
// =============================================================================

/// Runtime feature gate — check whether features are enabled.
///
/// Supports local overrides and remote configuration (pluggable).
class FeatureFlagService {
  final Map<String, bool> _overrides = {};
  final Map<String, bool> _defaults = {};

  /// Check if a feature flag is enabled.
  bool isEnabled(String flag) => _overrides[flag] ?? _defaults[flag] ?? false;

  /// Set a local override for a feature flag.
  void setOverride(String flag, bool enabled) => _overrides[flag] = enabled;

  /// Remove a local override.
  void removeOverride(String flag) => _overrides.remove(flag);

  /// Clear all overrides.
  void clearOverrides() => _overrides.clear();

  /// Load default values (e.g. from remote config).
  void loadDefaults(Map<String, bool> defaults) {
    _defaults
      ..clear()
      ..addAll(defaults);
  }

  /// All flags with their resolved values.
  Map<String, bool> get allFlags => {..._defaults, ..._overrides};
}

// =============================================================================
// ANALYTICS SERVICE
// =============================================================================

/// Lightweight analytics event tracker.
///
/// Events are buffered and flushed to a pluggable sink.
class AnalyticsService {
  final List<AnalyticsEvent> _buffer = [];
  void Function(List<AnalyticsEvent>)? _sink;

  /// Track an analytics event.
  void trackEvent(String name, [Map<String, dynamic>? properties]) {
    _buffer.add(
      AnalyticsEvent(
        name: name,
        properties: properties ?? const {},
        timestamp: DateTime.now(),
      ),
    );
    // Auto-flush at 100 events
    if (_buffer.length >= 100) flush();
  }

  /// Register an event sink (e.g. Firebase, custom backend).
  void registerSink(void Function(List<AnalyticsEvent>) sink) {
    _sink = sink;
  }

  /// Flush buffered events to the sink.
  void flush() {
    if (_buffer.isEmpty) return;
    _sink?.call(List.unmodifiable(_buffer));
    _buffer.clear();
  }

  /// Number of buffered events.
  int get pendingEvents => _buffer.length;
}

/// A single analytics event.
class AnalyticsEvent {
  final String name;
  final Map<String, dynamic> properties;
  final DateTime timestamp;

  const AnalyticsEvent({
    required this.name,
    required this.properties,
    required this.timestamp,
  });

  @override
  String toString() => 'AnalyticsEvent($name, $properties)';
}

// =============================================================================
// ENTERPRISE RBAC SERVICE
// =============================================================================

/// Enterprise RBAC wrapper over [PermissionService].
///
/// Adds role management, team-based access, and audit-friendly permission
/// checks on top of the core permission infrastructure.
class EnterpriseRBACService {
  final PermissionService permissionService;

  /// Current user roles.
  final Set<String> _roles = {};

  /// Role → permissions mapping.
  final Map<String, Set<String>> _rolePermissions = {};

  EnterpriseRBACService({required this.permissionService});

  /// Assign roles to the current session.
  void assignRoles(Set<String> roles) {
    _roles
      ..clear()
      ..addAll(roles);
  }

  /// Define permissions for a role.
  void defineRole(String role, Set<String> permissions) {
    _rolePermissions[role] = permissions;
  }

  /// Check if the current session has a specific permission.
  bool hasPermission(String permission) {
    for (final role in _roles) {
      if (_rolePermissions[role]?.contains(permission) ?? false) return true;
    }
    return false;
  }

  /// Check if the current session has a specific role.
  bool hasRole(String role) => _roles.contains(role);

  /// All active roles.
  Set<String> get activeRoles => Set.unmodifiable(_roles);
}
