import 'dart:math' as math;
import 'package:flutter/painting.dart';
import './content_cluster.dart';
import './knowledge_connection.dart';
import '../drawing/models/pro_drawing_point.dart';

/// 💡 SUGGESTED CONNECTION — A machine-discovered relationship between clusters.
///
/// The engine scores every cluster pair on 5 weighted signals and surfaces
/// the top suggestions as ghost connections the user can accept or dismiss.
class SuggestedConnection {
  /// Source cluster ID.
  final String sourceClusterId;

  /// Target cluster ID.
  final String targetClusterId;

  /// Similarity score (0.0–1.0). Higher = stronger suggestion.
  final double score;

  /// Human-readable reason for the suggestion.
  /// Mutable — AI ghost labels can replace generic reasons (e.g.,
  /// "Nearby notes" → "Legge fondamentale").
  String reason;

  /// Shared keywords between source and target (for semantic suggestions).
  /// Used to auto-populate connection labels on accept.
  final List<String> sharedKeywords;

  /// Whether the user has dismissed this suggestion.
  bool dismissed;

  /// Timestamp when this suggestion was first surfaced (ms since epoch).
  /// Used for confidence decay — suggestions fade after 30s without interaction.
  int surfacedAtMs;

  SuggestedConnection({
    required this.sourceClusterId,
    required this.targetClusterId,
    required this.score,
    required this.reason,
    this.sharedKeywords = const [],
    this.dismissed = false,
    int? surfacedAt,
  }) : surfacedAtMs = surfacedAt ?? DateTime.now().millisecondsSinceEpoch;

  /// Canonical pair key — order-independent so A↔B == B↔A.
  String get pairKey {
    final a = sourceClusterId.compareTo(targetClusterId) < 0
        ? sourceClusterId
        : targetClusterId;
    final b = a == sourceClusterId ? targetClusterId : sourceClusterId;
    return '$a|$b';
  }

  @override
  String toString() =>
      'SuggestedConnection($sourceClusterId → $targetClusterId, '
      'score: ${score.toStringAsFixed(2)}, reason: $reason)';
}

/// 🧠 CONNECTION SUGGESTION ENGINE — Discovers relationships between clusters.
///
/// Pure scoring engine with no Flutter dependency. Computes a weighted
/// similarity score for every cluster pair using 5 signals:
///
///   1. Spatial proximity (35%) — inverse centroid distance
///   2. Ink color overlap (25%) — HSL distance of dominant stroke colors
///   3. Temporal proximity (15%) — creation time overlap
///   4. Size similarity (10%) — bounding box area ratio
///   5. Type match (15%) — bonus for same element types
///
/// Only pairs above the threshold are returned, capped at maxSuggestions.
class ConnectionSuggestionEngine {
  // Signal weights (adaptable via learning) — 6 signals, sum = 1.0
  double _wSpatial = 0.28;
  double _wColor = 0.18;
  double _wSemantic = 0.20;
  double _wTemporal = 0.12;
  double _wSize = 0.08;
  double _wType = 0.14;

  // 🧠 LEARNING: Current weights (read-only for testing)
  double get wSpatial => _wSpatial;
  double get wColor => _wColor;
  double get wSemantic => _wSemantic;
  double get wTemporal => _wTemporal;
  double get wSize => _wSize;
  double get wType => _wType;

  /// 🧠 LEARNING: Reinforce the strongest signal when suggestion is accepted.
  void reinforceAccept(String reason) {
    _adjustWeight(reason, 0.02);
  }

  /// 🧠 LEARNING: Penalize the strongest signal when suggestion is dismissed.
  void reinforceDismiss(String reason) {
    _adjustWeight(reason, -0.02);
  }

  void _adjustWeight(String reason, double delta) {
    switch (reason) {
      case 'Nearby notes': _wSpatial = (_wSpatial + delta).clamp(0.05, 0.60); break;
      case 'Similar colors': _wColor = (_wColor + delta).clamp(0.05, 0.60); break;
      case 'Related content': _wSemantic = (_wSemantic + delta).clamp(0.05, 0.60); break;
      case 'Written together': _wTemporal = (_wTemporal + delta).clamp(0.05, 0.60); break;
      case 'Similar size': _wSize = (_wSize + delta).clamp(0.05, 0.60); break;
      case 'Same type': _wType = (_wType + delta).clamp(0.05, 0.60); break;
    }
    // Renormalize to sum = 1.0
    final sum = _wSpatial + _wColor + _wSemantic + _wTemporal + _wSize + _wType;
    if (sum > 0) {
      _wSpatial /= sum;
      _wColor /= sum;
      _wSemantic /= sum;
      _wTemporal /= sum;
      _wSize /= sum;
      _wType /= sum;
    }
  }

