/// 🎨 STYLE COHERENCE ENGINE — L4 Intelligence Subsystem
///
/// Learns the user's visual style *per document* and pre-configures tool
/// defaults accordingly. When the user switches back to a tool, the
/// engine recommends the colors and stroke widths they were using before,
/// so new elements match the document's visual language without manual
/// re-configuration.
///
/// ## What It Tracks
///
/// - **Per-tool color usage**: frequency map with temporal decay
/// - **Per-tool stroke width**: running average per tool
/// - **Per-tool opacity**: running average per tool
/// - **Recent colors**: ordered list of last unique colors used
/// - **Document palette**: top colors across all tools, recomputed on idle
///
/// ## What It Recommends
///
/// - `recommendedColor(tool)` → most-used color for that tool
/// - `recommendedStrokeWidth(tool)` → average width for that tool
/// - `recommendedOpacity(tool)` → average opacity for that tool
/// - `documentPalette` → top 5 document colors by frequency
/// - `recentColors` → last 8 unique colors used (chronological)
///
/// ## Polish Features
///
/// - **Per-document persistence**: profiles keyed by canvas ID
/// - **Temporal decay**: older color usage decays by 0.9× on each idle
/// - **Manual-change guard**: won't auto-apply if user explicitly changed
///   color/width in the current session
/// - **EventBus**: emits [StyleRecommendationEvent] on tool switch
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import '../utils/safe_path_provider.dart';

import '../core/conscious_architecture.dart';
import '../core/engine_event.dart';
import '../core/engine_event_bus.dart';

// =============================================================================
// Per-Tool Style Profile
// =============================================================================

/// Tracks color, stroke width, and opacity usage for a single tool.
///
/// Color frequencies support temporal decay: calling [applyDecay] multiplies
/// all counts by [decayFactor] so older usage weighs less over time.
class ToolStyleProfile {
  /// Color → usage count (may be fractional after decay).
  final Map<int, double> _colorFrequency = {};

  /// Running total of stroke widths for averaging.
  double _strokeWidthSum = 0;

  /// Number of stroke width samples.
  int _strokeWidthCount = 0;

  /// Running total of opacity values for averaging.
  double _opacitySum = 0;

  /// Number of opacity samples.
  int _opacityCount = 0;

  /// Record a style usage event.
  void record({Color? color, double? strokeWidth, double? opacity}) {
    if (color != null) {
      _colorFrequency[color.toARGB32()] =
          (_colorFrequency[color.toARGB32()] ?? 0) + 1;
    }
    if (strokeWidth != null && strokeWidth > 0) {
      _strokeWidthSum += strokeWidth;
      _strokeWidthCount++;
    }
    if (opacity != null && opacity > 0 && opacity <= 1.0) {
      _opacitySum += opacity;
      _opacityCount++;
    }
  }

  /// Apply temporal decay: multiply all color frequencies by [factor].
  ///
  /// Colors whose decayed count drops below [threshold] are pruned entirely.
  void applyDecay({double factor = 0.9, double threshold = 0.5}) {
    final toRemove = <int>[];
    for (final key in _colorFrequency.keys) {
      final decayed = _colorFrequency[key]! * factor;
      if (decayed < threshold) {
        toRemove.add(key);
      } else {
        _colorFrequency[key] = decayed;
      }
    }
    for (final key in toRemove) {
      _colorFrequency.remove(key);
    }
  }

  /// Most-used color for this tool, or null if no colors recorded.
  Color? get dominantColor {
    if (_colorFrequency.isEmpty) return null;
    final best = _colorFrequency.entries.reduce(
      (a, b) => a.value > b.value ? a : b,
    );
    return Color(best.key);
  }

  /// Average stroke width for this tool, or null if none recorded.
  double? get averageStrokeWidth {
    if (_strokeWidthCount == 0) return null;
    return _strokeWidthSum / _strokeWidthCount;
  }

  /// Average opacity for this tool, or null if none recorded.
  double? get averageOpacity {
    if (_opacityCount == 0) return null;
    return _opacitySum / _opacityCount;
  }

  /// All tracked colors with their frequencies (for palette extraction).
  Map<int, double> get colorFrequency => Map.unmodifiable(_colorFrequency);

  /// Total color sample count (may be fractional after decay).
  double get totalColorSamples =>
      _colorFrequency.values.fold(0.0, (sum, v) => sum + v);

