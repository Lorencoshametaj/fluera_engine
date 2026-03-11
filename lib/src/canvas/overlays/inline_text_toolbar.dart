import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 📝 Mini formatting toolbar — floats above the inline text editor.
///
/// V3: Two-row tabbed design with grouped categories.
/// Row 1: Colors + B/I/U/S + Sizes + Delete (always visible)
/// Row 2: Expandable tabs — Format / Effects / Actions
class InlineTextToolbar extends StatefulWidget {
  final Color currentColor;
  final FontWeight currentFontWeight;
  final double currentFontSize;
  final bool isItalic;
  final TextAlign textAlign;
  final String currentFontFamily;
  final ValueChanged<Color> onColorChanged;
  final ValueChanged<FontWeight> onFontWeightChanged;
  final ValueChanged<double> onFontSizeChanged;
  final ValueChanged<bool>? onItalicChanged;
  final ValueChanged<TextAlign>? onTextAlignChanged;
  final ValueChanged<String>? onFontFamilyChanged;
  final TextDecoration textDecoration;
  final ValueChanged<TextDecoration>? onTextDecorationChanged;
  final double letterSpacing;
  final ValueChanged<double>? onLetterSpacingChanged;
  final double opacity;
  final ValueChanged<double>? onOpacityChanged;
  final bool hasShadow;
  final ValueChanged<bool>? onShadowChanged;
  final ValueChanged<Color>? onShadowColorChanged;
  final Color? shadowColor;
  final bool hasBackground;
  final ValueChanged<bool>? onBackgroundChanged;
  final ValueChanged<Color>? onBackgroundColorChanged;
  final Color? bgColor;
  final bool hasOutline;
  final ValueChanged<bool>? onOutlineChanged;
  final ValueChanged<Color>? onOutlineColorChanged;
  final Color? outlineColor;
  final bool hasGradient;
  final ValueChanged<bool>? onGradientChanged;
  final bool hasGlow;
  final ValueChanged<bool>? onGlowChanged;
  final ValueChanged<Color>? onGlowColorChanged;
  final Color? glowColor;
  final VoidCallback? onDuplicate;
  final VoidCallback? onCopyStyle;
  final VoidCallback? onPasteStyle;
  final ValueChanged<Map<String, dynamic>>? onTemplateApply;
  final VoidCallback? onDelete;
  final VoidCallback? onBeforeDialog;

  const InlineTextToolbar({
    super.key,
    required this.currentColor,
    required this.currentFontWeight,
    required this.currentFontSize,
    this.isItalic = false,
    this.textAlign = TextAlign.left,
    this.currentFontFamily = 'Roboto',
    required this.onColorChanged,
    required this.onFontWeightChanged,
    required this.onFontSizeChanged,
    this.onItalicChanged,
    this.onTextAlignChanged,
    this.onFontFamilyChanged,
    this.textDecoration = TextDecoration.none,
    this.onTextDecorationChanged,
    this.letterSpacing = 0.0,
    this.onLetterSpacingChanged,
    this.opacity = 1.0,
    this.onOpacityChanged,
    this.hasShadow = false,
    this.onShadowChanged,
    this.onShadowColorChanged,
    this.shadowColor,
    this.hasBackground = false,
    this.onBackgroundChanged,
    this.onBackgroundColorChanged,
    this.bgColor,
    this.hasOutline = false,
    this.onOutlineChanged,
    this.onOutlineColorChanged,
    this.outlineColor,
    this.hasGradient = false,
    this.onGradientChanged,
    this.hasGlow = false,
    this.onGlowChanged,
    this.onGlowColorChanged,
    this.glowColor,
    this.onDuplicate,
    this.onCopyStyle,
    this.onPasteStyle,
    this.onTemplateApply,
    this.onDelete,
    this.onBeforeDialog,
  });

  static const List<Color> _presetColors = [
    Colors.black,
    Colors.white,
    Color(0xFFE53935), // red
    Color(0xFF1E88E5), // blue
    Color(0xFF43A047), // green
    Color(0xFFFB8C00), // orange
    Color(0xFF8E24AA), // purple
    Color(0xFF546E7A), // blue-grey
  ];

