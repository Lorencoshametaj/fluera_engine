// ============================================================================
// 🖼️ NEBULA CANVAS GALLERY — Canvas management screen
//
// Pre-built widget for browsing, creating, and deleting canvases.
// Uses Material Design 3 with premium aesthetics and full customization.
//
// USAGE (zero config):
//   NebulaCanvasGallery(
//     storageAdapter: storage,
//     onCanvasSelected: (id) => navigateTo(id),
//   )
//
// USAGE (custom):
//   NebulaCanvasGallery(
//     storageAdapter: storage,
//     onCanvasSelected: (id) => navigateTo(id),
//     gridColumns: 3,
//     canvasCardBuilder: (meta, onTap, onDelete) => MyCard(...),
//     emptyStateBuilder: () => MyEmptyState(),
//   )
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../storage/nebula_storage_adapter.dart';

/// 🖼️ Canvas gallery widget for browsing, creating, and deleting canvases.
///
/// Provides a Material Design 3 grid view of all stored canvases with:
/// - Animated card grid with metadata (title, stroke count, date)
/// - Create new canvas FAB
/// - Swipe-to-delete with confirmation
/// - Full customization via builders
///
/// REQUIREMENTS:
/// - A [NebulaStorageAdapter] (e.g. [SqliteStorageAdapter]) must be initialized
///   before passing it to this widget.
class NebulaCanvasGallery extends StatefulWidget {
  /// The storage adapter to use for listing/deleting canvases.
  final NebulaStorageAdapter storageAdapter;

  /// Called when a canvas is tapped. Use this to navigate to the canvas screen.
  final void Function(String canvasId) onCanvasSelected;

  /// Called when the user taps the "Create" button.
  /// Should return the new canvas ID, or null if creation was cancelled.
  /// If not provided, the FAB generates a UUID and calls [onCanvasSelected].
  final Future<String?> Function()? onCreateCanvas;

  /// Number of columns in the grid. Defaults to 2.
  final int gridColumns;

  /// Whether to show the floating action button for creating canvases.
  final bool showCreateButton;

  /// Whether to show the delete option on canvas cards.
  final bool showDeleteButton;

  /// Whether to show a search bar.
  final bool showSearchBar;

  /// Optional custom app bar title.
  final String? title;

  /// Optional custom empty state widget.
  final Widget Function()? emptyStateBuilder;

  /// Optional custom canvas card builder.
  /// If provided, replaces the default [_NebulaCanvasCard].
  final Widget Function(
    CanvasMetadata metadata,
    VoidCallback onTap,
    VoidCallback onDelete,
  )?
  canvasCardBuilder;

  /// Optional custom app bar.
  /// If provided, completely replaces the default app bar.
  final PreferredSizeWidget? appBar;

  const NebulaCanvasGallery({
    super.key,
    required this.storageAdapter,
    required this.onCanvasSelected,
    this.onCreateCanvas,
    this.gridColumns = 2,
    this.showCreateButton = true,
    this.showDeleteButton = true,
    this.showSearchBar = false,
    this.title,
    this.emptyStateBuilder,
    this.canvasCardBuilder,
    this.appBar,
  });

  @override
  State<NebulaCanvasGallery> createState() => _NebulaCanvasGalleryState();
}

