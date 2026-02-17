import 'dart:ui';

/// Type of user interaction that triggers a prototype transition.
enum PrototypeTrigger {
  /// Tap/click on the source element.
  click,

  /// Pointer enters the source element's bounds.
  hover,

  /// Drag gesture on the source element.
  drag,

  /// Automatic after a delay.
  timer,

  /// Keyboard shortcut or key press.
  keyPress,

  /// Scroll gesture on the source element.
  scroll,
}

/// Visual transition animation between prototype screens.
enum PrototypeTransition {
  /// Instant swap (no animation).
  instant,

  /// Cross-dissolve (fade out → fade in).
  dissolve,

  /// Slide from a direction.
  slideLeft,
  slideRight,
  slideUp,
  slideDown,

  /// Push: incoming screen pushes outgoing off-screen.
  pushLeft,
  pushRight,

  /// 3D flip around Y axis.
  flipHorizontal,

  /// 3D flip around X axis.
  flipVertical,

  /// Scale up from center of trigger element.
  scaleUp,

  /// Scale down to center of trigger element.
  scaleDown,

  /// Smart animate: interpolate matching layers.
  smartAnimate,
}

/// Easing curve for prototype transitions.
enum PrototypeEasing { linear, easeIn, easeOut, easeInOut, spring }

/// A link between two elements in a prototype flow.
///
/// Defines what happens when a user interacts with a source element:
/// which screen/frame to navigate to, and how the transition looks.
///
/// ```dart
/// final link = PrototypeLink(
///   id: 'btn-to-settings',
///   sourceNodeId: 'login-button',
///   targetFrameId: 'settings-screen',
///   trigger: PrototypeTrigger.click,
///   transition: PrototypeTransition.slideLeft,
/// );
/// ```
class PrototypeLink {
  final String id;

  /// Node ID that the user interacts with to trigger navigation.
  final String sourceNodeId;

  /// Frame/screen ID to navigate to.
  final String targetFrameId;

  /// What interaction triggers this link.
  PrototypeTrigger trigger;

  /// Visual transition animation.
  PrototypeTransition transition;

  /// Duration of the transition animation.
  Duration duration;

  /// Easing curve.
  PrototypeEasing easing;

  /// Delay before transition starts (for timer triggers or intentional delay).
  Duration delay;

  /// Whether to preserve scroll position when navigating back.
  bool preserveScrollPosition;

  /// Optional: specific scroll offset to reset to on target frame.
  Offset? scrollOffset;

  /// Whether this link is currently enabled.
  bool isEnabled;

  PrototypeLink({
    required this.id,
    required this.sourceNodeId,
    required this.targetFrameId,
    this.trigger = PrototypeTrigger.click,
    this.transition = PrototypeTransition.dissolve,
    this.duration = const Duration(milliseconds: 300),
    this.easing = PrototypeEasing.easeInOut,
    this.delay = Duration.zero,
    this.preserveScrollPosition = false,
    this.scrollOffset,
    this.isEnabled = true,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'sourceNodeId': sourceNodeId,
    'targetFrameId': targetFrameId,
    'trigger': trigger.name,
    'transition': transition.name,
    'durationMs': duration.inMilliseconds,
    'easing': easing.name,
    'delayMs': delay.inMilliseconds,
    'preserveScrollPosition': preserveScrollPosition,
    if (scrollOffset != null)
      'scrollOffset': {'dx': scrollOffset!.dx, 'dy': scrollOffset!.dy},
    'isEnabled': isEnabled,
  };

  factory PrototypeLink.fromJson(Map<String, dynamic> json) => PrototypeLink(
    id: json['id'] as String,
    sourceNodeId: json['sourceNodeId'] as String,
    targetFrameId: json['targetFrameId'] as String,
    trigger: PrototypeTrigger.values.byName(
      json['trigger'] as String? ?? 'click',
    ),
    transition: PrototypeTransition.values.byName(
      json['transition'] as String? ?? 'dissolve',
    ),
    duration: Duration(milliseconds: json['durationMs'] as int? ?? 300),
    easing: PrototypeEasing.values.byName(
      json['easing'] as String? ?? 'easeInOut',
    ),
    delay: Duration(milliseconds: json['delayMs'] as int? ?? 0),
    preserveScrollPosition: json['preserveScrollPosition'] as bool? ?? false,
    scrollOffset:
        json['scrollOffset'] != null
            ? Offset(
              (json['scrollOffset']['dx'] as num).toDouble(),
              (json['scrollOffset']['dy'] as num).toDouble(),
            )
            : null,
    isEnabled: json['isEnabled'] as bool? ?? true,
  );
}

/// A screen/frame in a prototype flow.
class PrototypeScreen {
  /// The frame node ID this screen represents.
  final String frameId;

