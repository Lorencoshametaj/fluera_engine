part of '../nebula_canvas_screen.dart';

/// 📦 Voice Recording — generic SDK implementation.
///
/// Delegates all recording, playback, and cloud sync operations to
/// [NebulaVoiceRecordingProvider] provided via [NebulaCanvasConfig].
/// The SDK manages state (recording status, duration, playback) while
/// the host app handles actual audio capture, storage, and cloud sync.
extension VoiceRecordingExtension on _NebulaCanvasScreenState {
  /// 🎤 Show dialog for choosing recording type.
  ///
  /// Delegates to [_config.voiceRecording] if available.
  Future<void> _showRecordingChoiceDialog() async {
    final provider = _config.voiceRecording;
    if (provider == null) {
      debugPrint('[VoiceRecording] No voice recording provider configured');
      return;
    }

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
    final provider = _config.voiceRecording;
    if (provider == null) return;

    try {
      HapticFeedback.mediumImpact();

      await provider.startRecording();

      _recordingStartTime = DateTime.now();

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
    final provider = _config.voiceRecording;
    if (provider == null) return;

    try {
      HapticFeedback.mediumImpact();

      _recordingDurationSubscription?.cancel();
      _recordingDurationSubscription = null;

      final audioPath = await provider.stopRecording();

      final recordedDuration = _recordingDuration;

      setState(() {
        _isRecordingAudio = false;
        _recordingDuration = Duration.zero;
      });

      if (audioPath != null && mounted) {
        // Show save dialog
        final result = await _showSaveRecordingDialog(
          audioPath,
          recordedDuration,
        );
        if (result == true) {
          setState(() {
            _savedRecordings.add(audioPath);
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ Recording saved'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('[VoiceRecording] Stop failed: $e');
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
  Future<bool> _showSaveRecordingDialog(
    String audioPath,
    Duration duration,
  ) async {
    final nameController = TextEditingController(
      text:
          'Recording ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}',
    );

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
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
                Text(
                  _recordingWithStrokes
                      ? 'Audio synced with strokes'
                      : 'Audio only',
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
                onPressed: () => Navigator.pop(context, {'action': 'delete'}),
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
    );

    if (result != null && result['action'] == 'save') {
      return true;
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Recording discarded'),
            duration: Duration(seconds: 1),
          ),
        );
      }
      return false;
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

    final provider = _config.voiceRecording;

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
                  final fileName = path.split('/').last;
                  return ListTile(
                    leading: const Icon(Icons.audiotrack),
                    title: Text(
                      fileName,
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
                            provider?.playRecording(path);
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () {
                            setState(() {
                              _savedRecordings.removeAt(index);
                            });
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
    final provider = _config.voiceRecording;
    provider?.stopPlayback();
    setState(() {
      _isPlayingSyncedRecording = false;
    });
  }

  /// 🔍 Navigate to the current drawing position during playback.
  void _navigateToCurrentDrawing() {
    // Navigate viewport to the position where drawing is happening
    // during synced playback. This is a no-op if not in playback mode.
    debugPrint('[VoiceRecording] Navigate to current drawing position');
  }
}