  /// Total number of stroke width recordings.
  int get totalStrokeWidthSamples => _strokeWidthCount;

  Map<String, dynamic> toJson() => {
    'dominantColor': dominantColor?.toARGB32(),
    'averageStrokeWidth': averageStrokeWidth,
    'averageOpacity': averageOpacity,
    'totalColorSamples': totalColorSamples,
    'totalStrokeWidthSamples': totalStrokeWidthSamples,
    'uniqueColors': _colorFrequency.length,
  };

  /// Restore from serialized counters.
  void _fromCountersMap(Map<String, dynamic> data) {
    final colors = data['colors'];
    if (colors is Map) {
      for (final entry in colors.entries) {
        final key = int.tryParse(entry.key.toString());
        final val = (entry.value as num?)?.toDouble() ?? 0;
        if (key != null) {
          _colorFrequency[key] = (_colorFrequency[key] ?? 0) + val;
        }
      }
    }
    _strokeWidthSum += (data['swSum'] as num?)?.toDouble() ?? 0;
    _strokeWidthCount += (data['swCount'] as int?) ?? 0;
    _opacitySum += (data['opSum'] as num?)?.toDouble() ?? 0;
    _opacityCount += (data['opCount'] as int?) ?? 0;
  }

  /// Serialize to a compact map for persistence.
  Map<String, dynamic> _toCountersMap() => {
    'colors': {
      for (final e in _colorFrequency.entries) e.key.toString(): e.value,
    },
    'swSum': _strokeWidthSum,
    'swCount': _strokeWidthCount,
    'opSum': _opacitySum,
    'opCount': _opacityCount,
  };
}

// =============================================================================
// Style Coherence Engine
// =============================================================================

/// L4 Intelligence: per-document style learning and recommendation.
///
/// Call [recordStyleUsage] whenever the user creates or modifies an element.
/// Query [recommendedColor], [recommendedStrokeWidth], [recommendedOpacity],
/// or [documentPalette] to get intelligent defaults.
class StyleCoherenceEngine extends IntelligenceSubsystem {
  @override
  IntelligenceLayer get layer => IntelligenceLayer.generative;

  @override
  String get name => 'StyleCoherence';

  bool _active = true;

  @override
  bool get isActive => _active;

  // ─────────────────────────────────────────────────────────────────────────
  // Per-Tool Profiles
  // ─────────────────────────────────────────────────────────────────────────

  final Map<String, ToolStyleProfile> _profiles = {};

  /// Maximum number of colors in the document palette.
  static const int maxPaletteSize = 5;

  /// Maximum number of recent colors tracked.
  static const int maxRecentColors = 8;

  /// Temporal decay factor applied each idle cycle (0–1).
  /// 0.9 means old data retains 90% weight per cycle.
  static const double decayFactor = 0.9;

  /// Minimum frequency threshold — colors below this after decay are pruned.
  static const double decayThreshold = 0.5;

  /// Access or lazily create a profile for [tool].
  ToolStyleProfile _profileFor(String tool) =>
      _profiles.putIfAbsent(tool, ToolStyleProfile.new);

  // ─────────────────────────────────────────────────────────────────────────
  // Per-Document Identity
  // ─────────────────────────────────────────────────────────────────────────

  /// The current canvas/document ID. Set by the canvas wiring layer.
  /// Persistence is keyed by this ID so each document has its own style.
  String? _canvasId;

  /// Set the canvas ID for per-document persistence.
  void setCanvasId(String id) => _canvasId = id;

  /// Current canvas ID (for diagnostics / testing).
  String? get canvasId => _canvasId;

  // ─────────────────────────────────────────────────────────────────────────
  // Manual-Change Guard
  // ─────────────────────────────────────────────────────────────────────────

  /// Set of tool names where the user has explicitly changed the style
  /// in the current session. Auto-apply is suppressed for these tools.
  final Set<String> _manualOverrides = {};

  /// Mark that the user explicitly changed the style for the current tool.
  /// Call from the toolbar when the user manually picks a color, width,
  /// or opacity to prevent the engine from overriding their choice.
  void markManualOverride(String tool) => _manualOverrides.add(tool);

  /// Clear manual override for a tool (e.g., when a new session starts).
  void clearManualOverride(String tool) => _manualOverrides.remove(tool);

