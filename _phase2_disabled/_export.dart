part of '../nebula_canvas_screen.dart';

/// 📦 Export & Multi-Page — extracted from _NebulaCanvasScreenState
extension on _NebulaCanvasScreenState {
  /// Entra in modalità export - va direttamente a "Personalizza Pagine"
  void _enterExportMode() {
    // Entra direttamente in modalità personalizza pagine
    _enterMultiPageEditMode(
      mode: MultiPageMode.uniform,
      pageFormat: _exportConfig.pageFormat,
      maxPages: 20,
    );
  }

  /// Esce dalla modalità export
  void _exitExportMode() {
    setState(() {
      _isExportMode = false;
      _exportArea = Rect.zero;
    });
  }

  /// Aggiorna l'area di export
  void _onExportAreaChanged(Rect newArea) {
    setState(() {
      _exportArea = newArea;
    });
  }

  /// Aggiorna la configurazione export
  void _onExportConfigChanged(ExportConfig config) {
    setState(() {
      _exportConfig = config;
    });
  }

  /// Applica un preset all'area di export
  void _applyExportPreset(ExportPreset preset) {
    final size = preset.getSizeAtDpi(_exportConfig.quality.dpi.toDouble());

    // Se size è zero, usa aspect ratio
    if (size == Size.zero) return;

    // Centra il nuovo rect sull'area esistente
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

  /// Carica un'area salvata
  void _loadSavedExportArea(SavedExportArea savedArea) {
    setState(() {
      _exportArea = savedArea.bounds;
    });

    HapticFeedback.selectionClick();
  }

  // ============================================================================
  // 📤 MULTI-PAGE EDIT MODE METHODS
  // ============================================================================

  /// Entra in modalità editing multi-pagina
  void _enterMultiPageEditMode({
    MultiPageMode mode = MultiPageMode.uniform,
    ExportPageFormat pageFormat = ExportPageFormat.a4Portrait,
    int maxPages = 20,
    MultiPageConfig? existingConfig,
  }) {
    // Se abbiamo una config esistente, usala direttamente
    if (existingConfig != null && existingConfig.pageCount > 0) {
      {}
      {}
      {}

      setState(() {
        _isMultiPageEditMode = true;
        _multiPageConfig = existingConfig;
      });

      HapticFeedback.mediumImpact();
      return;
    }

    // Altrimenti crea una nuova config
    // Calcola il centro del viewport in coordinate canvas
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

    // Crea sempre un'area centrata nel viewport corrente
    // La dimensione dell'area è proporzionale alla scala del canvas
    final viewportWidth = screenSize.width / _canvasController.scale;
    final viewportHeight = screenSize.height / _canvasController.scale;

    final canvasArea = Rect.fromCenter(
      center: viewportCenterCanvas,
      width: viewportWidth * 0.8,
      height: viewportHeight * 0.8,
    );

    {}
    {}
    {}
    {}
    {}

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

    {}

    HapticFeedback.mediumImpact();
  }

  /// Esce dalla modalità editing multi-pagina
  void _exitMultiPageEditMode({bool saveChanges = true}) {
    if (saveChanges && _multiPageConfig.individualPageBounds.isNotEmpty) {
      // Calcola l'area totale che racchiude tutte le pagine
      Rect totalArea = _multiPageConfig.individualPageBounds.first;
      for (final bounds in _multiPageConfig.individualPageBounds.skip(1)) {
        totalArea = totalArea.expandToInclude(bounds);
      }

      // Aggiorna l'area di export
      _exportArea = totalArea;
    }

    setState(() {
      _isMultiPageEditMode = false;
    });

    HapticFeedback.selectionClick();
  }

  /// Aggiorna la configurazione multi-pagina
  void _onMultiPageConfigChanged(MultiPageConfig config) {
    setState(() {
      _multiPageConfig = config;
    });
  }

  /// Gestisce l'auto-pan del canvas durante il trascinamento delle pagine
  void _onMultiPageAutoPan(Offset panDelta) {
    final currentOffset = _canvasController.offset;
    final newOffset = Offset(
      currentOffset.dx - panDelta.dx,
      currentOffset.dy - panDelta.dy,
    );
    _canvasController.setOffset(newOffset);
    // Non serve setState qui perché viene chiamato subito dopo da onConfigChanged
  }

  /// Cambia modalità pagine (uniform/individual)
  void _onMultiPageModeChanged(MultiPageMode mode) {
    setState(() {
      _multiPageConfig = _multiPageConfig.copyWith(mode: mode);
    });
  }

  /// Cambia formato pagina uniforme
  void _onMultiPageFormatChanged(ExportPageFormat format) {
    // Ricalcola dimensioni delle pagine con il nuovo formato
    final pageSizeInPoints = format.sizeInPoints;
    final aspectRatio = pageSizeInPoints.width / pageSizeInPoints.height;

    // Mantieni l'altezza della prima pagina e ricalcola la larghezza
    if (_multiPageConfig.individualPageBounds.isNotEmpty) {
      final firstPage = _multiPageConfig.individualPageBounds.first;
      final newWidth = firstPage.height * aspectRatio;
      final newSize = Size(newWidth, firstPage.height);

      // Aggiorna tutte le pagine con il nuovo aspect ratio
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

  /// Aggiunge una nuova pagina
  void _addMultiPagePage() {
    if (!_multiPageConfig.canAddPage) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Limite massimo di ${_multiPageConfig.maxPages} pagine raggiunto',
          ),
          backgroundColor: Colors.orange[700],
        ),
      );
      return;
    }

