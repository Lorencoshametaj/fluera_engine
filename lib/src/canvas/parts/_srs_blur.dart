part of '../fluera_canvas_screen.dart';

/// 🧠 SRS BLUR ON RETURN — Step 6/8 of the cognitive mastery cycle.
///
/// When the student returns to a canvas after time has passed, clusters with
/// overdue SRS cards appear blurred. The student taps to reveal, self-evaluates,
/// and the FSRS scheduler recalculates the interval.
///
/// Integration points:
///   - Called from `_loadSpacedRepetition().then(...)` in initState
///   - Uses `_clusterCache` and `_clusterTextCache` for matching
///   - Updates `_reviewSchedule` via `SrsReviewSession.endSession()`
///   - Renders via `SrsBlurOverlayPainter` in the canvas layer stack
extension SrsBlurOnReturn on _FlueraCanvasScreenState {

  // ── SESSION LIFECYCLE ────────────────────────────────────────────────────

  /// Called after `_loadSpacedRepetition` + `_checkDueForReview` completes.
  /// Waits for clusters to be detected, then starts the blur session.
  void _startSrsBlurSessionIfNeeded() {
    // Guard: only run if we have a review schedule with due items
    final now = DateTime.now();
    final hasDue = _reviewSchedule.entries.any(
      (e) => e.value.nextReview.isBefore(now),
    );
    if (!hasDue) return;

    // Clusters may not be ready yet (depends on stroke density detection).
    // Wait up to 4 seconds with periodic checks.
    int attempts = 0;
    Timer.periodic(const Duration(milliseconds: 500), (timer) {
      attempts++;
      if (!mounted) { timer.cancel(); return; }

      if (_clusterCache.isNotEmpty || attempts >= 8) {
        timer.cancel();
        _initSrsBlurSession();
      }
    });
  }

