import 'dart:ui';
import '../scene_graph/canvas_node.dart';
import '../scene_graph/scene_graph.dart';
import 'group_node.dart';

// =============================================================================
// 📄 MULTI-PAGE DOCUMENT — Top-level container with multiple pages
//
// Provides a Figma-style multi-page document where each page is an
// independent SceneGraph with its own layers and nodes.
//
//   DocumentNode
//   ├── PageNode "Home" (owns SceneGraph ← layers, nodes...)
//   ├── PageNode "Components" (owns SceneGraph)
//   └── PageNode "Icons" (owns SceneGraph)
// =============================================================================

/// A single page within a multi-page document.
///
/// Each page wraps its own [SceneGraph] and adds page-level metadata
/// (name, background color, canvas size, etc.).
///
/// ```dart
/// final page = PageNode(
///   id: NodeId.generate(),
///   name: 'Home Screen',
///   canvasWidth: 1920,
///   canvasHeight: 1080,
/// );
/// page.sceneGraph.addLayer(LayerNode(...));
/// ```
class PageNode {
  /// Unique page ID.
  final String id;

  /// Human-readable page name.
  String name;

  /// The scene graph for this page.
  final SceneGraph sceneGraph;

  /// Optional canvas width (artboard size). Null = infinite canvas.
  double? canvasWidth;

  /// Optional canvas height (artboard size). Null = infinite canvas.
  double? canvasHeight;

  /// Page background color.
  Color backgroundColor;

  /// Whether this page is currently visible in the page list.
  bool isVisible;

  /// Custom page metadata.
  Map<String, dynamic> metadata;

  PageNode({
    String? id,
    this.name = 'Page',
    SceneGraph? sceneGraph,
    this.canvasWidth,
    this.canvasHeight,
    this.backgroundColor = const Color(0xFFFFFFFF),
    this.isVisible = true,
    Map<String, dynamic>? metadata,
  }) : id = id ?? 'page_${DateTime.now().microsecondsSinceEpoch}',
       sceneGraph = sceneGraph ?? SceneGraph(),
       metadata = metadata ?? {};

