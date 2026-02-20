import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';

import './command_history.dart';
import '../tools/ruler/ruler_guide_system.dart';

// ---------------------------------------------------------------------------
// Guide Commands — Unified undo/redo with CommandHistory
// ---------------------------------------------------------------------------

/// Add a horizontal or vertical guide at a specific position.
class AddGuideCommand extends Command {
  final RulerGuideSystem guideSystem;
  final double position;
  final bool isHorizontal;
  final Color? color;

  AddGuideCommand({
    required this.guideSystem,
    required this.position,
    required this.isHorizontal,
    this.color,
  }) : super(label: isHorizontal ? 'Add H Guide' : 'Add V Guide');

  @override
  void execute() {
    if (isHorizontal) {
      guideSystem.addHorizontalGuide(position, color: color);
    } else {
      guideSystem.addVerticalGuide(position, color: color);
    }
  }

  @override
  void undo() {
    final guides =
        isHorizontal
            ? guideSystem.horizontalGuides
            : guideSystem.verticalGuides;
    final idx = guides.lastIndexOf(position);
    if (idx >= 0) {
      if (isHorizontal) {
        guideSystem.removeHorizontalGuideAt(idx);
      } else {
        guideSystem.removeVerticalGuideAt(idx);
      }
    }
  }
}

/// Remove a guide at a specific index. Stores full state for undo.
class RemoveGuideCommand extends Command {
  final RulerGuideSystem guideSystem;
  final bool isHorizontal;
  final int index;

  // Snapshot for undo
  late final double _position;
  late final bool _locked;
  late final Color? _color;
  late final String? _label;

  RemoveGuideCommand({
    required this.guideSystem,
    required this.isHorizontal,
    required this.index,
  }) : super(label: isHorizontal ? 'Remove H Guide' : 'Remove V Guide') {
    final guides =
        isHorizontal
            ? guideSystem.horizontalGuides
            : guideSystem.verticalGuides;
    final locked =
        isHorizontal
            ? guideSystem.horizontalLocked
            : guideSystem.verticalLocked;
    final colors =
        isHorizontal
            ? guideSystem.horizontalColors
            : guideSystem.verticalColors;
    final labels =
        isHorizontal
            ? guideSystem.horizontalLabels
            : guideSystem.verticalLabels;

    _position = index < guides.length ? guides[index] : 0;
    _locked = index < locked.length ? locked[index] : false;
    _color = index < colors.length ? colors[index] : null;
    _label = index < labels.length ? labels[index] : null;
  }

  @override
  void execute() {
    if (isHorizontal) {
      guideSystem.removeHorizontalGuideAt(index);
    } else {
      guideSystem.removeVerticalGuideAt(index);
    }
  }

  @override
  void undo() {
    if (isHorizontal) {
      guideSystem.addHorizontalGuide(_position, color: _color);
      if (_locked) {
        final idx = guideSystem.horizontalGuides.length - 1;
        if (idx < guideSystem.horizontalLocked.length) {
          guideSystem.horizontalLocked[idx] = true;
        }
      }
      if (_label != null) {
        guideSystem.setGuideLabel(
          true,
          guideSystem.horizontalGuides.length - 1,
          _label,
        );
      }
    } else {
      guideSystem.addVerticalGuide(_position, color: _color);
      if (_locked) {
        final idx = guideSystem.verticalGuides.length - 1;
        if (idx < guideSystem.verticalLocked.length) {
          guideSystem.verticalLocked[idx] = true;
        }
      }
      if (_label != null) {
        guideSystem.setGuideLabel(
          false,
          guideSystem.verticalGuides.length - 1,
          _label,
        );
      }
    }
  }
}

/// Move a guide to a new position. Supports drag coalescing via merge.
class MoveGuideCommand extends Command {
  final RulerGuideSystem guideSystem;
  final bool isHorizontal;
  final int index;
  final double _oldPosition;
  double _newPosition;

  MoveGuideCommand({
    required this.guideSystem,
    required this.isHorizontal,
    required this.index,
    required double newPosition,
  }) : _oldPosition =
           (isHorizontal
               ? guideSystem.horizontalGuides
               : guideSystem.verticalGuides)[index],
       _newPosition = newPosition,
       super(label: 'Move Guide');

  @override
  void execute() {
    final guides =
        isHorizontal
            ? guideSystem.horizontalGuides
            : guideSystem.verticalGuides;
    if (index < guides.length) {
      guides[index] = _newPosition;
      guideSystem.enforceSpacingLocks(isHorizontal, index);
    }
    guideSystem.notifyListeners();
  }