  static const Map<String, double> _fontSizePresets = {
    'S': 14.0,
    'M': 20.0,
    'L': 32.0,
    'XL': 48.0,
  };

  static const List<Map<String, String>> _fontFamilies = [
    {'label': 'Aa', 'family': 'Roboto'},
    {'label': 'Aa', 'family': 'serif'},
    {'label': 'Aa', 'family': 'monospace'},
  ];

  @override
  State<InlineTextToolbar> createState() => _InlineTextToolbarState();
}

class _InlineTextToolbarState extends State<InlineTextToolbar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entranceController;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  /// Active secondary tab: null = collapsed, 'format' / 'effects' / 'actions'
  String? _activeTab;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _fadeAnim = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOut,
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.easeOutCubic),
    );
    _entranceController.forward();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  void _toggleTab(String tab) {
    setState(() => _activeTab = _activeTab == tab ? null : tab);
    HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor =
        isDark
            ? const Color(0xFF1E1E1E).withValues(alpha: 0.95)
            : Colors.white.withValues(alpha: 0.97);
    final borderColor =
        isDark
            ? Colors.white.withValues(alpha: 0.1)
            : Colors.black.withValues(alpha: 0.06);
    final dividerColor =
        isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.black.withValues(alpha: 0.06);
    final accentColor = isDark ? Colors.blue.shade300 : Colors.blue.shade600;
    final mutedColor = isDark ? Colors.white54 : Colors.black38;

    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(
        position: _slideAnim,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanDown: (_) {},
          onPanUpdate: (_) {},
          onPanEnd: (_) {},
          child: Material(
            elevation: 12,
            shadowColor: Colors.black26,
            borderRadius: BorderRadius.circular(14),
            color: bgColor,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: borderColor, width: 0.5),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width - 36,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ═══════════════════════════════════════════
                    // ROW 1 — Primary (always visible)
                    // ═══════════════════════════════════════════
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 5,
                      ),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // ── Color dots ──
                            ...InlineTextToolbar._presetColors.map((color) {
                              final sel = _colorsEqual(
                                color,
                                widget.currentColor,
                              );
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 1.5,
                                ),
                                child: GestureDetector(
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    widget.onColorChanged(color);
                                  },
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 150),
                                    width: sel ? 24 : 20,
                                    height: sel ? 24 : 20,
                                    decoration: BoxDecoration(
                                      color: color,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color:
                                            sel
                                                ? accentColor
                                                : (color == Colors.white
                                                    ? Colors.grey.shade400
                                                    : Colors.transparent),
                                        width: sel ? 2.5 : 0.5,
                                      ),
                                      boxShadow:
                                          sel
                                              ? [
                                                BoxShadow(
                                                  color: color.withValues(
                                                    alpha: 0.4,
                                                  ),
                                                  blurRadius: 6,
                                                ),
                                              ]
                                              : null,
                                    ),
                                    child:
                                        sel
                                            ? Icon(
                                              Icons.check,
                                              size: 12,
                                              color:
                                                  _isLightColor(color)
                                                      ? Colors.black87
                                                      : Colors.white,
                                            )
                                            : null,
                                  ),
                                ),
                              );
                            }),

                            _divider(dividerColor),

                            // ── B weight cycle ──
                            GestureDetector(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                const w = [
                                  FontWeight.w300,
                                  FontWeight.w400,
                                  FontWeight.w500,
                                  FontWeight.w700,
                                  FontWeight.w800,
                                ];
                                final i = w.indexOf(widget.currentFontWeight);
                                widget.onFontWeightChanged(
                                  w[(i + 1) % w.length],
                                );
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      widget.currentFontWeight !=
                                              FontWeight.w400
                                          ? accentColor.withValues(alpha: 0.15)
                                          : Colors.transparent,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  _fontWeightLabel(widget.currentFontWeight),
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: widget.currentFontWeight,
                                    color:
                                        widget.currentFontWeight !=
                                                FontWeight.w400
                                            ? accentColor
                                            : mutedColor,
                                  ),
                                ),
                              ),
                            ),

                            // ── Italic ──
                            if (widget.onItalicChanged != null)
                              _FormatButton(
                                label: 'I',
                                isActive: widget.isItalic,
                                isDark: isDark,
                                fontStyle: FontStyle.italic,
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  widget.onItalicChanged!(!widget.isItalic);
                                },
                              ),

                            // ── Underline ──
                            if (widget.onTextDecorationChanged != null)
                              _FormatButton(
                                label: 'U',
                                isActive:
                                    widget.textDecoration ==
                                    TextDecoration.underline,
                                isDark: isDark,
                                textDecoration: TextDecoration.underline,
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  widget.onTextDecorationChanged!(
                                    widget.textDecoration ==
                                            TextDecoration.underline
                                        ? TextDecoration.none
                                        : TextDecoration.underline,
                                  );
                                },
                              ),

                            // ── Strikethrough ──
                            if (widget.onTextDecorationChanged != null)
                              _FormatButton(
                                label: 'S',
                                isActive:
                                    widget.textDecoration ==
                                    TextDecoration.lineThrough,
                                isDark: isDark,
                                textDecoration: TextDecoration.lineThrough,
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  widget.onTextDecorationChanged!(
                                    widget.textDecoration ==
                                            TextDecoration.lineThrough
                                        ? TextDecoration.none
                                        : TextDecoration.lineThrough,
                                  );
                                },
                              ),

                            _divider(dividerColor),

                            // ── Font Size presets ──
                            ...InlineTextToolbar._fontSizePresets.entries.map((
                              e,
                            ) {
                              final sel =
                                  (widget.currentFontSize - e.value).abs() <
                                  0.5;
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 1,
                                ),
                                child: GestureDetector(
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    widget.onFontSizeChanged(e.value);
                                  },
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 150),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          sel
                                              ? accentColor.withValues(
                                                alpha: 0.15,
                                              )
                                              : Colors.transparent,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      e.key,
                                      style: TextStyle(
                                        fontSize: _scaledLabelSize(e.key),
                                        fontWeight:
                                            sel
                                                ? FontWeight.bold
                                                : FontWeight.w500,
                                        color: sel ? accentColor : mutedColor,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }),

                            // ── Delete ──
                            if (widget.onDelete != null) ...[
                              _divider(dividerColor),
                              GestureDetector(
                                onTap: widget.onDelete,
                                child: SizedBox(
                                  width: 28,
                                  height: 26,
                                  child: Icon(
                                    Icons.delete_outline_rounded,
                                    size: 16,
                                    color:
                                        isDark
                                            ? Colors.red.shade300.withValues(
                                              alpha: 0.7,
                                            )
                                            : Colors.red.shade400.withValues(
                                              alpha: 0.7,
                                            ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),

                    // ═══════════════════════════════════════════
                    // TAB BAR — 3 category icons
                    // ═══════════════════════════════════════════
                    Container(
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(color: dividerColor, width: 0.5),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _TabIcon(
                            icon: Icons.text_format_rounded,
                            label: 'Formato',
                            isActive: _activeTab == 'format',
                            accentColor: accentColor,
                            mutedColor: mutedColor,
                            onTap: () => _toggleTab('format'),
                          ),
                          _TabIcon(
                            icon: Icons.auto_awesome_outlined,
                            label: 'Effetti',
                            isActive: _activeTab == 'effects',
                            accentColor: accentColor,
                            mutedColor: mutedColor,
                            onTap: () => _toggleTab('effects'),
                          ),
                          _TabIcon(
                            icon: Icons.dashboard_customize_outlined,
                            label: 'Azioni',
                            isActive: _activeTab == 'actions',
                            accentColor: accentColor,
                            mutedColor: mutedColor,
                            onTap: () => _toggleTab('actions'),
                          ),
                        ],
                      ),
                    ),

                    // ═══════════════════════════════════════════
                    // ROW 2 — Expandable tab content
                    // ═══════════════════════════════════════════
                    AnimatedSize(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      child:
                          _activeTab != null
                              ? Container(
                                decoration: BoxDecoration(
                                  border: Border(
                                    top: BorderSide(
                                      color: dividerColor,
                                      width: 0.5,
                                    ),
                                  ),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 5,
                                ),
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 200),
                                  child: SingleChildScrollView(
                                    key: ValueKey(_activeTab),
                                    scrollDirection: Axis.horizontal,
                                    physics: const BouncingScrollPhysics(),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: _buildTabContent(
                                        isDark,
                                        accentColor,
                                        mutedColor,
                                        dividerColor,
                                      ),
                                    ),
                                  ),
                                ),
                              )
                              : const SizedBox.shrink(),
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

  // ── Tab Content Dispatcher ──────────────────────────────────────────────

  List<Widget> _buildTabContent(
    bool isDark,
    Color accentColor,
    Color mutedColor,
    Color dividerColor,
  ) {
    return switch (_activeTab) {
      'format' => _buildFormatTab(
        isDark,
        accentColor,
        mutedColor,
        dividerColor,
      ),
      'effects' => _buildEffectsTab(
        isDark,
        accentColor,
        mutedColor,
        dividerColor,
      ),
      'actions' => _buildActionsTab(
        isDark,
        accentColor,
        mutedColor,
        dividerColor,
      ),
      _ => [],
    };
  }

  // ── FORMAT TAB ──────────────────────────────────────────────────────────

  List<Widget> _buildFormatTab(
    bool isDark,
    Color accentColor,
    Color mutedColor,
    Color dividerColor,
  ) {
    return [
      // Text Alignment
      if (widget.onTextAlignChanged != null) ...[
        _AlignButton(
          align: widget.textAlign,
          isDark: isDark,
          onTap: () {
            HapticFeedback.selectionClick();
            final next = switch (widget.textAlign) {
              TextAlign.left => TextAlign.center,
              TextAlign.center => TextAlign.right,
              _ => TextAlign.left,
            };
            widget.onTextAlignChanged!(next);
          },
        ),
        _divider(dividerColor),
      ],

      // Font Family Cycle
      if (widget.onFontFamilyChanged != null) ...[
        GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            final families = InlineTextToolbar._fontFamilies;
            final idx = families.indexWhere(
              (f) => f['family'] == widget.currentFontFamily,
            );
            widget.onFontFamilyChanged!(
              families[(idx + 1) % families.length]['family']!,
            );
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _fontFamilyLabel(widget.currentFontFamily),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                fontFamily: widget.currentFontFamily,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
          ),
        ),
        _divider(dividerColor),
      ],

      // Letter Spacing Cycle
      if (widget.onLetterSpacingChanged != null) ...[
        GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            final vals = [0.0, 1.0, 2.0, 4.0];
            final idx = vals.indexOf(widget.letterSpacing);
            widget.onLetterSpacingChanged!(vals[(idx + 1) % vals.length]);
          },
          child: _ToggleIcon(
            icon: Icons.space_bar,
            isActive: widget.letterSpacing > 0,
            accentColor: accentColor,
            mutedColor: mutedColor,
          ),
        ),
      ],

      // Opacity Cycle
      if (widget.onOpacityChanged != null) ...[
        _divider(dividerColor),
        GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            final vals = [1.0, 0.75, 0.5, 0.25];
            final idx = vals.indexWhere(
              (v) => (v - widget.opacity).abs() < 0.05,
            );
            widget.onOpacityChanged!(vals[(idx + 1) % vals.length]);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 28,
            height: 26,
            decoration: BoxDecoration(
              color:
                  widget.opacity < 1.0
                      ? accentColor.withValues(alpha: 0.2)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(
              child: Text(
                '${(widget.opacity * 100).round()}%',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: widget.opacity < 1.0 ? accentColor : mutedColor,
                ),
              ),
            ),
          ),
        ),
      ],
    ];
  }

  // ── EFFECTS TAB ─────────────────────────────────────────────────────────

  List<Widget> _buildEffectsTab(
    bool isDark,
    Color accentColor,
    Color mutedColor,
    Color dividerColor,
  ) {
    return [
      if (widget.onShadowChanged != null)
        _effectButton(
          isDark,
          accentColor,
          mutedColor,
          icon: Icons.wb_sunny_outlined,
          label: 'Ombra',
          isActive: widget.hasShadow,
          activeColor: widget.shadowColor,
          onTap: () {
            HapticFeedback.selectionClick();
            widget.onShadowChanged!(!widget.hasShadow);
          },
          onColorPick: widget.onShadowColorChanged,
        ),

      if (widget.onBackgroundChanged != null)
        _effectButton(
          isDark,
          accentColor,
          mutedColor,
          icon: Icons.format_color_fill_outlined,
          label: 'Sfondo',
          isActive: widget.hasBackground,
          activeColor: widget.bgColor,
          onTap: () {
            HapticFeedback.selectionClick();
            widget.onBackgroundChanged!(!widget.hasBackground);
          },
          onColorPick: widget.onBackgroundColorChanged,
        ),

      if (widget.onOutlineChanged != null)
        _effectButton(
          isDark,
          accentColor,
          mutedColor,
          icon: Icons.border_color_outlined,
          label: 'Bordo',
          isActive: widget.hasOutline,
          activeColor: widget.outlineColor,
          onTap: () {
            HapticFeedback.selectionClick();
            widget.onOutlineChanged!(!widget.hasOutline);
          },
          onColorPick: widget.onOutlineColorChanged,
        ),

      if (widget.onGradientChanged != null)
        GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            widget.onGradientChanged!(!widget.hasGradient);
          },
          child: _ToggleIcon(
            icon: Icons.gradient_outlined,
            label: 'Gradient',
            isActive: widget.hasGradient,
            accentColor: accentColor,
            mutedColor: mutedColor,
          ),
        ),

      if (widget.onGlowChanged != null)
        _effectButton(
          isDark,
          accentColor,
          mutedColor,
          icon: Icons.auto_awesome,
          label: 'Glow',
          isActive: widget.hasGlow,
          activeColor: widget.glowColor,
          onTap: () {
            HapticFeedback.selectionClick();
            widget.onGlowChanged!(!widget.hasGlow);
          },
          onColorPick: widget.onGlowColorChanged,
        ),
    ];
  }

  /// Effect button: tap = toggle, long-press = color picker popup
  Widget _effectButton(
    bool isDark,
    Color accentColor,
    Color mutedColor, {
    required IconData icon,
    required String label,
    required bool isActive,
    Color? activeColor,
    required VoidCallback onTap,
    ValueChanged<Color>? onColorPick,
  }) {
    return GestureDetector(
      onTap: onTap,
      onLongPress:
          isActive && onColorPick != null
              ? () {
                HapticFeedback.mediumImpact();
                _showEffectColorPicker(
                  context,
                  isDark,
                  activeColor,
                  onColorPick,
                );
              }
              : null,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          _ToggleIcon(
            icon: icon,
            label: label,
            isActive: isActive,
            accentColor: accentColor,
            mutedColor: mutedColor,
          ),
          if (isActive && activeColor != null)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: activeColor,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDark ? Colors.black : Colors.white,
                    width: 1,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Mini color picker popup for effects
  void _showEffectColorPicker(
    BuildContext ctx,
    bool isDark,
    Color? current,
    ValueChanged<Color> onPick,
  ) {
    const colors = [
      Colors.black,
      Colors.white,
      Color(0xFFE53935),
      Color(0xFF1E88E5),
      Color(0xFF43A047),
      Color(0xFFFB8C00),
      Color(0xFF8E24AA),
      Color(0xFF546E7A),
      Color(0xFFFFD54F),
      Color(0xFF4DD0E1),
      Color(0xFFFF7043),
      Color(0xFF66BB6A),
    ];
    widget.onBeforeDialog?.call();
    showDialog(
      context: ctx,
      barrierColor: Colors.black26,
      builder:
          (dCtx) => Center(
            child: Material(
              elevation: 16,
              borderRadius: BorderRadius.circular(12),
              color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Scegli colore',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children:
                          colors.map((c) {
                            final sel =
                                current != null &&
                                c.toARGB32() == current.toARGB32();
                            return GestureDetector(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                onPick(c);
                                Navigator.of(dCtx).pop();
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 120),
                                width: sel ? 32 : 28,
                                height: sel ? 32 : 28,
                                decoration: BoxDecoration(
                                  color: c,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color:
                                        sel
                                            ? (isDark
                                                ? Colors.white
                                                : Colors.blue)
                                            : (c == Colors.white
                                                ? Colors.grey.shade400
                                                : Colors.transparent),
                                    width: sel ? 2.5 : 0.5,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                    ),
                  ],
                ),
              ),
            ),
          ),
    );
  }

  // ── ACTIONS TAB ─────────────────────────────────────────────────────────

  List<Widget> _buildActionsTab(
    bool isDark,
    Color accentColor,
    Color mutedColor,
    Color dividerColor,
  ) {
    return [
      if (widget.onDuplicate != null)
        GestureDetector(
          onTap: widget.onDuplicate,
          child: _ToggleIcon(
            icon: Icons.copy_outlined,
            label: 'Duplica',
            isActive: false,
            accentColor: accentColor,
            mutedColor: mutedColor,
          ),
        ),

      if (widget.onCopyStyle != null) ...[
        _divider(dividerColor),
        GestureDetector(
          onTap: widget.onCopyStyle,
          child: _ToggleIcon(
            icon: Icons.format_paint_outlined,
            label: 'Copia',
            isActive: false,
            accentColor: accentColor,
            mutedColor: mutedColor,
          ),
        ),
      ],

      if (widget.onPasteStyle != null)
        GestureDetector(
          onTap: widget.onPasteStyle,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.format_paint,
                  size: 15,
                  color:
                      isDark
                          ? const Color(0xFFFFD54F)
                          : const Color(0xFFF57F17),
                ),
                const SizedBox(height: 1),
                Text(
                  'Incolla',
                  style: TextStyle(
                    fontSize: 8,
                    color:
                        isDark
                            ? const Color(0xFFFFD54F)
                            : const Color(0xFFF57F17),
                  ),
                ),
              ],
            ),
          ),
        ),

      if (widget.onTemplateApply != null) ...[
        _divider(dividerColor),
        PopupMenuButton<Map<String, dynamic>>(
          onSelected: widget.onTemplateApply,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 40, maxWidth: 40),
          itemBuilder:
              (context) => [
                PopupMenuItem(
                  value: {
                    'fontSize': 28.0,
                    'fontWeight': FontWeight.w700,
                    'letterSpacing': 0.0,
                  },
                  height: 36,
                  child: const Text('📝 Title', style: TextStyle(fontSize: 13)),
                ),
                PopupMenuItem(
                  value: {
                    'fontSize': 22.0,
                    'fontWeight': FontWeight.w500,
                    'letterSpacing': 0.5,
                  },
                  height: 36,
                  child: const Text(
                    '📋 Subtitle',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
                PopupMenuItem(
                  value: {
                    'fontSize': 16.0,
                    'fontWeight': FontWeight.w400,
                    'letterSpacing': 0.0,
                  },
                  height: 36,
                  child: const Text('📄 Body', style: TextStyle(fontSize: 13)),
                ),
                PopupMenuItem(
                  value: {
                    'fontSize': 12.0,
                    'fontWeight': FontWeight.w300,
                    'letterSpacing': 0.5,
                  },
                  height: 36,
                  child: const Text(
                    '🏷️ Caption',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ],
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.style_outlined, size: 15, color: mutedColor),
              const SizedBox(height: 1),
              Text(
                'Template',
                style: TextStyle(fontSize: 8, color: mutedColor),
              ),
            ],
          ),
        ),
      ],
    ];
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  Widget _divider(Color color) {
    return Container(
      width: 1,
      height: 20,
      margin: const EdgeInsets.symmetric(horizontal: 5),
      color: color,
    );
  }

  double _scaledLabelSize(String key) {
    return switch (key) {
      'S' => 10.0,
      'M' => 12.0,
      'L' => 14.0,
      'XL' => 11.0,
      _ => 12.0,
    };
  }

  String _fontFamilyLabel(String family) {
    return switch (family) {
      'serif' => 'Serif',
      'monospace' => 'Mono',
      _ => 'Sans',
    };
  }

  String _fontWeightLabel(FontWeight weight) {
    return switch (weight) {
      FontWeight.w300 => 'Light',
      FontWeight.w500 => 'Med',
      FontWeight.w700 => 'Bold',
      FontWeight.w800 => 'XBold',
      _ => 'Reg',
    };
  }

  bool _colorsEqual(Color a, Color b) => a.toARGB32() == b.toARGB32();
  bool _isLightColor(Color color) => color.computeLuminance() > 0.5;
}

