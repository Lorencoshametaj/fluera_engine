part of '../nebula_canvas_screen.dart';

/// 📦 Collaboration & Sync — generic SDK implementation.
///
/// Checks permissions and presence via [NebulaCanvasConfig] providers.
/// Initializes the [NebulaRealtimeEngine] when a [NebulaRealtimeAdapter]
/// is provided, connecting remote events to canvas state and feeding
/// the cursor overlay.
extension CollaborationExtension on _NebulaCanvasScreenState {
  /// 🔄 Initialize collaboration features (permissions + presence + realtime).
  ///
  /// Checks if canvas is shared and sets viewer mode accordingly.
  /// Uses `_config.permissions` to check access, `_config.presence` for
  /// user presence, and `_config.realtimeAdapter` for live collaboration.
  Future<void> _initRealtimeCollaboration() async {
    final userId = await _config.getUserId();
    if (userId == null) return;

    try {
      // Check permissions via config provider
      if (_config.permissions != null) {
        final permissionCheckId = widget.infiniteCanvasId ?? _canvasId;
        final canEdit = await _config.permissions!.canEdit(permissionCheckId);

        if (mounted) {
          setState(() {
            _isSharedCanvas =
                true; // If permissions provider is set, canvas is shared
            _isViewerMode = !canEdit;
          });
        }
      }

      // Start presence tracking if configured
      if (_isSharedCanvas && _config.presence != null) {
        final permissionCheckId = widget.infiniteCanvasId ?? _canvasId;
        _config.presence!.joinCanvas(permissionCheckId);
      }

      // 🔴 Initialize real-time engine if adapter is available
      if (_hasRealtimeCollab && _config.realtimeAdapter != null) {
        _realtimeEngine = NebulaRealtimeEngine(
          adapter: _config.realtimeAdapter!,
          localUserId: userId,
          conflictResolver: ConflictResolver(
            onUnresolved: (conflict) {
              // Show conflict resolution dialog when auto-resolve fails
              if (mounted) {
                showConflictDialog(
                  context,
                  conflict,
                  resolver: _realtimeEngine?.conflictResolver,
                );
              }
            },
          ),
        );

        // Subscribe to incoming events
        _realtimeEventSub = _realtimeEngine!.incomingEvents.listen(
          _onRemoteRealtimeEvent,
        );

        // Connect cursor stream → CanvasPresenceOverlay ValueNotifier
        _realtimeEngine!.remoteCursors.addListener(_onRemoteCursorsChanged);

        // Connect to canvas channel
        await _realtimeEngine!.connect(_canvasId);

        debugPrint('🔴 Real-time collaboration initialized');
      }
    } catch (e) {
      // Non-blocking: collaboration features are optional
      debugPrint('[Collaboration] Init failed: $e');
    }
  }

  // ─── Remote Event Dispatch ─────────────────────────────────────────

  /// Handle incoming real-time events from other collaborators.
  void _onRemoteRealtimeEvent(CanvasRealtimeEvent event) {
    if (!mounted) return;

    switch (event.type) {
      case RealtimeEventType.strokeAdded:
        _applyRemoteStroke(event.payload);
        // 🎨 Clear live stroke preview now that the final stroke arrived
        final strokeId = event.payload['id'] as String?;
        if (strokeId != null) _clearRemoteLiveStroke(strokeId);
        break;

      case RealtimeEventType.strokeRemoved:
        _applyRemoteStrokeRemoval(event.payload);
        break;

      case RealtimeEventType.imageAdded:
      case RealtimeEventType.imageUpdated:
        _applyRemoteImageUpdate(event.payload);
        break;

      case RealtimeEventType.imageRemoved:
        _applyRemoteImageRemoval(event.payload);
        break;

      case RealtimeEventType.textChanged:
        _applyRemoteTextChange(event.payload);
        break;

      case RealtimeEventType.textRemoved:
        _applyRemoteTextRemoval(event.payload);
        break;

      case RealtimeEventType.layerChanged:
        _applyRemoteLayerChange(event.payload);
        break;

      case RealtimeEventType.canvasSettingsChanged:
        _applyRemoteSettingsChange(event.payload);
        break;

      case RealtimeEventType.elementLocked:
      case RealtimeEventType.elementUnlocked:
        // Handled internally by NebulaRealtimeEngine (lock table)
        break;

      case RealtimeEventType.strokePointsStreamed:
        _applyRemoteLiveStroke(event.payload);
        break;
    }
  }

