// ============================================================================
// 🏷️ ClusterIdV2Flag — Big-bang migration toggle for cluster ID hash.
//
// V1 (legacy): cluster.id = 'cluster_stroke_${sortedStrokeIds.hashCode}'
//   — invalidated on EVERY stroke add/remove → AI title regenerated → wasted
//   Gemini calls + flickering UI.
//
// V2 (new):    cluster.id = 'cluster_v2_${contentHash(bounds, count, time)}'
//   — quantized bounds (24px grid) + count + temporal centroid (5min granul.)
//   — preserves the same ID when the user adds 1-2 strokes within the same
//   bounding-box footprint, so caches (`aiTitles`, `_clusterTextCache`,
//   `ClusterConceptIndex`) survive minor edits.
//
// Default: enabled = true (post-deploy). Override via direct field assignment
// — host app may flip this from a debug menu or persist via its own prefs
// (fluera_engine intentionally has no SharedPreferences dependency).
// This is a one-shot migration; no rollout-percent / A/B branching.
// ============================================================================

class ClusterIdV2Flag {
  ClusterIdV2Flag._();

  /// Whether to use the content-stable V2 hash. Default `true`.
  /// Read synchronously by [ClusterDetector] on every clustering pass.
  /// Toggle once at app startup, NOT in a hot path — flipping mid-session
  /// would split a canvas across two ID schemes and orphan its cache.
  static bool enabled = true;
}
