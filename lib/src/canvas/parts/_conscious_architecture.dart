part of '../fluera_canvas_screen.dart';

/// 🧠 CONSCIOUS ARCHITECTURE — Production wiring for the five intelligence
/// layers into the canvas lifecycle.
///
/// Phase 4 gap fixes:
/// 1. Canvas controller listener → context push on zoom/pan
/// 2. Tool switch context push
/// 3. AccessibilityAdapter + DesignLinterAdapter callback wiring
/// 4. AdaptiveProfile recommendation consumption (via idle apply)
/// 5. SmartSnapAdapter threshold piped into SmartSnapEngine
///
/// Phase 5 data-flow fixes:
/// - TileCacheManager reads directional margins from AnticipatoryTilePrefetch
/// - SemanticsService.sendAnnouncement for real screen reader support
/// - Cached DesignLinter instance (no per-tick recreation)
///
/// Phase 6 polish:
/// - Mutable SmartSnapEngine.threshold (no engine recreation)
/// - Transform listener skips rotation-only changes
/// - EventBus integration for subsystem outputs
/// - AdaptiveProfile persistence (save/restore via path_provider)
extension ConsciousArchitectureWiring on _FlueraCanvasScreenState {
  // ─────────────────────────────────────────────────────────────────────────
  // Init — called from initState()
  // ─────────────────────────────────────────────────────────────────────────

