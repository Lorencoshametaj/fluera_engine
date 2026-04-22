// ============================================================================
// 🔖 PIN THIS VIEW — helper for creating a SpatialBookmark from a viewport
//
// The canvas editor calls [pinThisView] when the user explicitly asks to
// bookmark the current view. This is the one and only sanctioned way to
// create a bookmark, coherent with §22 ("il Palazzo si abita, non si progetta"):
// the zone must already exist spatially before the user names it.
// ============================================================================

import 'dart:math' as math;
import 'package:flutter/foundation.dart';

import 'fluera_storage_adapter.dart';
import 'spatial_bookmark.dart';

/// Appends a new [SpatialBookmark] to the given [canvasId], preserving the
/// existing ones, and persists the merged list via [adapter].
///
/// - [name] is the user-supplied label (trimmed; fallback "Pinned view").
/// - [viewport] is the current camera state: (dx, dy, scale). The bookmark's
///   centre is computed as world coordinates (−dx/scale, −dy/scale) so that
///   jumping to it later re-creates the same framing.
/// - [existingBookmarks] must be the current list (usually read from
///   [CanvasMetadata.bookmarks]); it is preserved verbatim.
/// - [color] is optional — used only as a tint for the minimap label.
///
/// Returns the newly created bookmark so callers can react (e.g. show a
/// toast or focus the list entry).
Future<SpatialBookmark> pinThisView({
  required FlueraStorageAdapter adapter,
  required String canvasId,
  required String name,
  required ({double dx, double dy, double scale}) viewport,
  required List<SpatialBookmark> existingBookmarks,
  int? color,
}) async {
  final safeName = name.trim().isEmpty ? 'Pinned view' : name.trim();
  final safeScale = viewport.scale == 0 ? 1.0 : viewport.scale;
  final bookmark = SpatialBookmark(
    id: _generateId(),
    name: safeName,
    cx: -viewport.dx / safeScale,
    cy: -viewport.dy / safeScale,
    zoom: safeScale,
    color: color,
    createdAt: DateTime.now(),
  );

  final updated = <SpatialBookmark>[...existingBookmarks, bookmark];
  await adapter.saveBookmarks(canvasId, bookmarks: updated);
  return bookmark;
}

/// Marks a bookmark as just-visited (updates [SpatialBookmark.lastVisitedAt])
/// and re-persists the list. Call this when the user jumps to a bookmark.
Future<void> touchBookmarkVisit({
  required FlueraStorageAdapter adapter,
  required String canvasId,
  required String bookmarkId,
  required List<SpatialBookmark> existingBookmarks,
}) async {
  final now = DateTime.now();
  final updated = [
    for (final b in existingBookmarks)
      if (b.id == bookmarkId) b.copyWith(lastVisitedAt: now) else b,
  ];
  if (listEquals(updated, existingBookmarks)) return;
  await adapter.saveBookmarks(canvasId, bookmarks: updated);
}

/// Generates a stable bookmark id of the form `bm_<microseconds36>_<rand36>`.
/// Public so controllers can share the format without duplicating entropy.
String generateBookmarkId() {
  final rand = math.Random();
  final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final salt = rand.nextInt(1 << 24).toRadixString(36);
  return 'bm_${ts}_$salt';
}

String _generateId() => generateBookmarkId();
