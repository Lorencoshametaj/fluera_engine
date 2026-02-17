library professional_canvas_toolbar;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../../l10n/nebula_localizations.dart';
import '../../drawing/models/brush_preset.dart';
import '../../drawing/models/pro_drawing_point.dart';
import '../../core/models/shape_type.dart';
import '../../../testing/brush_testing.dart';
import '../../collaboration/sync_state_provider.dart';
// SDK: AI filters removed — use optional callback via NebulaToolbarConfig

import 'toolbar_status.dart';
import 'toolbar_tool_buttons.dart';
import 'toolbar_brush_strip.dart';
import 'toolbar_eraser.dart';
import 'toolbar_shapes.dart';
import 'toolbar_color_palette.dart';
import 'toolbar_sliders.dart';
import 'toolbar_settings_dropdown.dart';
import 'toolbar_recording.dart';
import 'toolbar_layout.dart';

part '_toolbar_top_row.dart';
part '_toolbar_tools_area.dart';

/// 🎨 Toolbar professionale per uso quotidiano
/// Design minimalista e funzionale con:
/// - Status bar compatta con info essenziali
/// - Tools organized logically (type → color → width)
/// - Quick actions sempre accessibili
/// - Scroll orizzontale smooth
/// - Collapsible to maximize canvas
class ProfessionalCanvasToolbar extends ConsumerStatefulWidget {
  final ProPenType selectedPenType;
  final Color selectedColor;
  final double selectedWidth;
  final double selectedOpacity;
  final ShapeType selectedShapeType;
  final int strokeCount;
  final bool canUndo;
  final bool canRedo;
  final bool isEraserActive;
  final bool isLassoActive;
  final bool isDigitalTextActive;
  final bool isImagePickerActive; // 🖼️ Pulsante immagini
  final bool isRecordingActive; // � Pulsante registrazione
  final bool isPanModeActive; // 🖐️ Modalità Pan
  final bool isStylusModeActive; // 🖊️ Modalità Stylus
  final bool isRulerActive; // 📏 Ruler/guide overlay
  final bool isPenToolActive; // ✒️ Vector Pen Tool
  final Duration recordingDuration;
  final String? noteTitle;
  // 🎨 Preset-based brush selection
  final List<BrushPreset> brushPresets;
  final String? selectedPresetId;
  final ValueChanged<BrushPreset>? onPresetSelected;
  final bool isImageEditingMode;

  final ValueChanged<ProPenType> onPenTypeChanged;
  final ValueChanged<Color> onColorChanged;
  final ValueChanged<double> onWidthChanged;
  final ValueChanged<double> onOpacityChanged;
  final ValueChanged<ShapeType> onShapeTypeChanged;
  final ValueChanged<String>? onNoteTitleChanged; // 🆕 Callback rinomina nota
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onClear;
  final VoidCallback onSettings;
  final void Function(Rect anchorRect)?
  onBrushSettingsPressed; // 🎛️ Callback impostazioni pennello
  final VoidCallback? onExportPressed; // 📤 Callback export canvas
  final VoidCallback onLayersPressed;
  final VoidCallback?
  onDualPagePressed; // 📖 Callback dual page viewer (solo PDF)
  final bool isDualPageMode; // 📖 Stato mode doppia pagina
  final VoidCallback onEraserToggle;
  final double eraserRadius;
  final ValueChanged<double>? onEraserRadiusChanged;
  final bool eraseWholeStroke;
  final ValueChanged<bool>? onEraseWholeStrokeChanged;
  final VoidCallback onLassoToggle;
  final VoidCallback onDigitalTextToggle;
  final VoidCallback onPanModeToggle; // 🖐️ Callback Pan Mode
  final VoidCallback onStylusModeToggle; // 🖊️ Callback Stylus Mode
  final VoidCallback? onRulerToggle; // 📏 Callback Ruler toggle
  final VoidCallback? onPenToolToggle; // ✒️ Callback Pen Tool toggle
  final VoidCallback onImagePickerPressed; // 🖼️ Callback immagini
  final VoidCallback? onImageEditorPressed;
  final VoidCallback? onExitImageEditMode; // ✅ Esci da edit mode
  final VoidCallback onRecordingPressed; // � Callback registrazione
  final VoidCallback
  onViewRecordingsPressed; // 🎧 Callback visualizza registrazioni
  final VoidCallback onPdfPressed; // 📄 Callback pulsante PDF
  final VoidCallback?
  onMultiViewPressed; // 📋 Callback pulsante multiview (opzionale)
  final ValueChanged<int>?
  onMultiViewModeSelected; // 📋 Callback selezione mode specifica
  final bool forceLeftAlign; // 🎯 Forza allineamento a sinistra
  // 📐 Layout callbacks
  final VoidCallback? onCanvasLayoutPressed; // Canvas solo
  final VoidCallback? onPdfLayoutPressed; // PDF solo
  final VoidCallback? onHSplitLayoutPressed; // H-Split
  final VoidCallback? onVSplitLayoutPressed; // V-Split
  final VoidCallback? onPdfOverlayPressed; // PDF Overlay
  final VoidCallback? onCanvasOverlayPressed; // Canvas Overlay
  // 🔄 Sync callback
  final VoidCallback? onSyncToggle; // Toggle sync
  final bool? isSyncEnabled; // Stato sync
  // 🔧 Advanced Split callback
  final VoidCallback? onAdvancedSplitPressed; // Advanced Split Configuretion
  // 📄 PDF Navigation
  final dynamic pdfController; // PDFController per navigazione
  final VoidCallback? onPdfAddPage; // Add page
  final VoidCallback? onPdfDeletePage; // 🗑️ Elimina pagina
  final VoidCallback? onPdfPageTemplate; // Change template pagina
  final VoidCallback? onPdfPageSelected; // Seleziona pagina
  final VoidCallback? onTimeTravelPressed; // ⏱️ Time Travel
  final VoidCallback? onBranchExplorerPressed; // 🌿 Branch Explorer
  final String? activeBranchName; // 🌿 Currently active branch
  final VoidCallback? onPaperTypePressed; // 📄 Paper type picker

