import 'dart:ui';

/// 🔗 Connection type — visual style and semantic meaning.
enum ConnectionType {
  /// Default: solid curved line
  association,
  /// Thick line + strong glow + energy pulse (cause → effect)
  causality,
  /// Double parallel lines (parent → child)
  hierarchy,
  /// Red wavy line with X marker (A contradicts B)
  contradiction,
}

/// 🌉 Cross-zone bridge type (Passo 9, P9-05 types A/B/C).
///
/// Classifies the pedagogical nature of a cross-domain connection.
enum CrossZoneBridgeType {
  /// Type A: Structural similarity across domains.
  /// e.g., "Supply/demand in economics ↔ predator/prey in ecology"
  analogyStructural,

  /// Type B: Shared underlying mechanism.
  /// e.g., "Exponential growth in biology ↔ compound interest in finance"
  sharedMechanism,

  /// Type C: Complementary perspectives on the same phenomenon.
  /// e.g., "Entropy in physics ↔ information theory in CS"
  complementaryPerspective,
}

/// 💡 Who discovered this cross-zone bridge (P9-12).
///
/// Determines the visual icon: 💡 for student, 🤖 for AI.
enum BridgeDiscoveryOrigin {
  /// Student drew this bridge autonomously (icon: 💡)
  student,

  /// AI suggested this bridge and student accepted (icon: 🤖)
  aiSuggested,
}

