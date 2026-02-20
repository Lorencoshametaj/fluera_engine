import 'dart:async';
import 'package:flutter/foundation.dart';
import './canvas_node.dart';
import '../nodes/group_node.dart';
import '../nodes/layer_node.dart';
import './scene_graph.dart';
import '../engine_error.dart';
import '../engine_scope.dart';

// =============================================================================
// 🛡️ SCENE GRAPH INTEGRITY — Structural validation & self-healing
// =============================================================================
//
// DESIGN PRINCIPLES:
// - Pure validation: no side effects in validate(), only in repair()
// - Exhaustive: checks ALL structural invariants, not just cycles
// - Self-healing: repairs fixable violations automatically
// - Observable: every violation is logged with full context
// - Debug-friendly: assert-based shortcuts for development builds
// =============================================================================

/// Maximum allowed tree depth before flagging as suspicious.
const int kMaxTreeDepth = 100;

// =============================================================================
// Violation model
// =============================================================================

/// Type of structural violation found in the scene graph.
enum ViolationType {
  /// Two or more nodes share the same ID.
  duplicateId,

  /// A child's `parent` pointer doesn't match its actual parent in the tree.
  parentPointerMismatch,

  /// A direct child of rootNode is not a [LayerNode].
  invalidRootChild,

  /// A node exists in the spatial index but not in the tree, or vice versa.
  spatialIndexDesync,

  /// A node exists in the dirty tracker registry but not in the tree, or vice versa.
  dirtyTrackerDesync,

  /// Tree nesting exceeds [kMaxTreeDepth].
  depthOverflow,

  /// A cycle was detected in the parent chain.
  cycle,

  /// A node exists in `_nodeIndex` but not in the tree, or vice versa.
  nodeIndexDesync,
}

/// A single structural violation found during validation.
class IntegrityViolation {
  /// What kind of violation this is.
  final ViolationType type;

  /// ID of the node involved (if applicable).
  final String? nodeId;

  /// Human-readable description.
  final String description;

  /// Whether this violation can be automatically repaired.
  final bool autoRepairable;

  const IntegrityViolation({
    required this.type,
    this.nodeId,
    required this.description,
    this.autoRepairable = false,
  });

  @override
  String toString() =>
      'IntegrityViolation(${type.name}, node: $nodeId, $description)';
}

/// Result of a validate-and-repair cycle.
class IntegrityReport {
  /// All violations found during validation.
  final List<IntegrityViolation> violations;

  /// Violations that were automatically repaired.
  final List<IntegrityViolation> repaired;

  /// Violations that could NOT be repaired automatically.
  List<IntegrityViolation> get unresolved =>
      violations.where((v) => !repaired.contains(v)).toList();

  /// Whether the graph is fully healthy (no violations).
  bool get isHealthy => violations.isEmpty;

  /// Whether all violations were repaired.
  bool get isFullyRepaired => unresolved.isEmpty;

  const IntegrityReport({required this.violations, required this.repaired});

  @override
  String toString() =>
      'IntegrityReport('
      'violations: ${violations.length}, '
      'repaired: ${repaired.length}, '
      'unresolved: ${unresolved.length})';
}

// =============================================================================
// Metrics
// =============================================================================

/// Session-level metrics for integrity monitoring.
///
/// Tracks how many checks, violations, and repairs have occurred since
/// the engine started, enabling detection of systematic corruption bugs.
class IntegrityMetrics {
  IntegrityMetrics._();

  /// Public constructor for per-scope instances.
  IntegrityMetrics.create();

  /// Shared singleton instance (backward-compatible default).
  static final IntegrityMetrics instance = IntegrityMetrics._();

  /// Total validation runs since session start.
  int totalChecks = 0;

  /// Total violations detected across all runs.
  int totalViolationsDetected = 0;

  /// Total repairs successfully applied.
  int totalRepairsApplied = 0;

  /// Timestamp of last check.
  DateTime? lastCheckAt;

  /// Record a validation run.
  void recordCheck(IntegrityReport report) {
    totalChecks++;
    totalViolationsDetected += report.violations.length;
    totalRepairsApplied += report.repaired.length;
    lastCheckAt = DateTime.now();
  }

