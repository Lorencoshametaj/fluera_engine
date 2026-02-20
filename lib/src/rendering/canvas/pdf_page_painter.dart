import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../core/engine_scope.dart';
import '../../core/engine_error.dart';
import '../../core/nodes/pdf_page_node.dart';
import '../../canvas/nebula_canvas_config.dart';
import '../../platform/native_performance_monitor.dart';
import './pdf_memory_budget.dart';
import './pdf_disk_cache.dart';
import './pdf_render_stats.dart';

/// 🎨 Painter for PDF pages with LOD-aware caching, concurrency-limited
/// render queue, progressive rendering, render cancellation, debounced LOD
/// upgrades, budget auto-refresh, and queue flushing.
///
/// Works with [PdfPageNode] to manage raster tile lifecycles:
/// 1. Check if a cached image exists at the required LOD
/// 2. If YES at correct LOD → draw it
/// 3. If cache exists at WRONG LOD → draw stale cache + schedule upgrade
/// 4. If NO cache → draw placeholder + schedule decode
///
/// Key features:
/// - **Render queue**: Max [_kMaxConcurrent] simultaneous native renders
/// - **Progressive LOD**: Stale cache shown during LOD upgrade (no flicker)
/// - **Cancellation**: Monotonic generation IDs reject stale render results
/// - **LRU eviction**: Oldest-drawn pages evicted first under memory pressure
/// - **LOD debounce**: Upgrades delayed 150ms during active zoom
/// - **Budget auto-refresh**: Refreshed from [NativePerformanceMonitor] every 60 frames
/// - **Queue flush**: Stale queue entries purged on each paint cycle
class PdfPagePainter {
  final NebulaPdfProvider? _provider;
  final PdfMemoryBudget _memoryBudget;
  final PdfDiskCache? _diskCache;

  /// 📊 Telemetry for this painter.
  final PdfRenderStats stats = PdfRenderStats();

  /// Public access to the memory budget for multi-document coordination.
  PdfMemoryBudget get memoryBudget => _memoryBudget;

  /// Global max active renders across all painters (shared pool).
  static const int _kGlobalMaxThreads = 6;

  /// Max active renders for THIS painter (dynamic share of global pool).
  int get maxConcurrent =>
      (_kGlobalMaxThreads / _memoryBudget.activeDocumentCount).ceil().clamp(
        2,
        _kGlobalMaxThreads,
      );

  /// Debounce duration for LOD upgrades during active zoom.
  static const Duration _kLodDebounceDuration = Duration(milliseconds: 300);

  /// Frames between budget auto-refresh checks.
  static const int _kBudgetRefreshInterval = 60;

  /// Active render count.
  int _activeRenders = 0;

  /// Priority queue of pending render requests (visible pages first).
  final Queue<_RenderRequest> _renderQueue = Queue<_RenderRequest>();

  /// Set of node IDs with the latest generation (prevent duplicates).
  final Map<String, int> _pendingGenerations = {};

  /// Monotonic generation counter for render cancellation.
  int _generation = 0;

  /// Total cached bytes across all managed pages.
  int _totalCachedBytes = 0;

  /// Whether this painter has been disposed.
  bool _isDisposed = false;

  /// Monotonic draw counter for LRU ordering.
  int _drawCounter = 0;

  /// LOD debounce timer — delays upgrades during active zoom.
  Timer? _lodDebounceTimer;

  /// Pending LOD upgrade requests waiting for debounce to settle.
  final Map<String, _RenderRequest> _debouncedRequests = {};

  /// Last zoom value seen — used to detect active zooming.
  double _lastZoom = 1.0;

  /// Track all pages managed by this painter for LRU eviction.
  final Set<PdfPageNode> _knownPages = {};

  /// Last viewport seen during painting — used by LRU eviction.
  Rect _lastViewport = Rect.zero;

  /// Viewport center for distance-based priority sorting.
  Offset _viewportCenter = Offset.zero;

  /// Previous viewport center — for computing scroll direction.
  Offset _prevViewportCenter = Offset.zero;

  /// Retry count per page ID — for error recovery with backoff.
  final Map<String, int> _retryCount = {};

  /// Max retries per page before giving up.
  static const int _kMaxRetries = 3;

  /// Fade-in duration in milliseconds.
  static const int _kFadeInMs = 200;

