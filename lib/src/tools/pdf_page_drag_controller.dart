import 'package:flutter/services.dart';
import '../core/nodes/pdf_page_node.dart';
import '../core/nodes/pdf_document_node.dart';

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
    if (_draggingPage == null) return;

    _draggingPage!.setPosition(_dragStartPosition.dx, _dragStartPosition.dy);
    _draggingPage!.invalidateTransformCache();
    _parentDocument?.invalidateBoundsCache();

    _draggingPage = null;
    _parentDocument = null;
    _isSnapped = false;
  }
}
