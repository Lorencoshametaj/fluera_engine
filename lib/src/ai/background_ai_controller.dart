// ============================================================================
// 🆓 BACKGROUND AI CONTROLLER — Fluera-absorbed free background AI orchestrator
//
// See plan: /home/lorenzo/.claude/plans/perfetto-fai-un-piano-dreamy-kite.md
//
// Coordinates two trigger paths that resolve cluster titles + clean OCR
// WITHOUT consuming user credits (Fluera absorbs the Gemini Flash Lite
// cost, ~$0.0002/cluster):
//
//   • Idle 5 s post-stroke — debounce timer reset on every stroke commit.
//     Fires `_processBatch` when the canvas has been idle for 5 seconds,
//     batch-processing every cluster that has raw OCR but no AI title.
//
//   • First dezoom < 0.30 — edge-triggered when the user pinches out toward
//     semantic mode (`SemanticMorphController.morphStartScale`). Forces an
//     immediate batch so the morph never reveals raw OCR titles. Resets
//     when the user zooms back above 0.30 so a second dezoom re-arms it.
//
// Guards:
//   • Cold-start defer (2 s) — avoids hammering the AI during canvas open
//   • App-pause cancellation — timer killed in didChangeAppLifecycleState
//   • Provider readiness check (`provider.isInitialized`)
//   • Signature dedup — `Map<String, int> _lastBatchSignatures` skips
//     clusters whose stroke set + text haven't changed since last batch
//   • Cap exceeded → silent skip, broadcast on
//     `AiCreditsController.backgroundCapEvents` (banner UI subscribes)
//   • `maxBatchSize` cap (default 50) — anti-stampede on big canvases
//
// The controller is per-canvas (member variable on `_FlueraCanvasScreenState`),
// not a singleton, so multi-canvas sessions don't collide on the same
// debounce timer. Disposed alongside the canvas screen.
// ============================================================================

import 'dart:async';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';

import '../canvas/ai/cluster_concept_index.dart';
import '../reflow/content_cluster.dart';
import 'ai_provider.dart';
import 'credits/ai_credits_controller.dart';

/// 🆓 Status of the free-background AI pipeline at any moment.
///
/// Set by `BackgroundAiController` at every exit point of `_processBatch`
/// + the pre-flight check. Observable via [BackgroundAiController.gate].
///
/// Exposed so callers (a dev-mode debug overlay, host telemetry) can react
/// to changes without having to grep `debugPrint` output.
enum BackgroundAiGate {
  /// All preconditions satisfied; controller is armed and waiting on the
  /// next idle / dezoom trigger.
  ready,

  /// No Supabase session detected. Background AI requires login because
  /// the per-tier cap is server-enforced. Resolves on auth state change.
  notAuthenticated,

  /// `providerFn()` returned `null` (no atlas provider in
  /// `EngineScope.current`).
  providerNull,

  /// `provider.isInitialized == false` and `provider.initialize()` threw
  /// or returned with the provider still not ready. Usually means the
  /// Gemini API key is missing or wrong.
  providerColdInitFailed,

  /// `consentFn()` returned false — user opted out via Settings
  /// (`backgroundAiEnabled = false`).
  consentOff,

  /// Server-side per-tier monthly cap reached
  /// (`record_background_ai` returned `error=cap_exceeded`). Resolves on
  /// next monthly rollover or tier upgrade.
  capExceeded,

  /// `record_background_ai` returned `error=rate_limited` (>200 calls/h).
  /// Auto-recovers on next idle cycle.
  rateLimited,

  /// `recordBackgroundCall` threw or returned an unmapped failure
  /// (network / Postgrest exception).
  networkError,

  /// `_buildPending` returned empty and exhausted its retry budget.
  /// Usually means the cluster cache has no rows with OCR text yet (e.g.
  /// drawings-only canvas, or MyScript pipeline not awakened).
  ocrTextNotReady,

  /// First processing attempt — initial state before any signal observed.
  initial,
}

