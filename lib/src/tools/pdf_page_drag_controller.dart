import 'package:flutter/services.dart';
import '../core/nodes/pdf_page_node.dart';
import '../core/nodes/pdf_document_node.dart';
import '../core/nodes/group_node.dart';
import '../reflow/reflow_controller.dart';

/// 📄 Controller for dragging unlocked PDF pages on the canvas.
///
/// Manages the drag session lifecycle:
/// 1. [startDrag] — records initial state + touch offset
/// 2. [updateDrag] — moves page in real-time, checks snap proximity
/// 3. [endDrag] — saves final position to customOffset
/// 4. [cancelDrag] — restores original position
///
/// Snap-to-grid: when the page is within [_snapThreshold] pixels of its
/// original grid slot, the position snaps with haptic feedback.
class PdfPageDragController {
  /// The page currently being dragged, if any.
  PdfPageNode? _draggingPage;

  /// The parent document of the dragging page.
  PdfDocumentNode? _parentDocument;

  /// The parent document being dragged (for broadcast).
  PdfDocumentNode? get parentDocument => _parentDocument;

  /// Page position at drag start (for cancel/undo).
  Offset _dragStartPosition = Offset.zero;

  /// Offset between touch point and page origin (top-left).
  /// Prevents the page from jumping to center on the finger.
  Offset _touchOffset = Offset.zero;

  /// Grid slot position of the page (from its pageIndex).
  Offset _gridSlotPosition = Offset.zero;

  /// Whether the page is currently snapped to its grid slot.
  bool _isSnapped = false;

  /// Movement delta from the last updateDrag call.
  /// Used by the draw handler to translate linked annotation strokes.
  Offset _lastDelta = Offset.zero;

  /// Previous page position (for delta calculation).
  Offset _previousPosition = Offset.zero;

  /// Distance threshold for snap-to-grid (pixels).
  static const double _snapThreshold = 40.0;

  /// Whether a drag is active.
  bool get isDragging => _draggingPage != null;

  /// The page being dragged (for rendering feedback).
  PdfPageNode? get draggingPage => _draggingPage;

  /// Position of the original grid slot (for ghost rendering).
  Offset get gridSlotPosition => _gridSlotPosition;

  /// Whether currently snapped to grid.
  bool get isSnapped => _isSnapped;

  /// Page position at drag start (for computing total delta).
  Offset get dragStartPosition => _dragStartPosition;

  /// Current page position after last updateDrag (for computing total delta).
  Offset get previousPosition => _previousPosition;

  /// The delta from the last updateDrag call (for translating linked strokes).
  Offset get lastDelta => _lastDelta;

  /// The annotation IDs linked to the dragging page.
  List<String> get linkedAnnotationIds =>
      _draggingPage?.pageModel.annotations ?? const [];

  /// All annotation IDs across grid-locked pages in the dragging document.
  /// Excludes unlocked pages (customOffset != null) since they don't move
  /// with the document drag.
  List<String> get allDocumentAnnotationIds {
    if (_parentDocument == null) return const [];
    final ids = <String>[];
    for (final page in _parentDocument!.pageNodes) {
      // Skip unlocked pages — they stay at their absolute position
      if (page.pageModel.customOffset != null) continue;
      ids.addAll(page.pageModel.annotations);
    }
    return ids;
  }

  /// Start dragging a page.
  ///
  /// [page] — the unlocked PdfPageNode to drag.
  /// [document] — the parent PdfDocumentNode.
  /// [touchPoint] — the initial touch position in canvas space.
  void startDrag(
    PdfPageNode page,
    PdfDocumentNode document,
    Offset touchPoint,
  ) {
    _draggingPage = page;
    _parentDocument = document;
    _dragStartPosition = page.position;
    _previousPosition = page.position;
    _lastDelta = Offset.zero;
    _isSnapped = false;

    // Calculate offset between touch and page origin
    _touchOffset = Offset(
      touchPoint.dx - page.position.dx,
      touchPoint.dy - page.position.dy,
    );

    // Calculate where the grid slot is for snap target
    final cols = document.documentModel.gridColumns;
    final spacing = document.documentModel.gridSpacing;
    final origin = document.documentModel.gridOrigin;
    final idx = page.pageModel.pageIndex;
    final row = idx ~/ cols;
    final col = idx % cols;
    final pageWidth = page.pageModel.originalSize.width;
    final pageHeight = page.pageModel.originalSize.height;

    // Compute cumulative Y for the row
    double cumulativeY = 0;
    for (int r = 0; r < row; r++) {
      // Use pageHeight as approximation (mixed sizes handled by actual layout)
      cumulativeY += pageHeight + spacing;
    }

    _gridSlotPosition = Offset(
      origin.dx + col * (pageWidth + spacing),
      origin.dy + cumulativeY,
    );

    HapticFeedback.selectionClick();
  }

