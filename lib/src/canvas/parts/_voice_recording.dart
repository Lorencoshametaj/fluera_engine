part of '../nebula_canvas_screen.dart';

/// 📦 Voice Recording — generic SDK implementation.
///
/// Delegates all recording, playback, and cloud sync operations to
/// [NebulaVoiceRecordingProvider] provided via [NebulaCanvasConfig].
/// Falls back to [DefaultVoiceRecordingProvider] if no custom provider
/// is configured, enabling zero-config recording.
extension VoiceRecordingExtension on _NebulaCanvasScreenState {
  /// Lazy default provider — created once per canvas state, cleaned up on dispose.
  static final Map<int, DefaultVoiceRecordingProvider> _defaultProviders = {};

  /// Returns the configured provider or a built-in default.
  NebulaVoiceRecordingProvider get _voiceRecordingProvider {
    final custom = _config.voiceRecording;
    if (custom != null) return custom;
    return _defaultProviders.putIfAbsent(
      hashCode,
      () => DefaultVoiceRecordingProvider(),
    );
  }

  /// Dispose the default provider if one was created for this canvas.
  /// Call this from the canvas state's dispose method.
  void _disposeDefaultVoiceRecordingProvider() {
    final provider = _defaultProviders.remove(hashCode);
    provider?.dispose();
  }

  /// 🎤 Show dialog for choosing recording type.
  ///
  /// Uses configured provider or built-in default.
  Future<void> _showRecordingChoiceDialog() async {
    final provider = _voiceRecordingProvider;

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
                  // Icon
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

                  // Title
                  const Text(
                    'Record with strokes?',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),

                  // Option 1: With strokes
                  ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context, 'with_strokes'),
                    icon: const Icon(Icons.brush_rounded),
                    label: const Text('With Strokes'),
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

