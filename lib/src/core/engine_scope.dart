import '../history/canvas_delta_tracker.dart';
import '../history/undo_redo_manager.dart';
import '../history/background_checkpoint_service.dart';
import '../drawing/services/brush_settings_service.dart';
import '../drawing/services/stroke_persistence_service.dart';
import '../rendering/shaders/shader_brush_service.dart';
import '../tools/base/tool_registry.dart';
import '../rendering/optimization/tile_cache_manager.dart';
import '../rendering/optimization/disk_stroke_manager.dart';
import '../rendering/optimization/frame_budget_manager.dart';
import '../rendering/optimization/advanced_tile_optimizer.dart';
import '../services/adaptive_debouncer_service.dart';
import '../drawing/input/path_pool.dart';
import '../drawing/input/stroke_point_pool.dart';
import '../platform/display_link_service.dart';
import '../drawing/input/predicted_touch_service.dart';
import '../platform/native_stylus_input.dart';
import '../platform/native_performance_monitor.dart';
import '../audio/platform_channels/audio_player_channel.dart';
import '../services/image_cache_service.dart';

/// Scoped dependency container for the Nebula Engine.
///
/// Replaces global singletons with a composable, testable scope.
/// Each [EngineScope] owns a complete set of engine services, enabling:
///
/// - **Multi-canvas**: Create independent scopes for parallel canvases
/// - **Testability**: Inject mocks or fresh instances per test
/// - **Clean Architecture**: Explicit dependency graph instead of globals
///
/// ## Usage
///
/// ```dart
/// // Default scope (backward-compatible with .instance accessors)
/// final tracker = EngineScope.current.deltaTracker;
///
/// // Explicit scope for multi-canvas
/// final scope = EngineScope();
/// EngineScope.bind(scope);
///
/// // Clean up
/// EngineScope.reset();
/// ```
///
/// All existing `.instance` accessors now delegate to [EngineScope.current],
/// so consumer code works unchanged.
class EngineScope {
  // ---------------------------------------------------------------------------
  // Global scope management
  // ---------------------------------------------------------------------------

  static EngineScope? _current;

  /// The active engine scope.
  ///
  /// Creates a default scope on first access (lazy initialization).
  static EngineScope get current => _current ??= EngineScope();

  /// Bind a new scope as the active scope.
  ///
  /// Typically used at canvas initialization or in tests.
  static void bind(EngineScope scope) => _current = scope;

  /// Reset the global scope, disposing the current one if present.
  static void reset() {
    _current?.dispose();
    _current = null;
  }

  /// Whether a scope is currently active.
  static bool get hasScope => _current != null;

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

  /// Image loading and LRU caching service.
  late final ImageCacheService imageCacheService = ImageCacheService.create();

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Dispose all services owned by this scope.
  void dispose() {
    // Dispose ChangeNotifier-based services
    undoRedoManager.dispose();
    brushSettingsService.dispose();
    toolRegistry.dispose();
  }
}
