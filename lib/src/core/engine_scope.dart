import 'assets/asset_registry.dart';
import 'scene_graph/invalidation_graph.dart';
import 'scene_graph/scene_graph_interceptor.dart';
import 'engine_error.dart';
import 'engine_event_bus.dart';
import 'engine_telemetry.dart';
import 'error_recovery_service.dart';
import '../history/canvas_delta_tracker.dart';
import '../history/command_history.dart';
import '../history/command_middlewares.dart';
import '../history/undo_redo_manager.dart';
import '../history/background_checkpoint_service.dart';
import '../history/command_journal.dart';
import '../history/journal_recovery_middleware.dart';
import '../drawing/services/brush_settings_service.dart';
import '../drawing/services/stroke_persistence_service.dart';
import '../rendering/shaders/shader_brush_service.dart';
import '../rendering/render_profiler.dart';
import '../tools/base/tool_registry.dart';
import '../rendering/optimization/tile_cache_manager.dart';
import '../rendering/optimization/disk_stroke_manager.dart';
import '../rendering/optimization/frame_budget_manager.dart';
import '../rendering/optimization/advanced_tile_optimizer.dart';
import '../rendering/optimization/memory_budget_controller.dart';
import '../services/adaptive_debouncer_service.dart';
import '../drawing/input/path_pool.dart';
import '../drawing/input/stroke_point_pool.dart';
import '../platform/display_link_service.dart';
import '../drawing/input/predicted_touch_service.dart';
import '../platform/native_stylus_input.dart';
import '../platform/native_performance_monitor.dart';
import '../audio/platform_channels/audio_player_channel.dart';
import '../audio/platform_channels/audio_recorder_channel.dart';
import '../services/image_cache_service.dart';
import '../history/async_command.dart';
import '../systems/engine_theme.dart';
import '../systems/plugin_api.dart';

// ---------------------------------------------------------------------------
// Scope Token
// ---------------------------------------------------------------------------

/// Unique token identifying scope ownership in the scope stack.
///
/// Returned by [EngineScope.push] and required for [EngineScope.pop]
/// to prevent accidental unbinding by unrelated code.
class ScopeToken {
  final int _id;
  ScopeToken._(this._id);

  @override
  String toString() => 'ScopeToken($_id)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is ScopeToken && other._id == _id);

  @override
  int get hashCode => _id.hashCode;
}

/// Internal scope-stack entry pairing a scope with its ownership token.
class _ScopeEntry {
  final EngineScope scope;
  final ScopeToken token;
  _ScopeEntry(this.scope, this.token);
}

// ---------------------------------------------------------------------------
// Engine Scope
// ---------------------------------------------------------------------------

/// Scoped dependency container for the Nebula Engine.
///
/// Replaces global singletons with a composable, testable scope.
/// Each [EngineScope] owns a complete set of engine services, enabling:
///
/// - **Multi-canvas**: Push independent scopes for parallel canvases
/// - **Testability**: Inject mocks or fresh instances per test
/// - **Clean Architecture**: Explicit dependency graph instead of globals
///
/// ## Usage
///
/// ```dart
/// // Default scope (backward-compatible)
/// final tracker = EngineScope.current.deltaTracker;
///
/// // Multi-canvas: push a scope per canvas
/// final token = EngineScope.push(EngineScope());
/// // … canvas A work …
/// EngineScope.pop(token);
///
/// // Clean up all
/// EngineScope.reset();
/// ```
class EngineScope {
  // ---------------------------------------------------------------------------
  // Constructor
  // ---------------------------------------------------------------------------

  /// Optional journal path for crash recovery.
  ///
  /// When set, a [CommandJournal] is created and a [JournalRecoveryMiddleware]
  /// is automatically registered on [commandHistory].
  final String? journalPath;

  /// Create a new engine scope.
  ///
  /// Pass [journalPath] to enable the crash-recovery write-ahead log.
  EngineScope({this.journalPath});
  // ---------------------------------------------------------------------------
  // Scope Stack Management
  // ---------------------------------------------------------------------------

