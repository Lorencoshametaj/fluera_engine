import 'dart:ui';

/// 🌊 CONTENT CLUSTER — A group of elements that move as a rigid body.
///
/// During content reflow, individual strokes within a cluster are NEVER
/// separated. The cluster moves as one unit, preserving handwritten words,
/// signatures, and coherent drawings.
///
/// DESIGN:
/// - Clusters are built by [ClusterDetector] using temporal + spatial proximity
/// - [DigitalTextElement], [ImageElement], [GeometricShape] → always single clusters
/// - Only [ProStroke] elements are candidates for multi-stroke clustering
/// - Clusters are rebuilt when layer content changes (add/remove/undo)
class ContentCluster {
  /// Unique cluster identifier.
  final String id;

  /// Stroke IDs belonging to this cluster (may be multiple for handwriting).
  final List<String> strokeIds;

  /// Shape IDs (always 0 or 1 per cluster).
  final List<String> shapeIds;

  /// Text IDs (always 0 or 1 per cluster).
  final List<String> textIds;

  /// Image IDs (always 0 or 1 per cluster).
  final List<String> imageIds;

  /// Union of all element bounds in this cluster (updated after reflow bake).
  Rect bounds;

  /// Mass center — used as origin for force calculations (updated after bake).
  Offset centroid;

  /// If true, this cluster is excluded from reflow (locked layer/element).
  final bool isPinned;

  /// Current reflow displacement (mutable, updated by physics engine).
  Offset displacement;

  /// Current velocity for settling animation.
  Offset velocity;

  ContentCluster({
    required this.id,
    required this.strokeIds,
    this.shapeIds = const [],
    this.textIds = const [],
    this.imageIds = const [],
    required this.bounds,
    required this.centroid,
    this.isPinned = false,
    this.displacement = Offset.zero,
    this.velocity = Offset.zero,
  });

  /// Total number of elements in this cluster.
  int get elementCount =>
      strokeIds.length + shapeIds.length + textIds.length + imageIds.length;

  /// Whether this cluster contains multiple strokes (handwriting/drawing).
  bool get isMultiStroke => strokeIds.length > 1;

  /// The displaced bounds (bounds shifted by current displacement).
  Rect get displacedBounds => bounds.shift(displacement);

  /// The displaced centroid.
  Offset get displacedCentroid => centroid + displacement;

  /// Approximate mass — larger clusters are harder to push.
  /// Uses bounds area as a proxy for visual weight.
  double get mass => bounds.width * bounds.height;

  /// Whether this cluster has any active displacement.
  bool get isDisplaced => displacement != Offset.zero;

  /// Check if this cluster contains a specific element ID.
  bool containsElement(String elementId) =>
      strokeIds.contains(elementId) ||
      shapeIds.contains(elementId) ||
      textIds.contains(elementId) ||
      imageIds.contains(elementId);

  /// Reset displacement and velocity to zero.
  void resetDisplacement() {
    displacement = Offset.zero;
    velocity = Offset.zero;
  }

  /// Create a copy with different displacement/velocity.
  ContentCluster copyWith({
    Offset? displacement,
    Offset? velocity,
    bool? isPinned,
  }) {
    return ContentCluster(
      id: id,
      strokeIds: strokeIds,
      shapeIds: shapeIds,
      textIds: textIds,
      imageIds: imageIds,
      bounds: bounds,
      centroid: centroid,
      isPinned: isPinned ?? this.isPinned,
      displacement: displacement ?? this.displacement,
      velocity: velocity ?? this.velocity,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ContentCluster &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'ContentCluster(id: $id, strokes: ${strokeIds.length}, '
      'shapes: ${shapeIds.length}, texts: ${textIds.length}, '
      'images: ${imageIds.length}, bounds: $bounds, '
      'displaced: $isDisplaced)';
}
