import 'dart:async';

import 'cell_address.dart';
import 'cell_value.dart';
import 'spreadsheet_evaluator.dart';
import '../scene_graph/invalidation_graph.dart';
import '../nodes/latex_node.dart';

/// 📊 Reactive bridge connecting TabularNode cells to LatexNode rendering.
///
/// When a `LatexNode` contains cell references in its LaTeX source
/// (e.g. `\int_{0}^{{{A1}}} x^2 dx`), this bridge:
///
/// 1. Parses the template placeholders `{A1}`, `{B2}`, etc.
/// 2. Subscribes to the evaluator's cell change stream.
/// 3. On change: substitutes new values into the LaTeX source,
///    clears the LatexNode's cached layout, and marks it dirty
///    in the InvalidationGraph.
///
/// ## Usage
///
/// ```dart
/// final bridge = TabularLatexBridge(evaluator, invalidationGraph);
/// bridge.registerLatexNode(latexNode, 'tabular-1');
/// // When a referenced cell changes → latexNode.cachedLayout = null
/// bridge.dispose();
/// ```
class TabularLatexBridge {
  final SpreadsheetEvaluator _evaluator;
  final InvalidationGraph? _invalidationGraph;

  /// Active registrations: latexNodeId → _Registration.
  final Map<String, _Registration> _registrations = {};

  TabularLatexBridge(this._evaluator, [this._invalidationGraph]);

  /// Register a [LatexNode] whose source may contain cell reference
  /// placeholders like `{A1}`, `{B2}`.
  ///
  /// The [tabularNodeId] is used as a namespace prefix for
  /// invalidation graph tracking.
  void registerLatexNode(LatexNode node, String tabularNodeId) {
    // Unregister any previous registration.
    unregisterLatexNode(node.id.toString());

    // Parse the template to find cell references.
    final pattern = RegExp(r'\{([A-Z]+[0-9]+)\}');
    final template = node.latexSource;
    final matches = pattern.allMatches(template);

    if (matches.isEmpty) return; // No cell references to track.

    final cellAddresses = <CellAddress>{};
    for (final match in matches) {
      cellAddresses.add(CellAddress.fromLabel(match.group(1)!));
    }

    // Subscribe to changes.
    final subscription = _evaluator.onCellChanged
        .where((event) => cellAddresses.contains(event.address))
        .listen((event) {
          _onCellChanged(node, template, cellAddresses);
        });

    _registrations[node.id.toString()] = _Registration(
      node: node,
      template: template,
      addresses: cellAddresses,
      subscription: subscription,
      tabularNodeId: tabularNodeId,
    );

    // Perform initial substitution.
    _substituteValues(node, template, cellAddresses);
  }

  /// Unregister a previously registered LatexNode.
  void unregisterLatexNode(String latexNodeId) {
    final reg = _registrations.remove(latexNodeId);
    reg?.subscription.cancel();
  }

  /// Dispose all registrations and subscriptions.
  void dispose() {
    for (final reg in _registrations.values) {
      reg.subscription.cancel();
    }
    _registrations.clear();
  }

  /// Get all registered LaTeX node IDs.
  Set<String> get registeredNodeIds => _registrations.keys.toSet();

  /// Check if a LatexNode is registered.
  bool isRegistered(String latexNodeId) =>
      _registrations.containsKey(latexNodeId);

  // -------------------------------------------------------------------------
  // Internal
  // -------------------------------------------------------------------------

  void _onCellChanged(
    LatexNode node,
    String template,
    Set<CellAddress> addresses,
  ) {
    _substituteValues(node, template, addresses);

    // Mark dirty in the invalidation graph.
    _invalidationGraph?.markDirty(node.id.toString(), DirtyFlag.paint);
  }

  void _substituteValues(
    LatexNode node,
    String template,
    Set<CellAddress> addresses,
  ) {
    var result = template;
    for (final addr in addresses) {
      final value = _evaluator.getComputedValue(addr);
      final displayStr = value.displayString;
      result = result.replaceAll('{${addr.label}}', displayStr);
    }

    // Update the LaTeX source (this clears the cached layout automatically).
    node.latexSource = result;
  }
}

/// Internal registration data.
class _Registration {
  final LatexNode node;
  final String template;
  final Set<CellAddress> addresses;
  final StreamSubscription<CellChangeEvent> subscription;
  final String tabularNodeId;

  _Registration({
    required this.node,
    required this.template,
    required this.addresses,
    required this.subscription,
    required this.tabularNodeId,
  });
}
