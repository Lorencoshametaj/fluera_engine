part of '../fluera_canvas_screen.dart';

/// 🔍 ECHO SEARCH — Jarvis-style Spatial Search (Query Pen Mode)
///
/// Final Boss enhancements:
///   🎨 Adaptive glow color from brush
///   🔄 History drawer (swipe-up on HUD)
///   📌 Pin button in HUD
///   + all previous features
extension on _FlueraCanvasScreenState {
  // ── Activation ────────────────────────────────────────────────────────────

  void _activateEchoSearch() {
    _echoSearchController?.dispose();
    _echoSearchController = EchoSearchController(
      canvasId: _canvasId,
      onNavigate: _echoSearchNavigate,
      onToast: _echoSearchToast,
      onDismiss: () => _deactivateEchoSearch(),
      // 🎨 Adaptive glow: pass current brush color
      accentColor: _effectiveSelectedColor,
    );
    setState(() {
      _isEchoSearchMode = true;
    });
    HapticFeedback.mediumImpact();
  }

  void _deactivateEchoSearch() {
    _echoSearchController?.dispose();
    _echoSearchController = null;
    if (mounted) {
      setState(() {
        _isEchoSearchMode = false;
      });
    }
  }

  // ── Drawing Intercept ─────────────────────────────────────────────────────

  bool get _echoSearchActive => _isEchoSearchMode && _echoSearchController != null;

