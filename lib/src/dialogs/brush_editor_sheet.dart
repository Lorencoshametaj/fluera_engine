import 'package:flutter/material.dart';
import '../drawing/models/brush_preset.dart';
import '../drawing/models/pro_brush_settings.dart';
import '../drawing/models/pro_drawing_point.dart';
import '../drawing/services/brush_preset_manager.dart';

/// 🎨 Phase 4C: Brush Editor Bottom Sheet
///
/// Full brush editor with preset carousel, live preview, and
/// comprehensive parameter controls. Opens from long-press on
/// pen type buttons in the toolbar.
class BrushEditorSheet extends StatefulWidget {
  final ProPenType currentPenType;
  final double currentBaseWidth;
  final Color currentColor;
  final ProBrushSettings currentSettings;
  final ValueChanged<BrushPreset> onPresetApplied;
  final BrushPresetManager presetManager;

  const BrushEditorSheet({
    super.key,
    required this.currentPenType,
    required this.currentBaseWidth,
    required this.currentColor,
    required this.currentSettings,
    required this.onPresetApplied,
    required this.presetManager,
  });

  /// Show the brush editor as a modal bottom sheet
  static Future<BrushPreset?> show(
    BuildContext context, {
    required ProPenType penType,
    required double baseWidth,
    required Color color,
    required ProBrushSettings settings,
    required BrushPresetManager presetManager,
    required ValueChanged<BrushPreset> onPresetApplied,
  }) {
    return showModalBottomSheet<BrushPreset>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (_) => BrushEditorSheet(
            currentPenType: penType,
            currentBaseWidth: baseWidth,
            currentColor: color,
            currentSettings: settings,
            onPresetApplied: onPresetApplied,
            presetManager: presetManager,
          ),
    );
  }

  @override
  State<BrushEditorSheet> createState() => _BrushEditorSheetState();
}

class _BrushEditorSheetState extends State<BrushEditorSheet> {
  late String? _selectedPresetId;