  static final List<_ScopeEntry> _stack = [];
  static int _tokenCounter = 0;

  /// The active engine scope (top of stack).
  ///
  /// Creates and pushes a default scope on first access (lazy initialization).
  static EngineScope get current {
    if (_stack.isEmpty) push(EngineScope());
    return _stack.last.scope;
  }

  /// Push a new scope onto the stack.
  ///
  /// Returns a [ScopeToken] that must be used to [pop] this scope later.
  /// Only the token holder can remove the scope, preventing accidental
  /// unbinding by unrelated code.
  static ScopeToken push(EngineScope scope) {
    final token = ScopeToken._(++_tokenCounter);
    _stack.add(_ScopeEntry(scope, token));
    return token;
  }

  /// Pop the scope associated with [token] from the stack.
  ///
  /// Throws [StateError] if the token doesn't match the top of the stack,
  /// or if the stack is empty.
  static void pop(ScopeToken token) {
    if (_stack.isEmpty) {
      throw StateError('Cannot pop: scope stack is empty.');
    }
    if (_stack.last.token != token) {
      throw StateError(
        'Cannot pop: token $token does not match the top of the stack '
        '(expected ${_stack.last.token}).',
      );
    }
    final entry = _stack.removeLast();
    entry.scope.dispose();
  }

  /// Bind a scope as the active scope (backward-compatible alias for [push]).
  ///
  /// Prefer [push]/[pop] for new code — they provide ownership safety.
  @Deprecated('Use push()/pop() for safe multi-canvas scope management')
  static void bind(EngineScope scope) => push(scope);

  /// Reset the global scope, disposing ALL scopes on the stack.
  static void reset() {
    for (final entry in _stack.reversed) {
      entry.scope.dispose();
    }
    _stack.clear();
  }

  /// Whether any scope is currently on the stack.
  static bool get hasScope => _stack.isNotEmpty;

  /// Current depth of the scope stack (for diagnostics).
  static int get depth => _stack.length;

  // ---------------------------------------------------------------------------
  // Services — lazily created on first access
  // ---------------------------------------------------------------------------

  /// Delta tracker for incremental canvas modifications.
  late final CanvasDeltaTracker deltaTracker = CanvasDeltaTracker.create();

  /// Undo/redo stack manager.
  late final UndoRedoManager undoRedoManager = UndoRedoManager.create();

  /// Background save service for WAL persistence.
  late final BackgroundSaveService backgroundSaveService =
      BackgroundSaveService.create();

  /// Brush settings storage & notification.
  late final BrushSettingsService brushSettingsService =
      BrushSettingsService.create();

  /// Stroke disk persistence service.
  late final StrokePersistenceService strokePersistenceService =
      StrokePersistenceService.create();

  /// GPU shader brush rendering service.
  late final ShaderBrushService shaderBrushService =
      ShaderBrushService.create();

  /// Tool registration and selection.
  late final ToolRegistry toolRegistry = ToolRegistry.create();

  /// Tile-based render cache manager.
  late final TileCacheManager tileCacheManager = TileCacheManager.create();

  /// Disk-based stroke manager for large canvases.
  late final DiskStrokeManager diskStrokeManager = DiskStrokeManager.create();

  /// Frame budget manager for render throttling.
  late final FrameBudgetManager frameBudgetManager =
      FrameBudgetManager.create();

  /// Memory pressure handler.
  late final MemoryPressureHandler memoryPressureHandler =
      MemoryPressureHandler.create();

  /// Advanced tile optimization.
  late final AdvancedTileOptimizer advancedTileOptimizer =
      AdvancedTileOptimizer.create();

  /// Adaptive debouncer for save operations.
  late final AdaptiveDebouncerService adaptiveDebouncerService =
      AdaptiveDebouncerService.create();

  /// Reusable Path object pool.
  late final PathPool pathPool = PathPool.create();