  /// Clear all manual overrides (e.g., on canvas close/reopen).
  void clearAllManualOverrides() => _manualOverrides.clear();

  /// Whether auto-apply is suppressed for this tool.
  bool hasManualOverride(String tool) => _manualOverrides.contains(tool);

  // ─────────────────────────────────────────────────────────────────────────
  // Recording
  // ─────────────────────────────────────────────────────────────────────────

  /// Record a style usage event for [tool].
  void recordStyleUsage(
    String tool, {
    Color? color,
    double? strokeWidth,
    double? opacity,
  }) {
    _profileFor(
      tool,
    ).record(color: color, strokeWidth: strokeWidth, opacity: opacity);
    _paletteDirty = true;

    // Track recent colors (most-recent first, deduped).
    if (color != null) {
      _recentColors.remove(color.toARGB32());
      _recentColors.insert(0, color.toARGB32());
      if (_recentColors.length > maxRecentColors) {
        _recentColors.removeLast();
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Recommendations
  // ─────────────────────────────────────────────────────────────────────────

  /// Recommended color for [tool].
  Color? recommendedColor(String tool) => _profiles[tool]?.dominantColor;

  /// Recommended stroke width for [tool].
  double? recommendedStrokeWidth(String tool) =>
      _profiles[tool]?.averageStrokeWidth;

  /// Recommended opacity for [tool].
  double? recommendedOpacity(String tool) => _profiles[tool]?.averageOpacity;

  /// Document palette: top [maxPaletteSize] colors by frequency.
  List<Color> get documentPalette => List.unmodifiable(_documentPalette);

  /// Last [maxRecentColors] unique colors used, most-recent first.
  List<Color> get recentColors =>
      _recentColors.map((v) => Color(v)).toList(growable: false);

  /// All tools that have recorded style data.
  List<String> get trackedTools => List.unmodifiable(_profiles.keys);

  // ─── Palette computation ───

  List<Color> _documentPalette = [];
  final List<int> _recentColors = [];
  bool _paletteDirty = true;

  void _recomputePalette() {
    if (!_paletteDirty) return;
    _paletteDirty = false;

    // Merge color frequencies across all tools.
    final merged = <int, double>{};
    for (final profile in _profiles.values) {
      for (final entry in profile.colorFrequency.entries) {
        merged[entry.key] = (merged[entry.key] ?? 0) + entry.value;
      }
    }

    if (merged.isEmpty) {
      _documentPalette = [];
      return;
    }

    // Sort by frequency descending, take top N.
    final sorted =
        merged.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    _documentPalette =
        sorted.take(maxPaletteSize).map((e) => Color(e.key)).toList();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────

  /// Last observed tool — used to detect tool switches.
  String? _lastTool;

  /// Number of idle cycles since last decay. Decay runs every ~5 cycles
  /// to avoid over-decaying on rapid idle calls.
  int _idleCyclesSinceDecay = 0;

  /// Callback invoked when the engine detects a tool switch and has
  /// recommendations for the new tool. Set by the canvas wiring layer.
  ///
  /// **Guard**: will NOT fire if [hasManualOverride] is true for that tool.
  void Function(Color? color, double? strokeWidth, double? opacity)?
  onToolSwitchRecommendation;

  /// Optional [EngineEventBus] for broadcasting [StyleRecommendationEvent].
  /// Set by the canvas wiring layer.
  EngineEventBus? eventBus;

  @override
  void onContextChanged(EngineContext context) {
    if (context.activeTool != null && context.activeTool != _lastTool) {
      final newTool = context.activeTool!;
      _lastTool = newTool;

      // Guard: skip if user manually overrode this tool's style.
      if (_manualOverrides.contains(newTool)) return;

      // Fire recommendation callback on tool switch.
      if (_profiles.containsKey(newTool)) {
        final color = recommendedColor(newTool);
        final width = recommendedStrokeWidth(newTool);
        final opacity = recommendedOpacity(newTool);

        onToolSwitchRecommendation?.call(color, width, opacity);

        // Emit EventBus event.
        eventBus?.emit(
          StyleRecommendationEvent(
            tool: newTool,
            color: color,
            strokeWidth: width,
            opacity: opacity,
          ),
        );
      }
    }
  }

  @override
  void onIdle(Duration idleDuration) {
    if (idleDuration.inMilliseconds > 200) {
      _recomputePalette();

      // Apply temporal decay every 5 idle cycles.
      _idleCyclesSinceDecay++;
      if (_idleCyclesSinceDecay >= 5) {
        _idleCyclesSinceDecay = 0;
        for (final profile in _profiles.values) {
          profile.applyDecay(factor: decayFactor, threshold: decayThreshold);
        }
        _paletteDirty = true; // Frequencies changed, recompute next time.
      }
    }
  }

  @override
  void dispose() {
    _active = false;
    _profiles.clear();
    _documentPalette = [];
    _recentColors.clear();
    _manualOverrides.clear();
    onToolSwitchRecommendation = null;
    eventBus = null;
    _canvasId = null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Persistence — per-document, keyed by canvasId
  // ─────────────────────────────────────────────────────────────────────────

  static const String _prefsDirName = 'style_coherence';

  /// Compute the file path for the current document's style data.
  Future<File?> _prefsFile() async {
    final dir = await getSafeAppSupportDirectory();
    if (dir == null) return null; // Web: no filesystem
    final subdir = Directory('${dir.path}/$_prefsDirName');
    if (!await subdir.exists()) await subdir.create(recursive: true);
    // Use canvasId if available, or a default for global fallback.
    final key = _canvasId ?? '_global';
    // Sanitize key for filesystem safety.
    final safe = key.replaceAll(RegExp(r'[^\w\-.]'), '_');
    return File('${subdir.path}/$safe.json');
  }

  /// Save the current profiles + recent colors to a per-document JSON file.
  Future<void> saveToPrefs() async {
    try {
      final file = await _prefsFile();
      if (file == null) return; // Web: no filesystem
      final data = <String, dynamic>{
        'profiles': {
          for (final e in _profiles.entries) e.key: e.value._toCountersMap(),
        },
        'recentColors': _recentColors,
        'savedAt': DateTime.now().toIso8601String(),
      };
      await file.writeAsString(jsonEncode(data));
    } catch (_) {
      // Best-effort — non-critical.
    }
  }

  /// Restore profiles + recent colors from the per-document JSON file.
  Future<void> restoreFromPrefs() async {
    try {
      final file = await _prefsFile();
      if (file == null) return; // Web: no filesystem
      if (await file.exists()) {
        final raw = await file.readAsString();
        final data = jsonDecode(raw) as Map<String, dynamic>;

        // Restore profiles.
        final profiles = data['profiles'];
        if (profiles is Map) {
          for (final entry in profiles.entries) {
            final tool = entry.key as String;
            final counters = entry.value as Map<String, dynamic>;
            _profileFor(tool)._fromCountersMap(counters);
          }
        }

        // Restore recent colors.
        final recent = data['recentColors'];
        if (recent is List) {
          _recentColors.clear();
          for (final v in recent) {
            if (v is int) _recentColors.add(v);
          }
        }

        _paletteDirty = true;
      }
    } catch (_) {
      // Best-effort — non-critical.
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Diagnostics
  // ─────────────────────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
    'canvasId': _canvasId,
    'trackedTools': _profiles.keys.toList(),
    'paletteSize': _documentPalette.length,
    'recentColorCount': _recentColors.length,
    'manualOverrides': _manualOverrides.toList(),
    'documentPalette':
        _documentPalette
            .map((c) => '0x${c.toARGB32().toRadixString(16).padLeft(8, '0')}')
            .toList(),
    'profiles': {
      for (final entry in _profiles.entries) entry.key: entry.value.toJson(),
    },
  };
}

// =============================================================================
// EventBus Event
// =============================================================================

/// Emitted by [StyleCoherenceEngine] when a tool switch triggers a
/// style recommendation. Other subsystems (debug overlay, etc.) can
/// listen for this event.
class StyleRecommendationEvent extends EngineEvent {
  /// Tool that the recommendation is for.
  final String tool;

  /// Recommended color (null if no data).
  final Color? color;

  /// Recommended stroke width (null if no data).
  final double? strokeWidth;

  /// Recommended opacity (null if no data).
  final double? opacity;

  StyleRecommendationEvent({
    required this.tool,
    this.color,
    this.strokeWidth,
    this.opacity,
  }) : super(source: 'StyleCoherence', domain: EventDomain.intelligence);
}
