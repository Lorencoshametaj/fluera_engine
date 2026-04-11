import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/foundation.dart';
import './knowledge_connection.dart';
import './content_cluster.dart';
import './connection_suggestion_engine.dart';
import '../drawing/models/pro_drawing_point.dart';

/// 🧠 KNOWLEDGE FLOW CONTROLLER — Manages the knowledge graph.
///
/// Orchestrates connections between content clusters:
/// - CRUD operations on connections
/// - Bézier path computation for arrows
/// - Magnetic snap detection for connection creation
/// - Particle animation tick
/// - Serialization for canvas save/load
class KnowledgeFlowController {
  /// All connections in the knowledge graph.
  final List<KnowledgeConnection> _connections = [];

  /// Unmodifiable view of connections.
  List<KnowledgeConnection> get connections =>
      List.unmodifiable(_connections);

  /// Version counter — incremented on every mutation.
  /// KnowledgeFlowPainter listens to this for repaint.
  final ValueNotifier<int> version = ValueNotifier(0);

  /// Whether the knowledge flow system is active.
  bool enabled = true;

  // ===========================================================================
  // SUGGESTIONS
  // ===========================================================================

  /// Suggestion engine instance.
  final ConnectionSuggestionEngine _suggestionEngine =
      ConnectionSuggestionEngine();

  /// Current suggestions (recomputed on cluster changes).
  List<SuggestedConnection> _suggestions = [];

  /// Dismissed suggestion pair keys (persisted across recomputations).
  final Set<String> _dismissedPairKeys = {};

  /// 🚀 PERF: Cache hash of last cluster configuration to skip O(n²)
  /// recomputation when clusters haven't changed.
  String _lastSuggestionHash = '';

  /// Unmodifiable view of active (non-dismissed) suggestions.
  List<SuggestedConnection> get suggestions =>
      _suggestions.where((s) => !s.dismissed).toList();

  /// Recompute suggestions from current clusters and strokes.
  /// [clusterTexts] maps clusterId → recognized handwriting text for semantic signal.
  void recomputeSuggestions({
    required List<ContentCluster> clusters,
    required List<ProStroke> allStrokes,
    Map<String, String>? clusterTexts,
  }) {
    // 🚀 PERF: Skip recomputation if clusters haven't changed
    final ids = clusters.map((c) => '${c.id}:${c.elementCount}').toList()
      ..sort();
    final hash = ids.join('|');
    if (hash == _lastSuggestionHash && _suggestions.isNotEmpty) {
      return; // Clusters unchanged — skip expensive O(n²) scoring
    }
    _lastSuggestionHash = hash;

    // 🎯 ADAPTIVE: Fewer suggestions when canvas is already busy
    final existingCount = _connections.length;
    final adaptiveMax = existingCount <= 3 ? 3
        : existingCount <= 6 ? 2
        : 1;

    _suggestions = _suggestionEngine.computeSuggestions(
      clusters: clusters,
      allStrokes: allStrokes,
      existingConnections: _connections,
      clusterTexts: clusterTexts,
      maxSuggestions: adaptiveMax,
    );
    // Re-apply dismissals
    for (final s in _suggestions) {
      if (_dismissedPairKeys.contains(s.pairKey)) {
        s.dismissed = true;
      }
    }
    version.value++;
  }

  /// Accept a suggestion — convert it into a real connection.
  /// If the suggestion has shared keywords, auto-populate the connection label.
  KnowledgeConnection? acceptSuggestion(SuggestedConnection suggestion) {
    // Auto-label from shared keywords (e.g., "Newton, physics")
    final autoLabel = suggestion.sharedKeywords.isNotEmpty
        ? suggestion.sharedKeywords.take(3).join(', ')
        : null;

    final conn = addConnection(
      sourceClusterId: suggestion.sourceClusterId,
      targetClusterId: suggestion.targetClusterId,
      label: autoLabel,
    );
    if (conn != null) {
      // 🧠 LEARNING: Reinforce the winning signal
      // Use base reason for learning (strip "Shared: ..." prefix)
      final baseReason = suggestion.reason.startsWith('Shared:')
          ? 'Related content'
          : suggestion.reason;
      _suggestionEngine.reinforceAccept(baseReason);
      // Remove from suggestions
      _suggestions.removeWhere((s) => s.pairKey == suggestion.pairKey);
    }
    return conn;
  }

  /// Dismiss a suggestion — mark it and remember across recomputations.
  void dismissSuggestion(SuggestedConnection suggestion) {
    suggestion.dismissed = true;
    _dismissedPairKeys.add(suggestion.pairKey);
    // 🧠 LEARNING: Penalize the losing signal
    final baseReason = suggestion.reason.startsWith('Shared:')
        ? 'Related content'
        : suggestion.reason;
    _suggestionEngine.reinforceDismiss(baseReason);
    version.value++;
  }

