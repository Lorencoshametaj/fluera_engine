/// 🧠 CONSCIOUS ARCHITECTURE — Four intelligence layers beyond fluidity.
///
/// The Fluera Engine operates at five levels of intelligence:
///
/// - **L0 — Fluid**        : 60 FPS, zero-alloc, 8-subsystem pipeline (complete)
/// - **L1 — Anticipatory** : Predicts user intent, pre-fetches/pre-computes
/// - **L2 — Adaptive**     : Tunes itself to context, device, and user behavior
/// - **L3 — Invisible**    : Technology disappears — zero-config UX
/// - **L4 — Generative**   : Co-creates with the user — AI-assisted design
///
/// This file defines the runtime registry and contracts that unify these layers.
/// Subsystems register themselves at startup and receive lifecycle events
/// (context changes, idle heartbeats) through a single coordination point.
///
/// ## Usage
///
/// ```dart
/// final arch = EngineScope.current.consciousArchitecture;
/// arch.register(AnticipatoryTilePrefetch(tileCacheManager));
/// arch.register(AdaptiveProfile(eventBus));
///
/// // Subsystems respond to context changes automatically
/// arch.notifyContextChanged(EngineContext(activeTool: 'pen', zoom: 1.5));
///
/// // During idle time, subsystems do background work
/// arch.notifyIdle(Duration(milliseconds: 200));
/// ```
library;

import 'dart:ui';

// =============================================================================
// INTELLIGENCE LAYER
// =============================================================================

/// The five levels of engine intelligence.
enum IntelligenceLayer {
  /// L0: 60 FPS guaranteed, zero-alloc hot path, 8-subsystem fluidity pipeline.
  fluid,

  /// L1: Predicts user intent — pre-fetches tiles, pre-computes LOD,
  /// extrapolates strokes before they arrive.
  anticipatory,

  /// L2: Tunes rendering/input parameters to device capabilities,
  /// user behavior patterns, and current workload.
  adaptive,

  /// L3: Technology disappears — smart snapping, auto-layout,
  /// zero-config collaboration, seamless persistence.
  invisible,

  /// L4: Co-creates with the user — LaTeX recognition, design linting,
  /// auto-complete, intelligent suggestions.
  generative,
}

// =============================================================================
// ENGINE CONTEXT
// =============================================================================

/// Snapshot of the engine's current state, passed to subsystems on changes.
///
/// This is the single channel through which intelligence subsystems learn
/// about what the user is doing. Keep it lightweight — add fields only
/// when a subsystem genuinely needs them.
class EngineContext {
  /// Currently active tool name (e.g. 'pen', 'lasso', 'shape').
  final String? activeTool;

  /// Current zoom level.
  final double zoom;

  /// Current viewport in canvas coordinates.
  final Rect? viewport;

  /// Current pan velocity (px/s) — useful for anticipatory prefetch.
  final Offset panVelocity;

  /// Whether the user is currently drawing (stylus/finger down).
  final bool isDrawing;

  /// Number of strokes on the canvas (workload indicator).
  final int strokeCount;

  /// Whether the document is a PDF (changes rendering strategy).
  final bool isPdfDocument;

  const EngineContext({
    this.activeTool,
    this.zoom = 1.0,
    this.viewport,
    this.panVelocity = Offset.zero,
    this.isDrawing = false,
    this.strokeCount = 0,
    this.isPdfDocument = false,
  });

  /// Create a modified copy.
  EngineContext copyWith({
    String? activeTool,
    double? zoom,
    Rect? viewport,
    Offset? panVelocity,
    bool? isDrawing,
    int? strokeCount,
    bool? isPdfDocument,
  }) {
    return EngineContext(
      activeTool: activeTool ?? this.activeTool,
      zoom: zoom ?? this.zoom,
      viewport: viewport ?? this.viewport,
      panVelocity: panVelocity ?? this.panVelocity,
      isDrawing: isDrawing ?? this.isDrawing,
      strokeCount: strokeCount ?? this.strokeCount,
      isPdfDocument: isPdfDocument ?? this.isPdfDocument,
    );
  }
}

// =============================================================================
// INTELLIGENCE SUBSYSTEM CONTRACT
// =============================================================================

/// Contract for any intelligence subsystem that participates in the
/// Conscious Architecture.
///
/// Implementations must declare their [layer] and [name], and respond to
/// lifecycle events:
///
/// - [onContextChanged]: the user switched tools, zoomed, opened a document
/// - [onIdle]: no user interaction for [idleDuration] — do background work
/// - [dispose]: graceful shutdown
abstract class IntelligenceSubsystem {
  /// Which intelligence layer this subsystem belongs to.
  IntelligenceLayer get layer;

