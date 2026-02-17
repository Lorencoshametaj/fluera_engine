// lib/screens/professional_canvas/services/canvas_realtime_sync_manager.dart

import 'package:flutter/foundation.dart';
import '../layers/layer_controller.dart';
import '../core/models/canvas_layer.dart';
import '../history/canvas_delta_tracker.dart';
import './nebula_sync_interfaces.dart';

/// 🔄 Real-Time Canvas Sync Manager (v3 — RTDB deltas + cursors)
///
/// Orchestrates inbound real-time sync for collaborative canvas editing.
/// Uses Firebase Realtime Database via [RtdbDeltaSyncService] for ultra-low
/// latency (~50-100ms). Listens for finalized deltas and remote cursors.
///
/// 🔥 COST OPT: Live stroke streaming removed — strokes appear on pen-up
/// via finalized deltas (~200-500ms delay, same as Figma).
class CanvasRealtimeSyncManager {
  final String canvasId;
  final String currentUserId;
  final LayerController layerController;
  final VoidCallback onRemoteUpdate;
  final NebulaRealtimeDeltaSync _deltaSyncService;

  /// Optional callback for text elements updated remotely
  final void Function(List<Map<String, dynamic>>?)? onRemoteTextUpdate;

  /// Optional callback for image elements updated remotely
  final void Function(List<Map<String, dynamic>>?)? onRemoteImageUpdate;

  /// ⚡ Conflict callback: (remoteUserId, elementId, deltaType)
  final void Function(String userId, String elementId, String deltaType)?
  onConflict;

  /// 📢 Layer change callback: (userName, isAdded)
  final void Function(String userName, bool isAdded)? onRemoteLayerChange;

  /// 📍 Remote cursors from RTDB (userId → cursorData)
  /// The presence overlay reads this for cursor positions + drawing state.
  final ValueNotifier<Map<String, Map<String, dynamic>>> remoteCursors =
      ValueNotifier({});

  /// Epoch-based dedup: skip deltas with epoch <= this
  int _lastProcessedEpoch = 0;

  /// Track processed delta IDs for extra safety
  final Set<String> _processedDeltaIds = {};

  /// Maximum number of processed IDs to keep (prevent memory leak)
  static const int _maxProcessedIds = 2000;

  /// Flag to pause sync during local operations
  bool _isPaused = false;

  /// Whether listener is active
  bool _isListening = false;

  // =========================================================================
  // 🔒 CONFLICT RESOLUTION: Element locking + active element tracking
  // =========================================================================

  /// ID of element the local user is currently interacting with
  String? _activeElementId;

  /// Remote locks: elementId → userId (from cursor data)
  final Map<String, String> _remoteLocks = {};

  /// Set the locally-active element (selected/editing)
  void setActiveElement(String? elementId) {
    _activeElementId = elementId;
  }

  /// Check if an element is locked by a remote user
  bool isLockedByRemote(String elementId) =>
      _remoteLocks.containsKey(elementId);

  /// Get the user who locked an element (null if not locked)
  String? getLockedByUser(String elementId) => _remoteLocks[elementId];

  /// Get display name of user who locked an element
  String? getLockedByName(String elementId) {
    final userId = _remoteLocks[elementId];
    if (userId == null) return null;
    final cursor = remoteCursors.value[userId];
    // 🚀 COST OPT: Read compact key with legacy fallback
    return (cursor?['n'] ?? cursor?['displayName']) as String? ?? 'User';
  }

  CanvasRealtimeSyncManager({
    required this.canvasId,
    required this.currentUserId,
    required this.layerController,
    required this.onRemoteUpdate,
    required NebulaRealtimeDeltaSync deltaSyncService,
    this.onRemoteTextUpdate,
    this.onRemoteImageUpdate,
    this.onConflict,
    this.onRemoteLayerChange,
  }) : _deltaSyncService = deltaSyncService;

  /// 🟢 Start listening for remote delta updates via RTDB.
  ///
  /// 🔥 COST OPT: Cursors only activate when `setCollaboratorsPresent(true)`
  /// is called. When solo, zero RTDB downloads for cursors.
  void startListening() {
    if (_isListening) return;
    _isListening = true;

    debugPrint(
      '🔄 CanvasRealtimeSyncManager: Starting RTDB listener for $canvasId',
    );

    // Listen for finalized deltas (always needed, even solo)
    _deltaSyncService.startListening(
      canvasId: canvasId,
      currentUserId: currentUserId,
      onDelta: _onRemoteDelta,
    );

    // NOTE: Cursors start via setCollaboratorsPresent()
  }

  /// 🔥 COST OPT: Enable/disable cursor listeners based on presence.
  ///
  /// Called by the canvas screen when the Firestore presence stream
  /// detects other users joining or leaving. When alone → no cursor
  /// downloads (saves ~100% of that bandwidth).
  bool _collaboratorsPresent = false;

