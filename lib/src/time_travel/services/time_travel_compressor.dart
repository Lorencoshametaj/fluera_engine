import 'dart:math' as math;

/// 📦 Compressore per dati Time Travel basato su teoria dell'informazione
///
/// Apply three complementary techniques to reduce pre-GZIP entropy:
///
/// 1. **Delta Encoding** — Coordinates (x,y) and timestamps change from values
///    assoluti a differenze rispetto at the point precedente. Siccome punti
///    adjacent points of a stroke differ by few pixels, deltas have
///    much lower entropy (typically 1-2 cifre vs 3-4).
///    Shannon entropy ridotta: H(delta) << H(absolute).
///
/// 2. **Controlled quantization** — For Time Travel replay, 1 decimal
///    (0.1px) is sufficient. Main storage uses 4 decimals to preserve
///    Catmull-Rom splines, but replay doesn't require the same precision.
///    Reduction: ~50% on coordinate bytes.
///
/// 3. **Run-Length Encoding (RLE)** — Pressure, tilt, and orientation are
///    often constant for long strokes. Instead of repeating the same value
///    N volte, codifichiamo [valore, count]. Efficienza massima su stylus
///    passive (without pressione) dove pressure = 0.5 for all punti.
///
/// The three techniques are **composed in a pipeline**: first we quantize,
/// poi si delta-encoda, poi GZIP (esterno) cattura le ripetizioni residue.
///
/// **Lossless for the replay**: decompression reconstructs exactly
/// i dati compressi. La quantizzazione is l'unico step lossy, ma 0.1px
/// is imperceptible in replay.
class TimeTravelCompressor {
  /// Moltiplicatore per fixed-point encoding: 10 = 1 decimale di precisione
  /// (0.1px — sufficient for replay, vs 0.0001px of main storage)
  static const int _coordScale = 10;

  /// Soglia RLE: if the stesso valore si ripete >= N volte, usa RLE
  static const int _rleThreshold = 3;

  // ============================================================================
  // 📦 COMPRESSIONE
  // ============================================================================

  /// Compress elementData for strokeAdded events
  ///
  /// Transform the stroke JSON by applying:
  /// - Delta encoding on points.x, points.y, points.timestamp
  /// - Quantization to 1 decimal on coordinates
  /// - RLE su pressure, tiltX, tiltY, orientation
  static Map<String, dynamic> compressStrokeData(
    Map<String, dynamic> strokeData,
  ) {
    final points = strokeData['points'];
    if (points == null || points is! List || points.isEmpty) {
      return strokeData;
    }

    final compressed = Map<String, dynamic>.from(strokeData);
    compressed['points'] = _compressPoints(
      List<Map<String, dynamic>>.from(
        points.map(
          (p) =>
              p is Map<String, dynamic>
                  ? p
                  : Map<String, dynamic>.from(p as Map),
        ),
      ),
    );
    compressed['_tt_v'] = 1; // Versione formato compresso

    return compressed;
  }