  /// Global stopwatch for fade-in timing.
  static final Stopwatch _fadeStopwatch = Stopwatch()..start();

  /// 📊 Warm-up progress: 0.0 (none) → 1.0 (all pages rendered).
  /// UI can listen to this to show a progress indicator.
  final ValueNotifier<double> warmUpProgress = ValueNotifier<double>(0.0);

  /// Total pages scheduled for warm-up.
  int _warmUpTotal = 0;

  /// Pages that have completed warm-up rendering.
  int _warmUpCompleted = 0;

  /// Frame counter for memory pressure checks.
  int _frameCount = 0;

  /// 🔋 Whether the viewport is actively scrolling (for idle detection).
  bool _isScrolling = false;

  /// Frame counter for throttled stale cleanup.
  int _cleanupFrameCounter = 0;

  /// Frames between stale-cache cleanup passes.
  static const int _kCleanupInterval = 120;

  /// Whether a fade-in repaint is already scheduled.
  bool _fadeInRepaintScheduled = false;

  /// Timer for staggered warm-up batches.
  Timer? _warmUpTimer;

  // Reusable Paint objects to avoid per-frame allocations.
  static final Paint _imagePaint =
      Paint()
        ..filterQuality = FilterQuality.high
        ..isAntiAlias = true;
  static final Paint _placeholderPaint =
      Paint()..color = const Color(0xFFF5F5F5);
  static final Paint _borderPaint =
      Paint()
        ..color = const Color(0xFFE0E0E0)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;

  // Cached TextPainter to avoid per-frame allocation in placeholder.
  static final TextPainter _textPainter = TextPainter(
    textDirection: TextDirection.ltr,
  );
  static const TextStyle _placeholderTextStyle = TextStyle(
    color: Color(0xFFBBBBBB),
    fontSize: 28,
    fontWeight: FontWeight.w300,
    letterSpacing: 1,
  );

  PdfPagePainter({
    required NebulaPdfProvider? provider,
    required PdfMemoryBudget memoryBudget,
    String? documentId,
  }) : _provider = provider,
       _memoryBudget = memoryBudget,
       _diskCache =
           documentId != null ? PdfDiskCache(documentId: documentId) : null;

  // ---------------------------------------------------------------------------
  // Core rendering
  // ---------------------------------------------------------------------------

