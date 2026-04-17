library pdf_export_settings_panel;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../export/export_pipeline.dart';
import '../../export/pdf_export_writer.dart';
import '../fluera_canvas_config.dart';
import '../../l10n/fluera_localizations.dart';

part 'pdf_export_widgets.dart';


/// 📄 PDF Export Settings Panel — Embeddable widget for any host app.
///
/// Provides Material 3 controls for all PDF-specific export features.
/// The host app embeds this widget inside its own export dialog/sheet.
///
/// ```dart
/// PdfExportSettingsPanel(
///   onConfigChanged: (config) => setState(() => _pdfConfig = config),
/// )
/// ```
class PdfExportSettingsPanel extends StatefulWidget {
  /// Called whenever a PDF setting changes.
  final ValueChanged<PdfExportConfig> onConfigChanged;

  /// Initial configuration (optional).
  final PdfExportConfig? initialConfig;

  const PdfExportSettingsPanel({
    super.key,
    required this.onConfigChanged,
    this.initialConfig,
  });

  @override
  State<PdfExportSettingsPanel> createState() => _PdfExportSettingsPanelState();
}

class _PdfExportSettingsPanelState extends State<PdfExportSettingsPanel> {
  late PdfExportConfig _config;
  late TextEditingController _watermarkController;
  late TextEditingController _titleController;
  late TextEditingController _authorController;

  @override
  void initState() {
    super.initState();
    _config = widget.initialConfig ?? const PdfExportConfig();
    _watermarkController = TextEditingController(text: _config.watermarkText);
    _titleController = TextEditingController(text: _config.title);
    _authorController = TextEditingController(text: _config.author);
  }

  @override
  void dispose() {
    _watermarkController.dispose();
    _titleController.dispose();
    _authorController.dispose();
    super.dispose();
  }

