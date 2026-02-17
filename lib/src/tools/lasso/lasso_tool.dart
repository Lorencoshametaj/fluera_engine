import 'dart:math';
import 'package:flutter/material.dart';
import '../../drawing/models/pro_drawing_point.dart';
import '../../core/models/shape_type.dart';
import '../../core/models/canvas_layer.dart';
import '../../layers/nebula_layer_controller.dart';
import '../../canvas/infinite_canvas_controller.dart';

/// 🎨 LASSO TOOL - Strumento di selezione professionale
///
/// Caratteristiche:
/// - Selezione a mano libera (lasso)
/// - Detection of elements inside closed path
/// - Supporto multi-selezione
/// - Operazioni su selected elements (move, delete, copy, rotate, flip)
/// - Drag to move elements
/// - Auto-scroll at screen edge
class LassoTool {
  final NebulaLayerController layerController;

  // Path del lasso corrente
  List<Offset> lassoPath = [];

  // Elementi selezionati
  final Set<String> selectedStrokeIds = {};
  final Set<String> selectedShapeIds = {};

  // Stato del drag
  bool _isDragging = false;
  Offset? _dragStartPosition;
  Rect? _selectionBounds;

  LassoTool({required this.layerController});

  /// Checks if the point is inside the selection area (to start drag)
  bool isPointInSelection(Offset point) {
    if (!hasSelection) return false;
    if (_selectionBounds == null) {
      _calculateSelectionBounds();
    }
    return _selectionBounds?.contains(point) ?? false;
  }

  /// Calculates i bounds degli selected elements
  void _calculateSelectionBounds() {
    if (!hasSelection) {
      _selectionBounds = null;
      return;
    }

    final activeLayer = layerController.layers.firstWhere(
      (layer) => layer.id == layerController.activeLayerId,
      orElse: () => layerController.layers.first,
    );

    double? minX, minY, maxX, maxY;

    // Calculate bounds of strokes selezionati
    for (final stroke in activeLayer.strokes) {
      if (selectedStrokeIds.contains(stroke.id)) {
        for (final point in stroke.points) {
          minX =
              minX == null
                  ? point.position.dx
                  : (point.position.dx < minX ? point.position.dx : minX);
          minY =
              minY == null
                  ? point.position.dy
                  : (point.position.dy < minY ? point.position.dy : minY);
          maxX =
              maxX == null
                  ? point.position.dx
                  : (point.position.dx > maxX ? point.position.dx : maxX);
          maxY =
              maxY == null
                  ? point.position.dy
                  : (point.position.dy > maxY ? point.position.dy : maxY);
        }
      }
    }

    // Calculate bounds delle shapes selezionate
    for (final shape in activeLayer.shapes) {
      if (selectedShapeIds.contains(shape.id)) {
        final rect = Rect.fromPoints(shape.startPoint, shape.endPoint);
        minX = minX == null ? rect.left : (rect.left < minX ? rect.left : minX);
        minY = minY == null ? rect.top : (rect.top < minY ? rect.top : minY);
        maxX =
            maxX == null ? rect.right : (rect.right > maxX ? rect.right : maxX);
        maxY =
            maxY == null
                ? rect.bottom
                : (rect.bottom > maxY ? rect.bottom : maxY);
      }
    }

    if (minX != null && minY != null && maxX != null && maxY != null) {
      _selectionBounds = Rect.fromLTRB(
        minX - 20,
        minY - 20,
        maxX + 20,
        maxY + 20,
      );
    }
  }

  /// Start il drag degli selected elements
  void startDrag(Offset position) {
    _isDragging = true;
    _dragStartPosition = position;
  }

  /// Updates the drag (moves elements)
  void updateDrag(Offset currentPosition) {
    if (!_isDragging || _dragStartPosition == null) return;

    final delta = currentPosition - _dragStartPosition!;
    moveSelected(delta);
    _dragStartPosition = currentPosition;

    // Sposta anche i bounds della selezione (more efficiente che ricalcolare)
    if (_selectionBounds != null) {
      _selectionBounds = _selectionBounds!.shift(delta);
    }
  }