  /// Hit-test suggestion midpoints. Returns the closest suggestion within
  /// [radius] canvas pixels to [canvasPoint], or null.
  SuggestedConnection? hitTestSuggestion(
    Offset canvasPoint,
    List<ContentCluster> clusters, {
    double radius = 25.0,
  }) {
    final activeSuggestions = suggestions;
    if (activeSuggestions.isEmpty) return null;

    final cMap = <String, ContentCluster>{};
    for (final c in clusters) {
      cMap[c.id] = c;
    }

    SuggestedConnection? best;
    double bestDist = radius;

    for (final s in activeSuggestions) {
      final src = cMap[s.sourceClusterId];
      final tgt = cMap[s.targetClusterId];
      if (src == null || tgt == null) continue;

      final midX = (src.centroid.dx + tgt.centroid.dx) / 2;
      final midY = (src.centroid.dy + tgt.centroid.dy) / 2;
      final dx = canvasPoint.dx - midX;
      final dy = canvasPoint.dy - midY;
      final dist = math.sqrt(dx * dx + dy * dy);

      if (dist < bestDist) {
        bestDist = dist;
        best = s;
      }
    }
    return best;
  }

  // ===========================================================================
  // CRUD
  // ===========================================================================

  /// Create a new connection between two clusters.
  ///
  /// Returns the created connection, or null if:
  /// - Source == target (self-loop)
  /// - Connection already exists between these clusters
  ///
  /// If [recordingTimestampMs] and [recordingId] are provided, the connection
  /// will be linked to that specific moment in the audio recording, enabling
  /// Flow Playback: tapping the connection seeks to that audio position.
  KnowledgeConnection? addConnection({
    required String sourceClusterId,
    required String targetClusterId,
    String? label,
    Color? color,
    Offset? sourceAnchor,
    Offset? targetAnchor,
    int? recordingTimestampMs,
    String? recordingId,
    bool isGhost = false,
  }) {
    // No self-loops
    if (sourceClusterId == targetClusterId) {
      debugPrint('🔗 [addConnection] BLOCKED: self-loop ($sourceClusterId)');
      return null;
    }

    // No duplicate connections (ghosts can coexist with pending ghosts)
    if (!isGhost) {
      final exists = _connections.any(
        (c) =>
            !c.isGhost &&
            ((c.sourceClusterId == sourceClusterId &&
                c.targetClusterId == targetClusterId) ||
            (c.sourceClusterId == targetClusterId &&
                c.targetClusterId == sourceClusterId)),
      );
      if (exists) {
        debugPrint('🔗 [addConnection] BLOCKED: duplicate '
            '($sourceClusterId ↔ $targetClusterId)');
        return null;
      }
    }

    final connection = KnowledgeConnection(
      id: _generateId(),
      sourceClusterId: sourceClusterId,
      targetClusterId: targetClusterId,
      label: label,
      color: color ?? KnowledgeConnection.mindMapPalette[
          _connections.length % KnowledgeConnection.mindMapPalette.length],
      sourceAnchor: sourceAnchor,
      targetAnchor: targetAnchor,
      recordingTimestampMs: recordingTimestampMs,
      recordingId: recordingId,
      isGhost: isGhost,
    );

    // Auto-classify cross-zone connections (P9-05):
    // If both anchors are set and spatially distant, mark as cross-zone.
    if (sourceAnchor != null && targetAnchor != null) {
      final dx = sourceAnchor.dx - targetAnchor.dx;
      final dy = sourceAnchor.dy - targetAnchor.dy;
      final dist = math.sqrt(dx * dx + dy * dy);
      if (dist > KnowledgeConnection.crossZoneDistanceThreshold) {
        connection.isCrossZone = true;
        // Apply golden color if no explicit color was provided
        if (color == null) {
          connection.color = KnowledgeConnection.crossZoneColor;
        }
      }
    }

    _connections.add(connection);
    _pushUndo(_ConnectionAction(
      type: _ActionType.add,
      connectionId: connection.id,
      snapshot: connection,
    ));
    version.value++;
    return connection;
  }

  /// Soft-delete a connection by ID (starts dissolve animation).
  /// The connection remains in the list with deletedAtMs set.
  /// Actual removal happens via [cleanupDyingConnections] after animation.
  bool removeConnection(String connectionId) {
    final conn = _connections.where((c) => c.id == connectionId).firstOrNull;
    if (conn == null) return false;
    // Snapshot before deletion for undo
    _pushUndo(_ConnectionAction(
      type: _ActionType.remove,
      connectionId: connectionId,
      snapshot: KnowledgeConnection(
        id: conn.id,
        sourceClusterId: conn.sourceClusterId,
        targetClusterId: conn.targetClusterId,
        label: conn.label,
        color: conn.color,
        curveStrength: conn.curveStrength,
        connectionType: conn.connectionType,
        isBidirectional: conn.isBidirectional,
        createdAt: 0,
      ),
    ));
    conn.deletedAtMs = DateTime.now().millisecondsSinceEpoch;
    version.value++;
    // Schedule actual cleanup after dissolve animation (500ms)
    Future.delayed(const Duration(milliseconds: 550), () {
      _connections.removeWhere((c) => c.id == connectionId);
      version.value++;
    });
    return true;
  }

  /// Remove all connections involving a cluster (call when cluster is deleted).
  void removeConnectionsForCluster(String clusterId) {
    _connections.removeWhere(
      (c) =>
          c.sourceClusterId == clusterId || c.targetClusterId == clusterId,
    );
    version.value++;
  }

  /// Get all connections involving a specific cluster.
  List<KnowledgeConnection> getConnectionsForCluster(String clusterId) {
    return _connections
        .where(
          (c) =>
              c.sourceClusterId == clusterId ||
              c.targetClusterId == clusterId,
        )
        .toList();
  }

