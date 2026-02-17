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

  Widget _buildTopRow(BuildContext context, bool isDark) {
    final l10n = NebulaLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.only(left: 0, right: 8, top: 8, bottom: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Back button
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded, size: 22),
              onPressed: () => Navigator.pop(context),
              tooltip: l10n.close,
              color: isDark ? Colors.white70 : Colors.black87,
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            ),

            const SizedBox(width: 8),

            // 📄 PDF NAVIGATION CONTROLS (se disponibili)
            if (widget.pdfController != null)
              ListenableBuilder(
                listenable: widget.pdfController,
                builder: (context, _) {
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Add page
                      if (widget.onPdfAddPage != null)
                        IconButton(
                          icon: const Icon(Icons.add_box_outlined, size: 20),
                          tooltip: l10n.proCanvas_addPage,
                          onPressed: widget.onPdfAddPage,
                          color: Colors.blue,
                          padding: const EdgeInsets.all(8),
                          constraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                        ),

                      // 🗑️ Elimina pagina
                      if (widget.onPdfDeletePage != null)
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20),
                          tooltip: l10n.proCanvas_removePage,
                          onPressed: widget.onPdfDeletePage,
                          color: Colors.red,
                          padding: const EdgeInsets.all(8),
                          constraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                        ),

                      // Change template pagina
                      if (widget.onPdfPageTemplate != null)
                        IconButton(
                          icon: const Icon(Icons.note_alt_outlined, size: 20),
                          tooltip:
                              'Page Template', // TODO: Add l10n.proCanvas_pageTemplate
                          onPressed: widget.onPdfPageTemplate,
                          color: Colors.deepPurple,
                          padding: const EdgeInsets.all(8),
                          constraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                        ),

                      // Separatore
                      if (widget.onPdfAddPage != null ||
                          widget.onPdfDeletePage != null ||
                          widget.onPdfPageTemplate != null)
                        Container(
                          width: 1,
                          height: 24,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          color: isDark ? Colors.white12 : Colors.black12,
                        ),

                      // Prima pagina
                      IconButton(
                        icon: const Icon(Icons.first_page, size: 18),
                        tooltip: l10n.proCanvas_firstPage,
                        onPressed: _canGoPreviousPage() ? _goToFirstPage : null,
                        padding: const EdgeInsets.all(6),
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                      ),

                      // Pagina precedente
                      IconButton(
                        icon: const Icon(Icons.chevron_left, size: 18),
                        tooltip: l10n.proCanvas_previousPage,
                        onPressed:
                            _canGoPreviousPage() ? _goToPreviousPage : null,
                        padding: const EdgeInsets.all(6),
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                      ),

                      // Indicatore pagina (cliccabile per aprire selettore)
                      if (widget.onPdfPageSelected != null)
                        InkWell(
                          onTap: widget.onPdfPageSelected,
                          borderRadius: BorderRadius.circular(4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white10 : Colors.grey[100],
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: isDark ? Colors.white24 : Colors.black26,
                                width: 1,
                              ),
                            ),
                            child: Text(
                              '${_getCurrentPage()} / ${_getTotalPages()}',
                              style: TextStyle(
                                color: isDark ? Colors.white : Colors.black87,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),

                      // Pagina successiva
                      IconButton(
                        icon: const Icon(Icons.chevron_right, size: 18),
                        tooltip: l10n.proCanvas_nextPage,
                        onPressed: _canGoNextPage() ? _goToNextPage : null,
                        padding: const EdgeInsets.all(6),
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                      ),

                      // Last page
                      IconButton(
                        icon: const Icon(Icons.last_page, size: 18),
                        tooltip: l10n.proCanvas_lastPage,
                        onPressed: _canGoNextPage() ? _goToLastPage : null,
                        padding: const EdgeInsets.all(6),
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                      ),

                      const SizedBox(width: 8),

                      // Separatore verticale
                      Container(
                        width: 1,
                        height: 24,
                        color: isDark ? Colors.white12 : Colors.black12,
                      ),

                      const SizedBox(width: 8),
                    ],
                  );
                },
              ),

            // 📐 LAYOUT BUTTONS - I pulsanti richiesti dall'utente
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Canvas button
                if (widget.onCanvasLayoutPressed != null)
                  ToolbarLayoutButton(
                    icon: Icons.gesture_rounded,
                    label: NebulaLocalizations.of(context).proCanvas_canvasMode,
                    onPressed: widget.onCanvasLayoutPressed!,
                    isDark: isDark,
                    color: Colors.grey,
                  ),
                if (widget.onCanvasLayoutPressed != null)
                  const SizedBox(width: 4),

                // PDF button
                if (widget.onPdfLayoutPressed != null)
                  ToolbarLayoutButton(
                    icon: Icons.picture_as_pdf_rounded,
                    label: NebulaLocalizations.of(context).proCanvas_pdfMode,
                    onPressed: widget.onPdfLayoutPressed!,
                    isDark: isDark,
                    color: Colors.grey,
                  ),
                if (widget.onPdfLayoutPressed != null) const SizedBox(width: 4),

                // H-Split button
                if (widget.onHSplitLayoutPressed != null)
                  ToolbarLayoutButton(
                    icon: Icons.view_sidebar_rounded,
                    label: NebulaLocalizations.of(context).proCanvas_hSplit,
                    onPressed: widget.onHSplitLayoutPressed!,
                    isDark: isDark,
                    color: Colors.blue,
                  ),
                if (widget.onHSplitLayoutPressed != null)
                  const SizedBox(width: 4),

                // V-Split button
                if (widget.onVSplitLayoutPressed != null)
                  ToolbarLayoutButton(
                    icon: Icons.view_agenda_rounded,
                    label: NebulaLocalizations.of(context).proCanvas_vSplit,
                    onPressed: widget.onVSplitLayoutPressed!,
                    isDark: isDark,
                    color: Colors.indigo,
                  ),
                if (widget.onVSplitLayoutPressed != null)
                  const SizedBox(width: 4),

                // PDF Overlay button
                if (widget.onPdfOverlayPressed != null)
                  ToolbarLayoutButton(
                    icon: Icons.picture_in_picture_rounded,
                    label: NebulaLocalizations.of(context).proCanvas_pdfOverlay,
                    onPressed: widget.onPdfOverlayPressed!,
                    isDark: isDark,
                    color: Colors.orange,
                  ),
                if (widget.onPdfOverlayPressed != null)
                  const SizedBox(width: 4),

                // Canvas Overlay button
                if (widget.onCanvasOverlayPressed != null)
                  ToolbarLayoutButton(
                    icon: Icons.picture_in_picture_alt_rounded,
                    label:
                        NebulaLocalizations.of(context).proCanvas_canvasOverlay,
                    onPressed: widget.onCanvasOverlayPressed!,
                    isDark: isDark,
                    color: Colors.teal,
                  ),
                if (widget.onCanvasOverlayPressed != null)
                  const SizedBox(width: 4),

                // Advanced Split button
                if (widget.onAdvancedSplitPressed != null)
                  ToolbarLayoutButton(
                    icon: Icons.view_quilt_rounded,
                    label: NebulaLocalizations.of(context).proCanvas_splitPro,
                    onPressed: widget.onAdvancedSplitPressed!,
                    isDark: isDark,
                    color: Colors.deepPurple,
                  ),
                if (widget.onAdvancedSplitPressed != null)
                  const SizedBox(width: 8),

                // 🔄 Sync button - only if callback fornito
                if (widget.onSyncToggle != null && widget.isSyncEnabled != null)
                  ToolbarSyncButton(
                    onPressed: widget.onSyncToggle!,
                    isEnabled: widget.isSyncEnabled!,
                    isDark: isDark,
                  ),
                if (widget.onSyncToggle != null && widget.isSyncEnabled != null)
                  const SizedBox(width: 8),
              ],
            ),

            // 🎯 QUICK ACTIONS - Solo essenziali
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Layers button (nascosto in editing mode)
                if (!widget.isImageEditingMode) ...[
                  ToolbarCompactActionButton(
                    icon: Icons.layers_rounded,
                    onPressed: widget.onLayersPressed,
                    tooltip: l10n.proCanvas_layers,
                    isDark: isDark,
                    isEnabled: true,
                  ),
                  const SizedBox(width: 4),
                  // ⏱️ Time Travel button (with animation MD3)
                  if (widget.onTimeTravelPressed != null) ...[
                    ToolbarTimeTravelButton(
                      onPressed: widget.onTimeTravelPressed!,
                      isDark: isDark,
                    ),
                    const SizedBox(width: 4),
                  ],
                  // 🌿 Branch Explorer / Active branch indicator
                  if (widget.onBranchExplorerPressed != null) ...[
                    GestureDetector(
                      onTap: widget.onBranchExplorerPressed,
                      child: Container(
                        height: 30,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color:
                              widget.activeBranchName != null
                                  ? const Color(
                                    0xFF7C4DFF,
                                  ).withValues(alpha: 0.15)
                                  : (isDark ? Colors.white : Colors.black)
                                      .withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(10),
                          border:
                              widget.activeBranchName != null
                                  ? Border.all(
                                    color: const Color(
                                      0xFF7C4DFF,
                                    ).withValues(alpha: 0.3),
                                  )
                                  : null,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              widget.activeBranchName != null
                                  ? Icons.alt_route_rounded
                                  : Icons.account_tree_rounded,
                              size: 14,
                              color:
                                  widget.activeBranchName != null
                                      ? const Color(0xFF7C4DFF)
                                      : (isDark
                                          ? Colors.white60
                                          : Colors.black45),
                            ),
                            if (widget.activeBranchName != null) ...[
                              const SizedBox(width: 4),
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 80),
                                child: Text(
                                  widget.activeBranchName!,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF7C4DFF),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    // ☁️ Cloud sync status indicator
                    if (NebulaSyncStateProvider.instance != null)
                      ValueListenableBuilder<NebulaSyncState>(
                        valueListenable:
                            NebulaSyncStateProvider.instance!.state,
                        builder: (context, state, _) {
                          if (state == NebulaSyncState.idle) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: ToolbarCloudSyncIndicator(
                              state: state,
                              progress: 0.0,
                            ),
                          );
                        },
                      ),
                    const SizedBox(width: 4),
                  ],
                  // 📋 MultiView button with theng press (only if callback fornito)
                  if (widget.onMultiViewPressed != null) ...[
                    ToolbarMultiViewCompactButton(
                      onPressed: widget.onMultiViewPressed!,
                      onModeSelected: widget.onMultiViewModeSelected,
                      isDark: isDark,
                    ),
                    const SizedBox(width: 4),
                  ],
                  // 📖 Dual page button (only if callback fornito)
                  if (widget.onDualPagePressed != null) ...[
                    ToolbarCompactActionButton(
                      icon:
                          widget.isDualPageMode
                              ? Icons.view_agenda_rounded
                              : Icons.view_sidebar_rounded,
                      onPressed: widget.onDualPagePressed,
                      tooltip:
                          widget.isDualPageMode
                              ? l10n.proCanvas_singleView
                              : l10n.proCanvas_dualView,
                      isDark: isDark,
                      isEnabled: true,
                    ),
                    const SizedBox(width: 4),
                  ],
                ],

                // Undo/Redo group (+ Image Editor in editing mode)
                Container(
                  decoration: BoxDecoration(
                    color: (isDark ? Colors.white : Colors.black).withValues(
                      alpha: 0.05,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ToolbarCompactActionButton(
                        icon: Icons.undo_rounded,
                        onPressed: widget.canUndo ? widget.onUndo : null,
                        tooltip: l10n.proCanvas_undo,
                        isDark: isDark,
                        isEnabled: widget.canUndo,
                      ),
                      Container(
                        width: 1,
                        height: 18,
                        color: (isDark ? Colors.white : Colors.black)
                            .withValues(alpha: 0.1),
                      ),
                      ToolbarCompactActionButton(
                        icon: Icons.redo_rounded,
                        onPressed: widget.canRedo ? widget.onRedo : null,
                        tooltip: l10n.proCanvas_redo,
                        isDark: isDark,
                        isEnabled: widget.canRedo,
                      ),
                      // 🎨 Pulsante Editor Immagini (only then editing mode)
                      if (widget.isImageEditingMode &&
                          widget.onImageEditorPressed != null) ...[
                        Container(
                          width: 1,
                          height: 18,
                          color: (isDark ? Colors.white : Colors.black)
                              .withValues(alpha: 0.1),
                        ),
                        ToolbarCompactActionButton(
                          icon: Icons.edit_rounded,
                          onPressed: widget.onImageEditorPressed,
                          tooltip: l10n.proCanvas_advancedEditor,
                          isDark: isDark,
                          isEnabled: true,
                        ),
                      ],
                      // ✅ Pulsante "Fatto" per uscire dall'edit mode
                      if (widget.isImageEditingMode &&
                          widget.onExitImageEditMode != null) ...[
                        Container(
                          width: 1,
                          height: 18,
                          color: (isDark ? Colors.white : Colors.black)
                              .withValues(alpha: 0.1),
                        ),
                        ToolbarCompactActionButton(
                          icon: Icons.check_rounded,
                          onPressed: widget.onExitImageEditMode,
                          tooltip: l10n.proCanvas_done,
                          isDark: isDark,
                          isEnabled: true,
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(width: 4),

                // Toggle tools
                ToolbarCompactActionButton(
                  icon:
                      _isToolsExpanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    setState(() => _isToolsExpanded = !_isToolsExpanded);
                  },
                  tooltip:
                      _isToolsExpanded
                          ? l10n.proCanvas_hide
                          : l10n.proCanvas_show,
                  isDark: isDark,
                  isEnabled: true,
                ),

                const SizedBox(width: 4),

                // Settings Dropdown
                ToolbarSettingsDropdown(
                  isDark: isDark,
                  onSettings: widget.onSettings,
                  onBrushSettingsPressed:
                      widget.onBrushSettingsPressed, // 🎛️ Brush settings
                  onExportPressed: widget.onExportPressed, // 📤 Export canvas
                  noteTitle: widget.noteTitle, // 🆕 Pass noteTitle
                  onNoteTitleChanged:
                      widget.onNoteTitleChanged, // 🆕 Pass callback
                  pdfController: widget.pdfController, // 📄 Pass PDF controller
                  onPaperTypePressed:
                      widget.onPaperTypePressed, // 📄 Paper type
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolsArea(BuildContext context, bool isDark) {
    final l10n = NebulaLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Prima riga: strumenti principali
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: [
              // 🖊️ TIPO PENNA
              _buildPenTypeSection(isDark, l10n),

              const SizedBox(width: 12),

              // 🎨 PALETTE COLORI
              _buildColorSection(isDark, l10n),

              const SizedBox(width: 12),

              // 📏 LARGHEZZA
              _buildWidthSection(isDark, l10n),

              const SizedBox(width: 12),

              // � OPACITÀ
              _buildOpacitySection(isDark, l10n),

              const SizedBox(width: 12),

              // �🔷 TOGGLE FORME GEOMETRICHE
              _buildShapesToggleButton(isDark, l10n),
            ],
          ),
        ),

        // Seconda riga: forme geometriche (only if espanse) with animation slide-in
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          child:
              _isShapesExpanded
                  ? AnimatedOpacity(
                    opacity: _isShapesExpanded ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                      decoration: BoxDecoration(
                        color: Colors.deepPurple.withValues(alpha: 0.03),
                        border: Border(
                          top: BorderSide(
                            color: Colors.deepPurple.withValues(alpha: 0.1),
                            width: 1,
                          ),
                        ),
                      ),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: _buildShapeSection(isDark),
                      ),
                    ),
                  )
                  : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildPenTypeSection(bool isDark, NebulaLocalizations l10n) {
    return ToolbarToolSection(
      title: l10n.proCanvas_pen,
      icon: Icons.edit_rounded,
      isDark: isDark,
      child: Row(
        children: [
          // 🎨 Preset-based brush selector
          ToolbarBrushStrip(
            presets: widget.brushPresets,
            selectedPresetId: widget.selectedPresetId,
            isPenActive: !widget.isEraserActive && !widget.isLassoActive,
            onPresetSelected: (preset) {
              HapticFeedback.selectionClick();
              // Disattiva gomma e lasso when attiva la penna
              if (widget.isEraserActive) {
                widget.onEraserToggle();
              }
              if (widget.isLassoActive) {
                widget.onLassoToggle();
              }
              // Apply preset (pen type, width, color, settings)
              widget.onPresetSelected?.call(preset);
            },
            onLongPress: () {
              // 🏛️ Long-press → Open brush settings popup anchored to strip
              HapticFeedback.mediumImpact();
              if (widget.onBrushSettingsPressed != null) {
                final box = context.findRenderObject() as RenderBox;
                final pos = box.localToGlobal(Offset.zero);
                final rect = pos & box.size;
                widget.onBrushSettingsPressed!(rect);
              }
            },
            isDark: isDark,
          ),
          const SizedBox(width: 12),
          // 🖐️ Pan Mode Button (a sinistra della gomma)
          ToolbarPanModeButton(
            isActive: widget.isPanModeActive,
            onTap: () {
              HapticFeedback.selectionClick();
              widget.onPanModeToggle();
            },
            isDark: isDark,
          ),
          const SizedBox(width: 12),
          // 🖊️ Stylus Mode Button (a destra del gesture)
          ToolbarStylusModeButton(
            isActive: widget.isStylusModeActive,
            onTap: () {
              HapticFeedback.selectionClick();
              widget.onStylusModeToggle();
            },
            isDark: isDark,
          ),
          const SizedBox(width: 12),
          ToolbarEraserButton(
            isActive: widget.isEraserActive,
            onTap: () {
              HapticFeedback.selectionClick();
              widget.onEraserToggle();
            },
            isDark: isDark,
          ),
          // 🎚️ Eraser size slider (appears when eraser is active)
          if (widget.isEraserActive &&
              widget.onEraserRadiusChanged != null) ...[
            const SizedBox(width: 8),
            ToolbarEraserSizeSlider(
              radius: widget.eraserRadius,
              onChanged: widget.onEraserRadiusChanged!,
              isDark: isDark,
            ),
            // 🔀 Whole/Partial toggle
            if (widget.onEraseWholeStrokeChanged != null) ...[
              const SizedBox(width: 4),
              ToolbarEraseModeToggle(
                isWholeStroke: widget.eraseWholeStroke,
                onChanged: widget.onEraseWholeStrokeChanged!,
                isDark: isDark,
              ),
            ],
          ],
          const SizedBox(width: 12),
          // Lasso nascosto in editing mode
          if (!widget.isImageEditingMode) ...[
            ToolbarLassoButton(
              isActive: widget.isLassoActive,
              onTap: () {
                HapticFeedback.selectionClick();
                widget.onLassoToggle();
              },
              isDark: isDark,
            ),
            const SizedBox(width: 12),
            // 📏 Ruler toggle
            ToolbarRulerButton(
              isActive: widget.isRulerActive,
              onTap: () {
                HapticFeedback.selectionClick();
                widget.onRulerToggle?.call();
              },
              isDark: isDark,
            ),
            const SizedBox(width: 12),
            // ✒️ Vector Pen Tool toggle
            if (widget.onPenToolToggle != null) ...[
              ToolbarPenToolButton(
                isActive: widget.isPenToolActive,
                onTap: () {
                  HapticFeedback.selectionClick();
                  widget.onPenToolToggle?.call();
                },
                isDark: isDark,
              ),
              const SizedBox(width: 12),
            ],
          ],
          // Digital text, image picker, recording e view recordings nascosti in editing mode
          if (!widget.isImageEditingMode) ...[
            ToolbarDigitalTextButton(
              isActive: widget.isDigitalTextActive,
              onTap: () {
                HapticFeedback.selectionClick();
                widget.onDigitalTextToggle();
              },
              isDark: isDark,
            ),
            const SizedBox(width: 12),
            ToolbarImagePickerButton(
              isActive: widget.isImagePickerActive,
              onTap: () {
                HapticFeedback.selectionClick();
                widget.onImagePickerPressed();
              },
              isDark: isDark,
            ),
            const SizedBox(width: 12),
            if (!widget.hideRecordingControlWhenActive ||
                !widget.isRecordingActive)
              ToolbarRecordingButton(
                isActive: widget.isRecordingActive,
                duration: widget.recordingDuration,
                onTap: () {
                  HapticFeedback.selectionClick();
                  widget.onRecordingPressed();
                },
                isDark: isDark,
              ),
            const SizedBox(width: 12),
            ToolbarViewRecordingsButton(
              onTap: () {
                HapticFeedback.selectionClick();
                widget.onViewRecordingsPressed();
              },
              isDark: isDark,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildShapeSection(bool isDark) {
    return ToolbarToolSection(
      title: NebulaLocalizations.of(context).proCanvas_shapes.toUpperCase(),
      icon: Icons.category_rounded,
      isDark: isDark,
      child: ToolbarShapeTypeSelector(
        selectedType: widget.selectedShapeType,
        onChanged: (type) {
          HapticFeedback.selectionClick();
          widget.onShapeTypeChanged(type);
        },
        isDark: isDark,
      ),
    );
  }

  Widget _buildColorSection(bool isDark, NebulaLocalizations l10n) {
    return ToolbarToolSection(
      title: l10n.proCanvas_color,
      icon: Icons.palette_rounded,
      isDark: isDark,
      child: ToolbarColorPalette(
        colors: _customColors,
        selectedColor: widget.selectedColor,
        onChanged: (color) {
          HapticFeedback.selectionClick();
          widget.onColorChanged(color);
        },
        onLongPress: _showColorPicker,
        isDark: isDark,
      ),
    );
  }

  Widget _buildWidthSection(bool isDark, NebulaLocalizations l10n) {
    return ToolbarToolSection(
      title: l10n.proCanvas_thickness,
      icon: Icons.line_weight,
      isDark: isDark,
      child: ToolbarWidthSlider(
        value: widget.selectedWidth,
        onChanged: widget.onWidthChanged,
        isDark: isDark,
      ),
    );
  }

  Widget _buildOpacitySection(bool isDark, NebulaLocalizations l10n) {
    return ToolbarToolSection(
      title: l10n.proCanvas_opacity,
      icon: Icons.opacity_rounded,
      isDark: isDark,
      child: ToolbarOpacitySlider(
        value: widget.selectedOpacity,
        onChanged: widget.onOpacityChanged,
        isDark: isDark,
      ),
    );
  }

  Widget _buildShapesToggleButton(bool isDark, NebulaLocalizations l10n) {
    return Tooltip(
      message: l10n.proCanvas_geometricShapes,
      waitDuration: const Duration(milliseconds: 500),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.mediumImpact();
            setState(() {
              _isShapesExpanded = !_isShapesExpanded;
              // 🔄 Quando si chiude la sezione forme, torna automaticamente al pennello
              if (!_isShapesExpanded) {
                widget.onShapeTypeChanged(ShapeType.freehand);
              }
            });
          },
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              gradient:
                  _isShapesExpanded
                      ? LinearGradient(
                        colors: [
                          Colors.deepPurple.withValues(alpha: 0.2),
                          Colors.deepPurple.withValues(alpha: 0.1),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                      : null,
              color:
                  _isShapesExpanded
                      ? null
                      : (isDark ? Colors.white : Colors.black).withValues(
                        alpha: 0.05,
                      ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color:
                    _isShapesExpanded
                        ? Colors.deepPurple.withValues(alpha: 0.6)
                        : (isDark ? Colors.white : Colors.black).withValues(
                          alpha: 0.1,
                        ),
                width: _isShapesExpanded ? 2.5 : 1,
              ),
              boxShadow:
                  _isShapesExpanded
                      ? [
                        BoxShadow(
                          color: Colors.deepPurple.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                      : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedRotation(
                  turns: _isShapesExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  child: Icon(
                    Icons.category_rounded,
                    size: 22,
                    color:
                        _isShapesExpanded
                            ? Colors.deepPurple
                            : (isDark ? Colors.white70 : Colors.black54),
                  ),
                ),
                const SizedBox(width: 6),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  style: TextStyle(
                    color:
                        _isShapesExpanded
                            ? Colors.deepPurple
                            : (isDark ? Colors.white70 : Colors.black54),
                    fontWeight:
                        _isShapesExpanded ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 13,
                  ),
                  child: Text(NebulaLocalizations.of(context).proCanvas_shapes),
                ),
                const SizedBox(width: 4),
                AnimatedRotation(
                  turns: _isShapesExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  child: Icon(
                    Icons.arrow_drop_down,
                    size: 20,
                    color:
                        _isShapesExpanded
                            ? Colors.deepPurple
                            : (isDark ? Colors.white70 : Colors.black54),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
