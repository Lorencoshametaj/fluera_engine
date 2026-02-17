part of '../nebula_canvas_screen.dart';

/// 📦 Navigation & PDF — extracted from _NebulaCanvasScreenState
extension on _NebulaCanvasScreenState {
  /// 👁️ Jump to the followed user's viewport position
  void _jumpToFollowedUser(String userId) {
    if (_realtimeSyncManager == null) return;
    final cursorMap = _realtimeSyncManager!.remoteCursors.value;
    final data = cursorMap[userId];
    if (data == null) return;

    final vx = (data['vx'] as num?)?.toDouble();
    final vy = (data['vy'] as num?)?.toDouble();
    final vs = (data['vs'] as num?)?.toDouble();

    if (vx != null && vy != null) {
      _canvasController.setOffset(Offset(vx, vy));
      if (vs != null && vs > 0) {
        _canvasController.setScale(vs);
      }
    }
  }

  /// 🧭 Naviga al punto corrente del disegno durante la riproduzione
  void _navigateToCurrentDrawing() {
    if (_playbackController == null) return;

    final drawingPos = _playbackController!.currentDrawingPosition;
    if (drawingPos == null) return;

    // Ottieni la dimensione della viewport
    final viewportSize = MediaQuery.of(context).size;

    // Calcola l'offset necessario per centrare il punto di disegno
    // Formula: screenPos = canvasPos * scale + offset
    // Vogliamo: centerScreen = drawingPos * scale + newOffset
    // Quindi: newOffset = centerScreen - drawingPos * scale
    final targetOffset = Offset(
      viewportSize.width / 2 - drawingPos.dx * _canvasController.scale,
      viewportSize.height / 2 - drawingPos.dy * _canvasController.scale,
    );

    // Muovi il canvas al punto target
    _canvasController.setOffset(targetOffset);

    {}
  }

  /// 🎵 Mostra dialog registrazioni sincronizzate
  Future<void> _showSyncedRecordingsDialog() async {
    final l10n = '*';
    if (_syncedRecordings.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('📭 ${l10n.proCanvas_noSyncedRecordings}'),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    await showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                const Icon(Icons.sync, color: Colors.green, size: 28),
                const SizedBox(width: 12),
                Text(l10n.proCanvas_syncedRecordings),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _syncedRecordings.length,
                itemBuilder: (context, index) {
                  final recording = _syncedRecordings[index];
                  return SyncedRecordingListItem(
                    title:
                        recording.noteTitle ??
                        l10n.proCanvas_recording(index + 1),
                    duration: recording.totalDuration,
                    strokeCount: recording.strokeCount,
                    onPlay: () {
                      Navigator.pop(context);
                      _startSyncedPlayback(recording);
                    },
                    onDelete: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder:
                            (context) => AlertDialog(
                              title: Text(l10n.proCanvas_confirmDeletion),
                              content: Text(
                                l10n.proCanvas_deleteSyncedRecordingQuestion,
                              ),
                              actions: [
                                TextButton(
                                  onPressed:
                                      () => Navigator.pop(context, false),
                                  child: Text(l10n.cancel),
                                ),
                                ElevatedButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                  ),
                                  child: Text(l10n.delete),
                                ),
                              ],
                            ),
                      );

                      if (confirm == true) {
                        setState(() {
                          _syncedRecordings.removeAt(index);
                        });
                        // Elimina anche il file JSON locale
                        // TODO: implementare eliminazione file
                        if (_syncedRecordings.isEmpty) {
                          Navigator.pop(context);
                        }
                      }
                    },
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.close),
              ),
            ],
          ),
    );
  }

  /// 📄 Mostra dialog per creare o aprire PDF
  Future<void> _showPdfOptionsDialog() async {
    final l10n = '*';
    await showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.picture_as_pdf_rounded, color: Colors.red),
                SizedBox(width: 12),
                Text('📄 PDF'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.proCanvas_chooseAction,
                  style: const TextStyle(fontSize: 14, color: Colors.black54),
                ),
                const SizedBox(height: 20),
                // Pulsante: Crea nuovo PDF
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _createNewPdf();
                  },
                  icon: const Icon(Icons.add_rounded),
                  label: Text(l10n.proCanvas_createNewPdf),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 14,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Pulsante: Apri PDF esistente
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _openExistingPdf();
                  },
                  icon: const Icon(Icons.folder_open_rounded),
                  label: Text(l10n.proCanvas_openExistingPdf),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 14,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.cancel),
              ),
            ],
          ),
    );
  }

  /// 🆕 Crea un nuovo PDF vuoto
  Future<void> _createNewPdf() async {
    // TODO: Implementare creazione PDF vuoto
    // Per ora mostra un messaggio temporaneo
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('PDF creation in development'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 📂 Apri PDF esistente da file system
  Future<void> _openExistingPdf() async {
    try {
      // Usa file_picker per selezionare PDF
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final filePath = result.files.first.path;
        if (filePath != null) {
          // Apri PDF in una nuova schermata
          if (!mounted) return;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PDFCanvasScreen(pdfFilePath: filePath),
            ),
          );
        }
      }
    } catch (e) {
      {}
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '❌ ${'Error: ${e.toString()}'}',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// 🚀 Lancia il sistema di split view avanzato
  Future<void> _launchAdvancedSplitView() async {
    try {
      // Mostra dialog di selezione layout rapidi
      await AdvancedSplitViewLauncher.showQuickLayoutDialog(context);

      // Ricarica i dati al ritorno
      await _loadCanvasData();
    } catch (e) {
      {}
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '❌ ${'Error: ${e.toString()}'}',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