  /// Summary for diagnostics.
  Map<String, dynamic> toJson() => {
    'totalChecks': totalChecks,
    'totalViolationsDetected': totalViolationsDetected,
    'totalRepairsApplied': totalRepairsApplied,
    'lastCheckAt': lastCheckAt?.toIso8601String(),
  };

  /// Reset all counters (for testing).
  void reset() {
    totalChecks = 0;
    totalViolationsDetected = 0;
    totalRepairsApplied = 0;
    lastCheckAt = null;
  }
}

// =============================================================================
// Validator
// =============================================================================

/// Structural integrity validator and self-healer for [SceneGraph].
///
/// Call [validate] for read-only checking, or [validateAndRepair] to
/// automatically fix repairable violations.
///
/// ```dart
/// final violations = SceneGraphIntegrity.validate(graph);
/// if (violations.isNotEmpty) {
///   debugPrint('Found ${violations.length} integrity violations!');
///   final report = SceneGraphIntegrity.validateAndRepair(graph);
///   debugPrint('Repaired: ${report.repaired.length}');
/// }
/// ```
class SceneGraphIntegrity {
  SceneGraphIntegrity._();

  // ===========================================================================
  // Public API
  // ===========================================================================

  /// Validate all structural invariants. Returns list of violations.
  ///
  /// This is a **read-only** operation — no mutations are made.
  static List<IntegrityViolation> validate(SceneGraph graph) {
    final violations = <IntegrityViolation>[];

    _checkDuplicateIds(graph, violations);
    _checkParentPointers(graph, violations);
    _checkRootChildTypes(graph, violations);
    _checkSpatialIndexSync(graph, violations);
    _checkDirtyTrackerSync(graph, violations);
    _checkDepth(graph, violations);
    _checkCycles(graph, violations);
    _checkNodeIndexSync(graph, violations);

    return violations;
  }

  /// Validate and attempt to repair all fixable violations.
  static IntegrityReport validateAndRepair(SceneGraph graph) {
    final span =
        EngineScope.hasScope
            ? EngineScope.current.telemetry.startSpan('integrity.validate')
            : null;

    final violations = validate(graph);

    if (EngineScope.hasScope) {
      final t = EngineScope.current.telemetry;
      t.counter('integrity.checks').increment();
      t.counter('integrity.violations').increment(violations.length);
    }

    if (violations.isEmpty) {
      span?.end();
      final report = const IntegrityReport(violations: [], repaired: []);
      IntegrityMetrics.instance.recordCheck(report); // Fix 4: track clean runs
      return report;
    }

    final repaired = <IntegrityViolation>[];
    final repairedTypes = <ViolationType>{}; // Fix 3: deduplicate

    for (final v in violations) {
      if (!v.autoRepairable) continue;
      if (repairedTypes.contains(v.type)) {
        repaired.add(v); // Already repaired this type, just mark it
        continue;
      }

      switch (v.type) {
        case ViolationType.parentPointerMismatch:
          _repairParentPointers(graph);
          repairedTypes.add(v.type);
          repaired.add(v);

        case ViolationType.spatialIndexDesync:
          _repairSpatialIndex(graph);
          repairedTypes.add(v.type);
          repaired.add(v);

        case ViolationType.dirtyTrackerDesync:
          _repairDirtyTracker(graph);
          repairedTypes.add(v.type);
          repaired.add(v);

        case ViolationType.nodeIndexDesync:
          _repairNodeIndex(graph);
          repairedTypes.add(v.type);
          repaired.add(v);

        default:
          break; // Not auto-repairable
      }
    }

    final report = IntegrityReport(violations: violations, repaired: repaired);

    // --- Metrics ---
    IntegrityMetrics.instance.recordCheck(report);

    if (EngineScope.hasScope) {
      EngineScope.current.telemetry
          .counter('integrity.repairs')
          .increment(repaired.length);
    }
    span?.end();

    // --- ErrorRecovery integration ---
    _reportToErrorRecovery(violations, repaired);

    if (repaired.isNotEmpty) {
      debugPrint(
        '[SceneGraphIntegrity] Repaired ${repaired.length}/${violations.length} '
        'violations',
      );
    }

    return report;
  }

