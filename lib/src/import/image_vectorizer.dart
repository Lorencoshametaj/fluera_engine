import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:image/image.dart' as img;

import '../drawing/models/pro_drawing_point.dart';
import '../drawing/models/pro_brush_settings.dart';
import '../utils/uid.dart';
import 'stroke_import_models.dart';

/// Converts a rasterized handwriting image into [ProStroke] objects.
///
/// Pipeline:
/// 1. Downscale large images (cap at ~2000px longest side)
/// 2. Extract per-pixel color map (before binarization destroys color)
/// 3. Binarize (Otsu threshold)
/// 4. Remove noise (small connected components < 20px)
/// 5. Filter ruled-paper lines (long straight horizontal/vertical runs)
/// 6. Distance transform (for width estimation)
/// 7. Zhang-Suen thinning → 1px skeleton
/// 8. Trace connected polylines
/// 9. Ramer-Douglas-Peucker simplification
/// 10. Gaussian smoothing on polyline coordinates
/// 11. Extract dominant color per stroke from color map
/// 12. Convert to [ProStroke]
///
/// Memory-optimized: uses [Uint8List] instead of `List<bool>` (~8x savings).
/// Designed to run in a `compute()` isolate for large images.
class ImageVectorizer {
  const ImageVectorizer._();

  /// Maximum processing dimension. Images larger than this are downscaled
  /// before vectorization, then coordinates are scaled back up.
  static const int _maxProcessingDim = 2000;

  /// Minimum connected component area (pixels) to keep. Smaller = noise.
  static const int _minComponentArea = 20;

  /// Minimum stroke length (points) after simplification.
  static const int _minStrokePoints = 2;

