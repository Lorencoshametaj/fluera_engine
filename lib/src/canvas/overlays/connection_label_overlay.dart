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

  const ConnectionLabelOverlay({
    super.key,
    this.initialText = '',
    this.accentColor = const Color(0xFF64B5F6),
    required this.onSubmit,
    required this.onDismiss,
    this.onDelete,
    this.onColorChanged,
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
    (a.red - b.red).abs() < 2 &&
    (a.green - b.green).abs() < 2 &&
    (a.blue - b.blue).abs() < 2;