class BackgroundAiController {
  BackgroundAiController({
    required this.providerFn,
    required this.indexFn,
    required this.clustersFn,
    required this.clusterTextsFn,
    this.creditsControllerFn,
    this.consentFn,
    this.viewportFn,
    this.isAuthenticatedFn,
    this.idleDuration = const Duration(seconds: 5),
    this.coldStartDelay = const Duration(seconds: 2),
    this.maxBatchSize = 50,
  });

  /// Returns the active AI provider. Wrapped in a closure because the
  /// provider is injected via `EngineScope.current.atlasProvider` which
  /// can change across canvas opens (auth refresh, theme change, etc.).
  final AiProvider? Function() providerFn;

  /// Returns the per-canvas `ClusterConceptIndex` instance.
  final ClusterConceptIndex Function() indexFn;

  /// Returns the current cluster list (rebuilt by `ClusterDetector`
  /// post-stroke). Read every batch.
  final List<ContentCluster> Function() clustersFn;

  /// Returns the cluster-id → recognised-text map. The index uses this as
  /// the raw OCR source; we read the same map for dedup signatures.
  final Map<String, String> Function() clusterTextsFn;

  /// Optional AI credits controller — used for the server-side cap check.
  /// When `null` (or returning null), the controller still proceeds with
  /// background AI but skips the cap RPC (suitable for tests / offline).
  final AiCreditsController? Function()? creditsControllerFn;

  /// Optional consent gate. When the host's `cognitive_preferences` reports
  /// `backgroundAiEnabled == false`, returning `false` here short-circuits
  /// every batch. Default `null` → always allowed (engine default + tests).
  final bool Function()? consentFn;

  /// Optional viewport bounds resolver (canvas-space rect). When provided,
  /// `_buildPending` sorts clusters so the ones intersecting the current
  /// viewport are processed FIRST within the `maxBatchSize` window —
  /// the user gets AI titles for what they're looking at before the
  /// off-screen tail. Returning `null` disables the prioritisation and
  /// falls back to the natural `clustersFn` order.
  final Rect? Function()? viewportFn;

  /// Optional authentication probe. Returns `true` when the host's auth
  /// session is active (e.g. a Supabase user is signed in), `false`
  /// otherwise.
  ///
  /// When omitted, the pre-flight falls back to
  /// `creditsControllerFn?.credits.value != null` as a heuristic (the
  /// credits snapshot is `null` until `refresh()` succeeds against an
  /// authenticated session). The dedicated callback is preferred when
  /// the host has a direct auth observer.
  final bool Function()? isAuthenticatedFn;

  /// Idle window after the last stroke commit before a batch fires.
  final Duration idleDuration;

  /// Grace period after canvas open during which no background AI fires
  /// (lets the LOD pipeline + render warm up first).
  final Duration coldStartDelay;

  /// Maximum cluster count per batch. Avoids submitting 10 000-cluster
  /// canvases to Gemini in a single call (would hit context window and
  /// would also blow past the per-feature rate limit).
  final int maxBatchSize;

  // ── Internal state ──────────────────────────────────────────────────────

  Timer? _idleTimer;
  Timer? _coldStartTimer;
  Timer? _providerReadyRetryTimer;
  bool _hasFiredDezoomBelow30 = false;
  bool _isPaused = false;
  bool _isColdStarting = false;
  bool _disposed = false;
  bool _isProcessing = false;
  /// 🔧 2026-05-18: two SEPARATE counters. Sharing one was a bug — the
  /// "provider came online" reset zeroed the counter every call, which
  /// then incremented to 1 again on pending-empty, scheduled a retry,
  /// and looped forever (every retry logged "1/5"). Splitting:
  ///   • `_providerNotReadyAttempts`  — provider.initialize() failures
  ///   • `_emptyPendingRetries`        — pending-empty retries (OCR not
  ///                                       ready yet)
  /// Each is reset only when its own success condition fires.
  int _providerNotReadyAttempts = 0;
  int _emptyPendingRetries = 0;
  static const int _maxProviderNotReadyAttempts = 5;
  static const int _maxEmptyPendingRetries = 5;