// ── Tab Icon (Format / Effects / Actions) ────────────────────────────────────

class _TabIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final Color accentColor;
  final Color mutedColor;
  final VoidCallback onTap;

  const _TabIcon({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.accentColor,
    required this.mutedColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive ? accentColor : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: isActive ? accentColor : mutedColor),
            const SizedBox(height: 1),
            Text(
              label,
              style: TextStyle(
                fontSize: 8,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive ? accentColor : mutedColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Toggle Icon (effect/action button with optional label) ───────────────────

class _ToggleIcon extends StatelessWidget {
  final IconData icon;
  final String? label;
  final bool isActive;
  final Color accentColor;
  final Color mutedColor;

  const _ToggleIcon({
    required this.icon,
    this.label,
    required this.isActive,
    required this.accentColor,
    required this.mutedColor,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color:
            isActive ? accentColor.withValues(alpha: 0.2) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: isActive ? accentColor : mutedColor),
          if (label != null) ...[
            const SizedBox(height: 1),
            Text(
              label!,
              style: TextStyle(
                fontSize: 8,
                color: isActive ? accentColor : mutedColor,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Format Button (B / I / U / S) ────────────────────────────────────────────

class _FormatButton extends StatelessWidget {
  final String label;
  final bool isActive;
  final bool isDark;
  final FontWeight fontWeight;
  final FontStyle fontStyle;
  final TextDecoration textDecoration;
  final VoidCallback onTap;

  const _FormatButton({
    required this.label,
    required this.isActive,
    required this.isDark,
    this.fontWeight = FontWeight.w600,
    this.fontStyle = FontStyle.normal,
    this.textDecoration = TextDecoration.none,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accentColor = isDark ? Colors.blue.shade300 : Colors.blue.shade600;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 28,
        height: 26,
        decoration: BoxDecoration(
          color:
              isActive
                  ? accentColor.withValues(alpha: 0.15)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border:
              isActive
                  ? Border.all(
                    color: accentColor.withValues(alpha: 0.3),
                    width: 1,
                  )
                  : null,
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: fontWeight,
              fontStyle: fontStyle,
              decoration: textDecoration,
              color:
                  isActive
                      ? accentColor
                      : (isDark ? Colors.white54 : Colors.black45),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Alignment Button ─────────────────────────────────────────────────────────

class _AlignButton extends StatelessWidget {
  final TextAlign align;
  final bool isDark;
  final VoidCallback onTap;

  const _AlignButton({
    required this.align,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final icon = switch (align) {
      TextAlign.center => Icons.format_align_center_rounded,
      TextAlign.right => Icons.format_align_right_rounded,
      _ => Icons.format_align_left_rounded,
    };

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 28,
        height: 26,
        child: Icon(
          icon,
          size: 16,
          color: isDark ? Colors.white54 : Colors.black45,
        ),
      ),
    );
  }
}
