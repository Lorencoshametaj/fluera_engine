import 'dart:ui';
import 'package:flutter/foundation.dart';
import '../config/advanced_split_layout.dart';
import '../config/split_panel_content.dart';

// =============================================================================
// MULTIVIEW STATE — Immutable state model for the multiview session
// =============================================================================

/// State for a single panel in the multiview grid.
class MultiviewPanelState {
  final SplitPanelContent content;
  final Offset viewportOffset;
  final double viewportScale;
  final double viewportRotation;

  const MultiviewPanelState({
    required this.content,
    this.viewportOffset = Offset.zero,
    this.viewportScale = 1.0,
    this.viewportRotation = 0.0,
  });

  MultiviewPanelState copyWith({
    SplitPanelContent? content,
    Offset? viewportOffset,
    double? viewportScale,
    double? viewportRotation,
  }) {
    return MultiviewPanelState(
      content: content ?? this.content,
      viewportOffset: viewportOffset ?? this.viewportOffset,
      viewportScale: viewportScale ?? this.viewportScale,
      viewportRotation: viewportRotation ?? this.viewportRotation,
    );
  }
}

/// Immutable state for the entire multiview session.
class MultiviewState {
  final AdvancedSplitLayout layout;
  final int activePanelIndex;
  final Map<int, MultiviewPanelState> panels;

  const MultiviewState({
    required this.layout,
    this.activePanelIndex = 0,
    required this.panels,
  });

  /// The currently active panel state.
  MultiviewPanelState? get activePanel => panels[activePanelIndex];

  /// Number of panels in this layout.
  int get panelCount => layout.panelCount;

  MultiviewState copyWith({
    AdvancedSplitLayout? layout,
    int? activePanelIndex,
    Map<int, MultiviewPanelState>? panels,
  }) {
    return MultiviewState(
      layout: layout ?? this.layout,
      activePanelIndex: activePanelIndex ?? this.activePanelIndex,
      panels: panels ?? this.panels,
    );
  }

  /// Create default state for a given layout type.
  factory MultiviewState.fromLayout(AdvancedSplitLayout layout) {
    final panels = <int, MultiviewPanelState>{};
    for (int i = 0; i < layout.panelCount; i++) {
      panels[i] = MultiviewPanelState(
        content: layout.panelContents[i] ?? SplitPanelContent.canvas(),
      );
    }
    return MultiviewState(layout: layout, panels: panels);
  }

  @override
  String toString() =>
      'MultiviewState(layout: ${layout.type}, active: $activePanelIndex, '
      'panels: ${panels.length})';
}
