part of 'ruler_interactive_overlay.dart';

// ─── MD3 Sheet Helpers ─────────────────────────────────────────

extension _RulerOverlayMenuHelpers on _RulerInteractiveOverlayState {
  Widget sectionHeader(
    String title,
    IconData icon,
    Color accent, {
    String? description,
  }) {
    final dark = widget.isDark;
    return Container(
      padding: const EdgeInsets.only(left: 16, right: 12, top: 14, bottom: 6),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: dark ? 0.15 : 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 13, color: accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: accent.withValues(alpha: 0.9),
                letterSpacing: 1.0,
              ),
            ),
          ),
          if (description != null)
            Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () {
                  showDialog(
                    context: context,
                    barrierColor: Colors.black26,
                    builder: (dCtx) {
                      // Auto-dismiss after 3 seconds
                      Future.delayed(const Duration(seconds: 3), () {
                        if (Navigator.of(dCtx).canPop()) {
                          Navigator.of(dCtx).pop();
                        }
                      });
                      return Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: const EdgeInsets.only(
                            left: 24,
                            right: 24,
                            bottom: 100,
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    dark
                                        ? accent.withValues(alpha: 0.9)
                                        : accent,
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  BoxShadow(
                                    color: accent.withValues(alpha: 0.3),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.info_outline,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 10),
                                  Flexible(
                                    child: Text(
                                      description,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.info_outline,
                    size: 15,
                    color: dark ? Colors.white24 : const Color(0xFFBBBBBB),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget sheetToggle(
    String value,
    IconData icon,
    String label,
    bool on,
    bool dark,
    BuildContext ctx,
    StateSetter setSheetState,
  ) {
    final tc = dark ? Colors.white : const Color(0xFF1A1A1A);
    final sc = dark ? Colors.white38 : const Color(0xFF999999);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.pop(ctx, value);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(icon, size: 18, color: on ? tc : sc),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    color: on ? tc : sc,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              SizedBox(
                width: 40,
                height: 22,
                child: FittedBox(
                  child: Switch.adaptive(
                    value: on,
                    activeTrackColor: const Color(0xFF00BCD4),
                    onChanged: (_) {
                      Navigator.pop(ctx, value);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget sheetAction(
    String value,
    IconData icon,
    String label,
    bool dark,
    BuildContext ctx, {
    bool destructive = false,
  }) {
    final c =
        destructive
            ? const Color(0xFFE53935)
            : (dark ? Colors.white : const Color(0xFF1A1A1A));
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.pop(ctx, value),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 18, color: c.withValues(alpha: 0.7)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    color: c,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 14,
                color: dark ? const Color(0xFF555555) : const Color(0xFFCCCCCC),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget sheetIconBtn(
    IconData icon,
    String value,
    bool dark,
    BuildContext ctx,
  ) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => Navigator.pop(ctx, value),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(
              icon,
              size: 18,
              color: dark ? const Color(0xFF90A4AE) : const Color(0xFF607D8B),
            ),
          ),
        ),
      ),
    );
  }

  Widget themeChip(
    String value,
    String label,
    Color color,
    bool dark,
    BuildContext ctx,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.pop(ctx, value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: dark ? 0.15 : 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: dark ? Colors.white70 : const Color(0xFF424242),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget presetChip(
    String value,
    String label,
    IconData icon,
    bool dark,
    BuildContext ctx,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => Navigator.pop(ctx, value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: dark ? const Color(0xFF2A2A2A) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: dark ? const Color(0xFF444444) : const Color(0xFFE0E0E0),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: dark ? const Color(0xFF90A4AE) : const Color(0xFF607D8B),
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: dark ? Colors.white70 : const Color(0xFF424242),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String gridStyleLabel(GridStyle style) {
    switch (style) {
      case GridStyle.lines:
        return 'Lines';
      case GridStyle.dots:
        return 'Dots';
      case GridStyle.crosses:
        return 'Crosses';
    }
  }
}
