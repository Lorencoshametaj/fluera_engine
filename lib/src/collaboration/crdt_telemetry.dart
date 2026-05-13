import 'scene_graph_crdt.dart';

// =============================================================================
// 📊 CRDT TELEMETRY
//
// Optional instrumentation hook that the CRDT layer invokes at every
// observable transition: a local op produced, a remote op applied, an op
// buffered as an orphan, an op deduplicated, a property changed.
//
// Concrete implementations forward these events to whatever observability
// stack the host app uses (Sentry breadcrumb, Grafana counter, in-app
// HUD overlay during a device validation session). Tests use the bundled
// [RecordingCRDTTelemetry] to assert that the engine fires the events the
// caller cares about — without coupling the CRDT module to any particular
// metrics backend.
//
// Default is [CRDTTelemetry.noop]: zero overhead, zero allocation, every
// callback is a constant tear-off.
// =============================================================================

/// Hook surface for observing CRDT lifecycle events.
abstract class CRDTTelemetry {
  /// Sentinel no-op instance. Use this when telemetry is disabled.
  static const CRDTTelemetry noop = _NoopCRDTTelemetry();

  const CRDTTelemetry();

  /// Fired whenever the local peer produces a fresh CRDT op (i.e. one whose
  /// `peerId == localPeerId`). The op has already been applied to the local
  /// in-memory state when this fires.
  void onLocalOp(CRDTOperation op) {}

  /// Fired whenever an op originating from a remote peer is applied to the
  /// local in-memory state. Idempotent re-deliveries do NOT fire this hook
  /// — they fire [onDuplicateOp] instead.
  void onRemoteOp(CRDTOperation op) {}

  /// Fired when an op is dropped because its `opId` was already applied or
  /// already buffered as an orphan. Useful for measuring at-least-once
  /// transport redelivery rates.
  void onDuplicateOp(CRDTOperation op) {}

  /// Fired when a `setProperty` / `moveNode` op arrives before the parent
  /// `addNode`, and is therefore buffered for a later replay.
  void onOrphanBuffered(CRDTOperation op) {}

  /// Fired when one or more orphan ops are drained as a side-effect of an
  /// `addNode` for the same node id.
  void onOrphanReplayed(String nodeId, int opCount) {}
}

class _NoopCRDTTelemetry extends CRDTTelemetry {
  const _NoopCRDTTelemetry();
}

/// In-memory recorder used by tests to assert which hooks fired.
///
/// Not safe for concurrent producers, but the CRDT layer is single-threaded
/// (every mutation runs on the UI isolate), so the simple list backing is
/// sufficient.
class RecordingCRDTTelemetry extends CRDTTelemetry {
  final List<CRDTOperation> localOps = [];
  final List<CRDTOperation> remoteOps = [];
  final List<CRDTOperation> duplicates = [];
  final List<CRDTOperation> orphansBuffered = [];
  final List<({String nodeId, int count})> orphanReplays = [];

  RecordingCRDTTelemetry();

  @override
  void onLocalOp(CRDTOperation op) => localOps.add(op);

  @override
  void onRemoteOp(CRDTOperation op) => remoteOps.add(op);

  @override
  void onDuplicateOp(CRDTOperation op) => duplicates.add(op);

  @override
  void onOrphanBuffered(CRDTOperation op) => orphansBuffered.add(op);

  @override
  void onOrphanReplayed(String nodeId, int opCount) =>
      orphanReplays.add((nodeId: nodeId, count: opCount));

  /// Reset every recorded list — useful between phases of a multi-step test.
  void clear() {
    localOps.clear();
    remoteOps.clear();
    duplicates.clear();
    orphansBuffered.clear();
    orphanReplays.clear();
  }
}