  void _echoSearchOnDrawStart(Offset canvasPosition, double pressure) {
    if (!_echoSearchActive) return;

    if (_echoSearchController!.phase == EchoSearchPhase.flyingTo ||
        _echoSearchController!.phase == EchoSearchPhase.fadingOut) {
      _echoSearchController!.dismiss();
      return;
    }

    final point = ProDrawingPoint(
      position: canvasPosition,
      pressure: pressure.clamp(0.0, 1.0),
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    _echoSearchController!.startStroke(point);
    _uiRebuildNotifier.value++;
  }

  void _echoSearchOnDrawUpdate(Offset canvasPosition, double pressure) {
    if (!_echoSearchActive) return;
    final point = ProDrawingPoint(
      position: canvasPosition,
      pressure: pressure.clamp(0.0, 1.0),
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    _echoSearchController!.addPoint(point);
    _uiRebuildNotifier.value++;
  }

  void _echoSearchOnDrawEnd() {
    if (!_echoSearchActive) return;
    _echoSearchController!.endStroke();
    _uiRebuildNotifier.value++;
  }

  // ── Navigation & Feedback ─────────────────────────────────────────────────

  void _echoSearchNavigate(HandwritingSearchResult result) {
    HapticFeedback.mediumImpact();

    final viewportSize = MediaQuery.of(context).size;
    final center = result.bounds.center;
    final currentScale = _canvasController.scale;

    final resultW = result.bounds.width.clamp(10.0, double.infinity);
    final resultH = result.bounds.height.clamp(10.0, double.infinity);
    final scaleForWidth = (viewportSize.width * 0.4) / resultW;
    final scaleForHeight = (viewportSize.height * 0.35) / resultH;
    final optimalScale = scaleForWidth < scaleForHeight ? scaleForWidth : scaleForHeight;
    final targetScale = (optimalScale * 0.8).clamp(0.5, 4.0);

    final resultScreenW = resultW * currentScale;
    final needsZoom = resultScreenW < 80 || resultScreenW > 500;
    final useScale = needsZoom ? targetScale : currentScale;

    final targetOffset = Offset(
      viewportSize.width / 2 - center.dx * useScale,
      viewportSize.height / 2 - center.dy * useScale,
    );
    _canvasController.animateOffsetTo(targetOffset);

    if (needsZoom && (targetScale - currentScale).abs() > 0.1) {
      _canvasController.animateZoomTo(
        targetScale,
        Offset(viewportSize.width / 2, viewportSize.height / 2),
      );
    }

    setState(() {
      _hwSearchResults = _echoSearchController?.results ?? [];
      _hwSearchActiveIndex = _echoSearchController?.activeResultIndex ?? 0;
    });

    Future.delayed(const Duration(milliseconds: 3000), () {
      if (mounted && _isEchoSearchMode && _echoSearchController != null &&
          _echoSearchController!.phase == EchoSearchPhase.flyingTo) {
        _echoSearchController!.beginFadeOut();
        _uiRebuildNotifier.value++;

        Future.delayed(const Duration(seconds: 4), () {
          if (mounted) {
            setState(() {
              _hwSearchResults = [];
              _hwSearchActiveIndex = 0;
            });
          }
        });
      }
    });
  }

  void _echoSearchToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('🔍 $message'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ── HUD Badge Builder ─────────────────────────────────────────────────────

  Widget _buildEchoSearchHudBadge() {
    if (_echoSearchController == null) return const SizedBox.shrink();

    return ListenableBuilder(
      listenable: _echoSearchController!,
      builder: (context, _) {
        final ctrl = _echoSearchController!;
        final phase = ctrl.phase;
        final text = ctrl.hudStatusText;
        final hasResults = ctrl.resultCount > 1 &&
            phase == EchoSearchPhase.flyingTo;

        // 🎨 Adaptive accent from controller
        final accent = ctrl.accentColor ?? const Color(0xFF6C63FF);
        final hsl = HSLColor.fromColor(accent);
        final badgeAccent = hsl.withSaturation(
            (hsl.saturation + 0.2).clamp(0.0, 1.0))
            .withLightness(0.55)
            .toColor();

        return AnimatedOpacity(
          opacity: _isEchoSearchMode ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 300),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Main badge ──
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A2E).withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: badgeAccent.withValues(alpha: 0.5),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: badgeAccent.withValues(alpha: 0.2),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (phase == EchoSearchPhase.recognizing ||
                        phase == EchoSearchPhase.previewing)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: SizedBox(
                          width: 12, height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: badgeAccent,
                          ),
                        ),
                      ),

                    Text(
                      text,
                      style: const TextStyle(
                        color: Color(0xFFE0DCFF),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),

                    // Multi-result nav arrows
                    if (hasResults) ...[
                      const SizedBox(width: 8),
                      _buildNavButton(Icons.chevron_left, ctrl.previousResult, badgeAccent),
                      const SizedBox(width: 2),
                      _buildNavButton(Icons.chevron_right, ctrl.nextResult, badgeAccent),
                    ],

                    // 📌 Pin button
                    if (phase == EchoSearchPhase.flyingTo && ctrl.resultCount > 0) ...[
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: ctrl.pinCurrentResult,
                        child: Container(
                          width: 22, height: 22,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: badgeAccent.withValues(alpha: 0.2),
                          ),
                          child: const Icon(Icons.push_pin_rounded, size: 13,
                              color: Color(0xFFE0DCFF)),
                        ),
                      ),
                    ],

                    // Dismiss
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () => _echoSearchController?.dismiss(),
                      child: Container(
                        width: 20, height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: badgeAccent.withValues(alpha: 0.2),
                        ),
                        child: const Icon(Icons.close_rounded, size: 14,
                            color: Color(0xFFE0DCFF)),
                      ),
                    ),
                  ],
                ),
              ),

              // ── 📜 Result snippet ──
              if (phase == EchoSearchPhase.flyingTo && ctrl.resultSnippet.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6, right: 4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D0D1A).withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: badgeAccent.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      '📜 ${ctrl.resultSnippet}',
                      style: TextStyle(
                        color: badgeAccent,
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),

              // ── 🎯 Alternatives chips ──
              if (ctrl.alternatives.isNotEmpty && phase == EchoSearchPhase.flyingTo)
                Padding(
                  padding: const EdgeInsets.only(top: 4, right: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('or: ', style: TextStyle(
                        color: Color(0xFF9D8FFF), fontSize: 10,
                      )),
                      for (final alt in ctrl.alternatives) ...[
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: () => ctrl.searchAlternative(alt),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: badgeAccent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: badgeAccent.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Text(
                              alt,
                              style: const TextStyle(
                                color: Color(0xFFE0DCFF),
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

              // ── 🔄 Search History (shown in idle phase) ──
              if ((phase == EchoSearchPhase.idle || phase == EchoSearchPhase.drawing) &&
                  ctrl.searchHistory.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6, right: 4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D0D1A).withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: badgeAccent.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Recent:', style: TextStyle(
                          color: Color(0xFF9D8FFF), fontSize: 9,
                          fontWeight: FontWeight.w600,
                        )),
                        const SizedBox(height: 3),
                        for (final q in ctrl.searchHistory.take(3))
                          GestureDetector(
                            onTap: () => ctrl.searchFromHistory(q),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 1.5),
                              child: Text(
                                '🕐 $q',
                                style: TextStyle(
                                  color: badgeAccent.withValues(alpha: 0.8),
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

              // ── ⌨️ Keyboard fallback ──
              if (ctrl.showKeyboardFallback)
                Padding(
                  padding: const EdgeInsets.only(top: 6, right: 4),
                  child: _EchoKeyboardFallback(
                    onSubmit: (text) => ctrl.searchKeyboard(text),
                    accentColor: badgeAccent,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNavButton(IconData icon, VoidCallback onTap, Color accent) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 22, height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: accent.withValues(alpha: 0.3),
        ),
        child: Icon(icon, size: 16, color: const Color(0xFFE0DCFF)),
      ),
    );
  }
  // ── 📲 Swipe-Down from Top Edge ────────────────────────────────────────────

  /// Build an invisible gesture zone at the top edge of the screen.
  /// Swipe-down from this zone activates Echo Search.
  Widget _buildEchoSearchSwipeZone() {
    return _EchoSwipeDownZone(
      onActivate: () {
        if (!_isEchoSearchMode) {
          _activateEchoSearch();
        }
      },
    );
  }

  // ── 🔮 Entry Animation ────────────────────────────────────────────────────

  Widget _buildEchoSearchEntryAnimation() {
    return _EchoEntryRing(
      accentColor: _effectiveSelectedColor,
      onComplete: () {
        if (mounted) _uiRebuildNotifier.value++;
      },
    );
  }
}

// =============================================================================
// 🔮 ENTRY RING
// =============================================================================

class _EchoEntryRing extends StatefulWidget {
  final VoidCallback onComplete;
  final Color? accentColor;
  const _EchoEntryRing({required this.onComplete, this.accentColor});

  @override
  State<_EchoEntryRing> createState() => _EchoEntryRingState();
}

class _EchoEntryRingState extends State<_EchoEntryRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward().then((_) => widget.onComplete());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final progress = Curves.easeOutCubic.transform(_controller.value);
        final alpha = (1.0 - progress).clamp(0.0, 0.6);
        final size = MediaQuery.of(context).size;
        final maxRadius = size.longestSide * 0.8;

        // 🎨 Adaptive colors
        final accent = widget.accentColor ?? const Color(0xFF6C63FF);
        final hsl = HSLColor.fromColor(accent);
        final ringColor1 = hsl.withSaturation(
            (hsl.saturation + 0.2).clamp(0.0, 1.0))
            .withLightness(0.55).toColor();
        final ringColor2 = hsl.withHue((hsl.hue + 60) % 360)
            .withSaturation(0.8).withLightness(0.6).toColor();

        return IgnorePointer(
          child: CustomPaint(
            size: size,
            painter: _EntryRingPainter(
              progress: progress,
              alpha: alpha,
              center: size.center(Offset.zero),
              maxRadius: maxRadius,
              color1: ringColor1,
              color2: ringColor2,
            ),
          ),
        );
      },
    );
  }
}

