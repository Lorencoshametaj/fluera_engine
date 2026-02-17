import 'package:flutter/material.dart';
import '../l10n/nebula_localizations.dart';

/// 🎨 SPLIT PANEL CONTENT
/// Model for defining the content of a panel in the advanced split system
class SplitPanelContent {
  final SplitPanelContentType type;
  final String? selectedId;
  final Map<String, dynamic> metadata;

  const SplitPanelContent({
    required this.type,
    this.selectedId,
    this.metadata = const {},
  });

  /// Factory to create specific content
  factory SplitPanelContent.pdf([String? pdfId, String? displayName]) =>
      SplitPanelContent(
        type: SplitPanelContentType.pdf,
        selectedId: pdfId,
        metadata: {if (displayName != null) 'displayName': displayName},
      );

  factory SplitPanelContent.canvas([String? canvasId]) => SplitPanelContent(
    type: SplitPanelContentType.canvas,
    selectedId: canvasId,
  );

  factory SplitPanelContent.note([
    String? noteId,
    String? infiniteCanvasId,
    String? nodeId,
    String? displayName,
  ]) => SplitPanelContent(
    type: SplitPanelContentType.note,
    selectedId: noteId,
    metadata: {
      if (infiniteCanvasId != null) 'infiniteCanvasId': infiniteCanvasId,
      if (nodeId != null) 'nodeId': nodeId,
      if (displayName != null) 'displayName': displayName,
    },
  );

  factory SplitPanelContent.whiteboard() =>
      const SplitPanelContent(type: SplitPanelContentType.whiteboard);

  factory SplitPanelContent.browser([String? url]) =>
      SplitPanelContent(type: SplitPanelContentType.browser, selectedId: url);

  factory SplitPanelContent.textEditor([String? documentId]) =>
      SplitPanelContent(
        type: SplitPanelContentType.textEditor,
        selectedId: documentId,
      );

  factory SplitPanelContent.calculator() =>
      const SplitPanelContent(type: SplitPanelContentType.calculator);

  factory SplitPanelContent.empty() =>
      const SplitPanelContent(type: SplitPanelContentType.empty);

  /// Creates a copy with modified parameters
  SplitPanelContent copyWith({
    SplitPanelContentType? type,
    String? selectedId,
    Map<String, dynamic>? metadata,
  }) {
    return SplitPanelContent(
      type: type ?? this.type,
      selectedId: selectedId ?? this.selectedId,
      metadata: metadata ?? this.metadata,
    );
  }

  /// If the content is valid and correctly configured
  bool get isValid {
    if (type.requiresSelection) {
      return selectedId != null && selectedId!.isNotEmpty;
    }
    return true;
  }

  @override
  String toString() {
    return 'SplitPanelContent(type: $type, selectedId: $selectedId)';
  }
}

/// Supported content types for panels
enum SplitPanelContentType {
  pdf(Icons.picture_as_pdf_rounded, true),
  canvas(Icons.brush_rounded, false),
  note(Icons.note_rounded, true),
  whiteboard(Icons.dashboard_rounded, false),
  browser(Icons.web_rounded, true),
  textEditor(Icons.text_fields_rounded, true),
  calculator(Icons.calculate_rounded, false),
  empty(Icons.crop_free_rounded, false);

  const SplitPanelContentType(
    this.icon,
    this.requiresSelection,
  );

  final IconData icon;
  final bool requiresSelection;

  /// Localized display name
  String getDisplayName(BuildContext context) {
    final l10n = NebulaLocalizations.of(context);
    switch (this) {
      case SplitPanelContentType.pdf:
        return l10n.splitPanel_pdfViewer;
      case SplitPanelContentType.canvas:
        return l10n.splitPanel_infiniteCanvas;
      case SplitPanelContentType.note:
        return l10n.splitPanel_existingNote;
      case SplitPanelContentType.whiteboard:
        return l10n.splitPanel_whiteboard;
      case SplitPanelContentType.browser:
        return l10n.splitPanel_webBrowser;
      case SplitPanelContentType.textEditor:
        return l10n.splitPanel_textEditor;
      case SplitPanelContentType.calculator:
        return l10n.splitPanel_calculator;
      case SplitPanelContentType.empty:
        return l10n.splitPanel_emptyPanel;
    }
  }

  /// Descrizione dettagliata del type of contenuto
  String getDescription(BuildContext context) {
    final l10n = NebulaLocalizations.of(context);
    switch (this) {
      case SplitPanelContentType.pdf:
        return l10n.splitPanel_pdfDescription;
      case SplitPanelContentType.canvas:
        return l10n.splitPanel_canvasDescription;
      case SplitPanelContentType.note:
        return l10n.splitPanel_noteDescription;
      case SplitPanelContentType.whiteboard:
        return l10n.splitPanel_whiteboardDescription;
      case SplitPanelContentType.browser:
        return l10n.splitPanel_browserDescription;
      case SplitPanelContentType.textEditor:
        return l10n.splitPanel_textEditorDescription;
      case SplitPanelContentType.calculator:
        return l10n.splitPanel_calculatorDescription;
      case SplitPanelContentType.empty:
        return l10n.splitPanel_emptyDescription;
    }
  }

  /// Color associated with content type
  Color get color {
    switch (this) {
      case SplitPanelContentType.pdf:
        return Colors.red;
      case SplitPanelContentType.canvas:
        return Colors.blue;
      case SplitPanelContentType.note:
        return Colors.green;
      case SplitPanelContentType.whiteboard:
        return Colors.orange;
      case SplitPanelContentType.browser:
        return Colors.purple;
      case SplitPanelContentType.textEditor:
        return Colors.teal;
      case SplitPanelContentType.calculator:
        return Colors.indigo;
      case SplitPanelContentType.empty:
        return Colors.grey;
    }
  }
}

/// Common presets for quick configurations
class SplitContentPresets {
  static const Map<String, List<SplitPanelContentType>> presets = {
    'Annotazione PDF': [
      SplitPanelContentType.pdf,
      SplitPanelContentType.canvas,
    ],
    'Studio Completo': [
      SplitPanelContentType.pdf,
      SplitPanelContentType.canvas,
      SplitPanelContentType.note,
    ],
    'Ricerca Web': [
      SplitPanelContentType.browser,
      SplitPanelContentType.note,
      SplitPanelContentType.textEditor,
    ],
    'Workspace Completo': [
      SplitPanelContentType.pdf,
      SplitPanelContentType.canvas,
      SplitPanelContentType.note,
      SplitPanelContentType.calculator,
    ],
    'Brainstorming': [
      SplitPanelContentType.whiteboard,
      SplitPanelContentType.whiteboard,
      SplitPanelContentType.textEditor,
      SplitPanelContentType.note,
    ],
  };

  /// Get a preset by name
  static List<SplitPanelContentType>? getPreset(String name) {
    return presets[name];
  }

  /// List of all preset names
  static List<String> get presetNames => presets.keys.toList();
}