  /// Human-readable name for diagnostics and logging.
  String get name;

  /// Whether this subsystem is currently active and responding to events.
  bool get isActive;

  /// Called when the engine context changes (tool switch, zoom, document load).
  ///
  /// Implementations should use this to adjust their strategy. For example,
  /// an anticipatory prefetcher might change prefetch direction based on
  /// pan velocity, while an adaptive profile might update its behavior model.
  void onContextChanged(EngineContext context);

  /// Called during idle periods when no user interaction is occurring.
  ///
  /// Use this for non-urgent background work: LOD precomputation,
  /// profile analysis, cache warming, etc.
  ///
  /// [idleDuration] is how long the user has been idle.
  void onIdle(Duration idleDuration);

  /// Graceful shutdown. Release resources, cancel timers, etc.
  void dispose();
}

// =============================================================================
// CONSCIOUS ARCHITECTURE REGISTRY
// =============================================================================

/// Central registry for all intelligence subsystems.
///
/// Provides:
/// - **Registration**: subsystems register themselves at startup
/// - **Lifecycle dispatch**: context changes and idle heartbeats
/// - **Typed lookup**: find a specific subsystem by type
/// - **Layer query**: list all subsystems in a given layer
/// - **Diagnostics**: summary of registered subsystems for health checks
class ConsciousArchitecture {
  final List<IntelligenceSubsystem> _subsystems = [];

  /// The last known engine context.
  EngineContext _currentContext = const EngineContext();

  /// The last known engine context.
  EngineContext get currentContext => _currentContext;

  // ─────────────────────────────────────────────────────────────────────────
  // Registration
  // ─────────────────────────────────────────────────────────────────────────

  /// Register an intelligence subsystem.
  ///
  /// Duplicate registrations (same type) are silently ignored.
  void register(IntelligenceSubsystem subsystem) {
    // Prevent duplicate registrations of the same type.
    if (_subsystems.any((s) => s.runtimeType == subsystem.runtimeType)) return;
    _subsystems.add(subsystem);
  }

  /// Unregister an intelligence subsystem.
  void unregister(IntelligenceSubsystem subsystem) {
    _subsystems.remove(subsystem);
  }

  /// All registered subsystems (unmodifiable view).
  List<IntelligenceSubsystem> get subsystems => List.unmodifiable(_subsystems);

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle Dispatch
  // ─────────────────────────────────────────────────────────────────────────

  /// Notify all active subsystems that the engine context has changed.
  ///
  /// This is the primary coordination mechanism. Call when:
  /// - The user switches tools
  /// - Zoom level changes significantly
  /// - A document is opened or closed
  /// - Pan velocity changes (for anticipatory work)
  void notifyContextChanged(EngineContext context) {
    _currentContext = context;
    for (final subsystem in _subsystems) {
      if (subsystem.isActive) {
        subsystem.onContextChanged(context);
      }
    }
  }

  /// Notify all active subsystems that the engine is idle.
  ///
  /// Call from the frame scheduler when no user interaction has occurred
  /// for a period. Subsystems can use this for background work.
  void notifyIdle(Duration idleDuration) {
    for (final subsystem in _subsystems) {
      if (subsystem.isActive) {
        subsystem.onIdle(idleDuration);
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Queries
  // ─────────────────────────────────────────────────────────────────────────

  /// Get all subsystems in a specific intelligence layer.
  List<IntelligenceSubsystem> byLayer(IntelligenceLayer layer) =>
      _subsystems.where((s) => s.layer == layer).toList();

  /// Find a specific subsystem by type. Returns null if not registered.
  T? find<T extends IntelligenceSubsystem>() {
    for (final subsystem in _subsystems) {
      if (subsystem is T) return subsystem;
    }
    return null;
  }

  /// Whether a specific subsystem type is registered and active.
  bool isLayerActive<T extends IntelligenceSubsystem>() {
    final sub = find<T>();
    return sub != null && sub.isActive;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Diagnostics
  // ─────────────────────────────────────────────────────────────────────────

  /// Summary of all registered subsystems for health checks.
  Map<String, dynamic> diagnostics() => {
    'totalSubsystems': _subsystems.length,
    'activeSubsystems': _subsystems.where((s) => s.isActive).length,
    'byLayer': {
      for (final layer in IntelligenceLayer.values)
        layer.name:
            byLayer(
              layer,
            ).map((s) => {'name': s.name, 'active': s.isActive}).toList(),
    },
  };

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────

  /// Dispose all registered subsystems.
  void dispose() {
    for (final subsystem in _subsystems) {
      subsystem.dispose();
    }
    _subsystems.clear();
  }
}