  /// `clusterId → Object.hash(strokeIds.length, text)`. Skip a cluster
  /// when its signature matches the last batch — the AI already saw this
  /// exact content.
  final Map<String, int> _lastBatchSignatures = {};

  /// One-shot callback the host can subscribe to so it can surface a
  /// non-blocking banner when the per-tier cap fires. Mirrors the pattern
  /// of `AiCreditsController.backgroundCapEvents` but kept per-controller
  /// so canvas screens can react locally (e.g. show toast above this
  /// canvas only).
  VoidCallback? onCapExceeded;

  /// 🆓 Observable gate state — set at every `_processBatch` exit point
  /// + at the end of `_logPreflightStatus`. Lets a debug overlay (or
  /// future host instrumentation) display "why is background AI not
  /// firing" without scraping `debugPrint` output.
  ///
  /// Starts at [BackgroundAiGate.initial] and transitions to
  /// [BackgroundAiGate.ready] once the pre-flight check passes.
  final ValueNotifier<BackgroundAiGate> gate =
      ValueNotifier<BackgroundAiGate>(BackgroundAiGate.initial);

  // ── Public API ──────────────────────────────────────────────────────────

  /// Call exactly once after the canvas finishes loading. Starts the
  /// cold-start grace period and prints the pre-flight diagnostic block.
  void onCanvasOpened() {
    if (_disposed) return;
    debugPrint(
        '🆓 BackgroundAi: canvas opened — cold-start window ${coldStartDelay.inSeconds}s');
    _isColdStarting = true;
    _coldStartTimer?.cancel();
    _coldStartTimer = Timer(coldStartDelay, () {
      _isColdStarting = false;
      debugPrint('🆓 BackgroundAi: cold-start ended');
    });
    // 🔍 2026-05-18: surface every gate UP-FRONT instead of discovering
    // them sequentially across device runs. See plan
    // `.claude/plans/perfetto-fai-un-piano-dreamy-kite.md`.
    _logPreflightStatus();
  }

  /// 🔍 Dumps the current state of every precondition the controller
  /// checks before firing a batch — auth, provider, consent, cluster
  /// cache, viewport, credits snapshot — in a single log block.
  ///
  /// Called automatically from [onCanvasOpened]. Side-effect-free
  /// (no RPC calls, no AI calls); reads cached state only. Updates
  /// [gate] to a non-`ready` value when a gate is clearly closed,
  /// otherwise leaves it untouched so `_processBatch` can refine.
  void _logPreflightStatus() {
    final provider = providerFn();
    final consent = consentFn?.call() ?? true;
    final credits = creditsControllerFn?.call();
    final snapshot = credits?.credits.value;
    final authResolver = isAuthenticatedFn;
    final isAuth = _isAuthenticatedNow();
    final clusters = clustersFn();
    final texts = clusterTextsFn();
    final clustersWithText =
        clusters.where((c) => (texts[c.id] ?? '').isNotEmpty).length;
    final clustersWithTitle = clusters
        .where((c) => (indexFn().peek(c.id)?.title ?? '').isNotEmpty)
        .length;
    final viewport = viewportFn?.call();

    String providerLabel;
    if (provider == null) {
      providerLabel = 'NULL (no EngineScope.atlasProvider)';
    } else if (provider.isInitialized) {
      providerLabel = 'READY';
    } else {
      providerLabel = 'COLD (will lazy-initialize on first batch)';
    }

    String authLabel;
    if (authResolver != null) {
      authLabel = isAuth ? 'signed_in' : 'NOT_SIGNED_IN';
    } else if (credits == null) {
      authLabel = 'n/a (engine standalone, no credits controller)';
    } else {
      authLabel = isAuth
          ? 'signed_in (heuristic: credits snapshot present)'
          : 'NOT_SIGNED_IN (heuristic: credits snapshot null)';
    }

    String creditsLabel;
    if (credits == null) {
      creditsLabel = 'NULL (engine running without host credits controller)';
    } else if (snapshot == null) {
      creditsLabel = 'controller present, snapshot=null';
    } else {
      creditsLabel = 'tier=${snapshot.tier} '
          'monthly=${snapshot.monthlyCredits} pack=${snapshot.packCredits}';
    }

    debugPrint('🆓 BackgroundAi preflight:');
    debugPrint('  • auth      : $authLabel');
    debugPrint('  • provider  : $providerLabel');
    debugPrint('  • consent   : ${consent ? "ON" : "OFF"}');
    debugPrint('  • credits   : $creditsLabel');
    debugPrint(
        '  • clusters  : total=${clusters.length} withText=$clustersWithText '
        'withTitle=$clustersWithTitle');
    debugPrint('  • viewport  : ${viewport ?? "n/a"}');

    // Set the gate to the first failed precondition we can observe
    // locally. `_processBatch` will refine it (cap, rate, network) once
    // it actually attempts an RPC.
    if (!isAuth) {
      gate.value = BackgroundAiGate.notAuthenticated;
    } else if (provider == null) {
      gate.value = BackgroundAiGate.providerNull;
    } else if (!consent) {
      gate.value = BackgroundAiGate.consentOff;
    } else if (clustersWithText == 0 && clusters.isNotEmpty) {
      gate.value = BackgroundAiGate.ocrTextNotReady;
    } else {
      gate.value = BackgroundAiGate.ready;
    }
    debugPrint('  • gate      : ${gate.value.name}');

    // 🔍 Async cap peek (migration 018). Fire-and-forget so canvas open
    // is not blocked by the round-trip. When the response lands we log
    // the cap headroom (or the server-side deny reason) so the user can
    // diagnose "cap exceeded" without waiting for the first idle batch.
    if (credits != null && isAuth) {
      unawaited(_peekAndLog(credits));
    }
  }

