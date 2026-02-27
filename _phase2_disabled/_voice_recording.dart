part of '../fluera_canvas_screen.dart';

/// 📦 Voice Recording — extracted from _FlueraCanvasScreenState
extension on _FlueraCanvasScreenState {
  /// � Mostra popup per scegliere tipo di registrazione audio
  Future<void> _showRecordingChoiceDialog() async {
    HapticFeedback.mediumImpact();

    final choice = await showDialog<String>(
      context: context,
      builder:
          (context) => Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Icona
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.mic_rounded,
                      size: 40,
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Titolo
                  Text(
                    // AppLocalizations removed // (
                      context,
                    ).proCanvas_recordWithStrokesQuestion,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),

                  // Opzione 1: Con tratti
                  ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context, 'with_strokes'),
                    icon: const Icon(Icons.brush_rounded),
                    label: Text(
                      'proCanvas_withStrokes',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      minimumSize: const Size(double.infinity, 0),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Opzione 2: Senza tratti
                  OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context, 'without_strokes'),
                    icon: const Icon(Icons.mic_none_rounded),
                    label: Text(
                      'proCanvas_withoutStrokes',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.primary,
                      side: BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                        width: 2,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      minimumSize: const Size(double.infinity, 0),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Pulsante annulla
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Cancel'),
                  ),
                ],
              ),
            ),
          ),
    );

    if (choice == 'without_strokes') {
      // Implementa registrazione audio senza tratti
      _recordingWithStrokes = false;
      await _startAudioRecording();
    } else if (choice == 'with_strokes') {
      _recordingWithStrokes = true;
      await _startAudioRecording();
    }
  }

  /// 🎤 Avvia registrazione audio senza tratti
  Future<void> _startAudioRecording() async {
    try {
      HapticFeedback.mediumImpact();

      // Inizializza controller se necessario
      _audioRecordingController ??= AudioRecordingController();

      // Verifica permessi
      final hasPermission =
          _audioRecordingController!.service.hasPermission;

      if (!hasPermission) {
        // Mostra dialog esplicativo PRIMA di richiedere il permesso
        final shouldRequest = await _showPermissionExplanationDialog();
        if (shouldRequest != true) {
          {}
          return;
        }

        // Richiedi permesso
        final granted =
            await _audioRecordingController!.service.requestPermission();
        if (!granted) {
          {}
          if (mounted) {
            _showPermissionDeniedDialog();
          }
          return;
        }
      }

      // Avvia registrazione (compresso su canvas condivisi per ridurre banda)
      if (_isSharedCanvas) {
        await _audioRecordingController!.startRecordingCompressed();
      } else {
        await _audioRecordingController!.startRecording();
      }

      // Salva timestamp inizio
      _recordingStartTime = DateTime.now();

      // 🎵 Se registrazione con tratti, inizializza il builder
      if (_recordingWithStrokes) {
        final audioPath = _audioRecordingController!.currentRecordingPath ?? '';
        _syncRecordingBuilder = SynchronizedRecordingBuilder(
          id: 'sync_${DateTime.now().millisecondsSinceEpoch}',
          audioPath: audioPath,
          startTime: _recordingStartTime!,
          canvasId: _canvasId,
          noteTitle: _noteTitle ?? 'Nota',
        );
        {}
      }

      // Aggiorna stato UI
      setState(() {
        _isRecordingAudio = true;
        _recordingDuration = Duration.zero;
      });

      // Avvia timer per aggiornare durata
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted) {
          setState(() {
            _recordingDuration =
                _audioRecordingController!.duration ?? Duration.zero;
          });
        }
      });

      {}
    } catch (e) {
      {}
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '❌ ${'Error: ${e.toString()}'}',
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// ⏹️ Ferma registrazione audio
  Future<void> _stopAudioRecording() async {
    try {
      HapticFeedback.mediumImpact();

      // Ferma timer
      _recordingTimer?.cancel();
      _recordingTimer = null;

      // Ferma registrazione e ottieni path
      final audioPath = await _audioRecordingController?.stopRecording();

      // 🕒 Cattura durata effettiva PRIMA di resettare lo stato
      final recordedDuration = _recordingDuration;

      // Aggiorna stato UI
      setState(() {
        _isRecordingAudio = false;
        _recordingDuration = Duration.zero;
      });

      if (audioPath != null) {
        {}

        // Mostra dialog per salvare o scartare
        if (mounted) {
          await _showSaveRecordingDialog(audioPath, recordedDuration);
        }
      }
    } catch (e) {
      {}
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '❌ ${'Error: ${e.toString()}'}',
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// 💾 Mostra dialog per salvare la registrazione
  Future<void> _showSaveRecordingDialog(
    String audioPath,
    Duration duration,
  ) async {
    final strokeCount = _syncRecordingBuilder?.strokeCount ?? 0;
    final l10nSave = '*';
    final nameController = TextEditingController(
      text: l10nSave.proCanvas_recordingTitle(
        '${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}',
      ),
    );

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green),
                const SizedBox(width: 8),
                Expanded(child: Text(l10nSave.proCanvas_recordingCompleted)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _recordingWithStrokes
                      ? l10nSave.proCanvas_audioSyncedStrokes(strokeCount)
                      : l10nSave.proCanvas_audioOnlyLabel,
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: l10nSave.proCanvas_recordingName,
                    hintText: l10nSave.proCanvas_enterName,
                    prefixIcon: const Icon(Icons.edit),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.grey[100],
                  ),
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: 8),
                Text(
                  l10nSave.proCanvas_saveRecordingQuestion,
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, {'action': 'delete'}),
                child: Text(
                  l10nSave.proCanvas_discard,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
              ElevatedButton(
                onPressed:
                    () => Navigator.pop(context, {
                      'action': 'save',
                      'name': nameController.text.trim(),
                    }),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                child: Text(l10nSave.save),
              ),
            ],
          ),
    );

    if (result != null && result['action'] == 'save') {
      final recordingName =
          result['name'] as String? ?? l10nSave.proCanvas_recordingDefault;
      await _saveRecordingPermanently(
        audioPath,
        recordingName: recordingName,
        duration: duration,
      );
    } else if (result != null && result['action'] == 'delete') {
      await _audioRecordingController?.deleteTemporaryFile('');
      // 🎵 Reset builder se scartata
      _syncRecordingBuilder = null;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10nSave.proCanvas_recordingDiscarded),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    }
  }

  /// � Mostra dialog spiegazione permesso microfono
  Future<bool?> _showPermissionExplanationDialog() async {
    final l10n = '*';
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Icon(
                  Icons.mic,
                  color: Theme.of(context).colorScheme.primary,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Text(l10n.proCanvas_micPermission),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.proCanvas_micPermissionExplanation,
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.proCanvas_recordingsSavedLocally,
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l10n.proCanvas_notNow),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                ),
                child: Text(l10n.proCanvas_allow),
              ),
            ],
          ),
    );
  }

  /// ❌ Mostra dialog quando permesso è negato
  Future<void> _showPermissionDeniedDialog() async {
    final l10n = '*';
    await showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Icon(
                  Icons.warning,
                  color: Theme.of(context).colorScheme.error,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Text(l10n.proCanvas_permissionDenied),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.proCanvas_micPermissionDenied,
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.proCanvas_enableMicInSettings,
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.ok),
              ),
            ],
          ),
    );
  }

  /// 💾 Salva registrazione permanentemente tramite VoiceRecordingService
  Future<void> _saveRecordingPermanently(
    String tempPath, {
    String? recordingName,
    Duration? duration,
  }) async {
    try {
      // Usa la durata passata se disponibile, altrimenti quella corrente
      final effectiveDuration = duration ?? _recordingDuration;
      String? strokesPath;
      SynchronizedRecording? tempSyncRecording;

      // 🎵 Se registrazione con tratti, prepara il JSON
      if (_recordingWithStrokes && _syncRecordingBuilder != null) {
        // Costruisci registrazione (con path temporaneo per ora)
        tempSyncRecording = _syncRecordingBuilder!.build(effectiveDuration);

        // Se nome personalizzato, aggiorna titolo nota
        if (recordingName != null) {
          tempSyncRecording = tempSyncRecording.copyWith(
            noteTitle: recordingName,
            // audioPath è ancora tempPath
          );
        }

        // Salva JSON in una posizione permanente (la cartella recordings)
        final directory = await getApplicationDocumentsDirectory();
        final recordingsDir = Directory('${directory.path}/canvas_recordings');
        if (!await recordingsDir.exists()) {
          await recordingsDir.create(recursive: true);
        }

        final timestamp = DateTime.now().millisecondsSinceEpoch;
        strokesPath = '${recordingsDir.path}/sync_${_canvasId}_$timestamp.json';

        // Salva il JSON (con audioPath temporaneo, verrà aggiornato dopo)
        await File(strokesPath).writeAsString(tempSyncRecording.toJsonString());
      }

      // 💾 Salva tramite VoiceRecordingService
      final savedRec = await VoiceRecordingService.saveVoiceRecording(
        audioPath: tempPath,
        title: recordingName ?? _noteTitle ?? 'Nota',
        parentId: _canvasId,
        recordingType:
            _recordingWithStrokes ? 'with_strokes' : 'without_strokes',
        strokesDataPath: strokesPath,
        duration: effectiveDuration,
      );

      // 🎵 Aggiorna il JSON con il PERMANENT audio path
      if (strokesPath != null && tempSyncRecording != null) {
        final updatedSyncRecording = tempSyncRecording.copyWith(
          audioPath: savedRec.audioPath,
        );
        await File(
          strokesPath,
        ).writeAsString(updatedSyncRecording.toJsonString());

        // ☁️ SHARED CANVAS: Upload audio + strokes to Firebase Storage
        debugPrint(
          '🎤 [REC-DEBUG] strokesPath=$strokesPath, _isSharedCanvas=$_isSharedCanvas, audioPath=${savedRec.audioPath}',
        );
        if (_isSharedCanvas && savedRec.audioPath != null) {
          final syncId = widget.infiniteCanvasId ?? _canvasId;
          debugPrint(
            '🎤 [REC-DEBUG] WITH STROKES: uploading to syncId=$syncId',
          );
          final storageService = CanvasImageStorageService();

          // Upload audio file
          final audioBytes = await File(savedRec.audioPath!).readAsBytes();
          final audioExt = savedRec.audioPath!.split('.').last.toLowerCase();
          // Show upload progress snackbar
          final uploadProgressNotifier = ValueNotifier<double>(0.0);
          final snackBarController = ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: ValueListenableBuilder<double>(
                valueListenable: uploadProgressNotifier,
                builder:
                    (context, progress, _) => Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '⬆️ Caricamento audio... ${(progress * 100).toInt()}%',
                        ),
                        const SizedBox(height: 4),
                        LinearProgressIndicator(value: progress),
                      ],
                    ),
              ),
              backgroundColor: Colors.blue.shade800,
              duration: const Duration(minutes: 5),
            ),
          );

          final audioUrl = await storageService.uploadAudio(
            canvasId: syncId,
            recordingId: updatedSyncRecording.id,
            audioData: audioBytes,
            extension: audioExt.isNotEmpty ? audioExt : 'm4a',
            filePath: savedRec.audioPath,
            onProgress: (p) => uploadProgressNotifier.value = p,
          );
          snackBarController.close();
          debugPrint('🎤 [REC-DEBUG] WITH STROKES: audioUrl=$audioUrl');

          // Upload strokes JSON
          final strokesJsonContent = updatedSyncRecording.toJsonString();
          final strokesUrl = await storageService.uploadStrokesJson(
            canvasId: syncId,
            recordingId: updatedSyncRecording.id,
            jsonContent: strokesJsonContent,
          );
          debugPrint('🎤 [REC-DEBUG] WITH STROKES: strokesUrl=$strokesUrl');

          // Update recording with cloud URLs
          final cloudRecording = updatedSyncRecording.copyWith(
            audioStorageUrl: audioUrl,
            strokesStorageUrl: strokesUrl,
          );

          // Push recording metadata to Firestore for remote discovery
          if (audioUrl != null) {
            debugPrint(
              '🎤 [REC-DEBUG] Pushing metadata to documents/$syncId/recordings/${cloudRecording.id}',
            );
            await _pushRecordingMetadata(syncId, cloudRecording);
          } else {
            debugPrint(
              '🎤 [REC-DEBUG] ⚠️ audioUrl is NULL — NOT pushing metadata!',
            );
          }

          // Update local with cloud URLs
          await File(strokesPath).writeAsString(cloudRecording.toJsonString());

          // Aggiungi alla lista locale per UI immediata
          setState(() {
            _syncedRecordings.add(cloudRecording);
          });
        } else {
          // Non-shared canvas: add locally only
          setState(() {
            _syncedRecordings.add(updatedSyncRecording);
          });
        }
      }

      // ☁️ SHARED CANVAS: Upload audio-only recordings (no strokes)
      debugPrint(
        '🎤 [REC-DEBUG] AUDIO-ONLY check: strokesPath=$strokesPath, _isSharedCanvas=$_isSharedCanvas, audioPath=${savedRec.audioPath}',
      );
      if (strokesPath == null &&
          _isSharedCanvas &&
          savedRec.audioPath != null) {
        final syncId = widget.infiniteCanvasId ?? _canvasId;
        final storageService = CanvasImageStorageService();
        final recId = '${_canvasId}_${DateTime.now().millisecondsSinceEpoch}';
        debugPrint(
          '🎤 [REC-DEBUG] AUDIO-ONLY: uploading to syncId=$syncId, recId=$recId',
        );

        // Upload audio file
        final audioBytes = await File(savedRec.audioPath!).readAsBytes();
        final audioExt = savedRec.audioPath!.split('.').last.toLowerCase();
        // Show upload progress snackbar
        final uploadProgressNotifier = ValueNotifier<double>(0.0);
        final snackBarController = ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: ValueListenableBuilder<double>(
              valueListenable: uploadProgressNotifier,
              builder:
                  (context, progress, _) => Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '⬆️ Caricamento audio... ${(progress * 100).toInt()}%',
                      ),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(value: progress),
                    ],
                  ),
            ),
            backgroundColor: Colors.blue.shade800,
            duration: const Duration(minutes: 5),
          ),
        );

        final audioUrl = await storageService.uploadAudio(
          canvasId: syncId,
          recordingId: recId,
          audioData: audioBytes,
          extension: audioExt.isNotEmpty ? audioExt : 'm4a',
          filePath: savedRec.audioPath,
          onProgress: (p) => uploadProgressNotifier.value = p,
        );
        snackBarController.close();
        debugPrint('🎤 [REC-DEBUG] AUDIO-ONLY: audioUrl=$audioUrl');

        if (audioUrl != null) {
          final audioOnlyRecording = SynchronizedRecording(
            id: recId,
            audioPath: savedRec.audioPath!,
            totalDuration: duration ?? _recordingDuration,
            startTime: DateTime.now(),
            syncedStrokes: [],
            canvasId: syncId,
            noteTitle: recordingName ?? _noteTitle ?? 'Nota',
            recordingType: 'without_strokes',
            audioStorageUrl: audioUrl,
          );
          debugPrint(
            '🎤 [REC-DEBUG] AUDIO-ONLY: pushing metadata to documents/$syncId/recordings/$recId',
          );
          await _pushRecordingMetadata(syncId, audioOnlyRecording);
        } else {
          debugPrint(
            '🎤 [REC-DEBUG] ⚠️ AUDIO-ONLY: audioUrl is NULL — NOT pushing metadata!',
          );
        }
      } else {
        debugPrint(
          '🎤 [REC-DEBUG] AUDIO-ONLY: SKIPPED (strokesPath=${strokesPath != null ? "not null" : "null"}, shared=$_isSharedCanvas, audio=${savedRec.audioPath != null})',
        );
      }

      // Aggiungi path audio alla lista locale
      setState(() {
        if (savedRec.audioPath != null) {
          _savedRecordings.add(savedRec.audioPath!);
        }
      });

      // Pulisci file temporaneo
      try {
        final tempFile = File(tempPath);
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (e) {
        {}
      }

      // Reset builder
      _syncRecordingBuilder = null;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ ${'Recording saved'}',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }

      {}
    } catch (e) {
      {}
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '❌ ${'Save error: ${e.toString()}'}',
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// ☁️ Push recording metadata to Firestore for remote discovery
  Future<void> _pushRecordingMetadata(
    String canvasId,
    SynchronizedRecording recording,
  ) async {
    try {
      debugPrint(
        '🎤 [REC-DEBUG] _pushRecordingMetadata: documents/$canvasId/recordings/${recording.id}',
      );
      debugPrint(
        '🎤 [REC-DEBUG]   audioStorageUrl=${recording.audioStorageUrl}',
      );
      debugPrint(
        '🎤 [REC-DEBUG]   createdBy=${null /* userId via _config */}',
      );
      await FirebaseFirestore.instance
          .collection('documents')
          .doc(canvasId)
          .collection('recordings')
          .doc(recording.id)
          .set({
            'id': recording.id,
            'noteTitle': recording.noteTitle ?? 'Recording',
            'totalDurationMs': recording.totalDuration.inMilliseconds,
            'startTime': recording.startTime.toIso8601String(),
            'recordingType': recording.recordingType,
            'audioStorageUrl': recording.audioStorageUrl,
            'strokesStorageUrl': recording.strokesStorageUrl,
            'hasStrokes': recording.hasStrokes,
            'strokeCount': recording.strokeCount,
            'createdBy': null /* userId via _config */,
            'createdByName':
                null /* auth via _config */?.displayName ??
                'Collaboratore',
            'createdAt': FieldValue.serverTimestamp(),
          });
      debugPrint('🎤 [REC-DEBUG] ✅ Metadata pushed successfully!');
    } catch (e) {
      debugPrint('🎤 [REC-DEBUG] ❌ _pushRecordingMetadata FAILED: $e');
    }
  }

  /// ☁️ Listen for remote recordings in real-time
  void _loadRemoteRecordings() {
    debugPrint(
      '🎤 [REC-DEBUG] _loadRemoteRecordings called, _isSharedCanvas=$_isSharedCanvas',
    );
    if (!_isSharedCanvas) {
      debugPrint('🎤 [REC-DEBUG] SKIPPING _loadRemoteRecordings — not shared');
      return;
    }

    final syncId = widget.infiniteCanvasId ?? _canvasId;
    final currentUserId = null /* userId via _config */;
    debugPrint(
      '🎤 [REC-DEBUG] Listening on documents/$syncId/recordings, currentUserId=$currentUserId',
    );

    _recordingsListener = FirebaseFirestore.instance
        .collection('documents')
        .doc(syncId)
        .collection('recordings')
        .orderBy('createdAt', descending: false)
        .snapshots()
        .listen(
          (snapshot) async {
            debugPrint(
              '🎤 [REC-DEBUG] LISTENER: got snapshot with ${snapshot.docChanges.length} changes',
            );
            for (final change in snapshot.docChanges) {
              final data = change.doc.data();
              if (data == null) continue;
              final recId = data['id'] as String?;
              if (recId == null) continue;
              debugPrint(
                '🎤 [REC-DEBUG] LISTENER: change type=${change.type}, recId=$recId, createdBy=${data['createdBy']}',
              );

              // 🗑️ Handle remote deletion
              if (change.type == DocumentChangeType.removed) {
                if (mounted) {
                  setState(() {
                    _syncedRecordings.removeWhere((r) => r.id == recId);
                    _savedRecordings.removeWhere((r) => r.contains(recId));
                  });
                  // Delete cached file
                  try {
                    final directory = await getApplicationDocumentsDirectory();
                    final cachedFile = File(
                      '${directory.path}/canvas_recordings/remote_$recId.m4a',
                    );
                    if (await cachedFile.exists()) await cachedFile.delete();
                  } catch (_) {}
                }
                continue;
              }

              if (change.type != DocumentChangeType.added) {
                debugPrint(
                  '🎤 [REC-DEBUG] LISTENER: skipping non-added change type: ${change.type}',
                );
                continue;
              }

              // Skip already loaded
              if (_syncedRecordings.any((r) => r.id == recId) ||
                  _savedRecordings.any((r) => r.contains(recId))) {
                debugPrint(
                  '🎤 [REC-DEBUG] LISTENER: skipping already loaded recId=$recId',
                );
                continue;
              }

              // Skip own recordings
              if (data['createdBy'] == currentUserId) {
                debugPrint(
                  '🎤 [REC-DEBUG] LISTENER: skipping own recording recId=$recId',
                );
                continue;
              }

              final audioUrl = data['audioStorageUrl'] as String?;
              final strokesUrl = data['strokesStorageUrl'] as String?;
              final creatorName =
                  data['createdByName'] as String? ?? 'Collaboratore';
              if (audioUrl == null) {
                debugPrint(
                  '🎤 [REC-DEBUG] LISTENER: skipping recId=$recId — audioUrl is null',
                );
                continue;
              }
              debugPrint(
                '🎤 [REC-DEBUG] LISTENER: processing recId=$recId, audioUrl=${audioUrl.substring(0, 50)}...',
              );

              // 🔒 Skip if already downloading
              if (_downloadingRecordingIds.contains(recId)) continue;
              _downloadingRecordingIds.add(recId);

              // Download in background
              try {
                final directory = await getApplicationDocumentsDirectory();
                final cacheDir = Directory(
                  '${directory.path}/canvas_recordings',
                );
                if (!await cacheDir.exists()) {
                  await cacheDir.create(recursive: true);
                }

                final localAudioPath = '${cacheDir.path}/remote_$recId.m4a';

                // 💾 Check if already cached locally (skip re-download)
                final cachedFile = File(localAudioPath);
                if (await cachedFile.exists() &&
                    (await cachedFile.length()) > 0) {
                  // File already cached — register without downloading
                  SynchronizedRecording recording;
                  if (strokesUrl != null) {
                    try {
                      final strokesResponse = await NetworkAssetBundle(
                        Uri.parse(strokesUrl),
                      ).load(strokesUrl);
                      final strokesJson = String.fromCharCodes(
                        strokesResponse.buffer.asUint8List(),
                      );
                      recording = SynchronizedRecording.fromJsonString(
                        strokesJson,
                      );
                      recording = recording.copyWith(
                        audioPath: localAudioPath,
                        audioStorageUrl: audioUrl,
                        strokesStorageUrl: strokesUrl,
                      );
                    } catch (_) {
                      recording = _buildFallbackRecording(
                        recId,
                        localAudioPath,
                        data,
                        syncId,
                        audioUrl,
                        strokesUrl,
                      );
                    }
                  } else {
                    recording = _buildFallbackRecording(
                      recId,
                      localAudioPath,
                      data,
                      syncId,
                      audioUrl,
                      strokesUrl,
                    );
                  }
                  if (mounted) {
                    setState(() {
                      _syncedRecordings.add(recording);
                      _savedRecordings.add(localAudioPath);
                    });
                  }
                  _downloadingRecordingIds.remove(recId);
                  continue;
                }

                // 📥 Download audio with progress
                final downloadProgressNotifier = ValueNotifier<double>(0.0);
                ScaffoldMessengerState? messengerState;
                ScaffoldFeatureController? downloadSnackController;
                if (mounted) {
                  messengerState = ScaffoldMessenger.of(context);
                  downloadSnackController = messengerState.showSnackBar(
                    SnackBar(
                      content: ValueListenableBuilder<double>(
                        valueListenable: downloadProgressNotifier,
                        builder:
                            (context, progress, _) => Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '⬇️ Download da $creatorName... ${(progress * 100).toInt()}%',
                                ),
                                const SizedBox(height: 4),
                                LinearProgressIndicator(value: progress),
                              ],
                            ),
                      ),
                      backgroundColor: Colors.indigo.shade700,
                      duration: const Duration(minutes: 5),
                    ),
                  );
                }

                // Chunked download via HttpClient
                final httpClient = HttpClient();
                final request = await httpClient.getUrl(Uri.parse(audioUrl));
                final response = await request.close();
                final contentLength = response.contentLength;
                final audioSink = File(localAudioPath).openWrite();
                int bytesReceived = 0;
                await for (final chunk in response) {
                  audioSink.add(chunk);
                  bytesReceived += chunk.length;
                  if (contentLength > 0) {
                    downloadProgressNotifier.value =
                        bytesReceived / contentLength;
                  }
                }
                await audioSink.close();
                httpClient.close();
                downloadSnackController?.close();
                debugPrint(
                  '🎤 [REC-DEBUG] LISTENER: audio downloaded to $localAudioPath (${bytesReceived} bytes)',
                );

                // Download and parse strokes JSON if available
                SynchronizedRecording recording;
                if (strokesUrl != null) {
                  debugPrint(
                    '🎤 [REC-DEBUG] LISTENER: downloading strokes from $strokesUrl',
                  );
                  final strokesResponse = await NetworkAssetBundle(
                    Uri.parse(strokesUrl),
                  ).load(strokesUrl);
                  final strokesJson = String.fromCharCodes(
                    strokesResponse.buffer.asUint8List(),
                  );
                  recording = SynchronizedRecording.fromJsonString(strokesJson);
                  recording = recording.copyWith(
                    audioPath: localAudioPath,
                    audioStorageUrl: audioUrl,
                    strokesStorageUrl: strokesUrl,
                  );
                  debugPrint(
                    '🎤 [REC-DEBUG] LISTENER: strokes parsed, recording built',
                  );
                } else {
                  debugPrint(
                    '🎤 [REC-DEBUG] LISTENER: no strokes, building audio-only recording',
                  );
                  recording = SynchronizedRecording(
                    id: recId,
                    audioPath: localAudioPath,
                    totalDuration: Duration(
                      milliseconds: data['totalDurationMs'] as int? ?? 0,
                    ),
                    startTime:
                        DateTime.tryParse(data['startTime'] as String? ?? '') ??
                        DateTime.now(),
                    syncedStrokes: [],
                    canvasId: syncId,
                    noteTitle: data['noteTitle'] as String?,
                    recordingType: data['recordingType'] as String?,
                    audioStorageUrl: audioUrl,
                    strokesStorageUrl: strokesUrl,
                  );
                }

                if (mounted) {
                  setState(() {
                    _syncedRecordings.add(recording);
                    _savedRecordings.add(localAudioPath);
                  });

                  // 📢 Notify user of new remote recording
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '🎤 $creatorName ha aggiunto "${recording.noteTitle ?? 'Recording'}"',
                      ),
                      backgroundColor: Colors.blue.shade700,
                      duration: const Duration(seconds: 3),
                    ),
                  );
                }
              } catch (e) {
                debugPrint(
                  '🎤 [REC-DEBUG] LISTENER: ❌ download FAILED for recId=$recId: $e',
                );
              } finally {
                _downloadingRecordingIds.remove(recId);
              }
            }
          },
          onError: (e) {
            debugPrint('🎤 [REC-DEBUG] LISTENER: ❌ Stream error: $e');
          },
        );
  }

  /// 🔧 Helper: Build a fallback SynchronizedRecording from Firestore metadata
  SynchronizedRecording _buildFallbackRecording(
    String recId,
    String localAudioPath,
    Map<String, dynamic> data,
    String syncId,
    String? audioUrl,
    String? strokesUrl,
  ) {
    return SynchronizedRecording(
      id: recId,
      audioPath: localAudioPath,
      totalDuration: Duration(
        milliseconds: data['totalDurationMs'] as int? ?? 0,
      ),
      startTime:
          DateTime.tryParse(data['startTime'] as String? ?? '') ??
          DateTime.now(),
      syncedStrokes: [],
      canvasId: syncId,
      noteTitle: data['noteTitle'] as String?,
      recordingType: data['recordingType'] as String?,
      audioStorageUrl: audioUrl,
      strokesStorageUrl: strokesUrl,
    );
  }

  /// 🎧 Mostra dialog con registrazioni salvate
  Future<void> _showSavedRecordingsDialog() async {
    // 🎯 Filtra registrazioni per questo canvas
    final syncId = widget.infiniteCanvasId ?? _canvasId;
    debugPrint(
      '🎤 [REC-DEBUG] _showSavedRecordingsDialog: _canvasId=$_canvasId, syncId=$syncId',
    );
    debugPrint(
      '🎤 [REC-DEBUG]   _syncedRecordings count=${_syncedRecordings.length}',
    );
    debugPrint(
      '🎤 [REC-DEBUG]   _savedRecordings count=${_savedRecordings.length}',
    );
    for (final r in _syncedRecordings) {
      debugPrint(
        '🎤 [REC-DEBUG]   syncedRec id=${r.id}, canvasId=${r.canvasId}',
      );
    }
    final filteredSyncRecordings =
        _syncedRecordings
            .where((r) => r.canvasId == _canvasId || r.canvasId == syncId)
            .toList();
    debugPrint(
      '🎤 [REC-DEBUG]   filteredSyncRecordings count=${filteredSyncRecordings.length}',
    );

    // Filtra anche le registrazioni audio: mostra solo quelle di questo canvas
    // (basandosi sulle sync recordings che hanno il canvasId)
    final syncedAudioPaths =
        filteredSyncRecordings.map((r) => r.audioPath).toSet();
    final filteredRecordings =
        _savedRecordings.where((path) {
          // Includi se ha una sync recording per questo canvas
          // O se il path contiene l'ID del canvas (per registrazioni solo audio)
          return syncedAudioPaths.contains(path) ||
              path.contains(_canvasId) ||
              // Includi registrazioni orfane solo se non hanno sync recording altrove
              !_syncedRecordings.any((r) => r.audioPath == path);
        }).toList();

    if (filteredRecordings.isEmpty && filteredSyncRecordings.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('📭 Nessuna registrazione per questa nota'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    await showDialog(
      context: context,
      builder:
          (context) => RecordingsListDialog(
            recordings: filteredRecordings,
            syncedRecordings: filteredSyncRecordings,
            onPlay: (path) {
              // Chiudi dialog e avvia player
              Navigator.pop(context);
              // 🛑 Ferma riproduzione sincronizzata se attiva
              _stopSyncedPlayback();
              setState(() {
                _playingAudioPath = path;
              });
            },
            onPlaySynced: (recording) {
              // Chiudi dialog e avvia player sincronizzato
              Navigator.pop(context);
              _startSyncedPlayback(recording);
            },
            onDelete: (path) async {
              try {
                final file = File(path);
                if (await file.exists()) {
                  await file.delete();
                }
                setState(() {
                  _savedRecordings.remove(path);
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('🗑️ Registrazione eliminata'),
                    backgroundColor: Colors.orange,
                  ),
                );
              } catch (e) {
                {}
              }
            },
          ),
    );
  }

  // ============================================================================
  // 🎵 RIPRODUZIONE SINCRONIZZATA
  // ============================================================================

  /// 🎵 Ferma riproduzione audio semplice
  void _stopAudioPlayback() {
    if (_playingAudioPath != null) {
      setState(() {
        _playingAudioPath = null;
      });
    }
  }

  /// 🎵 Avvia riproduzione sincronizzata di una registrazione
  Future<void> _startSyncedPlayback(SynchronizedRecording recording) async {
    // 🛑 Ferma audio semplice se attivo
    _stopAudioPlayback();

    try {
      // Inizializza controller se necessario
      _playbackController ??= SynchronizedPlaybackController();

      // Carica la registrazione
      await _playbackController!.loadRecording(recording);

      // Aggiorna stato UI
      setState(() {
        _isPlayingSyncedRecording = true;
      });

      // Avvia riproduzione
      await _playbackController!.play();

      {}
    } catch (e) {
      {}
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Errore riproduzione: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 🎵 Ferma riproduzione sincronizzata
  void _stopSyncedPlayback() {
    _playbackController?.stop();
    _playbackController?.unload();
    setState(() {
      _isPlayingSyncedRecording = false;
    });
    {}
  }
}