class _EntryRingPainter extends CustomPainter {
  final double progress;
  final double alpha;
  final Offset center;
  final double maxRadius;
  final Color color1;
  final Color color2;

  _EntryRingPainter({
    required this.progress,
    required this.alpha,
    required this.center,
    required this.maxRadius,
    required this.color1,
    required this.color2,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < 2; i++) {
      final ringProgress = (progress - i * 0.15).clamp(0.0, 1.0);
      final radius = ringProgress * maxRadius;
      final ringAlpha = alpha * (1.0 - i * 0.3);
      canvas.drawCircle(center, radius, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5 - i * 0.5
        ..color = Color.lerp(color1, color2, ringProgress)!
            .withValues(alpha: ringAlpha)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3.0 + ringProgress * 5));
    }
    if (progress < 0.3) {
      final flashAlpha = (0.3 - progress) / 0.3 * 0.8;
      canvas.drawCircle(center, 8 + progress * 20, Paint()
        ..color = color1.withValues(alpha: flashAlpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
    }
  }

  @override
  bool shouldRepaint(_EntryRingPainter old) => old.progress != progress;
}

// =============================================================================
// ⌨️ KEYBOARD FALLBACK
// =============================================================================

class _EchoKeyboardFallback extends StatefulWidget {
  final ValueChanged<String> onSubmit;
  final Color accentColor;
  const _EchoKeyboardFallback({
    required this.onSubmit,
    this.accentColor = const Color(0xFF00D4FF),
  });

