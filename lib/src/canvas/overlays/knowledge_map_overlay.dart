import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../reflow/content_cluster.dart';
import '../../reflow/knowledge_flow_controller.dart';

/// 🧠 KNOWLEDGE MAP OVERLAY — Interactive graph visualization of the
/// entire knowledge network. Glassmorphic fullscreen overlay showing
/// all clusters as colored nodes and connections as curved arcs.
///
/// Features:
///   - Tap a node → dismiss & animate canvas to that cluster
///   - Search bar → highlights matching clusters
///   - Auto-organize → force-directed layout
class KnowledgeMapOverlay extends StatefulWidget {
  final KnowledgeFlowController controller;
  final List<ContentCluster> clusters;
  final Map<String, String> clusterTexts;
  final VoidCallback onDismiss;
  final void Function(ContentCluster cluster) onNavigateToCluster;
  final void Function(Map<String, Offset> newPositions)? onAutoOrganize;

  const KnowledgeMapOverlay({
    super.key,
    required this.controller,
    required this.clusters,
    required this.clusterTexts,
    required this.onDismiss,
    required this.onNavigateToCluster,
    this.onAutoOrganize,
  });

  @override
  State<KnowledgeMapOverlay> createState() => _KnowledgeMapOverlayState();
}

class _KnowledgeMapOverlayState extends State<KnowledgeMapOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;
  String _searchQuery = '';

  // Graph layout: cluster positions mapped to overlay coordinates
  Map<String, Offset> _nodePositions = {};
  Size _graphSize = Size.zero;

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
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  /// Compute node positions to fit graph into the overlay viewport.
  void _computeLayout(Size viewportSize) {
    if (widget.clusters.isEmpty) return;
    if (_graphSize == viewportSize && _nodePositions.isNotEmpty) return;
    _graphSize = viewportSize;

    // Find bounding box of all cluster centroids in canvas space
    double minX = double.infinity, maxX = double.negativeInfinity;
    double minY = double.infinity, maxY = double.negativeInfinity;
    for (final c in widget.clusters) {
      final p = c.centroid;
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }

    // Map canvas coordinates → overlay coordinates with padding
    const pad = 60.0;
    final rangeX = maxX - minX;
    final rangeY = maxY - minY;
    final scaleX = rangeX > 0 ? (viewportSize.width - pad * 2) / rangeX : 1.0;
    final scaleY = rangeY > 0 ? (viewportSize.height - pad * 2 - 120) / rangeY : 1.0;
    final s = math.min(scaleX, scaleY);

    final centerX = viewportSize.width / 2;
    final centerY = (viewportSize.height + 60) / 2; // offset for search bar
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
  }

  /// Force-directed auto-organize: compute balanced positions.
  void _autoOrganize() {
    HapticFeedback.mediumImpact();
    if (widget.clusters.length < 2) return;

    // Initialize positions from current layout
    final pos = <String, Offset>{};
    for (final c in widget.clusters) {
      pos[c.id] = _nodePositions[c.id] ?? Offset(
        _graphSize.width / 2 + (math.Random().nextDouble() - 0.5) * 200,
        _graphSize.height / 2 + (math.Random().nextDouble() - 0.5) * 200,
      );
    }

    // Build adjacency set for connections
    final connected = <String, Set<String>>{};
    for (final conn in widget.controller.connections) {
      connected.putIfAbsent(conn.sourceClusterId, () => {}).add(conn.targetClusterId);
      connected.putIfAbsent(conn.targetClusterId, () => {}).add(conn.sourceClusterId);
    }

    // Run 80 iterations of force-directed layout
    const repulsion = 8000.0;
    const attraction = 0.01;
    const damping = 0.85;
    final vel = <String, Offset>{};
    for (final c in widget.clusters) vel[c.id] = Offset.zero;

    final ids = pos.keys.toList();
    for (int iter = 0; iter < 80; iter++) {
      final forces = <String, Offset>{};
      for (final id in ids) forces[id] = Offset.zero;

      // Repulsion (all pairs)
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

      // Attraction (connected pairs)
      for (final conn in widget.controller.connections) {
        final a = conn.sourceClusterId, b = conn.targetClusterId;
        if (!pos.containsKey(a) || !pos.containsKey(b)) continue;
        final delta = pos[b]! - pos[a]!;
        final force = delta * attraction;
        forces[a] = forces[a]! + force;
        forces[b] = forces[b]! - force;
      }

      // Center gravity (gentle pull toward center)
      final center = Offset(_graphSize.width / 2, _graphSize.height / 2);
      for (final id in ids) {
        final toCenter = center - pos[id]!;
        forces[id] = forces[id]! + toCenter * 0.001;
      }

      // Apply forces with damping
      for (final id in ids) {
        vel[id] = (vel[id]! + forces[id]!) * damping;
        pos[id] = pos[id]! + vel[id]!;
        // Clamp to viewport
        pos[id] = Offset(
          pos[id]!.dx.clamp(40.0, _graphSize.width - 40.0),
          pos[id]!.dy.clamp(100.0, _graphSize.height - 40.0),
        );
      }
    }

    setState(() {
      _nodePositions = pos;
    });

    // Notify parent to update canvas positions
    if (widget.onAutoOrganize != null) {
      // Convert overlay positions back to canvas space
      // (reverse of _computeLayout mapping)
      // For now, just report the new relative positions
      widget.onAutoOrganize!(pos);
    }
  }

  void _dismiss() async {
    await _animCtrl.reverse();
    widget.onDismiss();
  }

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

      return FadeTransition(
        opacity: _fadeAnim,
        child: GestureDetector(
          onTap: _dismiss,
          child: Stack(
            children: [
              // 🌫️ Backdrop blur
              BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  color: const Color(0xE01A1A2E),
                ),
              ),

              // 🎨 Graph canvas
              CustomPaint(
                size: size,
                painter: _KnowledgeGraphPainter(
                  clusters: widget.clusters,
                  connections: widget.controller.connections,
                  positions: _nodePositions,
                  clusterTexts: widget.clusterTexts,
                  matchingIds: matchingIds,
                  searchActive: _searchQuery.isNotEmpty,
                ),
              ),

              // 🔍 Search bar + title
              Positioned(
                top: MediaQuery.of(context).padding.top + 12,
                left: 16,
                right: 16,
                child: Column(
                  children: [
                    // Title
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
                    // Search field
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
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Search clusters...',
                          hintStyle: TextStyle(
                            color: Colors.white.withValues(alpha: 0.4),
                          ),
                          prefixIcon: Icon(
                            Icons.search,
                            color: Colors.white.withValues(alpha: 0.5),
                            size: 20,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 🎯 Cluster tap targets (invisible, on top of canvas)
              ..._buildTapTargets(matchingIds),

              // 🔄 Auto-organize button
              Positioned(
                bottom: MediaQuery.of(context).padding.bottom + 20,
                left: 0,
                right: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: _autoOrganize,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF64B5F6).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFF64B5F6).withValues(alpha: 0.3),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.auto_fix_high,
                              color: Color(0xFF64B5F6), size: 18),
                          SizedBox(width: 8),
                          Text(
                            'Auto-organize',
                            style: TextStyle(
                              color: Color(0xFF64B5F6),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Stats badge
              Positioned(
                bottom: MediaQuery.of(context).padding.bottom + 70,
                left: 0,
                right: 0,
                child: Center(
                  child: Text(
                    '${widget.clusters.length} clusters · '
                    '${widget.controller.connections.length} connections',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 12,
                    ),
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
                    child: Icon(
                      Icons.close,
                      color: Colors.white.withValues(alpha: 0.7),
                      size: 20,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  List<Widget> _buildTapTargets(Set<String> matchingIds) {
    return widget.clusters.map((cluster) {
      final pos = _nodePositions[cluster.id];
      if (pos == null) return const SizedBox.shrink();

      final isDimmed = _searchQuery.isNotEmpty &&
          !matchingIds.contains(cluster.id);
      if (isDimmed) return const SizedBox.shrink();

      return Positioned(
        left: pos.dx - 25,
        top: pos.dy - 25,
        width: 50,
        height: 50,
        child: GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            _dismiss();
            // Small delay for animation to complete
            Future.delayed(const Duration(milliseconds: 200), () {
              widget.onNavigateToCluster(cluster);
            });
          },
          behavior: HitTestBehavior.opaque,
          child: const SizedBox.expand(),
        ),
      );
    }).toList();
  }
}

// =============================================================================
// 🎨 Knowledge Graph Painter
// =============================================================================

class _KnowledgeGraphPainter extends CustomPainter {
  final List<ContentCluster> clusters;
  final List<dynamic> connections; // KnowledgeConnection
  final Map<String, Offset> positions;
  final Map<String, String> clusterTexts;
  final Set<String> matchingIds;
  final bool searchActive;

  _KnowledgeGraphPainter({
    required this.clusters,
    required this.connections,
    required this.positions,
    required this.clusterTexts,
    required this.matchingIds,
    required this.searchActive,
  });

  final _p = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    // --- Draw connections ---
    for (final conn in connections) {
      final srcPos = positions[conn.sourceClusterId];
      final tgtPos = positions[conn.targetClusterId];
      if (srcPos == null || tgtPos == null) continue;

      final isDimmed = searchActive &&
          !matchingIds.contains(conn.sourceClusterId) &&
          !matchingIds.contains(conn.targetClusterId);

      final alpha = isDimmed ? 0.05 : 0.25;

      // Curved connection line
      final midX = (srcPos.dx + tgtPos.dx) / 2;
      final midY = (srcPos.dy + tgtPos.dy) / 2;
      final dx = tgtPos.dx - srcPos.dx;
      final dy = tgtPos.dy - srcPos.dy;
      final cp = Offset(midX + (-dy * 0.15), midY + (dx * 0.15));

      final path = Path()
        ..moveTo(srcPos.dx, srcPos.dy)
        ..quadraticBezierTo(cp.dx, cp.dy, tgtPos.dx, tgtPos.dy);

      _p
        ..style = PaintingStyle.stroke
        ..strokeWidth = isDimmed ? 0.5 : 1.2
        ..color = (conn.color as Color? ?? const Color(0xFF64B5F6))
            .withValues(alpha: alpha);
      canvas.drawPath(path, _p);
    }

    // --- Draw nodes ---
    for (final cluster in clusters) {
      final pos = positions[cluster.id];
      if (pos == null) continue;

      final text = clusterTexts[cluster.id] ?? '';
      final isDimmed = searchActive && !matchingIds.contains(cluster.id);
      final isHighlighted = searchActive && matchingIds.contains(cluster.id);

      // Node size based on element count
      final nodeRadius = 8.0 + math.min(cluster.elementCount, 10) * 1.5;
      final alpha = isDimmed ? 0.1 : (isHighlighted ? 1.0 : 0.6);

      // Get cluster dominant color
      Color nodeColor = const Color(0xFF64B5F6);
      if (cluster.strokeIds.isNotEmpty) {
        // Simple hash to get a unique color per cluster
        final hash = cluster.id.hashCode;
        final hue = (hash % 360).abs().toDouble();
        nodeColor = HSLColor.fromAHSL(1.0, hue, 0.6, 0.6).toColor();
      }

      // Outer glow for highlighted nodes
      if (isHighlighted) {
        _p
          ..style = PaintingStyle.fill
          ..color = nodeColor.withValues(alpha: 0.15)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
        canvas.drawCircle(pos, nodeRadius + 10, _p);
        _p.maskFilter = null;
      }

      // Node circle
      _p
        ..style = PaintingStyle.fill
        ..color = nodeColor.withValues(alpha: alpha * 0.3);
      canvas.drawCircle(pos, nodeRadius, _p);

      // Node border
      _p
        ..style = PaintingStyle.stroke
        ..strokeWidth = isHighlighted ? 2.0 : 1.0
        ..color = nodeColor.withValues(alpha: alpha);
      canvas.drawCircle(pos, nodeRadius, _p);

      // Label
      if (text.isNotEmpty && !isDimmed) {
        final label = text.length > 20 ? '${text.substring(0, 18)}…' : text;
        final tp = TextPainter(
          text: TextSpan(
            text: label,
            style: TextStyle(
              color: Colors.white.withValues(
                alpha: isHighlighted ? 0.9 : 0.5,
              ),
              fontSize: isHighlighted ? 11 : 9,
              fontWeight:
                  isHighlighted ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: 120);
        tp.paint(
          canvas,
          Offset(pos.dx - tp.width / 2, pos.dy + nodeRadius + 4),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _KnowledgeGraphPainter old) =>
      positions != old.positions ||
      matchingIds != old.matchingIds ||
      searchActive != old.searchActive;
}
