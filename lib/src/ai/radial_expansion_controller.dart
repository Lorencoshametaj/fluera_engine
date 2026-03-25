import 'dart:math' as math;
import 'dart:ui';

import './ai_provider.dart';
import './atlas_action.dart';
import '../core/engine_scope.dart';

// =============================================================================
// 🌟 RADIAL EXPANSION CONTROLLER v3 — Full Polish Edition
//
// New in v3:
//   - Bounce overshoot when bubble lands (scale 1.2 → 1.0 spring)
//   - 6 sub-topics in two orbits (inner 4 + outer 2, staggered)
//   - Context-aware AI prompt (includes nearby cluster texts)
//   - Auto-dismiss "collapse toward source" animation
// =============================================================================

enum RadialExpansionPhase { idle, charging, generating, presenting, cooldown }

enum GhostBubbleState { launching, bouncing, idle, dragging, confirming, dismissing, collapsing }

// ===========================================================================
// 🌟 PARTICLE + BEAM — Confirm visual effects
// ===========================================================================

class ConfirmParticle {
  Offset position;
  final Offset velocity;
  double opacity;
  final double size;
  final int colorIndex;
  ConfirmParticle({required this.position, required this.velocity, this.opacity = 1.0, required this.size, required this.colorIndex});
}

class ConfirmBeam {
  final Offset from;
  final Offset to;
  double progress; // 0→1 draw progress
  double opacity;
  ConfirmBeam({required this.from, required this.to, this.progress = 0.0, this.opacity = 1.0});
}

class GhostBubble {
  final String id;
  final String label;
  final Offset targetPosition;
  final double angle;
  final double distance;
  final double launchDelay;    // stagger seconds
  final bool isOuterOrbit;     // outer ring gets slightly different style

  double launchProgress;       // 0→1 (position)
  double opacity;
  double scale;                // 1.0 at rest, 1.2 at bounce peak
  double floatPhase;
  GhostBubbleState state;
  Offset dragOffset;

  GhostBubble({
    required this.id,
    required this.label,
    required this.targetPosition,
    required this.angle,
    required this.distance,
    this.launchDelay = 0.0,
    this.isOuterOrbit = false,
    this.launchProgress = 0.0,
    this.opacity = 0.0,
    this.scale = 1.2,
    this.floatPhase = 0.0,
    this.state = GhostBubbleState.launching,
    this.dragOffset = Offset.zero,
  });

  Offset currentPosition(Offset sourceCenter) {
    final pos = Offset.lerp(sourceCenter, targetPosition, launchProgress.clamp(0, 1))!;
    return pos + dragOffset;
  }
}

class RadialExpansionController {
  // ===========================================================================
  // STATE
  // ===========================================================================

  RadialExpansionPhase _phase = RadialExpansionPhase.idle;
  RadialExpansionPhase get phase => _phase;

  String? _sourceClusterId;
  String? get sourceClusterId => _sourceClusterId;

  Offset _sourceCenter = Offset.zero;
  Offset get sourceCenter => _sourceCenter;

  String _sourceText = '';
  String _nearbyContext = '';

  final List<GhostBubble> _bubbles = [];
  List<GhostBubble> get bubbles => List.unmodifiable(_bubbles);

  final List<ConfirmParticle> _particles = [];
  List<ConfirmParticle> get particles => List.unmodifiable(_particles);

  final List<ConfirmBeam> _beams = [];
  List<ConfirmBeam> get beams => List.unmodifiable(_beams);

  double _chargeProgress = 0.0;
  double get chargeProgress => _chargeProgress;

  double _presentingTime = 0.0;
  double _cooldownRemaining = 0.0;
  bool _disposed = false;
  bool _generateCalled = false;

  void Function(RadialExpansionPhase)? onPhaseChanged;
  void Function()? onBubblesUpdated;

  // ===========================================================================
  // CONFIGURATION
  // ===========================================================================

  static const double chargeDuration = 0.7;
  static const double presentingTimeout = 14.0;
  static const double cooldownDuration = 0.5;
  static const double innerOrbitRadius = 190.0;
  static const double outerOrbitRadius = 270.0;
  static const int maxSubTopics = 6;           // 4 inner + 2 outer
  static const double launchDuration = 0.32;
  static const double confirmThresholdFraction = 0.55;
  static const double dismissThresholdFraction = 0.35;
  static const double staggerInterval = 0.07; // 70ms per bubble

