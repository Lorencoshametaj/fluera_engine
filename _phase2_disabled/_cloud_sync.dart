part of '../nebula_canvas_screen.dart';

/// 📦 Cloud Sync — extracted from _NebulaCanvasScreenState
extension on _NebulaCanvasScreenState {
  /// 💾 AUTO-SAVE canvas su disco (chiamato ad ogni modifica)
  Future<void> _autoSaveCanvas() async {
    // Non salvare se stiamo caricando
    if (_isLoading) return;

    try {
      // 🔧 FIX: Only snapshot deltas for shared canvases
      // Avoids unnecessary function call + print spam when sync is disabled
      if (_isSharedCanvas) {
        _snapshotAndPushCloudDeltas();
      }

      // 1️⃣ Salva SEMPRE in locale (backup immediato, no debounce!)
      await _localStorageService.saveCanvas(
        canvasId: _canvasId,
        layers: _layerController.layers,
        textElements: _digitalTextElements,
        imageElements: _imageElements,
        canvasBackgroundColor: _canvasBackgroundColor.toARGB32().toString(),
        paperType: _paperType,
        activeLayerId: _layerController.activeLayerId,
        title: _noteTitle,
        infiniteCanvasId: widget.infiniteCanvasId,
        nodeId: widget.nodeId,
        guides: _rulerGuideSystem.toJson(),
      );

      // 🔥 FULL FIREBASE SAVE: Write to shared Firestore path when canvas
      // is part of an infinite canvas. This populates the path that
      // loadFromFirebase reads from: documents/{infiniteCanvasId}/canvas_nodes/{nodeId}/...
      // Shorter debounce for shared canvases so other devices load data faster.
      // 💎 TIER GATE: Solo utenti Plus/Pro possono sincronizzare canvas sul cloud
      if (_hasCloudSync &&
          widget.infiniteCanvasId != null &&
          widget.nodeId != null) {
        final debounce =
            _isSharedCanvas
                ? const Duration(seconds: 2)
                : const Duration(seconds: 10);
        _firebaseSaveDebounceTimer?.cancel();
        _firebaseSaveDebounceTimer = Timer(debounce, () {
          _firebaseService.saveToFirebase(
            infiniteCanvasId: widget.infiniteCanvasId!,
            nodeId: widget.nodeId!,
            canvasId: _canvasId,
            layers: _layerController.layers,
            textElements: _digitalTextElements,
            imageElements: _imageElements,
            canvasBackgroundColor: _canvasBackgroundColor.toARGB32().toString(),
            paperType: _paperType,
            activeLayerId: _layerController.activeLayerId,
            title: _noteTitle,
            guides: _rulerGuideSystem.toJson(),
          );
        });
      }
    } catch (e) {
      {}
      // Non bloccare l'utente in caso di errore salvataggio
    }
  }

  /// 🔧 FIX: Snapshot deltas and push to RTDB BEFORE local save can consume them.
  ///
  /// The local save pipeline (saveCanvas → debounced _executeLocalSaveDelta
  /// → markCheckpointCompleted / removeDeltas) clears _pendingDeltas.
  /// We must capture and push deltas BEFORE that happens.
  void _snapshotAndPushCloudDeltas() {
    // Only push when shared OR auto-sync enabled
    if (!_isSharedCanvas) {
      print('📤 [CloudDeltaSync] SKIP: _isSharedCanvas=$_isSharedCanvas');
      return;
    }

    final user = null /* auth via _config */;
    if (user == null) return;

    // Snapshot deltas NOW, before local save can consume them
    final deltas = CanvasDeltaTracker.instance.peekDeltas();
    if (deltas.isEmpty) return;

    print('📤 [CloudDeltaSync] Pushing ${deltas.length} deltas to RTDB');

    // Tag each delta with userId + epoch for collaborative dedup
    final epoch = DateTime.now().millisecondsSinceEpoch;
    final taggedDeltas =
        deltas.map((d) {
          final json = d.toJson();
          json['userId'] = user.uid;
          json['epoch'] = epoch;
          return json;
        }).toList();

    // Push to RTDB via the service
    // 🔒 Element-scoped syncId prevents delta leaks between IC elements
    final syncId =
        (widget.infiniteCanvasId != null && widget.nodeId != null)
            ? '${widget.infiniteCanvasId}_${widget.nodeId}'
            : widget.infiniteCanvasId ?? _canvasId;
    _firebaseService.triggerDeltaSync(canvasId: syncId, deltas: taggedDeltas);
  }

  /// 🔄 Forza sincronizzazione - ora usa solo salvataggio locale
  /// Il sync cloud viene fatto manualmente dall'utente
  Future<void> forceFirebaseSync() async {
    try {
      {}

      // Salva solo localmente - il sync cloud è manuale
      await _localStorageService.saveCanvas(
        canvasId: _canvasId,
        layers: _layerController.layers,
        textElements: _digitalTextElements,
        imageElements: _imageElements,
        canvasBackgroundColor: _canvasBackgroundColor.toARGB32().toString(),
        paperType: _paperType,
        activeLayerId: _layerController.activeLayerId,
        title: _noteTitle,
        infiniteCanvasId: widget.infiniteCanvasId,
        nodeId: widget.nodeId,
        guides: _rulerGuideSystem.toJson(),
      );

      {}
    } catch (e) {
      {}
    }
  }
}