  // Stopwords for keyword extraction (common words that don't carry meaning)
  static const _stopwords = <String>{
    'the', 'a', 'an', 'is', 'are', 'was', 'were', 'be', 'been', 'being',
    'have', 'has', 'had', 'do', 'does', 'did', 'will', 'would', 'could',
    'should', 'may', 'might', 'can', 'shall', 'to', 'of', 'in', 'for',
    'on', 'with', 'at', 'by', 'from', 'as', 'into', 'about', 'between',
    'through', 'after', 'before', 'above', 'below', 'and', 'but', 'or',
    'not', 'no', 'nor', 'so', 'yet', 'both', 'each', 'this', 'that',
    'these', 'those', 'it', 'its', 'he', 'she', 'they', 'we', 'you',
    'i', 'me', 'my', 'your', 'his', 'her', 'our', 'their',
    // Italian common stopwords
    'il', 'lo', 'la', 'le', 'gli', 'un', 'una', 'uno', 'di', 'da',
    'del', 'della', 'dei', 'delle', 'nel', 'nella', 'con', 'su', 'per',
    'tra', 'fra', 'che', 'non', 'si', 'è', 'sono', 'ha', 'ho',
  };

  /// Compute connection suggestions between clusters.
  ///
  /// [allStrokes] provides color + timestamp data for ink-based signals.
  /// [existingConnections] are excluded from suggestions.
  /// Returns suggestions sorted by score (descending), capped at [maxSuggestions].
  List<SuggestedConnection> computeSuggestions({
    required List<ContentCluster> clusters,
    required List<ProStroke> allStrokes,
    required List<KnowledgeConnection> existingConnections,
    Map<String, String>? clusterTexts,
    double threshold = 0.42,
    int maxSuggestions = 2,
  }) {
    if (clusters.length < 2) return [];

    // Build stroke lookup: strokeId → ProStroke
    final strokeMap = <String, ProStroke>{};
    for (final s in allStrokes) {
      strokeMap[s.id] = s;
    }

    // Build set of existing connections (order-independent)
    final existingPairs = <String>{};
    for (final conn in existingConnections) {
      final a = conn.sourceClusterId.compareTo(conn.targetClusterId) < 0
          ? conn.sourceClusterId
          : conn.targetClusterId;
      final b = a == conn.sourceClusterId
          ? conn.targetClusterId
          : conn.sourceClusterId;
      existingPairs.add('$a|$b');
    }

    // Pre-compute cluster metadata for efficient pairwise scoring
    final metas = <String, _ClusterMeta>{};
    double maxDist = 1.0;

    for (final c in clusters) {
      if (c.elementCount < 1) continue;
      metas[c.id] = _extractMeta(c, strokeMap, clusterTexts?[c.id]);
    }

    // Compute max centroid distance for normalization
    final ids = metas.keys.toList();

    // 🚀 SPATIAL GRID: For >50 clusters, use grid-based early rejection
    // to skip pairs too far apart (only compute full 5-signal score for
    // clusters within 40% of max distance)
    Set<String>? nearbyPairs;
    if (ids.length > 50) {
      // Find bounding box of all centroids
      double minX = double.infinity, maxX = double.negativeInfinity;
      double minY = double.infinity, maxY = double.negativeInfinity;
      for (final id in ids) {
        final c = metas[id]!.centroid;
        if (c.dx < minX) minX = c.dx;
        if (c.dx > maxX) maxX = c.dx;
        if (c.dy < minY) minY = c.dy;
        if (c.dy > maxY) maxY = c.dy;
      }
      final rangeX = maxX - minX;
      final rangeY = maxY - minY;
      final cellSize = math.max(rangeX, rangeY) * 0.2; // 5x5 grid
      if (cellSize > 0) {
        final grid = <int, List<String>>{};
        for (final id in ids) {
          final c = metas[id]!.centroid;
          final gx = ((c.dx - minX) / cellSize).floor();
          final gy = ((c.dy - minY) / cellSize).floor();
          final key = gx * 1000 + gy;
          grid.putIfAbsent(key, () => []).add(id);
        }
        nearbyPairs = <String>{};
        for (final entry in grid.entries) {
          final gx = entry.key ~/ 1000;
          final gy = entry.key % 1000;
          // Check this cell + 8 neighbors
          for (int dx = -1; dx <= 1; dx++) {
            for (int dy = -1; dy <= 1; dy++) {
              final neighborKey = (gx + dx) * 1000 + (gy + dy);
              final neighbors = grid[neighborKey];
              if (neighbors == null) continue;
              for (final a in entry.value) {
                for (final b in neighbors) {
                  if (a.compareTo(b) < 0) nearbyPairs.add('$a|$b');
                }
              }
            }
          }
        }
      }
    }

    for (int i = 0; i < ids.length; i++) {
      for (int j = i + 1; j < ids.length; j++) {
        final dx = metas[ids[i]]!.centroid.dx - metas[ids[j]]!.centroid.dx;
        final dy = metas[ids[i]]!.centroid.dy - metas[ids[j]]!.centroid.dy;
        final dist = math.sqrt(dx * dx + dy * dy);
        if (dist > maxDist) maxDist = dist;
      }
    }

    // Score all pairs
    final candidates = <SuggestedConnection>[];

    for (int i = 0; i < ids.length; i++) {
      for (int j = i + 1; j < ids.length; j++) {
        final idA = ids[i];
        final idB = ids[j];

        // Skip already-connected pairs
        final pairKey = idA.compareTo(idB) < 0 ? '$idA|$idB' : '$idB|$idA';
        if (existingPairs.contains(pairKey)) continue;

        // 🚀 SPATIAL GRID: Skip far-apart pairs
        if (nearbyPairs != null && !nearbyPairs.contains(pairKey)) continue;

        final metaA = metas[idA]!;
        final metaB = metas[idB]!;

        // === Signal 1: Spatial proximity (closer = higher) ===
        final dx = metaA.centroid.dx - metaB.centroid.dx;
        final dy = metaA.centroid.dy - metaB.centroid.dy;
        final dist = math.sqrt(dx * dx + dy * dy);
        final spatialScore = 1.0 - (dist / maxDist).clamp(0.0, 1.0);

        // === Signal 2: Ink color overlap (similar hue = higher) ===
        final colorScore = _colorSimilarity(metaA.dominantColor, metaB.dominantColor);

        // === Signal 3: Temporal proximity (written close in time = higher) ===
        final temporalScore = _temporalSimilarity(metaA.timestamps, metaB.timestamps);

        // === Signal 4: Size similarity (similar area = higher) ===
        final sizeScore = _sizeSimilarity(metaA.area, metaB.area);

        // === Signal 5: Type match (same element types = bonus) ===
        final typeScore = _typeSimilarity(metaA.types, metaB.types);

        // === Signal 6: Semantic similarity (shared keywords in recognized text) ===
        final semanticScore = _semanticSimilarity(
          metaA.recognizedText, metaB.recognizedText,
        );

        // Weighted sum (using adaptive 6-signal weights)
        final total = _wSpatial * spatialScore +
            _wColor * colorScore +
            _wSemantic * semanticScore +
            _wTemporal * temporalScore +
            _wSize * sizeScore +
            _wType * typeScore;

        if (total >= threshold) {
          // Extract shared keywords for semantic reason label
          List<String> sharedKw = const [];
          if (metaA.recognizedText.isNotEmpty && metaB.recognizedText.isNotEmpty) {
            final kwA = _extractKeywords(metaA.recognizedText);
            final kwB = _extractKeywords(metaB.recognizedText);
            sharedKw = kwA.intersection(kwB).toList()
              ..sort((a, b) => b.length.compareTo(a.length)); // longest first
          }

          final reason = _pickReason(
            spatialScore, colorScore, semanticScore,
            temporalScore, sizeScore, typeScore,
            sharedKeywords: sharedKw,
          );

          candidates.add(SuggestedConnection(
            sourceClusterId: idA,
            targetClusterId: idB,
            score: total,
            reason: reason,
            sharedKeywords: sharedKw,
          ));
        }
      }
    }

    // Sort by score descending, cap at maxSuggestions
    candidates.sort((a, b) => b.score.compareTo(a.score));
    return candidates.take(maxSuggestions).toList();
  }

