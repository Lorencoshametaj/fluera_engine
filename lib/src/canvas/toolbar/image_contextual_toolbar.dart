import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/models/image_element.dart';

// =============================================================================
// 🖼️ IMAGE CONTEXTUAL TOOLBAR — Popup with quick actions for selected images
// =============================================================================

/// Shows the image actions popup anchored below [anchor].
///
/// Matches the MD3 design of [showPdfPagePopup] — same border radius,
/// elevation, and interaction patterns.
void showImageActionsPopup({
  required BuildContext context,
  required Rect anchor,
  required ImageElement image,
  VoidCallback? onEdit,
  VoidCallback? onCrop,
  VoidCallback? onAdjust,
  VoidCallback? onFlipH,
  VoidCallback? onFlipV,
  VoidCallback? onDuplicate,
  VoidCallback? onDelete,
}) {
  showMenu<void>(
    context: context,
    position: RelativeRect.fromLTRB(
      anchor.left,
      anchor.bottom + 4,
      anchor.right,
      0,
    ),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    elevation: 8,
    constraints: const BoxConstraints(minWidth: 260, maxWidth: 300),
    items: [
      _ImagePopupHeader(fileName: image.imagePath.split('/').last),
      _ImagePopupDivider(),
      _ImageQuickActions(onEdit: onEdit, onCrop: onCrop, onAdjust: onAdjust),
      _ImagePopupDivider(),
      _ImageTransformActions(
        flipH: image.flipHorizontal,
        flipV: image.flipVertical,
        onFlipH: onFlipH,
        onFlipV: onFlipV,
        onDuplicate: onDuplicate,
      ),
      if (onDelete != null) ...[
        _ImagePopupDivider(),
        _ImageDeleteAction(onDelete: onDelete),
      ],
    ],
  );
}

// =============================================================================
// 🖼️ Header
// =============================================================================

class _ImagePopupHeader extends PopupMenuEntry<void> {
  final String fileName;
  const _ImagePopupHeader({required this.fileName});

  @override
  double get height => 40;
  @override
  bool represents(void value) => false;
  @override
  State<_ImagePopupHeader> createState() => _ImagePopupHeaderState();
}

class _ImagePopupHeaderState extends State<_ImagePopupHeader> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.image_rounded, size: 18, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.fileName,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Divider
// =============================================================================

class _ImagePopupDivider extends PopupMenuEntry<void> {
  @override
  double get height => 1;
  @override
  bool represents(void value) => false;
  @override
  State<_ImagePopupDivider> createState() => _ImagePopupDividerState();
}

class _ImagePopupDividerState extends State<_ImagePopupDivider> {
  @override
  Widget build(BuildContext context) => const Divider(height: 1);
}

// =============================================================================
// 🎨 Quick Actions — Edit, Crop, Adjust
// =============================================================================

class _ImageQuickActions extends PopupMenuEntry<void> {
  final VoidCallback? onEdit;
  final VoidCallback? onCrop;
  final VoidCallback? onAdjust;

  const _ImageQuickActions({this.onEdit, this.onCrop, this.onAdjust});

  @override
  double get height => 44;
  @override
  bool represents(void value) => false;
  @override
  State<_ImageQuickActions> createState() => _ImageQuickActionsState();
}

class _ImageQuickActionsState extends State<_ImageQuickActions> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          if (widget.onEdit != null)
            _actionBtn(Icons.edit_rounded, 'Edit', cs, () {
              HapticFeedback.mediumImpact();
              Navigator.pop(context);
              widget.onEdit!();
            }),
          if (widget.onCrop != null)
            _actionBtn(Icons.crop_rounded, 'Crop', cs, () {
              HapticFeedback.mediumImpact();
              Navigator.pop(context);
              widget.onCrop!();
            }),
          if (widget.onAdjust != null)
            _actionBtn(Icons.tune_rounded, 'Adjust', cs, () {
              HapticFeedback.mediumImpact();
              Navigator.pop(context);
              widget.onAdjust!();
            }),
        ],
      ),
    );
  }

  Widget _actionBtn(
    IconData icon,
    String label,
    ColorScheme cs,
    VoidCallback onTap,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// 🔄 Transform Actions — Flip H/V, Duplicate
// =============================================================================

class _ImageTransformActions extends PopupMenuEntry<void> {
  final bool flipH;
  final bool flipV;
  final VoidCallback? onFlipH;
  final VoidCallback? onFlipV;
  final VoidCallback? onDuplicate;

  const _ImageTransformActions({
    this.flipH = false,
    this.flipV = false,
    this.onFlipH,
    this.onFlipV,
    this.onDuplicate,
  });

  @override
  double get height => 44;
  @override
  bool represents(void value) => false;
  @override
  State<_ImageTransformActions> createState() => _ImageTransformActionsState();
}

class _ImageTransformActionsState extends State<_ImageTransformActions> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          if (widget.onFlipH != null)
            _transformBtn(
              Icons.flip_rounded,
              'Flip H',
              cs,
              isActive: widget.flipH,
              onTap: () {
                HapticFeedback.mediumImpact();
                widget.onFlipH!();
                Navigator.pop(context);
              },
            ),
          if (widget.onFlipV != null)
            _transformBtn(
              Icons.flip_rounded,
              'Flip V',
              cs,
              rotate: true,
              isActive: widget.flipV,
              onTap: () {
                HapticFeedback.mediumImpact();
                widget.onFlipV!();
                Navigator.pop(context);
              },
            ),
          if (widget.onDuplicate != null)
            _transformBtn(
              Icons.copy_rounded,
              'Duplicate',
              cs,
              onTap: () {
                HapticFeedback.mediumImpact();
                widget.onDuplicate!();
                Navigator.pop(context);
              },
            ),
        ],
      ),
    );
  }

  Widget _transformBtn(
    IconData icon,
    String label,
    ColorScheme cs, {
    bool isActive = false,
    bool rotate = false,
    required VoidCallback onTap,
  }) {
    final color = isActive ? cs.primary : cs.onSurfaceVariant;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Transform.rotate(
                angle: rotate ? 1.5708 : 0, // 90° for vertical flip icon
                child: Icon(icon, size: 16, color: color),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: color,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// 🗑️ Delete Action
// =============================================================================

class _ImageDeleteAction extends PopupMenuEntry<void> {
  final VoidCallback onDelete;
  const _ImageDeleteAction({required this.onDelete});

  @override
  double get height => 48;
  @override
  bool represents(void value) => false;
  @override
  State<_ImageDeleteAction> createState() => _ImageDeleteActionState();
}

class _ImageDeleteActionState extends State<_ImageDeleteAction> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () {
        Navigator.of(context).pop(); // Close popup first
        widget.onDelete();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.delete_forever_rounded, color: cs.error, size: 20),
            const SizedBox(width: 12),
            Text(
              'Delete Image',
              style: TextStyle(
                color: cs.error,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
