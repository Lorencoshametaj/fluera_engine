part of '../fluera_canvas_screen.dart';

// ═══════════════════════════════════════
// 🤝 P2P Collaboration (Passo 7)
//
// Manages P2P session lifecycle in the canvas:
//   - Session creation/joining via FlueraP2PConnector
//   - Mode selection (Visit/Teaching/Duel)
//   - Overlay rendering (ghost cursor, laser, markers)
//   - Toolbar button + deep link handling
//
// The connector is injected via FlueraCanvasConfig.p2pConnector.
// ═══════════════════════════════════════

extension P2PSessionExtension on _FlueraCanvasScreenState {
  // ── State (static maps for extension compatibility) ───────────────
  static final Map<int, CanvasRasterizer?> _rasterizers = {};
  // ── Accessor ─────────────────────────────────────────────────────────

  /// Get the P2P connector from config (null = P2P not configured).
  FlueraP2PConnector? get _p2pConnector => _config.p2pConnector;

  /// Whether P2P is available (connector injected).
  bool get _isP2PAvailable => _p2pConnector != null;

  /// Whether a P2P session is currently active.
  bool get _isP2PActive =>
      _p2pConnector != null && _p2pConnector!.roomId != null;

  /// Whether fully connected.
  bool get _isP2PConnected =>
      _p2pConnector != null && _p2pConnector!.isConnected;

  // ── Lifecycle ───────────────────────────────────────────────────────

  /// Initialize P2P listeners when entering the canvas.
  ///
  /// Called from initState after config is ready.
  void initP2PSession() {
    final connector = _p2pConnector;
    if (connector == null) return;
    connector.addListener(_onP2PChanged);
  }

