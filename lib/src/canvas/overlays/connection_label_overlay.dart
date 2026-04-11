import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../reflow/knowledge_connection.dart';

/// 🏷️ CONNECTION LABEL OVERLAY — Premium floating text input for Knowledge Flow.
///
/// Appears at the midpoint of a connection arrow immediately after creation.
/// Features:
/// - Animated fade+scale entrance AND exit
/// - True glassmorphism with BackdropFilter
/// - Quick-pick suggested label pills for one-tap labeling
/// - Auto-focus with compact single-line input
/// - Submit on Done / dismiss on tap-outside
/// - Max 30 characters for concise labels
class ConnectionLabelOverlay extends StatefulWidget {
  /// Initial label text (empty for new, pre-populated for edit).
  final String initialText;

  /// Connection color for accent theming.
  final Color accentColor;

  /// Called when the user submits the label.
  final ValueChanged<String> onSubmit;

  /// Called when the user dismisses without entering text.
  final VoidCallback onDismiss;

  /// Called when the user wants to delete the connection.
  final VoidCallback? onDelete;

  /// Called when the user picks a new color.
  final ValueChanged<Color>? onColorChanged;

  /// Called when the user cycles to a new connection type.
  final ValueChanged<ConnectionType>? onTypeChanged;

  /// Called when the user toggles bidirectional mode.
  final ValueChanged<bool>? onBidirectionalToggled;

  /// Called when the user cycles to a new connection style.
  final ValueChanged<ConnectionStyle>? onStyleChanged;

  /// Called when the user enters multi-select mode.
  final VoidCallback? onMultiSelect;

  /// Current connection type (for display).
  final ConnectionType connectionType;

  /// Current connection style (for display).
  final ConnectionStyle connectionStyle;

  /// Current bidirectional state (for display).
  final bool isBidirectional;

  const ConnectionLabelOverlay({
    super.key,
    this.initialText = '',
    this.accentColor = const Color(0xFF64B5F6),
    required this.onSubmit,
    required this.onDismiss,
    this.onDelete,
    this.onColorChanged,
    this.onTypeChanged,
    this.onBidirectionalToggled,
    this.onStyleChanged,
    this.onMultiSelect,
    this.connectionType = ConnectionType.association,
    this.connectionStyle = ConnectionStyle.curved,
    this.isBidirectional = false,
  });

  @override
  State<ConnectionLabelOverlay> createState() => _ConnectionLabelOverlayState();
}