  @override
  void undo() {
    final guides =
        isHorizontal
            ? guideSystem.horizontalGuides
            : guideSystem.verticalGuides;
    if (index < guides.length) {
      guides[index] = _oldPosition;
      guideSystem.enforceSpacingLocks(isHorizontal, index);
    }
    guideSystem.notifyListeners();
  }

  @override
  bool canMergeWith(Command other) {
    if (other is MoveGuideCommand) {
      return other.guideSystem == guideSystem &&
          other.isHorizontal == isHorizontal &&
          other.index == index;
    }
    return false;
  }

  @override
  void mergeWith(Command other) {
    if (other is MoveGuideCommand) {
      _newPosition = other._newPosition;
    }
  }
}

/// Set a guide property (color, label, or lock state).
class SetGuidePropertyCommand extends Command {
  final RulerGuideSystem guideSystem;
  final bool isHorizontal;
  final int index;
  final _GuidePropertyType propertyType;
  final dynamic _oldValue;
  final dynamic _newValue;

  SetGuidePropertyCommand.color({
    required this.guideSystem,
    required this.isHorizontal,
    required this.index,
    required Color? newColor,
  }) : propertyType = _GuidePropertyType.color,
       _oldValue =
           (isHorizontal
               ? guideSystem.horizontalColors
               : guideSystem.verticalColors)[index],
       _newValue = newColor,
       super(label: 'Set Guide Color');

  SetGuidePropertyCommand.label({
    required this.guideSystem,
    required this.isHorizontal,
    required this.index,
    required String? newLabel,
  }) : propertyType = _GuidePropertyType.label,
       _oldValue = guideSystem.getGuideLabel(isHorizontal, index),
       _newValue = newLabel,
       super(label: 'Set Guide Label');

  SetGuidePropertyCommand.locked({
    required this.guideSystem,
    required this.isHorizontal,
    required this.index,
  }) : propertyType = _GuidePropertyType.locked,
       _oldValue = guideSystem.isLocked(isHorizontal, index),
       _newValue = !guideSystem.isLocked(isHorizontal, index),
       super(label: 'Toggle Guide Lock');

  @override
  void execute() => _apply(_newValue);

  @override
  void undo() => _apply(_oldValue);

  void _apply(dynamic value) {
    switch (propertyType) {
      case _GuidePropertyType.color:
        guideSystem.setGuideColor(isHorizontal, index, value as Color?);
      case _GuidePropertyType.label:
        guideSystem.setGuideLabel(isHorizontal, index, value as String?);
      case _GuidePropertyType.locked:
        final locked =
            isHorizontal
                ? guideSystem.horizontalLocked
                : guideSystem.verticalLocked;
        if (index < locked.length) {
          locked[index] = value as bool;
        }
        guideSystem.notifyListeners();
    }
  }
}

enum _GuidePropertyType { color, label, locked }

/// Clear all guides. Stores full snapshot for undo.
class ClearAllGuidesCommand extends Command {
  final RulerGuideSystem guideSystem;
  late final Map<String, dynamic> _snapshot;

  ClearAllGuidesCommand({required this.guideSystem})
    : super(label: 'Clear All Guides') {
    // Deep-copy via JSON round-trip to avoid mutable list references
    _snapshot =
        jsonDecode(jsonEncode(guideSystem.toJson())) as Map<String, dynamic>;
  }

  @override
  void execute() {
    guideSystem.clearAllGuides();
  }

  @override
  void undo() {
    guideSystem.loadFromJson(_snapshot);
  }
}

/// Add an angular guide.
class AddAngularGuideCommand extends Command {
  final RulerGuideSystem guideSystem;
  final Offset origin;
  final double angleDeg;
  final Color? color;
  int? _addedIndex;

  AddAngularGuideCommand({
    required this.guideSystem,
    required this.origin,
    required this.angleDeg,
    this.color,
  }) : super(label: 'Add Angular Guide');

  @override
  void execute() {
    guideSystem.addAngularGuide(origin, angleDeg, color: color);
    _addedIndex = guideSystem.angularGuides.length - 1;
  }

  @override
  void undo() {
    if (_addedIndex != null &&
        _addedIndex! < guideSystem.angularGuides.length) {
      guideSystem.removeAngularGuideAt(_addedIndex!);
    }
  }
}