  // ─── Remote Event Handlers ─────────────────────────────────────────

  void _applyRemoteStroke(Map<String, dynamic> payload) {
    try {
      final stroke = ProStroke.fromJson(payload);
      // Disable delta tracking during remote apply to avoid re-broadcasting
      final wasTracking = _layerController.enableDeltaTracking;
      _layerController.enableDeltaTracking = false;
      _layerController.addStroke(stroke);
      _layerController.enableDeltaTracking = wasTracking;
      setState(() {});
    } catch (e) {
      debugPrint('[RT] Failed to apply remote stroke: $e');
    }
  }

  void _applyRemoteStrokeRemoval(Map<String, dynamic> payload) {
    try {
      final strokeId = payload['strokeId'] as String?;
      if (strokeId == null) return;
      final wasTracking = _layerController.enableDeltaTracking;
      _layerController.enableDeltaTracking = false;
      _layerController.removeStroke(strokeId);
      _layerController.enableDeltaTracking = wasTracking;
      setState(() {});
    } catch (e) {
      debugPrint('[RT] Failed to apply remote stroke removal: $e');
    }
  }

  void _applyRemoteImageUpdate(Map<String, dynamic> payload) {
    try {
      final image = ImageElement.fromJson(payload);
      final wasTracking = _layerController.enableDeltaTracking;
      _layerController.enableDeltaTracking = false;
      _layerController.addImage(image);
      _layerController.enableDeltaTracking = wasTracking;
      // Also update local _imageElements
      final idx = _imageElements.indexWhere((e) => e.id == image.id);
      if (idx != -1) {
        _imageElements[idx] = image;
      } else {
        _imageElements.add(image);
      }
      _imageVersion++;
      _rebuildImageSpatialIndex();
      _preloadImage(
        image.imagePath,
        storageUrl: image.storageUrl,
        thumbnailUrl: image.thumbnailUrl,
      );
      setState(() {});
    } catch (e) {
      debugPrint('[RT] Failed to apply remote image update: $e');
    }
  }

  void _applyRemoteImageRemoval(Map<String, dynamic> payload) {
    try {
      final imageId = payload['id'] as String?;
      if (imageId == null) return;
      _imageElements.removeWhere((e) => e.id == imageId);
      _imageVersion++;
      _rebuildImageSpatialIndex();
      setState(() {});
    } catch (e) {
      debugPrint('[RT] Failed to apply remote image removal: $e');
    }
  }

  void _applyRemoteTextChange(Map<String, dynamic> payload) {
    try {
      final text = DigitalTextElement.fromJson(payload);
      final idx = _digitalTextElements.indexWhere((e) => e.id == text.id);
      setState(() {
        if (idx != -1) {
          _digitalTextElements[idx] = text;
        } else {
          _digitalTextElements.add(text);
        }
      });
      final wasTracking = _layerController.enableDeltaTracking;
      _layerController.enableDeltaTracking = false;
      _layerController.updateText(text);
      _layerController.enableDeltaTracking = wasTracking;
    } catch (e) {
      debugPrint('[RT] Failed to apply remote text change: $e');
    }
  }

  void _applyRemoteTextRemoval(Map<String, dynamic> payload) {
    try {
      final textId = payload['id'] as String?;
      if (textId == null) return;
      setState(() {
        _digitalTextElements.removeWhere((e) => e.id == textId);
      });
    } catch (e) {
      debugPrint('[RT] Failed to apply remote text removal: $e');
    }
  }