  Future<void> _peekAndLog(AiCreditsController credits) async {
    try {
      final peek = await credits.peekBackgroundStatus();
      if (_disposed) return;
      if (peek == null) {
        debugPrint(
            '🔍 BackgroundAi peek: not available (host controller did not '
            'implement peekBackgroundStatus, or migration 018 not deployed)');
        return;
      }
      if (!peek.ok) {
        debugPrint('🔍 BackgroundAi peek: ok=false error=${peek.error}');
        if (peek.error == 'not_authenticated') {
          gate.value = BackgroundAiGate.notAuthenticated;
        }
        return;
      }
      if (peek.allowed) {
        debugPrint(
            '🔍 BackgroundAi peek: cap headroom ${peek.used}/${peek.cap} '
            '(tier=${peek.tier}) — server allows next call');
      } else {
        debugPrint(
            '🔍 BackgroundAi peek: DENIED error=${peek.error} '
            'used=${peek.used}/${peek.cap} tier=${peek.tier}');
        switch (peek.error) {
          case 'consent_off':
            gate.value = BackgroundAiGate.consentOff;
            break;
          case 'cap_exceeded':
            gate.value = BackgroundAiGate.capExceeded;
            break;
          case 'not_authenticated':
            gate.value = BackgroundAiGate.notAuthenticated;
            break;
        }
      }
    } catch (e) {
      debugPrint('🔍 BackgroundAi peek: threw — $e');
    }
  }

  /// Reset the idle timer. Called from `_drawing_end.dart` post-stroke.
  ///
  /// 🔧 2026-05-17 fix: previously the cold-start window suppressed
  /// strokes committed in the first 2 s after canvas open, but real
  /// users typically start writing immediately. If they then stop
  /// (single-stroke session), `onStrokeCommitted` would never fire
  /// again and the batch never ran. We now schedule the timer always;
  /// during the cold-start window we just stretch the delay to
  /// `coldStartDelay + idleDuration` so the batch fires AFTER cold
  /// start ends, never before.
  void onStrokeCommitted() {
    if (_disposed || _isPaused) return;
    _idleTimer?.cancel();
    final delay = _isColdStarting
        ? coldStartDelay + idleDuration
        : idleDuration;
    debugPrint(
        '🆓 BackgroundAi: stroke committed — idle timer armed for '
        '${delay.inSeconds}s (coldStarting=$_isColdStarting)');
    _idleTimer = Timer(delay, () {
      debugPrint('🆓 BackgroundAi: idle timer fired — kicking batch');
      // unawaited — the controller is fire-and-forget; errors logged inside.
      _processBatch(reason: 'idle');
    });
  }

