import 'dart:ui';
import './vector_network.dart';

/// SVG path data (`d` attribute) converter for [VectorNetwork].
///
/// Supports M, L, C, Q, Z commands for import/export.
///
/// ```dart
/// // Export
/// final d = VectorNetworkSvg.toSvgPath(network);
/// // => "M 0 0 C 25 50 75 50 100 0"
///
/// // Import
/// final network = VectorNetworkSvg.fromSvgPath("M 0 0 L 100 0 L 50 86 Z");
/// ```
class VectorNetworkSvg {
  VectorNetworkSvg._();

  /// Convert a [VectorNetwork] to an SVG path `d` attribute string.
  ///
  /// Traces connected chains of segments. Each chain starts with 'M'
  /// and ends with 'Z' if the chain forms a loop.
  static String toSvgPath(VectorNetwork network) {
    if (network.segments.isEmpty) return '';

    final buf = StringBuffer();
    final usedSegments = <int>{};

    for (int v = 0; v < network.vertices.length; v++) {
      if (network.degree(v) == 0) continue;

      // Find unvisited segments from this vertex.
      final adj = network.adjacentSegments(v);
      for (final segIdx in adj) {
        if (usedSegments.contains(segIdx)) continue;

        // Start a new subpath.
        if (buf.isNotEmpty) buf.write(' ');
        final startPos = network.vertices[v].position;
        buf.write('M ${_fmt(startPos.dx)} ${_fmt(startPos.dy)}');

        // Trace the chain.
        var current = v;
        var nextSegIdx = segIdx;

        while (!usedSegments.contains(nextSegIdx)) {
          usedSegments.add(nextSegIdx);
          final seg = network.segments[nextSegIdx];
          final isReversed = seg.end == current;
          final target = isReversed ? seg.start : seg.end;
          final targetPos = network.vertices[target].position;

          if (seg.isStraight) {
            buf.write(' L ${_fmt(targetPos.dx)} ${_fmt(targetPos.dy)}');
          } else if (seg.tangentStart != null && seg.tangentEnd != null) {
            final ts = isReversed ? seg.tangentEnd! : seg.tangentStart!;
            final te = isReversed ? seg.tangentStart! : seg.tangentEnd!;
            buf.write(
              ' C ${_fmt(ts.dx)} ${_fmt(ts.dy)}'
              ' ${_fmt(te.dx)} ${_fmt(te.dy)}'
              ' ${_fmt(targetPos.dx)} ${_fmt(targetPos.dy)}',
            );
          } else {
            final cp =
                (isReversed
                    ? (seg.tangentEnd ?? seg.tangentStart)
                    : (seg.tangentStart ?? seg.tangentEnd)) ??
                targetPos;
            buf.write(
              ' Q ${_fmt(cp.dx)} ${_fmt(cp.dy)}'
              ' ${_fmt(targetPos.dx)} ${_fmt(targetPos.dy)}',
            );
          }

          current = target;

          // Find next segment (continue chain if degree == 2).
          if (current == v) {
            buf.write(' Z');
            break;
          }
          final nextAdj = network.adjacentSegments(current);
          nextSegIdx = -1;
          for (final s in nextAdj) {
            if (!usedSegments.contains(s)) {
              nextSegIdx = s;
              break;
            }
          }
          if (nextSegIdx == -1) break;
        }
      }
    }

    return buf.toString();
  }

  /// Parse an SVG path `d` attribute into a [VectorNetwork].
  ///
  /// Supports commands: M, L, C, Q, Z (case-insensitive).
  static VectorNetwork fromSvgPath(String d) {
    final network = VectorNetwork();
    final tokens = _tokenize(d);
    int pos = 0;
    int? firstVertexInSubpath;
    int? lastVertex;

    while (pos < tokens.length) {
      final cmd = tokens[pos].toUpperCase();
      pos++;

      switch (cmd) {
        case 'M':
          final x = double.parse(tokens[pos++]);
          final y = double.parse(tokens[pos++]);
          final idx = network.addVertex(NetworkVertex(position: Offset(x, y)));
          firstVertexInSubpath = idx;
          lastVertex = idx;
          break;

        case 'L':
          final x = double.parse(tokens[pos++]);
          final y = double.parse(tokens[pos++]);
          final idx = network.addVertex(NetworkVertex(position: Offset(x, y)));
          if (lastVertex != null) {
            network.addSegment(NetworkSegment(start: lastVertex, end: idx));
          }
          lastVertex = idx;
          break;

        case 'C':
          final cx1 = double.parse(tokens[pos++]);
          final cy1 = double.parse(tokens[pos++]);
          final cx2 = double.parse(tokens[pos++]);
          final cy2 = double.parse(tokens[pos++]);
          final x = double.parse(tokens[pos++]);
          final y = double.parse(tokens[pos++]);
          final idx = network.addVertex(NetworkVertex(position: Offset(x, y)));
          if (lastVertex != null) {
            network.addSegment(
              NetworkSegment(
                start: lastVertex,
                end: idx,
                tangentStart: Offset(cx1, cy1),
                tangentEnd: Offset(cx2, cy2),
              ),
            );
          }
          lastVertex = idx;
          break;

        case 'Q':
          final cx = double.parse(tokens[pos++]);
          final cy = double.parse(tokens[pos++]);
          final x = double.parse(tokens[pos++]);
          final y = double.parse(tokens[pos++]);
          final idx = network.addVertex(NetworkVertex(position: Offset(x, y)));
          if (lastVertex != null) {
            network.addSegment(
              NetworkSegment(
                start: lastVertex,
                end: idx,
                tangentStart: Offset(cx, cy),
              ),
            );
          }
          lastVertex = idx;
          break;

        case 'Z':
          if (lastVertex != null &&
              firstVertexInSubpath != null &&
              lastVertex != firstVertexInSubpath) {
            network.addSegment(
              NetworkSegment(start: lastVertex, end: firstVertexInSubpath),
            );
          }
          lastVertex = firstVertexInSubpath;
          break;

        default:
          // Skip unknown commands.
          break;
      }
    }

    return network;
  }

  /// Tokenize SVG path data into commands and numbers.
  static List<String> _tokenize(String d) {
    final result = <String>[];
    final pattern = RegExp(
      r'[MmLlCcQqZz]|[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?',
    );
    for (final match in pattern.allMatches(d)) {
      result.add(match.group(0)!);
    }
    return result;
  }

  /// Format a double for SVG (no trailing zeros).
  static String _fmt(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(2);
  }
}
