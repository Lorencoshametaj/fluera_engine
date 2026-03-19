import 'dart:ui';
import 'dart:math' as math;
import './content_cluster.dart';

// =============================================================================
// ✂️ SPACE-SPLIT CONTROLLER  v3
//
// v3 IMPROVEMENTS:
//   - Horizontal split mode (←→ spread pushes left/right)
//   - Auto-detect direction: if all clusters are on one side, use full spread
//     for that direction instead of splitting 50/50
//   - All v2 features: bidirectional, squeeze, element-level ghosts
// =============================================================================

/// The axis along which the split operates.
enum SplitAxis { vertical, horizontal }

/// ✂️ Controls the space-splitting gesture lifecycle.
///
/// Supports both vertical (↕) and horizontal (↔) splitting.
/// Auto-detects whether to use full spread or half-spread based on
/// cluster distribution around the split line.
class SpaceSplitController {
  /// Whether a split gesture is currently active.
  bool get isActive => _isActive;
  bool _isActive = false;

  /// The split axis (vertical = horizontal line, horizontal = vertical line).
  SplitAxis get axis => _axis;
  SplitAxis _axis = SplitAxis.vertical;

  /// The coordinate of the split line in canvas space.
  /// For vertical axis: Y coordinate. For horizontal axis: X coordinate.
  double get splitLinePosition => _splitLinePosition;
  double _splitLinePosition = 0.0;

  /// Convenience alias for vertical splits.
  double get splitLineY => _splitLinePosition;

  /// Convenience alias for horizontal splits.
  double get splitLineX => _splitLinePosition;

  /// The current spread distance in canvas-space pixels.
  double get spreadDistance => _spreadDistance;
  double _spreadDistance = 0.0;

  /// Whether auto-detect chose unidirectional mode.
  bool get isUnidirectional => _isUnidirectional;
  bool _isUnidirectional = false;

  /// Direction of unidirectional push: +1 = positive axis, -1 = negative axis.
  int get unidirectionalSign => _unidirectionalSign;
  int _unidirectionalSign = 0;

  /// Current ghost displacements for rendering preview.
  Map<String, Offset> get ghostDisplacements => _ghostDisplacements;
  Map<String, Offset> _ghostDisplacements = {};

  /// Element-level ghost displacements.
  Map<String, Offset> get elementGhostDisplacements => _elementGhostDisplacements;
  Map<String, Offset> _elementGhostDisplacements = {};

  /// Cached cluster list.
  List<ContentCluster> clusters = [];

  // ===========================================================================
  // TUNING CONSTANTS
  // ===========================================================================

  static const double minSpreadThreshold = 10.0;
  static const double _falloffRadius = 800.0;
  static const double _maxDisplacement = 2000.0;

  /// If more than this fraction of clusters are on one side, use unidirectional.
  static const double _unidirectionalThreshold = 0.85;

  // ===========================================================================
  // PUBLIC API
  // ===========================================================================

  /// Start a space-split gesture.
  ///
  /// [position] — the split line coordinate (Y for vertical, X for horizontal).
  /// [axis] — the split axis.
  void startSplit(double position, {SplitAxis axis = SplitAxis.vertical}) {
    _isActive = true;
    _axis = axis;
    _splitLinePosition = position;
    _spreadDistance = 0.0;
    _ghostDisplacements = {};
    _elementGhostDisplacements = {};

    // Auto-detect direction
    _autoDetectDirection();
  }

  /// Update the split with a new spread distance.
  Map<String, Offset> updateSplit(double spreadDistance) {
    if (!_isActive) return {};

    _spreadDistance = spreadDistance.clamp(-_maxDisplacement, _maxDisplacement);

    if (_spreadDistance.abs() < minSpreadThreshold) {
      _ghostDisplacements = {};
      _elementGhostDisplacements = {};
      return _ghostDisplacements;
    }

    _ghostDisplacements = _computeDisplacements();
    _elementGhostDisplacements = _expandToElements(_ghostDisplacements);
    return _ghostDisplacements;
  }

  /// End the split gesture.
  SpaceSplitResult endSplit() {
    if (!_isActive) return const SpaceSplitResult.empty();
    _isActive = false;

    if (_spreadDistance.abs() < minSpreadThreshold || _ghostDisplacements.isEmpty) {
      _ghostDisplacements = {};
      _elementGhostDisplacements = {};
      return const SpaceSplitResult.empty();
    }

    final result = SpaceSplitResult(
      elementDisplacements: Map<String, Offset>.from(_elementGhostDisplacements),
      clusterDisplacements: Map<String, Offset>.from(_ghostDisplacements),
    );

    _ghostDisplacements = {};
    _elementGhostDisplacements = {};
    return result;
  }