  // ===========================================================================
  // LIFECYCLE
  // ===========================================================================

  void startCharge(String clusterId, Offset center, String text) {
    if (_phase != RadialExpansionPhase.idle) return;
    _sourceClusterId = clusterId;
    _sourceCenter = center;
    _sourceText = text;
    _nearbyContext = '';
    _chargeProgress = 0.0;
    _generateCalled = false;
    _setPhase(RadialExpansionPhase.charging);
  }

  void updateSourceText(String text) {
    if (text.trim().isNotEmpty) _sourceText = text;
  }

  void updateNearbyContext(String context) {
    _nearbyContext = context;
  }

  void cancelCharge() {
    if (_phase != RadialExpansionPhase.charging) return;
    _chargeProgress = 0.0;
    _setPhase(RadialExpansionPhase.idle);
  }

  Future<List<String>> generate({String deviceLanguage = 'Italian'}) async {
    if (_generateCalled) return [];
    if (_phase != RadialExpansionPhase.charging && _phase != RadialExpansionPhase.idle) return [];
    _generateCalled = true;
    _setPhase(RadialExpansionPhase.generating);
    _bubbles.clear();

    try {
      final provider = EngineScope.current.atlasProvider;
      if (!provider.isInitialized) await provider.initialize();

      final prompt = _buildSubTopicPrompt(_sourceText, _nearbyContext, deviceLanguage);
      print('🌌 RadialExpansion sending prompt for "$_sourceText" (context: ${_nearbyContext.isNotEmpty})');
      final response = await provider.askAtlas(prompt, []);
      print('🌌 RadialExpansion response: ${response.actions.length} actions');

      final labels = <String>[];
      for (final action in response.actions) {
        if (action is CreateNodeAction) {
          final text = action.content.trim();
          if (text.isNotEmpty) labels.add(text);
        }
      }
      if (labels.isEmpty) {
        labels.addAll(_parseSubTopics(response.explanation ?? ''));
      }

      print('🌟 RadialExpansion: parsed labels=$labels');

      if (labels.isEmpty || _disposed) {
        _setPhase(RadialExpansionPhase.idle);
        return [];
      }

      _createBubbles(labels);
      _presentingTime = 0.0;
      _setPhase(RadialExpansionPhase.presenting);
      return labels;
    } catch (e, st) {
      print('❌ RadialExpansion generate error: $e\n$st');
      _setPhase(RadialExpansionPhase.idle);
      return [];
    }
  }

  // ===========================================================================
  // DRAG-TO-CONFIRM
  // ===========================================================================

  GhostBubble? startBubbleDrag(String bubbleId) {
    if (_phase != RadialExpansionPhase.presenting) return null;
    final bubble = _bubbles.where((b) => b.id == bubbleId).firstOrNull;
    if (bubble == null ||
        bubble.state == GhostBubbleState.launching ||
        bubble.state == GhostBubbleState.bouncing) return null;
    bubble.state = GhostBubbleState.dragging;
    bubble.dragOffset = Offset.zero;
    return bubble;
  }

  bool updateBubbleDrag(String bubbleId, Offset delta) {
    final bubble = _bubbles.where((b) => b.id == bubbleId).firstOrNull;
    if (bubble == null || bubble.state != GhostBubbleState.dragging) return false;
    bubble.dragOffset = delta;
    onBubblesUpdated?.call();
    return true;
  }

