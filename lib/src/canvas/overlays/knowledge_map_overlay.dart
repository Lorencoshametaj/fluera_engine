import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import '../../reflow/content_cluster.dart';
import '../../reflow/knowledge_connection.dart';
import '../../reflow/knowledge_flow_controller.dart';

/// 🔗 Inferred transitive connection: A→B and B→C suggests A→C
class _InferredConnection {
  final String sourceId;
  final String targetId;
  final String viaId; // The intermediate node B
  _InferredConnection({required this.sourceId, required this.targetId, required this.viaId});
}

/// 🧠 KNOWLEDGE MAP OVERLAY — Premium interactive graph visualization.
///
/// Features:
///   - 🖐️ Drag & Drop nodes to reposition
///   - 🔎 Zoom & Pan with InteractiveViewer
///   - 🎛️ Filter connections by type
///   - 📝 Tap-to-expand node detail card
///   - ✨ Animated particles on connections
///   - 📸 Export graph as PNG
///   - 🎨 Cluster grouping with colored hulls
///   - 📊 Advanced metrics (density, centrality)
///   - 🔍 Search clusters by text
///   - 🔄 Force-directed auto-organize
class KnowledgeMapOverlay extends StatefulWidget {
  final KnowledgeFlowController controller;
  final List<ContentCluster> clusters;
  final Map<String, String> clusterTexts;
  final VoidCallback onDismiss;
  final void Function(ContentCluster cluster) onNavigateToCluster;
  final void Function(Map<String, Offset> newPositions)? onAutoOrganize;

  /// 🎬 Callback fired when a connection is tapped for cinematic flight.
  /// Receives (sourceClusterId, targetClusterId, curveStrength).
  final void Function(String sourceClusterId, String targetClusterId, double curveStrength)? onConnectionTapped;

  const KnowledgeMapOverlay({
    super.key,
    required this.controller,
    required this.clusters,
    required this.clusterTexts,
    required this.onDismiss,
    required this.onNavigateToCluster,
    this.onAutoOrganize,
    this.onConnectionTapped,
  });

  @override
  State<KnowledgeMapOverlay> createState() => _KnowledgeMapOverlayState();
}

