// ============================================================================
// 🎙️ VOICE RECORD BUTTON — Toolbar-ready record/stop with quota awareness
//
// Drop-in widget for the canvas toolbar. Encapsulates:
//   • Tier gate (Free tier shows upgrade prompt instead of opening recorder)
//   • Quota pre-flight: reserve N minutes via [VoiceQuotaTracker]
//   • Visual state: idle / recording / cap-reached / unavailable
//   • Counter pill ("12 / 60 min · Plus" / "Pro ∞ min")
//
// Trasparenza-first: ALWAYS show remaining minutes when on Plus. Pro shows
// the ∞ symbol so the user knows there's no hidden throttle. Free shows
// the upgrade copy as part of the button affordance (not a hidden modal).
// ============================================================================

import 'dart:async';

import 'package:flutter/material.dart';

import 'voice_record_button_state.dart';
import '../voice_quota_tracker.dart';

/// 🎙️ Compact record / stop button + monthly counter pill.
///
/// The host wires [onStartRequested] to invoke the actual recorder
/// (typically `EngineScope.current.audioModule.provider.startRecording`),
/// returning a Future that completes when the recorder actually starts.
/// [onStopRequested] mirrors that for stop; returning the actual recording
/// duration so the quota tracker can [commit] the right number of minutes.
class VoiceRecordButton extends StatefulWidget {
  final VoiceQuotaTracker quota;

  /// Whether the current tier is allowed to record at all. When false the
  /// button renders the upgrade affordance instead of the record icon —
  /// callers usually pass `tierGate.canUseFeature(GatedFeature.voiceRecording)`.
  final bool tierAllowsRecording;

  /// Invoked when the user taps the record button and the quota pre-flight
  /// has passed. Implementation calls the native recorder.
  final Future<void> Function() onStartRequested;

  /// Invoked when the user taps stop. Must return the actual recording
  /// duration so the quota tracker can [VoiceQuotaTracker.commit] it.
  final Future<Duration> Function() onStopRequested;

  /// Invoked when the user taps the button while Free or the cap is reached.
  /// Use it to show the tier-upgrade or quota-exhausted dialog.
  final VoidCallback? onUpgradeRequested;

  /// Estimated minutes the user is asking for, used as the optimistic
  /// reservation amount. Defaults to 5 minutes which matches a typical
  /// short note. The actual minutes are committed on stop.
  final int estimateMinutes;

  const VoiceRecordButton({
    super.key,
    required this.quota,
    required this.tierAllowsRecording,
    required this.onStartRequested,
    required this.onStopRequested,
    this.onUpgradeRequested,
    this.estimateMinutes = 5,
  });

  @override
  State<VoiceRecordButton> createState() => _VoiceRecordButtonState();
}

class _VoiceRecordButtonState extends State<VoiceRecordButton> {
  VoiceRecordButtonPhase _phase = VoiceRecordButtonPhase.idle;
  String? _reservationToken;
  DateTime? _startedAt;

  Future<void> _handleTap() async {
    if (!widget.tierAllowsRecording) {
      widget.onUpgradeRequested?.call();
      return;
    }
    if (_phase == VoiceRecordButtonPhase.recording) {
      await _stop();
      return;
    }
    if (_phase != VoiceRecordButtonPhase.idle) return;

    setState(() => _phase = VoiceRecordButtonPhase.reserving);

    try {
      _reservationToken =
          await widget.quota.reserve(estimateMinutes: widget.estimateMinutes);
    } on VoiceQuotaExhaustedException {
      if (!mounted) return;
      setState(() => _phase = VoiceRecordButtonPhase.exhausted);
      widget.onUpgradeRequested?.call();
      return;
    } catch (e) {
      if (!mounted) return;
      setState(() => _phase = VoiceRecordButtonPhase.idle);
      return;
    }

    try {
      await widget.onStartRequested();
      if (!mounted) return;
      setState(() {
        _phase = VoiceRecordButtonPhase.recording;
        _startedAt = DateTime.now();
      });
    } catch (e) {
      // Recorder failed to start — refund the optimistic reservation so
      // the user doesn't get charged for nothing.
      final token = _reservationToken;
      _reservationToken = null;
      if (token != null) {
        unawaited(widget.quota.refund(token));
      }
      if (!mounted) return;
      setState(() => _phase = VoiceRecordButtonPhase.idle);
    }
  }

