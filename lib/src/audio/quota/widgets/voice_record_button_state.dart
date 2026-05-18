// ============================================================================
// 🎙️ VOICE RECORD BUTTON PHASE — UI state machine for the record/stop chip
//
// Kept in a separate file so widget tests and the Fluera app can pattern-match
// the phase without depending on Material widgets.
// ============================================================================

/// 🎙️ Operational phase of [VoiceRecordButton].
enum VoiceRecordButtonPhase {
  /// Default state. Tapping triggers a quota reservation + recorder start.
  idle,

  /// Quota reservation is in flight (RPC round trip to Supabase).
  /// Shown as a small spinner inside the chip.
  reserving,

  /// Recorder is capturing audio. Tapping stops and commits the reservation.
  recording,

  /// Stop tapped — flushing the recorder and committing actual minutes.
  stopping,

  /// Monthly cap reached on the current tier. The chip shows the upgrade
  /// affordance instead of the record icon; the host's `onUpgradeRequested`
  /// callback runs on tap.
  exhausted,
}