  /// Display name for this screen in the flow overview.
  String name;

  /// Starting screen flag.
  bool isStartScreen;

  /// Background color override during prototype playback.
  Color? backgroundColor;

  PrototypeScreen({
    required this.frameId,
    this.name = '',
    this.isStartScreen = false,
    this.backgroundColor,
  });

  Map<String, dynamic> toJson() => {
    'frameId': frameId,
    'name': name,
    'isStartScreen': isStartScreen,
    if (backgroundColor != null) 'backgroundColor': backgroundColor!.toARGB32(),
  };

  factory PrototypeScreen.fromJson(Map<String, dynamic> json) =>
      PrototypeScreen(
        frameId: json['frameId'] as String,
        name: json['name'] as String? ?? '',
        isStartScreen: json['isStartScreen'] as bool? ?? false,
        backgroundColor:
            json['backgroundColor'] != null
                ? Color(json['backgroundColor'] as int)
                : null,
      );
}

/// A complete prototype flow containing screens and links.
///
/// Manages the navigation graph for prototype playback.
/// Supports multiple flows within the same document.
///
/// ```dart
/// final flow = PrototypeFlow(id: 'onboarding');
/// flow.addScreen(PrototypeScreen(frameId: 'splash', isStartScreen: true));
/// flow.addScreen(PrototypeScreen(frameId: 'login'));
/// flow.addLink(PrototypeLink(
///   id: 'splash-to-login',
///   sourceNodeId: 'get-started-btn',
///   targetFrameId: 'login',
///   trigger: PrototypeTrigger.click,
///   transition: PrototypeTransition.slideLeft,
/// ));
/// ```
class PrototypeFlow {
  final String id;
  String name;

  /// All screens in this flow.
  final List<PrototypeScreen> _screens = [];

  /// All links in this flow.
  final List<PrototypeLink> _links = [];

  /// Device frame preset (for preview).
  String? devicePreset;

  PrototypeFlow({required this.id, this.name = '', this.devicePreset});

  // ---- Screens ----

  List<PrototypeScreen> get screens => List.unmodifiable(_screens);

  void addScreen(PrototypeScreen screen) => _screens.add(screen);

  void removeScreen(String frameId) {
    _screens.removeWhere((s) => s.frameId == frameId);
    _links.removeWhere(
      (l) => l.sourceNodeId == frameId || l.targetFrameId == frameId,
    );
  }

  PrototypeScreen? getScreen(String frameId) {
    for (final s in _screens) {
      if (s.frameId == frameId) return s;
    }
    return null;
  }

  PrototypeScreen? get startScreen {
    for (final s in _screens) {
      if (s.isStartScreen) return s;
    }
    return _screens.isNotEmpty ? _screens.first : null;
  }

  // ---- Links ----

  List<PrototypeLink> get links => List.unmodifiable(_links);

  void addLink(PrototypeLink link) => _links.add(link);

  void removeLink(String linkId) {
    _links.removeWhere((l) => l.id == linkId);
  }

  /// All links originating from a source node.
  List<PrototypeLink> linksFromNode(String nodeId) {
    return _links.where((l) => l.sourceNodeId == nodeId).toList();
  }

  /// All links targeting a frame.
  List<PrototypeLink> linksToFrame(String frameId) {
    return _links.where((l) => l.targetFrameId == frameId).toList();
  }

  /// Resolve: given a trigger on a node, which frame do we go to?
  PrototypeLink? resolveNavigation(
    String sourceNodeId,
    PrototypeTrigger trigger,
  ) {
    for (final link in _links) {
      if (link.sourceNodeId == sourceNodeId &&
          link.trigger == trigger &&
          link.isEnabled) {
        return link;
      }
    }
    return null;
  }

  // ---- Serialization ----

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (devicePreset != null) 'devicePreset': devicePreset,
    'screens': _screens.map((s) => s.toJson()).toList(),
    'links': _links.map((l) => l.toJson()).toList(),
  };

  factory PrototypeFlow.fromJson(Map<String, dynamic> json) {
    final flow = PrototypeFlow(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      devicePreset: json['devicePreset'] as String?,
    );

    final screensJson = json['screens'] as List<dynamic>? ?? [];
    for (final s in screensJson) {
      flow.addScreen(PrototypeScreen.fromJson(s as Map<String, dynamic>));
    }

    final linksJson = json['links'] as List<dynamic>? ?? [];
    for (final l in linksJson) {
      flow.addLink(PrototypeLink.fromJson(l as Map<String, dynamic>));
    }

    return flow;
  }
}
