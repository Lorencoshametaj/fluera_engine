import 'package:flutter/material.dart';
import '../../export/export_pipeline.dart';
import '../../export/pdf_export_writer.dart';

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

        // ── PDF/A Conformance ──
        _SettingsTile(
          icon: Icons.verified_outlined,
          title: 'PDF/A-1b Archival',
          subtitle: 'Long-term preservation',
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
// PDF EXPORT CONFIG (UI-level model)
// =============================================================================

/// Configuration model for PDF export settings.
///
/// This is the UI-facing model used by [PdfExportSettingsPanel].
/// It gets applied to [PdfExportWriter] via the [applyToWriter] method.
class PdfExportConfig {
  final String? title;
  final String? author;
  final bool pdfAConformance;
  final bool enableCompression;
  final bool enableWatermark;
  final String? watermarkText;
  final WatermarkPosition watermarkPosition;
  final double watermarkOpacity;

  const PdfExportConfig({
    this.title,
    this.author,
    this.pdfAConformance = false,
    this.enableCompression = true,
    this.enableWatermark = false,
    this.watermarkText,
    this.watermarkPosition = WatermarkPosition.diagonal,
    this.watermarkOpacity = 0.15,
  });

  PdfExportConfig copyWith({
    String? title,
    String? author,
    bool? pdfAConformance,
    bool? enableCompression,
    bool? enableWatermark,
    String? watermarkText,
    WatermarkPosition? watermarkPosition,
    double? watermarkOpacity,
  }) {
    return PdfExportConfig(
      title: title ?? this.title,
      author: author ?? this.author,
      pdfAConformance: pdfAConformance ?? this.pdfAConformance,
      enableCompression: enableCompression ?? this.enableCompression,
      enableWatermark: enableWatermark ?? this.enableWatermark,
      watermarkText: watermarkText ?? this.watermarkText,
      watermarkPosition: watermarkPosition ?? this.watermarkPosition,
      watermarkOpacity: watermarkOpacity ?? this.watermarkOpacity,
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

/// 📄 Ready-to-use PDF export dialog.
///
/// Any host app can show this with:
/// ```dart
/// final config = await PdfExportDialog.show(context);
/// if (config != null) {
///   // Use config to export
/// }
/// ```
class PdfExportDialog extends StatefulWidget {
  const PdfExportDialog({super.key});

  /// Show the dialog and return the chosen config, or null if cancelled.
  static Future<PdfExportConfig?> show(BuildContext context) {
    return showModalBottomSheet<PdfExportConfig>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const PdfExportDialog(),
    );
  }

  @override
  State<PdfExportDialog> createState() => _PdfExportDialogState();
}

class _PdfExportDialogState extends State<PdfExportDialog> {
  PdfExportConfig _config = const PdfExportConfig();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: EdgeInsets.only(bottom: bottomPadding),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Title bar
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
            child: Row(
              children: [
                Icon(
                  Icons.picture_as_pdf_rounded,
                  color: colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 10),
                Text(
                  'PDF Export',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => Navigator.pop(context, _config),
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Export'),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Settings panel
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: PdfExportSettingsPanel(
                initialConfig: _config,
                onConfigChanged: (c) => setState(() => _config = c),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// PRIVATE SUB-WIDGETS
// =============================================================================

class _SectionHeader extends StatelessWidget {
  final String label;
  final IconData icon;

  const _SectionHeader({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 14, color: colorScheme.primary.withValues(alpha: 0.7)),
        const SizedBox(width: 6),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: colorScheme.primary.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}

class _CompactTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final ValueChanged<String> onChanged;

  const _CompactTextField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          fontSize: 12,
          color: colorScheme.onSurfaceVariant,
        ),
        prefixIcon: Icon(icon, size: 18),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: colorScheme.outline.withValues(alpha: 0.3),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: colorScheme.outline.withValues(alpha: 0.3),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
      ),
    );
  }
}

class _WatermarkPositionSelector extends StatelessWidget {
  final WatermarkPosition value;
  final ValueChanged<WatermarkPosition> onChanged;

  const _WatermarkPositionSelector({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Icon(
          Icons.place_outlined,
          size: 16,
          color: colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        const Text('Position', style: TextStyle(fontSize: 12)),
        const Spacer(),
        SegmentedButton<WatermarkPosition>(
          segments: const [
            ButtonSegment(
              value: WatermarkPosition.diagonal,
              icon: Icon(Icons.rotate_left, size: 16),
              label: Text('Diagonal', style: TextStyle(fontSize: 11)),
            ),
            ButtonSegment(
              value: WatermarkPosition.center,
              icon: Icon(Icons.center_focus_strong, size: 16),
              label: Text('Center', style: TextStyle(fontSize: 11)),
            ),
            ButtonSegment(
              value: WatermarkPosition.tiled,
              icon: Icon(Icons.grid_view, size: 16),
              label: Text('Tiled', style: TextStyle(fontSize: 11)),
            ),
          ],
          selected: {value},
          onSelectionChanged: (s) => onChanged(s.first),
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ],
    );
  }
}

class _OpacitySlider extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;

  const _OpacitySlider({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Icon(Icons.opacity, size: 16, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Text(
          'Opacity ${(value * 100).round()}%',
          style: const TextStyle(fontSize: 12),
        ),
        Expanded(
          child: Slider.adaptive(
            value: value,
            min: 0.05,
            max: 0.5,
            divisions: 9,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