  // ===========================================================================
  // Metadata extraction
  // ===========================================================================

  _ClusterMeta _extractMeta(
    ContentCluster cluster,
    Map<String, ProStroke> strokeMap,
    String? recognizedText,
  ) {
    // Collect stroke colors and timestamps
    final colors = <Color>[];
    final timestamps = <int>[];

    for (final sid in cluster.strokeIds) {
      final stroke = strokeMap[sid];
      if (stroke != null) {
        colors.add(stroke.color);
        timestamps.add(stroke.createdAt.millisecondsSinceEpoch);
      }
    }

    // Dominant color: most frequent, or fallback
    Color dominant = const Color(0xFF64B5F6);
    if (colors.isNotEmpty) {
      // Simple: pick the color that appears most (by quantized hue)
      final hueVotes = <int, int>{};
      for (final c in colors) {
        final hsl = HSLColor.fromColor(c);
        final quantizedHue = (hsl.hue / 30).round(); // 12 hue buckets
        hueVotes[quantizedHue] = (hueVotes[quantizedHue] ?? 0) + 1;
      }
      final bestHue = hueVotes.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
      // Find a color matching the best hue bucket
      dominant = colors.firstWhere(
        (c) => (HSLColor.fromColor(c).hue / 30).round() == bestHue,
        orElse: () => colors.first,
      );
    }

    // Element types present
    final types = <String>{};
    if (cluster.strokeIds.isNotEmpty) types.add('stroke');
    if (cluster.shapeIds.isNotEmpty) types.add('shape');
    if (cluster.textIds.isNotEmpty) types.add('text');
    if (cluster.imageIds.isNotEmpty) types.add('image');

    return _ClusterMeta(
      centroid: cluster.centroid,
      area: cluster.bounds.width * cluster.bounds.height,
      dominantColor: dominant,
      timestamps: timestamps,
      types: types,
      recognizedText: recognizedText ?? '',
    );
  }

