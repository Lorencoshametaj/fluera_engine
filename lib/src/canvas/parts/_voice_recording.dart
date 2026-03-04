part of '../fluera_canvas_screen.dart';

/// 📦 Voice Recording — generic SDK implementation.
///
/// Delegates all recording, playback, and cloud sync operations to
/// [FlueraVoiceRecordingProvider] provided via [FlueraCanvasConfig].
/// Falls back to [DefaultVoiceRecordingProvider] if no custom provider
/// is configured, enabling zero-config recording.
extension VoiceRecordingExtension on _FlueraCanvasScreenState {
  /// Lazy default provider — created once per canvas state, cleaned up on dispose.
  static final Map<int, DefaultVoiceRecordingProvider> _defaultProviders = {};

  /// 🚦 #7 Rate limiting — last recording broadcast timestamp.
  static int _lastRecordingBroadcastMs = 0;

  /// 💾 #8 Cached recording metadata for fast dialog opens.
  static List<Map<String, dynamic>>? _recordingMetadataCache;
  static int _metadataCacheTimestamp = 0;

  /// 🌵 #3 Live waveform — rolling buffer of recent amplitudes (max 64).
  static final List<double> _liveAmplitudes = [];
  static StreamSubscription? _amplitudeSubscription;
  static DateTime _lastAmplitudeRebuild = DateTime.now();
  static DateTime _lastDurationRebuild = DateTime.now();
  static const int _maxLiveAmplitudes = 64;

  /// 📡 #8 Offline upload queue — recordings pending cloud upload.
  static final List<Map<String, dynamic>> _offlineUploadQueue = [];

  /// 🎛️ Recording quality configuration (user-configurable).
  static AudioRecordConfig _recordingConfig = AudioRecordConfig.high;

  /// Returns the configured provider or a built-in default.
  FlueraVoiceRecordingProvider get _voiceRecordingProvider {
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
                  const SizedBox(height: 4),

                  // Quality settings link
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(context); // close dialog first
                      _showRecordingQualitySettings();
                    },
                    icon: const Icon(Icons.tune, size: 16),
                    label: const Text('Quality Settings'),
                    style: TextButton.styleFrom(
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 12),

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

      await provider.startRecording(config: _recordingConfig);

      _recordingStartTime = DateTime.now();

      // 🎵 Create sync builder when recording with strokes
      if (_recordingWithStrokes) {
        _syncRecordingBuilder = SynchronizedRecordingBuilder(
          id: generateUid(),
          audioPath: '', // Will be updated when recording stops
          startTime: _recordingStartTime!,
          canvasId: widget.canvasId,
        );
        _syncRecordingBuilder!.setRecordingType('note');
      }

      setState(() {
        _isRecordingAudio = true;
        _recordingDuration = Duration.zero;
      });
      // 🚀 Notify toolbar so ListenableBuilder rebuilds with isRecordingActive
      _isRecordingNotifier.value = true;

      // 🔴 Broadcast recording state to collaborators (#4 real position)
      _broadcastCursorPosition(Offset.zero, isRecording: true);

      // Listen to duration updates
      _recordingDurationSubscription?.cancel();
      _recordingDurationSubscription = provider.recordingDuration.listen((
        duration,
      ) {
        _recordingDuration = duration;
        // 🚀 P99 FIX: Use ValueNotifier — no setState() needed.
        // Duration shows only seconds, so 500ms throttle is sufficient.
        final now = DateTime.now();
        if (now.difference(_lastDurationRebuild).inMilliseconds > 500) {
          _lastDurationRebuild = now;
          _recordingDurationNotifier.value = duration;
        }
      });