  /// Show the invite sheet (host mode — create session).
  void showP2PInviteSheet() async {
    final connector = _p2pConnector;
    if (connector == null) {
      _showP2PUnavailableToast();
      return;
    }

    // Create the session first to get a real room ID.
    try {
      final roomId = await connector.createSession();
      if (!mounted) return;

      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: const Color(0xFF1E1E2E),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => P2PInviteSheet(
          roomId: roomId,
          inviteLink: connector.inviteLink ?? 'fluera://collab/$roomId',
          isHost: true,
        ),
      );

      // Wait for peer to join in the background.
      _waitForPeerAndShowMode(connector);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Errore creazione sessione: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// Show the join sheet (guest mode — enter room code).
  void showP2PJoinSheet() {
    if (!_isP2PAvailable) {
      _showP2PUnavailableToast();
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => P2PInviteSheet(
        isHost: false,
        onJoin: (roomIdOrLink) => _joinP2PSession(roomIdOrLink),
      ),
    );
  }

  /// Join a session by room ID or link (called from join sheet or deep link).
  Future<void> _joinP2PSession(String roomIdOrLink) async {
    final connector = _p2pConnector;
    if (connector == null) return;

    try {
      await connector.joinSession(roomIdOrLink);
      _waitForPeerAndShowMode(connector);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Errore join: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// Handle a P2P deep link (called from the host app's deep link handler).
  ///
  /// Usage from host app:
  /// ```dart
  /// // In your deep link handler:
  /// if (P2PConnector.isInviteLink(link)) {
  ///   canvasScreenState.handleP2PDeepLink(link);
  /// }
  /// ```
  void handleP2PDeepLink(String link) {
    final roomId = FlueraP2PConnector.parseInviteLink(link);
    if (roomId != null && _isP2PAvailable) {
      _joinP2PSession(roomId);
    }
  }

  /// Wait for peer connection, then show mode selection.
  Future<void> _waitForPeerAndShowMode(FlueraP2PConnector connector) async {
    try {
      await connector.waitForConnection();
      if (!mounted) return;

      // Connection established → show mode selection.
      final mode = await showP2PModeSelectionSheet(
        peerName:
            connector.engine.session.remotePeer?.displayName ?? 'Peer',
        peerTopic:
            connector.engine.session.remotePeer?.zoneTopic,
      );

      if (mode != null) {
        connector.engine.selectMode(mode);

        // Enable voice for teaching mode.
        if (mode == P2PCollabMode.teaching) {
          connector.setAudioEnabled(true);
        }

        // Start/stop rasterizer based on mode.
        _updateRasterizer(mode);

        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⏱️ Timeout connessione: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// Show mode selection sheet.
  Future<P2PCollabMode?> showP2PModeSelectionSheet({
    required String peerName,
    String? peerTopic,
  }) {
    return showModalBottomSheet<P2PCollabMode>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => P2PModeSelectionSheet(
        peerName: peerName,
        peerTopic: peerTopic,
      ),
    );
  }

  /// End the current P2P session.
  Future<void> endP2PSession() async {
    _stopRasterizer();
    await _p2pConnector?.endSession();
    if (mounted) setState(() {});
  }

  // ── UI Builders (called from _build_ui.dart) ────────────────────────

  /// Build the P2P overlay if active.
  Widget buildP2POverlay() {
    final connector = _p2pConnector;
    if (connector == null || !_isP2PActive) {
      return const SizedBox.shrink();
    }

    return P2PSessionOverlay(
      engine: connector.engine,
      canvasController: _canvasController,
    );
  }

  /// Build the toolbar P2P action button.
  ///
  /// - Tap: invite sheet (or mode selection if already connected)
  /// - Long press: join sheet
  /// - Hidden if P2P not configured in config
  Widget buildP2PToolbarButton() {
    if (!_isP2PAvailable) return const SizedBox.shrink();

    final isActive = _isP2PActive;
    final isConnected = _isP2PConnected;

    return Tooltip(
      message: isActive
          ? (isConnected ? 'Sessione P2P attiva' : 'Connettendo...')
          : 'Collaborazione P2P',
      child: GestureDetector(
        onTap: () {
          if (isConnected) {
            // Already connected → show mode switch or end session.
            _showP2PActiveMenu();
          } else if (isActive) {
            // Connecting — no-op.
          } else {
            showP2PInviteSheet();
          }
        },
        onLongPress: () {
          if (!isActive) {
            showP2PJoinSheet();
          } else if (isConnected) {
            endP2PSession();
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isConnected
                ? const Color(0xFF6A1B9A).withValues(alpha: 0.2)
                : (isActive
                    ? const Color(0xFFFF9800).withValues(alpha: 0.15)
                    : Colors.transparent),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isConnected
                  ? const Color(0xFF6A1B9A).withValues(alpha: 0.4)
                  : Colors.transparent,
              width: 1.0,
            ),
          ),
          child: Icon(
            isConnected
                ? Icons.people
                : (isActive
                    ? Icons.sync
                    : Icons.people_outline),
            size: 22,
            color: isConnected
                ? const Color(0xFF6A1B9A)
                : (isActive
                    ? const Color(0xFFFF9800)
                    : Colors.grey.shade600),
          ),
        ),
      ),
    );
  }

  /// Show a context menu when P2P is active.
  void _showP2PActiveMenu() {
    final connector = _p2pConnector!;
    final peer =
        connector.engine.session.remotePeer?.displayName ?? 'Peer';
    final currentMode = connector.engine.session.activeMode;

    showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1E1E2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                '🤝 Sessione con $peer',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (currentMode != null) ...[
                const SizedBox(height: 4),
                Text(
                  _modeLabel(currentMode),
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ],
              const SizedBox(height: 24),

              // Change mode.
              ListTile(
                leading: const Icon(Icons.swap_horiz, color: Colors.white70),
                title: const Text('Cambia modalità',
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx, 'change_mode');
                },
              ),

              // Toggle voice.
              ListTile(
                leading: Icon(
                  connector.engine.voice.isLocalMuted
                      ? Icons.mic_off
                      : Icons.mic,
                  color: Colors.white70,
                ),
                title: Text(
                  connector.engine.voice.isLocalMuted
                      ? 'Attiva microfono'
                      : 'Disattiva microfono',
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(ctx, 'toggle_voice');
                },
              ),

              const Divider(color: Colors.white12),

              // End session.
              ListTile(
                leading: const Icon(Icons.close, color: Color(0xFFF44336)),
                title: const Text('Termina sessione',
                    style: TextStyle(color: Color(0xFFF44336))),
                onTap: () {
                  Navigator.pop(ctx, 'end');
                },
              ),
            ],
          ),
        ),
      ),
    ).then((action) async {
      if (!mounted || action == null) return;
      switch (action) {
        case 'change_mode':
          final newMode = await showP2PModeSelectionSheet(
            peerName: peer,
          );
          if (newMode != null) {
            connector.engine.selectMode(newMode);
            connector.setAudioEnabled(
                newMode == P2PCollabMode.teaching);
            _updateRasterizer(newMode);
            setState(() {});
          }
        case 'toggle_voice':
          final muted = connector.engine.voice.isLocalMuted;
          connector.setAudioEnabled(muted); // toggle
          setState(() {});
        case 'end':
          await endP2PSession();
      }
    });
  }

  String _modeLabel(P2PCollabMode mode) => switch (mode) {
    P2PCollabMode.visit => '👀 Modalità Visita',
    P2PCollabMode.teaching => '📚 Modalità Insegnamento',
    P2PCollabMode.duel => '⚔️ Modalità Duello',
  };

  // ── Helpers ──────────────────────────────────────────────────────────

  void _showP2PUnavailableToast() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('P2P non configurato — contatta lo sviluppatore'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _onP2PChanged() {
    if (mounted) setState(() {});
  }

  // ── Rasterizer (Visit mode 7a) ───────────────────────────────────

  /// Get/create the rasterizer for this canvas instance.
  CanvasRasterizer? get _rasterizer => _rasterizers[hashCode];

  /// Start rasterizer for Visit mode, stop for other modes.
  void _updateRasterizer(P2PCollabMode mode) {
    if (mode == P2PCollabMode.visit) {
      _startRasterizer();
    } else {
      _stopRasterizer();
    }
  }

  /// Start the canvas rasterizer (Visit mode).
  ///
  /// Captures canvas frames at 720p/10fps and feeds them to any
  /// attached [RasterFrameSink]s (e.g., WebRTC video track).
  void _startRasterizer() {
    if (_rasterizer?.isRunning == true) return;

    final rasterizer = CanvasRasterizer(
      boundaryKey: _canvasRepaintBoundaryKey,
      config: RasterConfig.standard,
    );
    _rasterizers[hashCode] = rasterizer;
    rasterizer.start();
  }

  /// Stop the rasterizer.
  void _stopRasterizer() {
    _rasterizer?.stop();
    _rasterizers.remove(hashCode);
  }

  /// Attach a frame sink to the rasterizer (called by host app's WebRTC layer).
  ///
  /// Usage:
  /// ```dart
  /// canvasState.attachRasterSink(myWebRtcFrameSink);
  /// ```
  void attachRasterSink(RasterFrameSink sink) {
    _rasterizer?.addSink(sink);
  }

  /// Remove a frame sink.
  void detachRasterSink(RasterFrameSink sink) {
    _rasterizer?.removeSink(sink);
  }

  // ── Cleanup ───────────────────────────────────────────────────────

  /// Dispose P2P listeners and rasterizer on canvas exit.
  void disposeP2PSession() {
    _stopRasterizer();
    _p2pConnector?.removeListener(_onP2PChanged);
    // Don't dispose the connector itself — it's owned by the host app config.
  }
}
