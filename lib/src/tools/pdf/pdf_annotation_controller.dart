import 'dart:ui' show Color, Offset, Rect;
import 'package:flutter/foundation.dart';
import '../../core/models/pdf_annotation_model.dart';
import '../../core/nodes/pdf_document_node.dart';
import '../../core/nodes/pdf_page_node.dart';
import '../../history/command_history.dart';

// =============================================================================
// 🏷️ PDF ANNOTATION CONTROLLER — CRUD for structured annotations
// =============================================================================

/// 🏷️ Controller for managing structured annotations on PDF pages.
///
/// Provides CRUD operations for highlights, underlines, and sticky notes.
/// Annotations are stored in [PdfPageModel.structuredAnnotations] and
/// persisted alongside the scene graph JSON.
///
/// DESIGN PRINCIPLES:
/// - Single source of truth: mutations go through the controller
/// - Immutable model updates via copyWith
/// - ChangeNotifier for reactive UI updates
/// - Integrates with PdfTextSelectionController for highlight creation
class PdfAnnotationController extends ChangeNotifier {
  PdfDocumentNode? _document;
  int _idCounter = 0;

  /// Optional command history for undo/redo support.
  /// When set, CRUD operations automatically push undoable commands.
  CommandHistory? history;

  // I9: Pre-compiled RegExp — avoids re-allocation on each attach()
  static final RegExp _numericExtractor = RegExp(r'[^0-9]');

  /// Active annotation type for creation.
  PdfAnnotationType _activeType = PdfAnnotationType.highlight;
  PdfAnnotationType get activeType => _activeType;
  set activeType(PdfAnnotationType value) {
    if (_activeType != value) {
      _activeType = value;
      notifyListeners();
    }
  }

  /// Active annotation color for creation.
  Color _activeColor = PdfAnnotationType.highlight.defaultColor;
  Color get activeColor => _activeColor;
  set activeColor(Color value) {
    if (_activeColor != value) {
      _activeColor = value;
      notifyListeners();
    }
  }

  /// Bind this controller to a PDF document.
  void attach(PdfDocumentNode doc) {
    _document = doc;
    // Derive counter from existing annotations to avoid ID collisions
    final maxExisting = _allAnnotations()
        .map((a) {
          final numPart = a.id.replaceAll(_numericExtractor, '');
          return numPart.isNotEmpty ? int.tryParse(numPart) ?? 0 : 0;
        })
        .fold(0, (a, b) => a > b ? a : b);
    _idCounter = maxExisting + 1;
    notifyListeners();
  }

  /// Detach from the current document.
  ///
  /// E8: Also clears history to prevent stale commands on detached pages.
  void detach() {
    _document = null;
    history = null;
    notifyListeners();
  }

  /// Whether a document is attached.
  bool get isAttached => _document != null;

  // ---------------------------------------------------------------------------
  // Query
  // ---------------------------------------------------------------------------

  /// All annotations across all pages.
  List<PdfAnnotation> get allAnnotations => _allAnnotations();

  /// Annotations for a specific page.
  List<PdfAnnotation> annotationsForPage(int pageIndex) {
    if (_document == null) return const [];
    final pages = _document!.pageNodes;
    for (final page in pages) {
      if (page.pageModel.pageIndex == pageIndex) {
        return page.pageModel.structuredAnnotations;
      }
    }
    return const [];
  }

  /// Find a single annotation by ID.
  PdfAnnotation? findById(String id) {
    for (final a in _allAnnotations()) {
      if (a.id == id) return a;
    }
    return null;
  }

