part of 'ruler_interactive_overlay.dart';

/// Dialogs for the ruler overlay: guide editing (double-tap),
/// custom grid, distribute, and save preset.

extension _RulerOverlayDialogs on _RulerInteractiveOverlayState {
  // ─── Double-tap (guide edit dialog) ────────────────────────────

  void onDoubleTap(int index, bool isH) {
    final guides =
        isH
            ? widget.guideSystem.horizontalGuides
            : widget.guideSystem.verticalGuides;
    if (index >= guides.length) return;

    final ctrl = TextEditingController(text: guides[index].round().toString());
    HapticFeedback.selectionClick();

    final color = isH ? const Color(0xFF00BCD4) : const Color(0xFFE040FB);

    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor:
                widget.isDark ? const Color(0xFF2A2A2A) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            title: Text(
              isH ? 'Position Y' : 'Position X',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: widget.isDark ? Colors.white : const Color(0xFF1A1A1A),
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                    color:
                        widget.isDark ? Colors.white : const Color(0xFF1A1A1A),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  decoration: InputDecoration(
                    suffixText: widget.guideSystem.unitSuffix,
                    suffixStyle: TextStyle(
                      color:
                          widget.isDark
                              ? Colors.white54
                              : const Color(0xFF888888),
                      fontSize: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: color, width: 2),
                    ),
                  ),
                  onSubmitted: (v) {
                    _applyPos(v, index, isH);
                    Navigator.of(ctx).pop();
                  },
                ),
                const SizedBox(height: 12),
                // Annotation text field
                Builder(
                  builder: (innerCtx) {
                    final annotCtrl = TextEditingController(
                      text: widget.guideSystem.getGuideLabel(isH, index) ?? '',
                    );
                    return TextField(
                      controller: annotCtrl,
                      style: TextStyle(
                        fontSize: 14,
                        color:
                            widget.isDark
                                ? Colors.white
                                : const Color(0xFF1A1A1A),
                      ),
                      decoration: InputDecoration(
                        labelText: 'Annotation',
                        labelStyle: TextStyle(
                          color:
                              widget.isDark
                                  ? Colors.white54
                                  : const Color(0xFF888888),
                          fontSize: 12,
                        ),
                        hintText: 'e.g. Header baseline',
                        hintStyle: TextStyle(
                          color:
                              widget.isDark
                                  ? Colors.white24
                                  : const Color(0xFFBBBBBB),
                          fontSize: 13,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: color, width: 2),
                        ),
                        isDense: true,
                      ),
                      onChanged: (v) {
                        widget.guideSystem.setGuideLabel(isH, index, v);
                        widget.onChanged();
                      },
                    );
                  },
                ),
                const SizedBox(height: 12),
                // Color picker row
                _buildColorRow(index, isH, ctx),
              ],
            ),
            actions: [
              // Copy coordinate to clipboard
              IconButton(
                onPressed: () {
                  final coord = widget.guideSystem.getGuideCoordinate(
                    isH,
                    index,
                  );
                  Clipboard.setData(ClipboardData(text: coord));
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                      content: Text('Copied: $coord'),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                },
                icon: Icon(
                  Icons.copy,
                  size: 18,
                  color:
                      widget.isDark ? Colors.white54 : const Color(0xFF888888),
                ),
                tooltip: 'Copy coordinate',
              ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    color:
                        widget.isDark
                            ? Colors.white54
                            : const Color(0xFF888888),
                  ),
                ),
              ),
              FilledButton(
                onPressed: () {
                  _applyPos(ctrl.text, index, isH);
                  Navigator.of(ctx).pop();
                },
                style: FilledButton.styleFrom(
                  backgroundColor: color,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('OK'),
              ),
            ],
          ),
    );
  }

  Widget _buildColorRow(int index, bool isH, BuildContext ctx) {
    const colors = [
      null, // default
      Color(0xFF00BCD4),
      Color(0xFFE040FB),
      Color(0xFFFF5252),
      Color(0xFF69F0AE),
      Color(0xFFFFD740),
      Color(0xFF448AFF),
      Color(0xFFFF6E40),
    ];
    final current = widget.guideSystem.getGuideColor(isH, index);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Color:  ',
          style: TextStyle(
            fontSize: 11,
            color: widget.isDark ? Colors.white54 : const Color(0xFF888888),
          ),
        ),
        for (final c in colors)
          GestureDetector(
            onTap: () {
              widget.guideSystem.setGuideColor(isH, index, c);
              widget.onChanged();
              Navigator.of(ctx).pop();
              Future.delayed(const Duration(milliseconds: 100), () {
                if (mounted) onDoubleTap(index, isH);
              });
            },
            child: Container(
              width: 20,
              height: 20,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color:
                    c ??
                    (isH ? const Color(0xFF00BCD4) : const Color(0xFFE040FB)),
                border: Border.all(
                  color:
                      (c ??
                                  (isH
                                      ? const Color(0xFF00BCD4)
                                      : const Color(0xFFE040FB))) ==
                              current
                          ? Colors.white
                          : Colors.transparent,
                  width: 2,
                ),
              ),
              child:
                  c == null
                      ? Icon(
                        Icons.auto_fix_high,
                        size: 10,
                        color: Colors.white.withValues(alpha: 0.7),
                      )
                      : null,
            ),
          ),
      ],
    );
  }

  void _applyPos(String text, int index, bool isH) {
    final v = double.tryParse(text);
    if (v == null) return;
    final guides =
        isH
            ? widget.guideSystem.horizontalGuides
            : widget.guideSystem.verticalGuides;
    if (index < guides.length) {
      guides[index] = v;
      HapticFeedback.mediumImpact();
      widget.onChanged();
      if (mounted) setState(() {});
    }
  }

  // ─── Long-press guide (toggle lock) ────────────────────────────

  void onLongPress(int index, bool isH) {
    HapticFeedback.heavyImpact();
    widget.guideSystem.toggleLock(isH, index);
    widget.onChanged();
    if (mounted) setState(() {});
  }

  // ─── Custom Grid Dialog ────────────────────────────────────────

  void showCustomGridDialog() {
    final controller = TextEditingController(text: '50');
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Custom Grid'),
            content: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Spacing (px)',
                hintText: 'e.g. 25, 50, 100',
              ),
              autofocus: true,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final val = double.tryParse(controller.text);
                  if (val != null && val > 0) {
                    widget.guideSystem.customGridStep = val;
                    widget.onChanged();
                    if (mounted) setState(() {});
                  }
                  Navigator.pop(ctx);
                },
                child: const Text('Apply'),
              ),
            ],
          ),
    );
  }

  // ─── Distribute Dialog ─────────────────────────────────────────

  void showDistributeDialog() {
    final countCtrl = TextEditingController(text: '5');
    final startCtrl = TextEditingController(text: '0');
    final endCtrl = TextEditingController(text: '1000');
    bool isHorizontal = true;

    showDialog(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder:
                (ctx, setDialogState) => AlertDialog(
                  title: const Text('Distribute Guides'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Text('Axis: '),
                          ChoiceChip(
                            label: const Text('H'),
                            selected: isHorizontal,
                            onSelected:
                                (v) =>
                                    setDialogState(() => isHorizontal = true),
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('V'),
                            selected: !isHorizontal,
                            onSelected:
                                (v) =>
                                    setDialogState(() => isHorizontal = false),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: countCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Number of guides',
                        ),
                      ),
                      TextField(
                        controller: startCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Start (px)',
                        ),
                      ),
                      TextField(
                        controller: endCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'End (px)',
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () {
                        final count = int.tryParse(countCtrl.text) ?? 0;
                        final start = double.tryParse(startCtrl.text) ?? 0;
                        final end = double.tryParse(endCtrl.text) ?? 0;
                        if (count >= 2 && start != end) {
                          widget.guideSystem.distributeGuides(
                            isHorizontal,
                            count,
                            start,
                            end,
                          );
                          widget.onChanged();
                          if (mounted) setState(() {});
                        }
                        Navigator.pop(ctx);
                      },
                      child: const Text('Distribute'),
                    ),
                  ],
                ),
          ),
    );
  }

  // ─── Save Preset Dialog ────────────────────────────────────────

  void showSavePresetDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Save Preset'),
            content: TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Preset name',
                hintText: 'e.g. Main layout',
              ),
              autofocus: true,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final name = controller.text.trim();
                  if (name.isNotEmpty) {
                    widget.guideSystem.savePreset(name);
                    widget.onChanged();
                    if (mounted) setState(() {});
                  }
                  Navigator.pop(ctx);
                },
                child: const Text('Save'),
              ),
            ],
          ),
    );
  }
}
