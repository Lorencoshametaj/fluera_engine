// ============================================================================
// 🚀 SAVE ISOLATE SERVICE — Persistent background isolate for binary encoding
//
// Eliminates the ~2-5ms overhead of spawning a new Isolate for each save.
// A long-lived isolate is kept warm and reused via SendPort/ReceivePort
// message passing.
//
// USAGE:
//   await SaveIsolateService.instance.initialize();
//   final blobs = await SaveIsolateService.instance.encodeLayers(layers);
//   SaveIsolateService.instance.dispose();
//
// FALLBACK:
//   If the isolate hasn't been initialized (or has been disposed), the service
//   falls back to Isolate.run() — same behavior as before, just with spawn cost.
// ============================================================================

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import '../core/models/canvas_layer.dart';
import '../export/binary_canvas_format.dart';

/// Singleton service managing a long-lived background isolate for binary encoding.
class SaveIsolateService {
  SaveIsolateService._();
  static final SaveIsolateService instance = SaveIsolateService._();

  Isolate? _isolate;
  SendPort? _sendPort;
  bool _isInitializing = false;

  /// Whether the persistent isolate is running and ready to accept work.
  bool get isReady => _sendPort != null;

  /// Initialize the persistent isolate. Safe to call multiple times — no-op
  /// if already initialized or currently initializing.
  Future<void> initialize() async {
    if (_sendPort != null || _isInitializing) return;
    _isInitializing = true;

    try {
      final receivePort = ReceivePort();
      _isolate = await Isolate.spawn(_isolateEntryPoint, receivePort.sendPort);

      // The first message from the isolate is its own SendPort for requests
      final completer = Completer<SendPort>();
      receivePort.listen((message) {
        if (message is SendPort) {
          completer.complete(message);
        }
      });

      _sendPort = await completer.future;
      receivePort.close();
    } catch (_) {
      // If spawn fails (e.g., web platform), fall back to Isolate.run
    } finally {
      _isInitializing = false;
    }
  }

  /// Encode layers to binary BLOBs using the persistent isolate.
  ///
  /// Returns one [Uint8List] per layer. If the persistent isolate isn't ready,
  /// falls back to [Isolate.run] (same result, just with spawn overhead).
  Future<List<Uint8List>> encodeLayers(List<CanvasLayer> layers) async {
    if (_sendPort == null) {
      // Fallback: no persistent isolate, use one-shot
      return Isolate.run(() {
        final blobs = <Uint8List>[];
        for (final layer in layers) {
          blobs.add(BinaryCanvasFormat.encode([layer]));
        }
        return blobs;
      });
    }

    // Send layers to the persistent isolate and wait for response
    final responsePort = ReceivePort();
    _sendPort!.send(_EncodeRequest(layers, responsePort.sendPort));

    final result = await responsePort.first;
    responsePort.close();

    return result as List<Uint8List>;
  }

  /// Shut down the persistent isolate.
  void dispose() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _sendPort = null;
  }
}

/// Message sent to the persistent isolate to request encoding.
class _EncodeRequest {
  final List<CanvasLayer> layers;
  final SendPort responsePort;

  _EncodeRequest(this.layers, this.responsePort);
}

/// Entry point for the persistent background isolate.
///
/// Listens for [_EncodeRequest] messages, encodes each layer to binary,
/// and sends back the list of blobs via the request's responsePort.
void _isolateEntryPoint(SendPort mainSendPort) {
  final receivePort = ReceivePort();
  // Send our SendPort back to the main isolate so it can send us requests
  mainSendPort.send(receivePort.sendPort);

  receivePort.listen((message) {
    if (message is _EncodeRequest) {
      final blobs = <Uint8List>[];
      for (final layer in message.layers) {
        blobs.add(BinaryCanvasFormat.encode([layer]));
      }
      message.responsePort.send(blobs);
    }
  });
}
