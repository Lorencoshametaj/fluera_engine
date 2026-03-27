import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui' as ui;
import '../image_editor_models.dart';
import '../image_editor_preview.dart';
import '../../rendering/native/image/lut_presets.dart';
import '../../core/models/text_overlay.dart';

/// 🎬 Presets Section — Quick Filters, Cinema LUTs, Text Overlay
class EditorSectionPresets extends StatelessWidget {
  final ui.Image image;
  final String activeFilterId;
  final int lutIndex;
  final List<TextOverlay> textOverlays;
  final VoidCallback onPushUndo;
  final ValueChanged<FilterPreset> onApplyFilter;
  final ValueChanged<int> onLutChanged;
  final VoidCallback onAddTextOverlay;
  final ValueChanged<int> onRemoveTextOverlay;

  const EditorSectionPresets({
    super.key,
    required this.image,
    required this.activeFilterId,
    required this.lutIndex,
    required this.textOverlays,
    required this.onPushUndo,
    required this.onApplyFilter,
    required this.onLutChanged,
    required this.onAddTextOverlay,
    required this.onRemoveTextOverlay,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Quick Filters Grid ──
        Text(
          'Quick Filters',
          style: tt.titleSmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.85,
          ),
          itemCount: kFilterPresets.length,
          itemBuilder: (_, i) {
            final f = kFilterPresets[i];
            final active = activeFilterId == f.id;
            return GestureDetector(
              onTap: () => onApplyFilter(f),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  color:
                      active ? cs.primaryContainer : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: active ? cs.primary : cs.outlineVariant,
                    width: active ? 2 : 1,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    RepaintBoundary(
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: cs.surfaceContainerLowest,
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: CustomPaint(
                            painter: PreviewPainter(
                              image: image,
                              rotation: 0,
                              flipHorizontal: false,
                              flipVertical: false,
                              brightness: f.brightness,
                              contrast: f.contrast,
                              saturation: f.saturation,
                              opacity: 1.0,
                              drawingStrokes: const [],
                            ),
                            child: const SizedBox.expand(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      f.id == 'none'
                          ? 'None'
                          : f.id[0].toUpperCase() + f.id.substring(1),
                      style: tt.labelMedium?.copyWith(
                        color:
                            active
                                ? cs.onPrimaryContainer
                                : cs.onSurfaceVariant,
                        fontWeight:
                            active ? FontWeight.w600 : FontWeight.normal,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 24),

        // ── LUT Cinema Presets ──
        Text(
          '🎬 Cinema LUTs',
          style: tt.titleSmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 90,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: lutPresets.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final preset = lutPresets[i];
              final isNone = preset.id == 'none';
              final active = isNone ? lutIndex == -1 : lutIndex == i;
              return GestureDetector(
                onTap: () {
                  onPushUndo();
                  onLutChanged(isNone ? -1 : i);
                  HapticFeedback.selectionClick();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 72,
                  decoration: BoxDecoration(
                    color:
                        active
                            ? cs.tertiaryContainer
                            : cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: active ? cs.tertiary : cs.outlineVariant,
                      width: active ? 2.5 : 1,
                    ),
                    boxShadow:
                        active
                            ? [
                              BoxShadow(
                                color: cs.tertiary.withValues(alpha: 0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ]
                            : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(preset.icon, style: const TextStyle(fontSize: 26)),
                      const SizedBox(height: 4),
                      Text(
                        preset.name,
                        style: tt.labelSmall?.copyWith(
                          color:
                              active
                                  ? cs.onTertiaryContainer
                                  : cs.onSurfaceVariant,
                          fontWeight:
                              active ? FontWeight.w600 : FontWeight.normal,
                          fontSize: 10,
                        ),
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),

        // ── Text Overlays ──
        const SizedBox(height: 24),
        Text(
          '📝 Text Overlay',
          style: tt.titleSmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          onPressed: onAddTextOverlay,
          icon: const Icon(Icons.text_fields_rounded, size: 20),
          label: const Text('Add Text'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(44),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        if (textOverlays.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...textOverlays.asMap().entries.map((entry) {
            final i = entry.key;
            final t = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: cs.outlineVariant),
                ),
                leading: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Color(t.color),
                    shape: BoxShape.circle,
                    border: Border.all(color: cs.outlineVariant),
                  ),
                ),
                title: Text(
                  t.text,
                  style: tt.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${t.fontSize.toInt()}px · ${t.fontFamily}',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                trailing: IconButton(
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    size: 20,
                    color: cs.error,
                  ),
                  onPressed: () => onRemoveTextOverlay(i),
                ),
              ),
            );
          }),
        ],
      ],
    );
  }
}