  ({String label, Offset position})? finalizeBubbleDrag(String bubbleId) {
    final bubble = _bubbles.where((b) => b.id == bubbleId).firstOrNull;
    if (bubble == null) return null;

    final dragDist = bubble.dragOffset.distance;

    // TAP FALLBACK: < 20px = direct confirm
    if (dragDist < 20.0) {
      bubble.state = GhostBubbleState.confirming;
      bubble.dragOffset = Offset.zero;
      onBubblesUpdated?.call();
      _spawnConfirmEffects(bubble.targetPosition);
      Future.delayed(const Duration(milliseconds: 400), _dismissRemaining);
      return (label: bubble.label, position: bubble.targetPosition);
    }

    final toTarget = bubble.targetPosition - _sourceCenter;
    final dot = toTarget.dx * bubble.dragOffset.dx + toTarget.dy * bubble.dragOffset.dy;
    final isOutward = dot >= 0;
    final confirmThreshold = innerOrbitRadius * confirmThresholdFraction;
    final dismissThreshold = innerOrbitRadius * dismissThresholdFraction;

    if (isOutward && dragDist >= confirmThreshold) {
      final confirmPos = bubble.targetPosition + bubble.dragOffset;
      bubble.state = GhostBubbleState.confirming;
      bubble.dragOffset = Offset.zero;
      onBubblesUpdated?.call();
      _spawnConfirmEffects(confirmPos);
      Future.delayed(const Duration(milliseconds: 400), _dismissRemaining);
      return (label: bubble.label, position: confirmPos);
    } else if (!isOutward || dragDist >= dismissThreshold) {
      bubble.state = GhostBubbleState.collapsing; // animate toward source
      bubble.dragOffset = Offset.zero;
      onBubblesUpdated?.call();
      return null;
    } else {
      bubble.state = GhostBubbleState.idle;
      bubble.dragOffset = Offset.zero;
      onBubblesUpdated?.call();
      return null;
    }
  }

  ({String label, Offset position})? confirmBubble(String bubbleId) {
    final bubble = _bubbles.where((b) => b.id == bubbleId).firstOrNull;
    if (bubble == null) return null;
    bubble.state = GhostBubbleState.confirming;
    onBubblesUpdated?.call();
    Future.delayed(const Duration(milliseconds: 400), _dismissRemaining);
    return (label: bubble.label, position: bubble.targetPosition);
  }

  void dismissAll() {
    if (_phase != RadialExpansionPhase.presenting) return;
    _collapseRemaining();
  }

  GhostBubble? hitTest(Offset canvasPoint, {double radius = 60.0}) {
    if (_phase != RadialExpansionPhase.presenting) return null;
    for (final bubble in _bubbles) {
      // Allow hit during bouncing (bubble is at target, just scale-animating)
      if (bubble.state == GhostBubbleState.dismissing ||
          bubble.state == GhostBubbleState.confirming ||
          bubble.state == GhostBubbleState.launching ||
          bubble.state == GhostBubbleState.collapsing) continue;
      if ((bubble.currentPosition(_sourceCenter) - canvasPoint).distance <= radius)
        return bubble;
    }
    return null;
  }

  // ===========================================================================
  // TICK
  // ===========================================================================