  void _updateConfig(PdfExportConfig newConfig) {
    setState(() => _config = newConfig);
    widget.onConfigChanged(newConfig);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header
        Row(
          children: [
            Icon(Icons.picture_as_pdf, color: colorScheme.primary, size: 20),
            const SizedBox(width: 8),
            Text(
              'PDF Settings',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // ── Metadata ──
        _SectionHeader(label: 'Metadata', icon: Icons.info_outline),
        const SizedBox(height: 8),
        _CompactTextField(
          controller: _titleController,
          label: 'Title',
          icon: Icons.title,
          onChanged: (v) => _updateConfig(_config.copyWith(title: v)),
        ),
        const SizedBox(height: 8),
        _CompactTextField(
          controller: _authorController,
          label: 'Author',
          icon: Icons.person_outline,
          onChanged: (v) => _updateConfig(_config.copyWith(author: v)),
        ),
        const SizedBox(height: 16),

        // ── Export Scope ──
        _SectionHeader(label: 'Scope', icon: Icons.filter_alt_outlined),
        const SizedBox(height: 8),
        _SettingsTile(
          icon: Icons.edit_note_rounded,
          title: 'Only Annotated Pages',
          subtitle: 'Skip pages without annotations',
          info:
              'When enabled, pages that have no drawn annotations '
              'will be excluded from the exported PDF. Useful to reduce '
              'file size when only a few pages have notes.',
          trailing: Switch.adaptive(
            value: _config.onlyAnnotatedPages,
            onChanged:
                (v) => _updateConfig(_config.copyWith(onlyAnnotatedPages: v)),
          ),
        ),
        const SizedBox(height: 16),

        // ── Quality & Format ──
        _SectionHeader(label: 'Quality', icon: Icons.high_quality_outlined),
        const SizedBox(height: 8),

        // ── PDF/A Conformance ──
        _SettingsTile(
          icon: Icons.verified_outlined,
          title: 'PDF/A-1b Archival',
          subtitle: 'Long-term preservation',
          info:
              'Ensures the PDF conforms to the PDF/A-1b ISO standard '
              'for long-term digital preservation. Embeds all fonts and '
              'disables features that could become obsolete.',
          trailing: Switch.adaptive(
            value: _config.pdfAConformance,
            onChanged:
                (v) => _updateConfig(_config.copyWith(pdfAConformance: v)),
          ),
        ),
        const SizedBox(height: 4),

        // ── Compression ──
        _SettingsTile(
          icon: Icons.compress,
          title: 'Compression',
          subtitle: 'Flate/ZLib stream compression',
          info:
              'Applies ZLib (Flate) compression to PDF content streams. '
              'Reduces file size significantly with no quality loss. '
              'Disable only for debugging or maximum compatibility.',
          trailing: Switch.adaptive(
            value: _config.enableCompression,
            onChanged:
                (v) => _updateConfig(_config.copyWith(enableCompression: v)),
          ),
        ),
        const SizedBox(height: 16),

        // ── Watermark ──
        _SectionHeader(label: 'Watermark', icon: Icons.water_drop_outlined),
        const SizedBox(height: 8),
        _SettingsTile(
          icon: Icons.text_fields,
          title: 'Enable Watermark',
          subtitle: 'Overlay text on all pages',
          info:
              'Adds a semi-transparent text overlay on every page. '
              'Useful for marking documents as DRAFT, CONFIDENTIAL, '
              'or with your name/organization.',
          trailing: Switch.adaptive(
            value: _config.enableWatermark,
            onChanged: (v) {
              _updateConfig(_config.copyWith(enableWatermark: v));
            },
          ),
        ),
        if (_config.enableWatermark) ...[
          const SizedBox(height: 8),
          _CompactTextField(
            controller: _watermarkController,
            label: 'Watermark Text',
            icon: Icons.text_snippet_outlined,
            onChanged: (v) => _updateConfig(_config.copyWith(watermarkText: v)),
          ),
          const SizedBox(height: 8),
          _WatermarkPositionSelector(
            value: _config.watermarkPosition,
            onChanged:
                (v) => _updateConfig(_config.copyWith(watermarkPosition: v)),
          ),
          const SizedBox(height: 8),
          _OpacitySlider(
            value: _config.watermarkOpacity,
            onChanged:
                (v) => _updateConfig(_config.copyWith(watermarkOpacity: v)),
          ),
        ],
      ],
    );
  }
}

// =============================================================================
// EXPORT FORMAT
// =============================================================================

/// Supported export formats for PDF document export.
enum PdfExportFormat {
  pdf(
    'PDF',
    Icons.picture_as_pdf_rounded,
    'application/pdf',
    'pdf',
    'Vector \u2022 Scalable',
    Color(0xFFE53935),
  ),
  jpg(
    'JPG',
    Icons.image_rounded,
    'image/jpeg',
    'jpg',
    'Lossy \u2022 Smaller files',
    Color(0xFFFFA726),
  ),
  png(
    'PNG',
    Icons.image_outlined,
    'image/png',
    'png',
    'Lossless \u2022 Best quality',
    Color(0xFF26A69A),
  ),
  svg(
    'SVG',
    Icons.polyline_rounded,
    'image/svg+xml',
    'svg',
    'Vector \u2022 Editable',
    Color(0xFF5C6BC0),
  );

  final String label;
  final IconData icon;
  final String mimeType;
  final String extension;
  final String subtitle;
  final Color accent;

  const PdfExportFormat(
    this.label,
    this.icon,
    this.mimeType,
    this.extension,
    this.subtitle,
    this.accent,
  );
}

/// Export resolution presets for image formats.
enum ExportResolution {
  screen('Screen', '1×', 1.0, Icons.phone_android_rounded),
  print_('Print', '2×', 2.0, Icons.print_rounded),
  ultra('Ultra', '3×', 3.0, Icons.hd_rounded);

  final String label;
  final String badge;
  final double multiplier;
  final IconData icon;