  /// Quick health check — returns true if graph passes all checks.
  ///
  /// Useful in debug assertions:
  /// ```dart
  /// assert(SceneGraphIntegrity.isHealthy(graph));
  /// ```
  static bool isHealthy(SceneGraph graph) => validate(graph).isEmpty;

  // ===========================================================================
  // Checks
  // ===========================================================================

  /// Check 1: No duplicate IDs in the tree.
  static void _checkDuplicateIds(
    SceneGraph graph,
    List<IntegrityViolation> violations,
  ) {
    final seen = <String>{};
    final duplicates = <String>{};

    void walk(CanvasNode node) {
      if (!seen.add(node.id)) {
        duplicates.add(node.id);
      }
      if (node is GroupNode) {
        for (final child in node.children) {
          walk(child);
        }
      }
    }

    walk(graph.rootNode);

    for (final id in duplicates) {
      violations.add(
        IntegrityViolation(
          type: ViolationType.duplicateId,
          nodeId: id,
          description: 'Duplicate node ID "$id" found in tree',
          autoRepairable: false,
        ),
      );
    }
  }

  /// Check 2: Every child's parent pointer matches its actual parent.
  static void _checkParentPointers(
    SceneGraph graph,
    List<IntegrityViolation> violations,
  ) {
    void walk(CanvasNode node, CanvasNode? expectedParent) {
      if (node.parent != expectedParent) {
        violations.add(
          IntegrityViolation(
            type: ViolationType.parentPointerMismatch,
            nodeId: node.id,
            description:
                'Node "${node.id}" parent pointer is '
                '${node.parent?.id ?? "null"}, expected '
                '${expectedParent?.id ?? "null"}',
            autoRepairable: true,
          ),
        );
      }
      if (node is GroupNode) {
        for (final child in node.children) {
          walk(child, node);
        }
      }
    }

    // Root's parent should be null
    walk(graph.rootNode, null);
  }

  /// Check 3: All direct children of root are LayerNodes.
  static void _checkRootChildTypes(
    SceneGraph graph,
    List<IntegrityViolation> violations,
  ) {
    for (final child in graph.rootNode.children) {
      if (child is! LayerNode) {
        violations.add(
          IntegrityViolation(
            type: ViolationType.invalidRootChild,
            nodeId: child.id,
            description:
                'Root child "${child.id}" is ${child.runtimeType}, '
                'expected LayerNode',
            autoRepairable: false,
          ),
        );
      }
    }
  }

  /// Check 4: Spatial index sync (both directions).
  ///
  /// - Tree→Index: leaf nodes with real bounds must be in the index.
  /// - Index→Tree: stale entries (more index entries than indexable nodes)
  ///   indicate ghost entries from removed nodes.
  static void _checkSpatialIndexSync(
    SceneGraph graph,
    List<IntegrityViolation> violations,
  ) {
    final indexableIds = <String>[];
    void collectIndexable(CanvasNode node) {
      if (node is! GroupNode) {
        final bounds = node.worldBounds;
        if (!bounds.isEmpty && bounds.isFinite) {
          indexableIds.add(node.id);
        }
      }
      if (node is GroupNode) {
        for (final child in node.children) {
          collectIndexable(child);
        }
      }
    }

    collectIndexable(graph.rootNode);

    // --- Tree→Index: missing entries ---
    bool anyMissing = false;
    for (final id in indexableIds) {
      if (!graph.spatialIndex.contains(id)) {
        anyMissing = true;
        break;
      }
    }

    // --- Index→Tree: stale ghost entries (Fix 5) ---
    final indexCount = graph.spatialIndex.nodeCount;
    final hasStale = indexCount > indexableIds.length;

    if (anyMissing || hasStale) {
      final parts = <String>[];
      if (anyMissing) parts.add('missing entries for indexable nodes');
      if (hasStale) {
        parts.add(
          'stale entries (index: $indexCount, expected: ${indexableIds.length})',
        );
      }
      violations.add(
        IntegrityViolation(
          type: ViolationType.spatialIndexDesync,
          description: 'Spatial index desync: ${parts.join("; ")}',
          autoRepairable: true,
        ),
      );
    }
  }

