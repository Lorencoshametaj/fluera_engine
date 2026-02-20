part of '../nebula_canvas_screen.dart';

/// 📦 Collaboration & Sync — generic SDK implementation.
///
/// Checks permissions and presence via [NebulaCanvasConfig] providers.
/// Real-time sync goes through [CanvasRealtimeSyncManager] +
/// [NebulaRealtimeSyncProvider].
extension CollaborationExtension on _NebulaCanvasScreenState {
  /// 🔄 Initialize real-time collaboration (sharing + presence).
  ///
  /// Checks if canvas is shared and starts listeners accordingly.
  /// Uses `_config.permissions` to check access, `_config.presence` for
  /// user presence, and `_config.realtimeSync` for delta/cursor sync.
  Future<void> _initRealtimeCollaboration() async {
    final userId = await _config.getUserId();
    if (userId == null) return;

    // 💎 TIER GATE
    if (!_hasCloudSync) return;

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

      // 💎 TIER GATE: Real-time collaboration requires appropriate tier
      if (!_hasRealtimeCollab) return;

      // Start real-time delta sync if shared and realtimeSync is configured
      if (_isSharedCanvas && _config.realtimeSync != null) {
        final syncId =
            (widget.infiniteCanvasId != null && widget.nodeId != null)
                ? '${widget.infiniteCanvasId}_${widget.nodeId}'
                : widget.infiniteCanvasId ?? _canvasId;

        _realtimeSyncManager = CanvasRealtimeSyncManager(
          canvasId: syncId,
          currentUserId: userId,
          layerController: _layerController,
          deltaSyncService: _config.realtimeSync!,
          onRemoteUpdate: () {
            if (mounted) {
              _refreshCachedLists();
              // Preload any new images from remote deltas
              for (final layer in _layerController.layers) {
                for (final img in layer.images) {
                  if (!_loadedImages.containsKey(img.imagePath)) {
                    _preloadImage(
                      img.imagePath,
                      storageUrl: img.storageUrl,
                      thumbnailUrl: img.thumbnailUrl,
                    );
                  }
                }
              }
              // 🧠 Full cache invalidation on remote updates (content may be completely different)
              ImagePainter.invalidateCache();
              setState(() {});
            }
          },
          onConflict: (userId, elementId, deltaType) {
            if (!mounted) return;
            final name =
                _realtimeSyncManager?.getLockedByName(elementId) ??
                _realtimeSyncManager
                        ?.remoteCursors
                        .value[userId]?['displayName']
                    as String? ??
                'Someone';
            HapticFeedback.mediumImpact();
            ScaffoldMessenger.of(context).clearSnackBars();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.flash_on, color: Colors.amber, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('$name modified the element you\'re editing'),
                    ),
                  ],
                ),
                duration: const Duration(seconds: 3),
                behavior: SnackBarBehavior.floating,
                backgroundColor: Colors.orange.shade800,
              ),
            );
          },
          onRemoteLayerChange: (userName, isAdded) {
            if (!mounted) return;
            HapticFeedback.lightImpact();
            ScaffoldMessenger.of(context).clearSnackBars();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Icon(
                      isAdded ? Icons.layers : Icons.layers_clear,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isAdded
                          ? '$userName added a new layer'
                          : '$userName removed a layer',
                    ),
                  ],
                ),
                duration: const Duration(seconds: 3),
                behavior: SnackBarBehavior.floating,
                backgroundColor:
                    isAdded ? Colors.blue.shade700 : Colors.red.shade700,
              ),
            );
          },
        );
        _realtimeSyncManager!.startListening();
      }

      // Start presence tracking if configured
      if (_isSharedCanvas && _config.presence != null) {
        final permissionCheckId = widget.infiniteCanvasId ?? _canvasId;
        _config.presence!.joinCanvas(permissionCheckId);
      }
    } catch (e) {
      // Non-blocking: collaboration features are optional
      debugPrint('[Collaboration] Init failed: $e');
    }
  }

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

  /// 🔒 Remote lock guard — prevents editing elements locked by other users.
  /// Returns true if the element is locked and editing should be blocked.
  bool _checkRemoteLockGuard(String elementId) {
    if (!_isSharedCanvas || _realtimeSyncManager == null) return false;
    if (!_realtimeSyncManager!.isLockedByRemote(elementId)) return false;

    final lockerName =
        _realtimeSyncManager!.getLockedByName(elementId) ?? 'Someone';
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.lock, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text('🔒 $lockerName is editing this element'),
          ],
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.deepPurple,
      ),
    );
    return true;
  }
}
