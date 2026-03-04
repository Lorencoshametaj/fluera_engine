// ============================================================================
// 🖼️ FLUERA CANVAS GALLERY — Material Design 3 Canvas Management Screen
//
// Pre-built widget for browsing, creating, and deleting canvases.
// Follows Material Design 3 guidelines with proper ColorScheme tokens,
// typography hierarchy, and motion patterns.
//
// USAGE (zero config):
//   FlueraCanvasGallery(
//     storageAdapter: storage,
//     onCanvasSelected: (id) => navigateTo(id),
//   )
//
// USAGE (custom):
//   FlueraCanvasGallery(
//     storageAdapter: storage,
//     onCanvasSelected: (id) => navigateTo(id),
//     gridColumns: 3,
//     canvasCardBuilder: (meta, onTap, onDelete) => MyCard(...),
//     emptyStateBuilder: () => MyEmptyState(),
//   )
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../storage/fluera_storage_adapter.dart';

/// 🖼️ Canvas gallery widget for browsing, creating, and deleting canvases.
///
/// Provides a Material Design 3 grid view of all stored canvases with:
/// - Animated card grid with metadata (title, stroke count, date)
/// - Create new canvas FAB
/// - Swipe-to-delete with confirmation
/// - Full customization via builders
///
/// REQUIREMENTS:
/// - A [FlueraStorageAdapter] (e.g. [SqliteStorageAdapter]) must be initialized
///   before passing it to this widget.
class FlueraCanvasGallery extends StatefulWidget {
  /// The storage adapter to use for listing/deleting canvases.
  final FlueraStorageAdapter storageAdapter;

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
  /// If provided, replaces the default [_FlueraCanvasCard].
  final Widget Function(
    CanvasMetadata metadata,
    VoidCallback onTap,
    VoidCallback onDelete,
  )?
  canvasCardBuilder;

  /// Optional custom app bar.
  /// If provided, completely replaces the default app bar.
  final PreferredSizeWidget? appBar;