class _ConnectionLabelOverlayState extends State<ConnectionLabelOverlay>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _scaleAnim;
  bool _submitted = false;
  late Color _selectedColor;
  late ConnectionType _currentType;
  late ConnectionStyle _currentStyle;
  late bool _currentBidirectional;

  /// Quick-pick suggested labels
  static const _suggestions = [
    'causa',
    'parte di',
    'vedi anche',
    'implica',
    'opposto',
    'esempio',
  ];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    _selectedColor = widget.accentColor;
    _currentType = widget.connectionType;
    _currentStyle = widget.connectionStyle;
    _currentBidirectional = widget.isBidirectional;
    _focusNode = FocusNode();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );
    _scaleAnim = Tween<double>(begin: 0.75, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutBack),
    );
    _animController.forward();

    // Auto-focus
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
        // Select all text for easy replacement when editing
        if (_controller.text.isNotEmpty) {
          _controller.selection = TextSelection(
            baseOffset: 0,
            extentOffset: _controller.text.length,
          );
        }
      }
    });
  }

  void _doSubmit([String? overrideText]) {
    if (_submitted) return;
    _submitted = true;
    final text = (overrideText ?? _controller.text).trim();
    HapticFeedback.lightImpact();

    // Fire callback IMMEDIATELY so parent clears state
    // (prevents ghost Positioned.fill from blocking touches)
    if (text.isEmpty) {
      widget.onDismiss();
    } else {
      widget.onSubmit(text);
    }
    // Animation plays visually but widget is already being removed
    _animController.reverse();
  }

  void _dismiss() {
    if (_submitted) return;
    _submitted = true;
    widget.onDismiss();
    _animController.reverse();
  }

  @override
  void dispose() {
    _animController.dispose();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = _selectedColor;

    return FadeTransition(
      opacity: _fadeAnim,
      child: ScaleTransition(
        scale: _scaleAnim,
        child: Material(
          color: Colors.transparent,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ── Main input pill ──
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: Container(
                    constraints: const BoxConstraints(
                      maxWidth: 240,
                      minWidth: 140,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xCC0D0D14), // ~80% opaque
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: accent.withValues(alpha: 0.35),
                        width: 1.0,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.45),
                          blurRadius: 20,
                          offset: const Offset(0, 6),
                        ),
                        BoxShadow(
                          color: accent.withValues(alpha: 0.06),
                          blurRadius: 30,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Accent glow dot
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              colors: [
                                accent,
                                accent.withValues(alpha: 0.3),
                              ],
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: accent.withValues(alpha: 0.4),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Text field
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            focusNode: _focusNode,
                            maxLength: 30,
                            maxLines: 1,
                            autofocus: true,
                            textCapitalization: TextCapitalization.none,
                            style: TextStyle(
                              fontSize: 13.5,
                              color: Colors.white.withValues(alpha: 0.95),
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.2,
                            ),
                            cursorColor: accent,
                            cursorWidth: 1.5,
                            cursorRadius: const Radius.circular(1),
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.zero,
                              isDense: true,
                              isCollapsed: true,
                              counterText: '',
                              hintText: 'Aggiungi label...',
                              hintStyle: TextStyle(
                                fontSize: 13.5,
                                color: Colors.white.withValues(alpha: 0.25),
                                fontWeight: FontWeight.w400,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                            onSubmitted: (_) => _doSubmit(),
                            textInputAction: TextInputAction.done,
                          ),
                        ),
                        const SizedBox(width: 4),
                        // Submit button
                        GestureDetector(
                          onTap: _doSubmit,
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  accent.withValues(alpha: 0.3),
                                  accent.withValues(alpha: 0.15),
                                ],
                              ),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.check_rounded,
                              size: 14,
                              color: accent,
                            ),
                          ),
                        ),
                        // Delete button (only when editing existing)
                        if (widget.onDelete != null) ...[
                          const SizedBox(width: 4),
                          GestureDetector(
                            onTap: () {
                              if (_submitted) return;
                              _submitted = true;
                              HapticFeedback.mediumImpact();
                              widget.onDelete!();
                              _animController.reverse();
                            },
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.delete_outline_rounded,
                                size: 13,
                                color: Colors.red.withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 6),

              // ── Quick-pick suggestions ──
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0x990D0D14),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                        width: 0.5,
                      ),
                    ),
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 2,
                      children: _suggestions.map((label) {
                        return GestureDetector(
                          onTap: () => _doSubmit(label),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: accent.withValues(alpha: 0.2),
                                width: 0.5,
                              ),
                            ),
                            child: Text(
                              label,
                              style: TextStyle(
                                fontSize: 11,
                                color: accent.withValues(alpha: 0.85),
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.1,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 6),

              // ── Action buttons: Type + Bidirectional ──
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0x990D0D14),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                        width: 0.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Type cycling button
                        _ActionButton(
                          icon: _typeIcon(_currentType),
                          label: _typeLabel(_currentType),
                          color: _currentType == ConnectionType.contradiction
                              ? Colors.red
                              : accent,
                          onTap: () {
                            final values = ConnectionType.values;
                            final nextIdx = (values.indexOf(_currentType) + 1) % values.length;
                            setState(() => _currentType = values[nextIdx]);
                            widget.onTypeChanged?.call(_currentType);
                            HapticFeedback.selectionClick();
                          },
                        ),
                        const SizedBox(width: 8),
                        // Bidirectional toggle
                        _ActionButton(
                          icon: _currentBidirectional ? Icons.swap_horiz_rounded : Icons.arrow_forward_rounded,
                          label: _currentBidirectional ? 'Bidirezionale' : 'Unidirezionale',
                          color: _currentBidirectional ? accent : Colors.white54,
                          onTap: () {
                            setState(() => _currentBidirectional = !_currentBidirectional);
                            widget.onBidirectionalToggled?.call(_currentBidirectional);
                            HapticFeedback.selectionClick();
                          },
                        ),
                        const SizedBox(width: 8),
                        // 🎨 Style cycling button
                        _ActionButton(
                          icon: _styleIcon(_currentStyle),
                          label: _styleLabel(_currentStyle),
                          color: accent.withValues(alpha: 0.9),
                          onTap: () {
                            final values = ConnectionStyle.values;
                            final nextIdx = (values.indexOf(_currentStyle) + 1) % values.length;
                            setState(() => _currentStyle = values[nextIdx]);
                            widget.onStyleChanged?.call(_currentStyle);
                            HapticFeedback.selectionClick();
                          },
                        ),
                        // Multi-select toggle
                        if (widget.onMultiSelect != null) ...[
                          const SizedBox(width: 8),
                          _ActionButton(
                            icon: Icons.checklist_rounded,
                            label: 'Multi Select',
                            color: Colors.white70,
                            onTap: () {
                              widget.onMultiSelect?.call();
                              HapticFeedback.selectionClick();
                              _doSubmit(); // Dismiss overlay
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 6),

              // ── Color picker dots ──
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0x990D0D14),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                        width: 0.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: KnowledgeConnection.mindMapPalette.map((color) {
                        final isSelected = _colorEquals(color, _selectedColor);
                        return GestureDetector(
                          onTap: () {
                            setState(() => _selectedColor = color);
                            widget.onColorChanged?.call(color);
                            HapticFeedback.selectionClick();
                          },
                          child: Container(
                            width: 18,
                            height: 18,
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: isSelected
                                  ? Border.all(color: Colors.white, width: 2)
                                  : null,
                              boxShadow: [
                                BoxShadow(
                                  color: color.withValues(alpha: 0.4),
                                  blurRadius: isSelected ? 6 : 3,
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
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

/// Compare colors ignoring minor floating-point differences
bool _colorEquals(Color a, Color b) =>
    ((a.r - b.r) * 255).abs() < 2 &&
    ((a.g - b.g) * 255).abs() < 2 &&
    ((a.b - b.b) * 255).abs() < 2;

/// Icon for each connection type.
IconData _typeIcon(ConnectionType type) {
  switch (type) {
    case ConnectionType.association:
      return Icons.remove_rounded;
    case ConnectionType.causality:
      return Icons.bolt_rounded;
    case ConnectionType.hierarchy:
      return Icons.account_tree_rounded;
    case ConnectionType.contradiction:
      return Icons.close_rounded;
  }
}

/// Icon for each connection style.
IconData _styleIcon(ConnectionStyle style) {
  switch (style) {
    case ConnectionStyle.curved:
      return Icons.show_chart_rounded;
    case ConnectionStyle.straight:
      return Icons.horizontal_rule_rounded;
    case ConnectionStyle.zigzag:
      return Icons.ssid_chart_rounded;
    case ConnectionStyle.dashed:
      return Icons.more_horiz_rounded;
  }
}

/// Label for each connection style.
String _styleLabel(ConnectionStyle style) {
  switch (style) {
    case ConnectionStyle.curved:
      return 'Curva';
    case ConnectionStyle.straight:
      return 'Retta';
    case ConnectionStyle.zigzag:
      return 'Zigzag';
    case ConnectionStyle.dashed:
      return 'Tratteg.';
  }
}

/// Label for each connection type.
String _typeLabel(ConnectionType type) {
  switch (type) {
    case ConnectionType.association:
      return 'Associazione';
    case ConnectionType.causality:
      return 'Causalità';
    case ConnectionType.hierarchy:
      return 'Gerarchia';
    case ConnectionType.contradiction:
      return 'Contraddizione';
  }
}

/// Compact action button used in the connection context menu.
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: color.withValues(alpha: 0.25),
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: color.withValues(alpha: 0.9),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