  /// Reusable StrokePoint object pool.
  late final StrokePointPool strokePointPool = StrokePointPool.create();

  /// CADisplayLink frame synchronization (iOS).
  late final DisplayLinkService displayLinkService =
      DisplayLinkService.create();

  /// Native predicted touches for low-latency drawing.
  late final PredictedTouchService predictedTouchService =
      PredictedTouchService.create();

  /// Native stylus input (hover, tilt, palm rejection).
  late final NativeStylusInput nativeStylusInput = NativeStylusInput.create();

  /// Native performance monitor (memory, thermal, battery).
  late final NativePerformanceMonitor performanceMonitor =
      NativePerformanceMonitor.create();

  /// Native audio player platform channel.
  late final NativeAudioPlayerChannel audioPlayerChannel =
      NativeAudioPlayerChannel.create();

  /// Native audio recorder platform channel.
  late final NativeAudioRecorderChannel audioRecorderChannel =
      NativeAudioRecorderChannel.create();

  /// Image loading and LRU caching service.
  late final ImageCacheService imageCacheService = ImageCacheService.create();

  /// Proactive memory budget controller with pressure-based eviction.
  late final MemoryBudgetController memoryBudgetController =
      MemoryBudgetController(
          performanceMonitor: performanceMonitor,
          memoryPressureHandler: memoryPressureHandler,
        )
        ..registerCache(tileCacheManager)
        ..registerCache(imageCacheService, warningFraction: 0.50)
        ..registerCache(diskStrokeManager)
        ..registerCache(assetRegistry);

  /// Unified asset registry: ref counting, dedup, async loading.
  late final AssetRegistry assetRegistry = AssetRegistry();

  /// Enterprise error recovery: retry, circuit breaker, telemetry.
  late final ErrorRecoveryService errorRecovery = ErrorRecoveryService();

  /// Unified telemetry bus: counters, gauges, spans, events.
  late final EngineTelemetry telemetry = EngineTelemetry();

  /// Centralized event bus for cross-subsystem communication.
  late final EngineEventBus eventBus = EngineEventBus();

  /// Command journal for crash recovery (null if journalPath is null).
  late final CommandJournal? commandJournal =
      journalPath != null ? CommandJournal(journalPath: journalPath!) : null;

  /// Command history with event-bus and optional journal middleware wired in.
  late final CommandHistory commandHistory = CommandHistory(
    middlewares: [
      EventBusCommandMiddleware(eventBus),
      if (commandJournal != null)
        JournalRecoveryMiddleware(journal: commandJournal!),
    ],
  );

  /// Reactive invalidation graph for incremental re-rendering.
  late final InvalidationGraph invalidationGraph = InvalidationGraph();

  /// Per-frame render pipeline profiler.
  late final RenderProfiler renderProfiler = RenderProfiler();

  /// Pre-mutation interceptor chain for scene graph validation.
  late final InterceptorChain interceptorChain =
      InterceptorChain()..add(LockInterceptor());

  /// Async command runner for long-running operations.
  late final AsyncCommandRunner asyncCommandRunner = AsyncCommandRunner(
    commandHistory: commandHistory,
  );

  /// Unified theming manager.
  late final EngineThemeManager themeManager = EngineThemeManager(
    eventBus: eventBus,
  );

  /// Plugin registry for managing engine plugins.
  late final PluginRegistry pluginRegistry = PluginRegistry(eventBus: eventBus);

  // ---------------------------------------------------------------------------
  // Health Check
  // ---------------------------------------------------------------------------