  const ProfessionalCanvasToolbar({
    super.key,
    required this.selectedPenType,
    required this.selectedColor,
    required this.selectedWidth,
    required this.selectedOpacity,
    required this.selectedShapeType,
    required this.strokeCount,
    required this.canUndo,
    required this.canRedo,
    required this.isEraserActive,
    required this.isLassoActive,
    required this.isDigitalTextActive,
    required this.isImagePickerActive,
    required this.isRecordingActive,
    required this.isPanModeActive,
    required this.isStylusModeActive,
    this.isRulerActive = false,
    this.isPenToolActive = false,
    required this.recordingDuration,
    this.isImageEditingMode = false,
    this.noteTitle,
    this.brushPresets = const [],
    this.selectedPresetId,
    this.onPresetSelected,
    required this.onPenTypeChanged,
    required this.onColorChanged,
    required this.onWidthChanged,
    required this.onOpacityChanged,
    required this.onShapeTypeChanged,
    this.onNoteTitleChanged,
    required this.onUndo,
    required this.onRedo,
    required this.onClear,
    required this.onSettings,
    this.onBrushSettingsPressed, // 🎛️ Brush settings
    this.onExportPressed, // 📤 Export canvas
    required this.onLayersPressed,
    this.onDualPagePressed,
    this.isDualPageMode = false,
    required this.onEraserToggle,
    this.eraserRadius = 20.0,
    this.onEraserRadiusChanged,
    this.eraseWholeStroke = false,
    this.onEraseWholeStrokeChanged,
    required this.onLassoToggle,
    required this.onDigitalTextToggle,
    required this.onPanModeToggle,
    required this.onStylusModeToggle,
    this.onRulerToggle,
    this.onPenToolToggle,
    required this.onImagePickerPressed,
    this.onImageEditorPressed,
    this.onExitImageEditMode, // ✅ Esci da edit mode
    required this.onRecordingPressed,
    required this.onViewRecordingsPressed,
    required this.onPdfPressed,
    this.onMultiViewPressed,
    this.onMultiViewModeSelected,
    this.forceLeftAlign = false,
    // 📐 Layout callbacks
    this.onCanvasLayoutPressed,
    this.onPdfLayoutPressed,
    this.onHSplitLayoutPressed,
    this.onVSplitLayoutPressed,
    this.onPdfOverlayPressed,
    this.onCanvasOverlayPressed,
    // 🔄 Sync callback
    this.onSyncToggle,
    this.isSyncEnabled,
    // 🔧 Advanced Split callback
    this.onAdvancedSplitPressed,
    // 📄 PDF Navigation
    this.pdfController,
    this.onPdfAddPage,
    this.onPdfDeletePage,
    this.onPdfPageTemplate,
    this.onPdfPageSelected,
    this.onTimeTravelPressed, // ⏱️ Time Travel
    this.onBranchExplorerPressed, // 🌿 Branch Explorer
    this.activeBranchName, // 🌿 Active branch name
    this.onPaperTypePressed, // 📄 Paper type picker
    this.hideRecordingControlWhenActive = false,
    this.isFloating = false, // 🏝️ Floating Island mode
  });

  final bool hideRecordingControlWhenActive;
  final bool isFloating;

  @override
  ConsumerState<ProfessionalCanvasToolbar> createState() =>
      _ProfessionalCanvasToolbarState();
}

