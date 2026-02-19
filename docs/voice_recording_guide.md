# 🎤 Nebula Engine — Voice Recording Integration Guide

How to enable voice recording in your app using the Nebula Engine SDK.

---

## Zero Config (Works Out-of-the-Box)

The SDK includes a built-in native audio recorder. **No configuration needed** —
just open a canvas and press the mic button in the toolbar.

```dart
// That's it — recording works automatically
NebulaCanvasScreen(
  config: NebulaCanvasConfig(
    storageAdapter: myStorage,
    layerController: myLayerController,
  ),
)
```

---

## Host App Requirements

### iOS — Info.plist

Add microphone usage description to your app's `ios/Runner/Info.plist`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>This app needs microphone access to record voice notes on your canvas.</string>
```

> ⚠️ **Required.** iOS will crash at runtime if this key is missing when the
> user taps "Record".

### Android — Runtime Permission

The SDK declares `RECORD_AUDIO` in its manifest, but **Android requires runtime
permission requests at the Activity level**. The SDK handles this automatically
on most devices, but for best results ensure your app requests the permission:

```dart
// Using permission_handler package
import 'package:permission_handler/permission_handler.dart';

Future<void> ensureMicrophonePermission() async {
  final status = await Permission.microphone.request();
  if (status.isDenied) {
    // Show explanation to user
  }
}
```

Or handle it in your `AndroidManifest.xml` if targeting API 23+:

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
```

---

## Recording Format

Default configuration:

| Setting | Value |
|---------|-------|
| Format | M4A (AAC) |
| Sample Rate | 44,100 Hz |
| Bit Rate | 128 kbps |
| Channels | Mono |

Files are saved to the device's temporary directory. The SDK returns the file
path after recording stops — your app is responsible for moving files to
permanent storage if needed.

---

## Custom Voice Recording Provider (Optional)

If you need custom recording behavior (e.g., cloud upload, custom format,
third-party audio library), implement `NebulaVoiceRecordingProvider`:

```dart
import 'package:nebula_engine/nebula_engine.dart';

class MyRecordingProvider implements NebulaVoiceRecordingProvider {
  @override
  Future<void> startRecording() async {
    // Your custom recording logic
  }

  @override
  Future<String?> stopRecording() async {
    // Return the file path of the recording
    return '/path/to/saved/recording.m4a';
  }

  @override
  bool get isRecording => _myRecorder.isRecording;

  @override
  Stream<Duration> get recordingDuration => _myDurationStream;

  @override
  Future<void> playRecording(String path) async {
    // Play back a saved recording
  }

  @override
  Future<void> stopPlayback() async {
    // Stop playback
  }
}
```

Then pass it to the config:

```dart
NebulaCanvasScreen(
  config: NebulaCanvasConfig(
    storageAdapter: myStorage,
    layerController: myLayerController,
    voiceRecording: MyRecordingProvider(),  // ← custom provider
  ),
)
```

> ℹ️ When a custom provider is set, the SDK's built-in recorder is **not** used.

---

## Using the Recorder Directly (Advanced)

You can use the native recorder outside of the canvas toolbar:

```dart
import 'package:nebula_engine/nebula_engine.dart';

final recorder = NativeAudioRecorder();

// Check / request permission
final hasPermission = await recorder.checkPermission();
if (!hasPermission) {
  await recorder.requestPermission();
}

// Record
await recorder.start();

// Listen to duration updates
recorder.durationStream.listen((duration) {
  print('Recording: ${duration.inSeconds}s');
});

// Listen to amplitude (for waveform visualization)
recorder.amplitudeStream.listen((amplitude) {
  print('Level: ${amplitude.current}');
});

// Stop and get file path
final filePath = await recorder.stop();
print('Saved to: $filePath');

// Cleanup
await recorder.dispose();
```

### Available Controls

| Method | Description |
|--------|-------------|
| `start({config})` | Start recording with optional `AudioRecordConfig` |
| `stop()` | Stop and return file path |
| `pause()` | Pause recording (iOS 12+, Android 24+) |
| `resume()` | Resume after pause |
| `cancel()` | Stop and delete temp file |
| `checkPermission()` | Check if mic permission granted |
| `requestPermission()` | Request mic permission (iOS only, Android needs Activity) |

### Streams

| Stream | Type | Description |
|--------|------|-------------|
| `stateStream` | `AudioRecorderState` | idle, recording, paused, stopped, error |
| `durationStream` | `Duration` | Elapsed recording time (updated every 100ms) |
| `amplitudeStream` | `AudioAmplitude` | Current + peak amplitude (0.0 – 1.0) |

---

## Platform Support

| Platform | Recorder Engine | Pause/Resume | Notes |
|----------|----------------|-------------|-------|
| **iOS** | AVAudioRecorder | ✅ iOS 12+ | Requires `NSMicrophoneUsageDescription` |
| **Android** | MediaRecorder | ✅ API 24+ | Requires `RECORD_AUDIO` permission |
| **Web** | ❌ Not supported | — | Falls back gracefully (no crash) |
| **Desktop** | ❌ Not supported | — | Falls back gracefully (no crash) |