/// 🎨 Connection visual style — how the line is drawn.
enum ConnectionStyle {
  /// Default smooth Bézier curve
  curved,
  /// Straight line from source to target
  straight,
  /// Zigzag pattern (stepped path)
  zigzag,
  /// Dashed line (weak/uncertain relationship)
  dashed,
}

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

  /// Connection type — determines visual style and semantic meaning.
  ConnectionType connectionType;

  /// Connection visual style — how the line is drawn.
  ConnectionStyle connectionStyle;

  /// Whether this connection is bidirectional (arrows on both ends).
  bool isBidirectional;

  /// Particle positions along the path (0.0–1.0).
  /// NOT serialized — regenerated on load.
  List<double> particlePositions;

  /// Number of particles on this connection.
  static const int defaultParticleCount = 5;

  /// 🎨 Mind-map palette — single source of truth for all connection coloring.
  /// Used by controller (auto-assign), overlay (color picker), and painter.
  static const List<Color> mindMapPalette = [
    Color(0xFF64B5F6), // Sky Blue
    Color(0xFF81C784), // Sage Green
    Color(0xFFFFB74D), // Warm Orange
    Color(0xFF9B72E8), // Violet
    Color(0xFFFF7A8A), // Coral
    Color(0xFF5CE0A0), // Emerald
    Color(0xFFE86BCC), // Magenta
    Color(0xFFFFB347), // Amber
    Color(0xFF6B8CFF), // Periwinkle
    Color(0xFFFF6BA6), // Rose
  ];

  /// Particle speed: full path traversal time in seconds.
  static const double particleLoopDuration = 2.5;

  /// Timestamp when this connection was created (milliseconds since epoch).
  /// Used for birth animation effect (1.5s draw-in with ease-out).
  /// NOT serialized — set to 0 on load (no animation on reload).
  int createdAtMs;

  /// Timestamp when this connection was marked for deletion (milliseconds since epoch).
  /// When > 0, the connection is "dying" and will dissolve over 500ms.
  /// NOT serialized — transient state only.
  int deletedAtMs;

  /// Approximate path length in canvas units.
  /// Set by controller after path computation. Used for speed-proportional particles.
  double pathLength;

  /// Frozen anchor point at source cluster (captured at creation time).
  /// Used for rendering instead of live cluster centroid to prevent
  /// endpoint shifts when new strokes change the cluster.
  /// May be null for legacy connections (falls back to cluster centroid).
  Offset? sourceAnchor;

  /// Frozen anchor point at target cluster (captured at creation time).
  Offset? targetAnchor;

  // ===========================================================================
  // 🎤 AUDIO-INK SYNC — Flow Playback timestamps
  // ===========================================================================

  /// Timestamp (ms) relative to the active audio recording when this
  /// connection was created. Used for audio-ink sync: tapping a connection
  /// seeks to this exact moment in the recording.
  /// Serialized — persisted alongside canvas data.
  int? recordingTimestampMs;

  /// ID of the [SynchronizedRecording] this connection was created during.
  /// null if the connection was created without an active recording.
  String? recordingId;

  /// Whether this is an AI-generated ghost connection (not yet confirmed).
  /// Ghost connections render as dashed pulsating lines and can be
  /// materialized by the user into solid connections.
  bool isGhost;

  /// Whether this connection spans across different conceptual zones.
  ///
  /// Spec P9-05: Cross-zone connections render with golden color (#FFD700)
  /// and 3px stroke width to visually distinguish them from intra-zone
  /// connections. They remain prominent at all zoom levels.
  ///
  /// Determined by spatial distance between source and target anchors:
  /// connections > [crossZoneDistanceThreshold] canvas units apart are
  /// considered cross-zone.
  bool isCrossZone;

  // ===========================================================================
  // 🌉 CROSS-ZONE BRIDGE METADATA (Passo 9)
  // ===========================================================================

  /// Bridge type classification (P9-05 types A/B/C).
  /// Null for non-cross-zone connections.
  CrossZoneBridgeType? bridgeType;

  /// Who discovered this bridge (P9-12): student (💡) or AI (🤖).
  /// Null for non-cross-zone connections.
  BridgeDiscoveryOrigin? discoveredBy;

  /// ID of the cluster containing the student's handwritten annotation
  /// explaining this bridge (P9-06). Written at the midpoint of the arrow.
  /// Null if the student hasn't annotated the bridge yet.
  String? bridgeAnnotationClusterId;

  /// The Socratic question that prompted this bridge (P9-09).
  /// Stored for reference and session data. Null for student-discovered bridges.
  String? bridgeSocraticQuestion;

  /// Golden color for cross-zone bridges (spec P9-05).
  static const Color crossZoneColor = Color(0xFFFFD700);

  /// Stroke width for cross-zone bridges (spec P9-05: 3px).
  static const double crossZoneStrokeWidth = 3.0;

  /// Spatial distance threshold (canvas units) to classify as cross-zone.
  /// Clusters > 800 units apart are considered different conceptual zones.
  static const double crossZoneDistanceThreshold = 800.0;

  KnowledgeConnection({
    required this.id,
    required this.sourceClusterId,
    required this.targetClusterId,
    this.label,
    this.color = const Color(0xFF64B5F6), // Material Blue 300
    this.curveStrength = 0.3,
    this.connectionType = ConnectionType.association,
    this.connectionStyle = ConnectionStyle.curved,
    this.isBidirectional = false,
    this.pathLength = 500.0, // Default path length
    this.sourceAnchor,
    this.targetAnchor,
    this.recordingTimestampMs,
    this.recordingId,
    this.isGhost = false,
    this.isCrossZone = false,
    this.bridgeType,
    this.discoveredBy,
    this.bridgeAnnotationClusterId,
    this.bridgeSocraticQuestion,
    int? createdAt,
  }) : createdAtMs = createdAt ?? DateTime.now().millisecondsSinceEpoch,
       deletedAtMs = 0,
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

  /// Materialize a ghost connection into a solid (user-confirmed) one.
  /// Sets [isGhost] to false and resets the birth animation timestamp.
  void materialize() {
    isGhost = false;
    createdAtMs = DateTime.now().millisecondsSinceEpoch;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'sourceClusterId': sourceClusterId,
    'targetClusterId': targetClusterId,
    if (label != null) 'label': label,
    'color': color.toARGB32(),
    'curveStrength': curveStrength,
    'connectionType': connectionType.name,
    'connectionStyle': connectionStyle.name,
    'isBidirectional': isBidirectional,
    if (sourceAnchor != null) 'sourceAnchor': [sourceAnchor!.dx, sourceAnchor!.dy],
    if (targetAnchor != null) 'targetAnchor': [targetAnchor!.dx, targetAnchor!.dy],
    if (recordingTimestampMs != null) 'recordingTimestampMs': recordingTimestampMs,
    if (recordingId != null) 'recordingId': recordingId,
    if (isGhost) 'isGhost': true,
    if (isCrossZone) 'isCrossZone': true,
    // 🌉 PASSO 9: Cross-zone bridge metadata
    if (bridgeType != null) 'bridgeType': bridgeType!.name,
    if (discoveredBy != null) 'discoveredBy': discoveredBy!.name,
    if (bridgeAnnotationClusterId != null)
      'bridgeAnnotationClusterId': bridgeAnnotationClusterId,
    if (bridgeSocraticQuestion != null)
      'bridgeSocraticQuestion': bridgeSocraticQuestion,
  };

  factory KnowledgeConnection.fromJson(Map<String, dynamic> json) {
    return KnowledgeConnection(
      id: json['id'] as String,
      sourceClusterId: json['sourceClusterId'] as String,
      targetClusterId: json['targetClusterId'] as String,
      label: json['label'] as String?,
      color: Color(json['color'] as int? ?? 0xFF64B5F6),
      curveStrength: (json['curveStrength'] as num?)?.toDouble() ?? 0.3,
      connectionType: _parseConnectionType(json['connectionType'] as String?),
      connectionStyle: _parseConnectionStyle(json['connectionStyle'] as String?),
      isBidirectional: json['isBidirectional'] as bool? ?? false,
      sourceAnchor: _parseOffset(json['sourceAnchor']),
      targetAnchor: _parseOffset(json['targetAnchor']),
      recordingTimestampMs: json['recordingTimestampMs'] as int?,
      recordingId: json['recordingId'] as String?,
      isGhost: json['isGhost'] as bool? ?? false,
      isCrossZone: json['isCrossZone'] as bool? ?? false,
      // 🌉 PASSO 9: Backward-compatible bridge fields
      bridgeType: _parseBridgeType(json['bridgeType'] as String?),
      discoveredBy: _parseDiscoveryOrigin(json['discoveredBy'] as String?),
      bridgeAnnotationClusterId: json['bridgeAnnotationClusterId'] as String?,
      bridgeSocraticQuestion: json['bridgeSocraticQuestion'] as String?,
      createdAt: 0, // No animation on reload
    );
  }

  static Offset? _parseOffset(dynamic json) {
    if (json is List && json.length >= 2) {
      return Offset((json[0] as num).toDouble(), (json[1] as num).toDouble());
    }
    return null;
  }

  static ConnectionType _parseConnectionType(String? name) {
    if (name == null) return ConnectionType.association;
    return ConnectionType.values.firstWhere(
      (e) => e.name == name,
      orElse: () => ConnectionType.association,
    );
  }

  static ConnectionStyle _parseConnectionStyle(String? name) {
    if (name == null) return ConnectionStyle.curved;
    return ConnectionStyle.values.firstWhere(
      (e) => e.name == name,
      orElse: () => ConnectionStyle.curved,
    );
  }

  /// Parse [CrossZoneBridgeType] from JSON (backward-compatible: null if absent).
  static CrossZoneBridgeType? _parseBridgeType(String? name) {
    if (name == null) return null;
    return CrossZoneBridgeType.values
        .where((e) => e.name == name)
        .firstOrNull;
  }

  /// Parse [BridgeDiscoveryOrigin] from JSON (backward-compatible: null if absent).
  static BridgeDiscoveryOrigin? _parseDiscoveryOrigin(String? name) {
    if (name == null) return null;
    return BridgeDiscoveryOrigin.values
        .where((e) => e.name == name)
        .firstOrNull;
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

