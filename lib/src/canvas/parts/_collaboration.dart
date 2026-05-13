part of '../fluera_canvas_screen.dart';

/// 💾 Op-log threshold above which the CRDT snapshot is rotated.
///
/// Picked as a balance between rehydration cost (linear in ops since the
/// last snapshot) and snapshot write cost (quadratic-ish in node count).
/// Multi-hour drawing sessions will fold ~every 500 mutations into a fresh
/// snapshot, capping cold-start replay at well under a second.
const int _kCrdtSnapshotEveryOps = 500;

/// 📦 Collaboration & Sync — generic SDK implementation.
///
/// Checks permissions and presence via [FlueraCanvasConfig] providers.
/// Initializes the [FlueraRealtimeEngine] when a [FlueraRealtimeAdapter]
/// is provided, connecting remote events to canvas state and feeding
/// the cursor overlay.
extension CollaborationExtension on _FlueraCanvasScreenState {
  /// 🔄 Initialize collaboration features (permissions + presence + realtime).
  ///
  /// Checks if canvas is shared and sets viewer mode accordingly.
  /// Uses `_config.permissions` to check access, `_config.presence` for
  /// user presence, and `_config.realtimeAdapter` for live collaboration.
  Future<void> _initRealtimeCollaboration() async {
    final userId = await _config.getUserId();
    if (userId == null) return;

    try {
      // Check permissions via config provider.
      //
      // The permission provider is wired unconditionally (every canvas in a
      // signed-in session, not only the shared ones), so we can't infer
      // "this canvas is shared" from `permissions != null`. The contract is:
      //
      //   • canEdit returns true  → owner, or editor-role share, or local-
      //                              only canvas not yet in cloud. Treat as
      //                              non-shared from the UI standpoint
      //                              unless the host has tagged it via
      //                              `permissions.currentUserRole`.
      //   • canEdit returns false → explicit viewer share (the only case
      //                              where we engage view-only mode).
      if (_config.permissions != null) {
        final permissionCheckId = widget.infiniteCanvasId ?? _canvasId;
        final canEdit = await _config.permissions!.canEdit(permissionCheckId);
        final role = _config.permissions!.currentUserRole;
        // Canvas is "shared" — i.e. has at least one peer that may show up
        // on the realtime channel — when:
        //   • we are an editor or viewer recipient, OR
        //   • we own the canvas AND have already invited at least one peer.
        // 'owner' (no shares yet) and 'none' / unknown stay non-shared.
        final isShared = role == 'editor' ||
            role == 'viewer' ||
            role == 'owner-shared';

        if (mounted) {
          setState(() {
            _isSharedCanvas = isShared;
            _isViewerMode = (role == 'viewer' || role == 'editor') && !canEdit;
          });
        }
      }

      // Start presence tracking if configured
      if (_isSharedCanvas && _config.presence != null) {
        final permissionCheckId = widget.infiniteCanvasId ?? _canvasId;
        _config.presence!.joinCanvas(permissionCheckId);
      }

      // 🔒 Live permission watch. The provider may emit role changes
      // mid-session (owner revokes our editor share, downgrades us to
      // viewer, etc). Without this we only re-check on canvas reopen,
      // letting a revoked editor keep broadcasting until they close
      // and reopen the canvas. Implementations may opt out by returning
      // null — the legacy "check-once" behavior.
      if (_config.permissions != null) {
        final permissionCheckId = widget.infiniteCanvasId ?? _canvasId;
        final stream =
            _config.permissions!.canEditChanges(permissionCheckId);
        _permissionSubscription?.cancel();
        _permissionSubscription =
            stream?.listen(_onPermissionChanged);
      }

      // 🔴 Initialize real-time engine only when:
      //   • the tier permits collaboration AND a transport adapter is wired,
      //   • AND the canvas is actually shared (a non-shared canvas has no
      //     remote peers, so subscribing to its broadcast channel just
      //     burns Supabase bandwidth and surfaces a misleading "Live" badge).
      if (_hasRealtimeCollab &&
          _config.realtimeAdapter != null &&
          _isSharedCanvas) {
        // 🔄 Resolve the local peer identity FIRST — the engine uses it as
        // its broadcast `senderId` (and self-echo filter), so two windows
        // of the same auth user must produce distinct broadcast ids or
        // they'll filter each other's events as own-echo and never see
        // remote strokes.
        //
        // Multi-device installs override `config.getDeviceId` with a
        // stable per-device UUID so two phones for the same user don't
        // collapse to one peerId at HLC tie-break time. We then append
        // a per-process session nonce ("{deviceId}-{nonce}") so the same
        // device opening the canvas in two windows / two app instances
        // doesn't produce colliding opIds either: the CRDT generates
        // opIds as `${peerId}_${counter}` and `_opCounter` is in-memory,
        // so without the nonce two processes would each emit counter
        // 0,1,2,… and the remote dedup (`_appliedOps.contains`) would
        // silently drop the second one. base36 24-bit nonce → collision
        // risk negligible per session; the per-canvas counter resume via
        // `maxOpCounterForPeer` still works because the new peerId is
        // unique to this session.
        final deviceId = (await _config.getDeviceId?.call()) ?? userId;
        final sessionNonce =
            math.Random().nextInt(1 << 24).toRadixString(36);
        final resolvedPeerId = '$deviceId-$sessionNonce';
        _crdtPeerId = resolvedPeerId;

        // Stamp every mutation we author with this peerId so the undo
        // manager can filter "mine" vs "teammate's" — `Ctrl+Z` reverts
        // only deltas whose actorId matches localActorId.
        _layerController.localActorId = resolvedPeerId;

        _realtimeEngine = FlueraRealtimeEngine(
          adapter: _config.realtimeAdapter!,
          // The engine's `localUserId` is semantically "broadcast id":
          // it's stamped onto every outbound senderId and used to drop
          // self-echoes. Pass the peerId, not the auth userId, so two
          // browsers for the same user don't filter each other.
          localUserId: resolvedPeerId,
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

        // 💾 Bind the CRDT persistence layer. We re-use the same SQLite
        // database that owns the canvas tables (the only adapter that
        // currently exposes a Database is SqliteStorageAdapter); other
        // backends keep working in pure-online mode (persistence == null).
        final adapter = _config.storageAdapter;
        if (adapter is SqliteStorageAdapter && adapter.isInitialized) {
          _crdtPersistence = CRDTPersistence(adapter.database);
        }

        // 🔄 Wire the CRDT capture/apply pipeline. Every LayerController
        // mutation produces a CRDTOperation that broadcasts via the realtime
        // engine; every incoming op is replayed on the local LayerController
        // inside the observer's runSilently window so we never re-broadcast
        // a remote change.
        final crdt = CRDTSceneGraph(localPeerId: resolvedPeerId);
        final persistence = _crdtPersistence;
        final canvasId = _canvasId;
        final engine = _realtimeEngine!;
        final observer = CRDTLayerControllerObserver(
          crdt,
          onLocalOperation: (op) async {
            // Try to persist BEFORE broadcasting (write-then-send) so a
            // crash between the two doesn't lose the mutation. If the DB
            // is briefly contended (SQLITE_BUSY past `busy_timeout`) we
            // still broadcast — peers prefer a momentarily-unpersisted
            // duplicate over a silently-dropped stroke. The CRDT layer
            // dedups by opId on either side.
            bool persisted = false;
            if (persistence != null) {
              try {
                await persistence.insertOp(canvasId, op);
                if (mounted) _crdtPendingOpsNotifier.value++;
                persisted = true;
              } catch (_) {
                // Local persistence failed — continue to broadcast anyway.
              }
            }
            // Await the actual wire send. broadcastCRDTOperation returns
            // true ONLY after `_adapter.broadcast` resolved cleanly. When
            // it returns false the engine has parked the event in its
            // in-memory offline queue, but we keep `sent_at` NULL so the
            // SQLite outbox + periodic drain can retry until the network
            // accepts it (Supabase Broadcast has no ack channel — without
            // this, transient packet loss silently drops strokes).
            final delivered = await engine.broadcastCRDTOperation(op);
            if (persistence != null && persisted && delivered) {
              try {
                await persistence.markBroadcast(op.opId);
              } catch (_) {}
              if (mounted) {
                _crdtPendingOpsNotifier.value =
                    (_crdtPendingOpsNotifier.value - 1).clamp(0, 1 << 31);
              }
            }
            // 📜 Server-side op log: fire-and-forget after the wire send
            // succeeded. Lets a peer that comes back online after a long
            // offline window catch up incrementally via opsSince(...) on
            // canvas open instead of waiting for the next snapshot diff.
            // Only push when we actually delivered — otherwise the
            // broadcast catch-up flow already handles re-emission.
            final cloud = _config.cloudAdapter;
            if (delivered && cloud != null) {
              unawaited(
                cloud
                    .uploadOp(
                      canvasId,
                      opId: op.opId,
                      peerId: op.peerId,
                      tsMs: op.timestamp.physicalMs,
                      counter: op.timestamp.counter,
                      opType: op.type.name,
                      nodeId: op.nodeId.isEmpty ? null : op.nodeId,
                      payloadJson: op.toJson(),
                    )
                    .catchError((_) {}),
              );
            }
          },
        );
        _crdtSceneGraph = crdt;
        _crdtMutationObserver = observer;
        _crdtApplier = CRDTToLayerControllerApplier(
          crdt: crdt,
          layerController: _layerController,
          observer: observer,
        );

        // 💾 Hybrid rehydration: load the snapshot as a baseline, then apply
        // only the ops produced strictly after the snapshot HLC. Falls back
        // to a full op-log replay when no snapshot exists (first session).
        // Runs inside `runSilently` so the observer doesn't re-broadcast.
        if (persistence != null) {
          await observer.runSilently(() async {
            final snap = await persistence.loadSnapshot(canvasId);
            final List<CRDTOperation> opsToReplay;
            if (snap != null) {
              _crdtSceneGraph!.mergeState(
                CRDTSceneGraph.fromJson(snap.graphJson),
              );
              opsToReplay = await persistence.opsSinceHlc(
                canvasId: canvasId,
                tsMs: snap.hlc.physicalMs,
                counter: snap.hlc.counter,
                peerIdTieBreak: snap.hlc.peerId,
              );
            } else {
              opsToReplay = await persistence.loadAllOps(canvasId);
            }
            for (final op in opsToReplay) {
              _crdtApplier!.applyRemote(op);
            }
          });

          // 🔄 Resume the local op-counter past anything we have already
          // produced on this canvas. The CRDT's _opCounter resets to 0
          // each process start; without this, the first op of a new
          // session reuses an opId from the previous session and remote
          // peers silently dedup it (their _appliedOps already contains
          // the id, restored from THEIR persistent log).
          final maxCounter = await persistence.maxOpCounterForPeer(
            canvasId: canvasId,
            peerId: resolvedPeerId,
          );
          crdt.advanceOpCounterTo(maxCounter + 1);
        }

        // Initialize the pending-ops badge from the persisted outbox: any
        // op produced offline in a previous session is still NULL until the
        // first reconnect drain.
        if (persistence != null) {
          final pending = await persistence.unsentOps(canvasId);
          if (mounted) _crdtPendingOpsNotifier.value = pending.length;
        }

        // 📜 Server-side catch-up: ask the cloud for every op the local
        // CRDT graph hasn't seen. This is the recovery path for a peer
        // that was offline while another peer was actively editing — the
        // live broadcast they missed is replayed from `operations_log`.
        // Runs after local rehydration so we know our own high-water HLC,
        // and before observer registration so the catch-up replay doesn't
        // bounce back through onLocalOperation.
        await _catchUpFromCloudOpsLog(crdt, canvasId);

        // Now that local replay is complete, start observing user mutations.
        _crdtMutationUnsubscribe =
            _layerController.addMutationObserver(observer.onMutation);

        // Subscribe to remote ops AFTER replay so we never apply the same
        // op twice (the persisted log already contains them).
        //
        // Apply to the in-memory LayerController FIRST, persist second:
        // the user's main feedback loop is "see the stroke appear", and
        // SQLite contention (busy_timeout exhaustion under load) must not
        // be allowed to drop visible strokes. The CRDT graph dedups by
        // opId so a future restart-driven replay won't double-apply.
        //
        // Coalesce ops arriving in the same microtask burst: the pixel
        // eraser sends `removeNode` immediately followed by 1-2 `addNode`
        // ops for the surviving fragments. Applying each op separately
        // triggers a paint frame between the remove and the adds → user
        // sees the parent stroke briefly disappear (visible "flash").
        // Batching with `beginBatch`/`endBatch` defers `notifyListeners`
        // until every op in the burst has been applied, so the swap is
        // atomic from the renderer's POV.
        _crdtOpSubscription = engine.incomingCRDTOperations.listen((op) {
          _pendingRemoteOps.add(op);
          _pendingRemoteOpsTimer?.cancel();
          _pendingRemoteOpsTimer =
              Timer(Duration.zero, _flushPendingRemoteOps);
        });

        // Connect cursor stream → CanvasPresenceOverlay ValueNotifier
        _realtimeEngine!.remoteCursors.addListener(_onRemoteCursorsChanged);

        // Connect to canvas channel
        await _realtimeEngine!.connect(_canvasId);

        // 🔄 #2 Auto-retry pending recording downloads on reconnect
        // 📡 #8 Auto-upload queued offline recordings
        // 💾 Drain CRDT outbox: any local op produced while offline is
        //    rebroadcast in HLC order on reconnect.
        _realtimeEngine!.connectionState.addListener(() {
          if (_realtimeEngine!.connectionState.value ==
              RealtimeConnectionState.connected) {
            _retryPendingRecordingDownloads();
            _syncOfflineUploads();
            _drainCRDTOutbox().then((_) => _maybeRotateCrdtSnapshot());
          }
        });

        // 💾 Initial drain: the listener above fires only on STATE
        // CHANGES, but `engine.connect()` already set the state to
        // `connected` synchronously above. Without this kick, ops
        // produced offline in a previous session would have to wait
        // for the next 5s periodic timer or a disconnect-reconnect
        // cycle. Cheap (no-op when outbox is empty).
        if (_realtimeEngine!.connectionState.value ==
            RealtimeConnectionState.connected) {
          unawaited(_drainCRDTOutbox());
        }

        // 💾 Periodic safety net for transient broadcast failures. Supabase
        // Broadcast has no ack channel: when the wire send raises (timeout,
        // backpressure, brief network blip) the op stays NULL in `sent_at`
        // and would otherwise wait until the next reconnect to flush. Five
        // seconds is short enough to feel "instant" on the receiver under
        // typical drops, long enough to coalesce naturally with the
        // observer-driven drain so we don't shadow-flood the channel.
        _crdtOutboxDrainTimer?.cancel();
        _crdtOutboxDrainTimer = Timer.periodic(
          const Duration(seconds: 5),
          (_) => _drainCRDTOutbox(),
        );

      }
    } catch (e) {
      // Non-blocking: collaboration features are optional
    }
  }

  // ─── Remote Event Dispatch ─────────────────────────────────────────

  /// Handle incoming real-time events from other collaborators.
  ///
  /// Scene-graph state (strokes / shapes / texts / images / layers) is
  /// replicated through the dedicated [RealtimeEventType.crdtOperation]
  /// channel — the realtime engine routes those events to
  /// `incomingCRDTOperations`, where [CRDTToLayerControllerApplier] applies
  /// them. Self-echo suppression and idempotency are handled by the CRDT
  /// layer (opId dedup + observer suspend), so this dispatcher is now
  /// concerned only with three categories of event:
  ///
  ///   1. Live, ephemeral streams that don't fit a CRDT (live stroke points).
  ///   2. PDF and recording orchestration (asset transfer, not state).
  ///   3. Element locks (handled internally by the engine, observed here
  ///      only to keep the lock table in sync).
  void _onRemoteRealtimeEvent(CanvasRealtimeEvent event) {
    if (!mounted) return;

    // Skip events that this device produced. CRDT ops do not flow here
    // (the engine peels them off into incomingCRDTOperations), and the few
    // remaining event types either are idempotent or carry no scene-graph
    // mutation — but the existing PDF/recording handlers were designed
    // assuming self-echo had been filtered, so keep the guard.
    if (_realtimeEngine != null &&
        event.senderId == _realtimeEngine!.localUserId) {
      return;
    }

    switch (event.type) {
      case RealtimeEventType.strokePointsStreamed:
        // 🐛 FIX: Skip live points from senders who just finished a stroke
        final now = DateTime.now().millisecondsSinceEpoch;
        final suppressUntil = _suppressedLiveStrokeSenders[event.senderId] ?? 0;
        if (now < suppressUntil) {
          break; // Discard late-arriving live points
        }
        _suppressedLiveStrokeSenders.remove(event.senderId);
        _applyRemoteLiveStroke(event.payload);
        break;

      case RealtimeEventType.pdfLoading:
        _applyRemotePdfLoading(event.payload);
        break;

      case RealtimeEventType.pdfProgress:
        _applyRemotePdfProgress(event.payload);
        break;

      case RealtimeEventType.pdfLoadingFailed:
        _applyRemotePdfLoadingFailed(event.payload);
        break;

      case RealtimeEventType.pdfAdded:
        _applyRemotePdf(event.payload);
        break;

      case RealtimeEventType.pdfBlankCreated:
        _applyRemoteBlankPdf(event.payload);
        break;

      case RealtimeEventType.pdfUpdated:
        _applyRemotePdfUpdate(event.payload);
        break;

      case RealtimeEventType.pdfRemoved:
        _applyRemotePdfRemoved(event.payload);
        break;

      case RealtimeEventType.recordingAdded:
        _applyRemoteRecordingAdded(event.payload);
        break;

      case RealtimeEventType.recordingRemoved:
        _applyRemoteRecordingRemoved(event.payload);
        break;

      case RealtimeEventType.recordingPinAdded:
        _applyRemoteRecordingPinAdded(event.payload);
        break;

      case RealtimeEventType.recordingPinRemoved:
        _applyRemoteRecordingPinRemoved(event.payload);
        break;

      case RealtimeEventType.elementLocked:
      case RealtimeEventType.elementUnlocked:
        // Handled internally by FlueraRealtimeEngine (lock table).
        break;

      case RealtimeEventType.strokeAdded:
      case RealtimeEventType.strokeRemoved:
      case RealtimeEventType.imageAdded:
      case RealtimeEventType.imageUpdated:
      case RealtimeEventType.imageRemoved:
      case RealtimeEventType.textChanged:
      case RealtimeEventType.textRemoved:
      case RealtimeEventType.layerChanged:
      case RealtimeEventType.canvasSettingsChanged:
        // Replaced by the CRDT pipeline. A peer running an older client may
        // still emit these — drop them rather than double-applying alongside
        // the CRDT op.
        break;

      case RealtimeEventType.crdtOperation:
        // Routed exclusively to incomingCRDTOperations by the realtime
        // engine. Listed here only to satisfy exhaustive switch checking.
        break;

      case RealtimeEventType.recordingRenamed:
        _applyRemoteRecordingRenamed(event.payload);
        break;
    }
  }

  // ─── Remote Event Handlers ─────────────────────────────────────────

  /// Deep-cast a Firebase RTDB map to Map<String, dynamic>
  static Map<String, dynamic> _deepCastMap(Map map) {
    return map.map((key, value) {
      final k = key.toString();
      if (value is Map) {
        return MapEntry(k, _deepCastMap(value));
      } else if (value is List) {
        return MapEntry(k, _deepCastList(value));
      }
      return MapEntry(k, value);
    });
  }

  static List<dynamic> _deepCastList(List list) {
    return list.map((item) {
      if (item is Map) return _deepCastMap(item);
      if (item is List) return _deepCastList(item);
      return item;
    }).toList();
  }

  // ─── Live Stroke Streaming ─────────────────────────────────────────

  /// 🎨 In-progress strokes from remote collaborators.
  /// Key: strokeId, Value: list of (x, y) points.
  static final Map<String, List<Offset>> _remoteLiveStrokes = {};
  static final Map<String, int> _remoteLiveStrokeColors = {};
  static final Map<String, double> _remoteLiveStrokeWidths = {};

  /// 🐛 FIX: Suppress live stroke points from senders who just finalized.
  /// Key: senderId, Value: suppress-until timestamp (ms since epoch).
  static final Map<String, int> _suppressedLiveStrokeSenders = {};

  // ─── PDF Loading Placeholders ──────────────────────────────────────

  /// 📄 PDF documents that are being uploaded by a collaborator.
  /// Shown as loading placeholders until the real PDF data arrives.
  static final Map<String, PdfLoadingPlaceholder> _pdfLoadingPlaceholders = {};
  static final Map<String, Timer> _pdfLoadingTimeouts = {};

  /// Get current PDF loading placeholders for rendering.
  static Map<String, PdfLoadingPlaceholder> get pdfLoadingPlaceholders =>
      _pdfLoadingPlaceholders;

  /// 🔄 Stop loading pulse if no more placeholders are pending.
  void _stopPdfPlaceholderPulseIfDone() {
    if (_pdfLoadingPlaceholders.isEmpty) {
      _stopLoadingPulseIfDone();
    }
  }

  /// 🧹 Centralized placeholder cleanup: removes state, timeout, pulse, and thumbnail cache.
  void _cleanupPlaceholder(String docId) {
    _pdfLoadingPlaceholders.remove(docId);
    _pdfLoadingTimeouts[docId]?.cancel();
    _pdfLoadingTimeouts.remove(docId);
    _stopPdfPlaceholderPulseIfDone();
    // 🧹 Cleanup decoded thumbnail from painter cache
    PdfLoadingPlaceholderPainter.decodedThumbnails.remove(docId);
    PdfLoadingPlaceholderPainter.thumbnailDecodeRequested.remove(docId);
    PdfLoadingPlaceholderPainter.animatedProgress.remove(docId);
  }

  /// 🐛 FIX: Timestamp each live stroke for stale cleanup.
  static final Map<String, int> _remoteLiveStrokeTimestamps = {};

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
        // Firebase RTDB returns Map<Object?, Object?> — safe cast
        final map = Map<String, dynamic>.from(pt as Map);
        _remoteLiveStrokes[strokeId]!.add(
          Offset((map['x'] as num).toDouble(), (map['y'] as num).toDouble()),
        );
      }
      _remoteLiveStrokeColors[strokeId] = color;
      _remoteLiveStrokeWidths[strokeId] = strokeWidth;
      _remoteLiveStrokeTimestamps[strokeId] =
          DateTime.now().millisecondsSinceEpoch;