  /// Compress la list of punti con delta + quantizzazione + RLE
  static Map<String, dynamic> _compressPoints(
    List<Map<String, dynamic>> points,
  ) {
    if (points.isEmpty) return {'n': 0};

    final n = points.length;

    // Arrays per delta encoding (fixed-point integers to avoid float drift)
    final dxDeltas = List<int>.filled(n, 0);
    final dyDeltas = List<int>.filled(n, 0);
    final tsDeltas = List<int>.filled(n, 0);

    // Arrays per RLE candidates
    final pressures = List<double>.filled(n, 0.0);
    final tiltXs = <double>[];
    final tiltYs = <double>[];
    final orientations = <double>[];
    bool hasTilt = false;
    bool hasOrientation = false;

    // Primo punto: valori assoluti (anchor)
    int prevX = _quantizeCoord((points[0]['x'] as num).toDouble());
    int prevY = _quantizeCoord((points[0]['y'] as num).toDouble());
    int prevTs = points[0]['timestamp'] as int;

    dxDeltas[0] = prevX; // Anchor assoluto
    dyDeltas[0] = prevY;
    tsDeltas[0] = prevTs;
    pressures[0] = _round2((points[0]['pressure'] as num).toDouble());

    if (points[0]['tiltX'] != null) {
      hasTilt = true;
      tiltXs.add(_round2((points[0]['tiltX'] as num).toDouble()));
      tiltYs.add(_round2((points[0]['tiltY'] as num?)?.toDouble() ?? 0.0));
    }
    if (points[0]['orientation'] != null) {
      hasOrientation = true;
      orientations.add(_round2((points[0]['orientation'] as num).toDouble()));
    }

    // Delta encoding: punto[i] = punto[i] - punto[i-1]
    for (int i = 1; i < n; i++) {
      final curX = _quantizeCoord((points[i]['x'] as num).toDouble());
      final curY = _quantizeCoord((points[i]['y'] as num).toDouble());
      final curTs = points[i]['timestamp'] as int;

      dxDeltas[i] = curX - prevX;
      dyDeltas[i] = curY - prevY;
      tsDeltas[i] = curTs - prevTs;

      prevX = curX;
      prevY = curY;
      prevTs = curTs;

      pressures[i] = _round2((points[i]['pressure'] as num).toDouble());

      if (hasTilt) {
        tiltXs.add(_round2((points[i]['tiltX'] as num?)?.toDouble() ?? 0.0));
        tiltYs.add(_round2((points[i]['tiltY'] as num?)?.toDouble() ?? 0.0));
      }
      if (hasOrientation) {
        orientations.add(
          _round2((points[i]['orientation'] as num?)?.toDouble() ?? 0.0),
        );
      }
    }

    // Buildi output compresso
    final result = <String, dynamic>{
      'n': n,
      'dx': dxDeltas, // Delta-encoded integers (fixed-point)
      'dy': dyDeltas,
      'dt': tsDeltas, // Delta-encoded timestamps
      'pr': _rleEncode(pressures), // RLE su pressione
    };

    if (hasTilt) {
      result['tx'] = _rleEncode(tiltXs);
      result['ty'] = _rleEncode(tiltYs);
    }
    if (hasOrientation) {
      result['or'] = _rleEncode(orientations);
    }

    return result;
  }

  // ============================================================================
  // 📤 DECOMPRESSIONE
  // ============================================================================

  /// Decomprime elementData per eventi di tipo strokeAdded
  ///
  /// Ricostruisce il JSON originale of the stroke dai dati compressi.
  /// If i dati non sono compressi (no _tt_v), li restituisce invariati.
  static Map<String, dynamic> decompressStrokeData(
    Map<String, dynamic> strokeData,
  ) {
    if (strokeData['_tt_v'] == null) return strokeData; // Do not compresso

    final compressedPoints = strokeData['points'];
    if (compressedPoints == null || compressedPoints is! Map) {
      return strokeData;
    }

    final decompressed = Map<String, dynamic>.from(strokeData);
    decompressed['points'] = _decompressPoints(
      Map<String, dynamic>.from(compressedPoints),
    );
    decompressed.remove('_tt_v');

    return decompressed;
  }

  /// Ricostruisce la list of punti da formato compresso
  static List<Map<String, dynamic>> _decompressPoints(
    Map<String, dynamic> compressed,
  ) {
    final n = compressed['n'] as int;
    if (n == 0) return [];

    final dxDeltas = List<int>.from(compressed['dx'] as List);
    final dyDeltas = List<int>.from(compressed['dy'] as List);
    final tsDeltas = List<int>.from(compressed['dt'] as List);
    final pressures = _rleDecode(compressed['pr'] as List, n);

    final hasTilt = compressed.containsKey('tx');
    final hasOrientation = compressed.containsKey('or');

    List<double>? tiltXs;
    List<double>? tiltYs;
    List<double>? orientationList;

    if (hasTilt) {
      tiltXs = _rleDecode(compressed['tx'] as List, n);
      tiltYs = _rleDecode(compressed['ty'] as List, n);
    }
    if (hasOrientation) {
      orientationList = _rleDecode(compressed['or'] as List, n);
    }

    // Rebuild coordinate assolute da delta
    final points = <Map<String, dynamic>>[];
    int curX = 0;
    int curY = 0;
    int curTs = 0;

    for (int i = 0; i < n; i++) {
      if (i == 0) {
        curX = dxDeltas[0]; // Anchor assoluto
        curY = dyDeltas[0];
        curTs = tsDeltas[0];
      } else {
        curX += dxDeltas[i];
        curY += dyDeltas[i];
        curTs += tsDeltas[i];
      }

      final point = <String, dynamic>{
        'x': curX / _coordScale,
        'y': curY / _coordScale,
        'pressure': pressures[i],
        'timestamp': curTs,
      };

      if (hasTilt && tiltXs![i] != 0.0) {
        point['tiltX'] = tiltXs[i];
      }
      if (hasTilt && tiltYs![i] != 0.0) {
        point['tiltY'] = tiltYs[i];
      }
      if (hasOrientation && orientationList![i] != 0.0) {
        point['orientation'] = orientationList[i];
      }

      points.add(point);
    }

    return points;
  }