  void setCollaboratorsPresent(bool present) {
    if (present == _collaboratorsPresent) return;
    _collaboratorsPresent = present;

    if (!_isListening) return;

    if (present) {
      debugPrint('👥 Collaborators detected — starting cursor listeners');
      _deltaSyncService.listenCursors(
        canvasId: canvasId,
        currentUserId: currentUserId,
        onUpdate: (cursors) {
          remoteCursors.value = cursors;
          // 🔒 Update remote locks from cursor data
          _remoteLocks.clear();
          for (final entry in cursors.entries) {
            // 🚀 COST OPT: Read compact key with legacy fallback
            final lockedId =
                (entry.value['lk'] ?? entry.value['lockedElementId'])
                    as String?;
            if (lockedId != null && lockedId.isNotEmpty) {
              _remoteLocks[lockedId] = entry.key;
            }
          }
        },
      );
    } else {
      debugPrint('👤 Alone on canvas — stopping cursor listeners');
      _deltaSyncService.stopListeningCursors();
      remoteCursors.value = {};
    }
  }

  /// 🔴 Stop listening
  void stopListening() {
    if (!_isListening) return;
    _isListening = false;

    _deltaSyncService.stopListening();
    _deltaSyncService.stopListeningCursors();
    remoteCursors.value = {};
    _collaboratorsPresent = false;
    debugPrint(
      '🔴 CanvasRealtimeSyncManager: Stopped RTDB listener for $canvasId',
    );
  }

  /// ⏸️ Pause sync (e.g., during local batch operations)
  void pause() => _isPaused = true;

  /// ▶️ Resume sync
  void resume() => _isPaused = false;

  /// 📥 Handle a single incoming remote delta from RTDB
  void _onRemoteDelta(Map<String, dynamic> deltaMap) {
    if (_isPaused) return;

    // Epoch-based dedup — use strict < so batch deltas sharing the same epoch
    // are all processed (ID-based dedup below handles exact duplicates)
    final epoch = deltaMap['epoch'] as int? ?? 0;
    if (epoch < _lastProcessedEpoch) return;

    // ID-based dedup (extra safety)
    final deltaId = deltaMap['id'] as String? ?? '$epoch';
    if (_processedDeltaIds.contains(deltaId)) return;

    // Parse and apply
    try {
      final delta = CanvasDelta.fromJson(deltaMap);

      // ⚡ CONFLICT CHECK: does this delta target our active element?
      if (_activeElementId != null && onConflict != null) {
        final targetId = delta.elementId ?? delta.layerId;
        if (targetId == _activeElementId) {
          // 🚀 COST OPT: Read compact key with legacy fallback
          final remoteUserId =
              (deltaMap['u'] ?? deltaMap['userId']) as String? ?? 'unknown';
          onConflict!(remoteUserId, targetId, delta.type.name);
        }
      }

      // Track processed
      _processedDeltaIds.add(deltaId);
      if (epoch > _lastProcessedEpoch) {
        _lastProcessedEpoch = epoch;
      }

      // Cleanup old processed IDs to prevent memory leak
      if (_processedDeltaIds.length > _maxProcessedIds) {
        final excess = _processedDeltaIds.length - (_maxProcessedIds ~/ 2);
        final toRemove = _processedDeltaIds.take(excess).toList();
        _processedDeltaIds.removeAll(toRemove);
      }

      // 📢 LAYER CHANGE NOTIFICATION
      if (onRemoteLayerChange != null) {
        if (delta.type == CanvasDeltaType.layerAdded ||
            delta.type == CanvasDeltaType.layerRemoved) {
          // 🚀 COST OPT: Read compact key with legacy fallback
          final remoteUserId =
              (deltaMap['u'] ?? deltaMap['userId']) as String? ?? 'unknown';
          final cursor = remoteCursors.value[remoteUserId];
          final userName =
              (cursor?['n'] ?? cursor?['displayName']) as String? ?? 'Someone';
          onRemoteLayerChange!(
            userName,
            delta.type == CanvasDeltaType.layerAdded,
          );
        }
      }

      // Apply the delta
      _applyRemoteDeltas([delta]);
    } catch (e) {
      debugPrint('⚠️ CanvasRealtimeSyncManager: Failed to parse delta: $e');
    }
  }

  /// 🎯 Apply remote deltas to the live canvas state
  void _applyRemoteDeltas(List<CanvasDelta> deltas) {
    try {
      // Temporarily disable delta tracking to avoid re-recording remote changes
      final previousTracking = layerController.enableDeltaTracking;
      layerController.enableDeltaTracking = false;

      // Apply deltas using the existing static method
      final currentLayers = List<CanvasLayer>.from(layerController.layers);
      final updatedLayers = CanvasDeltaTracker.applyDeltas(
        currentLayers,
        deltas,
      );

      // Reload with updated layers
      layerController.clearAllAndLoadLayers(updatedLayers);

      // Restore delta tracking
      layerController.enableDeltaTracking = previousTracking;

      debugPrint(
        '✅ CanvasRealtimeSyncManager: Applied ${deltas.length} remote deltas',
      );

      // Notify screen to rebuild
      onRemoteUpdate();
    } catch (e, stack) {
      debugPrint('❌ CanvasRealtimeSyncManager: Failed to apply deltas: $e');
    }
  }

  /// 🧹 Dispose resources
  void dispose() {
    stopListening();
    _processedDeltaIds.clear();
    remoteCursors.dispose();
  }
}