  /// Register all intelligence subsystems and start the idle timer.
  void _initConsciousArchitecture() {
    final arch = EngineScope.current.consciousArchitecture;

    // (L1 — AnticipatoryTilePrefetch removed: tile caching no longer used)

    // ── L2 — Adaptive (with cross-session persistence) ──
    final profile = AdaptiveProfile();
    profile.restoreFromPrefs(); // Fire-and-forget restore
    arch.register(profile);

    // ── L3 — Invisible ──
    arch.register(SmartSnapAdapter());
    arch.register(SmartAnimateAdapter());

    // Wire AccessibilityAdapter with real SemanticsService callbacks.
    final a11yAdapter = AccessibilityAdapter();
    a11yAdapter.onNeedsRebuild = () {
      final view = WidgetsBinding.instance.platformDispatcher.implicitView;
      if (view != null) {
        SemanticsService.sendAnnouncement(
          view,
          'Canvas updated',
          TextDirection.ltr,
        );
      }
    };
    a11yAdapter.onAnnounce = (message) {
      final view = WidgetsBinding.instance.platformDispatcher.implicitView;
      if (view != null) {
        SemanticsService.sendAnnouncement(view, message, TextDirection.ltr);
      }
    };
    arch.register(a11yAdapter);

    // ── L4 — Generative ──
    // Cache DesignLinter + rules once (avoids recreating 4 Rule objects per tick).
    final cachedLinter =
        DesignLinter()
          ..addRule(MissingA11yLabelRule())
          ..addRule(ConstraintConflictRule())
          ..addRule(DeepNestingRule())
          ..addRule(UnnamedNodeRule());
    final linterAdapter = DesignLinterAdapter();
    linterAdapter.onLintRequested = () {
      try {
        final violations = cachedLinter.lint(_layerController.sceneGraph);
        final count = violations.length;
        // Emit lint result via EventBus so debug overlay / UI can react.
        EngineScope.current.eventBus.emit(
          LintCompletedEvent(violationCount: count),
        );
        return count;
      } catch (_) {
        return 0;
      }
    };
    arch.register(linterAdapter);

    // Wire StyleCoherenceEngine — per-document style learning.
    final styleEngine = EngineScope.current.styleCoherenceEngine;
    styleEngine.setCanvasId(_canvasId);
    styleEngine.eventBus = EngineScope.current.eventBus;
    styleEngine.clearAllManualOverrides(); // Fresh session
    styleEngine.restoreFromPrefs(); // Fire-and-forget restore
    styleEngine.onToolSwitchRecommendation = (color, strokeWidth, opacity) {
      // Auto-apply learned defaults when the user switches tools.
      if (color != null) _toolController.setColor(color);
      if (strokeWidth != null) _toolController.setStrokeWidth(strokeWidth);
      if (opacity != null) _toolController.setOpacity(opacity);
      if (mounted) setState(() {});
    };
    arch.register(styleEngine);

    // ── Gap 1: Listen to canvas controller for zoom/pan changes ──
    // Store initial transform snapshot for the filter (Fix 2).
    _consciousLastScale = _canvasController.scale;
    _consciousLastOffsetX = _canvasController.offset.dx;
    _consciousLastOffsetY = _canvasController.offset.dy;
    _canvasController.addListener(_onCanvasTransformChanged);

    // ── Start idle detection ──
    _consciousIdleStart = DateTime.now();
    _consciousIdleTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted) return;
      final idle = DateTime.now().difference(_consciousIdleStart!);
      if (idle.inMilliseconds >= 500) {
        final arch = EngineScope.current.consciousArchitecture;
        arch.notifyIdle(idle);

        // ── Gap 4: Apply AdaptiveProfile recommendations during idle ──
        _applyAdaptiveRecommendations(arch);

        // ── Gap 5: Sync snap threshold from adapter to engine ──
        _syncSmartSnapThreshold(arch);
      }
    });

    // ── Emit initial context ──
    _pushConsciousContext();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Gap 1: Canvas transform listener (zoom/pan) — with rotation filter
  // ─────────────────────────────────────────────────────────────────────────

  /// Called by [InfiniteCanvasController] on every transform change.
  /// Throttled to 100ms AND filtered: only pushes context when scale or
  /// pan offset actually changed (skips rotation-only updates).
  void _onCanvasTransformChanged() {
    final now = DateTime.now().millisecondsSinceEpoch;
    // Throttle: push at most every 100ms.
    if (now - _consciousLastTransformPushMs < 100) return;

    // Filter: skip if only rotation changed (not zoom/pan).
    final scale = _canvasController.scale;
    final dx = _canvasController.offset.dx;
    final dy = _canvasController.offset.dy;
    if ((scale - _consciousLastScale).abs() < 0.001 &&
        (dx - _consciousLastOffsetX).abs() < 0.5 &&
        (dy - _consciousLastOffsetY).abs() < 0.5) {
      return; // Rotation-only change — skip.
    }
    _consciousLastScale = scale;
    _consciousLastOffsetX = dx;
    _consciousLastOffsetY = dy;

    _consciousLastTransformPushMs = now;
    _pushConsciousContext();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Gap 2: Tool switch context push
  // ─────────────────────────────────────────────────────────────────────────

  /// Call whenever the active tool changes. This should be invoked from
  /// the toolbar after any tool toggle.
  void _onConsciousToolChanged() {
    _pushConsciousContext();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Context — call whenever zoom/pan/tool/drawing state changes
  // ─────────────────────────────────────────────────────────────────────────

  /// Derive the current tool name from tool controller state.
  String _consciousToolName() {
    if (_effectiveIsEraser) return 'eraser';
    if (_effectiveIsLasso) return 'lasso';
    if (_effectiveIsPanMode) return 'pan';
    if (_effectiveIsDigitalText) return 'text';
    if (_effectiveIsFill) return 'fill';
    return _effectivePenType.name; // 'pen', 'marker', 'highlighter', etc.
  }

  /// Build and push the current EngineContext to all subsystems.
  void _pushConsciousContext() {
    EngineScope.current.consciousArchitecture.notifyContextChanged(
      EngineContext(
        activeTool: _consciousToolName(),
        zoom: _canvasController.scale,
        panVelocity: _canvasController.panVelocity,
        isDrawing: _isDrawingNotifier.value,
        strokeCount: _layerController.activeLayer?.strokes.length ?? 0,
        isPdfDocument: _pdfProviders.isNotEmpty,
      ),
    );
    // Reset idle timer — user is active.
    _consciousIdleStart = DateTime.now();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Gap 4: Consume AdaptiveProfile recommendations + EventBus emit
  // ─────────────────────────────────────────────────────────────────────────

  /// Read recommendations from AdaptiveProfile and apply them to the engine.
  /// Emits [ProfileRecommendationsChangedEvent] via EventBus when values change.
  void _applyAdaptiveRecommendations(ConsciousArchitecture arch) {
    final profile = arch.find<AdaptiveProfile>();
    if (profile == null || !profile.isActive) return;

    // 🚫 Stabilizer level is now user-controlled only (via toolbar slider).
    // The string-pulling algorithm creates a physical deadzone per level,
    // so auto-overriding it causes unexpected lag for the user.
    // Previously: _drawingHandler.stabilizerLevel = level;
    bool changed = false;

    // Tile prefetch was removed — tile caching is no longer used.
    final normalizedBias = 1.0;

    // Emit EventBus event if recommendations changed.
    if (changed) {
      EngineScope.current.eventBus.emit(
        ProfileRecommendationsChangedEvent(
          stabilizerLevel: _drawingHandler.stabilizerLevel,
          prefetchBias: normalizedBias,
        ),
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Gap 5: Sync SmartSnapAdapter threshold → SmartSnapEngine (mutable)
  // ─────────────────────────────────────────────────────────────────────────

  /// If smart snap is enabled, sync the zoom-adaptive threshold from the
  /// adapter into the live SmartSnapEngine instance using the mutable setter.
  /// Emits [SnapThresholdChangedEvent] via EventBus when threshold changes.
  void _syncSmartSnapThreshold(ConsciousArchitecture arch) {
    if (!_isSmartSnapEnabled || _smartSnapEngine == null) return;
    final adapter = arch.find<SmartSnapAdapter>();
    if (adapter == null || !adapter.isActive) return;

    final current = _smartSnapEngine!;
    if (current.threshold != adapter.snapThreshold) {
      // Mutable setter — no engine recreation, zero GC pressure.
      current.threshold = adapter.snapThreshold;

      EngineScope.current.eventBus.emit(
        SnapThresholdChangedEvent(threshold: adapter.snapThreshold),
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Dispose — called from dispose()
  // ─────────────────────────────────────────────────────────────────────────

  /// Stop idle timer, remove canvas listener, persist profiles.
  void _disposeConsciousArchitecture() {
    _consciousIdleTimer?.cancel();
    _consciousIdleTimer = null;
    _canvasController.removeListener(_onCanvasTransformChanged);

    // Persist AdaptiveProfile for cross-session learning.
    final arch = EngineScope.current.consciousArchitecture;
    arch.find<AdaptiveProfile>()?.saveToPrefs();

    // Persist StyleCoherenceEngine for cross-session style memory.
    EngineScope.current.styleCoherenceEngine.saveToPrefs();
  }
}