  // ============================================================================
  // 🔧 UTILITY
  // ============================================================================

  /// Quantizza coordinata a fixed-point integer
  /// 412.3456 → 4123 (with scale=10, i.e. 1 decimal)
  static int _quantizeCoord(double value) => (value * _coordScale).round();

  /// Round to 2 decimals (for pressure/tilt/orientation)
  static double _round2(double value) => (value * 100).roundToDouble() / 100;

  /// RLE encode: [0.5, 0.5, 0.5, 0.7, 0.7] → [0.5, 3, 0.7, 2]
  ///
  /// If la run is < _rleThreshold, i valori vengono lasciati esplicitamente.
  /// This evita overhead per sequenze brevi dove RLE peggiora.
  static List<dynamic> _rleEncode(List<double> values) {
    if (values.isEmpty) return [];

    final result = <dynamic>[];
    double current = values[0];
    int count = 1;

    for (int i = 1; i < values.length; i++) {
      if (values[i] == current) {
        count++;
      } else {
        _emitRle(result, current, count);
        current = values[i];
        count = 1;
      }
    }
    _emitRle(result, current, count);

    return result;
  }

  /// Emits an RLE segment in the result
  static void _emitRle(List<dynamic> result, double value, int count) {
    if (count >= _rleThreshold) {
      // RLE marker: valore negativo speciale per count
      // Formato: [value, -count] (il segno negativo distingue da valori reali
      // because pressure and tilt are always ≥ 0)
      result.add(value);
      result.add(-count);
    } else {
      // Sotto la soglia, espandi (RLE avrebbe overhead)
      for (int i = 0; i < count; i++) {
        result.add(value);
      }
    }
  }

  /// RLE decode: [0.5, -3, 0.7, -2] → [0.5, 0.5, 0.5, 0.7, 0.7]
  static List<double> _rleDecode(List<dynamic> encoded, int expectedLength) {
    final result = <double>[];

    int i = 0;
    while (i < encoded.length) {
      final value = (encoded[i] as num).toDouble();
      i++;

      if (i < encoded.length &&
          encoded[i] is num &&
          (encoded[i] as num).toDouble() < 0) {
        // RLE: valore seguito da -count
        final count = -(encoded[i] as num).toInt();
        for (int j = 0; j < count; j++) {
          result.add(value);
        }
        i++;
      } else {
        // Valore singolo (non-RLE)
        result.add(value);
      }
    }

    // Safety: pad o tronca se necessario (non dovrebbe mai servire)
    while (result.length < expectedLength) {
      result.add(result.isEmpty ? 0.0 : result.last);
    }

    return result.sublist(0, math.min(result.length, expectedLength));
  }

  // ============================================================================
  // 📊 GENERIC COMPRESSION FOR ALL ELEMENT TYPES
  // ============================================================================

  /// Compress elementData for any Time Travel event type
  ///
  /// Only strokes benefit from advanced optimizations.
  /// For other types (shape, text, image), the data is already compact.
  static Map<String, dynamic>? compressElementData(
    String deltaType,
    Map<String, dynamic>? data,
  ) {
    if (data == null) return null;

    // Only strokes have points[] that benefit from compression
    if (deltaType == 'strokeAdded' && data.containsKey('points')) {
      return compressStrokeData(data);
    }

    return data; // Altri tipi: passa invariato
  }

  /// Decomprime elementData per qualsiasi tipo
  static Map<String, dynamic>? decompressElementData(
    String deltaType,
    Map<String, dynamic>? data,
  ) {
    if (data == null) return null;

    if (data.containsKey('_tt_v')) {
      return decompressStrokeData(data);
    }

    return data;
  }
}
