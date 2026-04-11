import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 📝 Inline text editing overlay — appears directly on the canvas.
///
/// V2 improvements:
/// - Animated entrance (fade + scale)
/// - Subtle editing indicator (glowing underline)
/// - Multi-line with Shift+Enter support
/// - Cursor color matches text color
/// - Min-width placeholder for empty text
/// - Haptic feedback on submit
class InlineTextOverlay extends StatefulWidget {
  /// Initial text content (empty for new, pre-populated for edit).
  final String initialText;

  /// Text color.
  final Color color;

  /// Base font size (before canvas scale).
  final double fontSize;

  /// Font weight.
  final FontWeight fontWeight;

  /// Font style (normal or italic).
  final FontStyle fontStyle;

  /// Font family.
  final String? fontFamily;

  /// Canvas scale factor — applied to font size.
  final double canvasScale;

  /// Element scale factor.
  final double elementScale;

  /// Called when the user confirms the text (Enter or focus loss).
  final ValueChanged<String> onSubmit;

  /// Called when the user cancels (Escape or empty text).
  final VoidCallback onCancel;

  /// Called on every text change (for live preview / toolbar sync).
  final ValueChanged<String>? onTextChanged;

  /// 🎨 Called when text selection changes (for rich text style application).
  final ValueChanged<TextSelection>? onSelectionChanged;

  // ── Live effect properties ──
  final Shadow? shadow;
  final Color? backgroundColor;
  final Color? outlineColor;
  final double outlineWidth;
  final List<Color>? gradientColors;
  final double opacity;
  final double letterSpacing;
  final TextDecoration textDecoration;

  const InlineTextOverlay({
    super.key,
    this.initialText = '',
    this.color = Colors.black,
    this.fontSize = 24.0,
    this.fontWeight = FontWeight.normal,
    this.fontStyle = FontStyle.normal,
    this.fontFamily = 'Roboto',
    this.canvasScale = 1.0,
    this.elementScale = 1.0,
    required this.onSubmit,
    required this.onCancel,
    this.onTextChanged,
    this.onSelectionChanged,
    this.shadow,
    this.backgroundColor,
    this.outlineColor,
    this.outlineWidth = 0.0,
    this.gradientColors,
    this.opacity = 1.0,
    this.letterSpacing = 0.0,
    this.textDecoration = TextDecoration.none,
  });

  @override
  State<InlineTextOverlay> createState() => InlineTextOverlayState();
}