  // ===========================================================================
  // Signal scoring functions
  // ===========================================================================

  /// HSL-based color similarity (0–1). Weights: hue 60%, saturation 20%, lightness 20%.
  double _colorSimilarity(Color a, Color b) {
    final hslA = HSLColor.fromColor(a);
    final hslB = HSLColor.fromColor(b);

    // Hue distance (circular, 0–180° max)
    var hueDiff = (hslA.hue - hslB.hue).abs();
    if (hueDiff > 180) hueDiff = 360 - hueDiff;
    final hueScore = 1.0 - (hueDiff / 180.0);

    // Saturation distance
    final satScore = 1.0 - (hslA.saturation - hslB.saturation).abs();

    // Lightness distance
    final lightScore = 1.0 - (hslA.lightness - hslB.lightness).abs();

    return hueScore * 0.6 + satScore * 0.2 + lightScore * 0.2;
  }

  /// Temporal similarity: how close in time were the clusters created?
  /// Uses the median timestamp of each cluster's strokes.
  double _temporalSimilarity(List<int> tsA, List<int> tsB) {
    if (tsA.isEmpty || tsB.isEmpty) return 0.5; // Neutral for non-stroke clusters

    // Median timestamps
    final sortedA = List<int>.from(tsA)..sort();
    final sortedB = List<int>.from(tsB)..sort();
    final medA = sortedA[sortedA.length ~/ 2];
    final medB = sortedB[sortedB.length ~/ 2];

    // Time difference in minutes
    final diffMinutes = (medA - medB).abs() / 60000.0;

    // Within 1 minute = 1.0, decays over 30 minutes
    return (1.0 - (diffMinutes / 30.0)).clamp(0.0, 1.0);
  }

  /// Size similarity: ratio of bounding box areas (closer = higher).
  double _sizeSimilarity(double areaA, double areaB) {
    if (areaA <= 0 || areaB <= 0) return 0.5;
    final ratio = areaA < areaB ? areaA / areaB : areaB / areaA;
    return ratio; // 0–1, where 1 = identical size
  }

  /// Type similarity: Jaccard index of element types.
  double _typeSimilarity(Set<String> typesA, Set<String> typesB) {
    if (typesA.isEmpty && typesB.isEmpty) return 1.0;
    final intersection = typesA.intersection(typesB).length;
    final union = typesA.union(typesB).length;
    return union > 0 ? intersection / union : 0.0;
  }