      // 🌵 #3 Live waveform — listen to amplitude stream
      _amplitudeSubscription?.cancel();
      _liveAmplitudes.clear();
      _lastAmplitudeRebuild = DateTime.now();
      _lastDurationRebuild = DateTime.now();
      if (provider is DefaultVoiceRecordingProvider) {
        _amplitudeSubscription = provider.amplitudeStream.listen((amp) {
          // Normalize: native recorders report dB (negative, -160 to 0)
          // Convert to 0.0–1.0 range
          final normalized = ((amp.current + 60) / 60).clamp(0.0, 1.0);
          _liveAmplitudes.add(normalized);
          if (_liveAmplitudes.length > _maxLiveAmplitudes) {
            _liveAmplitudes.removeAt(0);
          }
          // 🚀 P99 FIX: Use ValueNotifier — no setState() needed.
          // Throttle to ~3 updates/sec (300ms) for smooth waveform.
          final now = DateTime.now();
          if (now.difference(_lastAmplitudeRebuild).inMilliseconds > 300) {
            _lastAmplitudeRebuild = now;
            _recordingAmplitudeNotifier.value = normalized;
          }
        });
      }
    } catch (e) {
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

      // 🖊️ Extract pen contact intervals from synchronized recording builder

      var audioPath = await provider.stopRecording();

      // 🔧 FIX: Do NOT move audio to persistent directory yet —
      // wait until user confirms save in the dialog.
      // The temp path is valid for the dialog preview/playback.
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

      }
      _syncRecordingBuilder = null;

      // 🔧 FIX #3: Capture recording type BEFORE resetting the flag
      final wasRecordingWithStrokes = _recordingWithStrokes;
      // 🔧 Enterprise: Capture start time BEFORE reset (used for audio-only persist)
      final capturedStartTime = _recordingStartTime ?? DateTime.now();

      setState(() {
        _isRecordingAudio = false;
      });
      // 🚀 Notify toolbar so ListenableBuilder rebuilds with isRecordingActive = false
      _isRecordingNotifier.value = false;

      // 🔴 Clear recording state for collaborators (#4 real position)
      _broadcastCursorPosition(Offset.zero, isRecording: false);

      // 🌵 #3 Stop live waveform
      _amplitudeSubscription?.cancel();
      _amplitudeSubscription = null;
      _liveAmplitudes.clear();
      // 🚀 P99 FIX: Reset notifiers instead of setState
      _recordingDurationNotifier.value = Duration.zero;
      _recordingAmplitudeNotifier.value = 0.0;
      setState(() {
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

          // 🎛️ DEFERRED POST-PROCESSING: Apply RNNoise denoising + DSP
          // now that the user confirmed save. This avoids blocking the UI
          // for ~5s between pressing stop and seeing the dialog.
          if (provider is DefaultVoiceRecordingProvider) {
            final recorder = provider.recorder;
            if (recorder.hasPendingPostProcessing) {
              final processed = await recorder.applyPendingPostProcessing(
                audioPath,
              );
              if (processed != null) {
                audioPath = processed;
              }
            }
          }

          // 🔧 FIX: NOW persist audio from temp → permanent directory
          try {
            final docsDir = await getSafeDocumentsDirectory();
            if (docsDir != null) {
              final recordingsDir = Directory('${docsDir.path}/recordings');
              if (!await recordingsDir.exists()) {
                await recordingsDir.create(recursive: true);
              }
              final fileName = audioPath!.split('/').last;
              final persistentPath = '${recordingsDir.path}/$fileName';
              final tempFile = File(audioPath);
              if (await tempFile.exists()) {
                await tempFile.copy(persistentPath);
                await tempFile.delete();
                audioPath = persistentPath;
              }
            }
          } catch (e) {
          }

          // 🔧 FIX: Update syncRecording audioPath to match the persisted path
          // (audioPath may have changed from temp → persistent above)
          if (syncRecording != null) {
            syncRecording = syncRecording.copyWith(audioPath: audioPath!);
          }

          // Attach recording name to synced recording
          if (syncRecording != null &&
              recordingName != null &&
              recordingName.isNotEmpty) {
            syncRecording = syncRecording.copyWith(noteTitle: recordingName);
          }

          // 💾 Build the persistable recording (with name + canvasId)
          SynchronizedRecording? persistable;
          if (RecordingStorageService.instance.isInitialized) {
            persistable =
                syncRecording != null
                    ? syncRecording.copyWith(canvasId: _canvasId)
                    : SynchronizedRecording.empty(
                      id: generateUid(),
                      audioPath: audioPath!,
                      startTime: capturedStartTime,
                      canvasId: _canvasId,
                      noteTitle: recordingName,
                      recordingType: 'audio_only',
                    );
          }

          setState(() {
            _savedRecordings.add(audioPath!);
            // Always add to _syncedRecordings — use persistable (has name + canvasId)
            final toAdd = persistable ?? syncRecording;
            if (toAdd != null) {
              _syncedRecordings.add(toAdd);
            }
          });

          // 💾 Persist to SQLite
          if (persistable != null) {
            try {
              await RecordingStorageService.instance.saveRecording(persistable);

              // ☁️ Upload audio file to cloud for cross-device access
              if (_syncEngine != null) {
                try {
                  // 🚦 #7 Rate limiting — debounce rapid recording broadcasts
                  final now = DateTime.now().millisecondsSinceEpoch;
                  if (now - _lastRecordingBroadcastMs < 2000) {
                  }
                  _lastRecordingBroadcastMs = now;

                  final audioBytes = await File(audioPath!).readAsBytes();
                  final originalSize = audioBytes.length;

                  // ⚡ #6 Offload compression + waveform to Isolate
                  final result = await Isolate.run(() {
                    final compressed = GZipCodec().encode(audioBytes);

                    // 📊 Waveform: 48 normalized amplitudes
                    final headerOff = audioBytes.length > 200 ? 200 : 0;
                    final dataLen = audioBytes.length - headerOff;
                    const sampleCount = 48;
                    final step = dataLen > 0 ? dataLen ~/ sampleCount : 0;
                    final samples = <double>[];
                    double maxAmp = 0;
                    if (step > 0) {
                      for (int i = 0; i < sampleCount; i++) {
                        final off = headerOff + (i * step);
                        if (off >= audioBytes.length) break;
                        double sum = 0;
                        int cnt = 0;
                        for (
                          int j = 0;
                          j < step && (off + j) < audioBytes.length;
                          j += 4
                        ) {
                          sum += (audioBytes[off + j] - 128).abs().toDouble();
                          cnt++;
                        }
                        final avg = cnt > 0 ? sum / cnt : 0.0;
                        samples.add(avg);
                        if (avg > maxAmp) maxAmp = avg;
                      }
                    }
                    final waveform =
                        maxAmp > 0
                            ? samples
                                .map(
                                  (s) => double.parse(
                                    (s / maxAmp)
                                        .clamp(0.0, 1.0)
                                        .toStringAsFixed(2),
                                  ),
                                )
                                .toList()
                            : List.filled(sampleCount, 0.5);

                    return {
                      'compressed': Uint8List.fromList(compressed),
                      'waveform': waveform,
                    };
                  });

                  final compressedData = result['compressed'] as Uint8List;
                  final waveformSamples = result['waveform'] as List<double>;


                  // 📦 #8 Chunked upload for large files (>5MB compressed)
                  const chunkSize = 2 * 1024 * 1024; // 2MB chunks
                  if (compressedData.length > 5 * 1024 * 1024) {
                    final totalChunks =
                        (compressedData.length / chunkSize).ceil();
                    for (int i = 0; i < totalChunks; i++) {
                      final start = i * chunkSize;
                      final end = (start + chunkSize).clamp(
                        0,
                        compressedData.length,
                      );
                      final chunk = compressedData.sublist(start, end);
                      await _syncEngine!.adapter.uploadAsset(
                        _canvasId,
                        'recording_${persistable.id}_chunk_$i',
                        Uint8List.fromList(chunk),
                        mimeType: 'audio/m4a+gzip+chunk',
                      );
                    }
                    final manifest =
                        '{"chunks":$totalChunks,"totalSize":${compressedData.length}}';
                    await _syncEngine!.adapter.uploadAsset(
                      _canvasId,
                      'recording_${persistable.id}',
                      Uint8List.fromList(manifest.codeUnits),
                      mimeType: 'application/json+manifest',
                    );
                  } else {
                    await _syncEngine!.adapter.uploadAsset(
                      _canvasId,
                      'recording_${persistable.id}',
                      compressedData,
                      mimeType: 'audio/m4a+gzip',
                    );
                  }

                  // 🎨 Upload synced strokes as separate compressed asset
                  String? strokesAssetKey;
                  if (persistable.syncedStrokes.isNotEmpty) {
                    try {
                      final strokesJson =
                          persistable.syncedStrokes
                              .map((s) => s.toJson())
                              .toList();
                      final strokesBytes = await Isolate.run(() {
                        // ⚡ Point decimation: keep every 2nd point for dense strokes
                        // Preserves first + last point for timing accuracy
                        for (final strokeMap in strokesJson) {
                          final strokeData =
                              strokeMap['stroke'] as Map<String, dynamic>?;
                          if (strokeData == null) continue;
                          final points = strokeData['points'] as List?;
                          if (points == null || points.length <= 50) continue;
                          final decimated = <dynamic>[];
                          for (int i = 0; i < points.length; i++) {
                            if (i == 0 ||
                                i == points.length - 1 ||
                                i % 2 == 0) {
                              decimated.add(points[i]);
                            }
                          }
                          strokeData['points'] = decimated;
                        }
                        final jsonStr = jsonEncode(strokesJson);
                        return Uint8List.fromList(
                          GZipCodec().encode(utf8.encode(jsonStr)),
                        );
                      });
                      strokesAssetKey = 'strokes_${persistable.id}';
                      await _syncEngine!.adapter.uploadAsset(
                        _canvasId,
                        strokesAssetKey,
                        strokesBytes,
                        mimeType: 'application/json+gzip',
                      );
                    } catch (e) {
                      strokesAssetKey = null;
                    }
                  }

                  // 🔴 Broadcast to collaborators (#1 waveform, #7 author, #10 fileSize)
                  final userName = await _config.getUserId();
                  _realtimeEngine?.broadcastRecordingAdded(
                    recordingId: persistable.id,
                    audioAssetKey: 'recording_${persistable.id}',
                    noteTitle: persistable.noteTitle,
                    durationMs: persistable.totalDuration.inMilliseconds,
                    recordingType: persistable.recordingType,
                    senderName: userName,
                    compressed: true,
                    waveform: waveformSamples,
                    fileSize: originalSize,
                    strokesAssetKey: strokesAssetKey,
                    strokeCount: persistable.syncedStrokes.length,
                  );

                  // 🧹 #5 Memory cleanup — help GC reclaim large buffers
                  // (audioBytes and compressedData go out of scope here)
                } catch (e) {
                  // 📡 #8 Queue for offline sync
                  _queueOfflineUpload(
                    recordingId: persistable.id,
                    audioPath: audioPath!,
                    noteTitle: persistable.noteTitle,
                    durationMs: persistable.totalDuration.inMilliseconds,
                    recordingType: persistable.recordingType,
                  );
                }
              }
            } catch (e) {
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
                  .catchError((e) {
                    EngineScope.current.errorRecovery.reportError(
                      EngineError(
                        severity: ErrorSeverity.transient,
                        domain: ErrorDomain.storage,
                        source: 'VoiceRecording.evictOldRecording.db',
                        original: e,
                      ),
                    );
                    return 0;
                  });
            }
            // Cascade: delete audio file from disk
            try {
              final file = File(evictedPath);
              if (await file.exists()) await file.delete();
            } catch (e, stack) {
              EngineScope.current.errorRecovery.reportError(
                EngineError(
                  severity: ErrorSeverity.transient,
                  domain: ErrorDomain.storage,
                  source: 'VoiceRecording.evictOldRecording.file',
                  original: e,
                  stack: stack,
                ),
              );
            }
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
            }
          } catch (e) {
          }
        }
      }
    } catch (e) {
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
                        fillColor:
                            Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                      ),
                      autofocus: true,
                      textCapitalization: TextCapitalization.sentences,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Duration: ${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
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
      // Defer dispose to after the current frame — Flutter's focus system
      // may still access the controller during the dialog dismissal frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        nameController.dispose();
      });
    }
  }

  /// 🎧 Show dialog listing saved recordings — Material Design 3.
  Future<void> _showSavedRecordingsDialog() async {
    // 🔔 #1 Reset badge counter when user opens recordings
    _resetRecordingsBadge();
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

    // 🧹 #6 Auto-cleanup old recordings on dialog open
    _cleanupOldRecordings();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        final cs = Theme.of(context).colorScheme;
        final tt = Theme.of(context).textTheme;

        // 🔍 #4 Search + 📋 #5 Sort state (local to dialog)
        String searchQuery = '';
        RecordingSortOrder sortOrder = RecordingSortOrder.dateNewest;

        return StatefulBuilder(
          builder: (context, setSheetState) {
            // 🔍 #4 Apply search filter
            final filtered = _filterRecordings(searchQuery);
            // 📋 #5 Apply sort order
            final displayRecordings = _sortRecordings(filtered, sortOrder);

            return DraggableScrollableSheet(
              initialChildSize: 0.5,
              minChildSize: 0.3,
              maxChildSize: 0.85,
              expand: false,
              builder: (context, scrollController) {
                return Column(
                  children: [
                    // ── Drag handle ──
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 4),
                      child: Container(
                        width: 32,
                        height: 4,
                        decoration: BoxDecoration(
                          color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),

                    // ── Header ──
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 8, 8, 0),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [cs.primary, cs.tertiary],
                              ),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.headphones_rounded,
                              color: cs.onPrimary,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Recordings',
                                  style: tt.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  searchQuery.isEmpty
                                      ? '${_savedRecordings.length} recording${_savedRecordings.length != 1 ? 's' : ''}'
                                      : '${displayRecordings.length} of ${_savedRecordings.length}',
                                  style: tt.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // 📋 Sort + more actions
                          PopupMenuButton<String>(
                            icon: Icon(
                              Icons.more_vert_rounded,
                              color: cs.onSurfaceVariant,
                            ),
                            tooltip: 'Options',
                            onSelected: (value) async {
                              if (value.startsWith('sort_')) {
                                final idx = int.parse(value.split('_')[1]);
                                setSheetState(
                                  () =>
                                      sortOrder =
                                          RecordingSortOrder.values[idx],
                                );
                              } else if (value == 'delete_all') {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder:
                                      (dlgCtx) => AlertDialog(
                                        icon: Icon(
                                          Icons.delete_sweep_rounded,
                                          color: cs.error,
                                          size: 32,
                                        ),
                                        title: const Text(
                                          'Delete all recordings?',
                                        ),
                                        content: Text(
                                          'This will permanently delete '
                                          '${displayRecordings.length} recording'
                                          '${displayRecordings.length != 1 ? 's' : ''}.',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed:
                                                () => Navigator.pop(
                                                  dlgCtx,
                                                  false,
                                                ),
                                            child: const Text('Cancel'),
                                          ),
                                          FilledButton(
                                            onPressed:
                                                () =>
                                                    Navigator.pop(dlgCtx, true),
                                            style: FilledButton.styleFrom(
                                              backgroundColor: cs.error,
                                              foregroundColor: cs.onError,
                                            ),
                                            child: const Text('Delete All'),
                                          ),
                                        ],
                                      ),
                                );
                                if (confirmed == true) {
                                  await batchDeleteRecordings(
                                    List<String>.from(displayRecordings),
                                  );
                                  if (mounted) Navigator.pop(context);
                                }
                              }
                            },
                            itemBuilder:
                                (_) => [
                                  // Sort options
                                  const PopupMenuItem<String>(
                                    enabled: false,
                                    height: 32,
                                    child: Text(
                                      'SORT BY',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 1.0,
                                      ),
                                    ),
                                  ),
                                  for (
                                    int i = 0;
                                    i < RecordingSortOrder.values.length;
                                    i++
                                  )
                                    PopupMenuItem<String>(
                                      value: 'sort_$i',
                                      child: Row(
                                        children: [
                                          Icon(
                                            RecordingSortOrder.values[i] ==
                                                    sortOrder
                                                ? Icons.radio_button_checked
                                                : Icons.radio_button_unchecked,
                                            size: 18,
                                            color:
                                                RecordingSortOrder.values[i] ==
                                                        sortOrder
                                                    ? cs.primary
                                                    : cs.onSurfaceVariant,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            _sortOrderLabel(
                                              RecordingSortOrder.values[i],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  const PopupMenuDivider(),
                                  PopupMenuItem<String>(
                                    value: 'delete_all',
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.delete_sweep_rounded,
                                          size: 18,
                                          color: cs.error,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Delete all',
                                          style: TextStyle(color: cs.error),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close_rounded),
                            style: IconButton.styleFrom(
                              foregroundColor: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // 🔍 #4 Search bar
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Search recordings...',
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            size: 20,
                          ),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: cs.outlineVariant),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: cs.outlineVariant),
                          ),
                        ),
                        onChanged: (value) {
                          setSheetState(() => searchQuery = value);
                        },
                      ),
                    ),

                    Divider(height: 1, color: cs.outlineVariant),

                    // ── Recording list ──
                    Expanded(
                      child: ListView.separated(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                        itemCount: displayRecordings.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final path = displayRecordings[index];
                          final synced = _syncedRecordings
                              .cast<SynchronizedRecording?>()
                              .firstWhere(
                                (r) => r?.audioPath == path,
                                orElse: () => null,
                              );
                          // Bug fix #1: Better display name
                          String displayName;
                          if (synced?.noteTitle != null &&
                              synced!.noteTitle!.isNotEmpty) {
                            displayName = synced.noteTitle!;
                          } else {
                            // Use recording start time if available,
                            // otherwise extract date from filename or use
                            // a friendly fallback
                            final file = File(path);
                            if (synced?.startTime != null) {
                              final dt = synced!.startTime;
                              displayName =
                                  'Recording ${dt.day}/${dt.month} '
                                  '${dt.hour.toString().padLeft(2, '0')}:'
                                  '${dt.minute.toString().padLeft(2, '0')}';
                            } else if (file.existsSync()) {
                              final dt = file.lastModifiedSync();
                              displayName =
                                  'Recording ${dt.day}/${dt.month} '
                                  '${dt.hour.toString().padLeft(2, '0')}:'
                                  '${dt.minute.toString().padLeft(2, '0')}';
                            } else {
                              displayName = 'Recording ${index + 1}';
                            }
                          }
                          final hasStrokes =
                              synced != null && synced.syncedStrokes.isNotEmpty;
                          final duration = synced?.totalDuration;

                          return Dismissible(
                            key: ValueKey(path),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              decoration: BoxDecoration(
                                color: cs.errorContainer,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Icon(
                                Icons.delete_rounded,
                                color: cs.onErrorContainer,
                              ),
                            ),
                            confirmDismiss: (_) async {
                              return await showDialog<bool>(
                                context: context,
                                builder:
                                    (ctx) => AlertDialog(
                                      icon: Icon(
                                        Icons.delete_forever_rounded,
                                        color: cs.error,
                                        size: 32,
                                      ),
                                      title: const Text('Delete recording?'),
                                      content: const Text(
                                        'This action cannot be undone.',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed:
                                              () => Navigator.pop(ctx, false),
                                          child: const Text('Cancel'),
                                        ),
                                        FilledButton(
                                          onPressed:
                                              () => Navigator.pop(ctx, true),
                                          style: FilledButton.styleFrom(
                                            backgroundColor: cs.error,
                                            foregroundColor: cs.onError,
                                          ),
                                          child: const Text('Delete'),
                                        ),
                                      ],
                                    ),
                              );
                            },
                            onDismissed: (_) async {
                              final deletedPath = _savedRecordings[index];

                              setState(() {
                                _savedRecordings.removeAt(index);
                              });

                              // Find recording ID for broadcast
                              final deletedRecording =
                                  _syncedRecordings
                                      .where((r) => r.audioPath == deletedPath)
                                      .toList();
                              final deletedRecordingId =
                                  deletedRecording.isNotEmpty
                                      ? deletedRecording.first.id
                                      : null;

                              _syncedRecordings.removeWhere(
                                (r) => r.audioPath == deletedPath,
                              );

                              if (RecordingStorageService
                                  .instance
                                  .isInitialized) {
                                await RecordingStorageService.instance
                                    .deleteByAudioPath(deletedPath);
                              }

                              // 🔴 Broadcast removal to collaborators
                              if (deletedRecordingId != null) {
                                _realtimeEngine?.broadcastRecordingRemoved(
                                  recordingId: deletedRecordingId,
                                  audioPath: deletedPath,
                                );

                                // 🧹 Clean up cloud assets (audio + strokes)
                                _syncEngine?.adapter
                                    .deleteAsset(
                                      _canvasId,
                                      'recording_$deletedRecordingId',
                                    )
                                    .catchError((_) {});
                                _syncEngine?.adapter
                                    .deleteAsset(
                                      _canvasId,
                                      'strokes_$deletedRecordingId',
                                    )
                                    .catchError((_) {});
                              }

                              try {
                                final file = File(deletedPath);
                                if (await file.exists()) await file.delete();
                              } catch (e, stack) {
                                EngineScope.current.errorRecovery.reportError(
                                  EngineError(
                                    severity: ErrorSeverity.transient,
                                    domain: ErrorDomain.storage,
                                    source:
                                        'VoiceRecording.deleteRecording.file',
                                    original: e,
                                    stack: stack,
                                  ),
                                );
                              }

                              if (mounted) {
                                ScaffoldMessenger.of(this.context).showSnackBar(
                                  SnackBar(
                                    content: const Text('Recording deleted'),
                                    backgroundColor: cs.error,
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                );
                              }

                              // Close sheet if no recordings left
                              if (_savedRecordings.isEmpty && mounted) {
                                Navigator.pop(context);
                              }
                            },
                            child: Card(
                              elevation: 0,
                              color: cs.surfaceContainerLow,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () {
                                  Navigator.pop(context);
                                  // Check if recording has synced strokes
                                  if (synced != null && synced.hasStrokes) {
                                    _startSyncedPlayback(synced);
                                  } else {
                                    _startAudioPlayback(
                                      path,
                                      displayName,
                                      provider,
                                    );
                                  }
                                },
                                // ✏️ #3 Rename on long-press
                                onLongPress:
                                    synced != null
                                        ? () {
                                          final controller =
                                              TextEditingController(
                                                text: displayName,
                                              );
                                          showDialog(
                                            context: context,
                                            builder:
                                                (dlgCtx) => AlertDialog(
                                                  icon: Icon(
                                                    Icons.edit_rounded,
                                                    color: cs.primary,
                                                  ),
                                                  title: const Text(
                                                    'Rename Recording',
                                                  ),
                                                  content: TextField(
                                                    controller: controller,
                                                    autofocus: true,
                                                    decoration:
                                                        const InputDecoration(
                                                          labelText: 'Name',
                                                          border:
                                                              OutlineInputBorder(),
                                                        ),
                                                    onSubmitted: (value) {
                                                      if (value
                                                          .trim()
                                                          .isNotEmpty) {
                                                        Navigator.pop(
                                                          dlgCtx,
                                                          value.trim(),
                                                        );
                                                      }
                                                    },
                                                  ),
                                                  actions: [
                                                    TextButton(
                                                      onPressed:
                                                          () => Navigator.pop(
                                                            dlgCtx,
                                                          ),
                                                      child: const Text(
                                                        'Cancel',
                                                      ),
                                                    ),
                                                    FilledButton(
                                                      onPressed: () {
                                                        final val =
                                                            controller.text
                                                                .trim();
                                                        if (val.isNotEmpty) {
                                                          Navigator.pop(
                                                            dlgCtx,
                                                            val,
                                                          );
                                                        }
                                                      },
                                                      child: const Text(
                                                        'Rename',
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                          ).then((newName) {
                                            if (newName != null &&
                                                newName is String &&
                                                newName.isNotEmpty) {
                                              batchRenameRecordings({
                                                synced.id: newName,
                                              });
                                              setSheetState(() {});
                                            }
                                          });
                                        }
                                        : null,
                                child: Padding(
                                  padding: const EdgeInsets.all(0),
                                  child: IntrinsicHeight(
                                    child: Row(
                                      children: [
                                        // Gradient accent bar
                                        Container(
                                          width: 4,
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              begin: Alignment.topCenter,
                                              end: Alignment.bottomCenter,
                                              colors:
                                                  hasStrokes
                                                      ? [
                                                        cs.primary,
                                                        cs.tertiary,
                                                      ]
                                                      : [
                                                        cs.secondary,
                                                        cs.secondary.withValues(
                                                          alpha: 0.3,
                                                        ),
                                                      ],
                                            ),
                                            borderRadius:
                                                const BorderRadius.only(
                                                  topLeft: Radius.circular(16),
                                                  bottomLeft: Radius.circular(
                                                    16,
                                                  ),
                                                ),
                                          ),
                                        ),
                                        // Content
                                        Expanded(
                                          child: Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                              14,
                                              14,
                                              14,
                                              14,
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                // Title row
                                                Row(
                                                  children: [
                                                    // Play icon
                                                    Container(
                                                      width: 36,
                                                      height: 36,
                                                      decoration: BoxDecoration(
                                                        color:
                                                            hasStrokes
                                                                ? cs.primaryContainer
                                                                : cs.secondaryContainer,
                                                        shape: BoxShape.circle,
                                                      ),
                                                      child: Icon(
                                                        Icons
                                                            .play_arrow_rounded,
                                                        color:
                                                            hasStrokes
                                                                ? cs.onPrimaryContainer
                                                                : cs.onSecondaryContainer,
                                                        size: 20,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 12),
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Text(
                                                            displayName,
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style: tt.bodyLarge
                                                                ?.copyWith(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                  letterSpacing:
                                                                      -0.2,
                                                                ),
                                                          ),
                                                          if (synced
                                                                  ?.startTime !=
                                                              null)
                                                            Padding(
                                                              padding:
                                                                  const EdgeInsets.only(
                                                                    top: 2,
                                                                  ),
                                                              child: Text(
                                                                _formatRecordingDate(
                                                                  synced!
                                                                      .startTime,
                                                                ),
                                                                style: tt
                                                                    .labelSmall
                                                                    ?.copyWith(
                                                                      color: cs
                                                                          .onSurfaceVariant
                                                                          .withValues(
                                                                            alpha:
                                                                                0.7,
                                                                          ),
                                                                    ),
                                                              ),
                                                            ),
                                                        ],
                                                      ),
                                                    ),
                                                    // 📌 Pin to canvas button
                                                    if (synced != null)
                                                      SizedBox(
                                                        width: 32,
                                                        height: 32,
                                                        child: IconButton(
                                                          padding:
                                                              EdgeInsets.zero,
                                                          iconSize: 18,
                                                          icon: Icon(
                                                            _recordingPins.any(
                                                                  (p) =>
                                                                      p.recordingId ==
                                                                      synced.id,
                                                                )
                                                                ? Icons.push_pin
                                                                : Icons
                                                                    .push_pin_outlined,
                                                            color:
                                                                _recordingPins.any(
                                                                      (p) =>
                                                                          p.recordingId ==
                                                                          synced
                                                                              .id,
                                                                    )
                                                                    ? cs.primary
                                                                    : cs.onSurfaceVariant,
                                                          ),
                                                          tooltip:
                                                              _recordingPins.any(
                                                                    (p) =>
                                                                        p.recordingId ==
                                                                        synced
                                                                            .id,
                                                                  )
                                                                  ? 'Already pinned'
                                                                  : 'Pin to canvas',
                                                          onPressed: () {
                                                            if (_recordingPins.any(
                                                              (p) =>
                                                                  p.recordingId ==
                                                                  synced.id,
                                                            )) {
                                                              // Already pinned — unpin
                                                              final removedPins =
                                                                  _recordingPins
                                                                      .where(
                                                                        (p) =>
                                                                            p.recordingId ==
                                                                            synced.id,
                                                                      )
                                                                      .map(
                                                                        (p) =>
                                                                            p.id,
                                                                      )
                                                                      .toList();
                                                              setSheetState(() {
                                                                setState(() {
                                                                  _recordingPins
                                                                      .removeWhere(
                                                                        (p) =>
                                                                            p.recordingId ==
                                                                            synced.id,
                                                                      );
                                                                });
                                                              });
                                                              _autoSaveCanvas();
                                                              for (final id
                                                                  in removedPins) {
                                                                _broadcastPinRemoved(
                                                                  id,
                                                                );
                                                              }
                                                              HapticFeedback.mediumImpact();
                                                              return;
                                                            }
                                                            // Close popup, enter pin placement mode
                                                            Navigator.pop(
                                                              context,
                                                            );
                                                            _enterPinPlacementMode(
                                                              synced,
                                                            );
                                                          },
                                                        ),
                                                      ),
                                                  ],
                                                ),

                                                // Waveform preview
                                                FutureBuilder<List<double>>(
                                                  future: File(
                                                    path,
                                                  ).exists().then((
                                                    exists,
                                                  ) async {
                                                    if (!exists) {
                                                      return <double>[];
                                                    }
                                                    final bytes =
                                                        await File(
                                                          path,
                                                        ).readAsBytes();
                                                    return _computeWaveformPreview(
                                                      bytes,
                                                      sampleCount: 64,
                                                    );
                                                  }),
                                                  builder: (context, snapshot) {
                                                    if (!snapshot.hasData ||
                                                        snapshot
                                                            .data!
                                                            .isEmpty) {
                                                      return const SizedBox(
                                                        height: 8,
                                                      );
                                                    }
                                                    return Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                            top: 10,
                                                            bottom: 2,
                                                          ),
                                                      child:
                                                          _buildWaveformPreview(
                                                            snapshot.data!,
                                                            height: 28,
                                                          ),
                                                    );
                                                  },
                                                ),

                                                // Metadata chips
                                                const SizedBox(height: 6),
                                                Wrap(
                                                  spacing: 6,
                                                  runSpacing: 4,
                                                  children: [
                                                    if (duration != null)
                                                      _buildMetadataChip(
                                                        Icons.timer_outlined,
                                                        '${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}',
                                                        cs.surfaceContainerHighest,
                                                        cs.onSurfaceVariant,
                                                      ),
                                                    _buildMetadataChip(
                                                      hasStrokes
                                                          ? Icons.draw_rounded
                                                          : Icons.mic_rounded,
                                                      hasStrokes
                                                          ? '${synced!.syncedStrokes.length} strokes'
                                                          : 'Audio only',
                                                      hasStrokes
                                                          ? cs.tertiaryContainer
                                                          : cs.secondaryContainer,
                                                      hasStrokes
                                                          ? cs.onTertiaryContainer
                                                          : cs.onSecondaryContainer,
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            );
          }, // StatefulBuilder builder
        ); // StatefulBuilder
      },
    );
  }

  /// 📋 #5 Human-readable label for sort order.
  String _sortOrderLabel(RecordingSortOrder order) {
    switch (order) {
      case RecordingSortOrder.dateNewest:
        return 'Newest first';
      case RecordingSortOrder.dateOldest:
        return 'Oldest first';
      case RecordingSortOrder.nameAZ:
        return 'Name A→Z';
      case RecordingSortOrder.nameZA:
        return 'Name Z→A';
      case RecordingSortOrder.durationLongest:
        return 'Longest first';
    }
  }

  /// 📅 Format recording date intelligently.
  String _formatRecordingDate(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final recordDate = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(recordDate).inDays;

    final time =
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';

    if (diff == 0) return 'Today, $time';
    if (diff == 1) return 'Yesterday, $time';
    if (diff < 7) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return '${days[dt.weekday - 1]}, $time';
    }
    return '${dt.day}/${dt.month}/${dt.year}, $time';
  }

  /// 💊 Build a metadata chip with icon + label.
  Widget _buildMetadataChip(
    IconData icon,
    String label,
    Color backgroundColor,
    Color foregroundColor,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: foregroundColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: foregroundColor,
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // 📌 RECORDING PINS ON CANVAS
  // =========================================================================

  /// 📌 Build the recording pins overlay (rendered on the canvas).
  ///
  /// This is a **render-only** layer — IgnorePointer is always true.
  /// Interaction (tap, long-press, drag) is handled by the main canvas
  /// gesture detector, which calls [_handleRecordingPinTap],
  /// [_handleRecordingPinLongPress], and [_handleRecordingPinDrag].
  Widget _buildRecordingPinsOverlay(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final controller = _canvasController;

    return Positioned.fill(
      child: IgnorePointer(
        child: ListenableBuilder(
          listenable: controller,
          builder:
              (context, _) => CustomPaint(
                painter: _RecordingPinPainter(
                  pins: _recordingPins,
                  controller: controller,
                  primaryColor: cs.primary,
                  tertiaryColor: cs.tertiary,
                  secondaryColor: cs.secondary,
                  onPrimaryColor: cs.onPrimary,
                  surfaceColor: cs.surface,
                  onSurfaceColor: cs.onSurface,
                  isPinPlacementMode: _isPinPlacementMode,
                  playingRecordingId:
                      _currentPlaybackPath.isNotEmpty
                          ? _currentPlaybackPath
                          : null,
                  draggingPinId: _draggingPinId,
                ),
              ),
        ),
      ),
    );
  }

  /// 📌 Enter pin placement mode from the recordings popup.
  ///
  /// Called when user taps the 📌 button on a recording card.
  /// Canvas enters "placement mode" where the next tap creates a pin.
  void _enterPinPlacementMode(SynchronizedRecording recording) {
    setState(() {
      _isPinPlacementMode = true;
      _pinPlacementRecording = recording;
    });
  }

  /// 📌 Complete pin placement — user tapped on the canvas.
  void _completePinPlacement(Offset screenPosition) {
    final recording = _pinPlacementRecording;
    if (recording == null) return;

    // Convert screen position to canvas coordinates
    final canvasPos = _canvasController.screenToCanvas(screenPosition);

    // Calculate duration from recording metadata
    final duration = recording.totalDuration;

    // Build display name
    String label;
    if (recording.noteTitle != null && recording.noteTitle!.isNotEmpty) {
      label = recording.noteTitle!;
    } else {
      final dt = recording.startTime;
      label =
          '${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
    }

    final pin = RecordingPin(
      id: generateUid(),
      recordingId: recording.id,
      position: canvasPos,
      label: label,
      duration: duration,
      hasStrokes: recording.syncedStrokes.isNotEmpty,
      createdAt: DateTime.now(),
    );

    setState(() {
      _recordingPins.add(pin);
      _isPinPlacementMode = false;
      _pinPlacementRecording = null;
    });

    // Auto-save
    _autoSaveCanvas();

    // 📡 Broadcast pin to collaborators
    _broadcastPinAdded(pin);

    // Haptic feedback
    HapticFeedback.mediumImpact();
  }

  /// 📌 Cancel pin placement mode (e.g. user tapped back).
  void _cancelPinPlacement() {
    setState(() {
      _isPinPlacementMode = false;
      _pinPlacementRecording = null;
    });
  }

  /// 📌 Handle tap on a recording pin (hit-test in canvas coordinates).
  ///
  /// Returns true if a pin was tapped (consumed the event).
  bool _handleRecordingPinTap(Offset canvasPosition) {
    if (_recordingPins.isEmpty) return false;

    const hitRadius = 24.0;
    for (final pin in _recordingPins.reversed) {
      final dx = canvasPosition.dx - pin.position.dx;
      final dy = canvasPosition.dy - pin.position.dy;
      if (dx * dx + dy * dy <= hitRadius * hitRadius) {
        // Found a pin — start playback
        _playRecordingFromPin(pin);
        return true;
      }
    }
    return false;
  }

  /// 📌 Handle long-press on a recording pin.
  ///
  /// Returns true if a pin was long-pressed.
  bool _handleRecordingPinLongPress(Offset canvasPosition) {
    if (_recordingPins.isEmpty) return false;

    const hitRadius = 24.0;
    for (final pin in _recordingPins.reversed) {
      final dx = canvasPosition.dx - pin.position.dx;
      final dy = canvasPosition.dy - pin.position.dy;
      if (dx * dx + dy * dy <= hitRadius * hitRadius) {
        // Show context menu for this pin
        _showPinContextMenu(pin);
        return true;
      }
    }
    return false;
  }

  /// 📌 Play the recording associated with a pin.
  void _playRecordingFromPin(RecordingPin pin) async {
    HapticFeedback.lightImpact();

    final provider = _voiceRecordingProvider;
    if (provider == null) return;

    // Load the synchronized recording from storage
    SynchronizedRecording? synced;
    if (RecordingStorageService.instance.isInitialized) {
      synced = await RecordingStorageService.instance.loadRecordingById(
        pin.recordingId,
      );
    }

    if (synced != null && synced.syncedStrokes.isNotEmpty) {
      // Synced playback (audio + strokes)
      _startSyncedPlayback(synced);
    } else if (synced?.audioPath != null) {
      // Audio-only playback
      _startAudioPlayback(synced!.audioPath!, pin.label, provider);
    }
  }

  /// 📌 Show context menu for a pin (long-press).
  void _showPinContextMenu(RecordingPin pin) {
    final cs = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  pin.label,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: Icon(Icons.play_arrow_rounded, color: cs.primary),
                  title: const Text('Play'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _playRecordingFromPin(pin);
                  },
                ),
                ListTile(
                  leading: Icon(Icons.push_pin_outlined, color: cs.error),
                  title: const Text('Unpin'),
                  onTap: () {
                    Navigator.pop(ctx);
                    final removedId = pin.id;
                    setState(() {
                      _recordingPins.removeWhere((p) => p.id == pin.id);
                    });
                    _autoSaveCanvas();
                    _broadcastPinRemoved(removedId);
                    HapticFeedback.mediumImpact();
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
    );
  }

  /// 📌 Try to start dragging a pin at the given canvas position.
  /// Returns true if a pin was hit and drag started.
  bool _handleRecordingPinDragStart(Offset canvasPosition) {
    if (_recordingPins.isEmpty) return false;

    const hitRadius = 28.0; // Slightly larger for easier dragging
    for (final pin in _recordingPins.reversed) {
      final dx = canvasPosition.dx - pin.position.dx;
      final dy = canvasPosition.dy - pin.position.dy;
      if (dx * dx + dy * dy <= hitRadius * hitRadius) {
        _draggingPinId = pin.id;
        _draggingPinOffset = canvasPosition - pin.position;
        _pinDragStartCanvasPos = canvasPosition; // Track for tap detection
        // No setState here — wait for first drag update or tap
        return true;
      }
    }
    return false;
  }

  /// 📌 Update pin position during drag.
  void _handleRecordingPinDragUpdate(Offset canvasPosition) {
    if (_draggingPinId == null) return;

    final offset = _draggingPinOffset ?? Offset.zero;
    final newPos = canvasPosition - offset;

    setState(() {
      final idx = _recordingPins.indexWhere((p) => p.id == _draggingPinId);
      if (idx != -1) {
        _recordingPins[idx] = _recordingPins[idx].copyWith(position: newPos);
      }
    });
  }

  /// 📌 End pin drag — if displacement < threshold, treat as tap.
  void _handleRecordingPinDragEnd(Offset canvasPosition) {
    if (_draggingPinId == null) return;

    // Tap detection: if finger barely moved, play instead of drag
    const tapThreshold = 8.0;
    final startPos = _pinDragStartCanvasPos;
    final displaced =
        startPos != null
            ? (canvasPosition - startPos).distance
            : double.infinity;

    if (displaced < tapThreshold) {
      // Revert any micro-movement
      if (startPos != null) {
        final idx = _recordingPins.indexWhere((p) => p.id == _draggingPinId);
        if (idx != -1) {
          final offset = _draggingPinOffset ?? Offset.zero;
          _recordingPins[idx] = _recordingPins[idx].copyWith(
            position: startPos - offset,
          );
        }
      }

      final tapPos = startPos ?? canvasPosition;
      setState(() {
        _draggingPinId = null;
        _draggingPinOffset = null;
        _pinDragStartCanvasPos = null;
      });

      // Delegate to tap handler → plays recording
      _handleRecordingPinTap(tapPos);
      return;
    }

    // Real drag — finalize position
    final pin = _recordingPins.firstWhere(
      (p) => p.id == _draggingPinId,
      orElse: () => _recordingPins.first,
    );

    setState(() {
      _draggingPinId = null;
      _draggingPinOffset = null;
      _pinDragStartCanvasPos = null;
    });

    _autoSaveCanvas();
    _broadcastPinAdded(pin); // Re-broadcast with updated position
    HapticFeedback.lightImpact();
  }

  /// 🎵 Start synced playback (audio + strokes animated on canvas).
  Future<void> _startSyncedPlayback(SynchronizedRecording recording) async {
    // Stop any existing playback
    _stopAudioPlayback();

    try {
      // Create or reuse playback controller
      _playbackController?.dispose();
      _playbackController = SynchronizedPlaybackController();

      // Load the recording into the controller
      await _playbackController!.loadRecording(recording);

      setState(() {
        _isPlayingSyncedRecording = true;
      });

      // Start playback
      await _playbackController!.play();

    } catch (e) {
      _stopSyncedPlayback();
    }
  }

  /// 🎵 Stop synced playback.
  void _stopSyncedPlayback() {
    _playbackController?.stop();
    _playbackController?.unload();
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
          }
          if (mounted && _isPlayingAudio) {
            // 🔁 Loop: replay from start
            if (_isLooping && _currentPlaybackPath.isNotEmpty) {
              _startAudioPlayback(
                _currentPlaybackPath,
                _playingRecordingName,
                _voiceRecordingProvider,
              );
            } else {
              _stopAudioPlayback();
            }
          }
        });
  }

  /// 🎵 Start audio-only playback with mini-player UI.
  void _startAudioPlayback(
    String path,
    String name,
    FlueraVoiceRecordingProvider provider,
  ) async {
    // Stop any existing playback
    _playbackPositionSub?.cancel();

    setState(() {
      _isPlayingAudio = true;
      _playingRecordingName = name;
      _currentPlaybackPath = path;
      _playbackPosition = Duration.zero;
      _playbackDuration = Duration.zero;
    });

    // 🎧 #2 Broadcast listening state to collaborators
    _broadcastCursorPosition(Offset.zero, isListening: true);

    try {
      await provider.playRecording(path);
      _listenForPlaybackCompletion();

      // 🎯 Reliable polling for position + duration (event streams unreliable)
      final defaultProvider = _voiceRecordingProvider;
      if (defaultProvider is DefaultVoiceRecordingProvider) {
        // Poll position + duration every 200ms via method channel
        _playbackPollingTimer?.cancel();
        _playbackPollingTimer = Timer.periodic(
          const Duration(milliseconds: 200),
          (_) async {
            if (!mounted || !_isPlayingAudio) {
              _playbackPollingTimer?.cancel();
              return;
            }
            try {
              final pos = await defaultProvider.getPositionAsync();
              final dur = await defaultProvider.getDurationAsync();
              if (!mounted || !_isPlayingAudio) return;
              setState(() {
                _playbackPosition = pos;
                if (dur != null && dur.inMilliseconds > 0) {
                  _playbackDuration = dur;
                }
              });
            } catch (_) {
              // Polling failed — next tick retries
            }
          },
        );
      }
    } catch (e) {
      _stopAudioPlayback();
    }
  }

  /// 🎵 Stop audio playback and hide mini-player.
  void _stopAudioPlayback() {
    HapticFeedback.mediumImpact();
    _playbackPositionSub?.cancel();
    _playbackPositionSub = null;
    _playbackDurationSub?.cancel();
    _playbackDurationSub = null;
    _playbackPollingTimer?.cancel();
    _playbackPollingTimer = null;
    _voiceRecordingProvider.stopPlayback();
    _playbackCompletedSubs[hashCode]?.cancel();
    _playbackCompletedSubs.remove(hashCode);

    // 🎧 #2 Clear listening state for collaborators
    _broadcastCursorPosition(Offset.zero, isListening: false);

    if (mounted) {
      setState(() {
        _isPlayingAudio = false;
        _isPlaybackPaused = false;
        _playingRecordingName = '';
        _playbackPosition = Duration.zero;
        _playbackDuration = Duration.zero;
        _playbackSpeed = 1.0;
        _showRemainingTime = false;
        _isLooping = false;
        _currentPlaybackPath = '';
        _playbackVolume = 1.0;
        _isScrubbing = false;
      });
    }
  }

  /// 🎵 Toggle play/pause.
  void _toggleAudioPlayback() {
    HapticFeedback.lightImpact();
    final provider = _voiceRecordingProvider;
    if (provider is! DefaultVoiceRecordingProvider) return;

    if (_isPlaybackPaused) {
      provider.resumePlayback();
      setState(() => _isPlaybackPaused = false);
    } else {
      provider.pausePlayback();
      setState(() => _isPlaybackPaused = true);
    }
  }

  /// 🎵 Cycle playback speed: 1x → 1.5x → 2x → 1x.
  void _cyclePlaybackSpeed() {
    HapticFeedback.lightImpact();
    final provider = _voiceRecordingProvider;
    if (provider is! DefaultVoiceRecordingProvider) return;

    final nextSpeed = switch (_playbackSpeed) {
      1.0 => 1.5,
      1.5 => 2.0,
      _ => 1.0,
    };
    provider.setSpeed(nextSpeed);
    setState(() => _playbackSpeed = nextSpeed);
  }

  /// 🔁 Toggle loop mode.
  void _toggleLoop() {
    HapticFeedback.selectionClick();
    setState(() => _isLooping = !_isLooping);
  }

  /// 🔊 Set volume.
  void _setPlaybackVolume(double vol) {
    final provider = _voiceRecordingProvider;
    if (provider is! DefaultVoiceRecordingProvider) return;
    final v = vol.clamp(0.0, 1.0);
    provider.setVolume(v);
    setState(() => _playbackVolume = v);
  }

  /// 🔇 Toggle mute.
  void _toggleMute() {
    HapticFeedback.selectionClick();
    if (_playbackVolume > 0) {
      _lastVolumeBeforeMute = _playbackVolume;
      _setPlaybackVolume(0.0);
    } else {
      _setPlaybackVolume(
        _lastVolumeBeforeMute > 0 ? _lastVolumeBeforeMute : 1.0,
      );
    }
  }

  /// 🎵 Skip forward/back by [seconds].
  void _skipAudioPlayback(int seconds) {
    HapticFeedback.selectionClick();
    final provider = _voiceRecordingProvider;
    if (provider is! DefaultVoiceRecordingProvider) return;
    if (_playbackDuration.inMilliseconds <= 0) return;

    final newPos = Duration(
      milliseconds: (_playbackPosition.inMilliseconds + seconds * 1000).clamp(
        0,
        _playbackDuration.inMilliseconds,
      ),
    );
    provider.seekPlayback(newPos);
    setState(() => _playbackPosition = newPos);
  }

  /// 🎵 Seek to position fraction (0.0–1.0).
  void _seekAudioPlayback(double fraction) {
    final provider = _voiceRecordingProvider;
    if (provider is! DefaultVoiceRecordingProvider) return;
    if (_playbackDuration.inMilliseconds <= 0) return;

    final target = Duration(
      milliseconds: (_playbackDuration.inMilliseconds * fraction).round(),
    );
    provider.seekPlayback(target);
  }

  /// 🎵 Build the floating audio mini-player widget.
  Widget _buildAudioMiniPlayer(BuildContext context) {
    final themeIsDark = Theme.of(context).brightness == Brightness.dark;
    // Mini-player always has dark background → always use dark-mode palette
    final cs =
        themeIsDark
            ? Theme.of(context).colorScheme
            : ColorScheme.fromSeed(
              seedColor: Theme.of(context).colorScheme.primary,
              brightness: Brightness.dark,
            );
    final tt = Theme.of(context).textTheme;
    // Mini-player is always dark-styled (dark bg even in light theme)
    final progress =
        _playbackDuration.inMilliseconds > 0
            ? (_playbackPosition.inMilliseconds /
                    _playbackDuration.inMilliseconds)
                .clamp(0.0, 1.0)
            : 0.0;

    String fmt(Duration d) {
      final m = d.inMinutes;
      final s = (d.inSeconds % 60).toString().padLeft(2, '0');
      return '$m:$s';
    }

    final timeText =
        _showRemainingTime
            ? '-${fmt(_playbackDuration - _playbackPosition)}'
            : fmt(_playbackPosition);

    // 🎵 Equalizer bar heights (sin-wave)
    final t = _playbackPosition.inMilliseconds / 1000.0;
    final barHeights = <double>[
      _isPlaybackPaused ? 5 : 6 + 14 * ((math.sin(t * 4.1) + 1) / 2),
      _isPlaybackPaused ? 5 : 6 + 18 * ((math.sin(t * 5.7 + 1.2) + 1) / 2),
      _isPlaybackPaused ? 5 : 6 + 12 * ((math.sin(t * 3.3 + 2.8) + 1) / 2),
      _isPlaybackPaused ? 5 : 6 + 16 * ((math.sin(t * 6.1 + 0.5) + 1) / 2),
      _isPlaybackPaused ? 5 : 6 + 10 * ((math.sin(t * 4.9 + 3.6) + 1) / 2),
    ];

    final speedLabel = _playbackSpeed == 1.0 ? '1x' : '${_playbackSpeed}x';

    return Positioned(
      bottom: 16,
      left: 16,
      right: 16,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutBack,
        builder: (context, value, child) {
          return Transform.translate(
            offset: Offset(0, 60 * (1 - value)),
            child: Opacity(opacity: value.clamp(0.0, 1.0), child: child),
          );
        },
        child: GestureDetector(
          onVerticalDragEnd: (details) {
            if (details.primaryVelocity != null &&
                details.primaryVelocity! > 200) {
              _stopAudioPlayback();
            }
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  // Always dark + opaque — canvas is white in both themes
                  color: const Color(0xFF1E1E2E).withValues(alpha: 0.92),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                    width: 0.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 30,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── Animated gradient accent line ──
                    Container(
                      height: 3,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            cs.primary.withValues(alpha: 0.0),
                            cs.primary,
                            cs.tertiary,
                            cs.primary.withValues(alpha: 0.0),
                          ],
                          stops: [
                            0.0,
                            (0.25 + 0.15 * math.sin(t * 1.5)).clamp(0.05, 0.45),
                            (0.75 + 0.15 * math.sin(t * 1.5 + 1.0)).clamp(
                              0.55,
                              0.95,
                            ),
                            1.0,
                          ],
                        ),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(22),
                        ),
                      ),
                    ),

                    // ── Drag handle pill ──
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(top: 6),
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: cs.onSurface.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),

                    // ── Title row ──
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 8, 0),
                      child: Row(
                        children: [
                          // 🎤 Mic icon
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Icon(
                              Icons.mic_rounded,
                              size: 16,
                              color: cs.primary,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              _playingRecordingName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tt.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.3,
                                color: cs.onSurface,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: _stopAudioPlayback,
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: cs.onSurface.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  Icons.close_rounded,
                                  color: cs.onSurfaceVariant,
                                  size: 16,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                      ),
                    ),

                    // ── Controls row ──
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Speed chip
                          GestureDetector(
                            onTap: _cyclePlaybackSpeed,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    _playbackSpeed != 1.0
                                        ? cs.primaryContainer
                                        : Colors.white.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                speedLabel,
                                style: tt.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color:
                                      _playbackSpeed != 1.0
                                          ? cs.onPrimaryContainer
                                          : cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),

                          // 🔁 Loop toggle
                          GestureDetector(
                            onTap: _toggleLoop,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: 34,
                              height: 28,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color:
                                    _isLooping
                                        ? cs.primaryContainer
                                        : Colors.white.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.repeat_rounded,
                                size: 16,
                                color:
                                    _isLooping
                                        ? cs.onPrimaryContainer
                                        : cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),

                          // 🔖 Bookmark at current position
                          GestureDetector(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              final posMs = _playbackPosition.inMilliseconds;
                              addBookmark(
                                _playingRecordingName,
                                _playbackPosition,
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '🔖 Bookmark added at ${fmt(_playbackPosition)}',
                                  ),
                                  duration: const Duration(seconds: 1),
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              );
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: 34,
                              height: 28,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.bookmark_add_rounded,
                                size: 16,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                          const Spacer(),

                          // ⏪ Skip back 10s
                          _buildMiniPlayerSkipBtn(
                            Icons.replay_10_rounded,
                            () => _skipAudioPlayback(-10),
                            cs,
                          ),
                          const SizedBox(width: 8),

                          // ▶️ Play/Pause
                          GestureDetector(
                            onTap: _toggleAudioPlayback,
                            onDoubleTap: () {
                              HapticFeedback.mediumImpact();
                              _seekAudioPlayback(0.0);
                              if (_isPlaybackPaused) _toggleAudioPlayback();
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeOutCubic,
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    cs.primary,
                                    Color.lerp(cs.primary, cs.tertiary, 0.3)!,
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: cs.primary.withValues(
                                      alpha:
                                          _isPlaybackPaused
                                              ? 0.2
                                              : 0.15 +
                                                  0.25 *
                                                      ((math.sin(t * 3.0) + 1) /
                                                          2),
                                    ),
                                    blurRadius:
                                        _isPlaybackPaused
                                            ? 12
                                            : 12 +
                                                10 *
                                                    ((math.sin(t * 3.0) + 1) /
                                                        2),
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 200),
                                transitionBuilder:
                                    (child, anim) => ScaleTransition(
                                      scale: anim,
                                      child: child,
                                    ),
                                child:
                                    _isPlaybackPaused
                                        ? Icon(
                                          Icons.play_arrow_rounded,
                                          key: const ValueKey('play'),
                                          color: cs.onPrimary,
                                          size: 30,
                                        )
                                        : Row(
                                          key: const ValueKey('eq'),
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          children: List.generate(5, (i) {
                                            return AnimatedContainer(
                                              duration: const Duration(
                                                milliseconds: 180,
                                              ),
                                              curve: Curves.easeInOut,
                                              width: 3.5,
                                              height: barHeights[i],
                                              margin: EdgeInsets.only(
                                                right: i < 4 ? 2.5 : 0,
                                              ),
                                              decoration: BoxDecoration(
                                                color: cs.onPrimary,
                                                borderRadius:
                                                    BorderRadius.circular(1.5),
                                              ),
                                            );
                                          }),
                                        ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),

                          // ⏩ Skip forward 10s
                          _buildMiniPlayerSkipBtn(
                            Icons.forward_10_rounded,
                            () => _skipAudioPlayback(10),
                            cs,
                          ),
                          const Spacer(),

                          // Time (tap to toggle elapsed/remaining)
                          GestureDetector(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(
                                () => _showRemainingTime = !_showRemainingTime,
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 4,
                              ),
                              child: Text(
                                '$timeText / ${fmt(_playbackDuration)}',
                                style: tt.labelSmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                  fontWeight: FontWeight.w500,
                                  fontFeatures: [
                                    const ui.FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ── Waveform-style seekable progress ──
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final trackWidth = constraints.maxWidth;
                          const barCount = 48;
                          final barW = ((trackWidth / barCount) - 1.5).clamp(
                            1.5,
                            5.0,
                          );

                          return GestureDetector(
                            onTapDown: (d) {
                              HapticFeedback.selectionClick();
                              _seekAudioPlayback(
                                (d.localPosition.dx / trackWidth).clamp(
                                  0.0,
                                  1.0,
                                ),
                              );
                            },
                            onHorizontalDragStart: (_) {
                              setState(() => _isScrubbing = true);
                            },
                            onHorizontalDragUpdate: (d) {
                              _seekAudioPlayback(
                                (d.localPosition.dx / trackWidth).clamp(
                                  0.0,
                                  1.0,
                                ),
                              );
                            },
                            onHorizontalDragEnd: (_) {
                              HapticFeedback.selectionClick();
                              setState(() => _isScrubbing = false);
                            },
                            behavior: HitTestBehavior.opaque,
                            child: SizedBox(
                              height: _isScrubbing ? 42 : 28,
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  // 💬 Time tooltip when scrubbing
                                  if (_isScrubbing)
                                    Positioned(
                                      left: (constraints.maxWidth * progress)
                                          .clamp(
                                            16.0,
                                            constraints.maxWidth - 40,
                                          ),
                                      top: 0,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: cs.primary,
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: cs.primary.withValues(
                                                alpha: 0.3,
                                              ),
                                              blurRadius: 8,
                                            ),
                                          ],
                                        ),
                                        child: Text(
                                          fmt(_playbackPosition),
                                          style: tt.labelSmall?.copyWith(
                                            color: cs.onPrimary,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ),
                                    ),
                                  // Waveform bars
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    bottom: 0,
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: List.generate(barCount, (i) {
                                        final frac = i / barCount;
                                        final isPast = frac < progress;
                                        final isActive =
                                            (frac - progress).abs() <
                                            (1.0 / barCount);
                                        // Deterministic pseudo-waveform + subtle pulse when playing
                                        final pulse =
                                            _isPlaybackPaused
                                                ? 0.0
                                                : 2.0 *
                                                    ((math.sin(
                                                              t * 5.0 + i * 0.8,
                                                            ) +
                                                            1) /
                                                        2);
                                        final h =
                                            4.0 +
                                            pulse +
                                            14.0 *
                                                ((math.sin(i * 0.7) * 0.5 +
                                                            0.5) *
                                                        0.5 +
                                                    (math.sin(i * 1.3 + 2.0) *
                                                                0.5 +
                                                            0.5) *
                                                        0.3 +
                                                    (math.sin(i * 2.1 + 4.0) *
                                                                0.5 +
                                                            0.5) *
                                                        0.2);

                                        return AnimatedContainer(
                                          duration: const Duration(
                                            milliseconds: 120,
                                          ),
                                          width: isActive ? barW + 1.0 : barW,
                                          height: isActive ? h + 4.0 : h,
                                          decoration: BoxDecoration(
                                            color:
                                                isPast || isActive
                                                    ? Color.lerp(
                                                      cs.primary,
                                                      cs.tertiary,
                                                      frac,
                                                    )
                                                    : cs.onSurface.withValues(
                                                      alpha: 0.12,
                                                    ),
                                            borderRadius: BorderRadius.circular(
                                              isActive ? 2.0 : 1.5,
                                            ),
                                            boxShadow:
                                                isActive
                                                    ? [
                                                      BoxShadow(
                                                        color: cs.primary
                                                            .withValues(
                                                              alpha: 0.5,
                                                            ),
                                                        blurRadius: 6,
                                                      ),
                                                    ]
                                                    : null,
                                          ),
                                        );
                                      }),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                    // ── Volume slider ──
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: _toggleMute,
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              transitionBuilder:
                                  (child, anim) => ScaleTransition(
                                    scale: anim,
                                    child: child,
                                  ),
                              child: Icon(
                                _playbackVolume == 0
                                    ? Icons.volume_off_rounded
                                    : _playbackVolume < 0.5
                                    ? Icons.volume_down_rounded
                                    : Icons.volume_up_rounded,
                                key: ValueKey(
                                  _playbackVolume == 0
                                      ? 'muted'
                                      : _playbackVolume < 0.5
                                      ? 'low'
                                      : 'high',
                                ),
                                size: 16,
                                color:
                                    _playbackVolume == 0
                                        ? cs.error
                                        : cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                          Expanded(
                            child: SliderTheme(
                              data: SliderThemeData(
                                trackHeight: 3,
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 6,
                                ),
                                overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 14,
                                ),
                                activeTrackColor:
                                    _playbackVolume == 0
                                        ? cs.error.withValues(alpha: 0.5)
                                        : cs.primary,
                                inactiveTrackColor: cs.onSurface.withValues(
                                  alpha: 0.12,
                                ),
                                thumbColor:
                                    _playbackVolume == 0
                                        ? cs.error
                                        : cs.primary,
                                overlayColor: cs.primary.withValues(
                                  alpha: 0.12,
                                ),
                              ),
                              child: Slider(
                                value: _playbackVolume,
                                onChanged: _setPlaybackVolume,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Mini-player skip button helper.
  Widget _buildMiniPlayerSkipBtn(
    IconData icon,
    VoidCallback onTap,
    ColorScheme cs,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: cs.onSurface, size: 22),
        ),
      ),
    );
  }

  // ─── Waveform Preview (#6) ────────────────────────────────────────────

  /// 📊 Compute a compact waveform preview (normalized amplitudes 0.0–1.0).
  ///
  /// Samples the raw audio bytes at evenly spaced intervals and normalizes
  /// each sample to produce a mini-waveform that can be transmitted in the
  /// broadcast payload for instant visualization without downloading the file.
  List<double> _computeWaveformPreview(
    Uint8List audioBytes, {
    int sampleCount = 48,
  }) {
    if (audioBytes.isEmpty || sampleCount <= 0) return [];

    // Skip the file header (first 44 bytes for WAV, or approximate for m4a)
    final headerOffset = audioBytes.length > 200 ? 200 : 0;
    final dataLength = audioBytes.length - headerOffset;
    if (dataLength <= 0) return List.filled(sampleCount, 0.5);

    final step = dataLength ~/ sampleCount;
    if (step <= 0) return List.filled(sampleCount, 0.5);

    final samples = <double>[];
    double maxAmplitude = 0;

    for (int i = 0; i < sampleCount; i++) {
      final offset = headerOffset + (i * step);
      if (offset >= audioBytes.length) break;

      // Sample amplitude: average of a window of bytes
      double sum = 0;
      int count = 0;
      for (int j = 0; j < step && (offset + j) < audioBytes.length; j += 4) {
        // Treat as unsigned byte centered at 128
        final value = (audioBytes[offset + j] - 128).abs().toDouble();
        sum += value;
        count++;
      }
      final avg = count > 0 ? sum / count : 0.0;
      samples.add(avg);
      if (avg > maxAmplitude) maxAmplitude = avg;
    }

    // Normalize to 0.0–1.0
    if (maxAmplitude > 0) {
      return samples.map((s) => (s / maxAmplitude).clamp(0.0, 1.0)).toList();
    }
    return samples.map((_) => 0.5).toList();
  }

  // ─── Badge UI (#1) ──────────────────────────────────────────────────

  /// 🔔 Build a badge icon for the recordings button showing the count of
  /// new recordings received from collaborators.
  Widget _buildRecordingsBadge(Widget child) {
    final count = CollaborationExtension._newRecordingCount;
    if (count <= 0) return child;

    return Badge.count(count: count, child: child);
  }

  /// 🔔 Reset the new recording badge counter (called when recordings dialog opens).
  void _resetRecordingsBadge() {
    CollaborationExtension._newRecordingCount = 0;
  }

  // ─── #2 Waveform Visualization Widget ─────────────────────────────────

  /// 📊 Build a compact waveform preview from amplitude data.
  /// Renders 48 vertical bars with heights proportional to amplitude.
  Widget _buildWaveformPreview(List<double> amplitudes, {double height = 32}) {
    if (amplitudes.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: height,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children:
            amplitudes.map((amp) {
              return Container(
                width: 2,
                height: (amp * height).clamp(2.0, height),
                margin: const EdgeInsets.symmetric(horizontal: 0.5),
                decoration: BoxDecoration(
                  color: Colors.blueAccent.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(1),
                ),
              );
            }).toList(),
      ),
    );
  }

  // ─── #4 Search / Filter ───────────────────────────────────────────────

  /// 🔍 Filter saved recordings by search query (name or path).
  List<String> _filterRecordings(String query) {
    if (query.isEmpty) return _savedRecordings;
    final lowerQuery = query.toLowerCase();
    return _savedRecordings.where((path) {
      final name = path.split('/').last.toLowerCase();
      // Also check synced recording noteTitle
      final synced = _syncedRecordings.where((r) => r.audioPath == path);
      if (synced.isNotEmpty) {
        final title = synced.first.noteTitle?.toLowerCase() ?? '';
        if (title.contains(lowerQuery)) return true;
      }
      return name.contains(lowerQuery);
    }).toList();
  }

  // ─── #5 Sorting ───────────────────────────────────────────────────────

  /// 📋 Sort recordings by the given criteria.
  List<String> _sortRecordings(
    List<String> recordings,
    RecordingSortOrder order,
  ) {
    final sorted = List<String>.from(recordings);
    switch (order) {
      case RecordingSortOrder.dateNewest:
        sorted.sort((a, b) {
          final aFile = File(a);
          final bFile = File(b);
          try {
            return bFile.lastModifiedSync().compareTo(aFile.lastModifiedSync());
          } catch (_) {
            return 0;
          }
        });
        break;
      case RecordingSortOrder.dateOldest:
        sorted.sort((a, b) {
          final aFile = File(a);
          final bFile = File(b);
          try {
            return aFile.lastModifiedSync().compareTo(bFile.lastModifiedSync());
          } catch (_) {
            return 0;
          }
        });
        break;
      case RecordingSortOrder.nameAZ:
        sorted.sort((a, b) => a.split('/').last.compareTo(b.split('/').last));
        break;
      case RecordingSortOrder.nameZA:
        sorted.sort((a, b) => b.split('/').last.compareTo(a.split('/').last));
        break;
      case RecordingSortOrder.durationLongest:
        sorted.sort((a, b) {
          final aSynced = _syncedRecordings.where((r) => r.audioPath == a);
          final bSynced = _syncedRecordings.where((r) => r.audioPath == b);
          final aDur =
              aSynced.isNotEmpty
                  ? aSynced.first.totalDuration.inMilliseconds
                  : 0;
          final bDur =
              bSynced.isNotEmpty
                  ? bSynced.first.totalDuration.inMilliseconds
                  : 0;
          return bDur.compareTo(aDur);
        });
        break;
    }
    return sorted;
  }

  // ─── #6 Auto-Cleanup ──────────────────────────────────────────────────

  /// 🧹 Remove recordings older than [maxAge] from local storage.
  Future<int> _cleanupOldRecordings({
    Duration maxAge = const Duration(days: 30),
  }) async {
    int removed = 0;
    final now = DateTime.now();
    final toRemove = <String>[];

    for (final path in _savedRecordings) {
      try {
        final file = File(path);
        if (await file.exists()) {
          final lastModified = await file.lastModified();
          if (now.difference(lastModified) > maxAge) {
            await file.delete();
            toRemove.add(path);
            removed++;
          }
        }
      } catch (e) {
      }
    }

    if (toRemove.isNotEmpty && mounted) {
      setState(() {
        _savedRecordings.removeWhere(toRemove.contains);
      });
    }

    return removed;
  }

  // ─── #7 Audio Quality Settings ────────────────────────────────────────

  /// 🎚️ Current audio quality setting.
  static AudioQualityPreset _audioQuality = AudioQualityPreset.standard;

  /// 🎚️ Get current audio quality.
  AudioQualityPreset get audioQuality => _audioQuality;

  /// 🎚️ Set audio quality for future recordings.
  void setAudioQuality(AudioQualityPreset quality) {
    _audioQuality = quality;
  }

  // ─── #9 Canvas-Anchored Recordings ────────────────────────────────────

  /// 📍 Anchor a recording to a specific canvas position.
  static final Map<String, Offset> _anchoredRecordings = {};

  /// 📍 Anchor a recording to the given canvas position.
  void anchorRecording(String recordingId, Offset canvasPosition) {
    _anchoredRecordings[recordingId] = canvasPosition;
  }

  /// 📍 Remove anchor from a recording.
  void unanchorRecording(String recordingId) {
    _anchoredRecordings.remove(recordingId);
  }

  /// 📍 Get all anchored recordings with their positions.
  Map<String, Offset> get anchoredRecordings =>
      Map.unmodifiable(_anchoredRecordings);

  // ─── #10 Batch Operations ─────────────────────────────────────────────

  /// 🗑️ Delete multiple recordings at once.
  Future<int> batchDeleteRecordings(List<String> paths) async {
    int deleted = 0;
    for (final path in paths) {
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
          deleted++;
        }
      } catch (e) {
      }
    }

    if (mounted) {
      setState(() {
        _savedRecordings.removeWhere(paths.contains);
        _syncedRecordings.removeWhere((r) => paths.contains(r.audioPath));
      });
    }

    return deleted;
  }

  /// ✏️ Rename multiple recordings at once.
  Future<int> batchRenameRecordings(Map<String, String> idToNewName) async {
    int renamed = 0;
    for (final entry in idToNewName.entries) {
      final idx = _syncedRecordings.indexWhere((r) => r.id == entry.key);
      if (idx != -1) {
        final old = _syncedRecordings[idx];
        _syncedRecordings[idx] = SynchronizedRecording(
          id: old.id,
          audioPath: old.audioPath,
          totalDuration: old.totalDuration,
          startTime: old.startTime,
          syncedStrokes: old.syncedStrokes,
          canvasId: old.canvasId,
          noteTitle: entry.value,
          recordingType: old.recordingType,
        );

        // Broadcast rename to collaborators
        _realtimeEngine?.broadcastRecordingRenamed(
          recordingId: entry.key,
          newTitle: entry.value,
        );
        renamed++;
      }
    }

    if (mounted) setState(() {});
    return renamed;
  }

  // ─── #11 Recording Bookmarks ──────────────────────────────────────────

  /// 🔖 Bookmarks per recording: recordingId → list of bookmark timestamps.
  static final Map<String, List<Duration>> _recordingBookmarks = {};

  /// 🔖 Add a bookmark at the current playback position.
  void addBookmark(String recordingId, Duration position) {
    _recordingBookmarks.putIfAbsent(recordingId, () => []);
    _recordingBookmarks[recordingId]!.add(position);
    _recordingBookmarks[recordingId]!.sort((a, b) => a.compareTo(b));
  }

  /// 🔖 Remove a bookmark.
  void removeBookmark(String recordingId, Duration position) {
    _recordingBookmarks[recordingId]?.remove(position);
  }

  /// 🔖 Get all bookmarks for a recording.
  List<Duration> getBookmarks(String recordingId) {
    return List.unmodifiable(_recordingBookmarks[recordingId] ?? []);
  }

  /// 🔖 Jump to next bookmark from current position.
  Duration? nextBookmark(String recordingId, Duration currentPosition) {
    final bookmarks = _recordingBookmarks[recordingId] ?? [];
    for (final bm in bookmarks) {
      if (bm > currentPosition) return bm;
    }
    return null;
  }

  /// 🔖 Jump to previous bookmark from current position.
  Duration? previousBookmark(String recordingId, Duration currentPosition) {
    final bookmarks = _recordingBookmarks[recordingId] ?? [];
    for (int i = bookmarks.length - 1; i >= 0; i--) {
      if (bookmarks[i] < currentPosition) return bookmarks[i];
    }
    return null;
  }

  // ─── #3 Live Waveform Widget ──────────────────────────────────────────

  /// 🎵 Build a live waveform visualization during recording.
  /// Shows a scrolling waveform of recent amplitudes with animated bars.
  /// 🎛️ Show recording quality settings bottom sheet.
  void _showRecordingQualitySettings() {
    try {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) {
          return StatefulBuilder(
            builder: (ctx, setSheetState) {
              final cs = Theme.of(ctx).colorScheme;
              final tt = Theme.of(ctx).textTheme;

              // Determine which preset is active
              String activePreset = 'custom';
              if (_recordingConfig.sampleRate == 44100 &&
                  _recordingConfig.bitRate == 128000) {
                activePreset = 'standard';
              } else if (_recordingConfig.sampleRate == 48000 &&
                  _recordingConfig.bitRate == 256000) {
                activePreset = 'high';
              } else if (_recordingConfig.sampleRate == 48000 &&
                  _recordingConfig.bitRate == 320000) {
                activePreset = 'studio';
              }

              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Handle bar
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Title
                    Text(
                      '🎛️ Recording Quality',
                      style: tt.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Preset chips
                    Row(
                      children: [
                        _qualityChip(
                          label: '📱 Standard',
                          subtitle: '44.1kHz · 128kbps',
                          infoText:
                              'Basic quality for smaller files.\nIncludes hardware noise suppression only.',
                          isSelected: activePreset == 'standard',
                          cs: cs,
                          tt: tt,
                          onTap: () {
                            setSheetState(() {
                              _recordingConfig = AudioRecordConfig.standard
                                  .copyWith(
                                    noiseSuppression:
                                        _recordingConfig.noiseSuppression,
                                    echoCancellation:
                                        _recordingConfig.echoCancellation,
                                    autoGain: _recordingConfig.autoGain,
                                  );
                            });
                          },
                        ),
                        const SizedBox(width: 8),
                        _qualityChip(
                          label: '🎵 High',
                          subtitle: '48kHz · 256kbps',
                          infoText:
                              'Recommended quality.\nRNNoise AI denoising, presence EQ,\ncompressor, and normalization.',
                          isSelected: activePreset == 'high',
                          cs: cs,
                          tt: tt,
                          onTap: () {
                            setSheetState(() {
                              _recordingConfig = AudioRecordConfig.high
                                  .copyWith(
                                    noiseSuppression:
                                        _recordingConfig.noiseSuppression,
                                    echoCancellation:
                                        _recordingConfig.echoCancellation,
                                    autoGain: _recordingConfig.autoGain,
                                  );
                            });
                          },
                        ),
                        const SizedBox(width: 8),
                        _qualityChip(
                          label: '🎤 Studio',
                          subtitle: '48kHz · 320kbps',
                          infoText:
                              'Maximum fidelity.\nRNNoise AI denoising, presence EQ,\ncompressor, normalization, 320kbps.',
                          isSelected: activePreset == 'studio',
                          cs: cs,
                          tt: tt,
                          onTap: () {
                            setSheetState(() {
                              _recordingConfig = AudioRecordConfig.studio
                                  .copyWith(
                                    noiseSuppression:
                                        _recordingConfig.noiseSuppression,
                                    echoCancellation:
                                        _recordingConfig.echoCancellation,
                                    autoGain: _recordingConfig.autoGain,
                                  );
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Audio processing toggles
                    Text(
                      'Audio Processing',
                      style: tt.labelLarge?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),

                    _settingsToggle(
                      icon: Icons.noise_aware,
                      title: 'Noise Suppression',
                      subtitle: 'Reduces pen/finger noise',
                      value: _recordingConfig.noiseSuppression,
                      cs: cs,
                      tt: tt,
                      onChanged: (v) {
                        setSheetState(() {
                          _recordingConfig = _recordingConfig.copyWith(
                            noiseSuppression: v,
                          );
                        });
                      },
                    ),
                    _settingsToggle(
                      icon: Icons.surround_sound,
                      title: 'Echo Cancellation',
                      subtitle: 'Removes speaker echo',
                      value: _recordingConfig.echoCancellation,
                      cs: cs,
                      tt: tt,
                      onChanged: (v) {
                        setSheetState(() {
                          _recordingConfig = _recordingConfig.copyWith(
                            echoCancellation: v,
                          );
                        });
                      },
                    ),
                    _settingsToggle(
                      icon: Icons.tune,
                      title: 'Auto Gain Control',
                      subtitle: 'Normalizes voice volume',
                      value: _recordingConfig.autoGain,
                      cs: cs,
                      tt: tt,
                      onChanged: (v) {
                        setSheetState(() {
                          _recordingConfig = _recordingConfig.copyWith(
                            autoGain: v,
                          );
                        });
                      },
                    ),
                    _settingsToggle(
                      icon: Icons.graphic_eq,
                      title: 'High-Pass Filter (100Hz)',
                      subtitle: 'Cuts low-frequency pen noise',
                      value: _recordingConfig.highPassFilterHz > 0,
                      cs: cs,
                      tt: tt,
                      onChanged: (v) {
                        setSheetState(() {
                          _recordingConfig = _recordingConfig.copyWith(
                            highPassFilterHz: v ? 250 : 0,
                          );
                        });
                      },
                    ),
                    _settingsToggle(
                      icon: Icons.compress,
                      title: 'Compressor',
                      subtitle: 'Evens out volume dynamics',
                      value: _recordingConfig.compressor,
                      cs: cs,
                      tt: tt,
                      onChanged: (v) {
                        setSheetState(() {
                          _recordingConfig = _recordingConfig.copyWith(
                            compressor: v,
                          );
                        });
                      },
                    ),
                    _settingsToggle(
                      icon: Icons.equalizer,
                      title: 'Normalization',
                      subtitle: 'Brings volume to standard level',
                      value: _recordingConfig.normalization,
                      cs: cs,
                      tt: tt,
                      onChanged: (v) {
                        setSheetState(() {
                          _recordingConfig = _recordingConfig.copyWith(
                            normalization: v,
                          );
                        });
                      },
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
    } catch (e) {
    }
  }

  /// Helper: quality preset chip.
  Widget _qualityChip({
    required String label,
    required String subtitle,
    required String infoText,
    required bool isSelected,
    required ColorScheme cs,
    required TextTheme tt,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color:
                isSelected ? cs.primaryContainer : cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? cs.primary : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Center(
                child: Column(
                  children: [
                    Text(
                      label,
                      style: tt.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color:
                            isSelected ? cs.onPrimaryContainer : cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: tt.labelSmall?.copyWith(
                        fontSize: 9,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: -6,
                right: -4,
                child: Tooltip(
                  message: infoText,
                  preferBelow: false,
                  textStyle: tt.bodySmall?.copyWith(
                    color: cs.onInverseSurface,
                    fontSize: 11,
                  ),
                  decoration: BoxDecoration(
                    color: cs.inverseSurface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: GestureDetector(
                    onTap:
                        () {}, // Absorb tap so it doesn't trigger chip selection
                    child: Icon(
                      Icons.info_outline,
                      size: 14,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Helper: settings toggle row.
  Widget _settingsToggle({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ColorScheme cs,
    required TextTheme tt,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: cs.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: tt.bodyMedium),
                Text(
                  subtitle,
                  style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Switch.adaptive(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _buildLiveWaveform({double height = 40, double barWidth = 3}) {
    // Safe snapshot — prevents concurrent modification RangeError
    final snapshot = List<double>.from(_liveAmplitudes);
    const displayBars = 32;

    // Downsample if we have more samples than bars
    final List<double> bars;
    if (snapshot.length <= displayBars) {
      bars = List.generate(displayBars, (i) {
        return i < snapshot.length ? snapshot[i] : 0.0;
      });
    } else {
      // Take the most recent samples and downsample
      final recent = snapshot.sublist(snapshot.length - displayBars);
      bars = recent;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 100),
      height: height,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(bars.length, (i) {
          final amp = bars[i].clamp(0.0, 1.0);
          return AnimatedContainer(
            duration: const Duration(milliseconds: 80),
            width: barWidth,
            height: (amp * height).clamp(2.0, height),
            margin: const EdgeInsets.symmetric(horizontal: 0.5),
            decoration: BoxDecoration(
              color: Color.lerp(
                Colors.redAccent.withValues(alpha: 0.5),
                Colors.redAccent,
                amp,
              ),
              borderRadius: BorderRadius.circular(barWidth / 2),
            ),
          );
        }),
      ),
    );
  }

  /// 🎵 Whether the live waveform has data to display.
  bool get hasLiveWaveformData => _liveAmplitudes.isNotEmpty;

  /// 🎵 Get a snapshot of the current live amplitudes (for external widgets).
  List<double> get liveAmplitudes => List.unmodifiable(_liveAmplitudes);

  // ─── #8 Offline-First Upload Queue ────────────────────────────────────

  /// 📡 Queue a recording for upload when connectivity returns.
  void _queueOfflineUpload({
    required String recordingId,
    required String audioPath,
    String? noteTitle,
    required int durationMs,
    String? recordingType,
  }) {
    _offlineUploadQueue.add({
      'recordingId': recordingId,
      'audioPath': audioPath,
      'noteTitle': noteTitle,
      'durationMs': durationMs,
      'recordingType': recordingType ?? 'audio_only',
      'queuedAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// 📡 Upload all queued recordings (call when connectivity returns).
  Future<int> _syncOfflineUploads() async {
    if (_offlineUploadQueue.isEmpty || _syncEngine == null) return 0;


    final queue = List<Map<String, dynamic>>.from(_offlineUploadQueue);
    _offlineUploadQueue.clear();
    int uploaded = 0;

    for (final item in queue) {
      try {
        final audioPath = item['audioPath'] as String;
        final recordingId = item['recordingId'] as String;
        final file = File(audioPath);

        if (!await file.exists()) {
          continue;
        }

        final audioBytes = await file.readAsBytes();

        // Compress on isolate
        final compressedData = await Isolate.run(() {
          return Uint8List.fromList(GZipCodec().encode(audioBytes));
        });

        // Upload audio
        await _syncEngine!.adapter.uploadAsset(
          _canvasId,
          'recording_$recordingId',
          compressedData,
          mimeType: 'audio/m4a+gzip',
        );

        // 🎨 Upload synced strokes from SQLite (if available)
        String? strokesAssetKey;
        int strokeCount = 0;
        if (RecordingStorageService.instance.isInitialized) {
          try {
            final recording = await RecordingStorageService.instance
                .loadRecordingById(recordingId);
            if (recording != null && recording.syncedStrokes.isNotEmpty) {
              final strokes = recording.syncedStrokes;
              strokeCount = strokes.length;
              final strokesJson = strokes.map((s) => s.toJson()).toList();
              final strokesBytes = await Isolate.run(() {
                final jsonStr = jsonEncode(strokesJson);
                return Uint8List.fromList(
                  GZipCodec().encode(utf8.encode(jsonStr)),
                );
              });
              strokesAssetKey = 'strokes_$recordingId';
              await _syncEngine!.adapter.uploadAsset(
                _canvasId,
                strokesAssetKey,
                strokesBytes,
                mimeType: 'application/json+gzip',
              );
            }
          } catch (e) {
          }
        }

        // Broadcast to collaborators
        final userName = await _config.getUserId();
        _realtimeEngine?.broadcastRecordingAdded(
          recordingId: recordingId,
          audioAssetKey: 'recording_$recordingId',
          noteTitle: item['noteTitle'] as String?,
          durationMs: item['durationMs'] as int,
          recordingType: item['recordingType'] as String?,
          senderName: userName,
          compressed: true,
          fileSize: audioBytes.length,
          strokesAssetKey: strokesAssetKey,
          strokeCount: strokeCount,
        );

        uploaded++;
      } catch (e) {
        // Re-queue for next sync attempt
        _offlineUploadQueue.add(item);
      }
    }

    return uploaded;
  }

  /// 📡 Number of recordings pending offline upload.
  int get pendingOfflineUploads => _offlineUploadQueue.length;

  /// 📡 Whether there are recordings waiting to be uploaded.
  bool get hasOfflineUploads => _offlineUploadQueue.isNotEmpty;
}

/// 📋 Sort order options for recordings list (#5).
enum RecordingSortOrder {
  dateNewest,
  dateOldest,
  nameAZ,
  nameZA,
  durationLongest,
}

/// 🎚️ Audio quality presets (#7).
enum AudioQualityPreset {
  /// Low quality — 64kbps, smaller files.
  low,

  /// Standard quality — 128kbps, balanced.
  standard,

  /// High quality — 256kbps, best fidelity.
  high,

  /// Lossless — maximum quality, largest files.
  lossless,
}

/// 📌 CustomPainter that renders recording pins on the canvas.
///
/// Each pin is drawn as a gradient circle with a mic icon at its center,
/// followed by a label and optional duration badge below.
class _RecordingPinPainter extends CustomPainter {
  final List<RecordingPin> pins;
  final InfiniteCanvasController controller;
  final Color primaryColor;
  final Color tertiaryColor;
  final Color secondaryColor;
  final Color onPrimaryColor;
  final Color surfaceColor;
  final Color onSurfaceColor;
  final bool isPinPlacementMode;
  final String? playingRecordingId;
  final String? draggingPinId;

  _RecordingPinPainter({
    required this.pins,
    required this.controller,
    required this.primaryColor,
    required this.tertiaryColor,
    required this.secondaryColor,
    required this.onPrimaryColor,
    required this.surfaceColor,
    required this.onSurfaceColor,
    this.isPinPlacementMode = false,
    this.playingRecordingId,
    this.draggingPinId,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final scale = controller.scale;
    final invScale = 1.0 / scale;

    // Paint in canvas space — compensate all pixel sizes by 1/scale
    // so they appear constant on screen regardless of zoom level.
    canvas.save();
    canvas.translate(controller.offset.dx, controller.offset.dy);
    canvas.scale(scale);

    for (final pin in pins) {
      // Pin position is already in canvas coordinates
      final center = pin.position;

      // Cull off-screen pins (convert to screen for comparison)
      final screenPos = controller.canvasToScreen(center);
      if (screenPos.dx < -60 ||
          screenPos.dx > size.width + 60 ||
          screenPos.dy < -60 ||
          screenPos.dy > size.height + 60) {
        continue;
      }

      final isDragging = draggingPinId != null && pin.id == draggingPinId;
      final radius = (isDragging ? 26.0 : 22.0) * invScale;
      final isPlaying =
          playingRecordingId != null && pin.recordingId == playingRecordingId;

      // Shadow (elevated when dragging)
      final shadowPaint =
          Paint()
            ..color = Colors.black.withValues(alpha: isDragging ? 0.35 : 0.2)
            ..maskFilter = MaskFilter.blur(
              BlurStyle.normal,
              (isDragging ? 10 : 6) * invScale,
            );
      canvas.drawCircle(
        center + Offset(0, (isDragging ? 4 : 2) * invScale),
        radius,
        shadowPaint,
      );

      // Gradient circle
      final gradientColors =
          pin.hasStrokes
              ? [primaryColor, tertiaryColor]
              : [secondaryColor, secondaryColor.withValues(alpha: 0.7)];
      final gradient = ui.Gradient.linear(
        center - Offset(radius, radius),
        center + Offset(radius, radius),
        gradientColors,
      );
      final circlePaint = Paint()..shader = gradient;
      canvas.drawCircle(center, radius, circlePaint);

      // Playing ring animation indicator
      if (isPlaying) {
        final ringPaint =
            Paint()
              ..color = onPrimaryColor.withValues(alpha: 0.6)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3 * invScale;
        canvas.drawCircle(center, radius + 4 * invScale, ringPaint);
      }

      // Mic icon (drawn as a simple glyph)
      final iconPainter = TextPainter(
        text: TextSpan(
          text: isPlaying ? '▶' : '🎤',
          style: TextStyle(fontSize: 16 * invScale, color: onPrimaryColor),
        ),
        textDirection: TextDirection.ltr,
      );
      iconPainter.layout();
      iconPainter.paint(
        canvas,
        center - Offset(iconPainter.width / 2, iconPainter.height / 2),
      );

      // Label below pin
      final labelPainter = TextPainter(
        text: TextSpan(
          text: pin.label,
          style: TextStyle(
            fontSize: 10 * invScale,
            fontWeight: FontWeight.w600,
            color: onSurfaceColor,
            backgroundColor: surfaceColor.withValues(alpha: 0.85),
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      );
      labelPainter.layout(maxWidth: 120 * invScale);
      labelPainter.paint(
        canvas,
        Offset(
          center.dx - labelPainter.width / 2,
          center.dy + radius + 6 * invScale,
        ),
      );

      // Duration badge
      if (pin.duration != null) {
        final mins = pin.duration!.inMinutes;
        final secs = pin.duration!.inSeconds % 60;
        final durText = '$mins:${secs.toString().padLeft(2, '0')}';
        final durPainter = TextPainter(
          text: TextSpan(
            text: durText,
            style: TextStyle(
              fontSize: 9 * invScale,
              color: onSurfaceColor.withValues(alpha: 0.6),
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        durPainter.layout();
        durPainter.paint(
          canvas,
          Offset(
            center.dx - durPainter.width / 2,
            center.dy + radius + 20 * invScale,
          ),
        );
      }
    }

    canvas.restore();

    // Pin placement mode indicator — painted in screen space (not canvas space)
    if (isPinPlacementMode) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: 'Tap to place pin',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: primaryColor,
            backgroundColor: surfaceColor.withValues(alpha: 0.9),
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset((size.width - textPainter.width) / 2, 20),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RecordingPinPainter oldDelegate) {
    return pins != oldDelegate.pins ||
        controller.offset != oldDelegate.controller.offset ||
        controller.scale != oldDelegate.controller.scale ||
        isPinPlacementMode != oldDelegate.isPinPlacementMode ||
        playingRecordingId != oldDelegate.playingRecordingId ||
        draggingPinId != oldDelegate.draggingPinId;
  }
}
