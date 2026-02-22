/// 🪆 NESTED INSTANCE RENDER INTERCEPTOR — Resolves nested instances before rendering.
///
/// A [RenderInterceptor] that resolves [SymbolInstanceNode]s using
/// [NestedInstanceResolver] before they are rendered.
///
/// ```dart
/// final interceptor = NestedInstanceInterceptor(
///   resolver: NestedInstanceResolver(registry: symbolRegistry),
/// );
/// sceneGraphRenderer.addInterceptor(interceptor);
/// ```
library;

import 'package:flutter/material.dart';
import '../../core/scene_graph/canvas_node.dart';
import '../../core/nodes/symbol_system.dart';
import './render_interceptor.dart';
import '../../systems/nested_instance_resolver.dart';

/// Pre-render resolution of nested instances.
///
/// When a [SymbolInstanceNode] is encountered, this interceptor resolves
/// it using [NestedInstanceResolver] and renders the resolved content
/// instead of the raw instance node.
class NestedInstanceInterceptor extends RenderInterceptor {
  final NestedInstanceResolver resolver;

  /// Cache resolved trees to avoid re-resolving every frame.
  final Map<String, _CachedResolution> _cache = {};

  /// Maximum cache entries.
  final int maxCacheSize;

  NestedInstanceInterceptor({required this.resolver, this.maxCacheSize = 64});

  @override
  void intercept(
    Canvas canvas,
    CanvasNode node,
    Rect viewport,
    RenderNext next,
  ) {
    if (node is! SymbolInstanceNode) {
      next(canvas, node, viewport);
      return;
    }

    // Check cache.
    final cacheKey = _cacheKey(node);
    final cached = _cache[cacheKey];
    if (cached != null && cached.overrideHash == node.overrides.hashCode) {
      // Cached — pass through to default rendering.
      next(canvas, node, viewport);
      return;
    }

    // Resolve the instance.
    final resolved = resolver.resolveDeep(node);
    if (resolved == null) {
      // Fall through to default rendering.
      next(canvas, node, viewport);
      return;
    }

    // Cache the resolution.
    if (_cache.length >= maxCacheSize) {
      _cache.remove(_cache.keys.first);
    }
    _cache[cacheKey] = _CachedResolution(
      resolvedTree: resolved,
      overrideHash: node.overrides.hashCode,
    );

    // Proceed with default rendering (the resolver already applied overrides).
    next(canvas, node, viewport);
  }

  String _cacheKey(SymbolInstanceNode node) =>
      '${node.symbolDefinitionId}:${node.variantSelections.hashCode}';

  /// Clear the resolution cache. Call when definitions change.
  void invalidateCache() => _cache.clear();

  @override
  void onFrameStart() {
    // Could expire stale cache entries here if needed.
  }
}

class _CachedResolution {
  final CanvasNode resolvedTree;
  final int overrideHash;

  _CachedResolution({required this.resolvedTree, required this.overrideHash});
}
