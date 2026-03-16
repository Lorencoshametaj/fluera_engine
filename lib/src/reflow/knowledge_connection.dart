import 'dart:ui';

/// 🔗 KNOWLEDGE CONNECTION — A directed link between two content clusters.
///
/// Represents a user-created connection in the Knowledge Flow graph.
/// Connections are visualized as curved arrows with flowing particles
/// when zoomed out, creating a mind-map experience.
///
/// SERIALIZABLE: Persisted alongside canvas data.
class KnowledgeConnection {
  /// Unique connection identifier.
  final String id;

  /// Source cluster ID (arrow starts here).
  final String sourceClusterId;

  /// Target cluster ID (arrow ends here).
  final String targetClusterId;

  /// Optional label displayed on the arrow.
  String? label;

  /// Arrow color (defaults to source cluster color).
  Color color;

  /// Bézier curve strength: 0.0 = straight line, 1.0 = very curved.
  /// Auto-calculated to avoid overlapping other clusters.
  double curveStrength;

  /// Particle positions along the path (0.0–1.0).
  /// NOT serialized — regenerated on load.
  List<double> particlePositions;

  /// Number of particles on this connection.
  static const int defaultParticleCount = 5;

  /// Particle speed: full path traversal time in seconds.
  static const double particleLoopDuration = 2.5;

  /// Timestamp when this connection was created (milliseconds since epoch).
  /// Used for birth animation effect (1s flash propagation).
  /// NOT serialized — set to 0 on load (no animation on reload).
  int createdAtMs;

  /// Approximate path length in canvas units.
  /// Set by controller after path computation. Used for speed-proportional particles.
  double pathLength;

  KnowledgeConnection({
    required this.id,
    required this.sourceClusterId,
    required this.targetClusterId,
    this.label,
    this.color = const Color(0xFF64B5F6), // Material Blue 300
    this.curveStrength = 0.3,
    this.pathLength = 500.0, // Default path length
    int? createdAt,
  }) : createdAtMs = createdAt ?? DateTime.now().millisecondsSinceEpoch,
       particlePositions = _generateInitialParticles();

  /// Generate evenly-spaced initial particle positions.
  static List<double> _generateInitialParticles() {
    return List.generate(
      defaultParticleCount,
      (i) => i / defaultParticleCount,
    );
  }

  /// Advance all particles by [dt] seconds.
  /// Speed is inversely proportional to path length:
  /// short connections (≤300px) = 2x speed, long connections (≥800px) = 0.7x speed
  void advanceParticles(double dt) {
    final speedFactor = (600.0 / pathLength.clamp(200.0, 1200.0));
    final speed = dt / particleLoopDuration * speedFactor;
    for (int i = 0; i < particlePositions.length; i++) {
      particlePositions[i] = (particlePositions[i] + speed) % 1.0;
    }
  }

  // ===========================================================================
  // Serialization
  // ===========================================================================

  Map<String, dynamic> toJson() => {
    'id': id,
    'sourceClusterId': sourceClusterId,
    'targetClusterId': targetClusterId,
    if (label != null) 'label': label,
    'color': color.value,
    'curveStrength': curveStrength,
  };

  factory KnowledgeConnection.fromJson(Map<String, dynamic> json) {
    return KnowledgeConnection(
      id: json['id'] as String,
      sourceClusterId: json['sourceClusterId'] as String,
      targetClusterId: json['targetClusterId'] as String,
      label: json['label'] as String?,
      color: Color(json['color'] as int? ?? 0xFF64B5F6),
      curveStrength: (json['curveStrength'] as num?)?.toDouble() ?? 0.3,
      createdAt: 0, // No animation on reload
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KnowledgeConnection &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'KnowledgeConnection($id: $sourceClusterId → $targetClusterId)';
}
