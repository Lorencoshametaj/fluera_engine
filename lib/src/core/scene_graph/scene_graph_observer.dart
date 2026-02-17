import 'dart:async';
import './canvas_node.dart';

// ---------------------------------------------------------------------------
// Scene Graph Events
// ---------------------------------------------------------------------------

/// Base class for all scene graph events.
abstract class SceneGraphEvent {
  /// Timestamp when the event was created.
  final DateTime timestamp = DateTime.now();
}

/// A node was added to the tree.
class NodeAddedEvent extends SceneGraphEvent {
  final CanvasNode node;
  final String parentId;
  NodeAddedEvent(this.node, this.parentId);
}

/// A node was removed from the tree.
class NodeRemovedEvent extends SceneGraphEvent {
  final CanvasNode node;
  final String parentId;
  NodeRemovedEvent(this.node, this.parentId);
}

/// A node's properties changed.
class NodeChangedEvent extends SceneGraphEvent {
  final CanvasNode node;
  final String property;
  NodeChangedEvent(this.node, this.property);
}

/// Children were reordered within a group.
class NodeReorderedEvent extends SceneGraphEvent {
  final String parentId;
  final int oldIndex;
  final int newIndex;
  NodeReorderedEvent(this.parentId, this.oldIndex, this.newIndex);
}

// ---------------------------------------------------------------------------
// Observer interface
// ---------------------------------------------------------------------------

/// Observer interface for scene graph structural changes.
///
/// Implement this to react to additions, removals, property changes,
/// and reorderings in the scene graph.
///
/// ```dart
/// class UndoTracker implements SceneGraphObserver {
///   @override
///   void onNodeAdded(CanvasNode node, String parentId) {
///     recordCommand(AddNodeCommand(node, parentId));
///   }
///   // ...
/// }
/// ```
abstract class SceneGraphObserver {
  /// Called when a node is added to the tree.
  void onNodeAdded(CanvasNode node, String parentId) {}

  /// Called when a node is removed from the tree.
  void onNodeRemoved(CanvasNode node, String parentId) {}

  /// Called when a node's property changes.
  void onNodeChanged(CanvasNode node, String property) {}

  /// Called when children are reordered.
  void onNodeReordered(String parentId, int oldIndex, int newIndex) {}
}

// ---------------------------------------------------------------------------
// Observer manager mixin
// ---------------------------------------------------------------------------

/// Mixin providing observer management and event stream capabilities.
///
/// Applied to [SceneGraph] to centralize notification dispatch.
mixin SceneGraphObservable {
  final List<SceneGraphObserver> _observers = [];
  final StreamController<SceneGraphEvent> _eventController =
      StreamController<SceneGraphEvent>.broadcast();

  /// Stream of all scene graph events (reactive alternative to observers).
  Stream<SceneGraphEvent> get events => _eventController.stream;

  /// Register an observer.
  void addObserver(SceneGraphObserver observer) => _observers.add(observer);

  /// Remove a previously registered observer.
  void removeObserver(SceneGraphObserver observer) =>
      _observers.remove(observer);

  /// Notify all observers that a node was added.
  void notifyNodeAdded(CanvasNode node, String parentId) {
    for (final o in _observers) {
      o.onNodeAdded(node, parentId);
    }
    _eventController.add(NodeAddedEvent(node, parentId));
  }

  /// Notify all observers that a node was removed.
  void notifyNodeRemoved(CanvasNode node, String parentId) {
    for (final o in _observers) {
      o.onNodeRemoved(node, parentId);
    }
    _eventController.add(NodeRemovedEvent(node, parentId));
  }

  /// Notify all observers that a node's property changed.
  void notifyNodeChanged(CanvasNode node, String property) {
    for (final o in _observers) {
      o.onNodeChanged(node, property);
    }
    _eventController.add(NodeChangedEvent(node, property));
  }

  /// Notify all observers that children were reordered.
  void notifyNodeReordered(String parentId, int oldIndex, int newIndex) {
    for (final o in _observers) {
      o.onNodeReordered(parentId, oldIndex, newIndex);
    }
    _eventController.add(NodeReorderedEvent(parentId, oldIndex, newIndex));
  }

  /// Close the event stream and clear observers.
  void disposeObservable() {
    _eventController.close();
    _observers.clear();
  }
}