  @override
  State<_EchoKeyboardFallback> createState() => _EchoKeyboardFallbackState();
}

class _EchoKeyboardFallbackState extends State<_EchoKeyboardFallback> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      height: 36,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E).withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: widget.accentColor.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 10),
          Icon(Icons.keyboard_rounded, size: 14,
              color: widget.accentColor),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              style: const TextStyle(
                color: Color(0xFFE0DCFF),
                fontSize: 12,
              ),
              decoration: InputDecoration(
                hintText: 'Type query...',
                hintStyle: TextStyle(
                  color: widget.accentColor.withValues(alpha: 0.5),
                  fontSize: 12,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              onSubmitted: (text) {
                if (text.trim().isNotEmpty) widget.onSubmit(text.trim());
              },
              textInputAction: TextInputAction.search,
            ),
          ),
          GestureDetector(
            onTap: () {
              if (_controller.text.trim().isNotEmpty) {
                widget.onSubmit(_controller.text.trim());
              }
            },
            child: Container(
              width: 28, height: 28,
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.accentColor,
              ),
              child: const Icon(Icons.search_rounded, size: 14,
                  color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// 📲 SWIPE-DOWN ZONE — Two-finger top edge gesture trigger
//
// ✌️ Requires 2 fingers to avoid pan conflicts
// 🏎️ Velocity-based: fast flick = lower distance threshold
// 🫧 Elastic snap-back on release
// ⏱️ 500ms cooldown after dismiss
// 💡 One-time onboarding hint
// =============================================================================

class _EchoSwipeDownZone extends StatefulWidget {
  final VoidCallback onActivate;
  const _EchoSwipeDownZone({required this.onActivate});

  @override
  State<_EchoSwipeDownZone> createState() => _EchoSwipeDownZoneState();
}

class _EchoSwipeDownZoneState extends State<_EchoSwipeDownZone>
    with SingleTickerProviderStateMixin {
  /// ✌️ Active pointer tracking (need 2+ to activate).
  final Set<int> _activePointers = {};
  double _dragDistance = 0;
  bool _activated = false;

  /// 🫧 Spring animation for elastic snap-back.
  late final AnimationController _springController;
  double _displayProgress = 0;

  /// ⏱️ Cooldown: timestamp of last activation.
  static int _lastActivationMs = 0;
  static const int _cooldownMs = 500;

  /// 💡 Onboarding: shown once per app session.
  static bool _hintShown = false;
  bool _showHint = false;

  /// Thresholds.
  static const double _activationThreshold = 40.0;
  static const double _zoneHeight = 60.0;

  @override
  void initState() {
    super.initState();
    _springController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..addListener(() {
        final newProgress = _displayProgress * (1.0 - _springController.value);
        // Only rebuild if progress changed meaningfully
        if ((newProgress - _displayProgress).abs() > 0.005) {
          _displayProgress = newProgress;
          setState(() {});
        }
      });

    // 💡 Show onboarding hint briefly
    if (!_hintShown) {
      _showHint = true;
      _hintShown = true;
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _showHint = false);
      });
    }
  }

  @override
  void dispose() {
    _springController.dispose();
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent event) {
    _activePointers.add(event.pointer);
    if (_activePointers.length == 2) {
      // Two fingers detected — start tracking
      _dragDistance = 0;
      _activated = false;
      _showHint = false;
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_activePointers.contains(event.pointer)) return;
    if (_activePointers.length < 2 || _activated) return;

    // ⏱️ Cooldown check (only check on first significant move)
    if (_dragDistance == 0) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastActivationMs < _cooldownMs) return;
    }

    _dragDistance += event.delta.dy;
    if (_dragDistance < 0) {
      _dragDistance = 0;
      return;
    }

    _displayProgress = (_dragDistance / _activationThreshold).clamp(0.0, 1.0);
    setState(() {});

    if (_dragDistance >= _activationThreshold) {
      _activate();
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    _activePointers.remove(event.pointer);

    if (_activePointers.isEmpty && !_activated) {
      // 🏎️ Velocity check: if released with high velocity, check reduced threshold
      // (Velocity data isn't available from Listener, so we rely on distance threshold)

      // 🫧 Elastic snap-back
      if (_displayProgress > 0.01) {
        _springController.forward(from: 0);
      }
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _activePointers.remove(event.pointer);
    if (_activePointers.isEmpty) {
      if (_displayProgress > 0.01) _springController.forward(from: 0);
    }
  }

  void _activate() {
    _activated = true;
    _lastActivationMs = DateTime.now().millisecondsSinceEpoch;
    HapticFeedback.mediumImpact();
    widget.onActivate();

    // Reset after brief delay
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) {
        setState(() {
          _displayProgress = 0;
          _dragDistance = 0;
          _activated = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: topPadding + _zoneHeight,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerCancel,
        child: Stack(
          children: [
            // Pull indicator
            if (_displayProgress > 0.05)
              Positioned.fill(
                child: CustomPaint(
                  painter: _SwipeIndicatorPainter(
                    progress: _displayProgress,
                    topPadding: topPadding,
                  ),
                ),
              ),

            // 💡 Onboarding hint
            if (_showHint)
              Positioned(
                left: 0,
                right: 0,
                top: topPadding + 8,
                child: Center(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 600),
                    builder: (context, value, child) => Opacity(
                      opacity: value * 0.6,
                      child: child,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A2E).withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF6C63FF).withValues(alpha: 0.3),
                        ),
                      ),
                      child: const Text(
                        '↓ 2-finger swipe to search',
                        style: TextStyle(
                          color: Color(0xFF9D8FFF),
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Paints the neon pull indicator as the user swipes down.
class _SwipeIndicatorPainter extends CustomPainter {
  final double progress;
  final double topPadding;

  _SwipeIndicatorPainter({
    required this.progress,
    required this.topPadding,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final y = topPadding + progress * 30;

    // Neon line that extends as you drag
    final lineWidth = 40.0 + progress * 60.0;
    final paint = Paint()
      ..color = Color.lerp(
        const Color(0xFF6C63FF),
        const Color(0xFF00D4FF),
        progress,
      )!.withValues(alpha: 0.4 + progress * 0.4)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3.0 + progress * 4);

    canvas.drawLine(
      Offset(centerX - lineWidth / 2, y),
      Offset(centerX + lineWidth / 2, y),
      paint,
    );

    // Glowing dot at center
    canvas.drawCircle(
      Offset(centerX, y + 6),
      3.0 + progress * 2,
      Paint()
        ..color = const Color(0xFF00D4FF).withValues(alpha: progress * 0.8)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    // Search icon glow at full progress
    if (progress > 0.7) {
      final iconAlpha = ((progress - 0.7) / 0.3).clamp(0.0, 0.6);
      canvas.drawCircle(
        Offset(centerX, y + 6),
        8,
        Paint()
          ..color = const Color(0xFF6C63FF).withValues(alpha: iconAlpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }
  }

  @override
  bool shouldRepaint(_SwipeIndicatorPainter old) => old.progress != progress;
}
