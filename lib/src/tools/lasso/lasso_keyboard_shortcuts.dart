import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'lasso_tool.dart';

/// Keyboard shortcut handler for lasso selection operations.
///
/// Wraps a child widget with a [Focus] node that intercepts key events
/// and dispatches them to the [LassoTool].
///
/// Shortcuts:
/// - Ctrl+C: Copy
/// - Ctrl+V: Paste
/// - Ctrl+D: Duplicate
/// - Ctrl+A: Select All
/// - Ctrl+G: Group
/// - Ctrl+Shift+G: Ungroup
/// - Ctrl+Z: Undo
/// - Delete/Backspace: Delete selected
/// - Ctrl+]: Bring to Front
/// - Ctrl+[: Send to Back
/// - Ctrl+Shift+S: Toggle Snap
class LassoKeyboardShortcuts extends StatelessWidget {
  final LassoTool lassoTool;
  final Widget child;

  /// Called after any shortcut triggers a state change.
  final VoidCallback? onStateChanged;

  /// Called when delete is triggered.
  final VoidCallback? onDelete;

  const LassoKeyboardShortcuts({
    super.key,
    required this.lassoTool,
    required this.child,
    this.onStateChanged,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(autofocus: false, onKeyEvent: _handleKeyEvent, child: child);
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final isCtrl =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;

    if (!lassoTool.hasSelection && !isCtrl) {
      return KeyEventResult.ignored;
    }

    // Ctrl+C: Copy
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyC) {
      lassoTool.copySelected();
      HapticFeedback.lightImpact();
      return KeyEventResult.handled;
    }

    // Ctrl+V: Paste
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyV) {
      if (lassoTool.hasClipboard) {
        lassoTool.pasteFromClipboard();
        onStateChanged?.call();
        HapticFeedback.lightImpact();
        return KeyEventResult.handled;
      }
    }

    // Ctrl+D: Duplicate
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyD) {
      lassoTool.duplicateSelected();
      onStateChanged?.call();
      HapticFeedback.lightImpact();
      return KeyEventResult.handled;
    }

    // Ctrl+A: Select All
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyA) {
      lassoTool.selectAll();
      onStateChanged?.call();
      HapticFeedback.lightImpact();
      return KeyEventResult.handled;
    }

    // Ctrl+G / Ctrl+Shift+G: Group / Ungroup
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyG) {
      if (isShift) {
        lassoTool.ungroupSelected();
      } else {
        lassoTool.groupSelected();
      }
      onStateChanged?.call();
      HapticFeedback.mediumImpact();
      return KeyEventResult.handled;
    }

    // Ctrl+Z: Undo
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyZ) {
      lassoTool.restoreUndo();
      onStateChanged?.call();
      HapticFeedback.mediumImpact();
      return KeyEventResult.handled;
    }

    // Ctrl+]: Bring to Front
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.bracketRight) {
      lassoTool.bringToFront();
      onStateChanged?.call();
      HapticFeedback.lightImpact();
      return KeyEventResult.handled;
    }

    // Ctrl+[: Send to Back
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.bracketLeft) {
      lassoTool.sendToBack();
      onStateChanged?.call();
      HapticFeedback.lightImpact();
      return KeyEventResult.handled;
    }

    // Ctrl+Shift+S: Toggle Snap
    if (isCtrl && isShift && event.logicalKey == LogicalKeyboardKey.keyS) {
      lassoTool.toggleSnap();
      onStateChanged?.call();
      HapticFeedback.lightImpact();
      return KeyEventResult.handled;
    }

    // Delete / Backspace: Delete selected
    if (event.logicalKey == LogicalKeyboardKey.delete ||
        event.logicalKey == LogicalKeyboardKey.backspace) {
      if (lassoTool.hasSelection) {
        onDelete?.call();
        HapticFeedback.mediumImpact();
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }
}