  /// 🎯 Hit-test for connection control point dragging.
  ///
  /// Returns the connection whose midpoint is within [hitRadius] of [point],
  /// given the cluster map for computing anchor positions.
  /// Returns null if no connection midpoint is near the point.
  KnowledgeConnection? hitTestConnectionMidpoint(
    Offset point,
    Map<String, Offset> clusterCentroids, {
    double hitRadius = 25.0,
  }) {
    KnowledgeConnection? closest;
    double closestDist = hitRadius;

    for (final conn in _connections) {
      final srcPt = clusterCentroids[conn.sourceClusterId];
      final tgtPt = clusterCentroids[conn.targetClusterId];
      if (srcPt == null || tgtPt == null) continue;

      final cp = getControlPoint(srcPt, tgtPt, conn.curveStrength);
      final midPt = pointOnQuadBezier(srcPt, cp, tgtPt, 0.5);
      final dist = (midPt - point).distance;
      if (dist < closestDist) {
        closestDist = dist;
        closest = conn;
      }
    }
    return closest;
  }

  /// 🎨 Update the curve strength of a connection based on a drag offset.
  ///
  /// [dragPoint] is the current drag position in canvas coordinates.
  /// The curve strength is computed from the perpendicular distance
  /// of the drag point from the source→target line.
  void updateCurveStrength(
    String connectionId,
    Offset dragPoint,
    Map<String, Offset> clusterCentroids,
  ) {
    final conn = _connections.where((c) => c.id == connectionId).firstOrNull;
    if (conn == null) return;

    final srcPt = clusterCentroids[conn.sourceClusterId];
    final tgtPt = clusterCentroids[conn.targetClusterId];
    if (srcPt == null || tgtPt == null) return;

    final dx = tgtPt.dx - srcPt.dx;
    final dy = tgtPt.dy - srcPt.dy;
    final length = math.sqrt(dx * dx + dy * dy);
    if (length < 1.0) return;

    // Perpendicular distance of drag point from the src→tgt line
    final perpX = -dy / length;
    final perpY = dx / length;
    final midX = (srcPt.dx + tgtPt.dx) / 2;
    final midY = (srcPt.dy + tgtPt.dy) / 2;
    final offsetX = dragPoint.dx - midX;
    final offsetY = dragPoint.dy - midY;
    final perpDist = offsetX * perpX + offsetY * perpY;

    // Convert perpendicular distance to curve strength (normalized by line length)
    conn.curveStrength = (perpDist / length).clamp(-0.8, 0.8);
    version.value++;
  }

  /// Clear all connections.
  void clear() {
    _connections.clear();
    _undoStack.clear();
    _redoStack.clear();
    _selectedConnectionIds.clear();
    version.value++;
  }

  // ===========================================================================
  // AUTO-COLOR PER TYPE
  // ===========================================================================

  /// Semantic color for each connection type (used when user doesn't
  /// explicitly pick a color via the palette).
  static Color autoColorForType(ConnectionType type) {
    switch (type) {
      case ConnectionType.association:
        return const Color(0xFF64B5F6); // Blue 300
      case ConnectionType.causality:
        return const Color(0xFFFFB74D); // Orange 300
      case ConnectionType.hierarchy:
        return const Color(0xFF4FC3F7); // Light Blue 300
      case ConnectionType.contradiction:
        return const Color(0xFFEF5350); // Red 400
    }
  }

  // ===========================================================================
  // 2-HOP GRAPH HIGHLIGHT
  // ===========================================================================

  /// Returns the set of cluster IDs reachable from [startClusterId]
  /// within [maxHops] hops through connections.
  Set<String> getConnectedGraph(String startClusterId, {int maxHops = 2}) {
    final visited = <String>{startClusterId};
    var frontier = <String>{startClusterId};
    for (int hop = 0; hop < maxHops; hop++) {
      final nextFrontier = <String>{};
      for (final clusterId in frontier) {
        for (final conn in _connections) {
          if (conn.deletedAtMs > 0) continue;
          if (conn.sourceClusterId == clusterId &&
              !visited.contains(conn.targetClusterId)) {
            nextFrontier.add(conn.targetClusterId);
          }
          if (conn.targetClusterId == clusterId &&
              !visited.contains(conn.sourceClusterId)) {
            nextFrontier.add(conn.sourceClusterId);
          }
        }
      }
      visited.addAll(nextFrontier);
      frontier = nextFrontier;
      if (frontier.isEmpty) break;
    }
    return visited;
  }

  // ===========================================================================
  // MULTI-SELECT CONNECTIONS
  // ===========================================================================

  final Set<String> _selectedConnectionIds = {};
  Set<String> get selectedConnectionIds => _selectedConnectionIds;
  bool get isMultiSelecting => _selectedConnectionIds.isNotEmpty;

  /// Toggle a connection's selection state for multi-select operations.
  void toggleMultiSelect(String connectionId) {
    if (_selectedConnectionIds.contains(connectionId)) {
      _selectedConnectionIds.remove(connectionId);
    } else {
      _selectedConnectionIds.add(connectionId);
    }
    version.value++;
  }

  /// Clear multi-selection.
  void clearMultiSelect() {
    _selectedConnectionIds.clear();
    version.value++;
  }