  /// Check 5: Dirty tracker registry matches tree nodes.
  ///
  /// Uses `DirtyTracker.isRegistered()` for a **pure, side-effect-free** check.
  /// Skips the root node (internal container, not registered in tracker).
  static void _checkDirtyTrackerSync(
    SceneGraph graph,
    List<IntegrityViolation> violations,
  ) {
    final tracker = graph.dirtyTracker;
    bool anyMissing = false;

    void checkNode(CanvasNode node) {
      // Skip root — it's an internal container, not registered in tracker.
      if (node.id != graph.rootNode.id) {
        if (!tracker.isRegistered(node.id)) {
          anyMissing = true;
          return;
        }
      }
      if (node is GroupNode) {
        for (final child in node.children) {
          if (anyMissing) return; // Early exit
          checkNode(child);
        }
      }
    }

    checkNode(graph.rootNode);

    if (anyMissing) {
      violations.add(
        IntegrityViolation(
          type: ViolationType.dirtyTrackerDesync,
          description:
              'Dirty tracker registry is out of sync — '
              'some tree nodes are not registered',
          autoRepairable: true,
        ),
      );
    }
  }

  /// Check 6: Tree depth doesn't exceed [kMaxTreeDepth].
  static void _checkDepth(
    SceneGraph graph,
    List<IntegrityViolation> violations,
  ) {
    int maxFound = 0;

    void walk(CanvasNode node, int depth) {
      if (depth > maxFound) maxFound = depth;
      if (depth > kMaxTreeDepth) return; // Stop early once detected
      if (node is GroupNode) {
        for (final child in node.children) {
          walk(child, depth + 1);
        }
      }
    }

    walk(graph.rootNode, 0);

    if (maxFound > kMaxTreeDepth) {
      violations.add(
        IntegrityViolation(
          type: ViolationType.depthOverflow,
          description: 'Tree depth $maxFound exceeds limit of $kMaxTreeDepth',
          autoRepairable: false,
        ),
      );
    }
  }

  /// Check 7: Detect cycles in parent chains.
  ///
  /// Walks each node's parent chain and verifies it terminates at null
  /// within [kMaxTreeDepth] steps. Catches cycles that bypass
  /// `GroupNode._assertNoCycle` (e.g. via deserialization or direct
  /// parent pointer corruption).
  static void _checkCycles(
    SceneGraph graph,
    List<IntegrityViolation> violations,
  ) {
    void walk(CanvasNode node) {
      // Walk parent chain — should reach null before kMaxTreeDepth steps.
      CanvasNode? current = node.parent;
      int steps = 0;
      while (current != null) {
        steps++;
        if (steps > kMaxTreeDepth || identical(current, node)) {
          violations.add(
            IntegrityViolation(
              type: ViolationType.cycle,
              nodeId: node.id,
              description:
                  'Cycle detected in parent chain of node "${node.id}"',
              autoRepairable: false,
            ),
          );
          return;
        }
        current = current.parent;
      }

      if (node is GroupNode) {
        for (final child in node.children) {
          walk(child);
        }
      }
    }

    walk(graph.rootNode);
  }

  /// Check 8: Node index (`_nodeIndex`) is in sync with the tree.
  ///
  /// Detects:
  /// - **Stale ghost entries**: IDs in the index that don't exist in the tree.
  /// - **Missing entries**: nodes in the tree that aren't indexed.
  static void _checkNodeIndexSync(
    SceneGraph graph,
    List<IntegrityViolation> violations,
  ) {
    final treeIds = <String>{};

    void walk(CanvasNode node, {bool isRoot = false}) {
      // Skip root — it's a synthetic container never registered in _nodeIndex.
      if (!isRoot) {
        treeIds.add(node.id);
      }
      if (node is GroupNode) {
        for (final child in node.children) {
          walk(child);
        }
      }
    }

    walk(graph.rootNode, isRoot: true);

    final indexIds = graph.nodeIndexIds;

    // Stale entries: in index, not in tree
    final stale = indexIds.difference(treeIds);
    // Missing entries: in tree, not in index
    final missing = treeIds.difference(indexIds);

    if (stale.isNotEmpty || missing.isNotEmpty) {
      final parts = <String>[];
      if (stale.isNotEmpty) {
        parts.add('${stale.length} stale ghost entries');
      }
      if (missing.isNotEmpty) {
        parts.add('${missing.length} missing index entries');
      }
      violations.add(
        IntegrityViolation(
          type: ViolationType.nodeIndexDesync,
          description: 'Node index desync: ${parts.join("; ")}',
          autoRepairable: true,
        ),
      );
    }
  }