  /// Serialize page to JSON.
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'sceneGraph': sceneGraph.toJson(),
    if (canvasWidth != null) 'canvasWidth': canvasWidth,
    if (canvasHeight != null) 'canvasHeight': canvasHeight,
    'backgroundColor': backgroundColor.toARGB32(),
    'isVisible': isVisible,
    if (metadata.isNotEmpty) 'metadata': metadata,
  };

  /// Deserialize page from JSON.
  factory PageNode.fromJson(Map<String, dynamic> json) {
    final sgJson = json['sceneGraph'] as Map<String, dynamic>?;
    return PageNode(
      id: json['id'] as String?,
      name: json['name'] as String? ?? 'Page',
      sceneGraph: sgJson != null ? SceneGraph.fromJson(sgJson) : SceneGraph(),
      canvasWidth: (json['canvasWidth'] as num?)?.toDouble(),
      canvasHeight: (json['canvasHeight'] as num?)?.toDouble(),
      backgroundColor:
          json['backgroundColor'] != null
              ? Color(json['backgroundColor'] as int)
              : const Color(0xFFFFFFFF),
      isVisible: json['isVisible'] as bool? ?? true,
      metadata:
          json['metadata'] != null
              ? Map<String, dynamic>.from(json['metadata'] as Map)
              : {},
    );
  }

  /// Total number of nodes across all layers.
  int get nodeCount =>
      sceneGraph.layers.fold<int>(0, (sum, layer) => sum + _countNodes(layer));

  int _countNodes(CanvasNode node) {
    var count = 1;
    if (node is GroupNode) {
      for (final child in node.children) {
        count += _countNodes(child);
      }
    }
    return count;
  }

  /// Create a deep copy of this page with a new ID.
  PageNode duplicate({String? newName}) {
    final json = sceneGraph.toJson();
    return PageNode(
      name: newName ?? '$name (Copy)',
      sceneGraph: SceneGraph.fromJson(json),
      canvasWidth: canvasWidth,
      canvasHeight: canvasHeight,
      backgroundColor: backgroundColor,
      isVisible: isVisible,
      metadata: Map<String, dynamic>.from(metadata),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DOCUMENT NODE — Multi-page container
// ─────────────────────────────────────────────────────────────────────────────

/// Top-level document container that owns multiple [PageNode]s.
///
/// This is the root of a design file, equivalent to a Figma file with
/// multiple pages. Each page has its own independent scene graph.
///
/// ```dart
/// final doc = DocumentNode(name: 'My Design System');
/// doc.addPage(PageNode(name: 'Components'));
/// doc.addPage(PageNode(name: 'Icons'));
/// doc.addPage(PageNode(name: 'Screens'));
///
/// // Navigate to a specific page
/// final icons = doc.pageByName('Icons')!;
/// icons.sceneGraph.addLayer(myLayer);
///
/// // Serialize the entire document
/// final json = doc.toJson();
/// ```
class DocumentNode {
  /// Unique document ID.
  final String id;

  /// Document name (file name).
  String name;

  /// File version for schema migration.
  int schemaVersion;

  /// Ordered list of pages.
  final List<PageNode> _pages = [];

  /// The currently active page index (for UI state tracking).
  int _activePageIndex = 0;

  /// Document-level metadata.
  Map<String, dynamic> metadata;

  /// Created timestamp.
  final DateTime createdAt;

  /// Last modified timestamp.
  DateTime modifiedAt;

  DocumentNode({
    String? id,
    this.name = 'Untitled',
    this.schemaVersion = 1,
    List<PageNode>? pages,
    Map<String, dynamic>? metadata,
    DateTime? createdAt,
    DateTime? modifiedAt,
  }) : id = id ?? 'doc_${DateTime.now().microsecondsSinceEpoch}',
       metadata = metadata ?? {},
       createdAt = createdAt ?? DateTime.now(),
       modifiedAt = modifiedAt ?? DateTime.now() {
    if (pages != null) {
      _pages.addAll(pages);
    }
  }

  // ─── Page access ─────────────────────────────────────────────────

  /// All pages (read-only view).
  List<PageNode> get pages => List.unmodifiable(_pages);

  /// Number of pages.
  int get pageCount => _pages.length;

  /// The currently active page.
  PageNode? get activePage =>
      _activePageIndex < _pages.length ? _pages[_activePageIndex] : null;

  /// Active page index.
  int get activePageIndex => _activePageIndex;

  /// Set the active page by index.
  set activePageIndex(int index) {
    if (index >= 0 && index < _pages.length) {
      _activePageIndex = index;
    }
  }

  /// Get a page by ID.
  PageNode? pageById(String pageId) {
    for (final page in _pages) {
      if (page.id == pageId) return page;
    }
    return null;
  }

  /// Get a page by name (first match).
  PageNode? pageByName(String name) {
    for (final page in _pages) {
      if (page.name == name) return page;
    }
    return null;
  }

  /// Get the index of a page by ID.
  int indexOfPage(String pageId) => _pages.indexWhere((p) => p.id == pageId);

  // ─── Page mutations ──────────────────────────────────────────────

  /// Add a page at the end.
  void addPage(PageNode page) {
    _pages.add(page);
    _touch();
  }

  /// Insert a page at a specific index.
  void insertPage(int index, PageNode page) {
    _pages.insert(index.clamp(0, _pages.length), page);
    _touch();
  }

  /// Remove a page by ID. Returns the removed page, or null.
  PageNode? removePage(String pageId) {
    final index = _pages.indexWhere((p) => p.id == pageId);
    if (index < 0) return null;
    final removed = _pages.removeAt(index);
    if (_activePageIndex >= _pages.length && _pages.isNotEmpty) {
      _activePageIndex = _pages.length - 1;
    }
    _touch();
    return removed;
  }

  /// Reorder pages (move from oldIndex to newIndex).
  void reorderPages(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _pages.length) return;
    final page = _pages.removeAt(oldIndex);
    final insertAt = newIndex > oldIndex ? newIndex - 1 : newIndex;
    _pages.insert(insertAt.clamp(0, _pages.length), page);
    _touch();
  }

  /// Duplicate a page and insert the copy after the original.
  PageNode? duplicatePage(String pageId, {String? newName}) {
    final index = _pages.indexWhere((p) => p.id == pageId);
    if (index < 0) return null;
    final copy = _pages[index].duplicate(newName: newName);
    _pages.insert(index + 1, copy);
    _touch();
    return copy;
  }

  void _touch() {
    modifiedAt = DateTime.now();
  }

  // ─── Cross-page queries ──────────────────────────────────────────

  /// Total node count across all pages.
  int get totalNodeCount =>
      _pages.fold<int>(0, (sum, page) => sum + page.nodeCount);

  /// Find a node by ID across all pages.
  ///
  /// Returns `(pageIndex, node)` or null if not found.
  (int, CanvasNode)? findNodeAcrossPages(String nodeId) {
    for (var i = 0; i < _pages.length; i++) {
      final node = _pages[i].sceneGraph.findNodeById(nodeId);
      if (node != null) return (i, node);
    }
    return null;
  }

  // ─── Serialization ───────────────────────────────────────────────

  /// Serialize the entire document to JSON.
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'schemaVersion': schemaVersion,
    'activePageIndex': _activePageIndex,
    'createdAt': createdAt.toIso8601String(),
    'modifiedAt': modifiedAt.toIso8601String(),
    'pages': _pages.map((p) => p.toJson()).toList(),
    if (metadata.isNotEmpty) 'metadata': metadata,
  };

  /// Deserialize a document from JSON.
  factory DocumentNode.fromJson(Map<String, dynamic> json) {
    final pagesJson = json['pages'] as List? ?? [];
    return DocumentNode(
      id: json['id'] as String?,
      name: json['name'] as String? ?? 'Untitled',
      schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 1,
      pages:
          pagesJson
              .map((p) => PageNode.fromJson(p as Map<String, dynamic>))
              .toList(),
      metadata:
          json['metadata'] != null
              ? Map<String, dynamic>.from(json['metadata'] as Map)
              : null,
      createdAt:
          json['createdAt'] != null
              ? DateTime.parse(json['createdAt'] as String)
              : null,
      modifiedAt:
          json['modifiedAt'] != null
              ? DateTime.parse(json['modifiedAt'] as String)
              : null,
    ).._activePageIndex = (json['activePageIndex'] as num?)?.toInt() ?? 0;
  }

  /// Document statistics.
  Map<String, dynamic> stats() => {
    'pageCount': pageCount,
    'totalNodeCount': totalNodeCount,
    'pages': [
      for (final page in _pages)
        {
          'id': page.id,
          'name': page.name,
          'nodeCount': page.nodeCount,
          'layerCount': page.sceneGraph.layers.length,
        },
    ],
  };
}
