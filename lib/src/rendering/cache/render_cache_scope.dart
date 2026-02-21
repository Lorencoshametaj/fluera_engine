import 'dart:ui' as ui;

import '../scene_graph/scene_graph_renderer.dart';
import '../optimization/stroke_cache_manager.dart';

// =============================================================================
// RENDER CACHE SCOPE — Per-scope rendering caches
// =============================================================================

/// Holds all mutable rendering cache state that was previously static.
///
/// By moving these caches from `static` fields into a scope-owned instance,
/// each [EngineScope] gets its own independent set of rendering caches.
/// This prevents cross-canvas contamination when multiple canvases are
/// active simultaneously (multi-tenancy).
///
/// ## Migrated caches:
/// - **delegateRenderer**: per-scope [SceneGraphRenderer]
/// - **strokeCache**: vectorial Picture cache for O(1) replay
/// - **layerCaches**: per-layer Picture cache keyed by layer ID
class RenderCacheScope {
  /// Per-scope scene graph renderer.
  final SceneGraphRenderer delegateRenderer = SceneGraphRenderer();

  /// Vectorial cache for stroke Picture replay.
  final StrokeCacheManager strokeCache = StrokeCacheManager();

  /// Per-layer Picture caches keyed by layer ID.
  final Map<String, ui.Picture> layerCaches = {};

  /// Version of the scene graph when layer caches were last populated.
  int layerCacheVersion = -1;

  /// Invalidate all per-layer caches (e.g. on undo or eraser).
  void invalidateLayerCaches() {
    for (final picture in layerCaches.values) {
      picture.dispose();
    }
    layerCaches.clear();
    layerCacheVersion = -1;
  }

  /// Dispose all cached resources.
  void dispose() {
    invalidateLayerCaches();
    strokeCache.invalidateCache();
    delegateRenderer.clearCache();
  }
}
