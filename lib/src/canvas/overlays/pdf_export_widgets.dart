part of 'pdf_export_settings_panel.dart';

// ═══════════════════════════════════════════════════════════════════════════
// 📄 PDF Export — Presets, Helper Widgets & Success Overlay
// ═══════════════════════════════════════════════════════════════════════════


// =============================================================================
// EXPORT PRESETS
// =============================================================================

class _ExportPreset {
  final String label;
  final IconData icon;
  final PdfExportFormat format;
  final double jpgQuality;
  final ExportResolution resolution;
  final bool enableCompression;
  final bool onlyAnnotated;

  const _ExportPreset({
    required this.label,
    required this.icon,
    required this.format,
    this.jpgQuality = 0.9,
    this.resolution = ExportResolution.print_,
    this.enableCompression = true,
    this.onlyAnnotated = false,
  });

  static const quickShare = _ExportPreset(
    label: 'Quick Share',
    icon: Icons.send_rounded,
    format: PdfExportFormat.jpg,
    jpgQuality: 0.7,
    resolution: ExportResolution.screen,
  );

  static const printReady = _ExportPreset(
    label: 'Print',
    icon: Icons.print_rounded,
    format: PdfExportFormat.pdf,
    enableCompression: true,
  );

  static const archive = _ExportPreset(
    label: 'Archive',
    icon: Icons.archive_rounded,
    format: PdfExportFormat.png,
    resolution: ExportResolution.ultra,
  );

  static const all = [quickShare, printReady, archive];
}

class _PresetBar extends StatelessWidget {
  final ValueChanged<_ExportPreset> onPreset;

  const _PresetBar({required this.onPreset});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _ExportPreset.all.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final preset = _ExportPreset.all[i];
          return Material(
            color: preset.format.accent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: () => onPreset(preset),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(preset.icon, size: 14, color: preset.format.accent),
                    const SizedBox(width: 6),
                    Text(
                      preset.label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// =============================================================================
// PAGE PREVIEW CARD
// =============================================================================

class _PagePreviewCard extends StatelessWidget {
  final Uint8List imageBytes;
  final PdfExportFormat format;
  final int totalPages;

  const _PagePreviewCard({
    required this.imageBytes,
    required this.format,
    required this.totalPages,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 120,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.15)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Thumbnail image
          Image.memory(
            imageBytes,
            fit: BoxFit.cover,
            errorBuilder:
                (_, __, ___) => Container(
                  color: cs.surfaceContainerHighest,
                  child: Icon(
                    Icons.image_outlined,
                    size: 40,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                  ),
                ),
          ),
          // Gradient overlay
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.55),
                  ],
                  stops: const [0.4, 1.0],
                ),
              ),
            ),
          ),
          // Info overlay
          Positioned(
            left: 10,
            bottom: 8,
            right: 10,
            child: Row(
              children: [
                Icon(Icons.preview_rounded, size: 14, color: Colors.white70),
                const SizedBox(width: 6),
                Text(
                  'Page 1 of $totalPages',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.white70,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: format.accent.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    format.label,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// EXPORT SUCCESS OVERLAY
// =============================================================================

/// Animated success overlay shown after export completes.
///
/// ```dart
/// ExportSuccessOverlay.show(context, format: PdfExportFormat.pdf,
///   fileName: 'document.pdf');
/// ```
class ExportSuccessOverlay extends StatefulWidget {
  final PdfExportFormat format;
  final String fileName;

  const ExportSuccessOverlay({required this.format, required this.fileName});

  static void show(
    BuildContext context, {
    required PdfExportFormat format,
    required String fileName,
  }) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => ExportSuccessOverlay(format: format, fileName: fileName),
    );
    overlay.insert(entry);
    Future.delayed(const Duration(milliseconds: 2500), () {
      entry.remove();
    });
  }

  @override
  State<ExportSuccessOverlay> createState() => ExportSuccessOverlayState();
}

class ExportSuccessOverlayState extends State<ExportSuccessOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scale = Tween<double>(
      begin: 0.5,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut));
    _fade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
      ),
    );
    _ctrl.forward();

    // Auto fade-out
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (mounted) _ctrl.reverse();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      bottom: 0,
      child: IgnorePointer(
        child: Center(
          child: FadeTransition(
            opacity: _fade,
            child: ScaleTransition(
              scale: _scale,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 24,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: widget.format.accent.withValues(alpha: 0.3),
                      blurRadius: 30,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Animated checkmark
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 800),
                      curve: Curves.elasticOut,
                      builder:
                          (_, v, child) =>
                              Transform.scale(scale: v, child: child),
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: widget.format.accent.withValues(alpha: 0.2),
                          border: Border.all(
                            color: widget.format.accent,
                            width: 2,
                          ),
                        ),
                        child: Icon(
                          Icons.check_rounded,
                          color: widget.format.accent,
                          size: 32,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Export Complete',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.fileName,
                      style: TextStyle(fontSize: 12, color: Colors.white60),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      margin: const EdgeInsets.only(top: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: widget.format.accent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        widget.format.label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: widget.format.accent,
                          letterSpacing: 0.5,
                        ),
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

/// Format selector with animated cards.
class _FormatSelector extends StatelessWidget {
  final PdfExportFormat value;
  final ValueChanged<PdfExportFormat> onChanged;

  const _FormatSelector({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      children:
          PdfExportFormat.values.map((format) {
            final isSelected = format == value;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: format != PdfExportFormat.values.last ? 8 : 0,
                ),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  decoration: BoxDecoration(
                    gradient:
                        isSelected
                            ? LinearGradient(
                              colors: [
                                cs.primaryContainer,
                                cs.primaryContainer.withValues(alpha: 0.6),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                            : null,
                    color:
                        isSelected
                            ? null
                            : cs.surfaceContainerHighest.withValues(
                              alpha: 0.35,
                            ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color:
                          isSelected
                              ? cs.primary.withValues(alpha: 0.4)
                              : cs.outlineVariant.withValues(alpha: 0.15),
                      width: isSelected ? 1.5 : 1,
                    ),
                    boxShadow:
                        isSelected
                            ? [
                              BoxShadow(
                                color: cs.primary.withValues(alpha: 0.12),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ]
                            : null,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => onChanged(format),
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedScale(
                              scale: isSelected ? 1.1 : 1.0,
                              duration: const Duration(milliseconds: 200),
                              child: Icon(
                                format.icon,
                                size: 24,
                                color:
                                    isSelected
                                        ? cs.primary
                                        : cs.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              format.label,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight:
                                    isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                color:
                                    isSelected
                                        ? cs.primary
                                        : cs.onSurfaceVariant,
                                letterSpacing: isSelected ? 0.5 : 0,
                              ),
                            ),
                            // Selection indicator dot
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.only(top: 4),
                              width: isSelected ? 6 : 0,
                              height: isSelected ? 6 : 0,
                              decoration: BoxDecoration(
                                color: cs.primary,
                                shape: BoxShape.circle,
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
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;
  final String? info;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.info,
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
          if (info != null)
            Tooltip(
              message: info!,
              preferBelow: false,
              triggerMode: TooltipTriggerMode.tap,
              showDuration: const Duration(seconds: 4),
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: colorScheme.primary.withValues(alpha: 0.6),
                ),
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