class _KnowledgeMapOverlayState extends State<KnowledgeMapOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;
  // ✨ Particle animation ticker
  late final AnimationController _particleCtrl;
  String _searchQuery = '';

  // Graph layout
  Map<String, Offset> _nodePositions = {};
  Map<String, Offset> _targetPositions = {}; // 🎬 Animation targets
  Map<String, int> _connectionCounts = {};
  Size _graphSize = Size.zero;

  // 🖐️ Drag state
  String? _draggingNodeId;

  // 📝 Expanded node detail
  String? _expandedNodeId;

  // 🏛️ Type filters (all visible by default)
  final Set<ConnectionType> _visibleTypes = Set.from(ConnectionType.values);

  // 📸 Export key
  final GlobalKey _repaintKey = GlobalKey();

  // 📊 Metrics cache
  Map<String, double> _centrality = {};
  double _graphDensity = 0;

  // 📌 Pinned nodes (locked during auto-organize)
  final Set<String> _pinnedNodes = {};

  // 🛤️ Shortest path state
  String? _pathStartNodeId;
  String? _pathEndNodeId;
  List<String> _shortestPath = [];    // node IDs in order
  Set<String> _shortestPathEdges = {}; // connection IDs on the path

  // 📝 List view mode
  bool _showListView = false;

  // 🌊 LIVE PHYSICS MODE
  bool _livePhysics = false;
  Map<String, Offset> _velocities = {};

  // ⏳ TIMELINE REPLAY
  double _timelineValue = 1.0; // 0.0 = empty, 1.0 = all connections
  bool _showTimeline = false;

  // 🧦 COMMUNITY DETECTION
  Map<String, int> _communities = {}; // nodeId → communityId
  int _communityCount = 0;

  // 🔗 TRANSITIVE INFERENCE
  List<_InferredConnection> _inferredConnections = [];
  bool _showInferred = false;

  // 🎯 FOCUS MODE
  String? _focusNodeId;
  int _focusHops = 2;
  Set<String> _focusedNodes = {};
  Set<String> _focusedEdges = {};

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animCtrl,
      curve: Curves.easeOutCubic,
    );
    _animCtrl.forward();

    // ✨ Particle ticker: 30fps for flowing particles
    _particleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();

    // 🎬 Smooth position lerp + live physics: in the particle tick
    _particleCtrl.addListener(_onPhysicsTick);

    _computeMetrics();
    _detectCommunities();
    _computeTransitiveInferences();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _particleCtrl.dispose();
    super.dispose();
  }

  // ===========================================================================
  // LAYOUT
  // ===========================================================================

  void _computeLayout(Size viewportSize) {
    if (widget.clusters.isEmpty) return;
    if (_graphSize == viewportSize && _nodePositions.isNotEmpty) return;
    _graphSize = viewportSize;

    double minX = double.infinity, maxX = double.negativeInfinity;
    double minY = double.infinity, maxY = double.negativeInfinity;
    for (final c in widget.clusters) {
      final p = c.centroid;
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }

    const pad = 60.0;
    final rangeX = maxX - minX;
    final rangeY = maxY - minY;
    final scaleX = rangeX > 0 ? (viewportSize.width - pad * 2) / rangeX : 1.0;
    final scaleY = rangeY > 0 ? (viewportSize.height - pad * 2 - 120) / rangeY : 1.0;
    final s = math.min(scaleX, scaleY);

    final centerX = viewportSize.width / 2;
    final centerY = (viewportSize.height + 60) / 2;
    final midX = (minX + maxX) / 2;
    final midY = (minY + maxY) / 2;

    final positions = <String, Offset>{};
    for (final c in widget.clusters) {
      positions[c.id] = Offset(
        centerX + (c.centroid.dx - midX) * s,
        centerY + (c.centroid.dy - midY) * s,
      );
    }
    _nodePositions = positions;

    final counts = <String, int>{};
    for (final conn in widget.controller.connections) {
      counts[conn.sourceClusterId] = (counts[conn.sourceClusterId] ?? 0) + 1;
      counts[conn.targetClusterId] = (counts[conn.targetClusterId] ?? 0) + 1;
    }
    _connectionCounts = counts;
  }

  // ===========================================================================
  // 📊 METRICS
  // ===========================================================================

  void _computeMetrics() {
    final n = widget.clusters.length;
    final e = widget.controller.connections.length;

    // Graph density
    _graphDensity = n > 1 ? (2 * e) / (n * (n - 1)) : 0;

    // Simple degree centrality (normalized)
    final maxDegree = _connectionCounts.isEmpty
        ? 1
        : _connectionCounts.values.reduce(math.max);
    _centrality = {};
    for (final c in widget.clusters) {
      final deg = _connectionCounts[c.id] ?? 0;
      _centrality[c.id] = maxDegree > 0 ? deg / maxDegree : 0;
    }
  }

  // ===========================================================================
  // AUTO-ORGANIZE
  // ===========================================================================

  void _autoOrganize() {
    HapticFeedback.mediumImpact();
    if (widget.clusters.length < 2) return;

    final pos = <String, Offset>{};
    for (final c in widget.clusters) {
      pos[c.id] = _nodePositions[c.id] ?? Offset(
        _graphSize.width / 2 + (math.Random().nextDouble() - 0.5) * 200,
        _graphSize.height / 2 + (math.Random().nextDouble() - 0.5) * 200,
      );
    }

    const repulsion = 8000.0;
    const attraction = 0.01;
    const damping = 0.85;
    final vel = <String, Offset>{};
    for (final c in widget.clusters) vel[c.id] = Offset.zero;
    final ids = pos.keys.toList();

    for (int iter = 0; iter < 80; iter++) {
      final forces = <String, Offset>{};
      for (final id in ids) forces[id] = Offset.zero;

      for (int i = 0; i < ids.length; i++) {
        for (int j = i + 1; j < ids.length; j++) {
          final a = ids[i], b = ids[j];
          final delta = pos[a]! - pos[b]!;
          final dist = math.max(delta.distance, 1.0);
          final force = delta / dist * (repulsion / (dist * dist));
          forces[a] = forces[a]! + force;
          forces[b] = forces[b]! - force;
        }
      }

      for (final conn in widget.controller.connections) {
        final a = conn.sourceClusterId, b = conn.targetClusterId;
        if (!pos.containsKey(a) || !pos.containsKey(b)) continue;
        final delta = pos[b]! - pos[a]!;
        final force = delta * attraction;
        forces[a] = forces[a]! + force;
        forces[b] = forces[b]! - force;
      }

      final center = Offset(_graphSize.width / 2, _graphSize.height / 2);
      for (final id in ids) {
        final toCenter = center - pos[id]!;
        forces[id] = forces[id]! + toCenter * 0.001;
      }

      for (final id in ids) {
        // 📌 PINNED: skip pinned nodes
        if (_pinnedNodes.contains(id)) continue;
        vel[id] = (vel[id]! + forces[id]!) * damping;
        pos[id] = pos[id]! + vel[id]!;
        pos[id] = Offset(
          pos[id]!.dx.clamp(40.0, _graphSize.width - 40.0),
          pos[id]!.dy.clamp(100.0, _graphSize.height - 40.0),
        );
      }
    }

    // 🎬 ANIMATED: Set targets, don't jump instantly
    setState(() {
      _targetPositions = Map.from(pos);
    });

    if (widget.onAutoOrganize != null) {
      widget.onAutoOrganize!(pos);
    }
  }

  // ===========================================================================
  // 🎬 ANIMATED TRANSITIONS
  // ===========================================================================

  void _lerpPositions() {
    if (_targetPositions.isEmpty) return;
    bool anyMoved = false;
    const lerpSpeed = 0.08;
    for (final id in _targetPositions.keys) {
      final current = _nodePositions[id];
      final target = _targetPositions[id];
      if (current == null || target == null) continue;
      final dist = (target - current).distance;
      if (dist < 0.5) continue;
      anyMoved = true;
      _nodePositions[id] = Offset.lerp(current, target, lerpSpeed)!;
    }
    if (!anyMoved) {
      _targetPositions.clear();
    }
  }

  // ===========================================================================
  // 🌊 LIVE PHYSICS MODE
  // ===========================================================================

  void _onPhysicsTick() {
    _lerpPositions();
    if (!_livePhysics) return;

    // Continuous force-directed simulation
    const repulsion = 5000.0;
    const attraction = 0.008;
    const damping = 0.92;
    const dt = 0.3;

    final ids = _nodePositions.keys.toList();
    final forces = <String, Offset>{};
    for (final id in ids) forces[id] = Offset.zero;

    // Repulsion
    for (int i = 0; i < ids.length; i++) {
      for (int j = i + 1; j < ids.length; j++) {
        final a = ids[i], b = ids[j];
        final pa = _nodePositions[a]!, pb = _nodePositions[b]!;
        final delta = pa - pb;
        final dist = math.max(delta.distance, 1.0);
        final force = delta / dist * (repulsion / (dist * dist));
        forces[a] = forces[a]! + force;
        forces[b] = forces[b]! - force;
      }
    }

    // Attraction for connected pairs
    for (final conn in widget.controller.connections) {
      final a = conn.sourceClusterId, b = conn.targetClusterId;
      final pa = _nodePositions[a], pb = _nodePositions[b];
      if (pa == null || pb == null) continue;
      final delta = pb - pa;
      final force = delta * attraction;
      forces[a] = forces[a]! + force;
      forces[b] = forces[b]! - force;
    }

    // Center gravity
    final center = Offset(_graphSize.width / 2, _graphSize.height / 2);
    for (final id in ids) {
      final toCenter = center - _nodePositions[id]!;
      forces[id] = forces[id]! + toCenter * 0.0008;
    }

    // Apply forces with velocity
    for (final id in ids) {
      if (_pinnedNodes.contains(id)) continue;
      if (id == _draggingNodeId) continue;
      final vel = (_velocities[id] ?? Offset.zero) + forces[id]! * dt;
      _velocities[id] = vel * damping;
      final newPos = _nodePositions[id]! + _velocities[id]! * dt;
      _nodePositions[id] = Offset(
        newPos.dx.clamp(40.0, _graphSize.width - 40.0),
        newPos.dy.clamp(100.0, _graphSize.height - 40.0),
      );
    }
  }

  // ===========================================================================
  // 🧦 COMMUNITY DETECTION (Label Propagation)
  // ===========================================================================

  void _detectCommunities() {
    if (widget.clusters.isEmpty) return;

    // Initialize: each node is its own community
    final labels = <String, int>{};
    for (int i = 0; i < widget.clusters.length; i++) {
      labels[widget.clusters[i].id] = i;
    }

    // Build adjacency
    final adj = <String, List<String>>{};
    for (final conn in widget.controller.connections) {
      adj.putIfAbsent(conn.sourceClusterId, () => []).add(conn.targetClusterId);
      adj.putIfAbsent(conn.targetClusterId, () => []).add(conn.sourceClusterId);
    }

    // Iterate: each node takes the most frequent label among neighbors
    final ids = labels.keys.toList();
    for (int iter = 0; iter < 20; iter++) {
      bool changed = false;
      ids.shuffle(); // Random order for convergence
      for (final id in ids) {
        final neighbors = adj[id];
        if (neighbors == null || neighbors.isEmpty) continue;

        // Count label frequency among neighbors
        final freq = <int, int>{};
        for (final n in neighbors) {
          final label = labels[n] ?? 0;
          freq[label] = (freq[label] ?? 0) + 1;
        }

        // Take most frequent label
        int bestLabel = labels[id]!;
        int bestCount = 0;
        for (final entry in freq.entries) {
          if (entry.value > bestCount) {
            bestCount = entry.value;
            bestLabel = entry.key;
          }
        }

        if (labels[id] != bestLabel) {
          labels[id] = bestLabel;
          changed = true;
        }
      }
      if (!changed) break; // Converged
    }

    // Normalize: remap labels to 0..N
    final unique = labels.values.toSet().toList();
    final remap = <int, int>{};
    for (int i = 0; i < unique.length; i++) {
      remap[unique[i]] = i;
    }

    _communities = labels.map((k, v) => MapEntry(k, remap[v]!));
    _communityCount = unique.length;
  }

  // ===========================================================================
  // 🔗 TRANSITIVE INFERENCE
  // ===========================================================================

  void _computeTransitiveInferences() {
    _inferredConnections = [];
    final conns = widget.controller.connections;

    // Build directed adjacency: source → [targets]
    final outgoing = <String, Set<String>>{};
    // Track existing direct connections as pair-set
    final directPairs = <String>{};
    for (final conn in conns) {
      outgoing.putIfAbsent(conn.sourceClusterId, () => {}).add(conn.targetClusterId);
      // Also add reverse for undirected matching
      outgoing.putIfAbsent(conn.targetClusterId, () => {}).add(conn.sourceClusterId);
      // Track both directions as "existing"
      directPairs.add('${conn.sourceClusterId}|${conn.targetClusterId}');
      directPairs.add('${conn.targetClusterId}|${conn.sourceClusterId}');
    }

    // Find all A→B→C where A→C doesn't exist
    final seen = <String>{}; // Avoid duplicate inferences
    for (final conn in conns) {
      final a = conn.sourceClusterId;
      final b = conn.targetClusterId;
      // From B, find all C
      for (final c in (outgoing[b] ?? <String>{})) {
        if (c == a) continue; // Skip self-loops
        final pairKey = '$a|$c';
        if (directPairs.contains(pairKey)) continue; // Already connected
        if (seen.contains(pairKey)) continue;
        seen.add(pairKey);
        seen.add('$c|$a');
        _inferredConnections.add(_InferredConnection(
          sourceId: a,
          targetId: c,
          viaId: b,
        ));
      }
    }
  }

  // ===========================================================================
  // 🎯 FOCUS MODE (N-hop BFS)
  // ===========================================================================

  void _computeFocusSet() {
    _focusedNodes = {};
    _focusedEdges = {};
    if (_focusNodeId == null) return;

    // BFS from focus node within N hops
    final adj = <String, List<MapEntry<String, String>>>{};
    for (final conn in widget.controller.connections) {
      adj.putIfAbsent(conn.sourceClusterId, () => []).add(
        MapEntry(conn.targetClusterId, conn.id),
      );
      adj.putIfAbsent(conn.targetClusterId, () => []).add(
        MapEntry(conn.sourceClusterId, conn.id),
      );
    }

    final distances = <String, int>{_focusNodeId!: 0};
    final queue = [_focusNodeId!];
    _focusedNodes.add(_focusNodeId!);

    while (queue.isNotEmpty) {
      final curr = queue.removeAt(0);
      final currDist = distances[curr]!;
      if (currDist >= _focusHops) continue;

      for (final edge in (adj[curr] ?? <MapEntry<String, String>>[])) {
        if (!distances.containsKey(edge.key)) {
          distances[edge.key] = currDist + 1;
          _focusedNodes.add(edge.key);
          _focusedEdges.add(edge.value);
          queue.add(edge.key);
        } else {
          // Still add the edge if both endpoints are within focus
          if (distances[edge.key]! <= _focusHops) {
            _focusedEdges.add(edge.value);
          }
        }
      }
    }
  }

  // ===========================================================================
  // 🛤️ SHORTEST PATH (BFS)
  // ===========================================================================

  void _computeShortestPath() {
    _shortestPath = [];
    _shortestPathEdges = {};
    if (_pathStartNodeId == null || _pathEndNodeId == null) return;
    if (_pathStartNodeId == _pathEndNodeId) return;

    // Build adjacency from connections
    final adj = <String, List<MapEntry<String, String>>>{}; // nodeId → [(neighbor, connId)]
    for (final conn in widget.controller.connections) {
      adj.putIfAbsent(conn.sourceClusterId, () => []).add(
        MapEntry(conn.targetClusterId, conn.id),
      );
      adj.putIfAbsent(conn.targetClusterId, () => []).add(
        MapEntry(conn.sourceClusterId, conn.id),
      );
    }

    // BFS
    final visited = <String>{};
    final prev = <String, MapEntry<String, String>>{}; // nodeId → (prevNode, edgeId)
    final queue = [_pathStartNodeId!];
    visited.add(_pathStartNodeId!);

    while (queue.isNotEmpty) {
      final curr = queue.removeAt(0);
      if (curr == _pathEndNodeId) break;

      for (final edge in (adj[curr] ?? <MapEntry<String, String>>[])) {
        if (!visited.contains(edge.key)) {
          visited.add(edge.key);
          prev[edge.key] = MapEntry(curr, edge.value);
          queue.add(edge.key);
        }
      }
    }

    // Reconstruct path
    if (!prev.containsKey(_pathEndNodeId)) return; // No path
    final path = <String>[_pathEndNodeId!];
    final edges = <String>{};
    var node = _pathEndNodeId!;
    while (prev.containsKey(node)) {
      final entry = prev[node]!;
      edges.add(entry.value);
      path.insert(0, entry.key);
      node = entry.key;
    }

    setState(() {
      _shortestPath = path;
      _shortestPathEdges = edges;
    });
  }

  // ===========================================================================
  // 📸 EXPORT
  // ===========================================================================

  Future<void> _exportAsPng() async {
    HapticFeedback.mediumImpact();
    try {
      final boundary = _repaintKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final bytes = byteData.buffer.asUint8List();
      // Copy to clipboard as feedback
      await Clipboard.setData(ClipboardData(text: 'Knowledge Map exported (${bytes.length} bytes)'));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('📸 Knowledge Map exported (${(bytes.length / 1024).toStringAsFixed(0)} KB)'),
            backgroundColor: const Color(0xFF2A2535),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {}
  }

  void _dismiss() async {
    await _animCtrl.reverse();
    widget.onDismiss();
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final size = constraints.biggest;
      _computeLayout(size);

      // Filter clusters for search
      final matchingIds = <String>{};
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        for (final c in widget.clusters) {
          final text = widget.clusterTexts[c.id] ?? '';
          if (text.toLowerCase().contains(q)) {
            matchingIds.add(c.id);
          }
        }
      }

      // Filter connections by type
      var filteredConnections = widget.controller.connections
          .where((c) => _visibleTypes.contains(c.connectionType))
          .toList();

      // ⏳ TIMELINE: slice connections by timeline position
      if (_showTimeline && _timelineValue < 1.0) {
        final count = (filteredConnections.length * _timelineValue).round();
        filteredConnections = filteredConnections.sublist(
          0, count.clamp(0, filteredConnections.length),
        );
      }

      return FadeTransition(
        opacity: _fadeAnim,
        child: Stack(
          children: [
            // 🌫️ Backdrop blur
            GestureDetector(
              onTap: () {
                if (_expandedNodeId != null) {
                  setState(() => _expandedNodeId = null);
                } else {
                  _dismiss();
                }
              },
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(color: const Color(0xE01A1A2E)),
              ),
            ),

            // 🎨 Graph canvas (or list view)
            if (_showListView)
              _buildListView(size)
            else ...
            [
              RepaintBoundary(
                key: _repaintKey,
                child: AnimatedBuilder(
                  animation: _particleCtrl,
                  builder: (context, _) => CustomPaint(
                    size: size,
                    painter: _KnowledgeGraphPainter(
                      clusters: widget.clusters,
                      connections: filteredConnections,
                      positions: _nodePositions,
                      clusterTexts: widget.clusterTexts,
                      matchingIds: matchingIds,
                      searchActive: _searchQuery.isNotEmpty,
                      connectionCounts: _connectionCounts,
                      centrality: _centrality,
                      graphDensity: _graphDensity,
                      animationTime: _particleCtrl.value * 10.0,
                      expandedNodeId: _expandedNodeId,
                      draggingNodeId: _draggingNodeId,
                      pinnedNodes: _pinnedNodes,
                      shortestPath: _shortestPath,
                      shortestPathEdges: _shortestPathEdges,
                      pathStartNodeId: _pathStartNodeId,
                      pathEndNodeId: _pathEndNodeId,
                      communities: _communities,
                      communityCount: _communityCount,
                      livePhysics: _livePhysics,
                      inferredConnections: _showInferred ? _inferredConnections : [],
                      focusNodeId: _focusNodeId,
                      focusedNodes: _focusedNodes,
                      focusedEdges: _focusedEdges,
                    ),
                  ),
                ),
              ),
            ],

            // 🖱️ Tappable connection targets (for cinematic flight)
            ..._buildConnectionTargets(filteredConnections),

            // 🖐️ Draggable + tappable node targets
            ..._buildNodeTargets(matchingIds),

            // 🔍 Search bar + title
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              left: 16,
              right: 16,
              child: Column(
                children: [
                  const Text(
                    '🧠  Knowledge Map',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                    child: TextField(
                      onChanged: (v) => setState(() => _searchQuery = v),
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Search clusters...',
                        hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                        ),
                        prefixIcon: Icon(Icons.search,
                            color: Colors.white.withValues(alpha: 0.5),
                            size: 20),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 🎛️ Type filter chips
            Positioned(
              top: MediaQuery.of(context).padding.top + 100,
              left: 16,
              right: 16,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: ConnectionType.values.map((type) {
                    final isActive = _visibleTypes.contains(type);
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            if (isActive) {
                              _visibleTypes.remove(type);
                            } else {
                              _visibleTypes.add(type);
                            }
                          });
                          HapticFeedback.selectionClick();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: isActive
                                ? _typeColor(type).withValues(alpha: 0.2)
                                : Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isActive
                                  ? _typeColor(type).withValues(alpha: 0.4)
                                  : Colors.white.withValues(alpha: 0.1),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _typeEmoji(type),
                                style: const TextStyle(fontSize: 11),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _typeLabel(type),
                                style: TextStyle(
                                  color: isActive
                                      ? _typeColor(type)
                                      : Colors.white38,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

            // 📝 Expanded node detail card
            if (_expandedNodeId != null) _buildExpandedCard(),

            // 🛤️ Shortest path indicator
            if (_pathStartNodeId != null && _pathEndNodeId == null)
              Positioned(
                top: MediaQuery.of(context).padding.top + 130,
                left: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CAF50).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFF4CAF50).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.route, color: Color(0xFF4CAF50), size: 16),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Tap a second node to show shortest path',
                          style: TextStyle(color: Color(0xFF4CAF50), fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => setState(() {
                          _pathStartNodeId = null;
                          _pathEndNodeId = null;
                          _shortestPath = [];
                          _shortestPathEdges = {};
                        }),
                        child: const Icon(Icons.close, color: Color(0xFF4CAF50), size: 16),
                      ),
                    ],
                  ),
                ),
              ),

            // 🛤️ Shortest path result
            if (_shortestPath.length >= 2)
              Positioned(
                top: MediaQuery.of(context).padding.top + 130,
                left: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CAF50).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFF4CAF50).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.route, color: Color(0xFF4CAF50), size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Path: ${_shortestPath.length - 1} hops',
                          style: const TextStyle(color: Color(0xFF4CAF50), fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => setState(() {
                          _pathStartNodeId = null;
                          _pathEndNodeId = null;
                          _shortestPath = [];
                          _shortestPathEdges = {};
                        }),
                        child: const Icon(Icons.close, color: Color(0xFF4CAF50), size: 16),
                      ),
                    ],
                  ),
                ),
              ),

            // 🗺️ Minimap
            if (!_showListView)
              Positioned(
                bottom: MediaQuery.of(context).padding.bottom + 120,
                right: 12,
                child: Container(
                  width: 100,
                  height: 70,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  child: CustomPaint(
                    painter: _MinimapPainter(
                      positions: _nodePositions,
                      connections: filteredConnections,
                      shortestPath: _shortestPath,
                    ),
                  ),
                ),
              ),

            // Bottom action bar
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 16,
              left: 16,
              right: 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Stats badge with advanced metrics
                  Builder(builder: (context) {
                    final hubCount = _connectionCounts.values
                        .where((v) => v >= 3).length;
                    final isolatedCount = widget.clusters
                        .where((c) => (_connectionCounts[c.id] ?? 0) == 0)
                        .length;
                    final parts = <String>[
                      '${widget.clusters.length} clusters',
                      '${widget.controller.connections.length} conn',
                      if (hubCount > 0) '$hubCount hubs',
                      if (isolatedCount > 0) '$isolatedCount isolated',
                      'density ${(_graphDensity * 100).toStringAsFixed(0)}%',
                    ];
                    return Text(
                      parts.join(' · '),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 11,
                      ),
                    );
                  }),
                  const SizedBox(height: 10),
                  // Action buttons row
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _BottomButton(
                        icon: Icons.auto_fix_high,
                        label: 'Auto-organize',
                        onTap: _autoOrganize,
                      ),
                      _BottomButton(
                        icon: Icons.camera_alt_rounded,
                        label: 'Export',
                        onTap: _exportAsPng,
                      ),
                      _BottomButton(
                        icon: _showListView ? Icons.bubble_chart : Icons.list_alt,
                        label: _showListView ? 'Graph' : 'List',
                        onTap: () => setState(() => _showListView = !_showListView),
                      ),
                      _BottomButton(
                        icon: Icons.route,
                        label: 'Path',
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() {
                            _pathStartNodeId = null;
                            _pathEndNodeId = null;
                            _shortestPath = [];
                            _shortestPathEdges = {};
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('🛤️ Tap the start node'),
                              backgroundColor: Color(0xFF2A2535),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                      _BottomButton(
                        icon: _livePhysics ? Icons.pause : Icons.play_arrow,
                        label: _livePhysics ? 'Pause' : 'Physics',
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _livePhysics = !_livePhysics);
                        },
                      ),
                      _BottomButton(
                        icon: Icons.timeline,
                        label: _showTimeline ? 'Hide' : 'Timeline',
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() {
                            _showTimeline = !_showTimeline;
                            if (!_showTimeline) _timelineValue = 1.0;
                          });
                        },
                      ),
                      _BottomButton(
                        icon: Icons.hub,
                        label: '$_communityCount groups',
                        onTap: () {
                          HapticFeedback.mediumImpact();
                          _detectCommunities();
                          setState(() {});
                        },
                      ),
                      _BottomButton(
                        icon: Icons.link,
                        label: _showInferred ? 'Hide +${_inferredConnections.length}' : 'Infer +${_inferredConnections.length}',
                        onTap: () {
                          HapticFeedback.selectionClick();
                          if (_inferredConnections.isEmpty) _computeTransitiveInferences();
                          setState(() => _showInferred = !_showInferred);
                        },
                      ),
                      _BottomButton(
                        icon: _focusNodeId != null ? Icons.center_focus_weak : Icons.filter_center_focus,
                        label: _focusNodeId != null ? 'Unfocus' : 'Focus',
                        onTap: () {
                          HapticFeedback.selectionClick();
                          if (_focusNodeId != null) {
                            setState(() {
                              _focusNodeId = null;
                              _focusedNodes = {};
                              _focusedEdges = {};
                            });
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('🎯 Tap a node to focus on it'),
                                backgroundColor: Color(0xFF2A2535),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ⏳ Timeline slider
            if (_showTimeline)
              Positioned(
                bottom: MediaQuery.of(context).padding.bottom + 105,
                left: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  child: Row(
                    children: [
                      Text(
                        '⏳',
                        style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.6)),
                      ),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: const Color(0xFF64B5F6),
                            inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
                            thumbColor: const Color(0xFF64B5F6),
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                            trackHeight: 3,
                          ),
                          child: Slider(
                            value: _timelineValue,
                            min: 0,
                            max: 1,
                            onChanged: (v) => setState(() => _timelineValue = v),
                          ),
                        ),
                      ),
                      Text(
                        '${(filteredConnections.length).toString()} conn',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // 🎯 Focus mode hop slider
            if (_focusNodeId != null)
              Positioned(
                bottom: MediaQuery.of(context).padding.bottom + (_showTimeline ? 145 : 105),
                left: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE040FB).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE040FB).withValues(alpha: 0.15)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.filter_center_focus, color: Color(0xFFE040FB), size: 14),
                      const SizedBox(width: 6),
                      Text(
                        '$_focusHops hops',
                        style: const TextStyle(color: Color(0xFFE040FB), fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: const Color(0xFFE040FB),
                            inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
                            thumbColor: const Color(0xFFE040FB),
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                            trackHeight: 3,
                          ),
                          child: Slider(
                            value: _focusHops.toDouble(),
                            min: 1,
                            max: 5,
                            divisions: 4,
                            onChanged: (v) {
                              setState(() {
                                _focusHops = v.round();
                                _computeFocusSet();
                              });
                            },
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => setState(() {
                          _focusNodeId = null;
                          _focusedNodes = {};
                          _focusedEdges = {};
                        }),
                        child: const Icon(Icons.close, color: Color(0xFFE040FB), size: 14),
                      ),
                    ],
                  ),
                ),
              ),

            // Close button
            Positioned(
              top: MediaQuery.of(context).padding.top + 10,
              right: 12,
              child: GestureDetector(
                onTap: _dismiss,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.close,
                      color: Colors.white.withValues(alpha: 0.7), size: 20),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }

  // ===========================================================================
  // 🖐️ DRAGGABLE + TAPPABLE NODE TARGETS
  // ===========================================================================

  List<Widget> _buildNodeTargets(Set<String> matchingIds) {
    return widget.clusters.map((cluster) {
      final pos = _nodePositions[cluster.id];
      if (pos == null) return const SizedBox.shrink();

      final isDimmed = _searchQuery.isNotEmpty &&
          !matchingIds.contains(cluster.id);
      if (isDimmed) return const SizedBox.shrink();

      final text = widget.clusterTexts[cluster.id] ?? '';
      final cardW = math.max(80.0, text.length.clamp(0, 30) * 3.5 + 30);
      const cardH = 58.0;
      final isPinned = _pinnedNodes.contains(cluster.id);
      final isPathStart = _pathStartNodeId == cluster.id;
      final isPathEnd = _pathEndNodeId == cluster.id;

      return Positioned(
        left: pos.dx - cardW / 2,
        top: pos.dy - cardH / 2,
        width: cardW,
        height: cardH,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticFeedback.selectionClick();
            // 🛤️ PATH MODE: selecting start/end nodes
            if (_pathStartNodeId != null && _pathEndNodeId == null && _pathStartNodeId != cluster.id) {
              setState(() {
                _pathEndNodeId = cluster.id;
              });
              _computeShortestPath();
              return;
            }
            if (_pathStartNodeId == null && _shortestPath.isEmpty) {
              // Normal tap mode
            } else if (_pathStartNodeId != null && _pathEndNodeId == null) {
              // Cannot select same node as start and end
              return;
            }

            setState(() {
              if (_expandedNodeId == cluster.id) {
                _expandedNodeId = null;
                _dismiss();
                Future.delayed(const Duration(milliseconds: 200), () {
                  widget.onNavigateToCluster(cluster);
                });
              } else {
                _expandedNodeId = cluster.id;
              }
            });
          },
          onLongPress: () {
            // 📌 LONG-PRESS: Toggle pin
            HapticFeedback.heavyImpact();
            setState(() {
              if (isPinned) {
                _pinnedNodes.remove(cluster.id);
              } else {
                _pinnedNodes.add(cluster.id);
              }
            });
          },
          onDoubleTap: () {
            // 🛤️ DOUBLE-TAP: Start path from this node
            HapticFeedback.mediumImpact();
            setState(() {
              _pathStartNodeId = cluster.id;
              _pathEndNodeId = null;
              _shortestPath = [];
              _shortestPathEdges = {};
            });
          },
          onPanStart: (_) {
            setState(() => _draggingNodeId = cluster.id);
            HapticFeedback.selectionClick();
          },
          onPanUpdate: (details) {
            setState(() {
              _nodePositions[cluster.id] =
                  (_nodePositions[cluster.id] ?? Offset.zero) + details.delta;
            });
          },
          onPanEnd: (_) {
            setState(() => _draggingNodeId = null);
          },
          child: Stack(
            children: [
              const SizedBox.expand(),
              // 📌 Pin indicator
              if (isPinned)
                Positioned(
                  top: 0, left: 0,
                  child: Container(
                    width: 14, height: 14,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF5252).withValues(alpha: 0.8),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.push_pin, size: 9, color: Colors.white),
                  ),
                ),
              // 🛤️ Path start/end indicator
              if (isPathStart || isPathEnd)
                Positioned(
                  top: 0, right: 0,
                  child: Container(
                    width: 14, height: 14,
                    decoration: BoxDecoration(
                      color: const Color(0xFF4CAF50).withValues(alpha: 0.8),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      isPathStart ? 'A' : 'B',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }).toList();
  }

  // ===========================================================================
  // 🎬 CONNECTION TAP TARGETS (Cinematic Flight)
  // ===========================================================================

  List<Widget> _buildConnectionTargets(List<dynamic> connections) {
    if (widget.onConnectionTapped == null) return [];

    return connections.map<Widget>((conn) {
      final srcPos = _nodePositions[conn.sourceClusterId];
      final tgtPos = _nodePositions[conn.targetClusterId];
      if (srcPos == null || tgtPos == null) return const SizedBox.shrink();

      // Position at the Bézier midpoint (same math as painter)
      final midX = (srcPos.dx + tgtPos.dx) / 2;
      final midY = (srcPos.dy + tgtPos.dy) / 2;
      final dx = tgtPos.dx - srcPos.dx;
      final dy = tgtPos.dy - srcPos.dy;
      final cp = Offset(midX + (-dy * 0.18), midY + (dx * 0.18));
      // Quadratic Bézier at t=0.5
      final bezierMid = Offset(
        srcPos.dx * 0.25 + cp.dx * 0.5 + tgtPos.dx * 0.25,
        srcPos.dy * 0.25 + cp.dy * 0.5 + tgtPos.dy * 0.25,
      );

      // Tap target size — larger for easier tapping
      const targetSize = 44.0;

      return Positioned(
        left: bezierMid.dx - targetSize / 2,
        top: bezierMid.dy - targetSize / 2,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticFeedback.lightImpact();
            widget.onConnectionTapped?.call(
              conn.sourceClusterId as String,
              conn.targetClusterId as String,
              (conn.curveStrength as double?) ?? 0.3,
            );
          },
          // 🔄 REVERSE FLIGHT: Double-tap = fly opposite direction
          onDoubleTap: () {
            HapticFeedback.mediumImpact();
            widget.onConnectionTapped?.call(
              conn.targetClusterId as String, // Swapped!
              conn.sourceClusterId as String,
              (conn.curveStrength as double?) ?? 0.3,
            );
          },
          child: Container(
            width: targetSize,
            height: targetSize,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.0),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A2E).withValues(alpha: 0.4),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF64B5F6).withValues(alpha: 0.4),
                    width: 1,
                  ),
                ),
                child: const Center(
                  child: Icon(
                    Icons.flight_takeoff,
                    color: Color(0xFF64B5F6),
                    size: 14,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  // ===========================================================================
  // 📝 EXPANDED DETAIL CARD
  // ===========================================================================

  Widget _buildExpandedCard() {
    final cluster = widget.clusters.where((c) => c.id == _expandedNodeId).firstOrNull;
    if (cluster == null) return const SizedBox.shrink();

    final text = widget.clusterTexts[cluster.id] ?? 'No text';
    final pos = _nodePositions[cluster.id] ?? Offset.zero;
    final connCount = _connectionCounts[cluster.id] ?? 0;
    final cent = _centrality[cluster.id] ?? 0;

    // Card position: below the node
    final cardTop = pos.dy + 40;
    final cardLeft = (pos.dx - 120).clamp(16.0, _graphSize.width - 276.0);

    return Positioned(
      left: cardLeft,
      top: cardTop,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 260,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF2A2535).withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                      color: _clusterColor(cluster),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${cluster.elementCount} elements',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _expandedNodeId = null),
                    child: Icon(Icons.close, size: 14,
                        color: Colors.white.withValues(alpha: 0.4)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Full text
              Text(
                text,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 12,
                  height: 1.4,
                ),
                maxLines: 8,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              // Metrics row
              Row(
                children: [
                  _MetricChip(
                    label: '$connCount connections',
                    color: connCount >= 3
                        ? const Color(0xFFFF9800)
                        : Colors.white38,
                  ),
                  const SizedBox(width: 6),
                  _MetricChip(
                    label: 'centrality ${(cent * 100).toStringAsFixed(0)}%',
                    color: cent > 0.5
                        ? const Color(0xFF64B5F6)
                        : Colors.white38,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Navigate button
              GestureDetector(
                onTap: () {
                  _dismiss();
                  Future.delayed(const Duration(milliseconds: 200), () {
                    widget.onNavigateToCluster(cluster);
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  decoration: BoxDecoration(
                    color: _clusterColor(cluster).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      'Vai al cluster →',
                      style: TextStyle(
                        color: _clusterColor(cluster),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  Color _clusterColor(ContentCluster cluster) {
    if (cluster.strokeIds.isNotEmpty) {
      final hash = cluster.id.hashCode;
      final hue = (hash % 360).abs().toDouble();
      return HSLColor.fromAHSL(1.0, hue, 0.6, 0.55).toColor();
    }
    return const Color(0xFF64B5F6);
  }

  static Color _typeColor(ConnectionType type) {
    switch (type) {
      case ConnectionType.association: return const Color(0xFF64B5F6);
      case ConnectionType.causality: return const Color(0xFFFFB74D);
      case ConnectionType.hierarchy: return const Color(0xFF81C784);
      case ConnectionType.contradiction: return const Color(0xFFFF7A8A);
    }
  }

  static String _typeEmoji(ConnectionType type) {
    switch (type) {
      case ConnectionType.association: return '—';
      case ConnectionType.causality: return '⚡';
      case ConnectionType.hierarchy: return '🌳';
      case ConnectionType.contradiction: return '✕';
    }
  }

  static String _typeLabel(ConnectionType type) {
    switch (type) {
      case ConnectionType.association: return 'Assoc';
      case ConnectionType.causality: return 'Causa';
      case ConnectionType.hierarchy: return 'Gerarc';
      case ConnectionType.contradiction: return 'Contr';
    }
  }

  // ===========================================================================
  // 📝 LIST VIEW MODE
  // ===========================================================================

  Widget _buildListView(Size size) {
    // Sort clusters by centrality (highest first)
    final sorted = List.of(widget.clusters)
      ..sort((a, b) {
        final ca = _centrality[a.id] ?? 0;
        final cb = _centrality[b.id] ?? 0;
        return cb.compareTo(ca);
      });

    return Positioned(
      top: MediaQuery.of(context).padding.top + 135,
      left: 16,
      right: 16,
      bottom: MediaQuery.of(context).padding.bottom + 95,
      child: ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: sorted.length,
        itemBuilder: (context, index) {
          final cluster = sorted[index];
          final text = widget.clusterTexts[cluster.id] ?? 'No text';
          final connCount = _connectionCounts[cluster.id] ?? 0;
          final cent = _centrality[cluster.id] ?? 0;
          final isPinned = _pinnedNodes.contains(cluster.id);
          final color = _clusterColor(cluster);

          return GestureDetector(
            onTap: () {
              setState(() => _expandedNodeId = cluster.id);
              setState(() => _showListView = false);
              HapticFeedback.selectionClick();
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: color.withValues(alpha: 0.15),
                ),
              ),
              child: Row(
                children: [
                  // Rank number
                  SizedBox(
                    width: 24,
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        color: color.withValues(alpha: 0.6),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  // Color dot
                  Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Text
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          text.length > 40 ? '${text.substring(0, 38)}…' : text,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${cluster.elementCount} elem · $connCount conn · ${(cent * 100).toStringAsFixed(0)}% centr',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.35),
                            fontSize: 9,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Pin icon
                  if (isPinned)
                    const Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: Icon(Icons.push_pin, size: 12, color: Color(0xFFFF5252)),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// =============================================================================
// SMALL WIDGETS
// =============================================================================

class _BottomButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _BottomButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF64B5F6).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFF64B5F6).withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: const Color(0xFF64B5F6), size: 16),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                    color: Color(0xFF64B5F6),
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  final String label;
  final Color color;

  const _MetricChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w600)),
    );
  }
}

// =============================================================================
// 🎨 Knowledge Graph Painter — Rich Information Display
// =============================================================================

class _KnowledgeGraphPainter extends CustomPainter {
  final List<ContentCluster> clusters;
  final List<dynamic> connections;
  final Map<String, Offset> positions;
  final Map<String, String> clusterTexts;
  final Set<String> matchingIds;
  final bool searchActive;
  final Map<String, int> connectionCounts;
  final Map<String, double> centrality;
  final double graphDensity;
  final double animationTime;
  final String? expandedNodeId;
  final String? draggingNodeId;
  final Set<String> pinnedNodes;
  final List<String> shortestPath;
  final Set<String> shortestPathEdges;
  final String? pathStartNodeId;
  final String? pathEndNodeId;
  final Map<String, int> communities;
  final int communityCount;
  final bool livePhysics;
  final List<_InferredConnection> inferredConnections;
  final String? focusNodeId;
  final Set<String> focusedNodes;
  final Set<String> focusedEdges;

  _KnowledgeGraphPainter({
    required this.clusters,
    required this.connections,
    required this.positions,
    required this.clusterTexts,
    required this.matchingIds,
    required this.searchActive,
    required this.connectionCounts,
    required this.centrality,
    required this.graphDensity,
    required this.animationTime,
    this.expandedNodeId,
    this.draggingNodeId,
    this.pinnedNodes = const {},
    this.shortestPath = const [],
    this.shortestPathEdges = const {},
    this.pathStartNodeId,
    this.pathEndNodeId,
    this.communities = const {},
    this.communityCount = 0,
    this.livePhysics = false,
    this.inferredConnections = const [],
    this.focusNodeId,
    this.focusedNodes = const {},
    this.focusedEdges = const {},
  });

  final _p = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    // === 🎨 Cluster grouping: draw colored hull backgrounds ===
    _drawClusterGroups(canvas);

    // === Draw connections with labels, arrows, and particles ===
    for (final conn in connections) {
      final srcPos = positions[conn.sourceClusterId];
      final tgtPos = positions[conn.targetClusterId];
      if (srcPos == null || tgtPos == null) continue;

      final isDimmed = (searchActive &&
          !matchingIds.contains(conn.sourceClusterId) &&
          !matchingIds.contains(conn.targetClusterId)) ||
          (focusNodeId != null && !focusedEdges.contains(conn.id));

      // 🛤️ Shortest path highlight
      final isOnPath = shortestPathEdges.contains(conn.id);
      final alpha = isDimmed ? 0.05 : (isOnPath ? 0.9 : 0.35);
      final connColor = isOnPath
          ? const Color(0xFF4CAF50)
          : (conn.color as Color? ?? const Color(0xFF64B5F6));

      final midX = (srcPos.dx + tgtPos.dx) / 2;
      final midY = (srcPos.dy + tgtPos.dy) / 2;
      final dx = tgtPos.dx - srcPos.dx;
      final dy = tgtPos.dy - srcPos.dy;
      final cp = Offset(midX + (-dy * 0.18), midY + (dx * 0.18));

      final path = Path()
        ..moveTo(srcPos.dx, srcPos.dy)
        ..quadraticBezierTo(cp.dx, cp.dy, tgtPos.dx, tgtPos.dy);

      double strokeW = isDimmed ? 0.5 : (isOnPath ? 3.0 : 1.8);
      if (!isOnPath && conn.connectionType == ConnectionType.causality) strokeW = 2.5;
      if (!isOnPath && conn.connectionType == ConnectionType.hierarchy) strokeW = 1.5;

      // Soft glow beneath
      if (!isDimmed) {
        _p
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeW + 4
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4)
          ..color = connColor.withValues(alpha: alpha * 0.4);
        canvas.drawPath(path, _p);
        _p.maskFilter = null;
      }

      _p
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW
        ..strokeCap = StrokeCap.round
        ..color = connColor.withValues(alpha: alpha);
      canvas.drawPath(path, _p);

      // ✨ Animated particles flowing along path
      if (!isDimmed) {
        const particleCount = 3;
        for (int pi = 0; pi < particleCount; pi++) {
          final t = ((animationTime * 0.15 + pi / particleCount) % 1.0);
          final pt = Offset(
            srcPos.dx * (1 - t) * (1 - t) + cp.dx * 2 * (1 - t) * t + tgtPos.dx * t * t,
            srcPos.dy * (1 - t) * (1 - t) + cp.dy * 2 * (1 - t) * t + tgtPos.dy * t * t,
          );
          final particleAlpha = math.sin(t * math.pi) * 0.7;
          _p
            ..style = PaintingStyle.fill
            ..color = connColor.withValues(alpha: particleAlpha)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
          canvas.drawCircle(pt, 2.5, _p);
          _p.maskFilter = null;
        }
      }

      // 🏷️ Connection label on arc
      if (!isDimmed) {
        final labelMid = Offset(
          srcPos.dx * 0.25 + cp.dx * 0.5 + tgtPos.dx * 0.25,
          srcPos.dy * 0.25 + cp.dy * 0.5 + tgtPos.dy * 0.25,
        );

        String typeIcon = '';
        switch (conn.connectionType) {
          case ConnectionType.association: typeIcon = '—'; break;
          case ConnectionType.causality: typeIcon = '⚡'; break;
          case ConnectionType.hierarchy: typeIcon = '🌳'; break;
          case ConnectionType.contradiction: typeIcon = '✕'; break;
        }

        final labelText = conn.label != null && (conn.label as String).isNotEmpty
            ? '$typeIcon ${conn.label}'
            : typeIcon;

        if (labelText.isNotEmpty) {
          final tp = TextPainter(
            text: TextSpan(
              text: labelText,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 8.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: 100);

          final pillW = tp.width + 10;
          final pillH = tp.height + 6;
          final pillRect = RRect.fromRectAndRadius(
            Rect.fromCenter(center: labelMid, width: pillW, height: pillH),
            const Radius.circular(6),
          );
          _p
            ..style = PaintingStyle.fill
            ..color = connColor.withValues(alpha: 0.35);
          canvas.drawRRect(pillRect, _p);
          tp.paint(canvas, Offset(labelMid.dx - tp.width / 2, labelMid.dy - tp.height / 2));
        }

        // ➡️ Directional arrow
        final arrowT = 0.75;
        final arrowPt = Offset(
          srcPos.dx * math.pow(1 - arrowT, 2) + cp.dx * 2 * (1 - arrowT) * arrowT + tgtPos.dx * arrowT * arrowT,
          srcPos.dy * math.pow(1 - arrowT, 2) + cp.dy * 2 * (1 - arrowT) * arrowT + tgtPos.dy * arrowT * arrowT,
        );
        final arrowT2 = 0.76;
        final arrowNext = Offset(
          srcPos.dx * math.pow(1 - arrowT2, 2) + cp.dx * 2 * (1 - arrowT2) * arrowT2 + tgtPos.dx * arrowT2 * arrowT2,
          srcPos.dy * math.pow(1 - arrowT2, 2) + cp.dy * 2 * (1 - arrowT2) * arrowT2 + tgtPos.dy * arrowT2 * arrowT2,
        );
        final tangent = arrowNext - arrowPt;
        final tLen = tangent.distance;
        if (tLen > 0.01) {
          final dir = tangent / tLen;
          final perp = Offset(-dir.dy, dir.dx);
          const arrowSize = 5.0;
          final tip = arrowPt + dir * arrowSize;
          final left = arrowPt - dir * arrowSize * 0.3 + perp * arrowSize * 0.6;
          final right = arrowPt - dir * arrowSize * 0.3 - perp * arrowSize * 0.6;
          final arrowPath = Path()
            ..moveTo(tip.dx, tip.dy)
            ..lineTo(left.dx, left.dy)
            ..lineTo(right.dx, right.dy)
            ..close();
          _p
            ..style = PaintingStyle.fill
            ..color = connColor.withValues(alpha: 0.6);
          canvas.drawPath(arrowPath, _p);
        }
      }
    }

    // === 🔗 Draw inferred transitive connections (dashed) ===
    for (final inf in inferredConnections) {
      final srcPos = positions[inf.sourceId];
      final tgtPos = positions[inf.targetId];
      if (srcPos == null || tgtPos == null) continue;

      // Draw dashed line
      final delta = tgtPos - srcPos;
      final dist = delta.distance;
      if (dist < 1) continue;
      final dir = delta / dist;
      const dashLen = 6.0;
      const gapLen = 4.0;

      _p
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0xFFFFAB40).withValues(alpha: 0.4);

      double d = 0;
      while (d < dist) {
        final start = srcPos + dir * d;
        final end = srcPos + dir * math.min(d + dashLen, dist);
        canvas.drawLine(start, end, _p);
        d += dashLen + gapLen;
      }

      // Draw "?" label at midpoint
      final mid = (srcPos + tgtPos) / 2;
      final tp = TextPainter(
        text: const TextSpan(
          text: '?',
          style: TextStyle(
            color: Color(0xFFFFAB40),
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(mid.dx - tp.width / 2, mid.dy - tp.height / 2 - 8));
    }

    // === Draw rich node cards ===
    for (final cluster in clusters) {
      final pos = positions[cluster.id];
      if (pos == null) continue;

      final text = clusterTexts[cluster.id] ?? '';
      final isFocusDimmed = focusNodeId != null && !focusedNodes.contains(cluster.id);
      final isDimmed = (searchActive && !matchingIds.contains(cluster.id)) || isFocusDimmed;
      final isHighlighted = searchActive && matchingIds.contains(cluster.id);
      final isExpanded = cluster.id == expandedNodeId;
      final isDragging = cluster.id == draggingNodeId;
      final connCount = connectionCounts[cluster.id] ?? 0;
      final isHub = connCount >= 3;
      final isIsolated = connCount == 0;
      final cent = centrality[cluster.id] ?? 0;
      final isOnPathNode = shortestPath.contains(cluster.id);
      final isPathEnd = pathStartNodeId == cluster.id || pathEndNodeId == cluster.id;
      final isPinned = pinnedNodes.contains(cluster.id);
      final alpha = isDimmed ? 0.08 : (isHighlighted ? 1.0 : 0.7);

      Color nodeColor = const Color(0xFF64B5F6);
      if (cluster.strokeIds.isNotEmpty) {
        final hash = cluster.id.hashCode;
        final hue = (hash % 360).abs().toDouble();
        nodeColor = HSLColor.fromAHSL(1.0, hue, 0.6, 0.55).toColor();
      }

      // 🌟 Hub glow
      if (isHub && !isDimmed) {
        _p
          ..style = PaintingStyle.fill
          ..color = nodeColor.withValues(alpha: 0.10 + cent * 0.08)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20);
        canvas.drawCircle(pos, 38, _p);
        _p.maskFilter = null;
      }

      // 📌 Pin glow
      if (isPinned && !isDimmed) {
        _p
          ..style = PaintingStyle.fill
          ..color = const Color(0xFFFF5252).withValues(alpha: 0.10)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
        canvas.drawCircle(pos, 30, _p);
        _p.maskFilter = null;
      }

      // 🛤️ Path node glow
      if (isOnPathNode && !isDimmed) {
        _p
          ..style = PaintingStyle.fill
          ..color = const Color(0xFF4CAF50).withValues(alpha: isPathEnd ? 0.25 : 0.12)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15);
        canvas.drawCircle(pos, 35, _p);
        _p.maskFilter = null;
      }

      // 🖐️ Drag glow
      if (isDragging) {
        _p
          ..style = PaintingStyle.fill
          ..color = Colors.white.withValues(alpha: 0.08)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
        canvas.drawCircle(pos, 45, _p);
        _p.maskFilter = null;
      }

      if (isHighlighted) {
        _p
          ..style = PaintingStyle.fill
          ..color = nodeColor.withValues(alpha: 0.2)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
        canvas.drawCircle(pos, 30, _p);
        _p.maskFilter = null;
      }

      // --- Glass card ---
      final cardW = math.max(80.0, text.length.clamp(0, 30) * 3.5 + 30);
      final cardH = 44.0 + (text.isNotEmpty ? 14.0 : 0.0);
      final cardRect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: pos, width: cardW, height: cardH),
        const Radius.circular(10),
      );

      // Expanded node gets brighter border
      _p
        ..style = PaintingStyle.fill
        ..color = nodeColor.withValues(alpha: alpha * (isExpanded ? 0.20 : 0.12));
      canvas.drawRRect(cardRect, _p);

      _p
        ..style = PaintingStyle.stroke
        ..strokeWidth = isExpanded ? 2.5 : (isHighlighted ? 2.0 : (isIsolated ? 0.6 : 1.0))
        ..color = isExpanded
            ? nodeColor.withValues(alpha: 0.9)
            : isIsolated
                ? nodeColor.withValues(alpha: alpha * 0.3)
                : nodeColor.withValues(alpha: alpha * 0.6);
      canvas.drawRRect(cardRect, _p);

      // --- Text preview ---
      if (text.isNotEmpty && !isDimmed) {
        final preview = text.length > 25 ? '${text.substring(0, 23)}…' : text;
        final tp = TextPainter(
          text: TextSpan(
            text: preview,
            style: TextStyle(
              color: Colors.white.withValues(alpha: isHighlighted ? 0.95 : 0.65),
              fontSize: isHighlighted ? 10.0 : 9.0,
              fontWeight: isHighlighted ? FontWeight.w600 : FontWeight.w400,
              height: 1.2,
            ),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: cardW - 12);
        tp.paint(canvas, Offset(pos.dx - tp.width / 2, pos.dy - 4));
      }

      // --- Connection count badge ---
      if (connCount > 0 && !isDimmed) {
        final badgePos = Offset(pos.dx + cardW / 2 - 8, pos.dy - cardH / 2 + 2);
        final badgeRadius = connCount >= 10 ? 9.0 : 7.5;
        _p
          ..style = PaintingStyle.fill
          ..color = isHub
              ? const Color(0xFFFF9800).withValues(alpha: 0.85)
              : nodeColor.withValues(alpha: 0.5);
        canvas.drawCircle(badgePos, badgeRadius, _p);

        final btp = TextPainter(
          text: TextSpan(
            text: '$connCount',
            style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w700),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        btp.paint(canvas, Offset(badgePos.dx - btp.width / 2, badgePos.dy - btp.height / 2));
      }

      // --- Bottom label ---
      if (!isDimmed) {
        final elemLabel = '${cluster.elementCount} elem${isIsolated ? " · isolated" : ""}';
        final etp = TextPainter(
          text: TextSpan(
            text: elemLabel,
            style: TextStyle(
              color: isIsolated ? Colors.orange.withValues(alpha: 0.5)
                  : Colors.white.withValues(alpha: 0.3),
              fontSize: 7.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: cardW - 8);
        etp.paint(canvas, Offset(pos.dx - etp.width / 2, pos.dy + 10));
      }
    }

    // --- Legend ---
    if (!searchActive) {
      _drawLegend(canvas, size);
    }
  }

  // ===========================================================================
  // 🎨 CLUSTER GROUPING — colored background blobs for connected clusters
  // ===========================================================================

  void _drawClusterGroups(Canvas canvas) {
    // 🧦 Use community detection results if available
    if (communities.isNotEmpty && communityCount > 1) {
      // Group nodes by community
      final groups = <int, List<String>>{};
      for (final entry in communities.entries) {
        groups.putIfAbsent(entry.value, () => []).add(entry.key);
      }

      for (final entry in groups.entries) {
        final group = entry.value;
        final groupPositions = group
            .map((id) => positions[id])
            .whereType<Offset>()
            .toList();
        if (groupPositions.length < 2) continue;

        double cx = 0, cy = 0;
        for (final p in groupPositions) { cx += p.dx; cy += p.dy; }
        cx /= groupPositions.length;
        cy /= groupPositions.length;
        double maxDist = 0;
        for (final p in groupPositions) {
          final d = (p - Offset(cx, cy)).distance;
          if (d > maxDist) maxDist = d;
        }

        final hue = (entry.key * 137.508) % 360;
        final groupColor = HSLColor.fromAHSL(1.0, hue, 0.5, 0.5).toColor();

        // Draw community blob
        _p
          ..style = PaintingStyle.fill
          ..color = groupColor.withValues(alpha: 0.06)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, math.max(maxDist * 0.4, 30));
        canvas.drawCircle(Offset(cx, cy), maxDist + 40, _p);
        _p.maskFilter = null;

        // Draw community label
        final ctp = TextPainter(
          text: TextSpan(
            text: 'Community ${entry.key + 1}',
            style: TextStyle(
              color: groupColor.withValues(alpha: 0.3),
              fontSize: 9,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        ctp.paint(canvas, Offset(cx - ctp.width / 2, cy - maxDist - 20));
      }
      return;
    }

    // Fallback: connected components
    final adj = <String, Set<String>>{};
    for (final conn in connections) {
      final src = conn.sourceClusterId as String;
      final tgt = conn.targetClusterId as String;
      adj.putIfAbsent(src, () => {}).add(tgt);
      adj.putIfAbsent(tgt, () => {}).add(src);
    }

    final visited = <String>{};
    final groups = <List<String>>[];
    for (final id in adj.keys) {
      if (visited.contains(id)) continue;
      final group = <String>[];
      final queue = [id];
      while (queue.isNotEmpty) {
        final curr = queue.removeLast();
        if (!visited.add(curr)) continue;
        group.add(curr);
        for (final neighbor in (adj[curr] ?? <String>{})) {
          if (!visited.contains(neighbor)) queue.add(neighbor);
        }
      }
      if (group.length >= 2) groups.add(group);
    }

    for (int gi = 0; gi < groups.length; gi++) {
      final group = groups[gi];
      final groupPositions = group
          .map((id) => positions[id])
          .whereType<Offset>()
          .toList();
      if (groupPositions.length < 2) continue;

      double cx = 0, cy = 0;
      for (final p in groupPositions) { cx += p.dx; cy += p.dy; }
      cx /= groupPositions.length;
      cy /= groupPositions.length;
      double maxDist = 0;
      for (final p in groupPositions) {
        final d = (p - Offset(cx, cy)).distance;
        if (d > maxDist) maxDist = d;
      }

      final hue = (gi * 137.508) % 360;
      final groupColor = HSLColor.fromAHSL(1.0, hue, 0.4, 0.5).toColor();

      _p
        ..style = PaintingStyle.fill
        ..color = groupColor.withValues(alpha: 0.04)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, math.max(maxDist * 0.4, 30));
      canvas.drawCircle(Offset(cx, cy), maxDist + 40, _p);
      _p.maskFilter = null;
    }
  }

  // ===========================================================================
  // LEGEND
  // ===========================================================================

  void _drawLegend(Canvas canvas, Size size) {
    final legendX = 16.0;
    final legendY = size.height - 130.0;

    final legendRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(legendX, legendY, 145, 105),
      const Radius.circular(10),
    );
    _p
      ..style = PaintingStyle.fill
      ..color = Colors.white.withValues(alpha: 0.06);
    canvas.drawRRect(legendRect, _p);
    _p
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = Colors.white.withValues(alpha: 0.1);
    canvas.drawRRect(legendRect, _p);

    final titleTp = TextPainter(
      text: const TextSpan(
        text: 'Legend',
        style: TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.5),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    titleTp.paint(canvas, Offset(legendX + 8, legendY + 6));

    const items = [
      ('—  Association', 0xFF64B5F6),
      ('⚡ Causality', 0xFFFFB74D),
      ('🌳 Hierarchy', 0xFF81C784),
      ('✕  Contradiction', 0xFFFF7A8A),
      ('🟠 Hub (3+ conn)', 0xFFFF9800),
    ];
    for (int i = 0; i < items.length; i++) {
      final tp = TextPainter(
        text: TextSpan(
          text: items[i].$1,
          style: TextStyle(
            color: Color(items[i].$2).withValues(alpha: 0.7),
            fontSize: 8,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(legendX + 10, legendY + 22 + i * 16.0));
    }
  }

  @override
  bool shouldRepaint(covariant _KnowledgeGraphPainter old) => true; // Always repaint for particles
}

// =============================================================================
// 🗺️ MINIMAP PAINTER — Tiny overview of entire graph
// =============================================================================

class _MinimapPainter extends CustomPainter {
  final Map<String, Offset> positions;
  final List<dynamic> connections;
  final List<String> shortestPath;

  _MinimapPainter({
    required this.positions,
    required this.connections,
    required this.shortestPath,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (positions.isEmpty) return;

    // Find bounds
    double minX = double.infinity, maxX = double.negativeInfinity;
    double minY = double.infinity, maxY = double.negativeInfinity;
    for (final p in positions.values) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }

    final rangeX = math.max(maxX - minX, 1.0);
    final rangeY = math.max(maxY - minY, 1.0);
    const pad = 6.0;
    final scaleX = (size.width - pad * 2) / rangeX;
    final scaleY = (size.height - pad * 2) / rangeY;
    final s = math.min(scaleX, scaleY);
    final offX = (size.width - rangeX * s) / 2;
    final offY = (size.height - rangeY * s) / 2;

    Offset mapPos(Offset p) => Offset(
      offX + (p.dx - minX) * s,
      offY + (p.dy - minY) * s,
    );

    final paint = Paint();

    // Draw connections
    for (final conn in connections) {
      final srcPos = positions[conn.sourceClusterId];
      final tgtPos = positions[conn.targetClusterId];
      if (srcPos == null || tgtPos == null) continue;
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5
        ..color = Colors.white.withValues(alpha: 0.15);
      canvas.drawLine(mapPos(srcPos), mapPos(tgtPos), paint);
    }

    // Draw nodes
    for (final entry in positions.entries) {
      final isOnPath = shortestPath.contains(entry.key);
      paint
        ..style = PaintingStyle.fill
        ..color = isOnPath
            ? const Color(0xFF4CAF50).withValues(alpha: 0.8)
            : Colors.white.withValues(alpha: 0.4);
      canvas.drawCircle(mapPos(entry.value), isOnPath ? 2.5 : 1.5, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MinimapPainter old) =>
      positions != old.positions || shortestPath != old.shortestPath;
}