  /// Select a single connection for focus/highlight (not multi-select).
  /// Clears multi-select and sets exactly one selected connection.
  void selectConnection(String connectionId) {
    _selectedConnectionIds.clear();
    _selectedConnectionIds.add(connectionId);
    version.value++;
  }

  /// Navigate to the next connection (cycles through all connections).
  /// Returns the navigated-to connection, or null if no connections exist.
  KnowledgeConnection? navigateToNextConnection(int currentIndex) {
    if (_connections.isEmpty) return null;
    final idx = (currentIndex + 1) % _connections.length;
    final conn = _connections[idx];
    selectConnection(conn.id);
    return conn;
  }

  /// Navigate to the previous connection (cycles through all connections).
  KnowledgeConnection? navigateToPrevConnection(int currentIndex) {
    if (_connections.isEmpty) return null;
    final idx = (currentIndex - 1 + _connections.length) % _connections.length;
    final conn = _connections[idx];
    selectConnection(conn.id);
    return conn;
  }

  // ===========================================================================
  // 🌉 CROSS-ZONE BRIDGES (Passo 9)
  // ===========================================================================

  /// Get all active cross-zone bridge connections (P9-05).
  ///
  /// Returns only non-ghost, non-deleted bridges. For ghost bridges
  /// (AI suggestions pending acceptance), filter with `isGhost == true`.
  List<KnowledgeConnection> getCrossZoneBridges({bool includeGhosts = false}) {
    return _connections
        .where((c) =>
            c.isCrossZone &&
            c.deletedAtMs == 0 &&
            (includeGhosts || !c.isGhost))
        .toList();
  }

  /// Navigate to the next cross-zone bridge (cycles through bridges only).
  ///
  /// Returns the bridge and selects it for highlight.
  /// Returns null if no cross-zone bridges exist.
  KnowledgeConnection? navigateToNextBridge(int currentIndex) {
    final bridges = getCrossZoneBridges();
    if (bridges.isEmpty) return null;
    final idx = (currentIndex + 1) % bridges.length;
    final bridge = bridges[idx];
    selectConnection(bridge.id);
    return bridge;
  }

  /// Count cross-zone bridges (for toolbar badge).
  int get crossZoneBridgeCount =>
      _connections.where((c) => c.isCrossZone && c.deletedAtMs == 0 && !c.isGhost).length;


  /// Apply an operation to all multi-selected connections.
  void applyToMultiSelected({
    ConnectionType? type,
    Color? color,
    bool? delete,
  }) {
    for (final id in _selectedConnectionIds.toList()) {
      if (delete == true) {
        removeConnection(id);
      } else {
        final conn = _connections.where((c) => c.id == id).firstOrNull;
        if (conn == null) continue;
        if (type != null) changeConnectionType(id, type);
        if (color != null) {
          _pushUndo(_ConnectionAction(
            type: _ActionType.modify,
            connectionId: id,
            oldValues: {'color': conn.color},
          ));
          conn.color = color;
        }
      }
    }
    _selectedConnectionIds.clear();
    version.value++;
  }

  // ===========================================================================
  // CONNECTION STATS PER CLUSTER
  // ===========================================================================

  /// Returns (outgoing, incoming) connection counts for a cluster.
  ({int outgoing, int incoming}) connectionStatsForCluster(String clusterId) {
    int outgoing = 0;
    int incoming = 0;
    for (final conn in _connections) {
      if (conn.deletedAtMs > 0) continue;
      if (conn.sourceClusterId == clusterId) outgoing++;
      if (conn.targetClusterId == clusterId) incoming++;
    }
    return (outgoing: outgoing, incoming: incoming);
  }

  // ===========================================================================
  // SNAP-TO-ANGLE CURVE DRAG
  // ===========================================================================

  /// Snap a drag point to the nearest 45° angle from the midpoint of
  /// the src→tgt line. Returns the snapped point.
  static Offset snapToAngle(Offset dragPoint, Offset midPoint, {double snapThreshold = 15.0}) {
    final dx = dragPoint.dx - midPoint.dx;
    final dy = dragPoint.dy - midPoint.dy;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist < 1.0) return dragPoint;

    // Current angle in 45° increments
    final angle = math.atan2(dy, dx);
    final snapAngle = (angle / (math.pi / 4)).round() * (math.pi / 4);