  /// 🔤 SEMANTIC SIMILARITY: Keyword overlap between recognized texts.
  ///
  /// Tokenizes, lowercases, removes stopwords, then computes Jaccard
  /// similarity of word sets. Returns 0.5 (neutral) if either text is empty.
  double _semanticSimilarity(String textA, String textB) {
    if (textA.isEmpty || textB.isEmpty) return 0.5; // Neutral fallback

    // Tokenize + clean
    final wordsA = _extractKeywords(textA);
    final wordsB = _extractKeywords(textB);

    if (wordsA.isEmpty || wordsB.isEmpty) return 0.5;

    // Jaccard similarity: |A ∩ B| / |A ∪ B|
    final intersection = wordsA.intersection(wordsB);
    final union = wordsA.union(wordsB);

    if (union.isEmpty) return 0.5;

    final jaccard = intersection.length / union.length;

    // Bonus for rare shared words (>3 chars = likely meaningful)
    int rareShared = 0;
    for (final w in intersection) {
      if (w.length > 3) rareShared++;
    }
    final rareBonus = (rareShared * 0.15).clamp(0.0, 0.3);

    // 🔗 CAUSAL BOOST: If either text contains relational words,
    // boost the score — these indicate explicit connections in the content.
    double causalBonus = 0.0;
    final combined = '${textA.toLowerCase()} ${textB.toLowerCase()}';
    const causalWords = [
      'perché', 'because', 'therefore', 'dunque', 'quindi',
      'implies', 'implica', 'causes', 'causa', 'leads',
      'così', 'thus', 'hence', 'ergo', 'allora',
      'dovuto', 'due', 'results', 'produce', 'genera',
    ];
    const causalSymbols = ['→', '⇒', '∴', '⟹', '=>'];
    for (final w in causalWords) {
      if (combined.contains(w)) { causalBonus = 0.15; break; }
    }
    if (causalBonus == 0.0) {
      for (final s in causalSymbols) {
        if (combined.contains(s)) { causalBonus = 0.15; break; }
      }
    }

    return (jaccard + rareBonus + causalBonus).clamp(0.0, 1.0);
  }

  /// Extract meaningful keywords from text, with basic stemming
  /// and formula/math detection.
  Set<String> _extractKeywords(String text) {
    final keywords = text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-zA-Z0-9àèéìòùáéíóúäöüßñçšžø\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 2 && !_stopwords.contains(w))
        .map(_stem)
        .where((w) => w.length >= 2)
        .toSet();

    // 🔢 FORMULA DETECTION: If text contains math symbols,
    // tag it as "formula" / "math" / "equation" for semantic matching.
    // This way "f=ma" (recognized as "Femal") still tags as formula,
    // and "Newton" + formula cluster get a semantic boost.
    if (RegExp(r'[=+×÷∫Σ∂√²³πΔ∞≈≠≤≥∈∀∃]').hasMatch(text) ||
        RegExp(r'\d+[a-z]|[a-z]\d+|[a-z]=[a-z]', caseSensitive: false).hasMatch(text)) {
      keywords.addAll(['formula', 'math', 'equation']);
    }

    return keywords;
  }

  /// Very basic stemming — strips common suffixes for EN/IT matching.
  /// "forces"→"forc", "equations"→"equat", "gravitazione"→"gravit"
  static String _stem(String word) {
    const enSuffixes = [
      'ation', 'ition', 'ness', 'ment', 'ence', 'ance',
      'able', 'ible', 'ting', 'ing', 'ous', 'ive',
      'ful', 'ity', 'ies', 'ion', 'ers', 'est',
      'ism', 'ist', 'ual', 'ial', 'ent', 'ant',
      'ed', 'ly', 'er', 'al',
    ];
    const itSuffixes = [
      'zione', 'mente', 'ità', 'ismo', 'ista',
      'ando', 'endo', 'ante', 'ente', 'ato', 'ito',
      'osa', 'oso', 'iva', 'ivo',
    ];
    for (final s in enSuffixes) {
      if (word.length > s.length + 2 && word.endsWith(s)) {
        return word.substring(0, word.length - s.length);
      }
    }
    for (final s in itSuffixes) {
      if (word.length > s.length + 2 && word.endsWith(s)) {
        return word.substring(0, word.length - s.length);
      }
    }
    if (word.length > 3 && word.endsWith('s') && !word.endsWith('ss')) {
      return word.substring(0, word.length - 1);
    }
    return word;
  }

  /// Pick the human-readable reason from the strongest signal.
  /// When semantic wins and [sharedKeywords] exist, shows the actual keywords.
  String _pickReason(
    double spatial, double color, double semantic,
    double temporal, double size, double type, {
    List<String> sharedKeywords = const [],
  }) {
    final scores = {
      'Nearby notes': spatial,
      'Similar colors': color,
      'Related content': semantic,
      'Written together': temporal,
      'Similar size': size,
      'Same type': type,
    };
    final winner = scores.entries.reduce((a, b) => a.value >= b.value ? a : b).key;

    // When semantic wins, show actual shared keywords
    if (winner == 'Related content' && sharedKeywords.isNotEmpty) {
      final top = sharedKeywords.take(3).join(', ');
      return 'Shared: $top';
    }
    return winner;
  }
}

/// Internal metadata for efficient pairwise comparison.
class _ClusterMeta {
  final Offset centroid;
  final double area;
  final Color dominantColor;
  final List<int> timestamps;
  final Set<String> types;
  final String recognizedText;

  const _ClusterMeta({
    required this.centroid,
    required this.area,
    required this.dominantColor,
    required this.timestamps,
    required this.types,
    required this.recognizedText,
  });
}
