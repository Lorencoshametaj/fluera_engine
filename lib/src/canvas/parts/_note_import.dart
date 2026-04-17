part of '../fluera_canvas_screen.dart';

/// 📥 Note Import — import handwritten notes from other apps and convert
/// them to native [ProStroke] objects for full cognitive feature support.
extension FlueraCanvasNoteImport on _FlueraCanvasScreenState {
  /// Pick a file (PDF, SVG, or image) and import its handwritten content
  /// as [ProStroke] objects on the active layer.
  ///
  /// The imported strokes enter the normal pipeline: clustering → OCR →
  /// cognitive features (Ghost Map, Exam, Chat, SRS Blur, etc.).
  Future<void> pickAndImportNotes() async {
    // 🔒 VIEWER GUARD
    if (_checkViewerGuard()) return;

    try {
      // 1. Pick file
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'svg', 'png', 'jpg', 'jpeg', 'webp'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) return;

      final fileName = file.name;
      final sourceType = NoteImportController.detectType(fileName);

      // 2. Show progress dialog
      if (!mounted) return;

      late StateSetter dialogSetState;
      var progress = const ImportProgress(
        currentPage: 0,
        totalPages: 1,
        phase: 'Starting import...',
      );

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (ctx, setState) {
              dialogSetState = setState;
              return AlertDialog(
                title: const Text('Importing Notes'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LinearProgressIndicator(value: progress.fraction),
                    const SizedBox(height: 12),
                    Text(
                      progress.phase,
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                    if (progress.totalPages > 1)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '${progress.currentPage} / ${progress.totalPages}',
                          style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                            color: Theme.of(ctx).colorScheme.outline,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          );
        },
      );

      // 3. Run import
      final controller = NoteImportController(
        pdfProvider: widget.config.pdfProvider,
      );

      NoteImportResult importResult;

      switch (sourceType) {
        case ImportSourceType.pdfInk:
        case ImportSourceType.rasterized:
          importResult = await controller.importFromPdf(
            Uint8List.fromList(bytes),
            insertPosition: _viewportCenter(),
            onProgress: (p) {
              if (mounted) {
                dialogSetState(() => progress = p);
              }
            },
          );
        case ImportSourceType.svgPath:
          final svgContent = String.fromCharCodes(bytes);
          importResult = controller.importFromSvg(
            svgContent,
            insertPosition: _viewportCenter(),
          );
      }

      // 4. Close dialog
      if (mounted) Navigator.of(context).pop();

      // 5. Add strokes to the active layer
      if (importResult.strokes.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No handwritten content found in the file.'),
            ),
          );
        }
        return;
      }

      // Record stroke IDs for undo
      final strokeIds = importResult.strokes.map((s) => s.id).toList();

      // Batch-add all imported strokes
      _layerController.addStrokesBatch(importResult.strokes);
      DrawingPainter.triggerRepaint();

      // 6. Register undo command so the entire import can be undone at once
      _commandHistory.execute(_ImportNotesCommand(
        layerController: _layerController,
        strokeIds: strokeIds,
        label: 'Import ${strokeIds.length} strokes',
        alreadyExecuted: true, // strokes are already added above
      ));

      // 7. Update cluster cache for cognitive features
      if (_clusterDetector != null) {
        final activeLayer = _layerController.layers.firstWhere(
          (l) => l.id == _layerController.activeLayerId,
          orElse: () => _layerController.layers.first,
        );
        for (final stroke in importResult.strokes) {
          _clusterCache = _clusterDetector!.addStroke(
            _clusterCache,
            stroke,
            activeLayer.strokes,
          );
        }
        _lassoTool.reflowController?.updateClusters(_clusterCache);
      }

      // 8. Auto-save
      _autoSaveCanvas();

      // 9. Notify user
      if (mounted) {
        final count = importResult.strokes.length;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Imported $count strokes successfully.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import failed: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  /// Calculate the center of the current viewport in canvas coordinates.
  Offset _viewportCenter() {
    final size = MediaQuery.sizeOf(context);
    final canvasCenter = _canvasController.screenToCanvas(
      Offset(size.width / 2, size.height / 2),
    );
    return canvasCenter;
  }
}

/// Command that allows undoing an entire note import in one step.
///
/// On undo: removes all imported strokes by ID.
/// On redo: re-adds them (strokes are retained in memory).
class _ImportNotesCommand extends Command {
  final LayerController layerController;
  final List<String> strokeIds;
  List<ProStroke> _removedStrokes = const [];
  bool _firstExecution;

  _ImportNotesCommand({
    required this.layerController,
    required this.strokeIds,
    required String label,
    bool alreadyExecuted = false,
  }) : _firstExecution = alreadyExecuted,
       super(label: label);

  @override
  void execute() {
    // On first call with alreadyExecuted=true, strokes are already added
    // by the import pipeline — skip. On subsequent calls (redo), re-add them.
    if (_firstExecution) {
      _firstExecution = false;
      return;
    }
    if (_removedStrokes.isNotEmpty) {
      layerController.addStrokesBatch(_removedStrokes);
      DrawingPainter.triggerRepaint();
    }
  }

  @override
  void undo() {
    // Remove all imported strokes and save them for redo
    final removed = <ProStroke>[];
    for (final id in strokeIds) {
      // Find the stroke in the layers before removing
      for (final layer in layerController.layers) {
        final stroke = layer.strokes.where((s) => s.id == id).firstOrNull;
        if (stroke != null) {
          removed.add(stroke);
          break;
        }
      }
      layerController.removeStroke(id);
    }
    _removedStrokes = removed;
    DrawingPainter.invalidateAllTiles();
    DrawingPainter.triggerRepaint();
  }
}
