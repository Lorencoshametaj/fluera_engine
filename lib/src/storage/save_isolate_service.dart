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
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;

import '../core/models/canvas_layer.dart';
import '../core/models/digital_text_element.dart';
import '../core/nodes/text_node.dart';
import '../core/nodes/pdf_document_node.dart';
import '../core/nodes/pdf_page_node.dart';
import '../core/nodes/pdf_preview_card_node.dart';
import '../core/scene_graph/canvas_node.dart';
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
  /// On web, this is a no-op (isolates are not available).
  Future<void> initialize() async {
    if (kIsWeb) return; // Isolates not available on web
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
      // If spawn fails (e.g., web platform), fall back to synchronous encoding
    } finally {
      _isInitializing = false;
    }
  }

  /// Encode layers to binary BLOBs using the persistent isolate.
  ///
  /// Returns one [Uint8List] per layer. If the persistent isolate isn't ready,
  /// falls back to synchronous encoding on the main thread.
  Future<List<Uint8List>> encodeLayers(List<CanvasLayer> layers) async {
    if (_sendPort == null) {
      // Fallback: synchronous encoding (web or uninitialized isolate)
      final blobs = <Uint8List>[];
      for (final layer in layers) {
        blobs.add(BinaryCanvasFormat.encode([layer]));
      }
      return blobs;
    }

    // 📄 Strip unsendable objects from PDF nodes before isolate send:
    // ui.Image (GPU-backed) and onMutation closures (reference
    // _FlueraCanvasScreenState). We null them temporarily and restore after.
    final strippedImages = _stripPdfCachedImages(layers);
    final strippedThumbnails = _stripPdfPreviewCardThumbnails(layers);
    final strippedCallbacks = _stripPdfCallbacks(layers);
    // 📝 Strip unsendable TextPainter caches from text nodes
    _stripTextLayoutCaches(layers);
    // 🔗 Strip parent references to prevent the SceneGraph root from
    // dragging the entire node tree (with potentially re-cached TextPainters
    // in sibling layers) into the isolate message.
    final strippedParents = _stripParentReferences(layers);

    // Send layers to the persistent isolate and wait for response
    final responsePort = ReceivePort();
    _sendPort!.send(_EncodeRequest(layers, responsePort.sendPort));

    final result = await responsePort.first;
    responsePort.close();

    // Restore stripped fields after send
    _restorePdfCachedImages(strippedImages, layers);
    _restorePdfPreviewCardThumbnails(strippedThumbnails, layers);
    _restorePdfCallbacks(strippedCallbacks, layers);
    _restoreParentReferences(strippedParents, layers);
    // Note: text caches are NOT restored — they rebuild lazily on next paint

    return result as List<Uint8List>;
  }

  /// Shut down the persistent isolate.
  void dispose() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _sendPort = null;
  }

  // ---------------------------------------------------------------------------
  // PDF cached image stripping (isolate safety)
  // ---------------------------------------------------------------------------

  /// Temporarily null out all `PdfPageNode.cachedImage` fields so the layer
  /// tree can safely cross the isolate boundary.
  ///
  /// Returns a map of node IDs → stripped images so they can be restored
  /// after the send completes.
  static Map<String, ui.Image> _stripPdfCachedImages(List<CanvasLayer> layers) {
    final stripped = <String, ui.Image>{};

    for (final layer in layers) {
      for (final child in layer.node.children) {
        if (child is PdfDocumentNode) {
          for (final page in child.pageNodes) {
            if (page.cachedImage != null) {
              stripped[page.id] = page.cachedImage!;
              page.cachedImage = null;
            }
          }
        }
      }
    }

    return stripped;
  }

  /// Restore previously stripped cached images by walking the tree again
  /// and matching node IDs. Avoids flicker — pages keep their render cache.
  static void _restorePdfCachedImages(
    Map<String, ui.Image> stripped,
    List<CanvasLayer> layers,
  ) {
    if (stripped.isEmpty) return;

    for (final layer in layers) {
      for (final child in layer.node.children) {
        if (child is PdfDocumentNode) {
          for (final page in child.pageNodes) {
            final img = stripped[page.id];
            if (img != null && page.cachedImage == null) {
              page.cachedImage = img;
            }
          }
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // PdfPreviewCardNode thumbnail stripping (isolate safety)
  // ---------------------------------------------------------------------------

  /// Temporarily null out all `PdfPreviewCardNode.thumbnailImage` fields so the
  /// layer tree can safely cross the isolate boundary.
  static Map<String, ui.Image> _stripPdfPreviewCardThumbnails(
    List<CanvasLayer> layers,
  ) {
    final stripped = <String, ui.Image>{};

    for (final layer in layers) {
      for (final child in layer.node.children) {
        if (child is PdfPreviewCardNode && child.thumbnailImage != null) {
          stripped[child.id] = child.thumbnailImage!;
          child.thumbnailImage = null;
        }
      }
    }

    return stripped;
  }

  /// Restore previously stripped PdfPreviewCardNode thumbnails.
  static void _restorePdfPreviewCardThumbnails(
    Map<String, ui.Image> stripped,
    List<CanvasLayer> layers,
  ) {
    if (stripped.isEmpty) return;

    for (final layer in layers) {
      for (final child in layer.node.children) {
        if (child is PdfPreviewCardNode) {
          final img = stripped[child.id];
          if (img != null && child.thumbnailImage == null) {
            child.thumbnailImage = img;
          }
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // PDF callback stripping (isolate safety)
  // ---------------------------------------------------------------------------

  /// Temporarily null out all `PdfDocumentNode.onMutation` closures so the
  /// layer tree can safely cross the isolate boundary.
  static Map<String, void Function(String, Map<String, dynamic>)?>
  _stripPdfCallbacks(List<CanvasLayer> layers) {
    final stripped = <String, void Function(String, Map<String, dynamic>)?>{};

    for (final layer in layers) {
      for (final child in layer.node.children) {
        if (child is PdfDocumentNode && child.onMutation != null) {
          stripped[child.id] = child.onMutation;
          child.onMutation = null;
        }
      }
    }

    return stripped;
  }

  /// Restore previously stripped onMutation callbacks.
  static void _restorePdfCallbacks(
    Map<String, void Function(String, Map<String, dynamic>)?> stripped,
    List<CanvasLayer> layers,
  ) {
    if (stripped.isEmpty) return;

    for (final layer in layers) {
      for (final child in layer.node.children) {
        if (child is PdfDocumentNode) {
          final cb = stripped[child.id];
          if (cb != null && child.onMutation == null) {
            child.onMutation = cb;
          }
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Text layout cache stripping (isolate safety)
  // ---------------------------------------------------------------------------

  /// Clear cached TextPainter from all DigitalTextElements in the tree.
  /// TextPainter contains native _Paragraph objects that cannot cross
  /// isolate boundaries. The cache rebuilds lazily on next paint.
  ///
  /// Uses [allDescendants] to recursively find TextNodes inside GroupNodes.
  static void _stripTextLayoutCaches(List<CanvasLayer> layers) {
    for (final layer in layers) {
      for (final node in layer.node.allDescendants) {
        if (node is TextNode) {
          node.textElement.clearLayoutCache();
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Parent reference stripping (isolate safety)
  // ---------------------------------------------------------------------------

  /// Temporarily null out LayerNode.parent to prevent the SceneGraph root
  /// from being dragged into the isolate message.
  ///
  /// The SceneGraph root holds ALL layers, and sibling layers may contain
  /// TextNodes whose _cachedPainter has been rebuilt by a concurrent paint
  /// frame between the strip and the send. Detaching parent prevents
  /// the entire graph reachability.
  static Map<String, CanvasNode?> _stripParentReferences(
    List<CanvasLayer> layers,
  ) {
    final stripped = <String, CanvasNode?>{};
    for (final layer in layers) {
      stripped[layer.id] = layer.node.parent;
      layer.node.parent = null;
    }
    return stripped;
  }

  /// Restore previously stripped parent references.
  static void _restoreParentReferences(
    Map<String, CanvasNode?> stripped,
    List<CanvasLayer> layers,
  ) {
    if (stripped.isEmpty) return;
    for (final layer in layers) {
      final parent = stripped[layer.id];
      if (parent != null && layer.node.parent == null) {
        layer.node.parent = parent;
      }
    }
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