  Future<void> _stop() async {
    setState(() => _phase = VoiceRecordButtonPhase.stopping);
    Duration recordedFor;
    try {
      recordedFor = await widget.onStopRequested();
    } catch (_) {
      // Treat as cancelled — refund.
      final token = _reservationToken;
      _reservationToken = null;
      if (token != null) {
        unawaited(widget.quota.refund(token));
      }
      if (!mounted) return;
      setState(() => _phase = VoiceRecordButtonPhase.idle);
      return;
    }

    final token = _reservationToken;
    _reservationToken = null;
    _startedAt = null;

    // Round UP to whole minutes (1 second of recording still costs 1 min,
    // matches the "you pay for what you reserve" expectation of users).
    final actualMinutes =
        recordedFor.inSeconds == 0 ? 0 : ((recordedFor.inSeconds + 59) ~/ 60);

    if (token != null) {
      if (actualMinutes <= 0) {
        unawaited(widget.quota.refund(token));
      } else {
        unawaited(widget.quota.commit(
          reservationToken: token,
          actualMinutes: actualMinutes,
        ));
      }
    }
    if (!mounted) return;
    setState(() => _phase = VoiceRecordButtonPhase.idle);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VoiceQuotaSnapshot?>(
      valueListenable: widget.quota.quota,
      builder: (context, snapshot, _) {
        return _VoiceRecordChrome(
          phase: _phase,
          snapshot: snapshot,
          tierAllowsRecording: widget.tierAllowsRecording,
          onTap: _handleTap,
          startedAt: _startedAt,
        );
      },
    );
  }
}

class _VoiceRecordChrome extends StatelessWidget {
  final VoiceRecordButtonPhase phase;
  final VoiceQuotaSnapshot? snapshot;
  final bool tierAllowsRecording;
  final VoidCallback onTap;
  final DateTime? startedAt;

  const _VoiceRecordChrome({
    required this.phase,
    required this.snapshot,
    required this.tierAllowsRecording,
    required this.onTap,
    required this.startedAt,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRecording = phase == VoiceRecordButtonPhase.recording;
    final isBusy = phase == VoiceRecordButtonPhase.reserving ||
        phase == VoiceRecordButtonPhase.stopping;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Record / stop chip ─────────────────────────────────────────
        Material(
          color: isRecording
              ? theme.colorScheme.errorContainer
              : theme.colorScheme.surfaceContainerHigh,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: isBusy ? null : onTap,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isBusy)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(
                      isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                      size: 18,
                      color: isRecording
                          ? theme.colorScheme.onErrorContainer
                          : (tierAllowsRecording
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant),
                    ),
                  const SizedBox(width: 6),
                  Text(
                    isRecording ? 'Stop' : 'Registra',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: isRecording
                          ? theme.colorScheme.onErrorContainer
                          : (tierAllowsRecording
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),

        // ── Counter pill (always visible — trasparenza-first) ─────────
        if (snapshot != null) _CounterPill(snapshot: snapshot!),
      ],
    );
  }
}

class _CounterPill extends StatelessWidget {
  final VoiceQuotaSnapshot snapshot;

  const _CounterPill({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUnlimited = snapshot.isUnlimited;
    final isExhausted = snapshot.isExhausted;

    final label = isUnlimited
        ? '∞ · ${_tierLabel(snapshot.tier)}'
        : '${snapshot.minutesUsed} / ${snapshot.minutesLimit} min · ${_tierLabel(snapshot.tier)}';

    final color = isExhausted
        ? theme.colorScheme.tertiary
        : theme.colorScheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }

  String _tierLabel(String tier) {
    return switch (tier) {
      'pro' => 'Pro',
      'plus' => 'Plus',
      'essential' => 'Essential',
      _ => 'Free',
    };
  }
}