  void _applyRemoteLayerChange(Map<String, dynamic> payload) {
    try {
      final layer = CanvasLayer.fromJson(payload);
      final wasTracking = _layerController.enableDeltaTracking;
      _layerController.enableDeltaTracking = false;
      // Replace matching layer in the current layer list
      final updatedLayers =
          _layerController.layers.map((existing) {
            return existing.id == layer.id ? layer : existing;
          }).toList();
      _layerController.clearAllAndLoadLayers(updatedLayers);
      _layerController.enableDeltaTracking = wasTracking;
      setState(() {});
    } catch (e) {
      debugPrint('[RT] Failed to apply remote layer change: $e');
    }
  }

  void _applyRemoteSettingsChange(Map<String, dynamic> payload) {
    try {
      setState(() {
        final bgColor = payload['backgroundColor'];
        if (bgColor != null) {
          _canvasBackgroundColor = Color(bgColor as int);
        }
        final paperType = payload['paperType'] as String?;
        if (paperType != null) {
          _paperType = paperType;
        }
      });
    } catch (e) {
      debugPrint('[RT] Failed to apply remote settings: $e');
    }
  }

  // ─── Live Stroke Streaming ─────────────────────────────────────────

  /// 🎨 In-progress strokes from remote collaborators.
  /// Key: strokeId, Value: list of (x, y) points.
  static final Map<String, List<Offset>> _remoteLiveStrokes = {};
  static final Map<String, int> _remoteLiveStrokeColors = {};
  static final Map<String, double> _remoteLiveStrokeWidths = {};

  void _applyRemoteLiveStroke(Map<String, dynamic> payload) {
    try {
      final strokeId = payload['strokeId'] as String?;
      if (strokeId == null) return;

      final points = payload['points'] as List?;
      if (points == null || points.isEmpty) return;

      final color = payload['color'] as int? ?? 0xFF000000;
      final strokeWidth = (payload['strokeWidth'] as num?)?.toDouble() ?? 2.0;

      _remoteLiveStrokes.putIfAbsent(strokeId, () => []);
      for (final pt in points) {
        final map = pt as Map<String, dynamic>;
        _remoteLiveStrokes[strokeId]!.add(
          Offset((map['x'] as num).toDouble(), (map['y'] as num).toDouble()),
        );
      }
      _remoteLiveStrokeColors[strokeId] = color;
      _remoteLiveStrokeWidths[strokeId] = strokeWidth;

      setState(() {}); // Trigger repaint
    } catch (e) {
      debugPrint('[RT] Failed to apply live stroke: $e');
    }
  }

  /// Clear a live stroke when the final strokeAdded event arrives.
  void _clearRemoteLiveStroke(String strokeId) {
    _remoteLiveStrokes.remove(strokeId);
    _remoteLiveStrokeColors.remove(strokeId);
    _remoteLiveStrokeWidths.remove(strokeId);
  }

  /// Get current live strokes for rendering.
  static Map<String, List<Offset>> get remoteLiveStrokes => _remoteLiveStrokes;
  static Map<String, int> get remoteLiveStrokeColors => _remoteLiveStrokeColors;
  static Map<String, double> get remoteLiveStrokeWidths =>
      _remoteLiveStrokeWidths;

  // ─── Follow Mode ──────────────────────────────────────────────────

  /// ID of the user we're following (static map: extensions can't have fields).
  static final Map<int, String?> _followingUserIds = {};

  /// Start following a user's viewport.
  void _startFollowing(String userId) {
    _followingUserIds[hashCode] = userId;
    setState(() {});
    debugPrint('👁️ Following user: $userId');
  }

  /// Stop following.
  void _stopFollowing() {
    _followingUserIds.remove(hashCode);
    setState(() {});
  }