  /// Compensate the scroll of the canvas durante il drag (more efficiente, without rebuild pesanti)
  void compensateScroll(Offset scrollDelta) {
    if (!_isDragging || _dragStartPosition == null) return;

    // Sposta direttamente gli elementi del delta dello scroll
    // This is more efficient than updateDrag because it doesn't recalculate everything
    moveSelected(scrollDelta);

    // IMPORTANTE: Update anche _dragStartPosition per compensare lo scroll
    // Altrimenti il prossimo movimento del dito will have un delta sbagliato
    _dragStartPosition = _dragStartPosition! + scrollDelta;

    // Also update the selection bounds
    if (_selectionBounds != null) {
      _selectionBounds = _selectionBounds!.shift(scrollDelta);
    }

    // NON ricalcolare bounds for performance
  }

  /// Termina il drag
  void endDrag() {
    _isDragging = false;
    _dragStartPosition = null;
  }

  /// Checks if it is in corso un drag
  bool get isDragging => _isDragging;

  /// Start il lasso path
  void startLasso(Offset position) {
    lassoPath.clear();
    lassoPath.add(position);
    clearSelection();
  }

  /// Updates il lasso path
  void updateLasso(Offset position) {
    lassoPath.add(position);
  }

  /// Complete the lasso and select elements
  void completeLasso() {
    if (lassoPath.length < 3) {
      lassoPath.clear();
      return;
    }

    // Cloif the percorso
    if (lassoPath.first != lassoPath.last) {
      lassoPath.add(lassoPath.first);
    }

    // Create un Path for the test di intersezione
    final path = Path();
    path.moveTo(lassoPath.first.dx, lassoPath.first.dy);
    for (var i = 1; i < lassoPath.length; i++) {
      path.lineTo(lassoPath[i].dx, lassoPath[i].dy);
    }
    path.close();

    // Seleziona elementi dentro il lasso
    _selectElementsInPath(path);

    // If is not stato selezionato nulla, pulisci tutto
    if (!hasSelection) {
      lassoPath.clear();
      return;
    }

    // Calculate i bounds for the drag
    _calculateSelectionBounds();

    // Clear the lasso path now that elements are selected
    // Rimane only the bordo della selezione
    lassoPath.clear();
  }

  /// Seleziona elementi che intersecano il path del lasso
  void _selectElementsInPath(Path lassoPath) {
    final activeLayer = layerController.layers.firstWhere(
      (layer) => layer.id == layerController.activeLayerId,
      orElse: () => layerController.layers.first,
    );

    // Check strokes
    for (final stroke in activeLayer.strokes) {
      if (_strokeIntersectsPath(stroke, lassoPath)) {
        selectedStrokeIds.add(stroke.id);
      }
    }

    // Check shapes
    for (final shape in activeLayer.shapes) {
      if (_shapeIntersectsPath(shape, lassoPath)) {
        selectedShapeIds.add(shape.id);
      }
    }
  }

  /// Checks se uno stroke interseca il path
  bool _strokeIntersectsPath(ProStroke stroke, Path lassoPath) {
    // Check if at least one point of the stroke is inside the path
    for (final point in stroke.points) {
      if (lassoPath.contains(point.position)) {
        return true;
      }
    }
    return false;
  }

  /// Checks if a shape interseca il path
  bool _shapeIntersectsPath(GeometricShape shape, Path lassoPath) {
    // Check if the key points of the shape are inside the path
    if (lassoPath.contains(shape.startPoint) ||
        lassoPath.contains(shape.endPoint)) {
      return true;
    }

    // Check the center of the shape
    final center = Offset(
      (shape.startPoint.dx + shape.endPoint.dx) / 2,
      (shape.startPoint.dy + shape.endPoint.dy) / 2,
    );
    return lassoPath.contains(center);
  }

  /// Erases gli selected elements
  void deleteSelected() {
    if (selectedStrokeIds.isEmpty && selectedShapeIds.isEmpty) return;

    final activeLayer = layerController.layers.firstWhere(
      (layer) => layer.id == layerController.activeLayerId,
      orElse: () => layerController.layers.first,
    );

    // Remove strokes selezionati
    final filteredStrokes =
        activeLayer.strokes
            .where((stroke) => !selectedStrokeIds.contains(stroke.id))
            .toList();

    // Remove shapes selezionati
    final filteredShapes =
        activeLayer.shapes
            .where((shape) => !selectedShapeIds.contains(shape.id))
            .toList();

    // Update il layer
    final updatedLayer = activeLayer.copyWith(
      strokes: filteredStrokes,
      shapes: filteredShapes,
    );

    _updateLayer(updatedLayer);
    clearSelection();
  }