  const FlueraCanvasGallery({
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
  State<FlueraCanvasGallery> createState() => _FlueraCanvasGalleryState();
}

class _FlueraCanvasGalleryState extends State<FlueraCanvasGallery>
    with TickerProviderStateMixin {
  List<CanvasMetadata> _canvases = [];
  List<CanvasMetadata> _filteredCanvases = [];
  bool _isLoading = true;
  String _searchQuery = '';
  bool _isSearchOpen = false;
  bool _pendingRefresh = false;

  late final AnimationController _fabController;
  late final AnimationController _gridController;
  late final AnimationController _headerController;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _fabController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _gridController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _headerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _loadCanvases();
  }

  @override
  void dispose() {
    _fabController.dispose();
    _gridController.dispose();
    _headerController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
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
        _headerController.forward(from: 0);
        _gridController.forward(from: 0);
        _fabController.forward(from: 0);
      }
    } catch (e) {
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

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Deleted "${canvas.title ?? "Untitled"}"'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
    }
  }

  Future<bool?> _showDeleteConfirmation(CanvasMetadata canvas) {
    final colorScheme = Theme.of(context).colorScheme;

    return showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            icon: Icon(
              Icons.delete_outline_rounded,
              color: colorScheme.error,
              size: 28,
            ),
            title: const Text('Delete Canvas?'),
            content: Text(
              '"${canvas.title ?? "Untitled"}" will be permanently deleted.\n'
              'This action cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.error,
                  foregroundColor: colorScheme.onError,
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
        _pendingRefresh = true;
        widget.onCanvasSelected(canvasId);
      }
    } else {
      final canvasId = 'canvas_${DateTime.now().millisecondsSinceEpoch}';
      _pendingRefresh = true;
      widget.onCanvasSelected(canvasId);
    }
  }

  void _toggleSearch() {
    setState(() {
      _isSearchOpen = !_isSearchOpen;
      if (!_isSearchOpen) {
        _searchController.clear();
        _searchQuery = '';
        _applyFilter();
      } else {
        _searchFocusNode.requestFocus();
      }
    });
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Auto-refresh after returning from canvas screen
    if (_pendingRefresh && !_isLoading) {
      _pendingRefresh = false;
      // Schedule refresh for after current build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadCanvases();
      });
    }

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: NestedScrollView(
        headerSliverBuilder:
            (context, innerBoxIsScrolled) => [
              widget.appBar != null
                  ? SliverToBoxAdapter(child: widget.appBar!)
                  : _buildSliverAppBar(colorScheme, theme),
            ],
        body: _buildBody(colorScheme, theme),
      ),
      floatingActionButton:
          widget.showCreateButton ? _buildFAB(colorScheme) : null,
    );
  }

  // ── Sliver App Bar ─────────────────────────────────────────────────────────

  Widget _buildSliverAppBar(ColorScheme colorScheme, ThemeData theme) {
    return SliverAppBar.large(
      expandedHeight: _isSearchOpen ? 140 : 120,
      pinned: true,
      backgroundColor: colorScheme.surface,
      surfaceTintColor: colorScheme.surfaceTint,
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
        title: AnimatedBuilder(
          animation: _headerController,
          builder: (context, child) {
            final opacity = Curves.easeOut.transform(
              _headerController.value.clamp(0.0, 1.0),
            );
            return Opacity(opacity: opacity, child: child);
          },
          child: Text(
            widget.title ?? 'My Canvases',
            style: TextStyle(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
      actions: [
        if (!_isLoading && _canvases.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: _CanvasCountChip(
              count: _canvases.length,
              colorScheme: colorScheme,
            ),
          ),
        if (widget.showSearchBar)
          IconButton(
            icon: Icon(
              _isSearchOpen ? Icons.close_rounded : Icons.search_rounded,
            ),
            onPressed: _toggleSearch,
            tooltip: _isSearchOpen ? 'Close search' : 'Search',
          ),
        const SizedBox(width: 8),
      ],
      bottom:
          _isSearchOpen
              ? PreferredSize(
                preferredSize: const Size.fromHeight(56),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: SearchBar(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    hintText: 'Search canvases…',
                    leading: const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(Icons.search_rounded, size: 20),
                    ),
                    trailing:
                        _searchQuery.isNotEmpty
                            ? [
                              IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {
                                    _searchQuery = '';
                                    _applyFilter();
                                  });
                                },
                              ),
                            ]
                            : null,
                    elevation: const WidgetStatePropertyAll(0),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                        _applyFilter();
                      });
                    },
                  ),
                ),
              )
              : null,
    );
  }

  // ── FAB ────────────────────────────────────────────────────────────────────

  Widget _buildFAB(ColorScheme colorScheme) {
    return ScaleTransition(
      scale: CurvedAnimation(parent: _fabController, curve: Curves.elasticOut),
      child: FloatingActionButton.extended(
        onPressed: _createCanvas,
        elevation: 2,
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'New Canvas',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  // ── Body ───────────────────────────────────────────────────────────────────

  Widget _buildBody(ColorScheme colorScheme, ThemeData theme) {
    if (_isLoading) {
      return _buildLoadingState(colorScheme);
    }

    if (_canvases.isEmpty) {
      return widget.emptyStateBuilder?.call() ??
          _buildEmptyState(colorScheme, theme);
    }

    if (_filteredCanvases.isEmpty && _searchQuery.isNotEmpty) {
      return _buildNoResultsState(colorScheme);
    }

    return RefreshIndicator(
      onRefresh: _loadCanvases,
      color: colorScheme.primary,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        child: GridView.builder(
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 200,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.82,
          ),
          itemCount: _filteredCanvases.length,
          itemBuilder: (context, index) {
            final canvas = _filteredCanvases[index];
            final delay = (index * 0.06).clamp(0.0, 0.4);

            return AnimatedBuilder(
              animation: _gridController,
              builder: (context, child) {
                final t = Curves.easeOutCubic.transform(
                  ((_gridController.value - delay) / (1 - delay)).clamp(
                    0.0,
                    1.0,
                  ),
                );
                return Transform.translate(
                  offset: Offset(0, 24 * (1 - t)),
                  child: Opacity(opacity: t, child: child),
                );
              },
              child:
                  widget.canvasCardBuilder != null
                      ? widget.canvasCardBuilder!(canvas, () {
                        _pendingRefresh = true;
                        widget.onCanvasSelected(canvas.canvasId);
                      }, () => _deleteCanvas(canvas))
                      : _FlueraCanvasCard(
                        metadata: canvas,
                        onTap: () {
                          _pendingRefresh = true;
                          widget.onCanvasSelected(canvas.canvasId);
                        },
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

  // ── Loading State ──────────────────────────────────────────────────────────

  Widget _buildLoadingState(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              strokeCap: StrokeCap.round,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Loading canvases…',
            style: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  // ── Empty State ────────────────────────────────────────────────────────────

  Widget _buildEmptyState(ColorScheme colorScheme, ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Large tonal icon
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                Icons.brush_rounded,
                size: 36,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No Canvases Yet',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Create your first canvas to start drawing.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            FilledButton.tonalIcon(
              onPressed: _createCanvas,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Create Canvas'),
            ),
          ],
        ),
      ),
    );
  }

  // ── No Results State ───────────────────────────────────────────────────────

  Widget _buildNoResultsState(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 48,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'No canvases match "$_searchQuery"',
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// 🎨 CANVAS COUNT CHIP (app bar trailing)
// =============================================================================

class _CanvasCountChip extends StatelessWidget {
  final int count;
  final ColorScheme colorScheme;

  const _CanvasCountChip({required this.count, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

// =============================================================================
// 🎨 DEFAULT CANVAS CARD — Material Design 3 Filled Card
// =============================================================================

class _FlueraCanvasCard extends StatelessWidget {
  final CanvasMetadata metadata;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const _FlueraCanvasCard({
    required this.metadata,
    required this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        onLongPress:
            onDelete != null
                ? () {
                  HapticFeedback.mediumImpact();
                  onDelete!();
                }
                : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Preview Area ─────────────────────────────────────
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: _buildPreviewGradient(colorScheme),
                ),
                child: Stack(
                  children: [
                    // Paper icon watermark
                    Center(
                      child: Icon(
                        _paperIcon,
                        size: 44,
                        color: colorScheme.onSurface.withValues(alpha: 0.06),
                      ),
                    ),
                    // Stroke count badge (top-right)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: _MetadataBadge(
                        icon: Icons.gesture_rounded,
                        label: '${metadata.strokeCount}',
                        colorScheme: colorScheme,
                      ),
                    ),
                    // Delete button (top-left)
                    if (onDelete != null)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: _CardActionButton(
                          icon: Icons.delete_outline_rounded,
                          color: colorScheme.error,
                          onTap: () {
                            HapticFeedback.mediumImpact();
                            onDelete!();
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // ── Info Section ─────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    metadata.title ?? 'Untitled',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.layers_outlined,
                        size: 13,
                        color: colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.7,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${metadata.layerCount} layer${metadata.layerCount == 1 ? "" : "s"}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.7,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _formatDate(metadata.updatedAt),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.5,
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
    );
  }

  LinearGradient _buildPreviewGradient(ColorScheme colorScheme) {
    // Deterministic gradient based on canvas ID hash
    final hash = metadata.canvasId.hashCode.abs();
    final hue = (hash % 360).toDouble();

    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        HSLColor.fromAHSL(1, hue, 0.12, 0.94).toColor(),
        HSLColor.fromAHSL(1, (hue + 30) % 360, 0.10, 0.90).toColor(),
      ],
    );
  }

  IconData get _paperIcon {
    switch (metadata.paperType) {
      case 'lines':
      case 'lines_narrow':
        return Icons.horizontal_rule_rounded;
      case 'grid_5mm':
      case 'grid_1cm':
      case 'grid_2cm':
        return Icons.grid_4x4_rounded;
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
    if (diff.inDays < 365) return '${date.day}/${date.month}';
    return '${date.day}/${date.month}/${date.year}';
  }
}

// =============================================================================
// 🏷️ METADATA BADGE (stroke count, layer count)
// =============================================================================

class _MetadataBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final ColorScheme colorScheme;

  const _MetadataBadge({
    required this.icon,
    required this.label,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// 🔘 CARD ACTION BUTTON (delete/more)
// =============================================================================

class _CardActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _CardActionButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainerHighest,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 16, color: color),
        ),
      ),
    );
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
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
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              'No canvases found',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
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
          padding: const EdgeInsets.only(bottom: 4),
          child: ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.brush_rounded,
                color: colorScheme.onPrimaryContainer,
                size: 20,
              ),
            ),
            title: Text(
              canvas.title ?? 'Untitled',
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            subtitle: Text(
              '${canvas.layerCount} layers · ${canvas.strokeCount} strokes',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            trailing: Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
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