  /// Update drag position.
  ///
  /// [currentPoint] — current touch position in canvas space.
  /// Returns `true` if position changed (needs repaint).
  bool updateDrag(Offset currentPoint) {
    if (_draggingPage == null) return false;

    // Target position = touch point minus initial offset
    var targetX = currentPoint.dx - _touchOffset.dx;
    var targetY = currentPoint.dy - _touchOffset.dy;

    // Check snap proximity
    final dx = targetX - _gridSlotPosition.dx;
    final dy = targetY - _gridSlotPosition.dy;
    final distance = (dx * dx + dy * dy);
    final wasSnapped = _isSnapped;

    if (distance < _snapThreshold * _snapThreshold) {
      // Snap to grid slot
      targetX = _gridSlotPosition.dx;
      targetY = _gridSlotPosition.dy;
      _isSnapped = true;

      if (!wasSnapped) {
        HapticFeedback.lightImpact();
      }
    } else {
      _isSnapped = false;
    }

    // Calculate delta for stroke translation
    final newPos = Offset(targetX, targetY);
    _lastDelta = newPos - _previousPosition;
    _previousPosition = newPos;

    _draggingPage!.setPosition(targetX, targetY);
    _draggingPage!.invalidateTransformCache();
    _parentDocument?.invalidateBoundsCache();

    return true;
  }

  /// End drag and save the final position.
  ///
  /// Returns the previous position for undo support.
  Offset? endDrag() {
    if (_draggingPage == null) return null;

    final previousPosition = _dragStartPosition;
    final finalPosition = _draggingPage!.position;

    // Save final position as customOffset
    _draggingPage!.pageModel = _draggingPage!.pageModel.copyWith(
      customOffset: finalPosition,
      lastModifiedAt: DateTime.now().microsecondsSinceEpoch,
    );

    // If snapped back to grid, re-lock the page
    if (_isSnapped) {
      _draggingPage!.pageModel = _draggingPage!.pageModel.copyWith(
        isLocked: true,
        clearCustomOffset: true,
        lastModifiedAt: DateTime.now().microsecondsSinceEpoch,
      );
      _parentDocument?.performGridLayout();
      HapticFeedback.mediumImpact();
    }

    _parentDocument?.invalidateBoundsCache();

    HapticFeedback.selectionClick();

    // Cleanup
    _draggingPage = null;
    _parentDocument = null;
    _isSnapped = false;

    return previousPosition;
  }

  /// Cancel the drag and restore original position.
  void cancelDrag() {
    if (_isDraggingDocument) {
      _cancelDocumentDrag();
      return;
    }
    if (_draggingPage == null) return;

    _draggingPage!.setPosition(_dragStartPosition.dx, _dragStartPosition.dy);
    _draggingPage!.invalidateTransformCache();
    _parentDocument?.invalidateBoundsCache();

    _draggingPage = null;
    _parentDocument = null;
    _isSnapped = false;
  }

  // ────────────────────────────────────────────────────────────────────────────
  // 📄 Document-level drag (move all pages as a block)
  // ────────────────────────────────────────────────────────────────────────────

  /// Whether we are dragging the entire document (vs a single page).
  bool _isDraggingDocument = false;

  /// Grid origin at drag start (for cancel/undo).
  Offset _docDragStartOrigin = Offset.zero;

  /// Document grid origin at drag start (for computing total delta).
  Offset get dragStartDocOrigin => _docDragStartOrigin;

  /// 🌊 Reflow controller for physics-based content displacement.
  ReflowController? reflowController;

  /// 🌊 Cluster IDs to exclude from reflow (the document's own elements).
  Set<String> _docExcludeClusterIds = const {};

  /// Whether a document-level drag is active.
  bool get isDraggingDocument => _isDraggingDocument;

