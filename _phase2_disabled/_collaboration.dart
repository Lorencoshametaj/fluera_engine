part of '../nebula_canvas_screen.dart';

/// 📦 Collaboration & Sync — extracted from _NebulaCanvasScreenState
extension on _NebulaCanvasScreenState {
  /// 🔄 Initialize real-time collaboration (sharing + presence)
  /// Checks if canvas is shared and starts listeners accordingly.
  Future<void> _initRealtimeCollaboration() async {
    final user = null /* auth via _config */;
    if (user == null) return;

    // 💎 TIER GATE: Fetch tier HERE (can't rely on initState .then() — race condition)
    _subscriptionTier = _config.subscriptionTier;
    print(
      '🔐 [ProCanvas] Tier fetched: $_subscriptionTier, hasCloudSync=$_hasCloudSync, hasRealtime=$_hasRealtimeCollab',
    );
    if (!_hasCloudSync) return;

    try {
      // Check if canvas is shared (has other participants)
      // 🔧 FIX: Use infiniteCanvasId for permission checks because permissions
      // are stored under documents/{infiniteCanvasId}/permissions/, not under
      // the professional canvas timestamp ID (_canvasId).
      final permissionCheckId = widget.infiniteCanvasId ?? _canvasId;
      print('🔐 [ProCanvas] Permission check ID: $permissionCheckId');
      // Permissions handled via _config.permissions
      final participantCount = await permissionService.getPermissionCount(
        permissionCheckId,
      );
      final myPermission = await permissionService.getMyPermission(
        permissionCheckId,
      );

      if (mounted) {
        setState(() {
          // 🔧 FIX: > 1 because the owner's own permission counts as 1.
          // A canvas is only "shared" when there are OTHER participants.
          _isSharedCanvas = participantCount > 1;
          _myRole = myPermission?.role ?? UserRole.editor;
        });
      }

      // ☁️ Now that _isSharedCanvas is known, start remote recordings listener
      _loadRemoteRecordings();
      print(
        '🔐 [ProCanvas] participantCount=$participantCount, _isSharedCanvas=$_isSharedCanvas, myRole=$_myRole',
      );

      // Start real-time sync if shared AND user has Pro tier
      // 💎 TIER GATE: RTDB deltas + cursors require Pro
      if (!_hasRealtimeCollab) {
        // Plus: sharing is allowed (async via Firestore), but no real-time RTDB
        return;
      }

      // 🔧 FIX: Only start RTDB realtime (cursors + deltas) when canvas is
      // actually shared. autoSyncEnabled is a GLOBAL pref that was activating
      // RTDB listeners on ALL canvases — it should only gate Firestore sync.
      if (_isSharedCanvas) {
        // 🔄 Start inbound delta listener
        // 🔧 FIX: Use element-scoped syncId to prevent delta cross-contamination
        // between different elements in the same IC
        final syncId =
            (widget.infiniteCanvasId != null && widget.nodeId != null)
                ? '${widget.infiniteCanvasId}_${widget.nodeId}'
                : widget.infiniteCanvasId ?? _canvasId;

        // 🧹 COST OPT: Clean stale deltas before starting listeners
        // RtdbDeltaSyncService.instance.clearOldDeltas(syncId);

        _realtimeSyncManager = CanvasRealtimeSyncManager(
          canvasId: syncId,
          currentUserId: user.uid,
          layerController: _layerController,
          // deltaSyncService: deferred to Phase 2,
          onRemoteUpdate: () {
            if (mounted) {
              _refreshCachedLists();
              // 🖼️ Preload any new images from remote deltas
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

      // 🔵 Start presence tracking if shared
      if (_isSharedCanvas) {
        // 🔔 Wire join/leave notifications
        _presenceService.onUserJoined = (user) {
          if (!mounted) return;
          HapticFeedback.lightImpact();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.person_add, color: user.cursorColor, size: 18),
                  const SizedBox(width: 8),
                  Text('${user.displayName} joined'),
                ],
              ),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.only(bottom: 60, left: 16, right: 16),
            ),
          );
        };
        _presenceService.onUserLeft = (user) {
          if (!mounted) return;
          HapticFeedback.lightImpact();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.person_remove, color: user.cursorColor, size: 18),
                  const SizedBox(width: 8),
                  Text('${user.displayName} left'),
                ],
              ),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.only(bottom: 60, left: 16, right: 16),
            ),
          );
        };

        await _presenceService.joinCanvas(permissionCheckId);
      }
    } catch (e) {
      // Non-blocking: collaboration features are optional
    }
  }

  /// 🔒 Viewer guard — blocks editing and shows toast if viewer on shared canvas.
  /// Returns true if editing should be blocked.
  bool _checkViewerGuard() {
    if (!_isSharedCanvas || _myRole != UserRole.viewer) return false;
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
  /// Returns the first selected stroke, shape, or text element ID.
  String? _getActiveElementId() {
    // Lasso selection (strokes or shapes)
    if (_lassoTool.selectedStrokeIds.isNotEmpty) {
      return _lassoTool.selectedStrokeIds.first;
    }
    if (_lassoTool.selectedShapeIds.isNotEmpty) {
      return _lassoTool.selectedShapeIds.first;
    }
    // Digital text selection
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