  /// Notify on every scale change. The controller is edge-triggered: the
  /// first time the scale drops below 0.30 (i.e. the user is entering
  /// semantic mode), force an immediate batch. Subsequent scale changes
  /// in the same dezoom are no-ops; zooming back above 0.30 re-arms the
  /// edge for the next dezoom.
  void onScaleChanged(double scale) {
    if (_disposed || _isPaused) return;
    if (scale < 0.30 && !_hasFiredDezoomBelow30) {
      _hasFiredDezoomBelow30 = true;
      // No debounce — the user is about to see the semantic node and we
      // want the AI title to be ready before the morph completes.
      _processBatch(reason: 'dezoom');
    } else if (scale >= 0.30 && _hasFiredDezoomBelow30) {
      _hasFiredDezoomBelow30 = false;
    }
  }

  /// Lifecycle hooks driven by the host's `didChangeAppLifecycleState`.
  void onAppPaused() {
    if (_disposed) return;
    _isPaused = true;
    _idleTimer?.cancel();
    _providerReadyRetryTimer?.cancel();
  }

  /// Re-arm on app resume. The edge-trigger flag is reset so a fresh
  /// dezoom after backgrounding fires once more — useful when the user
  /// returns to a canvas after several minutes.
  void onAppResumed() {
    if (_disposed) return;
    _isPaused = false;
    _hasFiredDezoomBelow30 = false;
  }

  /// Cancel timers + clear caches. Safe to call multiple times.
  void dispose() {
    _disposed = true;
    _idleTimer?.cancel();
    _coldStartTimer?.cancel();
    _providerReadyRetryTimer?.cancel();
    _lastBatchSignatures.clear();
    onCapExceeded = null;
    gate.dispose();
  }

  // ── Internals ───────────────────────────────────────────────────────────

  /// Visible-for-testing: build the pending map exactly as
  /// `_processBatch` would, without firing any AI call.
  @visibleForTesting
  Map<String, String> pendingForTest() => _buildPending().pending;

  /// Result of [_buildPending]. Carries both the cluster-id → text map
  /// the AI will receive AND a [hasOcrPending] flag distinguishing two
  /// "empty pending" cases:
  ///
  ///   • `hasOcrPending == true`  → at least one cluster has stroke
  ///     content but no OCR text yet (MyScript still recognising).
  ///     The caller schedules a short retry; the text usually lands
  ///     within 500–1500 ms.
  ///   • `hasOcrPending == false` → everything is already titled,
  ///     deduped, or text-empty by structure (drawings-only canvas).
  ///     The caller MUST NOT retry — there's nothing to wait for, and
  ///     re-entering on every dezoom edge would create the
  ///     `retry-retry-retry-…` loop fixed on 2026-05-18.
  ({Map<String, String> pending, bool hasOcrPending}) _buildPending() {
    final texts = clusterTextsFn();
    final index = indexFn();
    final viewport = viewportFn?.call();
    final allClusters = clustersFn();

    // 1. Filter — same predicate as before (text present, no cached title,
    //    signature differs from last batch).
    final eligible = <ContentCluster>[];
    int skippedNoText = 0;
    int skippedTitled = 0;
    int skippedDedup = 0;
    for (final cluster in allClusters) {
      final text = texts[cluster.id];
      if (text == null || text.trim().isEmpty) {
        skippedNoText++;
        continue;
      }
      final existing = index.peek(cluster.id)?.title;
      if (existing != null && existing.trim().isNotEmpty) {
        skippedTitled++;
        continue;
      }
      final sig = Object.hash(cluster.strokeIds.length, text);
      if (_lastBatchSignatures[cluster.id] == sig) {
        skippedDedup++;
        continue;
      }
      eligible.add(cluster);
    }
    debugPrint(
        '🆓 BackgroundAi: _buildPending — clusters=${allClusters.length} '
        'eligible=${eligible.length} skipped(noText=$skippedNoText '
        'titled=$skippedTitled dedup=$skippedDedup)');

    // 2. Viewport prioritisation — clusters whose bounds intersect the
    //    current viewport go first. Within each bucket, preserve the
    //    natural `clustersFn` order so determinism survives.
    if (viewport != null && eligible.length > 1) {
      final visible = <ContentCluster>[];
      final offscreen = <ContentCluster>[];
      for (final c in eligible) {
        if (c.bounds.overlaps(viewport)) {
          visible.add(c);
        } else {
          offscreen.add(c);
        }
      }
      eligible
        ..clear()
        ..addAll(visible)
        ..addAll(offscreen);
    }

    // 3. Build the pending map respecting `maxBatchSize`.
    final pending = <String, String>{};
    for (final c in eligible) {
      if (pending.length >= maxBatchSize) break;
      pending[c.id] = texts[c.id]!;
    }
    return (pending: pending, hasOcrPending: skippedNoText > 0);
  }