class _NebulaCanvasGalleryState extends State<NebulaCanvasGallery>
    with TickerProviderStateMixin {
  List<CanvasMetadata> _canvases = [];
  List<CanvasMetadata> _filteredCanvases = [];
  bool _isLoading = true;
  String _searchQuery = '';
  late final AnimationController _fabAnimController;
  late final AnimationController _gridAnimController;

  @override
  void initState() {
    super.initState();
    _fabAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _gridAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _loadCanvases();
  }

  @override
  void dispose() {
    _fabAnimController.dispose();
    _gridAnimController.dispose();
    super.dispose();
  }

  Future<void> _loadCanvases() async {
    setState(() => _isLoading = true);
    try {
      await widget.storageAdapter.initialize();
      final canvases = await widget.storageAdapter.listCanvases();
      if (mounted) {
        setState(() {
          _canvases = canvases;
          _applyFilter();
          _isLoading = false;
        });
        _gridAnimController.forward(from: 0);
        _fabAnimController.forward(from: 0);
      }
    } catch (e) {
      debugPrint('[NebulaGallery] Error loading canvases: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _applyFilter() {
    if (_searchQuery.isEmpty) {
      _filteredCanvases = List.from(_canvases);
    } else {
      final query = _searchQuery.toLowerCase();
      _filteredCanvases =
          _canvases
              .where(
                (c) =>
                    (c.title?.toLowerCase().contains(query) ?? false) ||
                    c.canvasId.toLowerCase().contains(query),
              )
              .toList();
    }
  }

  Future<void> _deleteCanvas(CanvasMetadata canvas) async {
    final confirmed = await _showDeleteConfirmation(canvas);
    if (confirmed != true) return;

    try {
      await widget.storageAdapter.deleteCanvas(canvas.canvasId);
      HapticFeedback.mediumImpact();
      await _loadCanvases();
    } catch (e) {
      debugPrint('[NebulaGallery] Error deleting canvas: $e');
    }
  }

  Future<bool?> _showDeleteConfirmation(CanvasMetadata canvas) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor:
                isDark ? const Color(0xFF1C1B1F) : colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            icon: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.delete_outline_rounded,
                color: colorScheme.onErrorContainer,
                size: 28,
              ),
            ),
            title: const Text(
              'Delete Canvas',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            content: Text(
              'Delete "${canvas.title ?? "Untitled"}"?\nThis action cannot be undone.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? Colors.white60 : colorScheme.onSurfaceVariant,
              ),
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.error,
                  foregroundColor: colorScheme.onError,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Delete'),
              ),
            ],
          ),
    );
  }

  Future<void> _createCanvas() async {
    if (widget.onCreateCanvas != null) {
      final canvasId = await widget.onCreateCanvas!();
      if (canvasId != null) {
        widget.onCanvasSelected(canvasId);
      }
    } else {
      // Generate a simple unique ID
      final canvasId = 'canvas_${DateTime.now().millisecondsSinceEpoch}';
      widget.onCanvasSelected(canvasId);
    }
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF111113) : colorScheme.surface,
      appBar: widget.appBar ?? _buildDefaultAppBar(colorScheme, isDark),
      body: _buildBody(colorScheme, isDark),
      floatingActionButton:
          widget.showCreateButton
              ? ScaleTransition(
                scale: CurvedAnimation(
                  parent: _fabAnimController,
                  curve: Curves.elasticOut,
                ),
                child: FloatingActionButton.extended(
                  onPressed: _createCanvas,
                  backgroundColor: colorScheme.primaryContainer,
                  foregroundColor: colorScheme.onPrimaryContainer,
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text(
                    'New Canvas',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              )
              : null,
    );
  }

  PreferredSizeWidget _buildDefaultAppBar(
    ColorScheme colorScheme,
    bool isDark,
  ) {
    return AppBar(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title ?? 'My Canvases',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              color: isDark ? Colors.white : colorScheme.onSurface,
            ),
          ),
          if (!_isLoading)
            Text(
              '${_canvases.length} canvas${_canvases.length == 1 ? "" : "es"}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: isDark ? Colors.white38 : colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
      toolbarHeight: 72,
      actions: [
        if (widget.showSearchBar)
          IconButton(
            icon: Icon(
              Icons.search_rounded,
              color: isDark ? Colors.white70 : colorScheme.onSurfaceVariant,
            ),
            onPressed: () {
              // Toggle search — simple implementation
              showSearch(
                context: context,
                delegate: _CanvasSearchDelegate(
                  canvases: _canvases,
                  onSelect: widget.onCanvasSelected,
                  onDelete: widget.showDeleteButton ? _deleteCanvas : null,
                  cardBuilder: widget.canvasCardBuilder,
                ),
              );
            },
          ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildBody(ColorScheme colorScheme, bool isDark) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Loading canvases…',
              style: TextStyle(
                color: isDark ? Colors.white38 : colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    if (_canvases.isEmpty) {
      return widget.emptyStateBuilder?.call() ??
          _buildDefaultEmptyState(colorScheme, isDark);
    }

    return RefreshIndicator(
      onRefresh: _loadCanvases,
      color: colorScheme.primary,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        child: GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: widget.gridColumns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.78,
          ),
          itemCount: _filteredCanvases.length,
          itemBuilder: (context, index) {
            final canvas = _filteredCanvases[index];
            final delay = (index * 0.08).clamp(0.0, 0.5);

            return AnimatedBuilder(
              animation: _gridAnimController,
              builder: (context, child) {
                final progress = Curves.easeOutCubic.transform(
                  ((_gridAnimController.value - delay) / (1 - delay)).clamp(
                    0.0,
                    1.0,
                  ),
                );
                return Transform.translate(
                  offset: Offset(0, 30 * (1 - progress)),
                  child: Opacity(opacity: progress, child: child),
                );
              },
              child:
                  widget.canvasCardBuilder != null
                      ? widget.canvasCardBuilder!(
                        canvas,
                        () => widget.onCanvasSelected(canvas.canvasId),
                        () => _deleteCanvas(canvas),
                      )
                      : _NebulaCanvasCard(
                        metadata: canvas,
                        onTap: () => widget.onCanvasSelected(canvas.canvasId),
                        onDelete:
                            widget.showDeleteButton
                                ? () => _deleteCanvas(canvas)
                                : null,
                      ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildDefaultEmptyState(ColorScheme colorScheme, bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon with gradient background
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    colorScheme.primaryContainer,
                    colorScheme.tertiaryContainer,
                  ],
                ),
                borderRadius: BorderRadius.circular(28),
              ),
              child: Icon(
                Icons.brush_rounded,
                size: 44,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'No Canvases Yet',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
                color: isDark ? Colors.white : colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap the button below to create your first canvas\nand start drawing.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                height: 1.5,
                color: isDark ? Colors.white38 : colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _createCanvas,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Create Canvas'),
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.primaryContainer,
                foregroundColor: colorScheme.onPrimaryContainer,
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// 🎨 DEFAULT CANVAS CARD
// =============================================================================

class _NebulaCanvasCard extends StatelessWidget {
  final CanvasMetadata metadata;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const _NebulaCanvasCard({
    required this.metadata,
    required this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        onLongPress:
            onDelete != null
                ? () {
                  HapticFeedback.mediumImpact();
                  onDelete!();
                }
                : null,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            color:
                isDark
                    ? const Color(0xFF1C1B1F)
                    : colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color:
                  isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : colorScheme.outlineVariant.withValues(alpha: 0.3),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Canvas preview area
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: _getPreviewGradient(colorScheme, isDark),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(19),
                    ),
                  ),
                  child: Stack(
                    children: [
                      // Paper type icon
                      Center(
                        child: Icon(
                          _getPaperIcon(metadata.paperType),
                          size: 48,
                          color: (isDark ? Colors.white : colorScheme.primary)
                              .withValues(alpha: 0.15),
                        ),
                      ),
                      // Stroke count badge
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: (isDark ? Colors.black : Colors.white)
                                .withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.gesture_rounded,
                                size: 12,
                                color:
                                    isDark
                                        ? Colors.white60
                                        : colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${metadata.strokeCount}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color:
                                      isDark
                                          ? Colors.white60
                                          : colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Delete button
                      if (onDelete != null)
                        Positioned(
                          top: 10,
                          left: 10,
                          child: GestureDetector(
                            onTap: () {
                              HapticFeedback.mediumImpact();
                              onDelete!();
                            },
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: (isDark ? Colors.black : Colors.white)
                                    .withValues(alpha: 0.7),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.delete_outline_rounded,
                                size: 16,
                                color: colorScheme.error,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              // Info section
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      metadata.title ?? 'Untitled',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                        color: isDark ? Colors.white : colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.layers_rounded,
                          size: 13,
                          color:
                              isDark
                                  ? Colors.white30
                                  : colorScheme.onSurfaceVariant.withValues(
                                    alpha: 0.6,
                                  ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${metadata.layerCount} layer${metadata.layerCount == 1 ? "" : "s"}',
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                isDark
                                    ? Colors.white30
                                    : colorScheme.onSurfaceVariant.withValues(
                                      alpha: 0.6,
                                    ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          _formatDate(metadata.updatedAt),
                          style: TextStyle(
                            fontSize: 11,
                            color:
                                isDark
                                    ? Colors.white24
                                    : colorScheme.onSurfaceVariant.withValues(
                                      alpha: 0.4,
                                    ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  LinearGradient _getPreviewGradient(ColorScheme colorScheme, bool isDark) {
    // Generate a unique-ish gradient per canvas based on ID hash
    final hash = metadata.canvasId.hashCode;
    final hue = (hash % 360).abs().toDouble();

    if (isDark) {
      return LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          HSLColor.fromAHSL(1, hue, 0.3, 0.15).toColor(),
          HSLColor.fromAHSL(1, (hue + 40) % 360, 0.25, 0.10).toColor(),
        ],
      );
    }
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        HSLColor.fromAHSL(1, hue, 0.25, 0.94).toColor(),
        HSLColor.fromAHSL(1, (hue + 40) % 360, 0.20, 0.90).toColor(),
      ],
    );
  }

  IconData _getPaperIcon(String paperType) {
    switch (paperType) {
      case 'lines':
      case 'lines_narrow':
        return Icons.horizontal_rule_rounded;
      case 'grid_5mm':
      case 'grid_1cm':
      case 'grid_2cm':
        return Icons.grid_on_rounded;
      case 'dots':
      case 'dots_dense':
        return Icons.grain_rounded;
      case 'music':
        return Icons.music_note_rounded;
      default:
        return Icons.crop_landscape_rounded;
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return 'Now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    if (diff.inDays < 365) {
      return '${date.day}/${date.month}';
    }
    return '${date.day}/${date.month}/${date.year}';
  }
}

// =============================================================================
// 🔍 SEARCH DELEGATE
// =============================================================================

class _CanvasSearchDelegate extends SearchDelegate<String?> {
  final List<CanvasMetadata> canvases;
  final void Function(String canvasId) onSelect;
  final void Function(CanvasMetadata canvas)? onDelete;
  final Widget Function(
    CanvasMetadata metadata,
    VoidCallback onTap,
    VoidCallback onDelete,
  )?
  cardBuilder;

  _CanvasSearchDelegate({
    required this.canvases,
    required this.onSelect,
    this.onDelete,
    this.cardBuilder,
  });

  @override
  String get searchFieldLabel => 'Search canvases…';

  @override
  List<Widget> buildActions(BuildContext context) => [
    if (query.isNotEmpty)
      IconButton(
        icon: const Icon(Icons.clear_rounded),
        onPressed: () => query = '',
      ),
  ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
    icon: const Icon(Icons.arrow_back_rounded),
    onPressed: () => close(context, null),
  );

  @override
  Widget buildResults(BuildContext context) => _buildSearchResults(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildSearchResults(context);

  Widget _buildSearchResults(BuildContext context) {
    final q = query.toLowerCase();
    final results =
        canvases
            .where(
              (c) =>
                  (c.title?.toLowerCase().contains(q) ?? false) ||
                  c.canvasId.toLowerCase().contains(q),
            )
            .toList();

    if (results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 48,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'No canvases found',
              style: TextStyle(color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final canvas = results[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.brush_rounded,
                color: Theme.of(context).colorScheme.primary,
                size: 22,
              ),
            ),
            title: Text(canvas.title ?? 'Untitled'),
            subtitle: Text(
              '${canvas.layerCount} layers · ${canvas.strokeCount} strokes',
              style: const TextStyle(fontSize: 12),
            ),
            onTap: () {
              close(context, canvas.canvasId);
              onSelect(canvas.canvasId);
            },
          ),
        );
      },
    );
  }
}
