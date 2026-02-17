import 'package:flutter/material.dart';
import './split_panel_content.dart';

/// 🔧 ADVANCED SPLIT LAYOUT
/// Model for advanced split layouts supporting 2-4 panels
/// with customizable orientations and configurable content
class AdvancedSplitLayout {
  final SplitLayoutType type;
  final SplitOrientation primaryOrientation;
  final SplitOrientation secondaryOrientation;
  final Map<int, SplitPanelContent> panelContents;
  final Map<String, double> proportions;

  const AdvancedSplitLayout({
    required this.type,
    required this.primaryOrientation,
    required this.secondaryOrientation,
    required this.panelContents,
    required this.proportions,
  });

  /// Numero di pannelli nel layout
  int get panelCount => type.panelCount;

  /// If il layout supporta orientamenti personalizzabili
  bool get supportsOrientation => type.supportsOrientation;

  /// If il layout supporta orientamenti secondari
  bool get supportsSecondaryOrientation => type.supportsSecondaryOrientation;

  /// Whether the layout supports proportion adjustment
  bool get supportsSplit => type.supportsSplit;

  /// Creates a copy with modified parameters
  AdvancedSplitLayout copyWith({
    SplitLayoutType? type,
    SplitOrientation? primaryOrientation,
    SplitOrientation? secondaryOrientation,
    Map<int, SplitPanelContent>? panelContents,
    Map<String, double>? proportions,
  }) {
    return AdvancedSplitLayout(
      type: type ?? this.type,
      primaryOrientation: primaryOrientation ?? this.primaryOrientation,
      secondaryOrientation: secondaryOrientation ?? this.secondaryOrientation,
      panelContents: panelContents ?? this.panelContents,
      proportions: proportions ?? this.proportions,
    );
  }

  @override
  String toString() {
    return 'AdvancedSplitLayout(type: $type, panels: ${panelContents.length}, proportions: $proportions)';
  }
}

/// Tipi di layout split supportati
enum SplitLayoutType {
  split2('Split 2 Pannelli', Icons.view_sidebar_rounded, 2),
  split3Horizontal('Split 3 Orizzontali', Icons.view_column_rounded, 3),
  split3Vertical('Split 3 Verticali', Icons.view_agenda_rounded, 3),
  split3Mixed('Split 3 Misto', Icons.view_quilt_rounded, 3),
  split4Grid('Griglia 2x2', Icons.grid_view_rounded, 4),
  split4Rows('4 Righe', Icons.view_stream_rounded, 4),
  split4Columns('4 Colonne', Icons.view_week_rounded, 4);

  const SplitLayoutType(this.displayName, this.icon, this.panelCount);

  final String displayName;
  final IconData icon;
  final int panelCount;

  /// If il layout supporta orientamenti personalizzabili
  bool get supportsOrientation {
    switch (this) {
      case SplitLayoutType.split2:
      case SplitLayoutType.split3Mixed:
        return true;
      default:
        return false;
    }
  }

  /// If il layout supporta orientamenti secondari
  bool get supportsSecondaryOrientation {
    switch (this) {
      case SplitLayoutType.split3Mixed:
        return true;
      default:
        return false;
    }
  }

  /// Whether the layout supports proportion adjustment
  bool get supportsSplit {
    switch (this) {
      case SplitLayoutType.split2:
      case SplitLayoutType.split3Mixed:
      case SplitLayoutType.split4Grid:
        return true;
      default:
        return false;
    }
  }

  /// Descrizione dettagliata del layout
  String get description {
    switch (this) {
      case SplitLayoutType.split2:
        return 'Due pannelli affiancati con divisore regolabile';
      case SplitLayoutType.split3Horizontal:
        return 'Tre pannelli disposti orizzontalmente';
      case SplitLayoutType.split3Vertical:
        return 'Tre pannelli disposti verticalmente';
      case SplitLayoutType.split3Mixed:
        return 'Un pannello principale e due secondari';
      case SplitLayoutType.split4Grid:
        return 'Quattro pannelli in griglia 2x2';
      case SplitLayoutType.split4Rows:
        return 'Quattro pannelli disposti in righe';
      case SplitLayoutType.split4Columns:
        return 'Quattro pannelli disposti in colonne';
    }
  }
}

/// Orientamenti supportati per i layout
enum SplitOrientation {
  horizontal('Orizzontale', Icons.horizontal_split_rounded),
  vertical('Verticale', Icons.vertical_split_rounded);

  const SplitOrientation(this.displayName, this.icon);

  final String displayName;
  final IconData icon;
}
