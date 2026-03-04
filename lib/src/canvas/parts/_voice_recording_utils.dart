part of '../fluera_canvas_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// 🎤 Voice Recording — Utilities, Settings & Helper Classes
// ═══════════════════════════════════════════════════════════════════════════


extension _VoiceRecordingUtils on _FlueraCanvasScreenState {
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
              if (VoiceRecordingExtension._recordingConfig.sampleRate == 44100 &&
                  VoiceRecordingExtension._recordingConfig.bitRate == 128000) {
                activePreset = 'standard';
              } else if (VoiceRecordingExtension._recordingConfig.sampleRate == 48000 &&
                  VoiceRecordingExtension._recordingConfig.bitRate == 256000) {
                activePreset = 'high';
              } else if (VoiceRecordingExtension._recordingConfig.sampleRate == 48000 &&
                  VoiceRecordingExtension._recordingConfig.bitRate == 320000) {
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
                              VoiceRecordingExtension._recordingConfig = AudioRecordConfig.standard
                                  .copyWith(
                                    noiseSuppression:
                                        VoiceRecordingExtension._recordingConfig.noiseSuppression,
                                    echoCancellation:
                                        VoiceRecordingExtension._recordingConfig.echoCancellation,
                                    autoGain: VoiceRecordingExtension._recordingConfig.autoGain,
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
                              VoiceRecordingExtension._recordingConfig = AudioRecordConfig.high
                                  .copyWith(
                                    noiseSuppression:
                                        VoiceRecordingExtension._recordingConfig.noiseSuppression,
                                    echoCancellation:
                                        VoiceRecordingExtension._recordingConfig.echoCancellation,
                                    autoGain: VoiceRecordingExtension._recordingConfig.autoGain,
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
                              VoiceRecordingExtension._recordingConfig = AudioRecordConfig.studio
                                  .copyWith(
                                    noiseSuppression:
                                        VoiceRecordingExtension._recordingConfig.noiseSuppression,
                                    echoCancellation:
                                        VoiceRecordingExtension._recordingConfig.echoCancellation,
                                    autoGain: VoiceRecordingExtension._recordingConfig.autoGain,
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
                      value: VoiceRecordingExtension._recordingConfig.noiseSuppression,
                      cs: cs,
                      tt: tt,
                      onChanged: (v) {
                        setSheetState(() {
                          VoiceRecordingExtension._recordingConfig = VoiceRecordingExtension._recordingConfig.copyWith(
                            noiseSuppression: v,
                          );
                        });
                      },
                    ),
                    _settingsToggle(
                      icon: Icons.surround_sound,
                      title: 'Echo Cancellation',
                      subtitle: 'Removes speaker echo',
                      value: VoiceRecordingExtension._recordingConfig.echoCancellation,
                      cs: cs,
                      tt: tt,
                      onChanged: (v) {
                        setSheetState(() {
                          VoiceRecordingExtension._recordingConfig = VoiceRecordingExtension._recordingConfig.copyWith(
                            echoCancellation: v,
                          );
                        });
                      },
                    ),
                    _settingsToggle(
                      icon: Icons.tune,
                      title: 'Auto Gain Control',
                      subtitle: 'Normalizes voice volume',
                      value: VoiceRecordingExtension._recordingConfig.autoGain,
                      cs: cs,
                      tt: tt,
                      onChanged: (v) {
                        setSheetState(() {
                          VoiceRecordingExtension._recordingConfig = VoiceRecordingExtension._recordingConfig.copyWith(
                            autoGain: v,
                          );
                        });
                      },
                    ),
                    _settingsToggle(
                      icon: Icons.graphic_eq,
                      title: 'High-Pass Filter (100Hz)',
                      subtitle: 'Cuts low-frequency pen noise',
                      value: VoiceRecordingExtension._recordingConfig.highPassFilterHz > 0,
                      cs: cs,
                      tt: tt,
                      onChanged: (v) {
                        setSheetState(() {
                          VoiceRecordingExtension._recordingConfig = VoiceRecordingExtension._recordingConfig.copyWith(
                            highPassFilterHz: v ? 250 : 0,
                          );
                        });
                      },
                    ),
                    _settingsToggle(
                      icon: Icons.compress,
                      title: 'Compressor',
                      subtitle: 'Evens out volume dynamics',
                      value: VoiceRecordingExtension._recordingConfig.compressor,
                      cs: cs,
                      tt: tt,
                      onChanged: (v) {
                        setSheetState(() {
                          VoiceRecordingExtension._recordingConfig = VoiceRecordingExtension._recordingConfig.copyWith(
                            compressor: v,
                          );
                        });
                      },
                    ),
                    _settingsToggle(
                      icon: Icons.equalizer,
                      title: 'Normalization',
                      subtitle: 'Brings volume to standard level',
                      value: VoiceRecordingExtension._recordingConfig.normalization,
                      cs: cs,
                      tt: tt,
                      onChanged: (v) {
                        setSheetState(() {
                          VoiceRecordingExtension._recordingConfig = VoiceRecordingExtension._recordingConfig.copyWith(
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
    final snapshot = List<double>.from(VoiceRecordingExtension._liveAmplitudes);
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
  bool get hasLiveWaveformData => VoiceRecordingExtension._liveAmplitudes.isNotEmpty;

  /// 🎵 Get a snapshot of the current live amplitudes (for external widgets).
  List<double> get liveAmplitudes => List.unmodifiable(VoiceRecordingExtension._liveAmplitudes);

  // ─── #8 Offline-First Upload Queue ────────────────────────────────────

  /// 📡 Queue a recording for upload when connectivity returns.
  void _queueOfflineUpload({
    required String recordingId,
    required String audioPath,
    String? noteTitle,
    required int durationMs,
    String? recordingType,
  }) {
    VoiceRecordingExtension._offlineUploadQueue.add({
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
    if (VoiceRecordingExtension._offlineUploadQueue.isEmpty || _syncEngine == null) return 0;


    final queue = List<Map<String, dynamic>>.from(VoiceRecordingExtension._offlineUploadQueue);
    VoiceRecordingExtension._offlineUploadQueue.clear();
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
        VoiceRecordingExtension._offlineUploadQueue.add(item);
      }
    }

    return uploaded;
  }

  /// 📡 Number of recordings pending offline upload.
  int get pendingOfflineUploads => VoiceRecordingExtension._offlineUploadQueue.length;

  /// 📡 Whether there are recordings waiting to be uploaded.
  bool get hasOfflineUploads => VoiceRecordingExtension._offlineUploadQueue.isNotEmpty;
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