    // Check if close enough to snap
    final angleDiff = (angle - snapAngle).abs();
    if (angleDiff < snapThreshold / dist) {
      return Offset(
        midPoint.dx + dist * math.cos(snapAngle),
        midPoint.dy + dist * math.sin(snapAngle),
      );
    }
    return dragPoint;
  }

  // ===========================================================================
  // PATH TRACING ANIMATION
  // ===========================================================================

  /// The cluster ID currently being traced (null = no trace active).
  String? tracingClusterId;

  /// When the trace animation started (milliseconds since epoch).
  int tracingStartMs = 0;

  /// Ordered list of connection IDs in the trace, sorted by graph distance.
  List<String> tracingConnectionIds = [];

  /// Start a path trace animation from a cluster.
  /// Finds all connected connections and orders them by distance for staggered illumination.
  void startPathTrace(String clusterId) {
    final connected = getConnectionsForCluster(clusterId);
    if (connected.isEmpty) return;

    tracingClusterId = clusterId;
    tracingStartMs = DateTime.now().millisecondsSinceEpoch;
    tracingConnectionIds = connected.map((c) => c.id).toList();
    version.value++;
  }

  /// Check if a connection is currently being traced, and its flash intensity (0.0–1.0).
  /// Returns 0.0 if not tracing or connection is not part of the trace.
  double getTraceFlash(String connectionId, int nowMs) {
    if (tracingClusterId == null) return 0.0;
    final idx = tracingConnectionIds.indexOf(connectionId);
    if (idx < 0) return 0.0;

    // Each connection lights up 200ms after the previous one
    final elapsed = (nowMs - tracingStartMs) / 1000.0;
    final connectionDelay = idx * 0.2;
    final connectionAge = elapsed - connectionDelay;

    if (connectionAge < 0) return 0.0;
    if (connectionAge > 1.2) {
      // Trace finished for this connection
      if (idx == tracingConnectionIds.length - 1 && connectionAge > 1.5) {
        // Last connection finished → clear trace
        tracingClusterId = null;
        tracingConnectionIds = [];
      }
      return 0.0;
    }

    // Flash: bright at start (1.0), fade out over 1.2s
    return (1.0 - (connectionAge / 1.2)).clamp(0.0, 1.0);
  }

  // ===========================================================================
  // UNDO / REDO
  // ===========================================================================

  final List<_ConnectionAction> _undoStack = [];
  final List<_ConnectionAction> _redoStack = [];
  static const int _maxUndoHistory = 30;

  /// Whether undo is available.
  bool get canUndo => _undoStack.isNotEmpty;

  /// Whether redo is available.
  bool get canRedo => _redoStack.isNotEmpty;

  /// Record an action for undo.
  void _pushUndo(_ConnectionAction action) {
    _undoStack.add(action);
    if (_undoStack.length > _maxUndoHistory) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear(); // New action invalidates redo
  }

  /// Undo the last connection action.
  bool undo() {
    if (_undoStack.isEmpty) return false;
    final action = _undoStack.removeLast();

    switch (action.type) {
      case _ActionType.add:
        // Undo add = remove
        _connections.removeWhere((c) => c.id == action.connectionId);
        _redoStack.add(action);
        break;
      case _ActionType.remove:
        // Undo remove = re-add from snapshot
        if (action.snapshot != null) {
          _connections.add(action.snapshot!);
          _redoStack.add(action);
        }
        break;
      case _ActionType.modify:
        // Undo modify = restore old values
        final conn = _connections.where((c) => c.id == action.connectionId).firstOrNull;
        if (conn != null && action.oldValues != null) {
          final newSnapshot = _ConnectionAction(
            type: _ActionType.modify,
            connectionId: action.connectionId,
            oldValues: {
              'curveStrength': conn.curveStrength,
              'connectionType': conn.connectionType,
              'isBidirectional': conn.isBidirectional,
              'color': conn.color,
              'label': conn.label,
            },
          );
          _applyValues(conn, action.oldValues!);
          _redoStack.add(newSnapshot);
        }
        break;
    }

    version.value++;
    return true;
  }

  /// Redo the last undone action.
  bool redo() {
    if (_redoStack.isEmpty) return false;
    final action = _redoStack.removeLast();

    switch (action.type) {
      case _ActionType.add:
        // Redo add = re-add from snapshot
        if (action.snapshot != null) {
          _connections.add(action.snapshot!);
        }
        _undoStack.add(action);
        break;
      case _ActionType.remove:
        // Redo remove = remove again
        _connections.removeWhere((c) => c.id == action.connectionId);
        _undoStack.add(action);
        break;
      case _ActionType.modify:
        final conn = _connections.where((c) => c.id == action.connectionId).firstOrNull;
        if (conn != null && action.oldValues != null) {
          final newSnapshot = _ConnectionAction(
            type: _ActionType.modify,
            connectionId: action.connectionId,
            oldValues: {
              'curveStrength': conn.curveStrength,
              'connectionType': conn.connectionType,
              'isBidirectional': conn.isBidirectional,
              'color': conn.color,
              'label': conn.label,
            },
          );
          _applyValues(conn, action.oldValues!);
          _undoStack.add(newSnapshot);
        }
        break;
    }

    version.value++;
    return true;
  }

  /// Apply a map of values to a connection (for undo/redo).
  void _applyValues(KnowledgeConnection conn, Map<String, dynamic> values) {
    if (values.containsKey('curveStrength')) {
      conn.curveStrength = values['curveStrength'] as double;
    }
    if (values.containsKey('connectionType')) {
      conn.connectionType = values['connectionType'] as ConnectionType;
    }
    if (values.containsKey('isBidirectional')) {
      conn.isBidirectional = values['isBidirectional'] as bool;
    }
    if (values.containsKey('color')) {
      conn.color = values['color'] as Color;
    }
    if (values.containsKey('label')) {
      conn.label = values['label'] as String?;
    }
  }

  // ===========================================================================
  // CONNECTION SEARCH
  // ===========================================================================

  /// Search connections by label text (case-insensitive substring match).
  /// Returns matching connections, or empty list if query is empty.
  List<KnowledgeConnection> searchConnections(String query) {
    if (query.trim().isEmpty) return [];
    final q = query.toLowerCase();
    return _connections.where((c) =>
      c.label != null && c.label!.toLowerCase().contains(q)
    ).toList();
  }

  // ===========================================================================
  // TYPE & BIDIRECTIONAL MUTATION (with undo)
  // ===========================================================================

  /// Change a connection's type (with undo support).
  void changeConnectionType(String connectionId, ConnectionType newType) {
    final conn = _connections.where((c) => c.id == connectionId).firstOrNull;
    if (conn == null) return;
    _pushUndo(_ConnectionAction(
      type: _ActionType.modify,
      connectionId: connectionId,
      oldValues: {'connectionType': conn.connectionType},
    ));
    conn.connectionType = newType;
    conn.color = autoColorForType(newType);
    version.value++;
  }

  /// Toggle a connection's bidirectional state (with undo support).
  void toggleBidirectional(String connectionId) {
    final conn = _connections.where((c) => c.id == connectionId).firstOrNull;
    if (conn == null) return;
    _pushUndo(_ConnectionAction(
      type: _ActionType.modify,
      connectionId: connectionId,
      oldValues: {'isBidirectional': conn.isBidirectional},
    ));
    conn.isBidirectional = !conn.isBidirectional;
    version.value++;
  }

  /// 🔄 Remap connection cluster IDs after a full cluster rebuild.
  ///
  /// [oldClusters] is the cluster list BEFORE the rebuild.
  /// [freshClusters] is the cluster list AFTER the rebuild.
  ///
  /// Builds an oldId→newId map by matching stroke content overlap,
  /// then recreates connections with corrected IDs.
  void remapClusterIds(
    List<ContentCluster> oldClusters,
    List<ContentCluster> freshClusters,
  ) {
    if (_connections.isEmpty || freshClusters.isEmpty) return;

    // Build: strokeId → new cluster ID
    final strokeToNew = <String, String>{};
    for (final c in freshClusters) {
      for (final sid in c.strokeIds) strokeToNew[sid] = c.id;
      for (final sid in c.shapeIds) strokeToNew[sid] = c.id;
      for (final sid in c.textIds) strokeToNew[sid] = c.id;
      for (final sid in c.imageIds) strokeToNew[sid] = c.id;
    }

    // Build: oldClusterId → newClusterId
    // For each old cluster, find which new cluster contains the most
    // of its strokes — that’s the mapping.
    final oldToNew = <String, String>{};
    for (final old in oldClusters) {
      // Count votes: how many of this old cluster's strokes ended up
      // in each new cluster?
      final votes = <String, int>{};
      for (final sid in old.strokeIds) {
        final newId = strokeToNew[sid];
        if (newId != null) votes[newId] = (votes[newId] ?? 0) + 1;
      }
      for (final sid in old.shapeIds) {
        final newId = strokeToNew[sid];
        if (newId != null) votes[newId] = (votes[newId] ?? 0) + 1;
      }
      for (final sid in old.textIds) {
        final newId = strokeToNew[sid];
        if (newId != null) votes[newId] = (votes[newId] ?? 0) + 1;
      }
      for (final sid in old.imageIds) {
        final newId = strokeToNew[sid];
        if (newId != null) votes[newId] = (votes[newId] ?? 0) + 1;
      }

      if (votes.isNotEmpty) {
        // Pick the new cluster with the most overlapping strokes
        final best = votes.entries.reduce(
          (a, b) => a.value >= b.value ? a : b,
        );
        oldToNew[old.id] = best.key;
      }
    }

    // Also add identity mappings for fresh IDs (no remap needed)
    final freshIds = freshClusters.map((c) => c.id).toSet();
    for (final id in freshIds) {
      oldToNew.putIfAbsent(id, () => id);
    }

    // Rebuild connections with remapped IDs
    final updated = <KnowledgeConnection>[];
    for (final conn in _connections) {
      final newSrc = oldToNew[conn.sourceClusterId];
      final newTgt = oldToNew[conn.targetClusterId];

      // Skip if we can't remap either end
      if (newSrc == null || newTgt == null) continue;
      // Skip self-loops
      if (newSrc == newTgt) continue;

      updated.add(KnowledgeConnection(
        id: conn.id,
        sourceClusterId: newSrc,
        targetClusterId: newTgt,
        label: conn.label,
        color: conn.color,
        curveStrength: conn.curveStrength,
        createdAt: conn.createdAtMs, // 🔧 Preserve original timestamp!
      )..deletedAtMs = conn.deletedAtMs);
    }

    _connections
      ..clear()
      ..addAll(updated);
    version.value++;
  }

  // ===========================================================================
  // Hit Testing (for delete gesture)
  // ===========================================================================

  /// Find the closest connection to a canvas point.
  ///
  /// Samples points along each connection's Bézier curve and returns
  /// the connection whose curve passes closest to [canvasPoint],
  /// within [maxDistance] canvas-space pixels.
  /// Uses 4-way smart anchoring (matches painter).
  KnowledgeConnection? hitTestConnection(
    Offset canvasPoint,
    List<ContentCluster> clusters, {
    double maxDistance = 20.0,
  }) {
    if (_connections.isEmpty) return null;

    // Clamp to prevent absurdly large or tiny hit zones at extreme zoom
    final effectiveMaxDist = maxDistance.clamp(8.0, 40.0);

    final cMap = <String, ContentCluster>{};
    for (final c in clusters) {
      cMap[c.id] = c;
    }

    KnowledgeConnection? closest;
    double closestDist = effectiveMaxDist;

    for (final conn in _connections) {
      if (conn.deletedAtMs > 0) continue;
      final src = cMap[conn.sourceClusterId];
      final tgt = cMap[conn.targetClusterId];
      if (src == null || tgt == null) continue;

      // 4-WAY smart anchor (matches painter)
      final adx = (tgt.centroid.dx - src.centroid.dx).abs();
      final ady = (tgt.centroid.dy - src.centroid.dy).abs();
      final Offset srcPt;
      final Offset tgtPt;
      if (adx > ady * 1.5) {
        if (tgt.centroid.dx > src.centroid.dx) {
          srcPt = Offset(src.bounds.right + 4, src.bounds.center.dy);
          tgtPt = Offset(tgt.bounds.left - 4, tgt.bounds.center.dy);
        } else {
          srcPt = Offset(src.bounds.left - 4, src.bounds.center.dy);
          tgtPt = Offset(tgt.bounds.right + 4, tgt.bounds.center.dy);
        }
      } else {
        if (tgt.centroid.dy < src.centroid.dy) {
          srcPt = Offset(src.bounds.center.dx, src.bounds.top - 4);
          tgtPt = Offset(tgt.bounds.center.dx, tgt.bounds.bottom + 4);
        } else {
          srcPt = Offset(src.bounds.center.dx, src.bounds.bottom + 4);
          tgtPt = Offset(tgt.bounds.center.dx, tgt.bounds.top - 4);
        }
      }
      final cp = getControlPoint(srcPt, tgtPt, conn.curveStrength);

      for (int i = 0; i <= 20; i++) {
        final t = i / 20.0;
        final pt = pointOnQuadBezier(srcPt, cp, tgtPt, t);
        final dist = (pt - canvasPoint).distance;
        if (dist < closestDist) {
          closestDist = dist;
          closest = conn;
        }
      }
    }

    return closest;
  }

  /// Get the midpoint of a connection's curve (for label overlay positioning).
  Offset? getConnectionMidpoint(
    KnowledgeConnection conn,
    List<ContentCluster> clusters,
  ) {
    final cMap = <String, ContentCluster>{};
    for (final c in clusters) cMap[c.id] = c;
    final src = cMap[conn.sourceClusterId];
    final tgt = cMap[conn.targetClusterId];
    if (src == null || tgt == null) return null;

    final adx = (tgt.centroid.dx - src.centroid.dx).abs();
    final ady = (tgt.centroid.dy - src.centroid.dy).abs();
    final Offset srcPt;
    final Offset tgtPt;
    if (adx > ady * 1.5) {
      if (tgt.centroid.dx > src.centroid.dx) {
        srcPt = Offset(src.bounds.right + 4, src.bounds.center.dy);
        tgtPt = Offset(tgt.bounds.left - 4, tgt.bounds.center.dy);
      } else {
        srcPt = Offset(src.bounds.left - 4, src.bounds.center.dy);
        tgtPt = Offset(tgt.bounds.right + 4, tgt.bounds.center.dy);
      }
    } else {
      if (tgt.centroid.dy < src.centroid.dy) {
        srcPt = Offset(src.bounds.center.dx, src.bounds.top - 4);
        tgtPt = Offset(tgt.bounds.center.dx, tgt.bounds.bottom + 4);
      } else {
        srcPt = Offset(src.bounds.center.dx, src.bounds.bottom + 4);
        tgtPt = Offset(tgt.bounds.center.dx, tgt.bounds.top - 4);
      }
    }
    final cp = getControlPoint(srcPt, tgtPt, conn.curveStrength);
    return pointOnQuadBezier(srcPt, cp, tgtPt, 0.5);
  }

  // ===========================================================================
  // Bézier Path Computation
  // ===========================================================================

  /// Compute a cubic Bézier path between two cluster centroids.
  ///
  /// The curve bows perpendicular to the straight line, controlled
  /// by [curveStrength]. This creates elegant, non-overlapping arrows.
  Path computeBezierPath({
    required Offset source,
    required Offset target,
    double curveStrength = 0.3,
  }) {
    final path = Path();
    path.moveTo(source.dx, source.dy);

    final mid = Offset(
      (source.dx + target.dx) / 2,
      (source.dy + target.dy) / 2,
    );

    // Perpendicular offset for the curve
    final dx = target.dx - source.dx;
    final dy = target.dy - source.dy;
    final length = math.sqrt(dx * dx + dy * dy);
    if (length < 1.0) {
      path.lineTo(target.dx, target.dy);
      return path;
    }

    // Perpendicular direction (rotated 90°)
    final perpX = -dy / length;
    final perpY = dx / length;

    // Control point offset
    final offset = length * curveStrength;

    // Single control point for quadratic, or two for cubic
    final cp1 = Offset(
      mid.dx + perpX * offset,
      mid.dy + perpY * offset,
    );

    path.quadraticBezierTo(cp1.dx, cp1.dy, target.dx, target.dy);
    return path;
  }

  /// Compute the arrowhead triangle at the end of a Bézier path.
  ///
  /// Returns a Path for the filled triangle pointing in the
  /// direction of arrival at [target].
  Path computeArrowhead({
    required Offset target,
    required Offset controlPoint,
    double size = 10.0,
  }) {
    // Direction of arrival: from last control point to target
    final dx = target.dx - controlPoint.dx;
    final dy = target.dy - controlPoint.dy;
    final length = math.sqrt(dx * dx + dy * dy);
    if (length < 0.1) return Path();

    final nx = dx / length;
    final ny = dy / length;

    // Perpendicular
    final px = -ny;
    final py = nx;

    // Triangle vertices
    final tip = target;
    final left = Offset(
      tip.dx - nx * size + px * size * 0.4,
      tip.dy - ny * size + py * size * 0.4,
    );
    final right = Offset(
      tip.dx - nx * size - px * size * 0.4,
      tip.dy - ny * size - py * size * 0.4,
    );

    return Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(right.dx, right.dy)
      ..close();
  }

  /// Get the control point for a connection between two centroids.
  Offset getControlPoint(Offset source, Offset target, double curveStrength) {
    final mid = Offset(
      (source.dx + target.dx) / 2,
      (source.dy + target.dy) / 2,
    );

    final dx = target.dx - source.dx;
    final dy = target.dy - source.dy;
    final length = math.sqrt(dx * dx + dy * dy);
    if (length < 1.0) return mid;

    final perpX = -dy / length;
    final perpY = dx / length;
    final offset = length * curveStrength;

    return Offset(mid.dx + perpX * offset, mid.dy + perpY * offset);
  }

  /// Get a point along the quadratic Bézier curve at parameter [t] (0–1).
  Offset pointOnQuadBezier(Offset p0, Offset p1, Offset p2, double t) {
    final mt = 1.0 - t;
    return Offset(
      mt * mt * p0.dx + 2 * mt * t * p1.dx + t * t * p2.dx,
      mt * mt * p0.dy + 2 * mt * t * p1.dy + t * t * p2.dy,
    );
  }

  // ===========================================================================
  // Magnetic Snap
  // ===========================================================================

  /// Find the nearest cluster to a canvas point within [maxDistance].
  ///
  /// Used during connection drag to detect snap targets.
  /// Returns null if no cluster is close enough.
  ContentCluster? findNearestCluster(
    Offset canvasPoint,
    List<ContentCluster> clusters, {
    double maxDistance = 60.0,
    String? excludeClusterId,
  }) {
    ContentCluster? nearest;
    double nearestDist = maxDistance;

    for (final cluster in clusters) {
      if (cluster.id == excludeClusterId) continue;
      if (cluster.elementCount < 1) continue;

      // Use bounds-based distance: 0 if inside bounds, nearest-edge distance otherwise
      final inflated = cluster.bounds.inflate(10.0); // Small padding for easier tapping
      double dist;
      if (inflated.contains(canvasPoint)) {
        dist = 0.0; // Inside bounds = perfect hit
      } else {
        // Distance to nearest edge of bounds
        final dx = (canvasPoint.dx - canvasPoint.dx.clamp(inflated.left, inflated.right)).abs();
        final dy = (canvasPoint.dy - canvasPoint.dy.clamp(inflated.top, inflated.bottom)).abs();
        dist = math.sqrt(dx * dx + dy * dy);
      }
      if (dist < nearestDist) {
        nearestDist = dist;
        nearest = cluster;
      }
    }

    return nearest;
  }

  // ===========================================================================
  // Particle Animation
  // ===========================================================================

  /// Advance all particle animations by [dt] seconds.
  ///
  /// Call this from a Ticker callback (~60/120fps).
  /// Optionally pass [clusters] to lazily compute pathLength for speed-proportional particles.
  void tickParticles(double dt, [List<ContentCluster>? clusters]) {
    for (final connection in _connections) {
      // Lazy path length computation: only compute once per connection
      if (clusters != null && connection.pathLength == 500.0) {
        final src = clusters.where((c) => c.id == connection.sourceClusterId).firstOrNull;
        final tgt = clusters.where((c) => c.id == connection.targetClusterId).firstOrNull;
        if (src != null && tgt != null) {
          final dx = tgt.centroid.dx - src.centroid.dx;
          final dy = tgt.centroid.dy - src.centroid.dy;
          connection.pathLength = math.sqrt(dx * dx + dy * dy);
        }
      }
      connection.advanceParticles(dt);
    }
  }

  // ===========================================================================
  // Serialization
  // ===========================================================================

  Map<String, dynamic> toJson() => {
    'connections': _connections.map((c) => c.toJson()).toList(),
  };

  void loadFromJson(Map<String, dynamic> json) {
    _connections.clear();
    final list = json['connections'] as List<dynamic>? ?? [];
    for (final item in list) {
      _connections.add(
        KnowledgeConnection.fromJson(item as Map<String, dynamic>),
      );
    }
    version.value++;
  }

  // ===========================================================================
  // Utilities
  // ===========================================================================

  static String _generateId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final rand = math.Random().nextInt(0xFFFF);
    return 'kc_${now.toRadixString(36)}_${rand.toRadixString(36)}';
  }

  void dispose() {
    version.dispose();
  }
}

// =============================================================================
// UNDO TYPES (private to this file)
// =============================================================================

enum _ActionType { add, remove, modify }

class _ConnectionAction {
  final _ActionType type;
  final String connectionId;

  /// Full snapshot of the connection (for add/remove undo).
  final KnowledgeConnection? snapshot;

  /// Old field values before a modify (for modify undo).
  final Map<String, dynamic>? oldValues;

  _ConnectionAction({
    required this.type,
    required this.connectionId,
    this.snapshot,
    this.oldValues,
  });
}
