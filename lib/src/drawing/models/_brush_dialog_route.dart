part of 'pro_brush_settings_dialog.dart';

// ════════════════════════════════════════════════════════════════════
//  CUSTOM POPUP ROUTE — positions card near anchor
// ════════════════════════════════════════════════════════════════════

class _BrushPopupRoute extends PopupRoute<void> {
  final Rect? anchorRect;
  final ProBrushSettings brushSettings;
  final ProPenType currentBrush;
  final Function(ProBrushSettings) onSettingsChanged;
  final Color? currentColor;
  final double? currentWidth;

  _BrushPopupRoute({
    required this.anchorRect,
    required this.brushSettings,
    required this.currentBrush,
    required this.onSettingsChanged,
    this.currentColor,
    this.currentWidth,
  });

  @override
  Color? get barrierColor => Colors.black26;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => 'Dismiss brush settings';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 200);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.92, end: 1.0).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        ),
        alignment: _scaleAlignment(context),
        child: child,
      ),
    );
  }

  Alignment _scaleAlignment(BuildContext context) {
    if (anchorRect == null) return Alignment.center;
    final size = MediaQuery.of(context).size;
    final cx = anchorRect!.center.dx / size.width * 2 - 1;
    final cy = anchorRect!.center.dy / size.height * 2 - 1;
    return Alignment(cx.clamp(-1.0, 1.0), cy.clamp(-1.0, 1.0));
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return _BrushPopupLayout(
      anchorRect: anchorRect,
      child: ProBrushSettingsDialog(
        settings: brushSettings,
        currentBrush: currentBrush,
        onSettingsChanged: onSettingsChanged,
        currentColor: currentColor,
        currentWidth: currentWidth,
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  LAYOUT — positions the card relative to anchor
// ════════════════════════════════════════════════════════════════════

class _BrushPopupLayout extends StatelessWidget {
  final Rect? anchorRect;
  final Widget child;

  const _BrushPopupLayout({required this.anchorRect, required this.child});

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final screenSize = mq.size;
    final padding = mq.padding;

    const popupWidth = 300.0;
    const popupMaxHeight = 420.0;
    const margin = 12.0;

    if (anchorRect == null) {
      // Fallback: center on screen
      return Align(
        alignment: const Alignment(0, -0.2),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: popupWidth,
            maxHeight: popupMaxHeight,
          ),
          child: child,
        ),
      );
    }

    // Calculate position: try above anchor, then below
    final anchor = anchorRect!;
    final spaceAbove = anchor.top - padding.top - margin;
    final spaceBelow =
        screenSize.height - anchor.bottom - padding.bottom - margin;

    final showAbove =
        spaceAbove >= popupMaxHeight * 0.5 || spaceAbove > spaceBelow;
    final availableHeight =
        showAbove
            ? spaceAbove.clamp(100.0, popupMaxHeight)
            : spaceBelow.clamp(100.0, popupMaxHeight);

    // Horizontal: center on anchor, but clamp to screen
    double left = anchor.center.dx - popupWidth / 2;
    left = left.clamp(margin, screenSize.width - popupWidth - margin);

    double top;
    if (showAbove) {
      top = anchor.top - availableHeight - 8;
    } else {
      top = anchor.bottom + 8;
    }
    top = top.clamp(
      padding.top + margin,
      screenSize.height - availableHeight - padding.bottom - margin,
    );

    return Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          width: popupWidth,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: availableHeight),
            child: child,
          ),
        ),
      ],
    );
  }
}
