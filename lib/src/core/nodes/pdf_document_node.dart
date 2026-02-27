import 'dart:ui';
import 'dart:math' as math;
import '../scene_graph/canvas_node.dart';
import '../scene_graph/node_id.dart';
import '../scene_graph/node_visitor.dart';
import './group_node.dart';
import './pdf_page_node.dart';
import '../models/pdf_document_model.dart';
import '../models/pdf_page_model.dart';
import '../models/pdf_layout_preset.dart';

/// 📄 Scene graph container node for an entire PDF document.
///
/// Extends [GroupNode] to hold [PdfPageNode] children. Manages the
/// automatic grid layout and lock/unlock semantics. When a page is
/// locked, it is positioned by [performGridLayout]; when unlocked,
/// it keeps its [PdfPageModel.customOffset].
///
/// DESIGN PRINCIPLES:
/// - One PdfDocumentNode per imported PDF
/// - Grid layout is recalculated on lock/unlock or config change
/// - Children are always PdfPageNodes (enforced by add helpers)
/// - Serialization includes all page metadata + grid config
class PdfDocumentNode extends GroupNode {
  /// Document-level metadata (hash, grid config, timestamps).
  PdfDocumentModel documentModel;

  /// Pending stroke translations from the last layout change.
  /// Populated by [performGridLayout] when pages with annotations move.
  /// Consumed by the layout-changed callback to translate linked strokes.
  List<({Offset delta, List<String> annotationIds})> pendingStrokeTranslations =
      [];

  /// Pending stroke rotation from the last [rotatePage] call.
  /// Consumed by the layout-changed callback to rotate linked strokes
  /// around [center] by [angleRadians].
  ({double angleRadians, Offset center, List<String> annotationIds})?
  pendingStrokeRotation;

  /// 📡 Callback fired after any mutation (for real-time broadcast).
  /// Parameters: (subAction, data)
  void Function(String subAction, Map<String, dynamic> data)? onMutation;

  PdfDocumentNode({
    required super.id,
    required this.documentModel,
    super.name = '',
    super.localTransform,
    super.opacity,
    super.blendMode,
    super.isVisible,
    super.isLocked,
  });

  // ---------------------------------------------------------------------------
  // Page access helpers
  // ---------------------------------------------------------------------------

  /// All child PdfPageNodes in order.
  List<PdfPageNode> get pageNodes => childrenOfType<PdfPageNode>().toList();

  /// Get a specific page node by page index.
  PdfPageNode? pageAt(int pageIndex) {
    for (final child in children) {
      if (child is PdfPageNode && child.pageModel.pageIndex == pageIndex) {
        return child;
      }
    }
    return null;
  }

  /// Hit-test unlocked pages at [canvasPoint] (canvas-space coordinates).
  ///
  /// Returns the topmost unlocked page whose bounds contain the point,
  /// or `null` if no unlocked page is hit. Iterates in reverse order
  /// so the visually topmost page wins (unlocked pages render last).
  PdfPageNode? hitTestUnlockedPage(Offset canvasPoint) {
    final pages = pageNodes;
    // Reverse: last painted = topmost
    for (int i = pages.length - 1; i >= 0; i--) {
      final page = pages[i];
      if (page.pageModel.isLocked) continue;
      if (pageRectFor(page).contains(canvasPoint)) return page;
    }
    return null;
  }

  /// Hit-test ALL pages (locked + unlocked) at [canvasPoint].
  ///
  /// Returns the page index of the topmost page containing the point,
  /// or -1 if no page is hit. Used to update toolbar selection on tap.
  int hitTestPageIndex(Offset canvasPoint) {
    final pages = pageNodes;
    for (int i = pages.length - 1; i >= 0; i--) {
      if (pageRectFor(pages[i]).contains(canvasPoint)) {
        return pages[i].pageModel.pageIndex;
      }
    }
    return -1;
  }

  // ---------------------------------------------------------------------------
  // Grid layout
  // ---------------------------------------------------------------------------

