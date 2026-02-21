import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'nebula_realtime_adapter.dart';
import 'realtime_enterprise.dart';

// =============================================================================
// 🔀 CONFLICT RESOLUTION — Enterprise-grade conflict detection & resolution
//
// Provides:
//   1. ConflictResolver — pluggable strategy-based resolution
//   2. Text OT — Operational Transform for concurrent text edits
//   3. Position auto-merge — average coordinates for concurrent moves
//   4. Conflict event model — structured conflict tracking
// =============================================================================

// ─────────────────────────────────────────────────────────────────────────────
// CONFLICT DATA MODEL
// ─────────────────────────────────────────────────────────────────────────────

/// A detected conflict between two concurrent events.
class ConflictRecord {
  /// Unique conflict ID.
  final String id;

  /// The local event that conflicts.
  final CanvasRealtimeEvent localEvent;

  /// The remote event that conflicts.
  final CanvasRealtimeEvent remoteEvent;

  /// Vector clocks at the time of conflict (if available).
  final VectorClock? localClock;
  final VectorClock? remoteClock;

  /// The element ID in conflict.
  final String? elementId;

  /// How the conflict was resolved.
  ConflictResolution? resolution;

  /// Timestamp of detection.
  final DateTime detectedAt;

  ConflictRecord({
    required this.id,
    required this.localEvent,
    required this.remoteEvent,
    this.localClock,
    this.remoteClock,
    this.elementId,
    this.resolution,
    DateTime? detectedAt,
  }) : detectedAt = detectedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'localEvent': localEvent.toJson(),
    'remoteEvent': remoteEvent.toJson(),
    'elementId': elementId,
    'resolution': resolution?.name,
    'detectedAt': detectedAt.toIso8601String(),
  };
}

/// How a conflict was resolved.
enum ConflictResolution {
  /// Local version kept (remote discarded).
  keepLocal,

  /// Remote version kept (local discarded).
  keepRemote,

  /// Both versions merged automatically.
  autoMerged,

  /// User manually chose a resolution.
  userChoice,

  /// Last writer wins (timestamp-based).
  lastWriteWins,

  /// Conflict could not be resolved automatically.
  unresolved,
}

// ─────────────────────────────────────────────────────────────────────────────
// CONFLICT RESOLUTION STRATEGIES
// ─────────────────────────────────────────────────────────────────────────────

/// Abstract strategy for resolving a specific type of conflict.
///
/// Implement this to create custom resolution logic for your app.
abstract class ConflictStrategy {
  /// Attempt to resolve the conflict.
  ///
  /// Returns the resolved event payload, or `null` if the conflict
  /// requires user intervention (strategy cannot auto-resolve).
  Future<ConflictResult?> resolve(ConflictRecord conflict);

  /// Human-readable name of this strategy.
  String get name;
}

/// Result of a conflict resolution.
class ConflictResult {
  /// The merged/resolved event to apply to the canvas state.
  final CanvasRealtimeEvent resolvedEvent;

  /// How it was resolved.
  final ConflictResolution resolution;

  /// Human-readable description of what happened.
  final String description;

  const ConflictResult({
    required this.resolvedEvent,
    required this.resolution,
    required this.description,
  });
}

/// **Last-Write-Wins (LWW)** — simplest strategy, always applies.
///
/// Uses event timestamps. The event with the later timestamp wins.
/// When timestamps are equal, falls back to senderId comparison
/// for deterministic ordering.
class LastWriteWinsStrategy implements ConflictStrategy {
  @override
  String get name => 'Last-Write-Wins';

