import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../l10n/nebula_localizations.dart';
import './compact_action_button.dart';

/// Menu azioni per la selezione del lasso (with animation)
class SelectionActionsMenu extends StatefulWidget {
  final int selectionCount;
  final VoidCallback onDelete;
  final VoidCallback onClearSelection;
  final VoidCallback onRotate;
  final VoidCallback onFlipHorizontal;
  final VoidCallback onFlipVertical;
  final VoidCallback onConvertToText;

  const SelectionActionsMenu({
    super.key,
    required this.selectionCount,
    required this.onDelete,
    required this.onClearSelection,
    required this.onRotate,
    required this.onFlipHorizontal,
    required this.onFlipVertical,
    required this.onConvertToText,
  });

  @override
  State<SelectionActionsMenu> createState() => _SelectionActionsMenuState();
}

class _SelectionActionsMenuState extends State<SelectionActionsMenu>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.elasticOut,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Info selezione compatta
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_circle_rounded,
                        color: Colors.blue,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${widget.selectionCount}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),

                // Azioni compatte
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Pulsante Ruota
                          CompactActionButton(
                            icon: Icons.rotate_90_degrees_ccw_rounded,
                            color: Colors.blue,
                            tooltip: 'Ruota',
                            onTap: () {
                              HapticFeedback.lightImpact();
                              widget.onRotate();
                            },
                          ),

                          // Pulsante Flip Orizzontale
                          CompactActionButton(
                            icon: Icons.flip,
                            color: Colors.orange,
                            tooltip:
                                NebulaLocalizations.of(
                                  context,
                                ).proCanvas_flipHorizontal,
                            onTap: () {
                              HapticFeedback.lightImpact();
                              widget.onFlipHorizontal();
                            },
                          ),

                          // Pulsante Flip Verticale
                          CompactActionButton(
                            icon: Icons.flip,
                            color: Colors.teal,
                            tooltip:
                                NebulaLocalizations.of(
                                  context,
                                ).proCanvas_flipVertical,
                            rotation: 90,
                            onTap: () {
                              HapticFeedback.lightImpact();
                              widget.onFlipVertical();
                            },
                          ),

                          // Pulsante OCR - Converti in testo
                          CompactActionButton(
                            icon: Icons.text_fields_rounded,
                            color: Colors.deepPurple,
                            tooltip:
                                NebulaLocalizations.of(
                                  context,
                                ).proCanvas_convertToText,
                            onTap: () {
                              HapticFeedback.lightImpact();
                              widget.onConvertToText();
                            },
                          ),

                          // Pulsante Elimina
                          CompactActionButton(
                            icon: Icons.delete_rounded,
                            color: Colors.red,
                            tooltip:
                                NebulaLocalizations.of(
                                  context,
                                ).proCanvas_delete,
                            onTap: () {
                              HapticFeedback.mediumImpact();
                              widget.onDelete();
                            },
                          ),

                          // Pulsante Chiudi
                          CompactActionButton(
                            icon: Icons.close_rounded,
                            color: Colors.grey.shade700,
                            tooltip:
                                NebulaLocalizations.of(context).proCanvas_close,
                            onTap: () {
                              HapticFeedback.lightImpact();
                              widget.onClearSelection();
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
