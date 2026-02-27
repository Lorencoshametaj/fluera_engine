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
  }

  /// Exit export mode.
  void _exitExportMode() {
    setState(() {
      _isExportMode = false;
      _exportArea = Rect.zero;
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
      debugPrint('[Export] No onShowExportDialog configured');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Export not configured in this app'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }
}