  /// Paint a [PdfPageNode] onto [canvas].
  ///
  /// Uses **progressive LOD**: if the node has a cached image at the wrong
  /// LOD scale, draws the stale image while scheduling a debounced upgrade.
  /// Only shows placeholder if no cache exists at all.
  void paintPage(
    Canvas canvas,
    PdfPageNode node, {
    required double currentZoom,
    VoidCallback? onNeedRepaint,
    Rect viewport = Rect.zero,
  }) {
    final pageSize = node.pageModel.originalSize;
    final pageRect = Rect.fromLTWH(0, 0, pageSize.width, pageSize.height);

    // Stamp LRU timestamp and track this page
    node.lastDrawnTimestamp = ++_drawCounter;
    _knownPages.add(node);
    if (viewport != Rect.zero) {
      _prevViewportCenter = _viewportCenter;
      _lastViewport = viewport;
      _viewportCenter = viewport.center;
      // 🔋 Idle detection: viewport moved > 2px = scrolling
      _isScrolling = (_viewportCenter - _prevViewportCenter).distance > 2.0;
    }

    // Periodic budget auto-refresh
    _maybeRefreshBudget();

    // Determine target LOD scale
    final baseLod = PdfMemoryBudget.lodScaleForZoom(currentZoom);
    final targetScale = _memoryBudget.clampScale(baseLod);

    // Detect zoom change for debounce (wider threshold to avoid jitter)
    final zoomChanged = (currentZoom - _lastZoom).abs() > 0.05;
    _lastZoom = currentZoom;

    if (node.hasCacheAtScale(targetScale) && node.cachedImage != null) {
      // ✅ Fast path: cache at correct LOD
      stats.recordMemoryHit();
      _drawCachedImage(canvas, node, pageRect, onNeedRepaint: onNeedRepaint);
    } else if (node.cachedImage != null) {
      // 🔄 Progressive path: draw stale cache + schedule upgrade
      _drawCachedImage(canvas, node, pageRect, onNeedRepaint: onNeedRepaint);
      if (zoomChanged) {
        // Debounce during active zoom — don't flood the queue
        _debounceLodUpgrade(node, targetScale, pageRect, onNeedRepaint);
      } else if (!_pendingGenerations.containsKey(node.id)) {
        // Only enqueue if no render is already pending for this page.
        // Without this guard, every paint frame re-enqueues the same page
        // with a new generation, creating a render→repaint→render loop.
        _enqueueRender(
          node,
          targetScale,
          pageRect,
          onNeedRepaint,
          priority: _RenderPriority.visible,
        );
      }
    } else {
      // ⚡ Progressive cold path: render at adaptive LOD first,
      // then the next paint frame will upgrade via the progressive path.
      stats.recordMemoryMiss();
      _drawPlaceholder(canvas, node, pageRect);
      if (!_pendingGenerations.containsKey(node.id)) {
        // Adaptive cold LOD: lower scale at very low zoom
        final double coldScale;
        if (targetScale <= 0.25) {
          coldScale = targetScale; // Already very low
        } else if (currentZoom < 0.3) {
          coldScale = 0.25; // Very low zoom → ultra-fast preview
        } else {
          coldScale = 0.5; // Normal quick preview
        }
        _enqueueRender(
          node,
          coldScale,
          pageRect,
          onNeedRepaint,
          priority: _RenderPriority.visible,
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Image drawing
  // ---------------------------------------------------------------------------

  void _drawCachedImage(
    Canvas canvas,
    PdfPageNode node,
    Rect pageRect, {
    VoidCallback? onNeedRepaint,
  }) {
    final img = node.cachedImage!;
    final srcRect = Rect.fromLTWH(
      0,
      0,
      img.width.toDouble(),
      img.height.toDouble(),
    );

    // 🎬 Smooth fade-in over _kFadeInMs
    final elapsed = _fadeStopwatch.elapsedMilliseconds - node.cacheUpdatedAt;
    if (elapsed < _kFadeInMs) {
      final opacity = (elapsed / _kFadeInMs).clamp(0.0, 1.0);
      final fadePaint =
          Paint()
            ..filterQuality = FilterQuality.high
            ..isAntiAlias = true
            ..color = Color.fromRGBO(255, 255, 255, opacity);
      canvas.drawImageRect(img, srcRect, pageRect, fadePaint);
      // 🔋 Single scheduled repaint for all active fade-ins (no microtask spam)
      if (onNeedRepaint != null && !_fadeInRepaintScheduled) {
        _fadeInRepaintScheduled = true;
        SchedulerBinding.instance.addPostFrameCallback((_) {
          _fadeInRepaintScheduled = false;
          onNeedRepaint();
        });
      }
    } else {
      canvas.drawImageRect(img, srcRect, pageRect, _imagePaint);
    }
  }

  // ---------------------------------------------------------------------------
  // Placeholder
  // ---------------------------------------------------------------------------

  void _drawPlaceholder(Canvas canvas, PdfPageNode node, Rect pageRect) {
    canvas.drawRect(pageRect, _placeholderPaint);
    canvas.drawRect(pageRect, _borderPaint);

    final pageNum = '${node.pageModel.pageIndex + 1}';
    _textPainter.text = TextSpan(text: pageNum, style: _placeholderTextStyle);
    _textPainter.layout();
    _textPainter.paint(
      canvas,
      Offset(
        (pageRect.width - _textPainter.width) / 2,
        (pageRect.height - _textPainter.height) / 2,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // LOD debounce (Fix 2)
  // ---------------------------------------------------------------------------

  /// Buffer a LOD upgrade request. Fires after zoom stabilizes for 150ms.
  void _debounceLodUpgrade(
    PdfPageNode node,
    double targetScale,
    Rect pageRect,
    VoidCallback? onNeedRepaint,
  ) {
    final gen = ++_generation;
    _pendingGenerations[node.id] = gen;

    _debouncedRequests[node.id] = _RenderRequest(
      node: node,
      targetScale: targetScale,
      pageRect: pageRect,
      onNeedRepaint: onNeedRepaint,
      generation: gen,
      priority: _RenderPriority.visible,
    );

    _lodDebounceTimer?.cancel();
    _lodDebounceTimer = Timer(_kLodDebounceDuration, _flushDebouncedRequests);
  }

  /// Flush all debounced LOD upgrade requests into the render queue.
  void _flushDebouncedRequests() {
    for (final request in _debouncedRequests.values) {
      _enqueueRender(
        request.node,
        request.targetScale,
        request.pageRect,
        request.onNeedRepaint,
        priority: _RenderPriority.visible,
      );
    }
    _debouncedRequests.clear();
  }

  // ---------------------------------------------------------------------------
  // Render queue (concurrency-limited)
  // ---------------------------------------------------------------------------

  /// Enqueue a render request.
  void _enqueueRender(
    PdfPageNode node,
    double targetScale,
    Rect pageRect,
    VoidCallback? onNeedRepaint, {
    required _RenderPriority priority,
  }) {
    if (_provider == null || _isDisposed) return;

    // Budget check — only applies to prefetch. Visible pages always render.
    final estimatedBytes =
        (pageRect.width * targetScale).toInt() *
        (pageRect.height * targetScale).toInt() *
        4;

    if (_totalCachedBytes + estimatedBytes > _memoryBudget.currentBudgetBytes) {
      // Evict LRU off-viewport cached pages to make room
      for (int i = 0; i < 20; i++) {
        _evictLruPage(node.id);
        if (_totalCachedBytes + estimatedBytes <=
            _memoryBudget.currentBudgetBytes) {
          break;
        }
      }
      // Only drop PREFETCH requests when over budget — never drop visible
      if (priority == _RenderPriority.prefetch &&
          _totalCachedBytes + estimatedBytes >
              _memoryBudget.currentBudgetBytes) {
        return;
      }
    }

    final gen = ++_generation;

    final existingGen = _pendingGenerations[node.id];
    if (existingGen != null && existingGen >= gen) return;
    _pendingGenerations[node.id] = gen;

    final request = _RenderRequest(
      node: node,
      targetScale: targetScale,
      pageRect: pageRect,
      onNeedRepaint: onNeedRepaint,
      generation: gen,
      priority: priority,
    );

    if (_activeRenders < maxConcurrent) {
      _executeRender(request);
    } else {
      if (priority == _RenderPriority.visible) {
        _renderQueue.addFirst(request);
      } else {
        _renderQueue.addLast(request);
      }
    }
  }

  /// Execute a single render request.
  void _executeRender(_RenderRequest request) {
    _activeRenders++;

    final targetWidth = (request.pageRect.width * request.targetScale).toInt();
    final targetHeight =
        (request.pageRect.height * request.targetScale).toInt();
    final pageIndex = request.node.pageModel.pageIndex;

    _executeRenderAsync(request, pageIndex, targetWidth, targetHeight);
  }

  /// Async implementation of render execution with disk cache support.
  Future<void> _executeRenderAsync(
    _RenderRequest request,
    int pageIndex,
    int targetWidth,
    int targetHeight,
  ) async {
    // 💾 Step 1: Check disk cache before native render
    final renderStopwatch = Stopwatch()..start();
    if (_diskCache != null) {
      try {
        final cachedBytes = await _diskCache.load(
          pageIndex,
          targetWidth,
          targetHeight,
        );
        if (cachedBytes != null && !_isDisposed) {
          final completer = Completer<ui.Image>();
          ui.decodeImageFromPixels(
            cachedBytes,
            targetWidth,
            targetHeight,
            ui.PixelFormat.rgba8888,
            completer.complete,
          );
          final image = await completer.future;
          if (_applyRenderResult(request, image)) {
            stats.recordDiskHit();
            return;
          }
          // _applyRenderResult decremented _activeRenders on stale —
          // re-increment so the native render path can decrement correctly.
          _activeRenders++;
        }
      } catch (e, stack) {
        EngineScope.current.errorRecovery.reportError(
          EngineError(
            severity: ErrorSeverity.transient,
            domain: ErrorDomain.storage,
            source: 'PdfPagePainter.diskCacheLoad',
            original: e,
            stack: stack,
          ),
        );
      }
    }

    // 💻 Step 2: Render via native provider
    stats.recordDiskMiss();
    try {
      final image = await _provider!.renderPage(
        pageIndex: pageIndex,
        scale: request.targetScale,
        targetSize: Size(targetWidth.toDouble(), targetHeight.toDouble()),
      );

      if (image == null) {
        stats.recordRenderError();
        _activeRenders--;
        final retries = _retryCount[request.node.id] ?? 0;
        if (retries < _kMaxRetries) {
          _retryCount[request.node.id] = retries + 1;
          final delay = Duration(milliseconds: 100 * (retries + 1));
          _pendingGenerations.remove(request.node.id);
          Timer(delay, () {
            if (!_isDisposed) {
              _enqueueRender(
                request.node,
                request.targetScale,
                request.pageRect,
                request.onNeedRepaint,
                priority: request.priority,
              );
            }
          });
        } else {
          _pendingGenerations.remove(request.node.id);
        }
        _drainQueue();
        return;
      }

      // ✅ Apply the rendered image
      renderStopwatch.stop();
      stats.recordNativeRender(renderStopwatch.elapsedMilliseconds);
      _applyRenderResult(request, image);

      // 💾 Save to disk cache asynchronously (fire-and-forget)
      if (_diskCache != null) {
        image
            .toByteData(format: ui.ImageByteFormat.rawRgba)
            .then((byteData) {
              if (byteData != null && !_isDisposed) {
                _diskCache.save(
                  pageIndex,
                  targetWidth,
                  targetHeight,
                  byteData.buffer.asUint8List(),
                );
              }
            })
            .catchError((e) {
              EngineScope.current.errorRecovery.reportError(
                EngineError(
                  severity: ErrorSeverity.transient,
                  domain: ErrorDomain.storage,
                  source: 'PdfPagePainter.diskCacheSave',
                  original: e,
                ),
              );
            });
      }
    } catch (_) {
      stats.recordRenderError();
      _activeRenders--;
      final retries = _retryCount[request.node.id] ?? 0;
      if (retries < _kMaxRetries) {
        _retryCount[request.node.id] = retries + 1;
        _pendingGenerations.remove(request.node.id);
        Timer(Duration(milliseconds: 200 * (retries + 1)), () {
          if (!_isDisposed) {
            _enqueueRender(
              request.node,
              request.targetScale,
              request.pageRect,
              request.onNeedRepaint,
              priority: request.priority,
            );
          }
        });
      } else {
        _pendingGenerations.remove(request.node.id);
      }
      _drainQueue();
    }
  }

  /// Apply a successfully rendered image to the node.
  /// Returns true if applied, false if stale/disposed.
  bool _applyRenderResult(_RenderRequest request, ui.Image image) {
    _activeRenders--;

    final currentGen = _pendingGenerations[request.node.id];
    final isStale = currentGen != null && currentGen > request.generation;

    if (_isDisposed || isStale) {
      image.dispose();
      _pendingGenerations.remove(request.node.id);
      _drainQueue();
      return false;
    }

    _retryCount.remove(request.node.id);

    final hadCache = request.node.cachedImage != null;
    final oldBytes = request.node.estimatedMemoryBytes;
    request.node.disposeCachedImage();
    _totalCachedBytes -= oldBytes;

    request.node.cachedImage = image;
    request.node.cachedScale = request.targetScale;
    if (!hadCache) {
      request.node.cacheUpdatedAt = _fadeStopwatch.elapsedMilliseconds;
    }
    _totalCachedBytes += request.node.estimatedMemoryBytes;

    _pendingGenerations.remove(request.node.id);
    _scheduleRepaint(request.onNeedRepaint);
    _drainQueue();
    return true;
  }

  /// Drain the queue, picking the request closest to viewport center first.
  void _drainQueue() {
    while (_activeRenders < maxConcurrent && _renderQueue.isNotEmpty) {
      // 🎯 Viewport-distance priority: pick closest to viewport center
      _RenderRequest? best;
      double bestDist = double.infinity;
      for (final req in _renderQueue) {
        final currentGen = _pendingGenerations[req.node.id];
        if (currentGen != null && currentGen > req.generation) continue;

        final pos = req.node.position;
        final sz = req.node.pageModel.originalSize;
        final center = Offset(pos.dx + sz.width / 2, pos.dy + sz.height / 2);
        final dist = (center - _viewportCenter).distanceSquared;

        // Visible priority bonus (treated as 0 distance)
        final effectiveDist =
            req.priority == _RenderPriority.visible ? dist * 0.001 : dist;

        if (effectiveDist < bestDist) {
          bestDist = effectiveDist;
          best = req;
        }
      }

      if (best == null) break;
      _renderQueue.remove(best);
      _executeRender(best);
    }
  }

  // ---------------------------------------------------------------------------
  // Queue flush on rapid scroll (Fix 6)
  // ---------------------------------------------------------------------------

  /// Purge stale queue entries whose nodes are no longer in [viewport].
  ///
  /// Call after painting visible pages. Removes requests that would waste
  /// native render time on pages the user has already scrolled past.
  void flushStaleQueue(Rect viewport) {
    if (_renderQueue.isEmpty) return;

    final fresh = Queue<_RenderRequest>();
    for (final req in _renderQueue) {
      final pos = req.node.position;
      final sz = req.node.pageModel.originalSize;
      final pageRect = Rect.fromLTWH(pos.dx, pos.dy, sz.width, sz.height);
      if (pageRect.overlaps(viewport) ||
          req.priority == _RenderPriority.prefetch) {
        fresh.addLast(req);
      }
    }
    _renderQueue.clear();
    _renderQueue.addAll(fresh);
  }

  // ---------------------------------------------------------------------------
  // Repaint batching
  // ---------------------------------------------------------------------------

  /// Immediately trigger a repaint callback.
  ///
  /// Flutter's vsync naturally batches frame updates, so we don't need
  /// a Timer debounce — just mark the painter as needing repaint.
  void _scheduleRepaint(VoidCallback? callback) {
    if (callback == null || _isDisposed) return;
    callback();
  }

  // ---------------------------------------------------------------------------
  // Budget auto-refresh (Fix 3)
  // ---------------------------------------------------------------------------

  /// Refresh memory budget and check for memory pressure.
  void _maybeRefreshBudget() {
    _frameCount++;
    if (_frameCount % _kBudgetRefreshInterval != 0) return;

    try {
      final monitor = NativePerformanceMonitor.instance;
      if (monitor.isInitialized) {
        monitor
            .getSnapshot()
            .then((metrics) {
              if (!_isDisposed && metrics != null) {
                _memoryBudget.computeBudgetMB(metrics);

                // 🚨 Memory pressure: aggressively evict off-viewport caches
                if (_memoryBudget.shouldEvictAgressively) {
                  for (final page in _knownPages.toList()) {
                    if (page.cachedImage == null) continue;
                    final pos = page.position;
                    final sz = page.pageModel.originalSize;
                    final rect = Rect.fromLTWH(
                      pos.dx,
                      pos.dy,
                      sz.width,
                      sz.height,
                    );
                    if (_lastViewport != Rect.zero &&
                        !rect.overlaps(_lastViewport)) {
                      _totalCachedBytes -= page.estimatedMemoryBytes;
                      page.disposeCachedImage();
                    }
                  }
                }
              }
            })
            .catchError((e) {
              EngineScope.current.errorRecovery.reportError(
                EngineError(
                  severity: ErrorSeverity.transient,
                  domain: ErrorDomain.rendering,
                  source: 'PdfPagePainter.budgetRefresh',
                  original: e,
                ),
              );
            });
      }
    } catch (e, stack) {
      EngineScope.current.errorRecovery.reportError(
        EngineError(
          severity: ErrorSeverity.transient,
          domain: ErrorDomain.rendering,
          source: 'PdfPagePainter._maybeRefreshBudget',
          original: e,
          stack: stack,
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Prefetch adjacent pages
  // ---------------------------------------------------------------------------

  void prefetchAdjacent(
    List<PdfPageNode> allPages,
    Rect viewport, {
    required double currentZoom,
    VoidCallback? onNeedRepaint,
  }) {
    if (_provider == null || _isDisposed) return;

    // 🔋 Skip prefetch when idle (not scrolling) — saves battery
    if (!_isScrolling) return;

    final prefetchCount = _memoryBudget.prefetchCount;
    if (prefetchCount == 0) return;

    int firstVisible = -1;
    int lastVisible = -1;

    for (int i = 0; i < allPages.length; i++) {
      final pos = allPages[i].position;
      final sz = allPages[i].pageModel.originalSize;
      final pageRect = Rect.fromLTWH(pos.dx, pos.dy, sz.width, sz.height);
      if (pageRect.overlaps(viewport)) {
        if (firstVisible == -1) firstVisible = i;
        lastVisible = i;
      }
    }

    if (firstVisible == -1) return;

    final baseLod = PdfMemoryBudget.lodScaleForZoom(currentZoom);
    final prefetchScale = _memoryBudget.clampScale(baseLod * 0.5);

    // 🎯 Scroll-direction bias: determine scroll direction from viewport delta
    final scrollDelta = _viewportCenter - _prevViewportCenter;
    final scrollDown = scrollDelta.dy > 5; // scrolling down
    final scrollUp = scrollDelta.dy < -5; // scrolling up

    // Allocate more prefetch budget in scroll direction
    final int forwardCount;
    final int backwardCount;
    if (scrollDown) {
      forwardCount = (prefetchCount * 0.75).ceil(); // more ahead
      backwardCount = (prefetchCount * 0.25).ceil(); // less behind
    } else if (scrollUp) {
      forwardCount = (prefetchCount * 0.25).ceil();
      backwardCount = (prefetchCount * 0.75).ceil();
    } else {
      forwardCount = (prefetchCount / 2).ceil();
      backwardCount = (prefetchCount / 2).ceil();
    }

    // Prefetch forward (after last visible)
    for (int delta = 1; delta <= forwardCount; delta++) {
      final idx = lastVisible + delta;
      if (idx >= allPages.length) break;
      final node = allPages[idx];
      if (!node.hasCacheAtScale(prefetchScale)) {
        final rect = Rect.fromLTWH(
          0,
          0,
          node.pageModel.originalSize.width,
          node.pageModel.originalSize.height,
        );
        _enqueueRender(
          node,
          prefetchScale,
          rect,
          onNeedRepaint,
          priority: _RenderPriority.prefetch,
        );
      }
    }

    // Prefetch backward (before first visible)
    for (int delta = 1; delta <= backwardCount; delta++) {
      final idx = firstVisible - delta;
      if (idx < 0) break;
      final node = allPages[idx];
      if (!node.hasCacheAtScale(prefetchScale)) {
        final rect = Rect.fromLTWH(
          0,
          0,
          node.pageModel.originalSize.width,
          node.pageModel.originalSize.height,
        );
        _enqueueRender(
          node,
          prefetchScale,
          rect,
          onNeedRepaint,
          priority: _RenderPriority.prefetch,
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Cache management (LRU eviction)
  // ---------------------------------------------------------------------------

  /// Evict a cached page to free memory.
  ///
  /// Prefers off-viewport pages (using [_lastViewport]) to avoid evicting
  /// visible pages. Falls back to pure LRU if all cached pages are visible.
  void _evictLruPage(String excludeId) {
    PdfPageNode? bestCandidate;
    int lowestTimestamp = 0x7FFFFFFFFFFFFFFF;
    bool bestIsOffViewport = false;

    for (final page in _knownPages) {
      if (page.cachedImage == null) continue;
      if (page.id == excludeId) continue;

      final pos = page.position;
      final size = page.pageModel.originalSize;
      final pageRect = Rect.fromLTWH(pos.dx, pos.dy, size.width, size.height);
      final isOffViewport =
          _lastViewport == Rect.zero || !pageRect.overlaps(_lastViewport);

      // Prefer off-viewport pages; among same category, pick LRU
      if (isOffViewport && !bestIsOffViewport) {
        // Off-viewport always beats on-viewport
        bestCandidate = page;
        lowestTimestamp = page.lastDrawnTimestamp;
        bestIsOffViewport = true;
      } else if (isOffViewport == bestIsOffViewport &&
          page.lastDrawnTimestamp < lowestTimestamp) {
        // Same category — pick oldest
        bestCandidate = page;
        lowestTimestamp = page.lastDrawnTimestamp;
      }
    }

    if (bestCandidate != null) {
      _totalCachedBytes -= bestCandidate.estimatedMemoryBytes;
      bestCandidate.disposeCachedImage();
      stats.recordEviction();
    }
  }

  void evictOffViewport(List<PdfPageNode> allPages, Rect viewport) {
    final offscreen = <PdfPageNode>[];
    for (final page in allPages) {
      if (page.cachedImage == null) continue;
      final pos = page.position;
      final sz = page.pageModel.originalSize;
      final pageRect = Rect.fromLTWH(pos.dx, pos.dy, sz.width, sz.height);
      if (!pageRect.overlaps(viewport)) {
        offscreen.add(page);
      }
    }

    if (offscreen.isEmpty) return;

    offscreen.sort(
      (a, b) => a.lastDrawnTimestamp.compareTo(b.lastDrawnTimestamp),
    );

    for (final page in offscreen) {
      if (_memoryBudget.shouldEvictAgressively ||
          _totalCachedBytes > _memoryBudget.currentBudgetBytes) {
        _totalCachedBytes -= page.estimatedMemoryBytes;
        page.disposeCachedImage();
      } else {
        break;
      }
    }
  }

  void disposeAll(List<PdfPageNode> allPages) {
    _isDisposed = true;
    _lodDebounceTimer?.cancel();
    _warmUpTimer?.cancel();
    _debouncedRequests.clear();
    warmUpProgress.dispose();
    for (final page in allPages) {
      page.disposeCachedImage();
    }
    _totalCachedBytes = 0;
    _pendingGenerations.clear();
    _renderQueue.clear();
    _knownPages.clear();
    _retryCount.clear();
  }

  int get totalCachedBytes => _totalCachedBytes;
  int get activeRenders => _activeRenders;
  int get queueLength => _renderQueue.length;

  // ---------------------------------------------------------------------------
  // Background warm-up
  // ---------------------------------------------------------------------------

  /// 🔥 Pre-render ALL pages at low LOD in background.
  ///
  /// Called after import/restore so pages are ready when the user scrolls.
  /// Progress is tracked via [warmUpProgress] (0.0 → 1.0).
  /// 🔋 Uses staggered batches (3 pages every 100ms) to avoid CPU burst.
  void warmUpAllPages(
    List<PdfPageNode> allPages, {
    VoidCallback? onNeedRepaint,
  }) {
    if (_provider == null || _isDisposed) return;
    if (allPages.isEmpty) return;

    _warmUpTimer?.cancel();
    _warmUpTotal = allPages.length;
    _warmUpCompleted = 0;
    warmUpProgress.value = 0.0;

    const warmUpScale = 0.25; // Ultra-low LOD for fast warm-up
    const batchSize = 3; // Pages per batch
    const batchDelay = Duration(milliseconds: 100);

    // Collect uncached pages
    final uncached = allPages.where((n) => n.cachedImage == null).toList();
    _warmUpCompleted = allPages.length - uncached.length;

    if (uncached.isEmpty) {
      warmUpProgress.value = 1.0;
      return;
    }

    int batchIndex = 0;
    void renderBatch() {
      if (_isDisposed || batchIndex >= uncached.length) return;

      final end = (batchIndex + batchSize).clamp(0, uncached.length);
      for (int i = batchIndex; i < end; i++) {
        final node = uncached[i];
        final rect = Rect.fromLTWH(
          0,
          0,
          node.pageModel.originalSize.width,
          node.pageModel.originalSize.height,
        );
        _enqueueRender(node, warmUpScale, rect, () {
          _warmUpCompleted++;
          if (_warmUpTotal > 0) {
            warmUpProgress.value = _warmUpCompleted / _warmUpTotal;
          }
          onNeedRepaint?.call();
        }, priority: _RenderPriority.prefetch);
      }

      batchIndex = end;
      if (batchIndex < uncached.length) {
        _warmUpTimer = Timer(batchDelay, renderBatch);
      }
    }

    renderBatch();
  }

  // ---------------------------------------------------------------------------
  // Stale cache cleanup
  // ---------------------------------------------------------------------------

  /// 🧹 Remove entries from [_knownPages] for pages that no longer exist
  /// in the scene graph (e.g., after undo/delete).
  /// 🔋 Throttled to run every [_kCleanupInterval] frames.
  void cleanupStalePages(List<PdfPageNode> currentPages) {
    _cleanupFrameCounter++;
    if (_cleanupFrameCounter % _kCleanupInterval != 0) return;

    final currentIds = currentPages.map((p) => p.id).toSet();
    _knownPages.removeWhere((page) {
      if (!currentIds.contains(page.id)) {
        if (page.cachedImage != null) {
          _totalCachedBytes -= page.estimatedMemoryBytes;
          page.disposeCachedImage();
        }
        return true;
      }
      return false;
    });
  }
}

// =============================================================================
// Private helpers
// =============================================================================

enum _RenderPriority { visible, prefetch }

class _RenderRequest {
  final PdfPageNode node;
  final double targetScale;
  final Rect pageRect;
  final VoidCallback? onNeedRepaint;
  final int generation;
  final _RenderPriority priority;

  const _RenderRequest({
    required this.node,
    required this.targetScale,
    required this.pageRect,
    required this.onNeedRepaint,
    required this.generation,
    required this.priority,
  });
}
