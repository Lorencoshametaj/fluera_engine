import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// 🪣 Fill Tool — Flood fill for the professional canvas
///
/// Implements the scanline flood fill algorithm to fill areas
/// bounded by existing strokes. Operates on a rasterized image
/// of the current canvas.
///
/// Workflow:
/// 1. User taps a point on the canvas
/// 2. Canvas is rasterized into a bitmap image
/// 3. The flood fill algorithm identifies the connected area
/// 4. A path is generated as the outline of the filled area
/// 5. The filled path is added as a new stroke/shape to the layer
class FloodFillTool {
  /// Color tolerance (0-255): how much a pixel can differ from the target color
  /// and still be considered the "same color" for the fill
  int colorTolerance;

  /// Fill color
  Color fillColor;

  FloodFillTool({this.colorTolerance = 32, this.fillColor = Colors.blue});

  /// Executes the flood fill on an image starting from a point
  ///
  /// [image] Rasterized image of the canvas
  /// [startPoint] Starting point in image coordinates
  /// [onComplete] Callback with the mask of pixels to fill
  ///
  /// Returns a boolean mask Uint8List of the same size as the image,
  /// where true indicates a pixel to fill.
  Future<Uint8List?> executeFloodFill(ui.Image image, Offset startPoint) async {
    final width = image.width;
    final height = image.height;

    // Convert image to RGBA byte array
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) return null;

    final pixels = byteData.buffer.asUint8List();
    final startX = startPoint.dx.toInt().clamp(0, width - 1);
    final startY = startPoint.dy.toInt().clamp(0, height - 1);

    // Target color (color of the pixel under the tap)
    final targetIndex = (startY * width + startX) * 4;
    final targetR = pixels[targetIndex];
    final targetG = pixels[targetIndex + 1];
    final targetB = pixels[targetIndex + 2];
    final targetA = pixels[targetIndex + 3];

    // Visited pixel mask
    final visited = Uint8List(width * height);

    // Scanline flood fill (more efficient than recursive)
    final stack = <_Span>[];
    stack.add(_Span(startX, startX, startY, 1));
    stack.add(_Span(startX, startX, startY - 1, -1));

    while (stack.isNotEmpty) {
      final span = stack.removeLast();
      var x1 = span.x1;
      final y = span.y;
      final dy = span.dy;

      if (y < 0 || y >= height) continue;

      // Expand left
      while (x1 >= 0 &&
          _matchesTarget(
            pixels,
            x1,
            y,
            width,
            targetR,
            targetG,
            targetB,
            targetA,
          ) &&
          visited[y * width + x1] == 0) {
        visited[y * width + x1] = 1;
        x1--;
      }
      x1++;

      // Expand right
      var x = x1;
      while (x < width &&
          _matchesTarget(
            pixels,
            x,
            y,
            width,
            targetR,
            targetG,
            targetB,
            targetA,
          ) &&
          visited[y * width + x] == 0) {
        visited[y * width + x] = 1;
        x++;
      }

      // Add span for the next row
      if (x1 < x) {
        // Row in the current direction
        final nextY = y + dy;
        if (nextY >= 0 && nextY < height) {
          _addSpans(
            stack,
            visited,
            pixels,
            x1,
            x - 1,
            nextY,
            dy,
            width,
            targetR,
            targetG,
            targetB,
            targetA,
          );
        }

        // Row in the opposite direction (for concave areas)
        final prevY = y - dy;
        if (prevY >= 0 && prevY < height) {
          // Only the parts that extend beyond the original range
          if (x1 < span.x1) {
            _addSpans(
              stack,
              visited,
              pixels,
              x1,
              span.x1 - 1,
              prevY,
              -dy,
              width,
              targetR,
              targetG,
              targetB,
              targetA,
            );
          }
          if (x - 1 > span.x2) {
            _addSpans(
              stack,
              visited,
              pixels,
              span.x2 + 1,
              x - 1,
              prevY,
              -dy,
              width,
              targetR,
              targetG,
              targetB,
              targetA,
            );
          }
        }
      }
    }

    return visited;
  }

  /// Generates an image from the flood fill result
  Future<ui.Image?> generateFillImage(
    Uint8List mask,
    int width,
    int height,
    Color fillColor,
  ) async {
    final pixels = Uint8List(width * height * 4);
    final r = (fillColor.r * 255.0).round().clamp(0, 255);
    final g = (fillColor.g * 255.0).round().clamp(0, 255);
    final b = (fillColor.b * 255.0).round().clamp(0, 255);
    final a = (fillColor.a * 255.0).round().clamp(0, 255);

    for (int i = 0; i < mask.length; i++) {
      if (mask[i] == 1) {
        final offset = i * 4;
        pixels[offset] = r;
        pixels[offset + 1] = g;
        pixels[offset + 2] = b;
        pixels[offset + 3] = a;
      }
    }

    final codec =
        await ui.ImageDescriptor.raw(
          await ui.ImmutableBuffer.fromUint8List(pixels),
          width: width,
          height: height,
          pixelFormat: ui.PixelFormat.rgba8888,
        ).instantiateCodec();

    final frame = await codec.getNextFrame();
    return frame.image;
  }

  /// Checks if a pixel matches the target color (with tolerance)
  bool _matchesTarget(
    Uint8List pixels,
    int x,
    int y,
    int width,
    int targetR,
    int targetG,
    int targetB,
    int targetA,
  ) {
    final index = (y * width + x) * 4;
    final dr = (pixels[index] - targetR).abs();
    final dg = (pixels[index + 1] - targetG).abs();
    final db = (pixels[index + 2] - targetB).abs();
    final da = (pixels[index + 3] - targetA).abs();

    return dr <= colorTolerance &&
        dg <= colorTolerance &&
        db <= colorTolerance &&
        da <= colorTolerance;
  }

  /// Adds spans for the next row
  void _addSpans(
    List<_Span> stack,
    Uint8List visited,
    Uint8List pixels,
    int x1,
    int x2,
    int y,
    int dy,
    int width,
    int targetR,
    int targetG,
    int targetB,
    int targetA,
  ) {
    var x = x1;
    while (x <= x2) {
      // Find the start of an unvisited segment that matches
      while (x <= x2 &&
          (visited[y * width + x] == 1 ||
              !_matchesTarget(
                pixels,
                x,
                y,
                width,
                targetR,
                targetG,
                targetB,
                targetA,
              ))) {
        x++;
      }
      if (x > x2) break;

      final spanStart = x;
      // Find the end of the segment
      while (x <= x2 &&
          visited[y * width + x] == 0 &&
          _matchesTarget(
            pixels,
            x,
            y,
            width,
            targetR,
            targetG,
            targetB,
            targetA,
          )) {
        x++;
      }

      stack.add(_Span(spanStart, x - 1, y, dy));
    }
  }
}

/// Span for the scanline flood fill algorithm
class _Span {
  final int x1;
  final int x2;
  final int y;
  final int dy; // Scan direction (+1 or -1)

  const _Span(this.x1, this.x2, this.y, this.dy);
}