    // Calcola il centro dello schermo corrente in coordinate canvas
    final screenSize = MediaQuery.of(context).size;
    final viewportCenterScreen = Offset(
      screenSize.width / 2,
      (screenSize.height - 150) / 2, // Escludi la toolbar
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

  /// Rimuove la pagina selezionata
  void _removeMultiPagePage() {
    if (!_multiPageConfig.canRemovePage) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('proCanvas_mustKeepOnePage'),
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

  /// Seleziona una pagina per l'editing
  void _selectMultiPagePage(int index) {
    if (index >= 0 && index < _multiPageConfig.pageCount) {
      setState(() {
        _multiPageConfig = _multiPageConfig.copyWith(selectedPageIndex: index);
      });
    }
  }

  /// Aggiorna i bounds di una pagina
  void _updateMultiPagePageBounds(int index, Rect newBounds) {
    setState(() {
      _multiPageConfig = _multiPageConfig.updatePageBounds(index, newBounds);
    });
  }

  /// Riorganizza le pagine in griglia
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

  /// Conferma le pagine multi-page e torna all'export mode
  void _confirmMultiPageEdit() {
    _exitMultiPageEditMode(saveChanges: true);

    // Aggiorna la config di export con multiPage abilitato
    setState(() {
      _exportConfig = _exportConfig.copyWith(multiPage: true);
    });

    // Mostra direttamente il dialog di export
    _showExportFormatDialog();
  }

  /// Mostra il dialog finale di export
  void _showExportFormatDialog() {
    // Passa la config multi-page se ha pagine personalizzate
    final multiPageConfig =
        _multiPageConfig.pageCount > 0 ? _multiPageConfig : null;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => ExportFormatDialog(
            exportArea: _exportArea,
            initialConfig: _exportConfig,
            canvasId: _canvasId,
            paperType: _paperType,
            multiPageConfig: multiPageConfig,
            onCancel: () => Navigator.pop(context),
            onExport: (config, savedArea) async {
              Navigator.pop(context);

              // Salva area se richiesto
              if (savedArea != null) {
                SavedExportAreasManager.instance.addArea(savedArea);
              }

              // Esegui export
              await _performExport(config);
            },
            onEditMultiPage: (mode, pageFormat, maxPages, existingConfig) {
              Navigator.pop(context);
              // Esci dalla modalità export normale prima di entrare in multi-page edit
              setState(() {
                _isExportMode = false;
              });
              _enterMultiPageEditMode(
                mode: mode,
                pageFormat: pageFormat,
                maxPages: maxPages,
                existingConfig: existingConfig,
              );
            },
          ),
    );
  }

  /// Esegue l'export effettivo
  Future<void> _performExport(ExportConfig config) async {
    final progressController = ExportProgressController();
    _exportProgressController = progressController;

    // Crea istanza del servizio
    final exportService = CanvasExportService();

    // Calcola se serve multi-page
    final (cols, rows, total) = CanvasExportService.calculatePageGrid(
      exportArea: _exportArea,
      quality: config.quality,
      pageFormat: config.pageFormat,
    );
    final needsMultiPage = false;

    // Flag per cancellazione
    bool isCancelled = false;

    // Mostra dialog di progresso (non await!)
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder:
          (dialogContext) => ExportProgressDialog(
            format: config.format,
            totalPages: 1,
            progressStream: progressController.progressStream,
            currentPageStream: progressController.pageStream,
            onCancel: () {
              isCancelled = true;
              progressController.dispose();
              Navigator.pop(dialogContext);
            },
          ),
    );

    // Piccolo delay per assicurarsi che il dialog sia visibile
    await Future.delayed(const Duration(milliseconds: 100));

    if (isCancelled) {
      return;
    }

    try {
      // Directory temporanea per salvare
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      progressController.updateProgress(0.1);

      // Export immagine (PNG o JPEG)
      {
        final bytes = await exportService.exportAsImage(
          layerController: _layerController,
          exportArea: _exportArea,
          config: config,
          onProgress: (progress) {
            progressController.updateProgress(0.1 + progress * 0.8);
          },
        );

        progressController.updateProgress(0.9);

        // Salva su file temporaneo
        final filePath =
            '${tempDir.path}/export_$timestamp.${config.format.name}';
        await File(filePath).writeAsBytes(bytes);

        progressController.updateProgress(0.95);

        // Condividi file
        if (mounted) {
          Navigator.pop(context);
          await Share.shareXFiles([
            XFile(filePath),
          ], subject: 'Looponia Canvas Export');
        }
      }

      // Esci da export mode
      if (mounted) {
        _exitExportMode();
      }
    } catch (e) {
      {}

      if (mounted) {
        Navigator.pop(context);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('proCanvas_exportError'(e.toString())),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      progressController.dispose();
      _exportProgressController = null;
    }
  }
}
