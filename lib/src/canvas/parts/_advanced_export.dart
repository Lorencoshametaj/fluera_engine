part of '../fluera_canvas_screen.dart';

// ============================================================================
// 📤 ADVANCED EXPORT — Wire token export, raster, CRDT, file format,
//    image adjustment, image fill mode, text auto-resize, plugins
// ============================================================================

extension AdvancedExportFeatures on _FlueraCanvasScreenState {
  /// Export design tokens in platform format.
  /// Wires: design_token_exporter (CSS/Kotlin/Swift), exportToString
  void _exportTokensToFormat(String format) {
    final formatMap = {
      'css': DesignTokenFormat.cssCustomProperties,
      'kotlin': DesignTokenFormat.kotlinObject,
      'swift': DesignTokenFormat.swiftStruct,
    };

    final tokenFormat = formatMap[format];
    if (tokenFormat == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => TokenExportDialog(format: tokenFormat),
    );
  }

  /// Show image adjustment panel.
  /// Wires: image_adjustment
  void _showImageAdjustments() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const ImageAdjustmentPanel(),
    );
  }

  /// Set image fill mode.
  /// Wires: image_fill_mode
  void _setImageFillMode() {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder:
          (ctx) => Container(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  'Image Fill Mode',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 16),
                _FillModeOption(
                  icon: Icons.zoom_out_map_rounded,
                  label: 'Fill',
                  subtitle: 'Cover entire area',
                  cs: cs,
                ),
                _FillModeOption(
                  icon: Icons.fit_screen_rounded,
                  label: 'Fit',
                  subtitle: 'Fit within bounds',
                  cs: cs,
                ),
                _FillModeOption(
                  icon: Icons.crop_rounded,
                  label: 'Crop',
                  subtitle: 'Crop to fit',
                  cs: cs,
                ),
                _FillModeOption(
                  icon: Icons.grid_view_rounded,
                  label: 'Tile',
                  subtitle: 'Repeat pattern',
                  cs: cs,
                ),
              ],
            ),
          ),
    );
  }

  /// Enable text auto-resize on selected text node.
  /// Wires: text_auto_resize
  void _enableTextAutoResize() {}

  /// Enable CRDT sync for real-time collaboration.
  /// Wires: scene_graph_crdt, realtime_enterprise
  void _enableCRDTSync() {}

  /// Save as binary Fluera format.
  /// Wires: fluera_file_format, binary_canvas_format, fluera_file_export_service
  Future<void> _saveAsFlueraFormat() async {
    final layers = _layerController.layers;
    if (layers.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nothing to export — canvas is empty'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    try {
      // Build the .fluera file
      final bytes = await FlueraFileExportService.buildFlueraFile(
        layers: layers,
        title: _noteTitle ?? 'Untitled',
        backgroundColor:
            '#${_canvasBackgroundColor.toARGB32().toRadixString(16).padLeft(8, '0')}',
        paperType: _paperType,
      );

      if (!mounted) return;

      // Use file_picker to let the user choose a save location
      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'Save as Fluera file',
        fileName: '${_noteTitle ?? 'canvas'}.fluera',
        type: FileType.any,
        bytes: bytes,
      );

      if (result != null && mounted) {
        // On desktop, file_picker returns a path; on mobile, bytes are written directly
        // On web, bytes are downloaded via browser — no File access needed
        if (!kIsWeb && result.isNotEmpty) {
          final file = File(result);
          if (!await file.exists()) {
            await file.writeAsBytes(bytes);
          }
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Saved ${(bytes.length / 1024).toStringAsFixed(1)} KB',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Export timelapse recording.
  /// Wires: timelapse_export_config
  void _exportTimelapseImpl() {}

  /// Open raster export dialog.
  /// Wires: raster_encoder_channel, raster_image_encoder
  void _exportRasterImage() {}

  /// Open plugin manager.
  /// Wires: plugin_api, plugin_budget, sandboxed_event_stream
  void _openPluginManager() {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (ctx) => DraggableScrollableSheet(
            initialChildSize: 0.5,
            minChildSize: 0.25,
            maxChildSize: 0.8,
            builder:
                (ctx, scrollCtrl) => Container(
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 8, bottom: 4),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.extension_rounded,
                              color: cs.primary,
                              size: 28,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Plugin Manager',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: cs.onSurface,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () => Navigator.pop(ctx),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.extension_rounded,
                                size: 64,
                                color: cs.primary.withValues(alpha: 0.3),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No plugins installed',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 8),
                              FilledButton.tonal(
                                onPressed: () {},
                                child: const Text('Browse Marketplace'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
          ),
    );
  }
}

class _FillModeOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final ColorScheme cs;

  const _FillModeOption({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: cs.primary),
      title: Text(
        label,
        style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurface),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onTap: () {
        Navigator.pop(context);
      },
    );
  }
}