class _ProfessionalCanvasToolbarState
    extends ConsumerState<ProfessionalCanvasToolbar> {
  bool _isToolsExpanded = true;
  bool _isShapesExpanded = false;

  // Customizable colors (6 slots)
  List<Color> _customColors = [
    Colors.black,
    const Color(0xFF2196F3), // Blu
    const Color(0xFFE53935), // Rosso
    const Color(0xFF43A047), // Verde
    const Color(0xFF8E24AA), // Viola
    const Color(0xFFFF6F00), // Arancione
  ];

  @override
  void initState() {
    super.initState();
    _loadCustomColors();
  }

  // 📄 PDF Navigation Helper Methods
  int _getCurrentPage() {
    if (widget.pdfController == null) return 0;
    try {
      return (widget.pdfController.currentPageIndex as int) + 1;
    } catch (e) {
      return 0;
    }
  }

  int _getTotalPages() {
    if (widget.pdfController == null) return 0;
    try {
      return widget.pdfController.totalPages as int;
    } catch (e) {
      return 0;
    }
  }

  bool _canGoPreviousPage() {
    if (widget.pdfController == null) return false;
    try {
      return widget.pdfController.pdfElement?.canGoPrevious ?? false;
    } catch (e) {
      return false;
    }
  }

  bool _canGoNextPage() {
    if (widget.pdfController == null) return false;
    try {
      return widget.pdfController.pdfElement?.canGoNext ?? false;
    } catch (e) {
      return false;
    }
  }

  void _goToFirstPage() {
    widget.pdfController?.firstPage();
  }

  void _goToPreviousPage() {
    widget.pdfController?.previousPage();
  }

  void _goToNextPage() {
    widget.pdfController?.nextPage();
  }

  void _goToLastPage() {
    widget.pdfController?.lastPage();
  }

  // Load colori salvati
  Future<void> _loadCustomColors() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? savedColors = prefs.getStringList('custom_colors');
    if (savedColors != null && savedColors.length == 6) {
      setState(() {
        _customColors =
            savedColors
                .map((colorString) => Color(int.parse(colorString)))
                .toList();
      });
    }
  }

  // Save colori
  Future<void> _saveCustomColors() async {
    final prefs = await SharedPreferences.getInstance();
    final colorStrings =
        _customColors.map((c) => c.toARGB32().toString()).toList();
    await prefs.setStringList('custom_colors', colorStrings);
  }

  // Show color picker per slot specifico
  void _showColorPicker(int index) {
    Color pickerColor = _customColors[index];

    showDialog(
      context: context,
      builder: (context) {
        final l10n = NebulaLocalizations.of(context);
        return AlertDialog(
          title: Text(l10n.proCanvas_chooseColor),
          content: SingleChildScrollView(
            child: ColorPicker(
              pickerColor: pickerColor,
              onColorChanged: (color) {
                pickerColor = color;
              },
              pickerAreaHeightPercent: 0.8,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.cancel),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _customColors[index] = pickerColor;
                });
                _saveCustomColors();
                widget.onColorChanged(pickerColor);
                Navigator.pop(context);
              },
              child: Text(l10n.save),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Different background color in editing mode
    final backgroundColor =
        widget.isImageEditingMode
            ? (isDark ? const Color(0xFF1A2F1A) : const Color(0xFFE8F5E8))
            : (isDark ? const Color(0xFF1E1E1E) : Colors.white);

    // 🏝️ Floating Configuretion
    final borderRadius =
        widget.isFloating ? BorderRadius.circular(24) : BorderRadius.zero;
    final elevation = widget.isFloating ? 4.0 : 8.0;
    final clipBehavior = widget.isFloating ? Clip.antiAlias : Clip.none;

    return widget.forceLeftAlign
        ? Align(
          alignment: Alignment.centerLeft,
          child: Material(
            color: backgroundColor,
            elevation: elevation,
            borderRadius: borderRadius,
            clipBehavior: clipBehavior,
            shadowColor: Colors.black.withValues(alpha: 0.3),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Row: Status Bar + Quick Actions
                _buildTopRow(context, isDark),

                // Tools Area (collapsabile)
                AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  child:
                      _isToolsExpanded
                          ? _buildToolsArea(context, isDark)
                          : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        )
        : Material(
          color: backgroundColor,
          elevation: elevation,
          borderRadius: borderRadius,
          clipBehavior: clipBehavior,
          shadowColor: Colors.black.withValues(alpha: 0.3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top Row: Status Bar + Quick Actions
              _buildTopRow(context, isDark),

              // Tools Area (collapsabile)
              AnimatedSize(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                child:
                    _isToolsExpanded
                        ? _buildToolsArea(context, isDark)
                        : const SizedBox.shrink(),
              ),
            ],
          ),
        );
  }

  // ============================================================================
  // 🔝 TOP ROW → see _toolbar_top_row.dart
  // 🛠️ TOOLS AREA → see _toolbar_tools_area.dart
  // ============================================================================
}
