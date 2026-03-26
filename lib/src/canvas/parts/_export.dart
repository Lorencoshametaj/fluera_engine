part of '../fluera_canvas_screen.dart';

/// 📦 Export & Multi-Page — generic SDK implementation.
///
/// Multi-page canvas math is kept in-SDK (pure state operations).
/// Export UI and actual file generation are delegated to the host app
/// via `_config.onShowExportDialog`.
extension ExportExtension on _FlueraCanvasScreenState {
  /// Enter export mode — directly opens multi-page editing.
  void _enterExportMode() {
    _enterMultiPageEditMode(
      mode: MultiPageMode.uniform,
      pageFormat: _exportConfig.pageFormat,
      maxPages: 20,
    );
    
    // 🔍 Detect content clusters for smart navigation
    _detectExportClusters();

    // 🪄 Zero-Touch Auto-Framing: inquadra il primo cluster (o tutto)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        if (_exportClusters.length > 1) {
          // Multiple clusters: frame the first one
          _currentClusterIndex = 0;
          _autoFrameCluster(_exportClusters[0]);
        } else {
          // Single cluster or empty: frame everything
          _currentClusterIndex = -1;
          _autoFrameMultiPage();
        }
      }
    });
  }

  // ============================================================================
  // 🔍 CLUSTER-AWARE EXPORT
  // ============================================================================

  /// Detect logical content clusters across all visible layers.
  void _detectExportClusters() {
    const detector = ClusterDetector();
    final allClusters = <ContentCluster>[];

    for (final layer in _layerController.layers) {
      if (!layer.isVisible) continue;
      final clusters = detector.detect(
        strokes: layer.strokes,
        shapes: layer.shapes,
        texts: layer.texts,
        images: layer.images,
      );
      allClusters.addAll(clusters);
    }

    // Sort clusters by position (top-left to bottom-right, reading order)
    allClusters.sort((a, b) {
      final rowDiff = (a.bounds.top / 200).floor() - (b.bounds.top / 200).floor();
      if (rowDiff != 0) return rowDiff;
      return a.bounds.left.compareTo(b.bounds.left);
    });

    setState(() {
      _exportClusters = allClusters;
      _currentClusterIndex = allClusters.length > 1 ? 0 : -1;
    });
  }

  /// Auto-frame a specific cluster (with cinematic fly-out).
  void _autoFrameCluster(ContentCluster cluster) {
    _frameBounds(cluster.bounds.inflate(30.0));
  }

  /// Navigate to the next cluster.
  void _nextExportCluster() {
    if (_exportClusters.isEmpty) return;
    setState(() {
      _currentClusterIndex = (_currentClusterIndex + 1) % _exportClusters.length;
    });
    _autoFrameCluster(_exportClusters[_currentClusterIndex]);
  }

  /// Navigate to the previous cluster.
  void _prevExportCluster() {
    if (_exportClusters.isEmpty) return;
    setState(() {
      _currentClusterIndex = _currentClusterIndex <= 0
          ? _exportClusters.length - 1
          : _currentClusterIndex - 1;
    });
    _autoFrameCluster(_exportClusters[_currentClusterIndex]);
  }

  /// Frame all content (exit cluster navigation).
  void _frameAllClusters() {
    setState(() {
      _currentClusterIndex = -1;
    });
    _autoFrameMultiPage();
  }

  /// Exit export mode.
  void _exitExportMode() {
    setState(() {
      _isExportMode = false;
      _exportArea = Rect.zero;
      _exportClusters = const [];
      _currentClusterIndex = -1;
    });
  }

  /// Update export area bounds.
  void _onExportAreaChanged(Rect newArea) {
    setState(() {
      _exportArea = newArea;
    });
  }

  /// Update export configuration.
  void _onExportConfigChanged(ExportConfig config) {
    setState(() {
      _exportConfig = config;
    });
  }

  /// Apply a preset to the export area.
  void _applyExportPreset(ExportPreset preset) {
    final size = preset.getSizeAtDpi(_exportConfig.quality.dpi.toDouble());
    if (size == Size.zero) return;

    final newArea = Rect.fromCenter(
      center: _exportArea.center,
      width: size.width,
      height: size.height,
    );

    setState(() {
      _exportArea = newArea;
    });
    HapticFeedback.selectionClick();
  }

  /// Load a saved export area.
  void _loadSavedExportArea(SavedExportArea savedArea) {
    setState(() {
      _exportArea = savedArea.bounds;
    });
    HapticFeedback.selectionClick();
  }

  // ============================================================================
  // 📤 MULTI-PAGE EDIT MODE
  // ============================================================================

  /// Enter multi-page edit mode.
  void _enterMultiPageEditMode({
    MultiPageMode mode = MultiPageMode.uniform,
    ExportPageFormat pageFormat = ExportPageFormat.a4Portrait,
    int maxPages = 20,
    MultiPageConfig? existingConfig,
  }) {
    if (existingConfig != null && existingConfig.pageCount > 0) {
      setState(() {
        _isMultiPageEditMode = true;
        _multiPageConfig = existingConfig;
      });
      HapticFeedback.mediumImpact();
      return;
    }

    // Calculate canvas area centered on current viewport
    final screenSize = MediaQuery.of(context).size;
    final viewportCenterScreen = Offset(
      screenSize.width / 2,
      screenSize.height / 2,
    );
    final viewportCenterCanvas = Offset(
      (viewportCenterScreen.dx - _canvasController.offset.dx) /
          _canvasController.scale,
      (viewportCenterScreen.dy - _canvasController.offset.dy) /
          _canvasController.scale,
    );

    final viewportWidth = screenSize.width / _canvasController.scale;
    final viewportHeight = screenSize.height / _canvasController.scale;
    final canvasArea = Rect.fromCenter(
      center: viewportCenterCanvas,
      width: viewportWidth * 0.8,
      height: viewportHeight * 0.8,
    );

    setState(() {
      _isMultiPageEditMode = true;
      _multiPageConfig = MultiPageConfig.initial(
        canvasArea: canvasArea,
        mode: mode,
        pageFormat: pageFormat,
        quality: _exportConfig.quality,
        maxPages: maxPages,
      );
    });
    HapticFeedback.mediumImpact();
  }

  /// Exit multi-page edit mode.
  void _exitMultiPageEditMode({bool saveChanges = true}) {
    if (saveChanges && _multiPageConfig.individualPageBounds.isNotEmpty) {
      Rect totalArea = _multiPageConfig.individualPageBounds.first;
      for (final bounds in _multiPageConfig.individualPageBounds.skip(1)) {
        totalArea = totalArea.expandToInclude(bounds);
      }
      _exportArea = totalArea;
    }

    setState(() {
      _isMultiPageEditMode = false;
      _exportClusters = const [];
      _currentClusterIndex = -1;
    });
    HapticFeedback.selectionClick();
  }

  /// Update multi-page config.
  void _onMultiPageConfigChanged(MultiPageConfig config) {
    setState(() {
      _multiPageConfig = config;
    });
  }

  /// Handle auto-pan during page dragging.
  void _onMultiPageAutoPan(Offset panDelta) {
    final currentOffset = _canvasController.offset;
    _canvasController.setOffset(
      Offset(currentOffset.dx - panDelta.dx, currentOffset.dy - panDelta.dy),
    );
  }

  /// Change page layout mode (uniform/individual).
  void _onMultiPageModeChanged(MultiPageMode mode) {
    setState(() {
      _multiPageConfig = _multiPageConfig.copyWith(mode: mode);
    });
  }

  /// Change uniform page format.
  void _onMultiPageFormatChanged(ExportPageFormat format) {
    final pageSizeInPoints = format.sizeInPoints;
    final aspectRatio = pageSizeInPoints.width / pageSizeInPoints.height;

    if (_multiPageConfig.individualPageBounds.isNotEmpty) {
      final firstPage = _multiPageConfig.individualPageBounds.first;
      final newWidth = firstPage.height * aspectRatio;
      final newSize = Size(newWidth, firstPage.height);
      final newBounds =
          _multiPageConfig.individualPageBounds.map((bounds) {
            return Rect.fromLTWH(
              bounds.left,
              bounds.top,
              newWidth,
              bounds.height,
            );
          }).toList();

      setState(() {
        _multiPageConfig = _multiPageConfig.copyWith(
          pageFormat: format,
          uniformPageSize: newSize,
          individualPageBounds: newBounds,
        );
      });
    } else {
      setState(() {
        _multiPageConfig = _multiPageConfig.copyWith(pageFormat: format);
      });
    }
  }

  /// Add a new page.
  void _addMultiPagePage() {
    if (!_multiPageConfig.canAddPage) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Maximum of ${_multiPageConfig.maxPages} pages reached',
          ),
          backgroundColor: const Color(0xFFF57C00),
        ),
      );
      return;
    }

    final screenSize = MediaQuery.of(context).size;
    final viewportCenterScreen = Offset(
      screenSize.width / 2,
      (screenSize.height - 150) / 2,
    );
    final viewportCenterCanvas = Offset(
      (viewportCenterScreen.dx - _canvasController.offset.dx) /
          _canvasController.scale,
      (viewportCenterScreen.dy - _canvasController.offset.dy) /
          _canvasController.scale,
    );

    setState(() {
      _multiPageConfig = _multiPageConfig.addPageAtCenter(viewportCenterCanvas);
    });
    HapticFeedback.selectionClick();
  }

  /// Remove the selected page.
  void _removeMultiPagePage() {
    if (!_multiPageConfig.canRemovePage) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Must keep at least one page'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _multiPageConfig = _multiPageConfig.removeSelectedPage();
    });
    HapticFeedback.selectionClick();
  }

  /// Select a page for editing.
  void _selectMultiPagePage(int index) {
    if (index >= 0 && index < _multiPageConfig.pageCount) {
      setState(() {
        _multiPageConfig = _multiPageConfig.copyWith(selectedPageIndex: index);
      });
    }
  }

  /// Update page bounds.
  void _updateMultiPagePageBounds(int index, Rect newBounds) {
    setState(() {
      _multiPageConfig = _multiPageConfig.updatePageBounds(index, newBounds);
    });
  }

  /// Reorganize pages in a grid.
  void _reorganizeMultiPages({int columns = 2, double spacing = 20}) {
    final canvasArea =
        _exportArea.isEmpty
            ? Rect.fromLTWH(0, 0, _canvasSize.width, _canvasSize.height)
            : _exportArea;

    setState(() {
      _multiPageConfig = _multiPageConfig.reorganizeAsGrid(
        canvasArea,
        columns: columns,
        spacing: spacing,
      );
    });
    HapticFeedback.mediumImpact();
  }

  /// 🔄 TOGGLE MODE: Passa da griglia (A4) a Freeform (Infinite)
  void _toggleMultiPageMode() {
    final newMode = _multiPageConfig.mode == MultiPageMode.uniform
        ? MultiPageMode.individual
        : MultiPageMode.uniform;

    setState(() {
      _multiPageConfig = _multiPageConfig.copyWith(
        mode: newMode,
      );
    });
    HapticFeedback.selectionClick();
    
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          newMode == MultiPageMode.uniform
              ? 'Modalità Griglia (Pagine fisse)'
              : 'Modalità Libera (Freeform)',
          textAlign: TextAlign.center,
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        width: 250,
      ),
    );
  }

  /// 🔲 TOGGLE BACKGROUND: Alterna trasparenza o sfondo originale
  void _toggleExportBackground() {
    final isTransparent = _exportConfig.background == ExportBackground.transparent;
    final newBackground = isTransparent ? ExportBackground.withTemplate : ExportBackground.transparent;

    setState(() {
      _exportConfig = _exportConfig.copyWith(background: newBackground);
    });
    HapticFeedback.selectionClick();

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          newBackground == ExportBackground.transparent
              ? 'Sfondo Esportazione: Trasparente'
              : 'Sfondo Esportazione: Con Griglia/Template',
          textAlign: TextAlign.center,
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        width: 320,
      ),
    );
  }

  /// 🎥 CINEMATIC FLY-OUT: Anima la videocamera per inquadrare le pagine generate
  void _cinematicFlyOut(List<Rect> boundingBoxes) {
    if (boundingBoxes.isEmpty) return;

    Rect totalRect = boundingBoxes.first;
    for (var b in boundingBoxes) {
      totalRect = totalRect.expandToInclude(b);
    }

    // Padding per non far toccare i bordi allo schermo
    final viewRect = totalRect.inflate(60.0);
    
    final viewportSize = MediaQuery.of(context).size;
    final scaleX = viewportSize.width / viewRect.width;
    final scaleY = viewportSize.height / viewRect.height;
    
    // clamp tra 0.05 e 2.0 in modo da non zoomare dentro roba minuscola o fuori troppo
    final targetScale = math.min(scaleX, scaleY).clamp(0.05, 2.0);

    final targetOffset = Offset(
      viewportSize.width / 2 - viewRect.center.dx * targetScale,
      viewportSize.height / 2 - viewRect.center.dy * targetScale,
    );

    _canvasController.animateToTransform(
      targetOffset: targetOffset,
      targetScale: targetScale,
    );
  }

  /// 🪄 SMART AUTO-FRAMING: Inquadra automaticamente tutti i contenuti del canvas
  /// (oppure SOLO la selezione attiva se si usa il Lazo).
  void _autoFrameMultiPage() {
    Rect contentBounds;
    bool isLassoSelection = false;

    if (_lassoTool.hasSelection && _lassoTool.exportBounds != null && !_lassoTool.exportBounds!.isEmpty) {
      contentBounds = _lassoTool.exportBounds!;
      isLassoSelection = true;
    } else {
      contentBounds = _contentBoundsTracker.bounds.value;
    }

    if (contentBounds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nessun contenuto da inquadrare'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    _frameBounds(contentBounds.inflate(isLassoSelection ? 20.0 : 40.0));
  }

  /// 🎯 Core framing logic: computes page bounds for a given target rect,
  /// updates config, triggers haptics + cinematic fly-out.
  void _frameBounds(Rect paddedBounds) {
    if (_multiPageConfig.mode == MultiPageMode.individual) {
      setState(() {
        _multiPageConfig = _multiPageConfig.copyWith(
          individualPageBounds: [paddedBounds],
          selectedPageIndex: 0,
        );
      });
    } else {
      final pageSize = _multiPageConfig.uniformPageSize ??
          const Size(800, 1131);

      final cols = (paddedBounds.width / pageSize.width).ceil().clamp(1, 10);
      final rows = (paddedBounds.height / pageSize.height).ceil().clamp(1, 10);

      final gridWidth = cols * pageSize.width;
      final gridHeight = rows * pageSize.height;
      final startX = paddedBounds.center.dx - (gridWidth / 2);
      final startY = paddedBounds.center.dy - (gridHeight / 2);

      final newBounds = <Rect>[];
      for (int r = 0; r < rows; r++) {
        for (int c = 0; c < cols; c++) {
          newBounds.add(Rect.fromLTWH(
            startX + c * pageSize.width,
            startY + r * pageSize.height,
            pageSize.width,
            pageSize.height,
          ));
        }
      }

      if (newBounds.length > _multiPageConfig.maxPages) {
        newBounds.removeRange(_multiPageConfig.maxPages, newBounds.length);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Limite di ${_multiPageConfig.maxPages} pagine raggiunto'),
            backgroundColor: Colors.orange,
          ),
        );
      }

      setState(() {
        _multiPageConfig = _multiPageConfig.copyWith(
          individualPageBounds: newBounds,
          selectedPageIndex: 0,
        );
      });
    }

    HapticFeedback.mediumImpact();
    _cinematicFlyOut(_multiPageConfig.individualPageBounds);
  }

  /// Confirm multi-page edit and proceed to export dialog.
  void _confirmMultiPageEdit() {
    _exitMultiPageEditMode(saveChanges: true);

    setState(() {
      _exportConfig = _exportConfig.copyWith(multiPage: true);
    });

    _showExportFormatDialog();
  }

  /// Show the export dialog via the host app's callback.
  void _showExportFormatDialog() {
    final multiPageConfig =
        _multiPageConfig.pageCount > 0 ? _multiPageConfig : null;

    final exportData = FlueraExportData(
      canvasId: _canvasId,
      layers: _layerController.layers,
      backgroundColor: _canvasBackgroundColor,
      exportArea: _exportArea,
      exportConfig: _exportConfig,
      paperType: _paperType,
      multiPageConfig: multiPageConfig,
    );

    if (_config.onShowExportDialog != null) {
      _config.onShowExportDialog!(context, exportData).then((_) {
        if (mounted) _exitExportMode();
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Export not configured in this app'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }
}