  /// Cancel the split gesture.
  void cancelSplit() {
    _isActive = false;
    _spreadDistance = 0.0;
    _ghostDisplacements = {};
    _elementGhostDisplacements = {};
  }

  // ===========================================================================
  // INTERNAL
  // ===========================================================================

  /// Detect if all clusters are on one side of the split line.
  /// If so, use full spread in that direction (unidirectional).
  void _autoDetectDirection() {
    if (clusters.isEmpty) {
      _isUnidirectional = false;
      _unidirectionalSign = 0;
      return;
    }

    int above = 0, below = 0;
    for (final cluster in clusters) {
      final pos = _axis == SplitAxis.vertical
          ? cluster.centroid.dy
          : cluster.centroid.dx;
      if (pos > _splitLinePosition) {
        below++;
      } else if (pos < _splitLinePosition) {
        above++;
      }
    }

    final total = above + below;
    if (total == 0) {
      _isUnidirectional = false;
      _unidirectionalSign = 0;
      return;
    }

    if (below / total >= _unidirectionalThreshold) {
      _isUnidirectional = true;
      _unidirectionalSign = 1; // All below → full push down/right
    } else if (above / total >= _unidirectionalThreshold) {
      _isUnidirectional = true;
      _unidirectionalSign = -1; // All above → full push up/left
    } else {
      _isUnidirectional = false;
      _unidirectionalSign = 0; // Bidirectional
    }
  }

  /// Compute displacements for all clusters.
  Map<String, Offset> _computeDisplacements() {
    final result = <String, Offset>{};

    // Unidirectional: full spread in one direction
    // Bidirectional: half spread each way
    final effectiveSpread = _isUnidirectional
        ? _spreadDistance
        : _spreadDistance / 2.0;

    for (final cluster in clusters) {
      final pos = _axis == SplitAxis.vertical
          ? cluster.centroid.dy
          : cluster.centroid.dx;
      final distanceFromLine = (pos - _splitLinePosition).abs();

      if (distanceFromLine < 0.1) continue;

      final falloff = 1.0 / (1.0 + distanceFromLine / _falloffRadius);
      final magnitude = effectiveSpread * falloff;

      if (magnitude.abs() < 0.5) continue;

      if (_isUnidirectional) {
        // Push everything in _unidirectionalSign direction
        final sign = _unidirectionalSign.toDouble();
        if (_axis == SplitAxis.vertical) {
          // Only affect clusters on the correct side
          if ((pos - _splitLinePosition) * sign > 0) {
            result[cluster.id] = Offset(0.0, magnitude * sign);
          }
        } else {
          if ((pos - _splitLinePosition) * sign > 0) {
            result[cluster.id] = Offset(magnitude * sign, 0.0);
          }
        }
      } else {
        // Bidirectional
        if (pos > _splitLinePosition) {
          result[cluster.id] = _axis == SplitAxis.vertical
              ? Offset(0.0, magnitude)
              : Offset(magnitude, 0.0);
        } else {
          result[cluster.id] = _axis == SplitAxis.vertical
              ? Offset(0.0, -magnitude)
              : Offset(-magnitude, 0.0);
        }
      }
    }

    return result;
  }

  /// Expand cluster-level displacements to element-level IDs.
  Map<String, Offset> _expandToElements(Map<String, Offset> clusterDisplacements) {
    final result = <String, Offset>{};

    for (final entry in clusterDisplacements.entries) {
      final cluster = clusters.firstWhere(
        (c) => c.id == entry.key,
        orElse: () => ContentCluster(
          id: '',
          strokeIds: const [],
          bounds: Rect.zero,
          centroid: Offset.zero,
        ),
      );
      if (cluster.id.isEmpty) continue;

      final d = entry.value;
      for (final id in cluster.strokeIds) result[id] = d;
      for (final id in cluster.shapeIds) result[id] = d;
      for (final id in cluster.textIds) result[id] = d;
      for (final id in cluster.imageIds) result[id] = d;
    }

    return result;
  }
}

// =============================================================================
// RESULT TYPE
// =============================================================================

class SpaceSplitResult {
  final Map<String, Offset> elementDisplacements;
  final Map<String, Offset> clusterDisplacements;

  const SpaceSplitResult({
    required this.elementDisplacements,
    required this.clusterDisplacements,
  });

  const SpaceSplitResult.empty()
      : elementDisplacements = const {},
        clusterDisplacements = const {};

  bool get isEmpty => elementDisplacements.isEmpty;
  bool get isNotEmpty => elementDisplacements.isNotEmpty;
}