  const ExportResolution(this.label, this.badge, this.multiplier, this.icon);
}

// =============================================================================
// PDF EXPORT CONFIG (UI-level model)
// =============================================================================

/// Configuration model for PDF export settings.
///
/// This is the UI-facing model used by [PdfExportSettingsPanel].
/// It gets applied to [PdfExportWriter] via the [applyToWriter] method.
class PdfExportConfig {
  final String? title;
  final String? author;
  final String? fileName;
  final PdfExportFormat format;
  final double jpgQuality;
  final ExportResolution resolution;
  final bool pdfAConformance;
  final bool enableCompression;
  final bool enableWatermark;
  final String? watermarkText;
  final WatermarkPosition watermarkPosition;
  final double watermarkOpacity;
  final bool onlyAnnotatedPages;

  const PdfExportConfig({
    this.title,
    this.author,
    this.fileName,
    this.format = PdfExportFormat.pdf,
    this.jpgQuality = 0.9,
    this.resolution = ExportResolution.print_,
    this.pdfAConformance = false,
    this.enableCompression = true,
    this.enableWatermark = false,
    this.watermarkText,
    this.watermarkPosition = WatermarkPosition.diagonal,
    this.watermarkOpacity = 0.15,
    this.onlyAnnotatedPages = false,
  });

  PdfExportConfig copyWith({
    String? title,
    String? author,
    String? fileName,
    PdfExportFormat? format,
    double? jpgQuality,
    ExportResolution? resolution,
    bool? pdfAConformance,
    bool? enableCompression,
    bool? enableWatermark,
    String? watermarkText,
    WatermarkPosition? watermarkPosition,
    double? watermarkOpacity,
    bool? onlyAnnotatedPages,
  }) {
    return PdfExportConfig(
      title: title ?? this.title,
      author: author ?? this.author,
      fileName: fileName ?? this.fileName,
      format: format ?? this.format,
      jpgQuality: jpgQuality ?? this.jpgQuality,
      resolution: resolution ?? this.resolution,
      pdfAConformance: pdfAConformance ?? this.pdfAConformance,
      enableCompression: enableCompression ?? this.enableCompression,
      enableWatermark: enableWatermark ?? this.enableWatermark,
      watermarkText: watermarkText ?? this.watermarkText,
      watermarkPosition: watermarkPosition ?? this.watermarkPosition,
      watermarkOpacity: watermarkOpacity ?? this.watermarkOpacity,
      onlyAnnotatedPages: onlyAnnotatedPages ?? this.onlyAnnotatedPages,
    );
  }

  /// Apply this configuration to a [PdfExportWriter].
  void applyToWriter(PdfExportWriter writer) {
    writer.pdfAConformance = pdfAConformance;

    if (enableWatermark && watermarkText != null && watermarkText!.isNotEmpty) {
      writer.setWatermark(
        PdfWatermark(
          text: watermarkText!,
          position: watermarkPosition,
          opacity: watermarkOpacity,
        ),
      );
    }
  }
}

// =============================================================================
// READY-TO-USE EXPORT DIALOG
// =============================================================================

/// 📄 Ready-to-use export dialog with format selection (PDF/JPG/PNG).
///
/// ```dart
/// final config = await PdfExportDialog.show(context,
///   defaultFileName: 'My Doc', totalPages: 5);
/// if (config != null) { /* export */ }
/// ```
class PdfExportDialog extends StatefulWidget {
  final String? defaultFileName;
  final int totalPages;
  final Uint8List? firstPagePreview;
  final FlueraSubscriptionTier subscriptionTier;

  const PdfExportDialog({
    super.key,
    this.defaultFileName,
    this.totalPages = 0,
    this.firstPagePreview,
    this.subscriptionTier = FlueraSubscriptionTier.free,
  });

  static Future<PdfExportConfig?> show(
    BuildContext context, {
    String? defaultFileName,
    int totalPages = 0,
    Uint8List? firstPagePreview,
    FlueraSubscriptionTier subscriptionTier = FlueraSubscriptionTier.free,
  }) {
    return showModalBottomSheet<PdfExportConfig>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (_) => PdfExportDialog(
            defaultFileName: defaultFileName,
            totalPages: totalPages,
            firstPagePreview: firstPagePreview,
            subscriptionTier: subscriptionTier,
          ),
    );
  }