  /// Initializes the SRS blur session once clusters are available.
  ///
  /// Shows the review type selector (Micro ⚡ vs Deep 🧠) and then
  /// starts the session with the appropriate parameters.
  void _initSrsBlurSession() {
    if (!mounted) return;
    if (_clusterCache.isEmpty) return;
    if (_srsReviewSession.isActive) return; // Already running

    // Count how many clusters would be due before showing the selector.
    final now = DateTime.now();
    int preCount = 0;
    for (final entry in _reviewSchedule.entries) {
      if (entry.value.nextReview.isBefore(now)) preCount++;
    }
    if (preCount == 0) return;

    // Show the review type selector after a brief delay (let canvas settle).
    Future.delayed(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      if (_srsReviewSession.isActive) return;

      showSrsReviewTypeSelector(context, totalDueNodes: preCount).then((type) {
        if (!mounted) return;
        if (type == null) {
          // Student chose "Non ora" — skip the session silently.
          return;
        }

        // 💳 A17: Tier gate for Deep Review — Free users get 1/day.
        if (type == SrsReviewType.deep) {
          final gateResult = _tierGateController.checkFeature(
            GatedFeature.deepReview,
          );
          if (!gateResult.allowed) {
            // Blocked — show upgrade prompt and fall back to micro.
            if (mounted && gateResult.upgradeMessage != null) {
              if (_config.onUpgradePrompt != null) {
                _config.onUpgradePrompt!(context, gateResult.upgradeMessage!);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(gateResult.upgradeMessage!),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    margin: const EdgeInsets.only(
                      bottom: 80, left: 20, right: 20,
                    ),
                    duration: const Duration(seconds: 5),
                    backgroundColor: const Color(0xFF6A1B9A),
                  ),
                );
              }
            }
            return;
          }
          // Record usage for deep review.
          _tierGateController.recordUsage(GatedFeature.deepReview);
          _saveTierGateHistory();
        }

        // 🎥 Progressive zoom-out (§1549-1554): the more times this canvas
        // has been reviewed, the wider the auto-opener pulls back — forcing
        // the student to reconstruct detail from titles and spatial position.
        // Uses the persisted [_canvasReturnCount] (loaded from disk alongside
        // the schedule and incremented on each successful endSession).
        final dueCount = _srsReviewSession.beginSession(
          clusters: _clusterCache,
          reviewSchedule: _reviewSchedule,
          clusterTexts: _clusterTextCache,
          reviewType: type,
          maxNodes: type == SrsReviewType.micro ? 12 : 999,
          canvasReviewCount: _canvasReturnCount,
          userBaseScale: _canvasController.scale,
        );

        if (dueCount > 0) {
          debugPrint('🧠 SRS Blur: $dueCount clusters for ${type.name} review');

          // Apply the progressive zoom-out if the session produced a target.
          final targetScale = _srsReviewSession.targetInitialZoomScale;
          final targetTier = _srsReviewSession.targetInitialLodTier;
          if (targetScale != null && mounted) {
            final viewport = MediaQuery.sizeOf(context);
            CameraActions.zoomToLevel(
              _canvasController,
              targetScale,
              viewport,
            );

            // Throttle: only surface the hint on the *first* session that
            // lands the student in a new LOD tier. Repeated sessions at
            // the same tier would be noise.
            final hint = _srsReviewSession.returnZoomHint;
            if (hint != null &&
                targetTier != null &&
                targetTier != _lastShownZoomHintTier) {
              _lastShownZoomHintTier = targetTier;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(hint),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  margin: const EdgeInsets.only(
                    bottom: 80, left: 20, right: 20,
                  ),
                  duration: const Duration(seconds: 3),
                  backgroundColor: const Color(0xFF263238),
                ),
              );
            }
          }

          if (mounted) setState(() {});
          HapticFeedback.mediumImpact();
        }
      });
    });
  }

  // ── TAP HANDLING ─────────────────────────────────────────────────────────

  /// Called from the gesture layer when a tap hits a blurred cluster.
  /// Returns true if the tap was consumed (cluster was blurred and got revealed).
  bool handleSrsBlurTap(Offset canvasPosition) {
    if (!_srsReviewSession.isActive) return false;

    // Find which blurred cluster was tapped
    for (final cluster in _clusterCache) {
      if (!_srsReviewSession.isClusterBlurred(cluster.id)) continue;

      final hitBounds = cluster.bounds.inflate(16.0); // Generous hit target
      if (hitBounds.contains(canvasPosition)) {
        _revealSrsCluster(cluster);
        return true;
      }
    }

    return false;
  }

  /// Reveals a blurred cluster with animation and shows the self-evaluation UI.
  void _revealSrsCluster(ContentCluster cluster) {
    HapticFeedback.mediumImpact();
    _srsReviewSession.revealCluster(cluster.id);

    if (mounted) setState(() {});

    // Show self-evaluation popup after a brief delay (let the reveal sink in)
    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      _showSrsEvaluationPopup(cluster);
    });
  }

  /// Shows the self-evaluation popup for a revealed cluster.
  void _showSrsEvaluationPopup(ContentCluster cluster) {
    if (!mounted) return;

    final concepts = _srsReviewSession.conceptsForCluster(cluster.id);
    final conceptLabel = concepts.take(3).join(', ');

    final screenPos = _canvasController.canvasToScreen(cluster.centroid);

    // Position the popup near the cluster
    final popupY = (screenPos.dy - 100).clamp(60.0, MediaQuery.sizeOf(context).height - 200);
    final popupX = (screenPos.dx - 100).clamp(20.0, MediaQuery.sizeOf(context).width - 220);

    showDialog(
      context: context,
      barrierColor: Colors.transparent, // Don't dim — student should see the canvas
      barrierDismissible: false,
      builder: (ctx) => Stack(
        children: [
          // Dismiss on tap outside
          Positioned.fill(
            child: GestureDetector(
              onTap: () {
                // Treat as "partial" — didn't evaluate
                _srsReviewSession.recordResult(cluster.id, true);
                Navigator.pop(ctx);
                _checkSrsSessionComplete();
              },
              child: const ColoredBox(color: Colors.transparent),
            ),
          ),
          Positioned(
            left: popupX,
            top: popupY,
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(16),
              color: Theme.of(ctx).colorScheme.surface,
              child: Container(
                width: 220,
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Ricordavi?',
                      style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      conceptLabel,
                      style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _SrsEvalButton(
                            label: 'No 😓',
                            color: const Color(0xFFF44336),
                            onTap: () {
                              HapticFeedback.lightImpact();
                              // 🎵 A13.4: Ab3 — "closed" tone for forgotten
                              PedagogicalSoundEngine.instance.play(PedagogicalSound.revealForgotten);
                              _srsReviewSession.recordResult(cluster.id, false);
                              Navigator.pop(ctx);
                              _checkSrsSessionComplete();
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _SrsEvalButton(
                            label: 'Sì! 💪',
                            color: const Color(0xFF4CAF50),
                            onTap: () {
                              HapticFeedback.lightImpact();
                              // 🎵 A13.4: C4 — "open" tone for remembered
                              PedagogicalSoundEngine.instance.play(PedagogicalSound.revealCorrect);
                              _srsReviewSession.recordResult(cluster.id, true);
                              Navigator.pop(ctx);
                              _checkSrsSessionComplete();
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Checks if all blurred clusters have been evaluated. If so, ends the session.
  void _checkSrsSessionComplete() {
    if (!mounted) return;
    setState(() {}); // Refresh overlay

    if (_srsReviewSession.allEvaluated) {
      _endSrsSession();
    }
  }

  /// Ends the SRS session: applies FSRS updates, shows summary toast, persists.
  void _endSrsSession() {
    final updates = _srsReviewSession.endSession(
      currentSchedule: _reviewSchedule,
    );

    // Apply FSRS updates to the review schedule
    _reviewSchedule.addAll(updates);

    // 🎥 Increment persistent canvas return counter — drives the
    // progressive zoom-out opener on the next session (§1549).
    _canvasReturnCount++;

    _saveSpacedRepetition();

    // Show summary toast
    final remembered = _srsReviewSession.totalRemembered;
    final forgot = _srsReviewSession.totalForgot;
    final total = remembered + forgot;

    if (total > 0 && mounted) {
      final emoji = remembered == total ? '🎉' : '💪';
      final message = '$emoji Ripasso: $remembered/$total ricordati';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.only(bottom: 80, left: 20, right: 20),
          duration: const Duration(seconds: 3),
          backgroundColor: remembered == total
              ? const Color(0xFF2E7D32) // dark green
              : const Color(0xFF37474F), // blue grey
        ),
      );
    }

    if (mounted) setState(() {});
    debugPrint('🧠 SRS session complete: $remembered/$total remembered');
  }

  // ── DISMISS ──────────────────────────────────────────────────────────────

  /// Allows the student to skip the SRS review session entirely.
  void dismissSrsBlurSession() {
    _srsReviewSession.dismiss();
    if (mounted) setState(() {});
  }
}

/// 🎨 Self-evaluation button (Sì/No) for the SRS reveal popup.
class _SrsEvalButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _SrsEvalButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
        ),
      ),
    );
  }
}
