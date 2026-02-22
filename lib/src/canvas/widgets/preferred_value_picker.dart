/// 🎯 PREFERRED VALUE PICKER — Dropdown/nudge UI for constrained property values.
///
/// Provides a compact property editor that shows preferred values as chips,
/// with snap-to-nearest and arrow-key nudge support.
///
/// ```dart
/// PreferredValuePicker(
///   registry: preferredValueRegistry,
///   property: 'spacing',
///   currentValue: 12,
///   onValueChanged: (v) => setState(() => spacing = v),
/// )
/// ```
library;

import 'package:flutter/material.dart';

import '../../systems/preferred_values.dart';

/// Compact property editor with preferred value chips and nudge buttons.
class PreferredValuePicker extends StatelessWidget {
  /// The preferred value registry.
  final PreferredValueRegistry registry;

  /// The property name to look up values for.
  final String property;

  /// The current value.
  final double currentValue;

  /// Called when the value changes.
  final ValueChanged<double> onValueChanged;

  /// Label to display above the picker.
  final String? label;

  const PreferredValuePicker({
    super.key,
    required this.registry,
    required this.property,
    required this.currentValue,
    required this.onValueChanged,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final set = registry.forProperty(property);
    if (set == null) {
      return Text('No preferred values for $property');
    }

    final cs = Theme.of(context).colorScheme;
    final isPreferred = set.contains(currentValue);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              label!,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: cs.onSurface.withAlpha(180),
              ),
            ),
          ),
        // Current value row with nudge buttons.
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _NudgeButton(
              icon: Icons.remove,
              onPressed: () {
                final next = set.nudgeDown(currentValue);
                if (next != null) onValueChanged(next.value);
              },
            ),
            Container(
              constraints: const BoxConstraints(minWidth: 48),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isPreferred ? cs.primary.withAlpha(20) : cs.surface,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isPreferred ? cs.primary : cs.outline.withAlpha(60),
                ),
              ),
              child: Text(
                '${currentValue.toStringAsFixed(currentValue % 1 == 0 ? 0 : 1)}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isPreferred ? cs.primary : cs.onSurface,
                ),
              ),
            ),
            _NudgeButton(
              icon: Icons.add,
              onPressed: () {
                final next = set.nudgeUp(currentValue);
                if (next != null) onValueChanged(next.value);
              },
            ),
          ],
        ),
        const SizedBox(height: 6),
        // Value chips.
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children:
              set.values.map((v) {
                final isActive = v.value == currentValue;
                return GestureDetector(
                  onTap: () => onValueChanged(v.value),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: isActive ? cs.primary : cs.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isActive ? cs.primary : cs.outline.withAlpha(60),
                      ),
                    ),
                    child: Text(
                      v.label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight:
                            isActive ? FontWeight.w600 : FontWeight.w400,
                        color: isActive ? cs.onPrimary : cs.onSurface,
                      ),
                    ),
                  ),
                );
              }).toList(),
        ),
      ],
    );
  }
}

class _NudgeButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _NudgeButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 28,
      child: IconButton(
        padding: EdgeInsets.zero,
        iconSize: 14,
        icon: Icon(icon),
        onPressed: onPressed,
      ),
    );
  }
}
