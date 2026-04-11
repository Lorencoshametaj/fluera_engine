// ============================================================================
// 🗺️ GHOST MAP CACHE — Concept map reference caching (A3-04)
//
// Specifica: A3-04
//
// Caches the AI-generated concept map reference so that repeated
// Ghost Map invocations on the same zone don't re-call the LLM.
//
// RULES:
//   - Cache key: zoneId + content hash (if content changes, cache invalidates)
//   - TTL: 24 hours (concept maps don't change frequently)
//   - Max entries: 50 (LRU eviction)
//   - Serializable for persistence across sessions
//
// ARCHITECTURE:
//   In-memory LRU cache with optional persistence layer.
//   The Ghost Map controller checks cache BEFORE calling Atlas AI.
//
// THREAD SAFETY: Main isolate only.
// ============================================================================

import 'dart:collection';

/// 🗺️ A cached concept map reference.
class CachedConceptMap {
  /// Zone ID this map was generated for.
  final String zoneId;

  /// Hash of the zone content at generation time.
  final String contentHash;

  /// The AI-generated concept map (JSON or structured data).
  final Map<String, dynamic> conceptMapData;

  /// When this entry was cached.
  final DateTime cachedAt;

  /// TTL: 24 hours.
  static const Duration ttl = Duration(hours: 24);

  CachedConceptMap({
    required this.zoneId,
    required this.contentHash,
    required this.conceptMapData,
    DateTime? cachedAt,
  }) : cachedAt = cachedAt ?? DateTime.now();

  /// Whether this cache entry is still valid.
  bool get isValid =>
      DateTime.now().difference(cachedAt) < ttl;

  /// Whether this entry matches the current content.
  bool matchesContent(String currentHash) => contentHash == currentHash;

  Map<String, dynamic> toJson() => {
        'zoneId': zoneId,
        'contentHash': contentHash,
        'conceptMapData': conceptMapData,
        'cachedAt': cachedAt.millisecondsSinceEpoch,
      };

  factory CachedConceptMap.fromJson(Map<String, dynamic> json) {
    return CachedConceptMap(
      zoneId: json['zoneId'] as String,
      contentHash: json['contentHash'] as String,
      conceptMapData:
          Map<String, dynamic>.from(json['conceptMapData'] as Map),
      cachedAt: DateTime.fromMillisecondsSinceEpoch(
          (json['cachedAt'] as num).toInt()),
    );
  }
}

/// 🗺️ Ghost Map Cache (A3-04).
///
/// LRU cache for AI-generated concept map references.
/// Eliminates redundant LLM calls when the student re-opens
/// Ghost Map on the same zone within 24 hours.
///
/// Usage:
/// ```dart
/// final cache = GhostMapCache();
/// final cached = cache.get(zoneId, contentHash);
/// if (cached != null) {
///   // Use cached concept map — skip AI call
/// } else {
///   final map = await atlasAI.generateConceptMap(zone);
///   cache.put(zoneId, contentHash, map);
/// }
/// ```
class GhostMapCache {
  /// Maximum cache entries.
  static const int maxEntries = 50;

  /// Creates an empty cache.
  GhostMapCache();

  /// Ordered map: zoneId → cached entry (insertion order for LRU).
  final LinkedHashMap<String, CachedConceptMap> _cache = LinkedHashMap();

  /// Number of cached entries.
  int get size => _cache.length;

  /// Get a cached concept map if valid.
  ///
  /// Returns null if not cached, expired, or content has changed.
  CachedConceptMap? get(String zoneId, String contentHash) {
    final entry = _cache[zoneId];
    if (entry == null) return null;

    if (!entry.isValid || !entry.matchesContent(contentHash)) {
      _cache.remove(zoneId);
      return null;
    }

    // Move to end (most recently accessed) for LRU.
    _cache.remove(zoneId);
    _cache[zoneId] = entry;
    return entry;
  }

  /// Cache a concept map.
  void put(
    String zoneId,
    String contentHash,
    Map<String, dynamic> conceptMapData,
  ) {
    // Evict oldest if at capacity.
    while (_cache.length >= maxEntries) {
      _cache.remove(_cache.keys.first);
    }

    _cache[zoneId] = CachedConceptMap(
      zoneId: zoneId,
      contentHash: contentHash,
      conceptMapData: conceptMapData,
    );
  }

  /// Invalidate a specific zone's cache.
  void invalidate(String zoneId) {
    _cache.remove(zoneId);
  }

  /// Clear all cached entries.
  void clear() {
    _cache.clear();
  }

  /// Evict all expired entries.
  int evictExpired() {
    final expired = _cache.entries
        .where((e) => !e.value.isValid)
        .map((e) => e.key)
        .toList();
    for (final key in expired) {
      _cache.remove(key);
    }
    return expired.length;
  }

  /// Serialize for persistence.
  List<Map<String, dynamic>> toJson() =>
      _cache.values.map((e) => e.toJson()).toList();

  /// Restore from persistence.
  factory GhostMapCache.fromJson(List<dynamic> json) {
    final cache = GhostMapCache();
    for (final item in json) {
      final entry =
          CachedConceptMap.fromJson(Map<String, dynamic>.from(item as Map));
      if (entry.isValid) {
        cache._cache[entry.zoneId] = entry;
      }
    }
    return cache;
  }
}