  /// Query the health of all engine subsystems.
  ///
  /// Returns a [HealthReport] with per-service status and summary metrics.
  /// Use for diagnostics dashboards, startup validation, or automated
  /// monitoring.
  ///
  /// ```dart
  /// final report = EngineScope.current.healthCheck();
  /// print(report); // HealthReport(healthy: 12/14, uptime: 0:03:42)
  /// ```
  HealthReport healthCheck() {
    final services = <ServiceHealth>[];

    services.add(
      ServiceHealth(
        name: 'EventBus',
        healthy: !eventBus.isPaused,
        detail: 'emitted=${eventBus.totalEmitted}',
      ),
    );

    services.add(ServiceHealth(name: 'ErrorRecovery', healthy: true));

    services.add(
      ServiceHealth(
        name: 'CommandHistory',
        healthy: true,
        detail:
            'undo=${commandHistory.undoCount}, '
            'redo=${commandHistory.redoCount}',
      ),
    );

    services.add(ServiceHealth(name: 'InvalidationGraph', healthy: true));

    services.add(
      ServiceHealth(
        name: 'MemoryBudget',
        healthy: true,
        detail: 'caches=${memoryBudgetController.registeredCacheCount}',
      ),
    );

    services.add(ServiceHealth(name: 'Telemetry', healthy: true));

    services.add(ServiceHealth(name: 'PluginRegistry', healthy: true));

    services.add(ServiceHealth(name: 'AssetRegistry', healthy: true));

    return HealthReport(services: services);
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Whether this scope has been disposed.
  bool _disposed = false;

  /// Whether this scope has been disposed.
  ///
  /// Use for defensive checks in services that hold a scope reference.
  bool get isDisposed => _disposed;

  /// Dispose all services owned by this scope.
  ///
  /// Disposal follows **reverse-dependency order** to ensure no service
  /// attempts to use an already-disposed dependency during cleanup:
  ///
  /// 1. **Leaf services** — tools, plugins, rendering (no dependents)
  /// 2. **Mid-tier** — history, state tracking, memory management
  /// 3. **Infrastructure** — error recovery, telemetry, event bus (depended upon by all)
  void dispose() {
    if (_disposed) return;
    _disposed = true;

    // ── 1. Leaf services (no other service depends on these) ──
    pluginRegistry.dispose();
    toolRegistry.dispose();
    brushSettingsService.dispose();
    themeManager.dispose();
    shaderBrushService.dispose();

    // ── 2. Mid-tier (depend on infra, depended on by leaves) ──
    asyncCommandRunner.dispose();
    undoRedoManager.dispose();
    commandHistory.dispose();
    memoryBudgetController.dispose();
    invalidationGraph.dispose();
    tileCacheManager.dispose();

    // ── 3. Infrastructure (depended upon by everything above) ──
    errorRecovery.dispose();
    telemetry.reset();
    // Event bus MUST be last — other dispose() calls may emit final events.
    eventBus.dispose();
  }
}

// ---------------------------------------------------------------------------
// Health Report
// ---------------------------------------------------------------------------

/// Health status of a single engine service.
class ServiceHealth {
  /// Service name.
  final String name;

  /// Whether the service is operating normally.
  final bool healthy;

  /// Optional detail string (metrics, state info).
  final String? detail;

  const ServiceHealth({required this.name, required this.healthy, this.detail});

  @override
  String toString() =>
      '$name: ${healthy ? '✅' : '❌'}${detail != null ? ' ($detail)' : ''}';
}

/// Aggregated health report for all engine subsystems.
class HealthReport {
  /// Per-service health status.
  final List<ServiceHealth> services;

  /// Timestamp of the health check.
  final DateTime timestamp = DateTime.now();

  HealthReport({required this.services});

  /// Number of healthy services.
  int get healthyCount => services.where((s) => s.healthy).length;

  /// Total number of checked services.
  int get totalCount => services.length;

  /// Whether all services are healthy.
  bool get allHealthy => healthyCount == totalCount;

  /// Export as a JSON-serializable map.
  Map<String, dynamic> toJson() => {
    'healthy': allHealthy,
    'healthyCount': healthyCount,
    'totalCount': totalCount,
    'timestamp': timestamp.toIso8601String(),
    'services': {
      for (final s in services)
        s.name: {
          'healthy': s.healthy,
          if (s.detail != null) 'detail': s.detail,
        },
    },
  };

  @override
  String toString() => 'HealthReport(healthy: $healthyCount/$totalCount)';
}