  /// Position all locked pages in a grid layout.
  ///
  /// Uses per-row max height to handle mixed page sizes (portrait + landscape).
  /// Unlocked pages retain their [PdfPageModel.customOffset].
  ///
  /// 🔑 Grid slots are based on each page's [PdfPageModel.pageIndex], NOT a
  /// compressed counter. This preserves visual gaps where unlocked pages were,
  /// preventing locked pages from overlapping unlocked ones.
  void performGridLayout() {
    final cols = documentModel.gridColumns;
    final spacing = documentModel.gridSpacing;
    final origin = documentModel.gridOrigin;

    // Cache locally to avoid rebuilding the list on each access
    final pages = pageNodes;
    if (pages.isEmpty) return;

    // 📄 Snapshot current positions — used to compute per-page deltas
    // so linked annotation strokes can be translated after layout.
    final oldPositions = <String, Offset>{};
    for (final page in pages) {
      if (page.pageModel.annotations.isNotEmpty) {
        oldPositions[page.id] = page.position;
      }
    }

    // First pass: compute max height per row using ALL pages' original indices
    final totalPages = pages.length;
    final rowCount = (totalPages / cols).ceil();
    final rowMaxHeights = List<double>.filled(rowCount, 0.0);

    for (final page in pages) {
      final idx = page.pageModel.pageIndex;
      final row = idx ~/ cols;
      final h = page.pageModel.originalSize.height;
      if (row < rowMaxHeights.length && h > rowMaxHeights[row]) {
        rowMaxHeights[row] = h;
      }
    }

    // Pre-compute cumulative Y offsets for each row
    final rowYOffsets = List<double>.filled(rowCount, 0.0);
    double cumulativeY = 0;
    for (int r = 0; r < rowCount; r++) {
      rowYOffsets[r] = cumulativeY;
      cumulativeY += rowMaxHeights[r] + spacing;
    }

    // Second pass: position pages using their original pageIndex for grid slots
    for (final pageNode in pages) {
      if (pageNode.pageModel.isLocked) {
        // 🔒 Lock-in-place: if the page has a customOffset, it was locked
        // at a custom position (not in the grid). Keep it there.
        final customPos = pageNode.pageModel.customOffset;
        if (customPos != null) {
          pageNode.setPosition(customPos.dx, customPos.dy);
          pageNode.invalidateTransformCache();
          continue;
        }

        // Use original pageIndex to preserve grid gaps
        final idx = pageNode.pageModel.pageIndex;
        final row = idx ~/ cols;
        final col = idx % cols;

        final pageWidth = pageNode.pageModel.originalSize.width;

        final x = origin.dx + col * (pageWidth + spacing);
        final y = origin.dy + (row < rowYOffsets.length ? rowYOffsets[row] : 0);

        pageNode.setPosition(x, y);
        pageNode.invalidateTransformCache();

        pageNode.pageModel = pageNode.pageModel.copyWith(
          gridRow: row,
          gridCol: col,
        );
      } else {
        // Unlocked pages use their custom offset
        final offset = pageNode.pageModel.customOffset ?? Offset.zero;
        pageNode.setPosition(offset.dx, offset.dy);
        pageNode.invalidateTransformCache();
      }
    }

    // 📄 Compute per-page deltas and queue stroke translations
    for (final page in pages) {
      final oldPos = oldPositions[page.id];
      if (oldPos == null) continue; // No annotations, skip
      final newPos = page.position;
      final delta = newPos - oldPos;
      if (delta != Offset.zero) {
        pendingStrokeTranslations.add((
          delta: delta,
          annotationIds: List<String>.from(page.pageModel.annotations),
        ));
      }
    }

    // 🔑 Invalidate parent bounds so viewport culling uses fresh values.
    // Without this, worldBounds stays stale after child positions change,
    // causing the entire document to be incorrectly culled.
    invalidateBoundsCache();
  }