  /// Sposta gli selected elements
  void moveSelected(Offset delta) {
    if (selectedStrokeIds.isEmpty && selectedShapeIds.isEmpty) return;

    final activeLayer = layerController.layers.firstWhere(
      (layer) => layer.id == layerController.activeLayerId,
      orElse: () => layerController.layers.first,
    );


    // Sposta strokes
    final movedStrokes =
        activeLayer.strokes.map((stroke) {
          if (selectedStrokeIds.contains(stroke.id)) {
            final movedPoints =
                stroke.points
                    .map(
                      (point) =>
                          point.copyWith(position: point.position + delta),
                    )
                    .toList();
            return stroke.copyWith(points: movedPoints);
          }
          return stroke;
        }).toList();

    // Sposta shapes
    final movedShapes =
        activeLayer.shapes.map((shape) {
          if (selectedShapeIds.contains(shape.id)) {
            return shape.copyWith(
              startPoint: shape.startPoint + delta,
              endPoint: shape.endPoint + delta,
            );
          }
          return shape;
        }).toList();

    // Update il layer
    final updatedLayer = activeLayer.copyWith(
      strokes: movedStrokes,
      shapes: movedShapes,
    );

    _updateLayer(updatedLayer);
  }

  /// Updates un layer nel controller
  void _updateLayer(CanvasLayer updatedLayer) {
    layerController.updateLayer(updatedLayer);
  }

  /// Ruota gli selected elements di 90° (senso orario)
  void rotateSelected() {
    if (!hasSelection) return;

    _calculateSelectionBounds();
    if (_selectionBounds == null) return;

    final center = _selectionBounds!.center;

    final activeLayer = layerController.layers.firstWhere(
      (layer) => layer.id == layerController.activeLayerId,
      orElse: () => layerController.layers.first,
    );

    // Ruota strokes
    final rotatedStrokes =
        activeLayer.strokes.map((stroke) {
          if (selectedStrokeIds.contains(stroke.id)) {
            final rotatedPoints =
                stroke.points.map((point) {
                  // Translate al centro, ruota, trasla indietro
                  final translated = point.position - center;
                  final rotated = Offset(
                    -translated.dy,
                    translated.dx,
                  ); // Rotazione 90° oraria
                  return point.copyWith(position: rotated + center);
                }).toList();
            return stroke.copyWith(points: rotatedPoints);
          }
          return stroke;
        }).toList();

    // Ruota shapes
    final rotatedShapes =
        activeLayer.shapes.map((shape) {
          if (selectedShapeIds.contains(shape.id)) {
            // For shapes, ruota i punti di start e end
            final startTranslated = shape.startPoint - center;
            final endTranslated = shape.endPoint - center;
            final startRotated = Offset(
              -startTranslated.dy,
              startTranslated.dx,
            );
            final endRotated = Offset(-endTranslated.dy, endTranslated.dx);
            return shape.copyWith(
              startPoint: startRotated + center,
              endPoint: endRotated + center,
            );
          }
          return shape;
        }).toList();

    // Update il layer
    final updatedLayer = activeLayer.copyWith(
      strokes: rotatedStrokes,
      shapes: rotatedShapes,
    );

    _updateLayer(updatedLayer);
    _calculateSelectionBounds(); // Recalculate bounds after rotation
  }