  bool tick(double dt) {
    if (_disposed) return false;

    switch (_phase) {
      case RadialExpansionPhase.idle: return false;
      case RadialExpansionPhase.charging:
        _chargeProgress = (_chargeProgress + dt / chargeDuration).clamp(0, 1);
        return true;
      case RadialExpansionPhase.generating: return true;

      case RadialExpansionPhase.presenting:
        _presentingTime += dt;
        bool changed = false;

        for (final bubble in _bubbles) {
          bubble.floatPhase += dt * 1.8;

          switch (bubble.state) {
            case GhostBubbleState.launching:
              if (_presentingTime < bubble.launchDelay) break;
              bubble.launchProgress = (bubble.launchProgress + dt / launchDuration).clamp(0, 1);
              bubble.opacity = (bubble.opacity + dt * 4.0).clamp(0, 1);
              if (bubble.launchProgress >= 1.0) {
                bubble.state = GhostBubbleState.bouncing;
                bubble.scale = 1.25; // overshoot start
              }
              changed = true;

            case GhostBubbleState.bouncing:
              // Spring from 1.25 → 1.0
              bubble.scale += (1.0 - bubble.scale) * 0.18;
              if ((bubble.scale - 1.0).abs() < 0.01) {
                bubble.scale = 1.0;
                bubble.state = GhostBubbleState.idle;
              }
              changed = true;

            case GhostBubbleState.idle: changed = true; // float

            case GhostBubbleState.dragging: changed = true;

            case GhostBubbleState.confirming:
              bubble.scale = (bubble.scale + dt * 2.5).clamp(0, 1.6);
              bubble.opacity = (bubble.opacity - dt * 2.8).clamp(0, 1);
              changed = true;

            case GhostBubbleState.dismissing:
              bubble.opacity = (bubble.opacity - dt * 4.0).clamp(0, 1);
              bubble.scale = (bubble.scale - dt * 3.0).clamp(0, 1);
              changed = true;

            case GhostBubbleState.collapsing:
              // Animate back toward source center
              bubble.launchProgress = (bubble.launchProgress - dt * 3.5).clamp(0, 1);
              bubble.opacity = (bubble.opacity - dt * 3.0).clamp(0, 1);
              changed = true;
          }
        }

        // update particles
        _particles.removeWhere((p) => p.opacity <= 0);
        for (final p in _particles) {
          p.position += p.velocity * dt;
          p.opacity = (p.opacity - dt * 2.2).clamp(0.0, 1.0);
          changed = true;
        }

        // update beams
        _beams.removeWhere((b) => b.opacity <= 0);
        for (final b in _beams) {
          b.progress = (b.progress + dt / 0.45).clamp(0.0, 1.0);
          if (b.progress >= 1.0) b.opacity = (b.opacity - dt * 3.5).clamp(0.0, 1.0);
          changed = true;
        }

        _bubbles.removeWhere((b) =>
          (b.state == GhostBubbleState.dismissing ||
           b.state == GhostBubbleState.confirming ||
           b.state == GhostBubbleState.collapsing) &&
          b.opacity <= 0.0);

        if (_presentingTime >= presentingTimeout && _bubbles.isNotEmpty) {
          _collapseRemaining();
        }
        if (_bubbles.isEmpty && _phase == RadialExpansionPhase.presenting) {
          _startCooldown();
        }
        return changed;

      case RadialExpansionPhase.cooldown:
        _cooldownRemaining -= dt;
        if (_cooldownRemaining <= 0) _setPhase(RadialExpansionPhase.idle);
        return true;
    }
  }

  void dispose() {
    _disposed = true;
    _bubbles.clear();
    onPhaseChanged = null;
    onBubblesUpdated = null;
  }

  // ===========================================================================
  // INTERNAL
  // ===========================================================================

  void _setPhase(RadialExpansionPhase p) {
    if (_phase == p) return;
    _phase = p;
    onPhaseChanged?.call(p);
  }

  void _spawnConfirmEffects(Offset pos) {
    // 14 particles fanning outward
    const count = 14;
    final rng = math.Random();
    for (int i = 0; i < count; i++) {
      final angle = (2 * math.pi / count) * i + rng.nextDouble() * 0.4;
      final speed = 55.0 + rng.nextDouble() * 60.0;
      _particles.add(ConfirmParticle(
        position: pos,
        velocity: Offset(math.cos(angle) * speed, math.sin(angle) * speed),
        opacity: 0.9 + rng.nextDouble() * 0.1,
        size: 2.0 + rng.nextDouble() * 3.5,
        colorIndex: i % 4,
      ));
    }
    // Animated beam from source to confirm position
    _beams.add(ConfirmBeam(from: _sourceCenter, to: pos));
  }

  void _dismissRemaining() {
    for (final b in _bubbles) {
      if (b.state == GhostBubbleState.idle || b.state == GhostBubbleState.launching || b.state == GhostBubbleState.bouncing) {
        b.state = GhostBubbleState.dismissing;
        b.dragOffset = Offset.zero;
      }
    }
    onBubblesUpdated?.call();
  }

  void _collapseRemaining() {
    for (final b in _bubbles) {
      if (b.state == GhostBubbleState.idle || b.state == GhostBubbleState.launching || b.state == GhostBubbleState.bouncing) {
        b.state = GhostBubbleState.collapsing;
        b.dragOffset = Offset.zero;
      }
    }
    onBubblesUpdated?.call();
  }

  void _startCooldown() {
    _cooldownRemaining = cooldownDuration;
    _setPhase(RadialExpansionPhase.cooldown);
  }