  /// Called when remote cursors change — apply follow mode viewport.
  void _onRemoteCursorsChanged() {
    final followingId = _followingUserIds[hashCode];
    if (followingId == null || _realtimeEngine == null) return;

    final cursors = _realtimeEngine!.remoteCursors.value;
    final followed = cursors[followingId];
    if (followed == null) {
      _stopFollowing();
      return;
    }

    // Follow mode: log viewport data for host app to handle.
    // The host app can subscribe to connectionState or a follow-mode callback.
    final vx = followed['vx'] as num?;
    final vy = followed['vy'] as num?;
    final vs = followed['vs'] as num?;
    if (vx != null && vy != null && vs != null) {
      debugPrint(
        '👁️ Follow viewport: offset=(${vx.toDouble()}, ${vy.toDouble()}) '
        'scale=${vs.toDouble()}',
      );
    }
  }

  // ─── Typing Indicator ─────────────────────────────────────────────

  // ─── Viewer Guard ──────────────────────────────────────────────────

  /// 🔒 Viewer guard — blocks editing and shows toast if viewer.
  /// Returns true if editing should be blocked.
  bool _checkViewerGuard() {
    if (!_isSharedCanvas || !_isViewerMode) return false;
    HapticFeedback.heavyImpact();
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.visibility, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text('View-only mode — you can\'t edit this canvas'),
          ],
        ),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return true;
  }

  /// 🔒 Get the currently-active element ID for locking broadcast.
  String? _getActiveElementId() {
    if (_lassoTool.hasSelection) {
      return _lassoTool.selectedIds.first;
    }
    if (_digitalTextTool.hasSelection) {
      return _digitalTextTool.selectedElement?.id;
    }
    return null;
  }

  // ─── Broadcast Helpers (called from drawing handlers) ──────────────

  /// Broadcast cursor position during drawing (throttled by engine).
  void _broadcastCursorPosition(
    Offset canvasPosition, {
    bool isDrawing = false,
    bool isTyping = false,
  }) {
    if (_realtimeEngine == null) return;

    _realtimeEngine!.updateCursor(
      CursorPresenceData(
        userId: '', // Set by engine
        displayName: '', // Set by engine
        cursorColor: 0xFF42A5F5,
        x: canvasPosition.dx,
        y: canvasPosition.dy,
        isDrawing: isDrawing,
        isTyping: isTyping,
        penType: _effectivePenType.name,
        penColor: _effectiveColor.toARGB32(),
      ),
    );
  }

  /// Broadcast a completed stroke to all collaborators.
  void _broadcastStrokeAdded(ProStroke stroke) {
    _realtimeEngine?.broadcastStroke(stroke.toJson());
  }

  /// Broadcast a stroke removal to all collaborators.
  void _broadcastStrokeRemoved(String strokeId) {
    _realtimeEngine?.broadcastStrokeRemoved(strokeId);
  }

  /// Broadcast an image update to all collaborators.
  void _broadcastImageUpdate(ImageElement image, {bool isNew = false}) {
    _realtimeEngine?.broadcastImageUpdate(image.toJson(), isNew: isNew);
  }

  /// Broadcast a text change to all collaborators.
  void _broadcastTextChange(DigitalTextElement text) {
    _realtimeEngine?.broadcastTextChange(text.toJson());
  }

  /// ⌨️ Broadcast typing state to show "typing..." on remote cursors.
  void _broadcastTypingState(bool isTyping, Offset position) {
    _broadcastCursorPosition(position, isTyping: isTyping);
  }

  /// 🎨 Stream stroke points during active drawing.
  void _broadcastStrokePoints({
    required String strokeId,
    required List<Map<String, dynamic>> newPoints,
    required String penType,
    required int color,
    double? strokeWidth,
  }) {
    _realtimeEngine?.streamStrokePoints(
      strokeId: strokeId,
      newPoints: newPoints,
      penType: penType,
      color: color,
      strokeWidth: strokeWidth,
    );
  }

  // ─── Cleanup ───────────────────────────────────────────────────────

  /// Disconnect and dispose real-time engine.
  Future<void> _disposeRealtimeCollaboration() async {
    _realtimeEventSub?.cancel();
    _realtimeEventSub = null;
    _realtimeEngine?.remoteCursors.removeListener(_onRemoteCursorsChanged);
    await _realtimeEngine?.disconnect();
    _realtimeEngine?.dispose();
    _realtimeEngine = null;
  }
}