  /// 🔄 Ruota gli selected elements di un angolo arbitrario (in radianti)
  ///
  /// Generalizzazione di rotateSelected() per rotazione libera.
  /// [radians] Angolo di rotazione (positivo = orario)
  /// [center] Rotation center (default: selection center)
  void rotateSelectedByAngle(double radians, {Offset? center}) {
    if (!hasSelection) return;

    _calculateSelectionBounds();
    if (_selectionBounds == null) return;

    final rotCenter = center ?? _selectionBounds!.center;
    final cosA = cos(radians);
    final sinA = sin(radians);

    final activeLayer = layerController.layers.firstWhere(
      (layer) => layer.id == layerController.activeLayerId,
      orElse: () => layerController.layers.first,
    );

    // Ruota strokes
    final rotatedStrokes =
        activeLayer.strokes.map((stroke) {
          if (selectedStrokeIds.contains(stroke.id)) {
            final rotatedPoints =
                stroke.points.map((point) {
                  final translated = point.position - rotCenter;
                  final rotated = Offset(
                    translated.dx * cosA - translated.dy * sinA,
                    translated.dx * sinA + translated.dy * cosA,
                  );
                  return point.copyWith(position: rotated + rotCenter);
                }).toList();
            return stroke.copyWith(points: rotatedPoints);
          }
          return stroke;
        }).toList();

    // Ruota shapes
    final rotatedShapes =
        activeLayer.shapes.map((shape) {
          if (selectedShapeIds.contains(shape.id)) {
            final startT = shape.startPoint - rotCenter;
            final endT = shape.endPoint - rotCenter;
            return shape.copyWith(
              startPoint: Offset(
                startT.dx * cosA - startT.dy * sinA + rotCenter.dx,
                startT.dx * sinA + startT.dy * cosA + rotCenter.dy,
              ),
              endPoint: Offset(
                endT.dx * cosA - endT.dy * sinA + rotCenter.dx,
                endT.dx * sinA + endT.dy * cosA + rotCenter.dy,
              ),
            );
          }
          return shape;
        }).toList();

    final updatedLayer = activeLayer.copyWith(
      strokes: rotatedStrokes,
      shapes: rotatedShapes,
    );

    _updateLayer(updatedLayer);
    _calculateSelectionBounds();
  }

  /// 📐 Scala gli selected elements rispetto a un centro
  ///
  /// [factor] Fattore di scala (>1 = ingrandisci, <1 = rimpicciolisci)
  /// [center] Centro di scala (default: centro selezione)
  void scaleSelected(double factor, {Offset? center}) {
    if (!hasSelection || factor <= 0) return;

    _calculateSelectionBounds();
    if (_selectionBounds == null) return;

    final scaleCenter = center ?? _selectionBounds!.center;

    final activeLayer = layerController.layers.firstWhere(
      (layer) => layer.id == layerController.activeLayerId,
      orElse: () => layerController.layers.first,
    );

    // Scala strokes
    final scaledStrokes =
        activeLayer.strokes.map((stroke) {
          if (selectedStrokeIds.contains(stroke.id)) {
            final scaledPoints =
                stroke.points.map((point) {
                  final translated = point.position - scaleCenter;
                  final scaled = Offset(
                    translated.dx * factor,
                    translated.dy * factor,
                  );
                  return point.copyWith(position: scaled + scaleCenter);
                }).toList();
            // Scala anthat the larghezza of the stroke
            return stroke.copyWith(
              points: scaledPoints,
              baseWidth: stroke.baseWidth * factor,
            );
          }
          return stroke;
        }).toList();

    // Scala shapes
    final scaledShapes =
        activeLayer.shapes.map((shape) {
          if (selectedShapeIds.contains(shape.id)) {
            final startT = shape.startPoint - scaleCenter;
            final endT = shape.endPoint - scaleCenter;
            return shape.copyWith(
              startPoint: Offset(
                startT.dx * factor + scaleCenter.dx,
                startT.dy * factor + scaleCenter.dy,
              ),
              endPoint: Offset(
                endT.dx * factor + scaleCenter.dx,
                endT.dy * factor + scaleCenter.dy,
              ),
              strokeWidth: shape.strokeWidth * factor,
            );
          }
          return shape;
        }).toList();

    final updatedLayer = activeLayer.copyWith(
      strokes: scaledStrokes,
      shapes: scaledShapes,
    );

    _updateLayer(updatedLayer);
    _calculateSelectionBounds();
  }