  @override
  State<PdfExportDialog> createState() => _PdfExportDialogState();
}

class _PdfExportDialogState extends State<PdfExportDialog>
    with SingleTickerProviderStateMixin {
  late PdfExportConfig _config;
  late TextEditingController _fileNameController;
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    final baseName = widget.defaultFileName?.replaceAll(
      RegExp(r'\.pdf$', caseSensitive: false),
      '',
    );
    _config = PdfExportConfig(fileName: baseName, title: baseName);
    _fileNameController = TextEditingController(text: baseName ?? '');
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    )..forward();
  }

  @override
  void dispose() {
    _fileNameController.dispose();
    _animController.dispose();
    super.dispose();
  }

  String get _fullFileName {
    final name =
        _config.fileName?.isNotEmpty == true ? _config.fileName! : 'export';
    return '$name.${_config.format.extension}';
  }

  Color get _accent => _config.format.accent;

  void _applyPreset(_ExportPreset preset) {
    HapticFeedback.mediumImpact();
    _fileNameController.text = _config.fileName ?? '';
    setState(() {
      _config = _config.copyWith(
        format: preset.format,
        jpgQuality: preset.jpgQuality,
        resolution: preset.resolution,
        enableCompression: preset.enableCompression,
        onlyAnnotatedPages: preset.onlyAnnotated,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final mq = MediaQuery.of(context);
    final bottomPadding = mq.viewInsets.bottom;
    final maxHeight =
        mq.size.height - mq.padding.top - 24; // 24px breathing room

    return FadeTransition(
      opacity: CurvedAnimation(parent: _animController, curve: Curves.easeOut),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.06),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            padding: EdgeInsets.only(bottom: bottomPadding),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: _accent.withValues(alpha: 0.08),
                width: 1.5,
              ),
              boxShadow: [
                // Format-colored ambient glow
                BoxShadow(
                  color: _accent.withValues(alpha: 0.1),
                  blurRadius: 50,
                  spreadRadius: -5,
                  offset: const Offset(0, -8),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 24,
                  offset: const Offset(0, -3),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Animated Gradient Handle ──
                Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 2),
                  width: 40,
                  height: 4.5,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        _accent.withValues(alpha: 0.15),
                        _accent.withValues(alpha: 0.35),
                        _accent.withValues(alpha: 0.15),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),

                // ── Header with accent wash ──
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        _accent.withValues(alpha: 0.04),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 12, 14, 14),
                  child: Row(
                    children: [
                      // Animated format icon in circle
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _accent.withValues(alpha: 0.1),
                        ),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          transitionBuilder:
                              (w, a) => ScaleTransition(scale: a, child: w),
                          child: Icon(
                            _config.format.icon,
                            key: ValueKey(_config.format),
                            color: _accent,
                            size: 22,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Export Document',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                                fontSize: 17,
                              ),
                            ),
                            const SizedBox(height: 2),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              child: Text(
                                widget.totalPages > 0
                                    ? '${widget.totalPages} ${widget.totalPages == 1 ? "page" : "pages"} \u2022 ${_config.format.label} \u2022 ${_config.format.subtitle}'
                                    : _config.format.subtitle,
                                key: ValueKey('${_config.format}_sub'),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant.withValues(
                                    alpha: 0.7,
                                  ),
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Export CTA — gradient with glow
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: _accent.withValues(alpha: 0.35),
                              blurRadius: 12,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: FilledButton.icon(
                          onPressed: () => Navigator.pop(context, _config),
                          icon: const Icon(Icons.ios_share_rounded, size: 16),
                          label: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 150),
                            child: Text(
                              'Export ${_config.format.label}',
                              key: ValueKey(_config.format.label),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: _accent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Gradient Divider ──
                Container(
                  height: 1,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        _accent.withValues(alpha: 0.15),
                        _accent.withValues(alpha: 0.15),
                        Colors.transparent,
                      ],
                      stops: const [0, 0.2, 0.8, 1],
                    ),
                  ),
                ),

                // ── Content ──
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ── Quick Presets ──
                        _PresetBar(onPreset: _applyPreset),
                        const SizedBox(height: 16),

                        // ── Thumbnail Preview ──
                        if (widget.firstPagePreview != null) ...[
                          _PagePreviewCard(
                            imageBytes: widget.firstPagePreview!,
                            format: _config.format,
                            totalPages: widget.totalPages,
                          ),
                          const SizedBox(height: 16),
                        ],

                        // ── File Name ── (Section Card)
                        _sectionCard(
                          cs,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _SectionHeader(
                                label: 'File Name',
                                icon: Icons.drive_file_rename_outline,
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: _CompactTextField(
                                      controller: _fileNameController,
                                      label: 'File name',
                                      icon: Icons.description_outlined,
                                      onChanged:
                                          (v) => setState(() {
                                            _config = _config.copyWith(
                                              fileName: v,
                                              title: v,
                                            );
                                          }),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 200),
                                    transitionBuilder:
                                        (w, a) => FadeTransition(
                                          opacity: a,
                                          child: ScaleTransition(
                                            scale: a,
                                            child: w,
                                          ),
                                        ),
                                    child: Container(
                                      key: ValueKey(_config.format.extension),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            _accent.withValues(alpha: 0.2),
                                            _accent.withValues(alpha: 0.1),
                                          ],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: _accent.withValues(alpha: 0.3),
                                        ),
                                      ),
                                      child: Text(
                                        '.${_config.format.extension}',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: _accent,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              // Preview filename
                              Padding(
                                padding: const EdgeInsets.only(left: 4, top: 5),
                                child: Text(
                                  _fullFileName,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: cs.onSurfaceVariant.withValues(
                                      alpha: 0.5,
                                    ),
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 12),

                        // ── Format Selector ── (Section Card)
                        _sectionCard(
                          cs,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _SectionHeader(
                                label: 'Format',
                                icon: Icons.file_present_rounded,
                              ),
                              const SizedBox(height: 10),
                              _FormatSelector(
                                value: _config.format,
                                subscriptionTier: widget.subscriptionTier,
                                onChanged: (f) {
                                  HapticFeedback.selectionClick();
                                  setState(() {
                                    _config = _config.copyWith(format: f);
                                  });
                                },
                              ),
                            ],
                          ),
                        ),

                        AnimatedSize(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOutCubic,
                          alignment: Alignment.topCenter,
                          child:
                              _config.format != PdfExportFormat.pdf &&
                                      _config.format != PdfExportFormat.svg
                                  ? _buildResolutionSelector(cs)
                                  : const SizedBox.shrink(),
                        ),

                        // ── JPG Quality (conditional) ──
                        AnimatedSize(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOutCubic,
                          alignment: Alignment.topCenter,
                          child:
                              _config.format == PdfExportFormat.jpg
                                  ? _buildJpgQualitySlider(cs)
                                  : const SizedBox.shrink(),
                        ),

                        // ── PNG info (conditional) ──
                        AnimatedSize(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOutCubic,
                          alignment: Alignment.topCenter,
                          child:
                              _config.format == PdfExportFormat.png
                                  ? _buildPngInfo(cs)
                                  : const SizedBox.shrink(),
                        ),

                        // ── Estimated size ──
                        if (widget.totalPages > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: _buildEstimatedSize(cs),
                          ),

                        const SizedBox(height: 14),

                        // ── PDF Settings (conditional) ──
                        AnimatedSize(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOutCubic,
                          alignment: Alignment.topCenter,
                          child:
                              _config.format == PdfExportFormat.pdf
                                  ? PdfExportSettingsPanel(
                                    initialConfig: _config,
                                    onConfigChanged:
                                        (c) => setState(() => _config = c),
                                  )
                                  : const SizedBox.shrink(),
                        ),

                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionCard(ColorScheme cs, {required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.08)),
      ),
      child: child,
    );
  }

  Widget _buildJpgQualitySlider(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tune_rounded, size: 16, color: cs.onSurfaceVariant),
                const SizedBox(width: 8),
                Text(
                  'Quality',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${(_config.jpgQuality * 100).round()}%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: cs.primary,
                    ),
                  ),
                ),
              ],
            ),
            SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                activeTrackColor: cs.primary,
                inactiveTrackColor: cs.onSurfaceVariant.withValues(alpha: 0.15),
                thumbColor: cs.primary,
              ),
              child: Slider(
                value: _config.jpgQuality,
                min: 0.3,
                max: 1.0,
                divisions: 7,
                onChanged:
                    (v) => setState(() {
                      _config = _config.copyWith(jpgQuality: v);
                    }),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Smaller',
                    style: TextStyle(
                      fontSize: 10,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  Text(
                    _config.jpgQuality >= 0.9
                        ? 'Maximum quality'
                        : _config.jpgQuality >= 0.7
                        ? 'High quality'
                        : _config.jpgQuality >= 0.5
                        ? 'Balanced'
                        : 'Compact',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                  ),
                  Text(
                    'Larger',
                    style: TextStyle(
                      fontSize: 10,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  Widget _buildPngInfo(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.tertiaryContainer.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.tertiary.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline_rounded, size: 16, color: cs.tertiary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Lossless quality • Best for screenshots and editing',
                style: TextStyle(
                  fontSize: 11,
                  color: cs.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResolutionSelector(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(label: 'Resolution', icon: Icons.aspect_ratio_rounded),
          const SizedBox(height: 8),
          Row(
            children:
                ExportResolution.values.map((res) {
                  final isSelected = res == _config.resolution;
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        right: res != ExportResolution.values.last ? 6 : 0,
                      ),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        decoration: BoxDecoration(
                          color:
                              isSelected
                                  ? cs.secondaryContainer.withValues(alpha: 0.7)
                                  : cs.surfaceContainerHighest.withValues(
                                    alpha: 0.3,
                                  ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color:
                                isSelected
                                    ? cs.secondary.withValues(alpha: 0.4)
                                    : cs.outlineVariant.withValues(alpha: 0.12),
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() {
                                _config = _config.copyWith(resolution: res);
                              });
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    res.icon,
                                    size: 18,
                                    color:
                                        isSelected
                                            ? cs.secondary
                                            : cs.onSurfaceVariant,
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    res.label,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight:
                                          isSelected
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                      color:
                                          isSelected
                                              ? cs.secondary
                                              : cs.onSurfaceVariant,
                                    ),
                                  ),
                                  Text(
                                    res.badge,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: (isSelected
                                              ? cs.secondary
                                              : cs.onSurfaceVariant)
                                          .withValues(alpha: 0.6),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildEstimatedSize(ColorScheme cs) {
    // Rough estimation based on format, quality, resolution, and page count
    final pages = widget.totalPages;
    final resMult = _config.resolution.multiplier;

    double sizePerPageMb;
    switch (_config.format) {
      case PdfExportFormat.pdf:
        sizePerPageMb = 0.8;
      case PdfExportFormat.jpg:
        sizePerPageMb = 0.3 * _config.jpgQuality * resMult * resMult;
      case PdfExportFormat.png:
        sizePerPageMb = 1.5 * resMult * resMult;
      case PdfExportFormat.svg:
        sizePerPageMb = 2.0 * resMult * resMult;
    }

    final totalMb = sizePerPageMb * pages;
    final sizeStr =
        totalMb < 1
            ? '~${(totalMb * 1024).round()} KB'
            : '~${totalMb.toStringAsFixed(1)} MB';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            Icons.storage_rounded,
            size: 15,
            color: cs.onSurfaceVariant.withValues(alpha: 0.6),
          ),
          const SizedBox(width: 8),
          Text(
            'Estimated: $sizeStr',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: cs.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          Text(
            '$pages ${pages == 1 ? "page" : "pages"} • ${_config.format.label} ${_config.resolution.badge}',
            style: TextStyle(
              fontSize: 10,
              color: cs.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}