  void _createBubbles(List<String> labels) {
    final count = labels.length.clamp(1, maxSubTopics);
    // Inner orbit: first 4 (or all if ≤ 4); outer orbit: remaining
    final innerCount = count <= 4 ? count : 4;
    final outerCount = count - innerCount;
    final innerAngleStep = (2 * math.pi) / innerCount;
    const startAngle = -math.pi / 2;

    for (int i = 0; i < innerCount; i++) {
      final angle = startAngle + innerAngleStep * i;
      final jitter = (math.sin(i * 1.618) * 15).toDouble();
      final dist = innerOrbitRadius + jitter;
      _bubbles.add(GhostBubble(
        id: 'ghost_$i',
        label: labels[i],
        targetPosition: Offset(_sourceCenter.dx + dist * math.cos(angle), _sourceCenter.dy + dist * math.sin(angle)),
        angle: angle,
        distance: dist,
        launchDelay: staggerInterval * i,
      ));
    }

    if (outerCount > 0) {
      final outerAngleStep = (2 * math.pi) / outerCount;
      final outerOffset = outerAngleStep / 2; // offset for visual variety
      for (int i = 0; i < outerCount; i++) {
        final idx = innerCount + i;
        final angle = startAngle + outerOffset + outerAngleStep * i;
        final jitter = (math.sin(idx * 2.718) * 12).toDouble();
        final dist = outerOrbitRadius + jitter;
        _bubbles.add(GhostBubble(
          id: 'ghost_$idx',
          label: labels[idx],
          targetPosition: Offset(_sourceCenter.dx + dist * math.cos(angle), _sourceCenter.dy + dist * math.sin(angle)),
          angle: angle,
          distance: dist,
          launchDelay: staggerInterval * idx,
          isOuterOrbit: true,
        ));
      }
    }
  }

  String _buildSubTopicPrompt(String topic, String nearbyContext, String language) {
    final contextSection = nearbyContext.isNotEmpty
        ? '\nNEARBY CONCEPTS on the same canvas: $nearbyContext\nUse these to give more SPECIFIC and CONNECTED sub-topics, avoid repetition.'
        : '';

    return '''IGNORE all previous canvas action rules.
You are Atlas, a knowledge graph assistant for a student's mind map. Generate exactly $maxSubTopics sub-topics to expand a concept.

RULES:
- Return ONLY a valid JSON object with key "azioni" containing an array of objects.
- Each object: {"tipo": "create_node", "testo": "<sub-topic>"}
- Sub-topics must be concise (1-3 words each).
- Sub-topics must be specific and directly related to the main topic.
- You MUST respond in $language.
- NO explanations, NO markdown, ONLY the JSON object.
$contextSection

CONCEPT: "$topic"

EXAMPLE — Concept: "Fisica"
{"azioni": [{"tipo": "create_node", "testo": "Meccanica"}, {"tipo": "create_node", "testo": "Termodinamica"}, {"tipo": "create_node", "testo": "Onde"}, {"tipo": "create_node", "testo": "Ottica"}, {"tipo": "create_node", "testo": "Elettromagnetismo"}, {"tipo": "create_node", "testo": "Fisica quantistica"}]}''';
  }

  List<String> _parseSubTopics(String raw) {
    if (raw.trim().isEmpty) return [];

    final quotedPattern = RegExp(r'"testo"\s*:\s*"([^"]+)"');
    final matches = quotedPattern.allMatches(raw);
    if (matches.isNotEmpty) {
      return matches.map((m) => m.group(1)!).take(maxSubTopics).toList();
    }

    final arrayPattern = RegExp(r'\[([^\]]+)\]');
    final arrayMatch = arrayPattern.firstMatch(raw);
    if (arrayMatch != null) {
      final items = RegExp(r'"([^"]+)"')
          .allMatches(arrayMatch.group(1)!)
          .map((m) => m.group(1)!)
          .take(maxSubTopics)
          .toList();
      if (items.isNotEmpty) return items;
    }

    return raw
        .split(RegExp(r'[\n,]'))
        .map((l) => l.replaceAll(RegExp(r'^[\d.\-*•]+\s*'), '').trim())
        .where((l) => l.isNotEmpty && l.length <= 40)
        .take(maxSubTopics)
        .toList();
  }
}