  @override
  void initState() {
    super.initState();
    _selectedPresetId = null;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final allPresets = widget.presetManager.allPresets;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.65,
      ),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
              color: isDark ? Colors.white24 : Colors.black12,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
            child: Row(
              children: [
                Text(
                  '🎨 Brush Presets',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => _showSaveDialog(context, isDark),
                  icon: Icon(
                    Icons.save_rounded,
                    color: isDark ? Colors.tealAccent : Colors.teal,
                  ),
                  tooltip: 'Save as Preset',
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Preset carousel
          SizedBox(
            height: 90,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: allPresets.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final preset = allPresets[index];
                final isSelected = preset.id == _selectedPresetId;
                return _PresetCard(
                  preset: preset,
                  isSelected: isSelected,
                  isDark: isDark,
                  onTap: () {
                    setState(() => _selectedPresetId = preset.id);
                    widget.onPresetApplied(preset);
                  },
                  onLongPress:
                      preset.isBuiltIn
                          ? null
                          : () => _showDeleteDialog(context, preset, isDark),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          // Divider
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Divider(color: isDark ? Colors.white12 : Colors.black12),
          ),
          // Current brush info
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: widget.currentColor,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDark ? Colors.white24 : Colors.black12,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _penTypeName(widget.currentPenType),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    Text(
                      'Width: ${widget.currentBaseWidth.toStringAsFixed(1)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white38 : Colors.black45,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                _StabilizerBadge(
                  level: widget.currentSettings.stabilizerLevel,
                  isDark: isDark,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _penTypeName(ProPenType type) => switch (type) {
    ProPenType.ballpoint => 'Ballpoint',
    ProPenType.fountain => 'Fountain Pen',
    ProPenType.pencil => 'Pencil',
    ProPenType.highlighter => 'Highlighter',
    ProPenType.watercolor => 'Watercolor',
    ProPenType.marker => 'Marker',
    ProPenType.charcoal => 'Charcoal',
    ProPenType.oilPaint => 'Oil Paint',
    ProPenType.sprayPaint => 'Spray Paint',
    ProPenType.neonGlow => 'Neon Glow',
    ProPenType.inkWash => 'Ink Wash',
  };

  void _showSaveDialog(BuildContext context, bool isDark) {
    final nameController = TextEditingController();
    String selectedEmoji = '🖌️';
    final emojis = [
      '🖌️',
      '✒️',
      '🖊️',
      '✏️',
      '🖋️',
      '📏',
      '🖍️',
      '🎨',
      '🔵',
      '🔴',
    ];

    showDialog(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder:
                (ctx, setDialogState) => AlertDialog(
                  backgroundColor: isDark ? Colors.grey[850] : Colors.white,
                  title: Text(
                    'Save Preset',
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameController,
                        decoration: InputDecoration(
                          hintText: 'Preset name',
                          hintStyle: TextStyle(
                            color: isDark ? Colors.white38 : Colors.black38,
                          ),
                        ),
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black,
                        ),
                        autofocus: true,
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        children:
                            emojis.map((e) {
                              final isSelected = e == selectedEmoji;
                              return GestureDetector(
                                onTap: () {
                                  setDialogState(() => selectedEmoji = e);
                                },
                                child: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color:
                                        isSelected
                                            ? (isDark
                                                ? Colors.tealAccent.withValues(
                                                  alpha: 0.2,
                                                )
                                                : Colors.teal.withValues(
                                                  alpha: 0.1,
                                                ))
                                            : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color:
                                          isSelected
                                              ? (isDark
                                                  ? Colors.tealAccent
                                                  : Colors.teal)
                                              : Colors.transparent,
                                    ),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    e,
                                    style: const TextStyle(fontSize: 20),
                                  ),
                                ),
                              );
                            }).toList(),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () async {
                        if (nameController.text.trim().isEmpty) return;

                        final template = BrushPreset(
                          id: '', // will be overwritten
                          name: nameController.text.trim(),
                          icon: selectedEmoji,
                          penType: widget.currentPenType,
                          baseWidth: widget.currentBaseWidth,
                          color: widget.currentColor,
                          settings: widget.currentSettings,
                        );

                        await widget.presetManager.createPreset(
                          name: nameController.text.trim(),
                          icon: selectedEmoji,
                          template: template,
                        );

                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) setState(() {});
                      },
                      child: const Text('Save'),
                    ),
                  ],
                ),
          ),
    );
  }

  void _showDeleteDialog(
    BuildContext context,
    BrushPreset preset,
    bool isDark,
  ) {
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: isDark ? Colors.grey[850] : Colors.white,
            title: Text(
              'Delete "${preset.name}"?',
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
            ),
            content: Text(
              'This preset will be permanently removed.',
              style: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  await widget.presetManager.deletePreset(preset.id);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    setState(() {
                      if (_selectedPresetId == preset.id) {
                        _selectedPresetId = null;
                      }
                    });
                  }
                },
                style: FilledButton.styleFrom(backgroundColor: Colors.red[700]),
                child: const Text('Delete'),
              ),
            ],
          ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// PRIVATE WIDGETS
// ─────────────────────────────────────────────────────────────

class _PresetCard extends StatelessWidget {
  final BrushPreset preset;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _PresetCard({
    required this.preset,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 72,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color:
              isSelected
                  ? (isDark
                      ? Colors.tealAccent.withValues(alpha: 0.15)
                      : Colors.teal.withValues(alpha: 0.08))
                  : (isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.grey[100]),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color:
                isSelected
                    ? (isDark ? Colors.tealAccent : Colors.teal)
                    : Colors.transparent,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(preset.icon, style: const TextStyle(fontSize: 24)),
            const SizedBox(height: 4),
            Text(
              preset.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StabilizerBadge extends StatelessWidget {
  final int level;
  final bool isDark;

  const _StabilizerBadge({required this.level, required this.isDark});

  @override
  Widget build(BuildContext context) {
    if (level == 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color:
            isDark
                ? Colors.orangeAccent.withValues(alpha: 0.15)
                : Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.gesture_rounded,
            size: 14,
            color: isDark ? Colors.orangeAccent : Colors.deepOrange,
          ),
          const SizedBox(width: 4),
          Text(
            'S$level',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.orangeAccent : Colors.deepOrange,
            ),
          ),
        ],
      ),
    );
  }
}