  // ===========================================================================
  // Repairs
  // ===========================================================================

  /// Fix all parent pointers by walking the tree and re-assigning.
  static void _repairParentPointers(SceneGraph graph) {
    void walk(CanvasNode node, CanvasNode? expectedParent) {
      node.parent = expectedParent;
      if (node is GroupNode) {
        for (final child in node.children) {
          walk(child, node);
        }
      }
    }

    walk(graph.rootNode, null);
    debugPrint('[SceneGraphIntegrity] Parent pointers repaired');
  }

  /// Rebuild the spatial index from the tree.
  static void _repairSpatialIndex(SceneGraph graph) {
    graph.spatialIndex.rebuild(graph.allNodes);
    debugPrint('[SceneGraphIntegrity] Spatial index rebuilt');
  }

  /// Re-register all tree nodes in the dirty tracker.
  static void _repairDirtyTracker(SceneGraph graph) {
    graph.dirtyTracker.registerSubtree(graph.rootNode);
    debugPrint('[SceneGraphIntegrity] Dirty tracker re-synced');
  }

  /// Rebuild the node index from the tree.
  ///
  /// Removes stale ghost entries and adds missing nodes.
  static void _repairNodeIndex(SceneGraph graph) {
    graph.rebuildNodeIndex();
    debugPrint('[SceneGraphIntegrity] Node index rebuilt');
  }

  /// Report violations to the centralized ErrorRecoveryService as EngineErrors.
  static void _reportToErrorRecovery(
    List<IntegrityViolation> violations,
    List<IntegrityViolation> repaired,
  ) {
    if (!EngineScope.hasScope) return;

    for (final v in violations) {
      final wasRepaired = repaired.contains(v);
      EngineScope.current.errorRecovery.reportError(
        EngineError(
          severity: wasRepaired ? ErrorSeverity.degraded : ErrorSeverity.fatal,
          domain: ErrorDomain.sceneGraph,
          source: 'SceneGraphIntegrity.validateAndRepair',
          original: v.description,
          context: {
            'violationType': v.type.name,
            'nodeId': v.nodeId,
            'autoRepaired': wasRepaired,
          },
        ),
      );
    }
  }
}

// =============================================================================
// 🐕 Periodic Watchdog
// =============================================================================

/// Periodic background integrity validator for debug builds.
///
/// Runs [SceneGraphIntegrity.validateAndRepair] at a set interval,
/// catching corruption as soon as it happens rather than at save time.
///
/// ```dart
/// // In your canvas controller init:
/// final watchdog = IntegrityWatchdog(graph, interval: Duration(seconds: 30));
/// // ... later:
/// watchdog.dispose();
/// ```
class IntegrityWatchdog {
  final SceneGraph _graph;
  Timer? _timer;

  /// Create and start the watchdog.
  ///
  /// Only runs in debug/profile mode — no-op in release builds.
  IntegrityWatchdog(
    this._graph, {
    Duration interval = const Duration(seconds: 30),
  }) {
    // Only run in debug/profile — never in release.
    if (kReleaseMode) return;

    _timer = Timer.periodic(interval, (_) {
      final report = SceneGraphIntegrity.validateAndRepair(_graph);
      if (report.violations.isNotEmpty) {
        debugPrint(
          '[IntegrityWatchdog] Found ${report.violations.length} violations '
          '(${report.repaired.length} repaired, '
          '${report.unresolved.length} unresolved)',
        );
      }
    });
    debugPrint(
      '[IntegrityWatchdog] Started (interval: ${interval.inSeconds}s)',
    );
  }

  /// Whether the watchdog is actively monitoring.
  bool get isActive => _timer?.isActive ?? false;

  /// Stop the watchdog.
  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