  /// Rifletti gli selected elements (flip orizzontale)
  void flipHorizontal() {
    if (!hasSelection) return;

    _calculateSelectionBounds();
    if (_selectionBounds == null) return;

    final centerX = _selectionBounds!.center.dx;

    final activeLayer = layerController.layers.firstWhere(
      (layer) => layer.id == layerController.activeLayerId,
      orElse: () => layerController.layers.first,
    );

    // Rifletti strokes
    final flippedStrokes =
        activeLayer.strokes.map((stroke) {
          if (selectedStrokeIds.contains(stroke.id)) {
            final flippedPoints =
                stroke.points.map((point) {
                  final distance = point.position.dx - centerX;
                  return point.copyWith(
                    position: Offset(centerX - distance, point.position.dy),
                  );
                }).toList();
            return stroke.copyWith(points: flippedPoints);
          }
          return stroke;
        }).toList();

    // Rifletti shapes
    final flippedShapes =
        activeLayer.shapes.map((shape) {
          if (selectedShapeIds.contains(shape.id)) {
            final startDistance = shape.startPoint.dx - centerX;
            final endDistance = shape.endPoint.dx - centerX;
            return shape.copyWith(
              startPoint: Offset(centerX - startDistance, shape.startPoint.dy),
              endPoint: Offset(centerX - endDistance, shape.endPoint.dy),
            );
          }
          return shape;
        }).toList();

    final updatedLayer = activeLayer.copyWith(
      strokes: flippedStrokes,
      shapes: flippedShapes,
    );

    _updateLayer(updatedLayer);
  }

  /// Rifletti gli selected elements (flip verticale)
  void flipVertical() {
    if (!hasSelection) return;

    _calculateSelectionBounds();
    if (_selectionBounds == null) return;

    final centerY = _selectionBounds!.center.dy;

    final activeLayer = layerController.layers.firstWhere(
      (layer) => layer.id == layerController.activeLayerId,
      orElse: () => layerController.layers.first,
    );

    // Rifletti strokes
    final flippedStrokes =
        activeLayer.strokes.map((stroke) {
          if (selectedStrokeIds.contains(stroke.id)) {
            final flippedPoints =
                stroke.points.map((point) {
                  final distance = point.position.dy - centerY;
                  return point.copyWith(
                    position: Offset(point.position.dx, centerY - distance),
                  );
                }).toList();
            return stroke.copyWith(points: flippedPoints);
          }
          return stroke;
        }).toList();

    // Rifletti shapes
    final flippedShapes =
        activeLayer.shapes.map((shape) {
          if (selectedShapeIds.contains(shape.id)) {
            final startDistance = shape.startPoint.dy - centerY;
            final endDistance = shape.endPoint.dy - centerY;
            return shape.copyWith(
              startPoint: Offset(shape.startPoint.dx, centerY - startDistance),
              endPoint: Offset(shape.endPoint.dx, centerY - endDistance),
            );
          }
          return shape;
        }).toList();

    final updatedLayer = activeLayer.copyWith(
      strokes: flippedStrokes,
      shapes: flippedShapes,
    );

    _updateLayer(updatedLayer);
  }

  /// Erases la selezione
  void clearSelection() {
    selectedStrokeIds.clear();
    selectedShapeIds.clear();
    _selectionBounds = null;
    lassoPath.clear(); // Clear anthat the lasso path
    _isDragging = false; // Termina eventuale drag
    _dragStartPosition = null;
  }

  /// Checks if there are selected elements
  bool get hasSelection =>
      selectedStrokeIds.isNotEmpty || selectedShapeIds.isNotEmpty;

  /// Get il number of selected elements
  int get selectionCount => selectedStrokeIds.length + selectedShapeIds.length;

  /// Erases il path del lasso
  void clearLassoPath() {
    lassoPath.clear();
  }

  /// Gets i tratti selezionati dal layer attivo
  List<ProStroke> getSelectedStrokes() {
    if (selectedStrokeIds.isEmpty) return [];

    final activeLayer = layerController.layers.firstWhere(
      (layer) => layer.id == layerController.activeLayerId,
      orElse: () => layerController.layers.first,
    );

    return activeLayer.strokes
        .where((stroke) => selectedStrokeIds.contains(stroke.id))
        .toList();
  }

  /// Gets i bounds della selezione corrente
  Rect? getSelectionBounds() {
    if (_selectionBounds == null) {
      _calculateSelectionBounds();
    }
    return _selectionBounds;
  }
}