  @override
  Future<ConflictResult?> resolve(ConflictRecord conflict) async {
    final local = conflict.localEvent;
    final remote = conflict.remoteEvent;

    // Prefer later timestamp
    if (remote.timestamp > local.timestamp) {
      return ConflictResult(
        resolvedEvent: remote,
        resolution: ConflictResolution.lastWriteWins,
        description:
            'Remote event wins (later timestamp: '
            '${remote.timestamp} > ${local.timestamp})',
      );
    } else if (local.timestamp > remote.timestamp) {
      return ConflictResult(
        resolvedEvent: local,
        resolution: ConflictResolution.lastWriteWins,
        description:
            'Local event wins (later timestamp: '
            '${local.timestamp} > ${remote.timestamp})',
      );
    }

    // Equal timestamps: deterministic tie-break by senderId
    final winner =
        local.senderId.compareTo(remote.senderId) >= 0 ? local : remote;
    final isLocal = winner == local;
    return ConflictResult(
      resolvedEvent: winner,
      resolution: ConflictResolution.lastWriteWins,
      description:
          '${isLocal ? "Local" : "Remote"} wins '
          '(tie-break by senderId)',
    );
  }
}

/// **Position Auto-Merge** — averages coordinates for concurrent moves.
///
/// When two users move the same element simultaneously, this strategy
/// merges by averaging the final positions. Works for image updates
/// with `x`, `y`, `width`, `height`, `rotation` fields.
class PositionAutoMergeStrategy implements ConflictStrategy {
  @override
  String get name => 'Position Auto-Merge';

  @override
  Future<ConflictResult?> resolve(ConflictRecord conflict) async {
    final localPayload = conflict.localEvent.payload;
    final remotePayload = conflict.remoteEvent.payload;

    // Only works for image/element updates with position data
    if (!_hasPositionData(localPayload) || !_hasPositionData(remotePayload)) {
      return null; // Can't auto-merge, fall through to next strategy
    }

    final merged = Map<String, dynamic>.from(remotePayload);

    // Average numeric position fields
    for (final key in const ['x', 'y', 'width', 'height', 'rotation']) {
      final localVal = localPayload[key] as num?;
      final remoteVal = remotePayload[key] as num?;
      if (localVal != null && remoteVal != null) {
        merged[key] = (localVal + remoteVal) / 2;
      }
    }

    // For non-position fields, prefer remote (latest)
    return ConflictResult(
      resolvedEvent: CanvasRealtimeEvent(
        type: conflict.remoteEvent.type,
        senderId: conflict.remoteEvent.senderId,
        elementId: conflict.remoteEvent.elementId,
        payload: merged,
        timestamp: max(
          conflict.localEvent.timestamp,
          conflict.remoteEvent.timestamp,
        ),
      ),
      resolution: ConflictResolution.autoMerged,
      description: 'Positions merged (averaged x, y, width, height, rotation)',
    );
  }

  bool _hasPositionData(Map<String, dynamic> payload) {
    return payload.containsKey('x') && payload.containsKey('y');
  }
}

/// **User-Pick** strategy — always defers to the user.
///
/// Returns `null` to trigger the conflict resolution UI dialog.
class UserPickStrategy implements ConflictStrategy {
  @override
  String get name => 'User Pick';