  /// Toggle lock state for a specific page and re-layout.
  ///
  /// **Lock-in-place**: re-locking keeps the page at its current custom
  /// position. To return a page to the grid, use [returnPageToGrid].
  void togglePageLock(int pageIndex) {
    final pageNode = pageAt(pageIndex);
    if (pageNode == null) return;

    final now = DateTime.now().microsecondsSinceEpoch;

    if (pageNode.pageModel.isLocked) {
      // Unlock: capture current position as custom offset
      pageNode.pageModel = pageNode.pageModel.copyWith(
        isLocked: false,
        customOffset: pageNode.position,
        lastModifiedAt: now,
      );
    } else {
      // Lock in place: keep customOffset so page stays where it is
      pageNode.pageModel = pageNode.pageModel.copyWith(
        isLocked: true,
        customOffset: pageNode.position,
        lastModifiedAt: now,
      );
    }

    // Update document timestamp
    documentModel = documentModel.copyWith(lastModifiedAt: now);
    _syncTotalPages();
    performGridLayout();

    onMutation?.call('pageLocked', {
      'pageIndex': pageIndex,
      'locked': pageNode.pageModel.isLocked,
    });
  }

  /// Return a locked page to its default grid position.
  ///
  /// Clears [customOffset] so the page snaps back to its grid slot.
  /// Returns the position delta and annotation IDs for stroke translation,
  /// or `null` if no translation is needed.
  ({Offset delta, List<String> annotationIds})? returnPageToGrid(
    int pageIndex,
  ) {
    final pageNode = pageAt(pageIndex);
    if (pageNode == null) return null;
    if (pageNode.pageModel.customOffset == null) return null;

    final now = DateTime.now().microsecondsSinceEpoch;

    pageNode.pageModel = pageNode.pageModel.copyWith(
      isLocked: true,
      clearCustomOffset: true,
      lastModifiedAt: now,
    );

    documentModel = documentModel.copyWith(lastModifiedAt: now);
    _syncTotalPages();
    // performGridLayout() now auto-populates pendingStrokeTranslations
    performGridLayout();

    onMutation?.call('returnedToGrid', {'pageIndex': pageIndex});

    // Return the translation for this specific page (if any)
    if (pendingStrokeTranslations.isNotEmpty) {
      return pendingStrokeTranslations.last;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Layout presets
  // ---------------------------------------------------------------------------

  /// Apply a [PdfLayoutPreset] to this document.
  ///
  /// Updates grid columns and spacing, then locks/unlocks all pages
  /// according to the preset. Triggers [performGridLayout].
  void applyLayoutPreset(PdfLayoutPreset preset) {
    final now = DateTime.now().microsecondsSinceEpoch;

    documentModel = documentModel.copyWith(
      gridColumns: preset.columns,
      gridSpacing: preset.spacing,
      lastModifiedAt: now,
    );

    // Lock or unlock all pages based on preset
    for (final page in pageNodes) {
      if (preset.locksPages && !page.pageModel.isLocked) {
        page.pageModel = page.pageModel.copyWith(
          isLocked: true,
          clearCustomOffset: true,
          lastModifiedAt: now,
        );
      } else if (!preset.locksPages && page.pageModel.isLocked) {
        page.pageModel = page.pageModel.copyWith(
          isLocked: false,
          customOffset: page.position,
          lastModifiedAt: now,
        );
      }
    }

    _syncTotalPages();
    performGridLayout();
  }

  /// Change grid columns and re-layout.
  void setGridColumns(int columns) {
    if (columns < 1 || columns > 10) return;
    documentModel = documentModel.copyWith(
      gridColumns: columns,
      lastModifiedAt: DateTime.now().microsecondsSinceEpoch,
    );
    performGridLayout();
  }

  /// Change grid spacing and re-layout.
  void setGridSpacing(double spacing) {
    documentModel = documentModel.copyWith(
      gridSpacing: spacing.clamp(0.0, 200.0),
      lastModifiedAt: DateTime.now().microsecondsSinceEpoch,
    );
    performGridLayout();
  }

  /// Rotate a page by [angleDegrees] (typically 90 increments).
  void rotatePage(int pageIndex, {double angleDegrees = 90}) {
    final pageNode = pageAt(pageIndex);
    if (pageNode == null) return;

    final now = DateTime.now().microsecondsSinceEpoch;
    final raw = pageNode.pageModel.rotation + (angleDegrees * math.pi / 180);
    // Normalize to [0, 2π) — add twoPi first since Dart % preserves sign
    final twoPi = 2.0 * math.pi;
    final newRotation = ((raw % twoPi) + twoPi) % twoPi;

    pageNode.pageModel = pageNode.pageModel.copyWith(
      rotation: newRotation,
      lastModifiedAt: now,
    );
    documentModel = documentModel.copyWith(lastModifiedAt: now);

    // 🔄 Queue stroke rotation so linked annotations rotate with the page.
    final annotations = pageNode.pageModel.annotations;
    if (annotations.isNotEmpty) {
      final pos = pageNode.position;
      final size = pageNode.pageModel.originalSize;
      final center = Offset(pos.dx + size.width / 2, pos.dy + size.height / 2);
      pendingStrokeRotation = (
        angleRadians: angleDegrees * math.pi / 180,
        center: center,
        annotationIds: List<String>.of(annotations),
      );
    }

    // 🔄 Dispose cached raster image so the page is re-rendered at the
    // new orientation. Without this, the stale unrotated image persists.
    pageNode.disposeCachedImage();

    // 🔑 Invalidate bounds so viewport culling and grid layout use fresh
    // values. Row heights may change when a portrait page becomes landscape.
    invalidateBoundsCache();

    // NOTE: onMutation NOT called here for rotation — broadcast happens
    // at the call site AFTER the pending rotation is consumed by
    // onLayoutChanged. This prevents interference with the rotation flow.
  }

  // ---------------------------------------------------------------------------
  // Annotations
  // ---------------------------------------------------------------------------

  /// Find which page (if any) a stroke's bounding rect overlaps,
  /// and add [annotationId] to that page's annotation list.
  ///
  /// Returns the page index it was linked to, or -1 if no overlap.
  int linkAnnotation(String annotationId, Rect strokeBounds) {
    final now = DateTime.now().microsecondsSinceEpoch;

    for (final page in pageNodes) {
      final pageRect = pageRectFor(page);
      if (pageRect.overlaps(strokeBounds)) {
        // O(1) dup-check via Set
        final existing = page.pageModel.annotations;
        if (!existing.contains(annotationId)) {
          page.pageModel = page.pageModel.copyWith(
            annotations: [...existing, annotationId],
            lastModifiedAt: now,
          );
        }
        return page.pageModel.pageIndex;
      }
    }
    return -1;
  }

  /// Remove an annotation ID from all pages (e.g. on stroke delete / undo).
  void unlinkAnnotation(String annotationId) {
    final now = DateTime.now().microsecondsSinceEpoch;
    for (final page in pageNodes) {
      final existing = page.pageModel.annotations;
      if (existing.contains(annotationId)) {
        page.pageModel = page.pageModel.copyWith(
          annotations: List<String>.of(existing)..remove(annotationId),
          lastModifiedAt: now,
        );
      }
    }
  }

  /// Toggle annotation visibility on a specific page.
  void togglePageAnnotations(int pageIndex) {
    final page = pageAt(pageIndex);
    if (page == null) return;
    page.pageModel = page.pageModel.copyWith(
      showAnnotations: !page.pageModel.showAnnotations,
      lastModifiedAt: DateTime.now().microsecondsSinceEpoch,
    );

    onMutation?.call('annotationsToggled', {
      'pageIndex': pageIndex,
      'visible': page.pageModel.showAnnotations,
    });
  }

  /// Get the canvas-space rect for a page, accounting for rotation.
  ///
  /// For 90°/270° rotations, width and height are swapped while keeping
  /// the same center point. This ensures hit-testing and annotation
  /// linking match the visually rotated page area.
  Rect pageRectFor(PdfPageNode page) {
    final pos = page.position;
    final size = page.pageModel.originalSize;
    final rotation = page.pageModel.rotation;

    // Check if rotation is near 90° or 270° (π/2 or 3π/2)
    final quarterTurns = (rotation / (math.pi / 2)).round() % 4;
    if (quarterTurns == 1 || quarterTurns == 3) {
      // Dimensions swap; keep same center
      final cx = pos.dx + size.width / 2;
      final cy = pos.dy + size.height / 2;
      return Rect.fromCenter(
        center: Offset(cx, cy),
        width: size.height,
        height: size.width,
      );
    }

    return Rect.fromLTWH(pos.dx, pos.dy, size.width, size.height);
  }

  // ---------------------------------------------------------------------------
  // Memory management
  // ---------------------------------------------------------------------------

  /// Total estimated memory usage of all cached page images (bytes).
  int get totalCachedMemoryBytes {
    int total = 0;
    for (final page in pageNodes) {
      total += page.estimatedMemoryBytes;
    }
    return total;
  }

  /// Dispose all cached images (call during memory pressure or cleanup).
  void disposeAllCachedImages() {
    for (final page in pageNodes) {
      page.disposeCachedImage();
    }
  }

  /// Evict least-recently-used cached images, keeping at most [maxCached].
  ///
  /// Uses [PdfPageNode.lastDrawnTimestamp] for LRU ordering.
  void evictLeastRecentlyUsed({int maxCached = 10}) {
    final pages = pageNodes;
    final cached = pages.where((p) => p.cachedImage != null).toList();
    if (cached.length <= maxCached) return;

    // Sort ascending by timestamp (oldest first)
    cached.sort((a, b) => a.lastDrawnTimestamp.compareTo(b.lastDrawnTimestamp));

    final toEvict = cached.length - maxCached;
    for (int i = 0; i < toEvict; i++) {
      cached[i].disposeCachedImage();
    }
  }

  /// Reorder a page from [fromIndex] to [toIndex] (0-based within pageNodes).
  ///
  /// Updates page indices and re-layouts the grid.
  void reorderPage(int fromIndex, int toIndex) {
    final pages = pageNodes;
    if (fromIndex < 0 || fromIndex >= pages.length) return;
    if (toIndex < 0 || toIndex >= pages.length) return;
    if (fromIndex == toIndex) return;

    final now = DateTime.now().microsecondsSinceEpoch;

    // 🔄 Swap visual positions so unlocked pages trade places visually.
    // For locked pages, performGridLayout() handles repositioning.
    // For unlocked pages, we swap their customOffset so they land in each
    // other's old spot.
    final fromPage = pages[fromIndex];
    final toPage = pages[toIndex];

    final fromCustom = fromPage.pageModel.customOffset;
    final toCustom = toPage.pageModel.customOffset;
    final fromPos = fromPage.position;
    final toPos = toPage.position;

    // Swap customOffset (unlocked pages use this)
    fromPage.pageModel = fromPage.pageModel.copyWith(
      customOffset: toCustom ?? toPos,
    );
    toPage.pageModel = toPage.pageModel.copyWith(
      customOffset: fromCustom ?? fromPos,
    );

    // Remove then insert at target position in the children list
    remove(fromPage);

    // Re-fetch after removal to get correct insertion index
    final updatedPages = pageNodes;
    final insertIdx = toIndex.clamp(0, updatedPages.length);
    insertAt(insertIdx, fromPage);

    // Re-assign pageIndex to match new order
    final reordered = pageNodes;
    for (int i = 0; i < reordered.length; i++) {
      reordered[i].pageModel = reordered[i].pageModel.copyWith(
        pageIndex: i,
        lastModifiedAt: now,
      );
    }

    documentModel = documentModel.copyWith(lastModifiedAt: now);
    _syncTotalPages();
    performGridLayout();

    onMutation?.call('pageReordered', {
      'fromIndex': fromIndex,
      'toIndex': toIndex,
    });
  }

  /// Insert a blank page at [afterIndex] (0-based) or at the end if null.
  ///
  /// Creates a new [PdfPageNode] with blank content and the given [size]
  /// (defaults to A4 portrait: 612×792 PDF points). Returns the created node.
  PdfPageNode insertBlankPage({int? afterIndex, Size? size}) {
    final pageSize = size ?? const Size(612, 792); // US Letter / A4
    final now = DateTime.now().microsecondsSinceEpoch;
    final pages = pageNodes;

    // Determine insertion position (after afterIndex, or at end)
    final insertIdx =
        afterIndex != null
            ? (afterIndex + 1).clamp(0, pages.length)
            : pages.length;

    // E7: Set descriptive name for layer panel identification
    final blankPage = PdfPageNode(
      id: NodeId('blank_${now}_$insertIdx'),
      name: 'Blank Page ${insertIdx + 1}',
      pageModel: PdfPageModel(
        pageIndex: insertIdx,
        originalSize: pageSize,
        lastModifiedAt: now,
        isBlank: true,
        isLocked: false,
      ),
    );

    // Position blank page next to the reference page
    if (afterIndex != null && afterIndex < pages.length) {
      final refPage = pages[afterIndex];
      final refPos = refPage.position;
      final refWidth = refPage.pageModel.originalSize.width;
      blankPage.pageModel = blankPage.pageModel.copyWith(
        customOffset: Offset(
          refPos.dx + refWidth + documentModel.gridSpacing,
          refPos.dy,
        ),
      );
    }

    insertAt(insertIdx, blankPage);

    // Re-index all pages after insertion
    final updated = pageNodes;
    for (int i = 0; i < updated.length; i++) {
      updated[i].pageModel = updated[i].pageModel.copyWith(
        pageIndex: i,
        lastModifiedAt: now,
      );
    }

    documentModel = documentModel.copyWith(lastModifiedAt: now);
    _syncTotalPages();
    performGridLayout();

    onMutation?.call('pageAdded', {
      'afterIndex': afterIndex,
      'pageWidth': pageSize.width,
      'pageHeight': pageSize.height,
    });

    return blankPage;
  }

  /// Duplicate an existing page at [pageIndex] (0-based).
  ///
  /// Creates a copy of the page with the same size and native page content
  /// (same [pageIndex] so the renderer fetches the same native image).
  /// Annotations are NOT duplicated — the new page is a clean copy.
  /// Returns the duplicated node.
  PdfPageNode duplicatePage(int pageIndex) {
    final pages = pageNodes;
    if (pageIndex < 0 || pageIndex >= pages.length) {
      throw RangeError.range(pageIndex, 0, pages.length - 1, 'pageIndex');
    }

    final sourcePage = pages[pageIndex];
    final now = DateTime.now().microsecondsSinceEpoch;
    final insertIdx = pageIndex + 1;

    // Keep the same native pageIndex so the renderer shows the same content
    final dupPage = PdfPageNode(
      id: NodeId('dup_${now}_$insertIdx'),
      name: '${sourcePage.name} (copy)',
      pageModel: PdfPageModel(
        pageIndex: sourcePage.pageModel.pageIndex,
        originalSize: sourcePage.pageModel.originalSize,
        rotation: sourcePage.pageModel.rotation,
        isBlank: sourcePage.pageModel.isBlank,
        isLocked: false,
        lastModifiedAt: now,
      ),
    );

    // Position to the right of the source page
    final srcPos = sourcePage.position;
    final srcWidth = sourcePage.pageModel.originalSize.width;
    dupPage.pageModel = dupPage.pageModel.copyWith(
      customOffset: Offset(
        srcPos.dx + srcWidth + documentModel.gridSpacing,
        srcPos.dy,
      ),
    );

    insertAt(insertIdx, dupPage);

    documentModel = documentModel.copyWith(lastModifiedAt: now);
    _syncTotalPages();
    performGridLayout();

    onMutation?.call('pageDuplicated', {'pageIndex': pageIndex});

    return dupPage;
  }

  /// Split this document: extract pages [fromIndex..toIndex] (inclusive)
  /// into a new standalone list of page models.
  ///
  /// The original document is NOT modified. Returns a list of copied
  /// page models that can be used to create a new PdfDocumentNode.
  List<PdfPageModel> splitDocument(int fromIndex, int toIndex) {
    final pages = pageNodes;
    final from = fromIndex.clamp(0, pages.length - 1);
    final to = toIndex.clamp(from, pages.length - 1);
    final result = <PdfPageModel>[];
    for (int i = from; i <= to; i++) {
      result.add(pages[i].pageModel.copyWith(pageIndex: i - from));
    }
    return result;
  }

  /// Merge pages from another document into this one.
  ///
  /// Appends all pages from [otherPages] at the end of this document,
  /// re-indexes, syncs totalPages, and rebuilds the grid.
  void mergePages(List<PdfPageModel> otherPages) {
    final now = DateTime.now().microsecondsSinceEpoch;
    final currentCount = pageNodes.length;

    for (int i = 0; i < otherPages.length; i++) {
      final srcPage = otherPages[i];
      final newPage = PdfPageNode(
        id: NodeId('merged_${now}_${currentCount + i}'),
        name: 'Page ${currentCount + i + 1}',
        pageModel: srcPage.copyWith(
          pageIndex: currentCount + i,
          lastModifiedAt: now,
          isLocked: true,
          clearCustomOffset: true,
        ),
      );
      add(newPage);
    }

    // Re-index all pages
    final updated = pageNodes;
    for (int i = 0; i < updated.length; i++) {
      updated[i].pageModel = updated[i].pageModel.copyWith(
        pageIndex: i,
        lastModifiedAt: now,
      );
    }

    documentModel = documentModel.copyWith(lastModifiedAt: now);
    _syncTotalPages();
    performGridLayout();
  }

  /// E6: Remove a page by [pageIndex] (0-based).
  ///
  /// Removes the node, re-indexes remaining pages, syncs totalPages,
  /// and recalculates the grid layout. Returns the removed node
  /// (useful for undo commands).
  PdfPageNode? removePage(int pageIndex) {
    final pages = pageNodes;
    if (pageIndex < 0 || pageIndex >= pages.length) return null;

    final now = DateTime.now().microsecondsSinceEpoch;
    final page = pages[pageIndex];
    remove(page);

    // Re-index remaining pages
    final remaining = pageNodes;
    for (int i = 0; i < remaining.length; i++) {
      remaining[i].pageModel = remaining[i].pageModel.copyWith(
        pageIndex: i,
        lastModifiedAt: now,
      );
    }

    documentModel = documentModel.copyWith(lastModifiedAt: now);
    _syncTotalPages();
    performGridLayout();

    onMutation?.call('pageRemoved', {'pageIndex': pageIndex});

    return page;
  }

  /// Sync [documentModel.totalPages] with actual child count.
  ///
  /// Call after any operation that adds, removes, or reorders pages.
  void _syncTotalPages() {
    final actual = pageNodes.length;
    if (documentModel.totalPages != actual) {
      documentModel = documentModel.copyWith(totalPages: actual);
    }
  }

  // ---------------------------------------------------------------------------
  // Bounds
  // ---------------------------------------------------------------------------

  @override
  Rect get localBounds {
    if (children.isEmpty) return Rect.zero;
    Rect bounds = children.first.localBounds;
    for (int i = 1; i < children.length; i++) {
      bounds = bounds.expandToInclude(children[i].localBounds);
    }
    return bounds;
  }

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  @override
  Map<String, dynamic> toJson() {
    final json = baseToJson();
    json['nodeType'] = 'pdfDocument';
    json['documentModel'] = documentModel.toJson();
    json['children'] = children.map((c) => c.toJson()).toList();
    return json;
  }

  factory PdfDocumentNode.fromJson(Map<String, dynamic> json) {
    // E5: Defensive fallback if documentModel is missing or malformed
    PdfDocumentModel docModel;
    if (json['documentModel'] is Map<String, dynamic>) {
      docModel = PdfDocumentModel.fromJson(
        json['documentModel'] as Map<String, dynamic>,
      );
    } else {
      docModel = const PdfDocumentModel(
        sourceHash: '',
        totalPages: 0,
        pages: [],
      );
    }

    final node = PdfDocumentNode(
      id: NodeId((json['id'] as String?) ?? 'unknown'),
      documentModel: docModel,
    );
    CanvasNode.applyBaseFromJson(node, json);

    // Restore child PdfPageNodes
    if (json['children'] is List<dynamic>) {
      final childrenJson = json['children'] as List<dynamic>;
      for (final childJson in childrenJson) {
        if (childJson is Map<String, dynamic>) {
          final nodeType = childJson['nodeType'] as String?;
          if (nodeType == 'pdfPage') {
            final pageNode = PdfPageNode.fromJson(childJson);
            node.add(pageNode);
          }
        }
      }
    }

    return node;
  }

  // ---------------------------------------------------------------------------
  // Visitor
  // ---------------------------------------------------------------------------

  @override
  R accept<R>(NodeVisitor<R> visitor) => visitor.visitPdfDocument(this);

  @override
  String toString() =>
      'PdfDocumentNode(id: $id, '
      '${children.length} pages, '
      '${children.length} children)';
}