  /// Start dragging the entire document.
  ///
  /// [document] — the PdfDocumentNode to drag.
  /// [touchPoint] — the initial touch position in canvas space.
  void startDocumentDrag(PdfDocumentNode document, Offset touchPoint) {
    _parentDocument = document;
    _isDraggingDocument = true;
    _docDragStartOrigin = document.documentModel.gridOrigin;
    _previousPosition = touchPoint;
    _lastDelta = Offset.zero;
    _touchOffset = Offset(
      touchPoint.dx - _docDragStartOrigin.dx,
      touchPoint.dy - _docDragStartOrigin.dy,
    );

    // 🌊 REFLOW: Build exclude set from all page annotation IDs
    if (reflowController != null && reflowController!.isEnabled) {
      final pageElementIds = <String>{};
      for (final page in document.pageNodes) {
        pageElementIds.addAll(page.pageModel.annotations);
      }
      _docExcludeClusterIds = reflowController!.getClusterIdsForElements(
        pageElementIds,
      );
    }

    HapticFeedback.selectionClick();
  }

  /// Compute the union of all page rects as the disturbance area.
  Rect? _computePageUnionRect() {
    if (_parentDocument == null) return null;
    final pages = _parentDocument!.pageNodes;
    if (pages.isEmpty) return null;
    var rect = _parentDocument!.pageRectFor(pages.first);
    for (int i = 1; i < pages.length; i++) {
      rect = rect.expandToInclude(_parentDocument!.pageRectFor(pages[i]));
    }
    return rect;
  }

  /// Update document drag position.
  bool updateDocumentDrag(Offset currentPoint) {
    if (!_isDraggingDocument || _parentDocument == null) return false;

    final newOriginX = currentPoint.dx - _touchOffset.dx;
    final newOriginY = currentPoint.dy - _touchOffset.dy;
    final newOrigin = Offset(newOriginX, newOriginY);

    _lastDelta = currentPoint - _previousPosition;
    _previousPosition = currentPoint;

    // Update grid origin and re-lay out all pages
    _parentDocument!.documentModel = _parentDocument!.documentModel.copyWith(
      gridOrigin: newOrigin,
    );

    // 🔑 Unlocked pages (with customOffset) stay at their absolute position.
    // They were individually repositioned and should NOT follow the document drag.
    // Only grid-locked pages (no customOffset) move with the gridOrigin.

    _parentDocument!.performGridLayout();
    _parentDocument!.invalidateBoundsCache();

    // 🌊 REFLOW: Compute ghost displacements using page union rect
    if (reflowController != null && reflowController!.isEnabled) {
      final disturbance = _computePageUnionRect();
      if (disturbance != null && disturbance.isFinite) {
        reflowController!.computeGhostDisplacements(
          disturbance: disturbance,
          excludeIds: _docExcludeClusterIds,
        );
      }
    }

    return true;
  }

  /// End document drag.
  Offset? endDocumentDrag({GroupNode? layerNode}) {
    if (!_isDraggingDocument || _parentDocument == null) return null;

    final previousOrigin = _docDragStartOrigin;
    _parentDocument!.invalidateBoundsCache();

    // 🌊 REFLOW: Solve and bake final displacements
    if (reflowController != null &&
        reflowController!.ghostDisplacements.isNotEmpty &&
        layerNode != null) {
      final disturbance = _computePageUnionRect();
      if (disturbance != null && disturbance.isFinite) {
        reflowController!.solveAndBake(
          disturbance: disturbance,
          excludeIds: _docExcludeClusterIds,
          layerNode: layerNode,
        );
      }
    }
    reflowController?.clearGhosts();

    HapticFeedback.selectionClick();

    _isDraggingDocument = false;
    _parentDocument = null;
    _docExcludeClusterIds = const {};
    return previousOrigin;
  }

  void _cancelDocumentDrag() {
    if (_parentDocument == null) return;
    _parentDocument!.documentModel = _parentDocument!.documentModel.copyWith(
      gridOrigin: _docDragStartOrigin,
    );
    _parentDocument!.performGridLayout();
    _parentDocument!.invalidateBoundsCache();
    reflowController?.clearGhosts();
    _isDraggingDocument = false;
    _parentDocument = null;
    _docExcludeClusterIds = const {};
  }
}