      // 🐛 FIX: Clean stale live strokes (>5s old — strokeAdded was lost)
      _cleanStaleLiveStrokes();

      setState(() {}); // Trigger repaint
    } catch (e) {
    }
  }

  /// 🐛 FIX: Remove live strokes that are older than 5 seconds.
  /// This catches cases where the strokeAdded event was lost or delayed.
  void _cleanStaleLiveStrokes() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final staleIds = <String>[];
    for (final entry in _remoteLiveStrokeTimestamps.entries) {
      if (now - entry.value > 5000) {
        staleIds.add(entry.key);
      }
    }
    for (final id in staleIds) {
      _remoteLiveStrokes.remove(id);
      _remoteLiveStrokeColors.remove(id);
      _remoteLiveStrokeWidths.remove(id);
      _remoteLiveStrokeTimestamps.remove(id);
    }
    if (staleIds.isNotEmpty) {
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

  /// Resolve a CRDT node id to its bounding rect in canvas coordinates.
  ///
  /// Used by `CanvasPresenceOverlay` to draw selection awareness rects
  /// for remote peers. Walks every layer's strokes & shapes in O(N) —
  /// acceptable because selections are small (1-20 ids typical) and the
  /// canvas-screen rebuild rate is throttled by the pulse animation.
  /// Returns `null` when the id isn't resolvable (element not yet
  /// replicated, deleted while in flight, or a text/image node — those
  /// types don't expose a precomputed bounds; their selection rects
  /// stay un-rendered until we wire a layout-aware lookup, Tier 2).
  Rect? _lookupSelectionBounds(String nodeId) {
    for (final layer in _layerController.layers) {
      for (final s in layer.strokes) {
        if (s.id == nodeId) return s.bounds;
      }
      for (final s in layer.shapes) {
        if (s.id == nodeId) {
          return Rect.fromPoints(s.startPoint, s.endPoint);
        }
      }
    }
    return null;
  }

  // ─── Broadcast Helpers (called from drawing handlers) ──────────────

  /// Broadcast cursor position during drawing (throttled by engine).
  void _broadcastCursorPosition(
    Offset canvasPosition, {
    bool isDrawing = false,
    bool isTyping = false,
    bool isRecording = false,
    bool isListening = false,
    List<String>? selection,
  }) {
    if (_realtimeEngine == null) return;

    // When the caller doesn't explicitly pass selection, fall back to
    // the lasso tool's current selection so any cursor broadcast (drag,
    // hover, draw) automatically carries the local user's selection
    // state to peers. Empty selection collapses to `null` on the wire
    // (CursorPresenceData.toJson skips empty lists) — keeps idle cursor
    // updates at the same baseline cost.
    final effectiveSelection = selection ??
        (_lassoTool.hasSelection ? _lassoTool.selectedIds.toList() : null);

    _realtimeEngine!.updateCursor(
      CursorPresenceData(
        userId: '', // Set by engine
        displayName: '', // Set by engine
        cursorColor: 0xFF42A5F5,
        x: canvasPosition.dx,
        y: canvasPosition.dy,
        isDrawing: isDrawing,
        isTyping: isTyping,
        isRecording: isRecording,
        isListening: isListening,
        penType: _effectivePenType.name,
        penColor: _effectiveColor.toARGB32(),
        selection: effectiveSelection,
      ),
    );
  }

  // Stroke / image / text broadcasts are no longer manually invoked: every
  // mutation on `_layerController` produces a CanvasDelta that the registered
  // CRDTLayerControllerObserver translates into a CRDTOperation, which is
  // broadcast through `_realtimeEngine.broadcastCRDTOperation`. Receivers
  // apply ops via `CRDTToLayerControllerApplier.applyRemote`. This eliminates
  // self-echo handling, delta-tracking guards and the stroke/image/text
  // legacy event types from this dispatcher.

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

  // ─── Permission revocation handling ───────────────────────────────

  /// React to a live permission change for this canvas.
  ///
  /// Provider emits `false` when the local user has been demoted (share
  /// row deleted, role flipped to `viewer`, etc). We immediately stop
  /// generating CRDT ops by detaching the LayerController observer so
  /// further strokes still draw locally but don't reach peers, then
  /// surface a non-blocking SnackBar. Re-grant is also handled — if the
  /// owner restores the share, we re-attach the observer.
  void _onPermissionChanged(bool canEdit) {
    if (!mounted) return;
    final wasViewer = _isViewerMode;
    final isViewer = !canEdit;

    setState(() => _isViewerMode = isViewer);

    if (isViewer && !wasViewer) {
      // Just lost edit access. Detach the mutation observer so local
      // edits stop emitting ops; the engine itself stays connected
      // (we still receive remote updates, just don't send).
      _crdtMutationUnsubscribe?.call();
      _crdtMutationUnsubscribe = null;

      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.lock_outline, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                    'Your edit access was revoked — view only mode.'),
              ),
            ],
          ),
          duration: Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else if (!isViewer && wasViewer) {
      // Edit access restored. Re-attach the mutation observer so user
      // edits start producing ops again. The CRDT graph and persistence
      // are still alive — only the LayerController hook was dropped.
      final observer = _crdtMutationObserver;
      if (observer != null) {
        _crdtMutationUnsubscribe =
            _layerController.addMutationObserver(observer.onMutation);
      }

      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.edit, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Expanded(child: Text('Edit access granted.')),
            ],
          ),
          duration: Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ─── Cleanup ───────────────────────────────────────────────────────

  /// Disconnect and dispose real-time engine.
  Future<void> _disposeRealtimeCollaboration() async {
    _realtimeEventSub?.cancel();
    _realtimeEventSub = null;

    await _permissionSubscription?.cancel();
    _permissionSubscription = null;

    // Tear down the CRDT pipeline before the engine so no in-flight remote
    // op can land on a stale LayerController.
    _crdtOutboxDrainTimer?.cancel();
    _crdtOutboxDrainTimer = null;
    _pendingRemoteOpsTimer?.cancel();
    _pendingRemoteOpsTimer = null;
    _pendingRemoteOps.clear();
    await _crdtOpSubscription?.cancel();
    _crdtOpSubscription = null;
    _crdtMutationUnsubscribe?.call();
    _crdtMutationUnsubscribe = null;
    _crdtApplier?.dispose();
    _crdtApplier = null;
    _crdtMutationObserver = null;
    _crdtSceneGraph = null;
    // [_crdtPersistence] wraps the SqliteStorageAdapter database which is
    // owned by the host app — we never close it here.
    _crdtPersistence = null;
    _crdtPeerId = null;
    if (mounted) _crdtPendingOpsNotifier.value = 0;

    _realtimeEngine?.remoteCursors.removeListener(_onRemoteCursorsChanged);
    await _realtimeEngine?.disconnect();
    _realtimeEngine?.dispose();
    _realtimeEngine = null;
  }

  /// 💾 Drain the CRDT outbox on reconnect.
  ///
  /// Reads every op for the current canvas with `sent_at IS NULL` in HLC
  /// order and re-broadcasts it. This is the single mechanism by which
  /// mutations produced offline propagate to peers — the live broadcast
  /// path already marks `sent_at` immediately, so a healthy session should
  /// almost always find this queue empty.
  /// Drain `_pendingRemoteOps` in a single repaint frame.
  ///
  /// Called on the next microtask after the first op of a burst arrives,
  /// so all ops queued by the stream listener in the same event-loop
  /// tick land together. `LayerController.beginBatch()` defers the
  /// underlying `notifyListeners` and version bumps until `endBatch()`
  /// — without that, the pixel eraser's `removeNode + addNode(frag1) +
  /// addNode(frag2)` sequence would triple-paint the canvas, briefly
  /// showing a hole between the parent removal and the fragment adds.
  ///
  /// Persistence runs after the visual apply, fire-and-forget per op:
  /// the user-facing feedback (stroke appears / disappears) is what
  /// matters, the SQLite log catches up in the background.
  void _flushPendingRemoteOps() {
    final applier = _crdtApplier;
    if (applier == null || _pendingRemoteOps.isEmpty) return;
    final ops = List<CRDTOperation>.of(_pendingRemoteOps);
    _pendingRemoteOps.clear();

    _layerController.beginBatch();
    try {
      for (final op in ops) {
        applier.applyRemote(op);
      }
    } finally {
      _layerController.endBatch();
    }

    final persistence = _crdtPersistence;
    if (persistence != null) {
      // Fire-and-forget: persistence failures don't block rendering.
      // CRDT opId dedup guarantees idempotent re-apply on next session.
      unawaited(() async {
        for (final op in ops) {
          try {
            await persistence.insertOp(_canvasId, op);
            await persistence.markBroadcast(op.opId);
          } catch (_) {}
        }
      }());
    }
  }

  Future<void> _drainCRDTOutbox() async {
    final persistence = _crdtPersistence;
    final engine = _realtimeEngine;
    if (persistence == null || engine == null) return;

    final pending = await persistence.unsentOps(_canvasId);
    for (final entry in pending) {
      final delivered = await engine.broadcastCRDTOperation(entry.operation);
      if (delivered) {
        await persistence.markBroadcast(entry.operation.opId);
      }
      // If delivery still fails, leave sent_at NULL — the next periodic
      // drain (or reconnect drain) tries again with the same op.
    }
    // Re-sync the badge with reality after the drain (also corrects any
    // accumulated drift from skipped ++/-- in error paths).
    final remaining = await persistence.unsentOps(_canvasId);
    if (mounted) _crdtPendingOpsNotifier.value = remaining.length;
  }

  /// 📜 Pull every op the local CRDT graph hasn't seen from the cloud
  /// `operations_log`. Runs once at canvas open, after local rehydration,
  /// before the realtime engine starts emitting live updates — bridges
  /// the "I was offline while a teammate edited" gap that the live
  /// Supabase Broadcast channel can't fill (it has no buffering).
  ///
  /// The high-water HLC is the highest (ts_ms, counter, peerId) the local
  /// graph already knows about. We pass it to `cloudAdapter.opsSince`
  /// which returns ops strictly newer in HLC ordering. Each is replayed
  /// through the applier inside `runSilently` so it doesn't bounce back
  /// out via the observer.
  Future<void> _catchUpFromCloudOpsLog(
    CRDTSceneGraph crdt,
    String canvasId,
  ) async {
    final cloud = _config.cloudAdapter;
    final observer = _crdtMutationObserver;
    final applier = _crdtApplier;
    if (cloud == null || observer == null || applier == null) return;

    try {
      // Best-effort cursor: the local HLC clock advances on every applied
      // op (local + remote), so [localClock] is the highest HLC we've
      // seen. opsSince(cursor) returns ops STRICTLY greater than the
      // cursor — the CRDT's opId dedup absorbs any rare duplicates from
      // an out-of-order frontier. This is intentionally not a vector-
      // clock-aware cursor: a per-peer frontier would catch every hole
      // but doubles the catch-up complexity. Acceptable for v1; the
      // backend op log is bounded in practice (~100KB per canvas).
      final hwm = crdt.localClock;
      final raw = await cloud.opsSince(
        canvasId: canvasId,
        tsMs: hwm.physicalMs,
        counter: hwm.counter,
        peerIdTieBreak: hwm.peerId,
      );
      if (raw.isEmpty) return;
      observer.runSilently(() {
        for (final entry in raw) {
          try {
            applier.applyRemote(CRDTOperation.fromJson(entry));
          } catch (_) {
            // Tolerate malformed rows — the live broadcast path will
            // re-deliver if any corresponding live op still flows.
          }
        }
      });
    } catch (_) {
      // Catch-up is best-effort. If cloud is unavailable the live
      // broadcast + outbox drain still cover the in-session case;
      // the next canvas open will retry.
    }
  }

  /// 💾 Rotate the CRDT snapshot when the op-log grows past
  /// [_kCrdtSnapshotEveryOps]. The snapshot becomes the new baseline used by
  /// the hybrid rehydration path on the next process start, capping replay
  /// time regardless of total session length.
  ///
  /// We never delete prior ops here — peers that haven't yet observed them
  /// rely on the log surviving until they catch up. A future GC pass can
  /// trim ops whose HLC ≤ the most recent snapshot AND whose `sent_at` is
  /// non-null for every active peer; that's a separate vector-clock-aware
  /// step, deliberately out of scope for this rotation.
  Future<void> _maybeRotateCrdtSnapshot() async {
    final persistence = _crdtPersistence;
    final crdt = _crdtSceneGraph;
    if (persistence == null || crdt == null) return;

    final count = await persistence.opCount(_canvasId);
    if (count < _kCrdtSnapshotEveryOps) return;

    await persistence.saveSnapshot(
      canvasId: _canvasId,
      graph: crdt,
      hlc: crdt.localClock,
    );
  }

  // ─── Recording Sync ────────────────────────────────────────────────

  /// 🎤 Apply a remotely-added voice recording.
  ///
  /// Downloads the audio file from cloud storage, persists it locally,
  /// and adds it to the recordings list.
  ///
  /// Improvements:
  ///   #2 — Download placeholder SnackBar with progress
  ///   #3 — Gzip decompression (if compressed flag is set)
  ///   #4 — Deduplication (skip if already downloaded)
  ///   #7 — Author name in notification
  void _applyRemoteRecordingAdded(Map<String, dynamic> payload) async {
    try {
      final recordingId = payload['recordingId'] as String?;
      final audioAssetKey = payload['audioAssetKey'] as String?;
      final noteTitle = payload['noteTitle'] as String?;
      final durationMs = (payload['durationMs'] as num?)?.toInt() ?? 0;
      final recordingType = payload['recordingType'] as String? ?? 'audio_only';
      final senderName = payload['senderName'] as String?;
      final isCompressed = payload['compressed'] as bool? ?? false;
      final fileSize = (payload['fileSize'] as num?)?.toInt();
      final waveform =
          (payload['waveform'] as List?)
              ?.cast<num>()
              .map((e) => e.toDouble())
              .toList();

      if (recordingId == null || audioAssetKey == null) return;

      // 🔒 #3 Validation — sanitize IDs to prevent path traversal / injection
      final idPattern = RegExp(r'^[a-zA-Z0-9_\-]+$');
      if (!idPattern.hasMatch(recordingId) ||
          !idPattern.hasMatch(audioAssetKey)) {
        return;
      }
      if (recordingId.length > 128 || audioAssetKey.length > 256) {
        return;
      }

      // 🔄 #4 Deduplication — skip if recording already exists locally
      final existingPath = _savedRecordings.where(
        (p) => p.contains('fluera_recording_$recordingId'),
      );
      if (existingPath.isNotEmpty) {
        return;
      }

      // 📥 #2 Show download placeholder notification
      final authorLabel = senderName ?? 'A collaborator';
      final titleLabel = noteTitle ?? 'recording';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '🎤 Downloading "$titleLabel" from $authorLabel'
                    '${fileSize != null ? ' (${(fileSize / 1024).toStringAsFixed(0)} KB)' : ''}...',
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 10),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

      // ⚡ Launch strokes download in parallel with audio (fire-and-forget Future)
      final strokesAssetKey = payload['strokesAssetKey'] as String?;
      Future<List<SyncedStroke>>? strokesFuture;
      if (strokesAssetKey != null && _syncEngine != null) {
        strokesFuture = _downloadSyncedStrokes(strokesAssetKey);
      }

      // Download audio bytes from cloud (#1 chunked, #3 exponential backoff, #8 progress)
      Uint8List? audioBytes;
      if (_syncEngine != null) {
        for (int attempt = 1; attempt <= 3; attempt++) {
          try {
            // #8 Show download progress
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('📥 Download attempt $attempt/3...'),
                  duration: const Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }

            audioBytes = await _syncEngine!.adapter.downloadAsset(
              _canvasId,
              audioAssetKey,
            );

            // #1 Chunked download — check if response is a manifest
            if (audioBytes != null && audioBytes.isNotEmpty) {
              try {
                final manifestStr = String.fromCharCodes(audioBytes);
                if (manifestStr.startsWith('{"chunks":')) {
                  final manifestJson = Map<String, dynamic>.from(
                    json.decode(manifestStr) as Map,
                  );
                  final totalChunks = manifestJson['chunks'] as int;

                  // Download and reassemble all chunks
                  final chunks = <Uint8List>[];
                  for (int i = 0; i < totalChunks; i++) {
                    final chunkKey = '${audioAssetKey}_chunk_$i';
                    final chunkData = await _syncEngine!.adapter.downloadAsset(
                      _canvasId,
                      chunkKey,
                    );
                    if (chunkData != null && chunkData.isNotEmpty) {
                      chunks.add(chunkData);
                    }
                  }

                  // Concatenate chunks into final audio
                  if (chunks.isNotEmpty) {
                    final totalSize = chunks.fold<int>(
                      0,
                      (sum, c) => sum + c.length,
                    );
                    final assembled = Uint8List(totalSize);
                    int offset = 0;
                    for (final chunk in chunks) {
                      assembled.setRange(offset, offset + chunk.length, chunk);
                      offset += chunk.length;
                    }
                    audioBytes = assembled;
                  }
                }
              } catch (_) {
                // Not a manifest — treat as normal audio data
              }
            }

            if (audioBytes != null && audioBytes.isNotEmpty) break;
          } catch (e) {
            if (attempt < 3) {
              // #3 Exponential backoff: 1s, 2s, 4s
              final delay = Duration(seconds: 1 << (attempt - 1));
              await Future<void>.delayed(delay);
            }
          }
        }
      }

      if (audioBytes == null || audioBytes.isEmpty) {
        _pendingRecordingRetries.add(payload);
        return;
      }

      // Non-null from here on
      Uint8List finalBytes = audioBytes;

      // 🗄️ #3 Decompress gzip if sender flagged it as compressed
      //    #6 Offload to Isolate for non-blocking main thread
      if (isCompressed) {
        try {
          finalBytes = await compute((_) {
            return Uint8List.fromList(GZipCodec().decode(finalBytes));
          }, null);
        } catch (e) {
          // Fallback: use bytes as-is (might not be compressed)
        }
      }

      // 📊 #6 Log received waveform preview if present
      if (waveform != null && waveform.isNotEmpty) {
      }

      // Persist audio to local documents directory
      final docsDir = await getSafeDocumentsDirectory();
      if (docsDir == null) return;

      final recordingsDir = Directory('${docsDir.path}/recordings');
      if (!await recordingsDir.exists()) {
        await recordingsDir.create(recursive: true);
      }

      final localPath =
          '${recordingsDir.path}/fluera_recording_$recordingId.m4a';
      if (!kIsWeb) {
        await File(localPath).writeAsBytes(finalBytes, flush: true);
      }

      // Save to SQLite
      if (RecordingStorageService.instance.isInitialized) {
        // ⚡ Await strokes (likely already finished while audio was downloading)
        final syncedStrokes = await strokesFuture ?? const <SyncedStroke>[];

        final persistable = SynchronizedRecording(
          id: recordingId,
          audioPath: localPath,
          totalDuration: Duration(milliseconds: durationMs),
          startTime: DateTime.now(),
          syncedStrokes: syncedStrokes,
          canvasId: _canvasId,
          noteTitle: noteTitle,
          recordingType: recordingType,
        );
        await RecordingStorageService.instance.saveRecording(persistable);
      }

      // Add to UI
      if (mounted) {
        // Clear the download SnackBar
        ScaffoldMessenger.of(context).hideCurrentSnackBar();

        setState(() {
          if (!_savedRecordings.contains(localPath)) {
            _savedRecordings.add(localPath);
          }
        });

        // 👤 #7 Show author name in confirmation
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🎤 "$titleLabel" received from $authorLabel'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }


      // 📳 Haptic feedback
      HapticFeedback.lightImpact();

      // 🔔 #1 Increment badge counter for new recordings
      _newRecordingCount++;
    } catch (e) {
    }
  }

  /// 🎤 Handle remote recording removal.
  void _applyRemoteRecordingRemoved(Map<String, dynamic> payload) {
    try {
      final recordingId = payload['recordingId'] as String?;
      if (recordingId == null) return;

      // Find the recording by ID in synced recordings
      final matchIndex = _savedRecordings.indexWhere(
        (path) => path.contains('fluera_recording_$recordingId'),
      );

      if (matchIndex != -1) {
        final removedPath = _savedRecordings[matchIndex];
        setState(() {
          _savedRecordings.removeAt(matchIndex);
        });
        _syncedRecordings.removeWhere((r) => r.id == recordingId);

        // Delete from SQLite
        if (RecordingStorageService.instance.isInitialized) {
          RecordingStorageService.instance
              .deleteRecording(recordingId)
              .catchError((_) => 0);
        }

        // 🧹 Clean up cloud assets (audio + strokes)
        _syncEngine?.adapter
            .deleteAsset(_canvasId, 'recording_$recordingId')
            .catchError((_) {});
        _syncEngine?.adapter
            .deleteAsset(_canvasId, 'strokes_$recordingId')
            .catchError((_) {});

        // Delete local file
        if (!kIsWeb) {
          File(removedPath).delete().catchError((_) => File(removedPath));
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('🎤 A collaborator removed a recording'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

    } catch (e) {
    }
  }

  /// 🎤 Handle remote recording rename (#4).
  void _applyRemoteRecordingRenamed(Map<String, dynamic> payload) {
    try {
      final recordingId = payload['recordingId'] as String?;
      final newTitle = payload['newTitle'] as String?;
      if (recordingId == null || newTitle == null) return;

      // Update in synced recordings
      final idx = _syncedRecordings.indexWhere((r) => r.id == recordingId);
      if (idx != -1) {
        // Update the recording's noteTitle
        final old = _syncedRecordings[idx];
        _syncedRecordings[idx] = SynchronizedRecording(
          id: old.id,
          audioPath: old.audioPath,
          totalDuration: old.totalDuration,
          startTime: old.startTime,
          syncedStrokes: old.syncedStrokes,
          canvasId: old.canvasId,
          noteTitle: newTitle,
          recordingType: old.recordingType,
        );

        // Persist rename to SQLite
        if (RecordingStorageService.instance.isInitialized) {
          RecordingStorageService.instance
              .saveRecording(_syncedRecordings[idx])
              .catchError((_) => null);
        }
      }

      if (mounted) {
        setState(() {}); // Refresh UI
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🎤 Recording renamed to "$newTitle"'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

    } catch (e) {
    }
  }

  // ─── Recording Pin Remote Handlers ──────────────────────────────────

  /// 📌 Apply a remote recording pin addition.
  void _applyRemoteRecordingPinAdded(Map<String, dynamic> payload) {
    try {
      final safePayload = _deepCastMap(payload);
      final pin = RecordingPin.fromJson(safePayload);

      // Avoid duplicates
      if (_recordingPins.any((p) => p.id == pin.id)) return;

      if (mounted) {
        setState(() {
          _recordingPins.add(pin);
        });
      }

    } catch (e) {
    }
  }

  /// 📌 Apply a remote recording pin removal.
  void _applyRemoteRecordingPinRemoved(Map<String, dynamic> payload) {
    try {
      final pinId = payload['id'] as String?;
      if (pinId == null) return;

      if (mounted) {
        setState(() {
          _recordingPins.removeWhere((p) => p.id == pinId);
        });
      }

    } catch (e) {
    }
  }

  /// 📌 Broadcast a recording pin addition to collaborators.
  void _broadcastPinAdded(RecordingPin pin) {
    _realtimeEngine?.broadcastRecordingPinAdded(pin.toJson());
  }

  /// 📌 Broadcast a recording pin removal to collaborators.
  void _broadcastPinRemoved(String pinId) {
    _realtimeEngine?.broadcastRecordingPinRemoved(pinId);
  }

  // ─── Recording Retry Queue (#5) ─────────────────────────────────────

  /// 🔄 Queue of failed recording downloads to retry on reconnect.
  /// 🔄 Queue of failed recording downloads to retry on reconnect.
  static final List<Map<String, dynamic>> _pendingRecordingRetries = [];

  /// 🔔 Badge counter for new recordings received from collaborators (#1).
  static int _newRecordingCount = 0;

  /// 🎨 Download and decompress synced strokes from cloud asset.
  /// Returns empty list on failure (graceful fallback to audio-only).
  Future<List<SyncedStroke>> _downloadSyncedStrokes(String assetKey) async {
    try {
      final bytes = await _syncEngine!.adapter.downloadAsset(
        _canvasId,
        assetKey,
      );
      if (bytes == null || bytes.isEmpty) return const [];

      // Decompress + parse in Isolate (non-blocking)
      final parsed = await compute((_) {
        final decompressed = GZipCodec().decode(bytes);
        final jsonStr = utf8.decode(decompressed);
        return jsonDecode(jsonStr) as List;
      }, null);

      final strokes = <SyncedStroke>[];
      for (final raw in parsed) {
        strokes.add(
          SyncedStroke.fromJson(Map<String, dynamic>.from(raw as Map)),
        );
      }
      return strokes;
    } catch (e) {
      return const [];
    }
  }

  /// 🔄 Retry all pending recording downloads with exponential backoff (#3).
  Future<void> _retryPendingRecordingDownloads() async {
    if (_pendingRecordingRetries.isEmpty) return;

    final pending = List<Map<String, dynamic>>.from(_pendingRecordingRetries);
    _pendingRecordingRetries.clear();

    for (int i = 0; i < pending.length; i++) {
      final payload = pending[i];
      // #3 Exponential backoff between retries: 500ms, 1s, 2s, 4s...
      if (i > 0) {
        final delay = Duration(milliseconds: 500 * (1 << i.clamp(0, 4)));
        await Future<void>.delayed(delay);
      }
      _applyRemoteRecordingAdded(payload);
    }
  }
}

// PdfLoadingPlaceholder moved to
// `lib/src/rendering/canvas/collab_overlay_painters.dart` as public
// [PdfLoadingPlaceholder] so [FlueraCanvasView] can render the same
// loading FX. Same library so all references inside the screen work via
// the public name.