class InlineTextOverlayState extends State<InlineTextOverlay>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  late final AnimationController _entranceController;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;
  bool _submitted = false;
  bool _hasText = false;
  bool _focusLossSuppressed = false;

  /// Temporarily suppress focus-loss submit (e.g., when a dialog opens
  /// from the toolbar). Auto-resets after 500ms as a safety net.
  void suppressFocusLoss() {
    _focusLossSuppressed = true;
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _focusLossSuppressed = false;
    });
  }

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    _focusNode = FocusNode();
    _hasText = widget.initialText.isNotEmpty;

    // Entrance animation
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOut,
    );
    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.easeOutBack),
    );
    _entranceController.forward();

    // Auto-focus after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
        // 🎨 Track selection changes for rich text
        _controller.addListener(_onSelectionChange);
        _controller.selection = TextSelection.fromPosition(
          TextPosition(offset: _controller.text.length),
        );
      }
    });

    // Submit on focus loss (tap outside)
    _focusNode.addListener(_onFocusChange);

    _controller.addListener(() {
      widget.onTextChanged?.call(_controller.text);
      final hasText = _controller.text.isNotEmpty;
      if (hasText != _hasText) {
        setState(() => _hasText = hasText);
      }
    });
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus && !_submitted && mounted) {
      if (_focusLossSuppressed) {
        _focusLossSuppressed = false;
        // Re-request focus after dialog closes
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_submitted) _focusNode.requestFocus();
        });
        return;
      }
      _doSubmit();
    }
  }

  void _onSelectionChange() {
    widget.onSelectionChanged?.call(_controller.selection);
  }

  void _doSubmit() {
    if (_submitted) return;
    _submitted = true;
    final text = _controller.text.trim();
    if (text.isEmpty) {
      widget.onCancel();
    } else {
      HapticFeedback.lightImpact();
      widget.onSubmit(text);
    }
  }

  /// Public accessor for current text.
  String get currentText => _controller.text;

  /// Inserts [text] at the current cursor position (or replaces selection).
  /// Used by the Math symbol strip to inject symbols into the active field.
  void insertText(String text) {
    final sel = _controller.selection;
    final current = _controller.text;
    if (!sel.isValid) {
      // No valid selection — just append
      _controller.text = current + text;
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    } else {
      final newText = sel.textBefore(current) + text + sel.textAfter(current);
      _controller.value = _controller.value.copyWith(
        text: newText,
        selection: TextSelection.collapsed(offset: sel.start + text.length),
      );
    }
    _focusNode.requestFocus();
  }

  @override
  void didUpdateWidget(covariant InlineTextOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Controller text is preserved across rebuilds (style changes from toolbar)
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _focusNode.removeListener(_onFocusChange);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final effectiveFontSize =
        widget.fontSize * widget.elementScale * widget.canvasScale;

    final isLightColor = widget.color.computeLuminance() > 0.5;
    final indicatorColor =
        isLightColor
            ? widget.color.withValues(alpha: 0.4)
            : widget.color.withValues(alpha: 0.3);

    return FadeTransition(
      opacity: _fadeAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        alignment: Alignment.topLeft,
        child: KeyboardListener(
          focusNode: FocusNode(),
          onKeyEvent: (event) {
            if (event is KeyDownEvent) {
              if (event.logicalKey == LogicalKeyboardKey.escape) {
                _submitted = true;
                widget.onCancel();
              }
            }
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              IntrinsicWidth(
                child: Container(
                  constraints: BoxConstraints(
                    minWidth:
                        _hasText
                            ? 20
                            : (effectiveFontSize * 4).clamp(60.0, 200.0),
                  ),
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Opacity(
                    opacity: widget.opacity,
                    child: _wrapWithGradient(
                      _buildTextField(effectiveFontSize),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Container(
                height: 2,
                width:
                    _hasText
                        ? null
                        : (effectiveFontSize * 4).clamp(60.0, 200.0),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      indicatorColor,
                      widget.color.withValues(alpha: 0.08),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build the text field with proper effect-aware TextStyle.
  Widget _buildTextField(double effectiveFontSize) {
    // ⚠️ TextStyle: `color` and `foreground` are MUTUALLY EXCLUSIVE.
    final bool useOutline = widget.outlineColor != null;

    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      maxLines: null,
      minLines: 1,
      autofocus: true,
      style: TextStyle(
        fontSize: effectiveFontSize,
        color: useOutline ? null : widget.color,
        foreground:
            useOutline
                ? (Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = widget.outlineWidth
                  ..color = widget.outlineColor!)
                : null,
        fontWeight: widget.fontWeight,
        fontStyle: widget.fontStyle,
        fontFamily: widget.fontFamily,
        letterSpacing: widget.letterSpacing,
        decoration: widget.textDecoration,
        shadows: widget.shadow != null ? [widget.shadow!] : null,
        background:
            widget.backgroundColor != null
                ? (Paint()..color = widget.backgroundColor!)
                : null,
        height: 1.3,
      ),
      cursorColor: widget.color,
      cursorWidth: 2.5,
      cursorRadius: const Radius.circular(1),
      decoration: InputDecoration(
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        isDense: true,
        isCollapsed: true,
        hintText: _hasText ? null : 'Digita qui...',
        hintStyle: TextStyle(
          fontSize: effectiveFontSize,
          color: widget.color.withValues(alpha: 0.25),
          fontWeight: widget.fontWeight,
          fontStyle: widget.fontStyle,
          fontFamily: widget.fontFamily,
          height: 1.3,
        ),
      ),
      onSubmitted: (_) => _doSubmit(),
      textInputAction: TextInputAction.done,
    );
  }

  /// Wraps child in ShaderMask for gradient text effect.
  Widget _wrapWithGradient(Widget child) {
    if (widget.gradientColors == null || widget.gradientColors!.length < 2) {
      return child;
    }
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback:
          (bounds) => LinearGradient(
            colors: widget.gradientColors!,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(bounds),
      child: child,
    );
  }
}