  @override
  Future<ConflictResult?> resolve(ConflictRecord conflict) async {
    return null; // Always requires user intervention
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TEXT OPERATIONAL TRANSFORM (OT)
// ─────────────────────────────────────────────────────────────────────────────

/// A text operation — insert, delete, or retain characters.
sealed class TextOp {
  const TextOp();
}

/// Retain [count] characters (no change).
class RetainOp extends TextOp {
  final int count;
  const RetainOp(this.count);
  @override
  String toString() => 'retain($count)';
}

/// Insert [text] at the current position.
class InsertOp extends TextOp {
  final String text;
  const InsertOp(this.text);
  @override
  String toString() => 'insert("$text")';
}

/// Delete [count] characters at the current position.
class DeleteOp extends TextOp {
  final int count;
  const DeleteOp(this.count);
  @override
  String toString() => 'delete($count)';
}

/// Operational Transform engine for concurrent text editing.
///
/// Given two concurrent text operations A and B applied to the same
/// base document, OT produces A' and B' such that:
///   apply(apply(doc, A), B') == apply(apply(doc, B), A')
///
/// This ensures convergence regardless of application order.
class TextOTEngine {
  /// Apply an operation list to a document string.
  static String apply(String document, List<TextOp> ops) {
    final buf = StringBuffer();
    var cursor = 0;

    for (final op in ops) {
      switch (op) {
        case RetainOp(:final count):
          if (cursor + count > document.length) {
            throw OTException(
              'Retain past end: cursor=$cursor, '
              'count=$count, docLen=${document.length}',
            );
          }
          buf.write(document.substring(cursor, cursor + count));
          cursor += count;
        case InsertOp(:final text):
          buf.write(text);
        case DeleteOp(:final count):
          if (cursor + count > document.length) {
            throw OTException(
              'Delete past end: cursor=$cursor, '
              'count=$count, docLen=${document.length}',
            );
          }
          cursor += count; // Skip deleted characters
      }
    }

    // Append remaining document
    if (cursor < document.length) {
      buf.write(document.substring(cursor));
    }

    return buf.toString();
  }

  /// Transform two concurrent operations against each other.
  ///
  /// Returns `(aPrime, bPrime)` where:
  ///   apply(apply(doc, a), bPrime) == apply(apply(doc, b), aPrime)
  static (List<TextOp>, List<TextOp>) transform(
    List<TextOp> a,
    List<TextOp> b,
  ) {
    final aPrime = <TextOp>[];
    final bPrime = <TextOp>[];

    var ia = 0;
    var ib = 0;
    var aRemainder = 0;
    var bRemainder = 0;

    while (ia < a.length || ib < b.length) {
      final opA = ia < a.length ? a[ia] : null;
      final opB = ib < b.length ? b[ib] : null;

      // If one side is exhausted, just pass through the other
      if (opA == null) {
        bPrime.add(opB!);
        ib++;
        continue;
      }
      if (opB == null) {
        aPrime.add(opA);
        ia++;
        continue;
      }

      // Insert vs anything: insert goes first
      if (opA is InsertOp) {
        aPrime.add(opA);
        bPrime.add(RetainOp(opA.text.length));
        ia++;
        continue;
      }
      if (opB is InsertOp) {
        bPrime.add(opB);
        aPrime.add(RetainOp(opB.text.length));
        ib++;
        continue;
      }

      // Both retain
      if (opA is RetainOp && opB is RetainOp) {
        final lenA = aRemainder > 0 ? aRemainder : opA.count;
        final lenB = bRemainder > 0 ? bRemainder : opB.count;
        final minLen = min(lenA, lenB);
        aPrime.add(RetainOp(minLen));
        bPrime.add(RetainOp(minLen));

        aRemainder = lenA - minLen;
        bRemainder = lenB - minLen;
        if (aRemainder == 0) ia++;
        if (bRemainder == 0) ib++;
        continue;
      }

      // Retain vs Delete
      if (opA is RetainOp && opB is DeleteOp) {
        final lenA = aRemainder > 0 ? aRemainder : opA.count;
        final lenB = bRemainder > 0 ? bRemainder : opB.count;
        final minLen = min(lenA, lenB);
        bPrime.add(DeleteOp(minLen));
        // A's retain is consumed by B's delete (no output in aPrime)

        aRemainder = lenA - minLen;
        bRemainder = lenB - minLen;
        if (aRemainder == 0) ia++;
        if (bRemainder == 0) ib++;
        continue;
      }

      // Delete vs Retain
      if (opA is DeleteOp && opB is RetainOp) {
        final lenA = aRemainder > 0 ? aRemainder : opA.count;
        final lenB = bRemainder > 0 ? bRemainder : opB.count;
        final minLen = min(lenA, lenB);
        aPrime.add(DeleteOp(minLen));

        aRemainder = lenA - minLen;
        bRemainder = lenB - minLen;
        if (aRemainder == 0) ia++;
        if (bRemainder == 0) ib++;
        continue;
      }

      // Both delete — they cancel out
      if (opA is DeleteOp && opB is DeleteOp) {
        final lenA = aRemainder > 0 ? aRemainder : opA.count;
        final lenB = bRemainder > 0 ? bRemainder : opB.count;
        final minLen = min(lenA, lenB);
        // Both deletes cancel — no output

        aRemainder = lenA - minLen;
        bRemainder = lenB - minLen;
        if (aRemainder == 0) ia++;
        if (bRemainder == 0) ib++;
        continue;
      }

      // Shouldn't reach here
      ia++;
      ib++;
    }

    return (_compact(aPrime), _compact(bPrime));
  }

  /// Compute the diff between two document versions as ops.
  ///
  /// Simple character-level diff (Myers-like for short texts).
  static List<TextOp> diff(String from, String to) {
    if (from == to) return [RetainOp(from.length)];
    if (from.isEmpty) return [InsertOp(to)];
    if (to.isEmpty) return [DeleteOp(from.length)];

    // Find common prefix
    var commonPrefix = 0;
    while (commonPrefix < from.length &&
        commonPrefix < to.length &&
        from[commonPrefix] == to[commonPrefix]) {
      commonPrefix++;
    }

    // Find common suffix
    var commonSuffix = 0;
    while (commonSuffix < from.length - commonPrefix &&
        commonSuffix < to.length - commonPrefix &&
        from[from.length - 1 - commonSuffix] ==
            to[to.length - 1 - commonSuffix]) {
      commonSuffix++;
    }

    final ops = <TextOp>[];

    if (commonPrefix > 0) ops.add(RetainOp(commonPrefix));

    final deleteLen = from.length - commonPrefix - commonSuffix;
    if (deleteLen > 0) ops.add(DeleteOp(deleteLen));

    final insertLen = to.length - commonPrefix - commonSuffix;
    if (insertLen > 0) {
      ops.add(InsertOp(to.substring(commonPrefix, to.length - commonSuffix)));
    }

    if (commonSuffix > 0) ops.add(RetainOp(commonSuffix));

    return ops;
  }

  /// Compact consecutive ops of the same type.
  static List<TextOp> _compact(List<TextOp> ops) {
    if (ops.isEmpty) return ops;
    final result = <TextOp>[];
    for (final op in ops) {
      if (result.isEmpty) {
        result.add(op);
        continue;
      }
      final last = result.last;
      if (op is RetainOp && last is RetainOp) {
        result[result.length - 1] = RetainOp(last.count + op.count);
      } else if (op is DeleteOp && last is DeleteOp) {
        result[result.length - 1] = DeleteOp(last.count + op.count);
      } else if (op is InsertOp && last is InsertOp) {
        result[result.length - 1] = InsertOp(last.text + op.text);
      } else {
        result.add(op);
      }
    }
    return result;
  }
}

/// Exception thrown by OT operations.
class OTException implements Exception {
  final String message;
  const OTException(this.message);
  @override
  String toString() => 'OTException: $message';
}

/// Text OT conflict strategy — merges concurrent text edits.
///
/// When two users edit the same text element concurrently, this strategy
/// uses OT to produce a merged result that preserves both edits.
class TextOTConflictStrategy implements ConflictStrategy {
  @override
  String get name => 'Text OT Merge';

  @override
  Future<ConflictResult?> resolve(ConflictRecord conflict) async {
    // Only applicable to text events
    if (conflict.localEvent.type != RealtimeEventType.textChanged ||
        conflict.remoteEvent.type != RealtimeEventType.textChanged) {
      return null;
    }

    final localText = conflict.localEvent.payload['text'] as String?;
    final remoteText = conflict.remoteEvent.payload['text'] as String?;
    final baseText =
        conflict.localEvent.payload['baseText'] as String? ??
        conflict.remoteEvent.payload['baseText'] as String? ??
        '';

    if (localText == null || remoteText == null) return null;

    try {
      // Compute ops from base to each version
      final opsA = TextOTEngine.diff(baseText, localText);
      final opsB = TextOTEngine.diff(baseText, remoteText);

      // Transform
      final (_, bPrime) = TextOTEngine.transform(opsA, opsB);

      // Apply: base → local → bPrime = merged
      final merged = TextOTEngine.apply(localText, bPrime);

      // Build merged payload
      final mergedPayload = Map<String, dynamic>.from(
        conflict.remoteEvent.payload,
      );
      mergedPayload['text'] = merged;
      mergedPayload['baseText'] = merged; // New base for next edit

      return ConflictResult(
        resolvedEvent: CanvasRealtimeEvent(
          type: RealtimeEventType.textChanged,
          senderId: conflict.remoteEvent.senderId,
          elementId: conflict.remoteEvent.elementId,
          payload: mergedPayload,
          timestamp: max(
            conflict.localEvent.timestamp,
            conflict.remoteEvent.timestamp,
          ),
        ),
        resolution: ConflictResolution.autoMerged,
        description:
            'Text merged via OT: "${_truncate(baseText)}" → '
            '"${_truncate(merged)}"',
      );
    } catch (e) {
      debugPrint('🔀 OT merge failed: $e');
      return null; // Fall through to next strategy
    }
  }

  String _truncate(String s) => s.length > 30 ? '${s.substring(0, 30)}…' : s;
}

// ─────────────────────────────────────────────────────────────────────────────
// CONFLICT RESOLVER — Orchestrator with strategy chain
// ─────────────────────────────────────────────────────────────────────────────

/// Enterprise-grade conflict resolver with pluggable strategy chain.
///
/// Strategies are tried in order. If a strategy returns `null`,
/// the next one is tried. If all strategies return `null`,
/// the conflict is marked as unresolved and the [onUnresolved]
/// callback is fired (for showing a UI dialog).
///
/// **Default strategy chain:**
/// 1. TextOTConflictStrategy (for text elements)
/// 2. PositionAutoMergeStrategy (for element moves)
/// 3. LastWriteWinsStrategy (fallback)
///
/// **Usage:**
/// ```dart
/// final resolver = ConflictResolver(
///   strategies: [
///     TextOTConflictStrategy(),
///     PositionAutoMergeStrategy(),
///     LastWriteWinsStrategy(),
///   ],
///   onUnresolved: (conflict) {
///     showConflictDialog(context, conflict);
///   },
/// );
/// ```
class ConflictResolver {
  /// Ordered chain of resolution strategies.
  final List<ConflictStrategy> strategies;

  /// Callback when no strategy can auto-resolve.
  final void Function(ConflictRecord conflict)? onUnresolved;

  /// History of detected conflicts (for audit/debugging).
  final List<ConflictRecord> conflictHistory = [];

  /// Stream of resolved conflicts.
  Stream<ConflictRecord> get onResolved => _resolvedController.stream;
  final _resolvedController = StreamController<ConflictRecord>.broadcast();

  /// Stream of newly detected conflicts (before resolution).
  Stream<ConflictRecord> get onDetected => _detectedController.stream;
  final _detectedController = StreamController<ConflictRecord>.broadcast();

  /// Max history entries.
  final int maxHistory;

  ConflictResolver({
    List<ConflictStrategy>? strategies,
    this.onUnresolved,
    this.maxHistory = 500,
  }) : strategies =
           strategies ??
           [
             TextOTConflictStrategy(),
             PositionAutoMergeStrategy(),
             LastWriteWinsStrategy(),
           ];

  /// Detect and resolve a potential conflict.
  ///
  /// Call this when a remote event arrives and the VectorClock
  /// indicates a concurrent modification to the same element.
  ///
  /// Returns the resolved event to apply, or `null` if the conflict
  /// requires user intervention.
  Future<ConflictResult?> resolveConflict({
    required CanvasRealtimeEvent localEvent,
    required CanvasRealtimeEvent remoteEvent,
    VectorClock? localClock,
    VectorClock? remoteClock,
  }) async {
    final conflict = ConflictRecord(
      id:
          '${DateTime.now().millisecondsSinceEpoch}_'
          '${localEvent.elementId ?? 'global'}',
      localEvent: localEvent,
      remoteEvent: remoteEvent,
      localClock: localClock,
      remoteClock: remoteClock,
      elementId: remoteEvent.elementId,
    );

    _detectedController.add(conflict);
    conflictHistory.insert(0, conflict);
    if (conflictHistory.length > maxHistory) {
      conflictHistory.removeLast();
    }

    debugPrint(
      '🔀 Conflict detected on ${conflict.elementId ?? "global"}: '
      '${localEvent.type.name} vs ${remoteEvent.type.name}',
    );

    // Try strategies in order
    for (final strategy in strategies) {
      try {
        final result = await strategy.resolve(conflict);
        if (result != null) {
          conflict.resolution = result.resolution;
          _resolvedController.add(conflict);
          debugPrint('🔀 Resolved via ${strategy.name}: ${result.description}');
          return result;
        }
      } catch (e) {
        debugPrint('🔀 Strategy ${strategy.name} failed: $e');
      }
    }

    // No strategy could resolve
    conflict.resolution = ConflictResolution.unresolved;
    onUnresolved?.call(conflict);
    debugPrint('🔀 Conflict unresolved — requires user intervention');
    return null;
  }

  /// Manually resolve a conflict (from UI dialog).
  void resolveManually(ConflictRecord conflict, ConflictResolution resolution) {
    conflict.resolution = resolution;
    _resolvedController.add(conflict);
  }

  /// Get statistics about conflict history.
  ConflictStats get stats {
    final total = conflictHistory.length;
    final autoResolved =
        conflictHistory
            .where(
              (c) =>
                  c.resolution == ConflictResolution.autoMerged ||
                  c.resolution == ConflictResolution.lastWriteWins,
            )
            .length;
    final userResolved =
        conflictHistory
            .where((c) => c.resolution == ConflictResolution.userChoice)
            .length;
    final unresolved =
        conflictHistory
            .where((c) => c.resolution == ConflictResolution.unresolved)
            .length;

    return ConflictStats(
      total: total,
      autoResolved: autoResolved,
      userResolved: userResolved,
      unresolved: unresolved,
    );
  }

  void dispose() {
    _resolvedController.close();
    _detectedController.close();
  }
}

/// Statistics about conflict resolution.
class ConflictStats {
  final int total;
  final int autoResolved;
  final int userResolved;
  final int unresolved;

  const ConflictStats({
    required this.total,
    required this.autoResolved,
    required this.userResolved,
    required this.unresolved,
  });

  /// Auto-resolution rate (0.0 to 1.0).
  double get autoResolutionRate => total > 0 ? autoResolved / total : 1.0;

  @override
  String toString() =>
      'ConflictStats(total=$total, auto=$autoResolved, '
      'user=$userResolved, unresolved=$unresolved, '
      'rate=${(autoResolutionRate * 100).toStringAsFixed(1)}%)';
}

// ─────────────────────────────────────────────────────────────────────────────
// LAST-KNOWN STATE TRACKER
// ─────────────────────────────────────────────────────────────────────────────

/// Tracks the last-known state of each element for conflict detection.
///
/// When a remote event arrives for an element that was also locally
/// modified since the last sync, a conflict is flagged.
class ElementStateTracker {
  /// Last-known event per element: elementId → event.
  final Map<String, CanvasRealtimeEvent> _lastApplied = {};

  /// Locally modified elements since last sync.
  final Set<String> _locallyDirty = {};

  /// Record a locally applied event.
  void markLocallyModified(String elementId, CanvasRealtimeEvent event) {
    _locallyDirty.add(elementId);
    _lastApplied[elementId] = event;
  }

  /// Record a remotely applied event (clears dirty flag).
  void markRemoteApplied(String elementId, CanvasRealtimeEvent event) {
    _locallyDirty.remove(elementId);
    _lastApplied[elementId] = event;
  }

  /// Check if an incoming remote event conflicts with local state.
  bool hasConflict(CanvasRealtimeEvent remoteEvent) {
    final elementId = remoteEvent.elementId;
    if (elementId == null) return false;
    return _locallyDirty.contains(elementId);
  }

  /// Get the last locally-applied event for an element.
  CanvasRealtimeEvent? getLastLocal(String elementId) =>
      _locallyDirty.contains(elementId) ? _lastApplied[elementId] : null;

  /// Clear all tracking (e.g. on reconnect).
  void clear() {
    _lastApplied.clear();
    _locallyDirty.clear();
  }

  /// Number of elements with pending local modifications.
  int get dirtyCount => _locallyDirty.length;
}