                  // Option 2: Without strokes
                  OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context, 'without_strokes'),
                    icon: const Icon(Icons.mic_none_rounded),
                    label: const Text('Without Strokes'),
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

                  // Cancel button
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ),
          ),
    );

    if (choice == 'without_strokes' || choice == 'with_strokes') {
      _recordingWithStrokes = (choice == 'with_strokes');
      await _startAudioRecording();
    }
  }

  /// 🎤 Start audio recording via the provider.
  Future<void> _startAudioRecording() async {
    // 🔧 FIX #2: Guard against double-tap
    if (_isRecordingAudio) return;

    final provider = _voiceRecordingProvider;

    try {
      HapticFeedback.mediumImpact();

      await provider.startRecording();

      _recordingStartTime = DateTime.now();

      // 🎵 Create sync builder when recording with strokes
      if (_recordingWithStrokes) {
        _syncRecordingBuilder = SynchronizedRecordingBuilder(
          id: const Uuid().v4(),
          audioPath: '', // Will be updated when recording stops
          startTime: _recordingStartTime!,
          canvasId: widget.canvasId,
        );
        _syncRecordingBuilder!.setRecordingType('note');
        debugPrint(
          '[VoiceRecording] SyncRecordingBuilder created for stroke sync',
        );
      }

      setState(() {
        _isRecordingAudio = true;
        _recordingDuration = Duration.zero;
      });

      // Listen to duration updates
      _recordingDurationSubscription?.cancel();
      _recordingDurationSubscription = provider.recordingDuration.listen((
        duration,
      ) {
        if (mounted) {
          setState(() {
            _recordingDuration = duration;
          });
        }
      });
    } catch (e) {
      debugPrint('[VoiceRecording] Start failed: $e');
      _syncRecordingBuilder = null;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error starting recording: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// ⏹️ Stop audio recording.
  Future<void> _stopAudioRecording() async {
    final provider = _voiceRecordingProvider;

    try {
      HapticFeedback.mediumImpact();

      _recordingDurationSubscription?.cancel();
      _recordingDurationSubscription = null;

      final audioPath = await provider.stopRecording();

      final recordedDuration = _recordingDuration;

      // 🎵 Finalize synchronized recording builder
      SynchronizedRecording? syncRecording;
      if (_syncRecordingBuilder != null && audioPath != null) {
        // Build the synchronized recording, then override with correct audio path
        // (audioPath was '' at construction time since we didn't know it yet)
        syncRecording = _syncRecordingBuilder!.build(recordedDuration);
        // Override with correct audio path
        syncRecording = SynchronizedRecording(
          id: syncRecording.id,
          audioPath: audioPath,
          totalDuration: recordedDuration,
          startTime: syncRecording.startTime,
          syncedStrokes: syncRecording.syncedStrokes,
          canvasId: syncRecording.canvasId,
          noteTitle: syncRecording.noteTitle,
          recordingType: syncRecording.recordingType,
        );

        debugPrint(
          '[VoiceRecording] SyncRecording finalized: '
          '${syncRecording.syncedStrokes.length} strokes captured',
        );
      }
      _syncRecordingBuilder = null;

      // 🔧 FIX #3: Capture recording type BEFORE resetting the flag
      final wasRecordingWithStrokes = _recordingWithStrokes;
      // 🔧 Enterprise: Capture start time BEFORE reset (used for audio-only persist)
      final capturedStartTime = _recordingStartTime ?? DateTime.now();

      setState(() {
        _isRecordingAudio = false;
        _recordingDuration = Duration.zero;
        _recordingWithStrokes = false; // Reset for next session
        _recordingStartTime = null; // 🔧 FIX #6: Prevent stale value leaking
      });

      if (audioPath != null && mounted) {
        // Show save dialog (pass captured type so label is correct)
        final saveResult = await _showSaveRecordingDialog(
          audioPath,
          recordedDuration,
          withStrokes: wasRecordingWithStrokes,
        );
        if (saveResult != null && saveResult['action'] == 'save') {
          final recordingName = saveResult['name'] as String?;

          // Attach recording name to synced recording
          if (syncRecording != null &&
              recordingName != null &&
              recordingName.isNotEmpty) {
            syncRecording = syncRecording.copyWith(noteTitle: recordingName);
          }

          setState(() {
            _savedRecordings.add(audioPath);
            // Store synced recording for playback
            if (syncRecording != null) {
              _syncedRecordings.add(syncRecording);
            }
          });

          // 💾 Persist to SQLite (both audio-only and with-strokes)
          if (RecordingStorageService.instance.isInitialized) {
            // For audio-only, create a minimal SynchronizedRecording
            final persistable =
                syncRecording != null
                    ? syncRecording.copyWith(canvasId: _canvasId)
                    : SynchronizedRecording.empty(
                      id: const Uuid().v4(),
                      audioPath: audioPath,
                      startTime: capturedStartTime,
                      canvasId: _canvasId,
                      noteTitle: recordingName,
                      recordingType: 'audio_only',
                    );
            try {
              await RecordingStorageService.instance.saveRecording(persistable);
            } catch (e) {
              debugPrint('[VoiceRecording] Failed to persist recording: $e');
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '⚠️ Recording saved locally but not persisted: $e',
                    ),
                    backgroundColor: Colors.orange,
                    duration: const Duration(seconds: 4),
                  ),
                );
              }
            }
          }

          // 🔧 Enterprise: Cap recordings at 50 — evict oldest from memory + DB + disk
          while (_savedRecordings.length > 50) {
            final evictedPath = _savedRecordings.removeAt(0);
            _syncedRecordings.removeWhere((r) => r.audioPath == evictedPath);
            // Cascade: delete from SQLite
            if (RecordingStorageService.instance.isInitialized) {
              RecordingStorageService.instance
                  .deleteByAudioPath(evictedPath)
                  .catchError((_) => 0);
            }
            // Cascade: delete audio file from disk
            try {
              final file = File(evictedPath);
              if (await file.exists()) await file.delete();
            } catch (_) {}
          }
          if (mounted) {
            final strokeInfo =
                syncRecording != null
                    ? ' (${syncRecording.syncedStrokes.length} strokes synced)'
                    : '';
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('✅ Recording saved$strokeInfo'),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        } else {
          // User discarded — delete the audio file from disk
          try {
            final file = File(audioPath);
            if (await file.exists()) {
              await file.delete();
              debugPrint(
                '[VoiceRecording] Discarded recording file deleted: $audioPath',
              );
            }
          } catch (e) {
            debugPrint(
              '[VoiceRecording] Failed to delete discarded recording: $e',
            );
          }
        }
      }
    } catch (e) {
      debugPrint('[VoiceRecording] Stop failed: $e');
      _syncRecordingBuilder = null;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error stopping recording: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// 💾 Show dialog to save or discard the recording.
  /// Returns the full result map with 'action' and 'name' keys, or null.
  Future<Map<String, dynamic>?> _showSaveRecordingDialog(
    String audioPath,
    Duration duration, {
    bool withStrokes = false,
  }) async {
    final nameController = TextEditingController(
      text:
          'Recording ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}',
    );

    // 🔧 FIX #6: Ensure controller is disposed after dialog
    try {
      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        barrierDismissible: false,
        builder:
            (context) => PopScope(
              // 🔧 FIX #5: Prevent back button from silently dismissing
              canPop: false,
              onPopInvokedWithResult: (didPop, _) {
                if (!didPop) {
                  // Back button pressed — treat as save with default name
                  Navigator.pop(context, {
                    'action': 'save',
                    'name': nameController.text.trim(),
                  });
                }
              },
              child: AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                title: const Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green),
                    SizedBox(width: 8),
                    Expanded(child: Text('Recording Complete')),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 🔧 FIX #3: Use parameter instead of reset flag
                    Text(
                      withStrokes ? 'Audio synced with strokes' : 'Audio only',
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: 'Recording name',
                        hintText: 'Enter name',
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
                      'Duration: ${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed:
                        () => Navigator.pop(context, {'action': 'discard'}),
                    child: const Text(
                      'Discard',
                      style: TextStyle(color: Colors.red),
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
                    child: const Text('Save'),
                  ),
                ],
              ),
            ),
      );

      return result;
    } finally {
      nameController.dispose();
    }
  }

  /// 🎧 Show dialog listing saved recordings.
  Future<void> _showSavedRecordingsDialog() async {
    if (_savedRecordings.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No recordings saved for this canvas'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final provider = _voiceRecordingProvider;

    await showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Row(
              children: [
                Icon(Icons.headphones, color: Colors.blue),
                SizedBox(width: 8),
                Text('Saved Recordings'),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _savedRecordings.length,
                itemBuilder: (context, index) {
                  final path = _savedRecordings[index];
                  // 🔧 FIX #1: Show noteTitle if available
                  final synced = _syncedRecordings
                      .cast<SynchronizedRecording?>()
                      .firstWhere(
                        (r) => r?.audioPath == path,
                        orElse: () => null,
                      );
                  final displayName =
                      (synced?.noteTitle != null &&
                              synced!.noteTitle!.isNotEmpty)
                          ? synced.noteTitle!
                          : path.split('/').last;
                  return ListTile(
                    leading: const Icon(Icons.audiotrack),
                    title: Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.play_arrow),
                          onPressed: () {
                            Navigator.pop(context);
                            provider.playRecording(path);
                            _listenForPlaybackCompletion();
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () async {
                            // 🔧 FIX #2: Confirm before deleting
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder:
                                  (ctx) => AlertDialog(
                                    title: const Text('Delete Recording?'),
                                    content: const Text(
                                      'This action cannot be undone.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed:
                                            () => Navigator.pop(ctx, false),
                                        child: const Text('Cancel'),
                                      ),
                                      TextButton(
                                        onPressed:
                                            () => Navigator.pop(ctx, true),
                                        child: const Text(
                                          'Delete',
                                          style: TextStyle(color: Colors.red),
                                        ),
                                      ),
                                    ],
                                  ),
                            );
                            if (confirmed != true) return;

                            final deletedPath = _savedRecordings[index];

                            // Remove from all in-memory lists
                            setState(() {
                              _savedRecordings.removeAt(index);
                            });
                            _syncedRecordings.removeWhere(
                              (r) => r.audioPath == deletedPath,
                            );

                            // 🔧 FIX #3: Direct delete by audioPath (O(1))
                            if (RecordingStorageService
                                .instance
                                .isInitialized) {
                              await RecordingStorageService.instance
                                  .deleteByAudioPath(deletedPath);
                            }

                            // Delete audio file from disk
                            try {
                              final file = File(deletedPath);
                              if (await file.exists()) await file.delete();
                            } catch (_) {}

                            Navigator.pop(context);
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              const SnackBar(
                                content: Text('Recording deleted'),
                                backgroundColor: Colors.orange,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
    );
  }

  /// 🎵 Stop synced playback.
  void _stopSyncedPlayback() {
    final provider = _voiceRecordingProvider;
    provider.stopPlayback();
    _playbackCompletedSubs[hashCode]?.cancel();
    _playbackCompletedSubs.remove(hashCode);
    setState(() {
      _isPlayingSyncedRecording = false;
    });
  }

  /// 🔧 FIX #7: Subscribe to playback completion so UI auto-resets.
  static final Map<int, StreamSubscription<void>> _playbackCompletedSubs = {};

  void _listenForPlaybackCompletion() {
    _playbackCompletedSubs[hashCode]?.cancel();
    _playbackCompletedSubs[hashCode] = _voiceRecordingProvider.playbackCompleted
        .listen((_) {
          if (mounted && _isPlayingSyncedRecording) {
            setState(() {
              _isPlayingSyncedRecording = false;
            });
            debugPrint('[VoiceRecording] Playback completed naturally');
          }
        });
  }
}