  /// Full pipeline: image → list of [ProStroke].
  static List<ProStroke> vectorize(
    img.Image image, {
    Offset offset = Offset.zero,
    double scale = 1.0,
    Color? inkColor,
  }) {
    // 1. Downscale if needed
    final downscaleFactor = _computeDownscale(image.width, image.height);
    final img.Image proc;
    if (downscaleFactor < 1.0) {
      proc = img.copyResize(
        image,
        width: (image.width * downscaleFactor).round(),
        height: (image.height * downscaleFactor).round(),
        interpolation: img.Interpolation.average,
      );
    } else {
      proc = image;
    }
    // Total scale: downscale correction * caller scale
    final totalScale = scale / downscaleFactor;

    final w = proc.width;
    final h = proc.height;
    final n = w * h;

    // 2. Extract color map (RGB per pixel, before we lose it to binarization)
    final colorR = Uint8List(n);
    final colorG = Uint8List(n);
    final colorB = Uint8List(n);
    final gray = Uint8List(n);

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final pixel = proc.getPixel(x, y);
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();
        final i = y * w + x;
        colorR[i] = r;
        colorG[i] = g;
        colorB[i] = b;
        gray[i] = (0.299 * r + 0.587 * g + 0.114 * b).round();
      }
    }

    // 3. Binarize — hybrid: Otsu on luminance + saturation boost for colored ink
    //
    // Blue/red ink on white has low luminance contrast but HIGH saturation.
    // Pure Otsu misses it. We detect ink as: dark (Otsu) OR saturated+not-bright.
    final threshold = _otsuThreshold(gray, n);
    final binary = Uint8List(n); // 1 = ink, 0 = background
    for (int i = 0; i < n; i++) {
      // Standard Otsu
      if (gray[i] < threshold) {
        binary[i] = 1;
        continue;
      }
      // Saturation boost: detect colored ink that Otsu misses.
      // Compute saturation: (max - min) / max, in 0..255 range.
      final r = colorR[i], g = colorG[i], b = colorB[i];
      final maxC = math.max(r, math.max(g, b));
      final minC = math.min(r, math.min(g, b));
      if (maxC > 30) { // avoid div-by-zero on near-black
        final sat = ((maxC - minC) * 255) ~/ maxC; // 0..255
        // Ink if: saturated (>80/255) AND not very bright (gray < 200)
        if (sat > 80 && gray[i] < 200) {
          binary[i] = 1;
          continue;
        }
      }
      binary[i] = 0;
    }

    // 4. Remove noise: flood-fill connected components, discard small ones
    _removeSmallComponents(binary, w, h, _minComponentArea);

    // 5. Filter ruled-paper lines
    _filterRuledLines(binary, w, h);

    // 6. Distance transform (on clean binary, before thinning)
    final distMap = _distanceTransform(binary, w, h);

    // 7. Zhang-Suen thinning
    _zhangSuenThin(binary, w, h);

    // 8. Trace polylines from skeleton
    final polylines = _tracePolylines(binary, w, h);

    // 9–12. Process each polyline into a ProStroke
    final strokes = <ProStroke>[];
    final now = DateTime.now();
    final baseTimestamp = now.millisecondsSinceEpoch;

    // Global max width for cross-stroke pressure normalization
    double globalMaxW = 0;
    for (int i = 0; i < n; i++) {
      if (distMap[i] > globalMaxW) globalMaxW = distMap[i];
    }

    // 8b. Split polylines at sharp direction changes (>90°) to separate
    // connected letters/shapes that skeleton tracing merged into one polyline.
    final splitPolylines = <List<Offset>>[];
    for (final raw in polylines) {
      if (raw.length < 3) {
        splitPolylines.add(raw);
      } else {
        splitPolylines.addAll(_splitAtSharpAngles(raw, maxAngleDeg: 90.0));
      }
    }

    for (int i = 0; i < splitPolylines.length; i++) {
      final raw = splitPolylines[i];
      if (raw.length < _minStrokePoints) continue;

      // 9. Simplify with RDP (iterative — safe for long polylines)
      final simplified = _rdpSimplify(raw, 1.5);
      if (simplified.length < _minStrokePoints) continue;

      // 10. Gaussian smooth the polyline coordinates
      final smoothed = _gaussianSmooth(simplified, sigma: 1.2);

      // Estimate widths from distance transform
      final widths = <double>[];
      for (final p in smoothed) {
        final px = p.dx.round().clamp(0, w - 1);
        final py = p.dy.round().clamp(0, h - 1);
        widths.add(distMap[py * w + px]);
      }

      // Median width for baseWidth
      final sortedWidths = List<double>.from(widths)..sort();
      final medianWidth = sortedWidths[sortedWidths.length ~/ 2];
      final baseWidth = (medianWidth * 2 * totalScale).clamp(0.5, 20.0);

      // 11. Extract dominant color along this stroke
      Color strokeColor;
      if (inkColor != null) {
        strokeColor = inkColor;
      } else {
        strokeColor = _extractStrokeColor(
          smoothed, colorR, colorG, colorB, w, h,
        );
      }

      // 12. Convert to ProDrawingPoints
      final points = <ProDrawingPoint>[];
      for (int j = 0; j < smoothed.length; j++) {
        final p = smoothed[j];
        // Normalize pressure against global max for consistent cross-stroke weight
        final pressure =
            globalMaxW > 0 ? (widths[j] / globalMaxW).clamp(0.15, 1.0) : 0.5;
        points.add(ProDrawingPoint(
          position: Offset(
            p.dx * totalScale + offset.dx,
            p.dy * totalScale + offset.dy,
          ),
          pressure: pressure,
          timestamp: baseTimestamp + i * 100 + j,
        ));
      }

      strokes.add(ProStroke(
        id: generateUid(),
        points: points,
        color: strokeColor,
        baseWidth: baseWidth,
        penType: ProPenType.ballpoint,
        createdAt: now,
        settings: const ProBrushSettings(),
      ));
    }

    return strokes;
  }

  // ---------------------------------------------------------------------------
  // Downscaling
  // ---------------------------------------------------------------------------

  static double _computeDownscale(int w, int h) {
    final longest = math.max(w, h);
    if (longest <= _maxProcessingDim) return 1.0;
    return _maxProcessingDim / longest;
  }

  // ---------------------------------------------------------------------------
  // Binarization (Otsu)
  // ---------------------------------------------------------------------------

  static int _otsuThreshold(Uint8List gray, int total) {
    final histogram = Int32List(256);
    for (int i = 0; i < total; i++) {
      histogram[gray[i]]++;
    }

    double sumAll = 0;
    for (int i = 0; i < 256; i++) {
      sumAll += i * histogram[i];
    }

    double sumBg = 0;
    int weightBg = 0;
    double maxVariance = 0;
    int bestThreshold = 128;

    for (int t = 0; t < 256; t++) {
      weightBg += histogram[t];
      if (weightBg == 0) continue;
      final weightFg = total - weightBg;
      if (weightFg == 0) break;

      sumBg += t * histogram[t];
      final meanBg = sumBg / weightBg;
      final meanFg = (sumAll - sumBg) / weightFg;
      final diff = meanBg - meanFg;
      final variance = diff * diff * weightBg * weightFg;

      if (variance > maxVariance) {
        maxVariance = variance;
        bestThreshold = t;
      }
    }
    return bestThreshold;
  }

  // ---------------------------------------------------------------------------
  // Noise removal (connected component filtering)
  // ---------------------------------------------------------------------------

  static void _removeSmallComponents(Uint8List binary, int w, int h, int minArea) {
    final labels = Int32List(w * h); // 0 = unlabeled
    int nextLabel = 1;
    final areas = <int, int>{}; // label → pixel count

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final i = y * w + x;
        if (binary[i] == 0 || labels[i] != 0) continue;

        // BFS flood fill
        final label = nextLabel++;
        int area = 0;
        final queue = <int>[i];
        labels[i] = label;

        while (queue.isNotEmpty) {
          final ci = queue.removeLast();
          area++;
          final cx = ci % w;
          final cy = ci ~/ w;

          for (int dy = -1; dy <= 1; dy++) {
            for (int dx = -1; dx <= 1; dx++) {
              if (dx == 0 && dy == 0) continue;
              final nx = cx + dx, ny = cy + dy;
              if (nx < 0 || nx >= w || ny < 0 || ny >= h) continue;
              final ni = ny * w + nx;
              if (binary[ni] == 1 && labels[ni] == 0) {
                labels[ni] = label;
                queue.add(ni);
              }
            }
          }
        }
        areas[label] = area;
      }
    }

    // Zero out small components
    for (int i = 0; i < w * h; i++) {
      if (labels[i] > 0 && (areas[labels[i]] ?? 0) < minArea) {
        binary[i] = 0;
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Ruled-paper line filtering
  // ---------------------------------------------------------------------------

  /// Detects and removes long horizontal/vertical runs that are likely
  /// ruled-paper lines rather than handwriting.
  ///
  /// Heuristic: a horizontal run of ink pixels spanning >60% of the image
  /// width, with a thin profile (height ≤ 3px), is classified as a rule line.
  /// Same logic vertically for graph paper.
  static void _filterRuledLines(Uint8List binary, int w, int h) {
    // Horizontal scan: for each row, find max continuous ink run
    final minRunLength = (w * 0.6).round();
    for (int y = 0; y < h; y++) {
      int run = 0;
      int runStart = 0;
      for (int x = 0; x <= w; x++) {
        final isInk = x < w && binary[y * w + x] == 1;
        if (isInk) {
          if (run == 0) runStart = x;
          run++;
        } else {
          if (run >= minRunLength) {
            // Check that this run is thin (max 3px tall)
            if (_isLineThin(binary, w, h, runStart, y, run, true, 3)) {
              for (int rx = runStart; rx < runStart + run; rx++) {
                binary[y * w + rx] = 0;
              }
            }
          }
          run = 0;
        }
      }
    }

    // Vertical scan
    final minRunLengthV = (h * 0.6).round();
    for (int x = 0; x < w; x++) {
      int run = 0;
      int runStart = 0;
      for (int y = 0; y <= h; y++) {
        final isInk = y < h && binary[y * w + x] == 1;
        if (isInk) {
          if (run == 0) runStart = y;
          run++;
        } else {
          if (run >= minRunLengthV) {
            if (_isLineThin(binary, w, h, x, runStart, run, false, 3)) {
              for (int ry = runStart; ry < runStart + run; ry++) {
                binary[ry * w + x] = 0;
              }
            }
          }
          run = 0;
        }
      }
    }
  }

  /// Check if a horizontal or vertical run of ink is thin (≤ maxThickness).
  static bool _isLineThin(
    Uint8List binary, int w, int h,
    int startX, int startY, int runLen,
    bool isHorizontal, int maxThickness,
  ) {
    // Sample a few points along the run and check cross-axis thickness
    const sampleCount = 5;
    final step = math.max(1, runLen ~/ sampleCount);

    for (int s = 0; s < runLen; s += step) {
      int thickness = 0;
      if (isHorizontal) {
        final x = startX + s;
        for (int dy = -maxThickness; dy <= maxThickness; dy++) {
          final ny = startY + dy;
          if (ny >= 0 && ny < h && binary[ny * w + x] == 1) thickness++;
        }
      } else {
        final y = startY + s;
        for (int dx = -maxThickness; dx <= maxThickness; dx++) {
          final nx = startX + dx;
          if (nx >= 0 && nx < w && binary[y * w + nx] == 1) thickness++;
        }
      }
      if (thickness > maxThickness) return false;
    }
    return true;
  }

  // ---------------------------------------------------------------------------
  // Distance Transform
  // ---------------------------------------------------------------------------

  static Float32List _distanceTransform(Uint8List binary, int w, int h) {
    const double inf = 1e9;
    final dist = Float32List(w * h);

    for (int i = 0; i < w * h; i++) {
      dist[i] = binary[i] == 1 ? inf : 0;
    }

    // Forward pass
    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        final i = y * w + x;
        if (binary[i] == 0) continue;
        dist[i] = _min5(
          dist[i],
          dist[(y - 1) * w + (x - 1)] + 1.414,
          dist[(y - 1) * w + x] + 1.0,
          dist[(y - 1) * w + (x + 1)] + 1.414,
          dist[y * w + (x - 1)] + 1.0,
        );
      }
    }

    // Backward pass
    for (int y = h - 2; y > 0; y--) {
      for (int x = w - 2; x > 0; x--) {
        final i = y * w + x;
        if (binary[i] == 0) continue;
        dist[i] = _min5(
          dist[i],
          dist[(y + 1) * w + (x + 1)] + 1.414,
          dist[(y + 1) * w + x] + 1.0,
          dist[(y + 1) * w + (x - 1)] + 1.414,
          dist[y * w + (x + 1)] + 1.0,
        );
      }
    }

    return dist;
  }

  static double _min5(double a, double b, double c, double d, double e) =>
      math.min(math.min(math.min(a, b), math.min(c, d)), e);

  // ---------------------------------------------------------------------------
  // Zhang-Suen Thinning (Uint8List version)
  // ---------------------------------------------------------------------------

  static void _zhangSuenThin(Uint8List binary, int w, int h) {
    bool changed = true;
    final toRemove = <int>[];

    while (changed) {
      changed = false;

      toRemove.clear();
      for (int y = 1; y < h - 1; y++) {
        for (int x = 1; x < w - 1; x++) {
          final i = y * w + x;
          if (binary[i] == 0) continue;
          if (_zsStep1(binary, x, y, w)) toRemove.add(i);
        }
      }
      for (final i in toRemove) {
        binary[i] = 0;
        changed = true;
      }

      toRemove.clear();
      for (int y = 1; y < h - 1; y++) {
        for (int x = 1; x < w - 1; x++) {
          final i = y * w + x;
          if (binary[i] == 0) continue;
          if (_zsStep2(binary, x, y, w)) toRemove.add(i);
        }
      }
      for (final i in toRemove) {
        binary[i] = 0;
        changed = true;
      }
    }
  }

  // Inline neighbor access to avoid List allocation per pixel
  static bool _zsStep1(Uint8List b, int x, int y, int w) {
    final p2 = b[(y - 1) * w + x];
    final p3 = b[(y - 1) * w + x + 1];
    final p4 = b[y * w + x + 1];
    final p5 = b[(y + 1) * w + x + 1];
    final p6 = b[(y + 1) * w + x];
    final p7 = b[(y + 1) * w + x - 1];
    final p8 = b[y * w + x - 1];
    final p9 = b[(y - 1) * w + x - 1];

    final nz = p2 + p3 + p4 + p5 + p6 + p7 + p8 + p9;
    if (nz < 2 || nz > 6) return false;

    // Count 0→1 transitions
    int tr = 0;
    if (p2 == 0 && p3 == 1) tr++;
    if (p3 == 0 && p4 == 1) tr++;
    if (p4 == 0 && p5 == 1) tr++;
    if (p5 == 0 && p6 == 1) tr++;
    if (p6 == 0 && p7 == 1) tr++;
    if (p7 == 0 && p8 == 1) tr++;
    if (p8 == 0 && p9 == 1) tr++;
    if (p9 == 0 && p2 == 1) tr++;
    if (tr != 1) return false;

    if (p2 == 1 && p4 == 1 && p6 == 1) return false;
    if (p4 == 1 && p6 == 1 && p8 == 1) return false;
    return true;
  }

  static bool _zsStep2(Uint8List b, int x, int y, int w) {
    final p2 = b[(y - 1) * w + x];
    final p3 = b[(y - 1) * w + x + 1];
    final p4 = b[y * w + x + 1];
    final p5 = b[(y + 1) * w + x + 1];
    final p6 = b[(y + 1) * w + x];
    final p7 = b[(y + 1) * w + x - 1];
    final p8 = b[y * w + x - 1];
    final p9 = b[(y - 1) * w + x - 1];

    final nz = p2 + p3 + p4 + p5 + p6 + p7 + p8 + p9;
    if (nz < 2 || nz > 6) return false;

    int tr = 0;
    if (p2 == 0 && p3 == 1) tr++;
    if (p3 == 0 && p4 == 1) tr++;
    if (p4 == 0 && p5 == 1) tr++;
    if (p5 == 0 && p6 == 1) tr++;
    if (p6 == 0 && p7 == 1) tr++;
    if (p7 == 0 && p8 == 1) tr++;
    if (p8 == 0 && p9 == 1) tr++;
    if (p9 == 0 && p2 == 1) tr++;
    if (tr != 1) return false;

    if (p2 == 1 && p4 == 1 && p8 == 1) return false;
    if (p2 == 1 && p6 == 1 && p8 == 1) return false;
    return true;
  }

  // ---------------------------------------------------------------------------
  // Polyline Tracing
  // ---------------------------------------------------------------------------

  static List<List<Offset>> _tracePolylines(Uint8List skel, int w, int h) {
    final visited = Uint8List(w * h);
    final polylines = <List<Offset>>[];

    // Mark junctions (3+ skeleton neighbors)
    final junctions = Uint8List(w * h);
    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        final i = y * w + x;
        if (skel[i] == 0) continue;
        int nc = 0;
        for (int dy = -1; dy <= 1; dy++) {
          for (int dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) continue;
            if (skel[(y + dy) * w + (x + dx)] == 1) nc++;
          }
        }
        if (nc >= 3) junctions[i] = 1;
      }
    }

    // Trace from endpoints and junctions
    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        final i = y * w + x;
        if (skel[i] == 0 || visited[i] == 1) continue;

        int nc = 0;
        for (int dy = -1; dy <= 1; dy++) {
          for (int dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) continue;
            if (skel[(y + dy) * w + (x + dx)] == 1) nc++;
          }
        }
        if (nc != 1 && junctions[i] == 0) continue;

        final line = <Offset>[];
        int cx = x, cy = y;

        while (true) {
          final ci = cy * w + cx;
          if (visited[ci] == 1 && line.isNotEmpty) break;
          visited[ci] = 1;
          line.add(Offset(cx.toDouble(), cy.toDouble()));
          if (junctions[ci] == 1 && line.length > 1) break;

          int nx = -1, ny = -1;
          for (int dy = -1; dy <= 1; dy++) {
            for (int dx = -1; dx <= 1; dx++) {
              if (dx == 0 && dy == 0) continue;
              final nxi = cx + dx, nyi = cy + dy;
              if (nxi < 0 || nxi >= w || nyi < 0 || nyi >= h) continue;
              if (skel[nyi * w + nxi] == 1 && visited[nyi * w + nxi] == 0) {
                nx = nxi;
                ny = nyi;
              }
            }
          }
          if (nx < 0) break;
          cx = nx;
          cy = ny;
        }
        if (line.length >= 2) polylines.add(line);
      }
    }

    // Second pass: unvisited segments
    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        final i = y * w + x;
        if (skel[i] == 0 || visited[i] == 1) continue;

        final line = <Offset>[];
        int cx = x, cy = y;
        while (true) {
          final ci = cy * w + cx;
          if (visited[ci] == 1 && line.isNotEmpty) break;
          visited[ci] = 1;
          line.add(Offset(cx.toDouble(), cy.toDouble()));

          int nx = -1, ny = -1;
          for (int dy = -1; dy <= 1; dy++) {
            for (int dx = -1; dx <= 1; dx++) {
              if (dx == 0 && dy == 0) continue;
              final nxi = cx + dx, nyi = cy + dy;
              if (nxi < 0 || nxi >= w || nyi < 0 || nyi >= h) continue;
              if (skel[nyi * w + nxi] == 1 && visited[nyi * w + nxi] == 0) {
                nx = nxi;
                ny = nyi;
              }
            }
          }
          if (nx < 0) break;
          cx = nx;
          cy = ny;
        }
        if (line.length >= 2) polylines.add(line);
      }
    }

    return polylines;
  }

  // ---------------------------------------------------------------------------
  // Stroke Splitting at Sharp Direction Changes
  // ---------------------------------------------------------------------------

  /// Splits a polyline at points where the direction changes by more than
  /// [maxAngleDeg] degrees. This separates connected letters/shapes that
  /// the skeleton tracer merged into a single polyline.
  static List<List<Offset>> _splitAtSharpAngles(
    List<Offset> points, {
    double maxAngleDeg = 90.0,
  }) {
    if (points.length < 3) return [points];

    final maxAngleRad = maxAngleDeg * math.pi / 180.0;
    final segments = <List<Offset>>[];
    int segStart = 0;

    for (int i = 1; i < points.length - 1; i++) {
      final a = points[i] - points[i - 1];
      final b = points[i + 1] - points[i];
      final lenA = a.distance;
      final lenB = b.distance;
      if (lenA < 0.5 || lenB < 0.5) continue;

      // Angle between vectors via dot product
      final dot = a.dx * b.dx + a.dy * b.dy;
      final cosAngle = (dot / (lenA * lenB)).clamp(-1.0, 1.0);
      final angle = math.acos(cosAngle);

      if (angle > maxAngleRad) {
        // Split here — include the split point in both segments
        if (i - segStart >= 1) {
          segments.add(points.sublist(segStart, i + 1));
        }
        segStart = i;
      }
    }

    // Add final segment
    if (points.length - segStart >= 2) {
      segments.add(points.sublist(segStart));
    }

    return segments.isEmpty ? [points] : segments;
  }

  // ---------------------------------------------------------------------------
  // Ramer-Douglas-Peucker Simplification (iterative — no stack overflow)
  // ---------------------------------------------------------------------------

  static List<Offset> _rdpSimplify(List<Offset> points, double epsilon) {
    if (points.length <= 2) return points;

    // Iterative RDP using an explicit stack to avoid stack overflow
    // on very long polylines (>5000 points).
    final keep = List<bool>.filled(points.length, false);
    keep[0] = true;
    keep[points.length - 1] = true;

    // Stack of (startIndex, endIndex) ranges to process
    final stack = <int>[0, points.length - 1];

    while (stack.isNotEmpty) {
      final end = stack.removeLast();
      final start = stack.removeLast();

      double maxDist = 0;
      int maxIdx = start;
      final a = points[start];
      final b = points[end];

      for (int i = start + 1; i < end; i++) {
        final d = _perpendicularDistance(points[i], a, b);
        if (d > maxDist) {
          maxDist = d;
          maxIdx = i;
        }
      }

      if (maxDist > epsilon) {
        keep[maxIdx] = true;
        // Push right segment first (processed second = left-to-right order)
        if (maxIdx + 1 < end) {
          stack.add(maxIdx);
          stack.add(end);
        }
        if (start + 1 < maxIdx) {
          stack.add(start);
          stack.add(maxIdx);
        }
      }
    }

    return [
      for (int i = 0; i < points.length; i++)
        if (keep[i]) points[i],
    ];
  }

  static double _perpendicularDistance(Offset point, Offset a, Offset b) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final lenSq = dx * dx + dy * dy;
    if (lenSq == 0) return (point - a).distance;
    final num = (point.dx - a.dx) * dy - (point.dy - a.dy) * dx;
    return num.abs() / math.sqrt(lenSq);
  }

  // ---------------------------------------------------------------------------
  // Gaussian Smoothing on Polyline
  // ---------------------------------------------------------------------------

  /// Applies 1D Gaussian smoothing to polyline coordinates.
  /// Preserves endpoints to maintain stroke geometry.
  static List<Offset> _gaussianSmooth(List<Offset> points, {double sigma = 1.2}) {
    if (points.length <= 3) return points;

    final radius = (sigma * 2.5).ceil();
    final kernel = <double>[];
    double sum = 0;
    for (int i = -radius; i <= radius; i++) {
      final v = math.exp(-(i * i) / (2 * sigma * sigma));
      kernel.add(v);
      sum += v;
    }
    for (int i = 0; i < kernel.length; i++) {
      kernel[i] /= sum;
    }

    final result = List<Offset>.from(points);
    // Smooth interior points only (preserve endpoints)
    for (int i = 1; i < points.length - 1; i++) {
      double sx = 0, sy = 0;
      for (int k = -radius; k <= radius; k++) {
        final idx = (i + k).clamp(0, points.length - 1);
        sx += points[idx].dx * kernel[k + radius];
        sy += points[idx].dy * kernel[k + radius];
      }
      result[i] = Offset(sx, sy);
    }
    return result;
  }

  // ---------------------------------------------------------------------------
  // Color Extraction per Stroke
  // ---------------------------------------------------------------------------

  /// Samples the original image color along the stroke's path
  /// and returns the median color (robust to outliers).
  static Color _extractStrokeColor(
    List<Offset> points,
    Uint8List colorR, Uint8List colorG, Uint8List colorB,
    int w, int h,
  ) {
    if (points.isEmpty) return const Color(0xFF000000);

    // Sample up to 20 points evenly along the stroke
    final sampleCount = math.min(points.length, 20);
    final step = math.max(1, points.length ~/ sampleCount);

    final rs = <int>[];
    final gs = <int>[];
    final bs = <int>[];

    for (int i = 0; i < points.length; i += step) {
      final px = points[i].dx.round().clamp(0, w - 1);
      final py = points[i].dy.round().clamp(0, h - 1);
      final idx = py * w + px;
      rs.add(colorR[idx]);
      gs.add(colorG[idx]);
      bs.add(colorB[idx]);
    }

    // Median of each channel (robust to background bleed at edges)
    rs.sort();
    gs.sort();
    bs.sort();
    final mid = rs.length ~/ 2;

    return Color.fromARGB(255, rs[mid], gs[mid], bs[mid]);
  }
}