  /// I10: Hit-test — find annotation at [point] on [pageIndex].
  ///
  /// Returns the topmost (last-added) annotation whose rect contains [point],
  /// or null if none match. Point is in page-local coordinates.
  PdfAnnotation? annotationAt(int pageIndex, Offset point) {
    if (_document == null) return null;
    final annotations = annotationsForPage(pageIndex);
    // Iterate in reverse for topmost-first hit
    for (int i = annotations.length - 1; i >= 0; i--) {
      if (annotations[i].rect.contains(point)) return annotations[i];
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Create
  // ---------------------------------------------------------------------------

  /// Add a highlight annotation covering [rect] on [pageIndex].
  PdfAnnotation addHighlight({
    required int pageIndex,
    required Rect rect,
    Color? color,
  }) {
    return _addAnnotation(
      type: PdfAnnotationType.highlight,
      pageIndex: pageIndex,
      rect: rect,
      color: color ?? _activeColor,
    );
  }

  /// Add an underline annotation spanning [rect] on [pageIndex].
  PdfAnnotation addUnderline({
    required int pageIndex,
    required Rect rect,
    Color? color,
  }) {
    return _addAnnotation(
      type: PdfAnnotationType.underline,
      pageIndex: pageIndex,
      rect: rect,
      color: color ?? PdfAnnotationType.underline.defaultColor,
    );
  }

  /// Add a sticky note at [rect] on [pageIndex] with optional [text].
  PdfAnnotation addStickyNote({
    required int pageIndex,
    required Rect rect,
    String? text,
    Color? color,
  }) {
    return _addAnnotation(
      type: PdfAnnotationType.stickyNote,
      pageIndex: pageIndex,
      rect: rect,
      color: color ?? PdfAnnotationType.stickyNote.defaultColor,
      text: text,
    );
  }

  // ---------------------------------------------------------------------------
  // Update
  // ---------------------------------------------------------------------------

  /// Update an annotation by [id] with new fields.
  bool updateAnnotation(
    String id, {
    Color? color,
    Rect? rect,
    String? text,
    bool clearText = false,
  }) {
    if (_document == null) return false;

    final now = DateTime.now().microsecondsSinceEpoch;
    final pages = _document!.pageNodes;

    for (final page in pages) {
      final annotations = page.pageModel.structuredAnnotations;
      final idx = annotations.indexWhere((a) => a.id == id);
      if (idx < 0) continue;

      final oldAnnotation = annotations[idx];
      final updated = oldAnnotation.copyWith(
        color: color,
        rect: rect,
        text: text,
        clearText: clearText,
        lastModifiedAt: now,
      );

      if (history != null) {
        history!.execute(
          UpdateAnnotationCommand(
            page: page,
            oldAnnotation: oldAnnotation,
            newAnnotation: updated,
          ),
        );
      } else {
        final newList = List<PdfAnnotation>.from(annotations);
        newList[idx] = updated;
        page.pageModel = page.pageModel.copyWith(
          structuredAnnotations: newList,
        );
      }
      notifyListeners();
      return true;
    }

    return false;
  }

  // ---------------------------------------------------------------------------
  // Delete
  // ---------------------------------------------------------------------------

  /// Remove an annotation by [id].
  bool removeAnnotation(String id) {
    if (_document == null) return false;

    final pages = _document!.pageNodes;

    for (final page in pages) {
      final annotations = page.pageModel.structuredAnnotations;
      final idx = annotations.indexWhere((a) => a.id == id);
      if (idx < 0) continue;

      if (history != null) {
        history!.execute(
          RemoveAnnotationCommand(page: page, annotation: annotations[idx]),
        );
      } else {
        final newList = List<PdfAnnotation>.from(annotations);
        newList.removeAt(idx);
        page.pageModel = page.pageModel.copyWith(
          structuredAnnotations: newList,
        );
      }
      notifyListeners();
      return true;
    }

    return false;
  }

  /// Remove all annotations on [pageIndex].
  ///
  /// F1: When history is set, pushes a CompositeCommand of individual
  /// RemoveAnnotationCommands — fully undoable as a batch.
  int clearPage(int pageIndex) {
    if (_document == null) return 0;

    final page = _findPage(pageIndex);
    if (page == null) return 0;

    final annotations = page.pageModel.structuredAnnotations;
    final count = annotations.length;
    if (count == 0) return 0;

    if (history != null) {
      final commands =
          annotations
              .map(
                (a) =>
                    RemoveAnnotationCommand(page: page, annotation: a)
                        as Command,
              )
              .toList();
      history!.execute(
        CompositeCommand(
          label: 'Clear page ${pageIndex + 1} annotations',
          commands: commands,
        ),
      );
    } else {
      page.pageModel = page.pageModel.copyWith(structuredAnnotations: const []);
    }
    notifyListeners();
    return count;
  }

  /// Remove all annotations across all pages.
  ///
  /// F2: When history is set, pushes a CompositeCommand — fully undoable.
  int removeAllAnnotations() {
    if (_document == null) return 0;
    int total = 0;
    final commands = <Command>[];

    for (final page in _document!.pageNodes) {
      final annotations = page.pageModel.structuredAnnotations;
      if (annotations.isEmpty) continue;
      total += annotations.length;

      if (history != null) {
        for (final a in annotations) {
          commands.add(RemoveAnnotationCommand(page: page, annotation: a));
        }
      } else {
        page.pageModel = page.pageModel.copyWith(
          structuredAnnotations: const [],
        );
      }
    }

    if (history != null && commands.isNotEmpty) {
      history!.execute(
        CompositeCommand(label: 'Clear all annotations', commands: commands),
      );
    }

    if (total > 0) notifyListeners();
    return total;
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  PdfAnnotation _addAnnotation({
    required PdfAnnotationType type,
    required int pageIndex,
    required Rect rect,
    required Color color,
    String? text,
  }) {
    final now = DateTime.now().microsecondsSinceEpoch;
    final annotation = PdfAnnotation(
      id: 'annot_${_idCounter++}',
      type: type,
      pageIndex: pageIndex,
      rect: rect,
      color: color,
      text: text,
      createdAt: now,
      lastModifiedAt: now,
    );

    if (_document == null) return annotation;

    final page = _findPage(pageIndex);
    if (page == null) return annotation;

    if (history != null) {
      history!.execute(
        AddAnnotationCommand(page: page, annotation: annotation),
      );
    } else {
      final newList = [...page.pageModel.structuredAnnotations, annotation];
      page.pageModel = page.pageModel.copyWith(structuredAnnotations: newList);
    }
    notifyListeners();
    return annotation;
  }

  /// F3: Indexed page lookup — O(1) when pageIndex matches array position.
  PdfPageNode? _findPage(int pageIndex) {
    if (_document == null) return null;
    final pages = _document!.pageNodes;
    // Fast path: pageIndex usually matches array position
    if (pageIndex >= 0 &&
        pageIndex < pages.length &&
        pages[pageIndex].pageModel.pageIndex == pageIndex) {
      return pages[pageIndex];
    }
    // Fallback: linear scan (pages may be reordered)
    for (final page in pages) {
      if (page.pageModel.pageIndex == pageIndex) return page;
    }
    return null;
  }

  List<PdfAnnotation> _allAnnotations() {
    if (_document == null) return const [];
    return _document!.pageNodes
        .expand((p) => p.pageModel.structuredAnnotations)
        .toList();
  }

  @override
  void dispose() {
    _document = null;
    history = null; // F4: Prevent stale command references
    super.dispose();
  }
}