  Future<void> _processBatch({required String reason}) async {
    if (_disposed || _isPaused) return;
    // Idempotency guard: if a batch is mid-flight (idle fired and a
    // dezoom forced a second pass before the first returned), skip the
    // duplicate. The first batch will pick up everything anyway.
    if (_isProcessing) return;

    // Auth gate — server cap RPC requires a Supabase session. Resolved
    // by `isAuthenticatedFn` when wired by the host, falls back to the
    // credits-snapshot heuristic.
    if (!_isAuthenticatedNow()) {
      gate.value = BackgroundAiGate.notAuthenticated;
      debugPrint(
          '🆓 BackgroundAi: not authenticated — skipping ($reason). '
          'Background AI requires a Supabase session for the per-tier cap.');
      return;
    }

    // Consent gate — host-controlled, lets the user opt out from Settings.
    if (consentFn != null && !consentFn!()) {
      gate.value = BackgroundAiGate.consentOff;
      debugPrint('🆓 BackgroundAi: consent off — skipping ($reason)');
      return;
    }

    final provider = providerFn();
    if (provider == null) {
      gate.value = BackgroundAiGate.providerNull;
      debugPrint('🆓 BackgroundAi: provider null — skipping ($reason)');
      return;
    }
    // 🔧 2026-05-17 (lazy init fix): mirror the pattern used by every
    // other consumer in the codebase (`_proactive_analysis.dart`,
    // `_semantic_titles.dart`, …) — the GeminiProvider exposes
    // `isInitialized` and an `initialize()` future that does the real
    // setup (system prompts, model handshake). Without this call the
    // provider stays dormant forever even with a valid API key.
    if (!provider.isInitialized) {
      try {
        await provider.initialize();
      } catch (e) {
        _providerNotReadyAttempts++;
        if (_providerNotReadyAttempts <= _maxProviderNotReadyAttempts) {
          final backoff =
              Duration(seconds: 1 << (_providerNotReadyAttempts - 1));
          debugPrint(
              '🆓 BackgroundAi: provider.initialize() failed — retry '
              '$_providerNotReadyAttempts/$_maxProviderNotReadyAttempts '
              'in ${backoff.inSeconds}s ($reason): $e');
          _providerReadyRetryTimer?.cancel();
          _providerReadyRetryTimer = Timer(backoff, () {
            if (!_disposed && !_isPaused) {
              _processBatch(reason: 'retry-$reason');
            }
          });
        } else {
          gate.value = BackgroundAiGate.providerColdInitFailed;
          debugPrint(
              '🆓 BackgroundAi: provider.initialize() failed after '
              '$_maxProviderNotReadyAttempts retries — giving up ($reason). '
              'Check the Gemini API key in Settings → AI. Last error: $e');
        }
        return;
      }
    }
    if (!provider.isInitialized) {
      gate.value = BackgroundAiGate.providerColdInitFailed;
      debugPrint(
          '🆓 BackgroundAi: provider still not initialized post-init — '
          'skipping ($reason)');
      return;
    }
    // Reset retry counter — provider came online.
    _providerNotReadyAttempts = 0;

    final build = _buildPending();
    final pending = build.pending;
    if (pending.isEmpty) {
      // 🔧 2026-05-18 fix: distinguish "OCR-in-flight" from "nothing to
      // do". When at least one cluster has stroke content but no
      // recognised text yet (MyScript still running), retry after 2 s —
      // the text usually lands within 500–1500 ms. When every cluster
      // is already titled / deduped / drawings-only, EXIT — there is
      // nothing the AI can act on, and re-entering on every dezoom
      // edge would create the `retry-retry-retry-…-dezoom` loop seen
      // on the 2026-05-18 device session.
      if (!build.hasOcrPending) {
        // Nothing pending means we're caught up; reset both counters
        // so the next stroke commit / dezoom starts fresh.
        _emptyPendingRetries = 0;
        debugPrint(
            '🆓 BackgroundAi: nothing to do — all clusters already titled / '
            'deduped / drawings-only ($reason)');
        return;
      }

      _emptyPendingRetries++;
      if (_emptyPendingRetries <= _maxEmptyPendingRetries) {
        final backoff = const Duration(seconds: 2);
        debugPrint(
            '🆓 BackgroundAi: pending empty (cluster texts not ready yet) — '
            'retry ${_emptyPendingRetries}/$_maxEmptyPendingRetries in '
            '${backoff.inSeconds}s ($reason)');
        _providerReadyRetryTimer?.cancel();
        _providerReadyRetryTimer = Timer(backoff, () {
          if (!_disposed && !_isPaused) _processBatch(reason: 'retry-$reason');
        });
      } else {
        gate.value = BackgroundAiGate.ocrTextNotReady;
        debugPrint(
            '🆓 BackgroundAi: pending stayed empty after '
            '$_maxEmptyPendingRetries retries — likely no cluster has '
            'OCR text (canvas might be drawings only).');
        _emptyPendingRetries = 0;
      }
      return;
    }
    // Pending non-empty → reset BOTH retry counters.
    _emptyPendingRetries = 0;

    // Server-side cap check (1 RPC per batch, not per cluster).
    final credits = creditsControllerFn?.call();
    if (credits != null) {
      bool allowed;
      try {
        allowed =
            await credits.recordBackgroundCall(clusterCount: pending.length);
      } catch (e) {
        gate.value = BackgroundAiGate.networkError;
        debugPrint(
            '🆓 BackgroundAi: recordBackgroundCall threw — skipping ($reason): $e');
        return;
      }
      if (!allowed) {
        // RPC outcomes other than cap_exceeded are silent. The Supabase
        // controller broadcasts the exception itself; we just notify the
        // local callback so the per-canvas UI can react too. We can't
        // tell the exact deny reason from the boolean — the granular log
        // emitted by SupabaseAiCreditsController.recordBackgroundCall
        // discriminates auth vs consent vs cap vs rate vs network. The
        // gate value defaults to `capExceeded` since that's the most
        // common case once auth/consent are verified by the pre-flight.
        gate.value = BackgroundAiGate.capExceeded;
        onCapExceeded?.call();
        debugPrint(
            '🆓 BackgroundAi: server denied call — skipping ($reason). See '
            'the preceding `recordBackgroundCall denied:` log for the '
            'specific reason (auth / consent / cap / rate / network).');
        return;
      }
    }

    _isProcessing = true;
    try {
      // Snapshot the signatures BEFORE the call so a stroke committed
      // mid-flight doesn't clobber them (the next batch will recompute).
      final newSignatures = <String, int>{
        for (final entry in pending.entries)
          entry.key: Object.hash(
            _strokeIdsLengthFor(entry.key),
            entry.value,
          ),
      };

      // 🔁 Retry with exponential backoff (1 s → 2 s → 4 s) on transient
      // failures. Each `bulkGenerateTitles` call already catches its own
      // exceptions internally, so the retry here is only triggered when
      // the call throws (network drop, TimeoutException, server 503).
      // Cap at 3 attempts so we don't burn the Gemini quota on a
      // genuinely unavailable backend.
      Object? lastError;
      for (var attempt = 0; attempt < 3; attempt++) {
        if (_isPaused || _disposed) return;
        try {
          await indexFn().bulkGenerateTitles(
            pending,
            isFreeBackground: true,
          );
          lastError = null;
          break;
        } catch (e) {
          lastError = e;
          if (attempt < 2) {
            final backoff = Duration(seconds: 1 << attempt);
            debugPrint(
                '🆓 BackgroundAi: batch ($reason) attempt ${attempt + 1} failed — '
                'retrying in ${backoff.inSeconds}s ($e)');
            await Future<void>.delayed(backoff);
          }
        }
      }

      if (lastError != null) {
        // All 3 attempts failed — give up. The next stroke commit will
        // re-arm the idle timer; signatures are NOT committed so the
        // cluster stays in the pending queue.
        debugPrint(
            '🆓 BackgroundAi: batch ($reason) gave up after 3 attempts — $lastError');
        return;
      }

      // 🧹 2026-05-18: also run cleanOcr for each cluster so the
      // mini-card (and Atlas Chat / Socratic when they read the
      // concept) see normalised text instead of MyScript raw — the
      // user-visible bug was a card showing
      //   🔑 Prima · Lelle · Newtn
      //   📝 Prima lelle o' newtn
      // even though the title bar correctly read "Leggi di Newton".
      //
      // Triggers `resolve(needsCleanedOcr: true, isFreeBackground:
      // true)` per cluster, in parallel; the index reuses the rawOcr
      // already cached by `setTitle` above, so this is effectively N
      // parallel `provider.cleanOcr` calls. Errors per-cluster are
      // swallowed — a failed cleanup just leaves rawOcr visible.
      final clusterMap = {for (final c in clustersFn()) c.id: c};
      final cleanFutures = <Future<void>>[];
      for (final cid in pending.keys) {
        final cluster = clusterMap[cid];
        if (cluster == null) continue;
        cleanFutures.add(() async {
          if (_disposed || _isPaused) return;
          try {
            await indexFn().resolve(
              cluster,
              needsCleanedOcr: true,
              isFreeBackground: true,
            );
          } catch (e) {
            debugPrint(
                '🧹 BackgroundAi: cleanOcr failed for cluster $cid ($e)');
          }
        }());
      }
      if (cleanFutures.isNotEmpty) {
        await Future.wait(cleanFutures);
      }

      // Commit signatures so we don't re-process unchanged clusters.
      _lastBatchSignatures.addAll(newSignatures);
      gate.value = BackgroundAiGate.ready;
      debugPrint(
          '🆓 BackgroundAi: batch ($reason) processed ${pending.length} clusters');
    } finally {
      _isProcessing = false;
    }
  }

  int _strokeIdsLengthFor(String clusterId) {
    for (final c in clustersFn()) {
      if (c.id == clusterId) return c.strokeIds.length;
    }
    return 0;
  }

  /// Resolve the current auth state, preferring the explicit
  /// [isAuthenticatedFn] probe and falling back to a credits-snapshot
  /// heuristic when no probe was wired.
  ///
  /// Semantics:
  ///   • Explicit probe (`isAuthenticatedFn != null`) → trust it verbatim.
  ///   • No probe AND no credits controller → engine running without a
  ///     host, no auth concept exists → return `true` so SDK builds and
  ///     tests proceed.
  ///   • No probe but credits controller present → credits snapshot
  ///     becomes non-null only after `refresh()` succeeds against an
  ///     authenticated session, so `snapshot != null` is a reliable
  ///     proxy for "signed in".
  bool _isAuthenticatedNow() {
    final fn = isAuthenticatedFn;
    if (fn != null) return fn();
    final credits = creditsControllerFn?.call();
    if (credits == null) return true; // engine standalone
    return credits.credits.value != null;
  }
}
